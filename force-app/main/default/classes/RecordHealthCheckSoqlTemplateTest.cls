/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Unit tests for RecordHealthCheckSoqlTemplate — the depth-aware SOQL normalizer.
 * Pure string logic, so no DML/SOQL is needed. Focuses on the RB-08 cases the old
 * substring/regex logic got wrong: clauses inside subqueries, keywords inside
 * string literals, and oversized/childed LIMITs.
 */
@isTest
private class RecordHealthCheckSoqlTemplateTest {
  // ─── maskStringLiterals / depthAt ──────────────────────────────────────────

  @isTest
  static void maskBlanksLiteralContentsAndPreservesLength() {
    String input = 'A = \'xy\' B';
    String masked = RecordHealthCheckSoqlTemplate.maskStringLiterals(input);
    System.assertEquals(input.length(), masked.length(), 'Length preserved.');
    System.assertEquals(
      'A = \'  \' B',
      masked,
      'Literal contents blanked, quotes kept.'
    );
  }

  @isTest
  static void depthAtTracksParentheses() {
    String masked = 'SELECT Id, (SELECT Id) FROM A';
    System.assertEquals(
      0,
      RecordHealthCheckSoqlTemplate.depthAt(masked, 0),
      'Outer position is depth 0.'
    );
    Integer innerSelect = masked.indexOf('SELECT', 5);
    System.assertEquals(
      1,
      RecordHealthCheckSoqlTemplate.depthAt(masked, innerSelect),
      'Position inside the subquery is depth 1.'
    );
  }

  // ─── assertSingleOuterSelect ───────────────────────────────────────────────

  @isTest
  static void singleOuterSelectWithSubqueryIsValid() {
    // Inner SELECT is at depth 1, so this is a single outer SELECT — no exception.
    RecordHealthCheckSoqlTemplate.assertSingleOuterSelect(
      'SELECT Id, (SELECT Id FROM Contacts) FROM Account'
    );
  }

  @isTest
  static void multipleOuterSelectsRejected() {
    try {
      RecordHealthCheckSoqlTemplate.assertSingleOuterSelect(
        'SELECT Id FROM A SELECT Id FROM B'
      );
      System.assert(false, 'Expected TemplateException for two outer SELECTs.');
    } catch (RecordHealthCheckSoqlTemplate.TemplateException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
  }

  // ─── rewriteBareCount ──────────────────────────────────────────────────────

  @isTest
  static void bareCountRewrittenToCountId() {
    System.assertEquals(
      'SELECT COUNT(Id) FROM Contact',
      RecordHealthCheckSoqlTemplate.rewriteBareCount(
        'SELECT COUNT() FROM Contact'
      )
    );
  }

  // ─── enforceRowCap ─────────────────────────────────────────────────────────

  @isTest
  static void plainQueryGetsCap() {
    String out = RecordHealthCheckSoqlTemplate.enforceRowCap(
      'SELECT Id FROM Account',
      2000
    );
    System.assert(out.toUpperCase().endsWith('LIMIT 2000'), out);
  }

  @isTest
  static void oversizedOuterLimitIsLowered() {
    String out = RecordHealthCheckSoqlTemplate.enforceRowCap(
      'SELECT Id FROM Account LIMIT 50000',
      2000
    );
    System.assert(out.contains('LIMIT 2000'), out);
    System.assert(!out.contains('50000'), 'Oversized limit must be lowered.');
  }

  @isTest
  static void smallExistingLimitUntouched() {
    String out = RecordHealthCheckSoqlTemplate.enforceRowCap(
      'SELECT Id FROM Account LIMIT 10',
      2000
    );
    System.assertEquals('SELECT Id FROM Account LIMIT 10', out);
  }

  @isTest
  static void childSubqueryLimitDoesNotCountAsOuterCap() {
    String out = RecordHealthCheckSoqlTemplate.enforceRowCap(
      'SELECT Id, (SELECT Id FROM Contacts LIMIT 5) FROM Account',
      2000
    );
    System.assert(out.contains('LIMIT 5)'), 'Inner LIMIT preserved.');
    System.assert(out.toUpperCase().endsWith('LIMIT 2000'), 'Outer cap added.');
  }

  @isTest
  static void pureAggregateGetsNoLimit() {
    String out = RecordHealthCheckSoqlTemplate.enforceRowCap(
      'SELECT COUNT(Id) FROM Contact WHERE AccountId = \'001\'',
      2000
    );
    System.assert(
      !out.toUpperCase().contains('LIMIT'),
      'Pure aggregate must not get LIMIT.'
    );
  }

  @isTest
  static void groupByGetsCap() {
    String out = RecordHealthCheckSoqlTemplate.enforceRowCap(
      'SELECT AccountId, COUNT(Id) FROM Contact GROUP BY AccountId',
      2000
    );
    System.assert(out.toUpperCase().contains('LIMIT 2000'), out);
  }

  // ─── injectUserMode ────────────────────────────────────────────────────────

  @isTest
  static void userModeAppendedWhenNoTailClause() {
    String out = RecordHealthCheckSoqlTemplate.injectUserMode(
      'SELECT Id FROM Account WHERE Id = \'001\''
    );
    System.assert(out.endsWith('WITH USER_MODE'), out);
  }

  @isTest
  static void userModeInsertedBeforeOuterOrderBy() {
    String out = RecordHealthCheckSoqlTemplate.injectUserMode(
      'SELECT Id FROM Account WHERE Id = \'001\' ORDER BY Name'
    );
    Integer wm = out.indexOf('WITH USER_MODE');
    Integer ob = out.indexOf('ORDER BY');
    System.assert(
      wm >= 0 && wm < ob,
      'WITH USER_MODE must precede ORDER BY: ' + out
    );
  }

  @isTest
  static void userModeGoesOutsideChildSubqueryOrderBy() {
    // RB-08: the inner ORDER BY must NOT be the injection point.
    String out = RecordHealthCheckSoqlTemplate.injectUserMode(
      'SELECT Id, (SELECT Id FROM Contacts ORDER BY LastName) FROM Account WHERE Id = \'001\''
    );
    Integer wm = out.indexOf('WITH USER_MODE');
    System.assert(
      out.contains('ORDER BY LastName)'),
      'Inner ORDER BY preserved: ' + out
    );
    System.assert(
      wm > out.indexOf(')'),
      'WITH USER_MODE must be outside the subquery: ' + out
    );
  }

  @isTest
  static void literalClauseKeywordNotMistakenForClause() {
    String out = RecordHealthCheckSoqlTemplate.injectUserMode(
      'SELECT Id FROM Account WHERE Name = \'Order by 5\''
    );
    System.assert(
      out.contains('Name = \'Order by 5\''),
      'Literal preserved: ' + out
    );
    System.assert(out.endsWith('WITH USER_MODE'), out);
  }

  @isTest
  static void existingUserModeIsNoOp() {
    String soql = 'SELECT Id FROM Account WHERE Id = \'001\' WITH USER_MODE';
    System.assertEquals(
      soql,
      RecordHealthCheckSoqlTemplate.injectUserMode(soql)
    );
  }

  // ─── validateNoDisallowedKeywords ──────────────────────────────────────────

  @isTest
  static void dmlKeywordRejected() {
    try {
      RecordHealthCheckSoqlTemplate.validateNoDisallowedKeywords(
        'SELECT Id FROM Account WHERE X = 1 DELETE'
      );
      System.assert(false, 'Expected rejection of DELETE.');
    } catch (RecordHealthCheckSoqlTemplate.TemplateException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
  }

  @isTest
  static void keywordInsideLiteralIsAllowed() {
    // "update" inside a string literal must NOT be rejected (RB-08).
    RecordHealthCheckSoqlTemplate.validateNoDisallowedKeywords(
      'SELECT Id FROM Account WHERE Name = \'please update me\''
    );
  }

  @isTest
  static void remainingBlankEscapeOffsetAndSelectBranchesAreCovered() {
    RecordHealthCheckSoqlTemplate.validateNoDisallowedKeywords(null);
    System.assertEquals(
      false,
      RecordHealthCheckSoqlTemplate.isScalarCountQuery(null)
    );
    String escapedLiteral = 'A = \'x\\\'\'';
    System.assertEquals(
      escapedLiteral.length(),
      RecordHealthCheckSoqlTemplate.maskStringLiterals(escapedLiteral).length()
    );
    System.assert(
      RecordHealthCheckSoqlTemplate.enforceRowCap(
          'SELECT Id FROM Account OFFSET 2',
          10
        )
        .contains('LIMIT 10 OFFSET 2')
    );
    try {
      RecordHealthCheckSoqlTemplate.assertSingleOuterSelect('FROM Account');
      System.assert(false, 'Expected a missing SELECT error.');
    } catch (RecordHealthCheckSoqlTemplate.TemplateException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
  }

  @isTest
  static void forUpdatePhraseRejected() {
    try {
      RecordHealthCheckSoqlTemplate.validateNoDisallowedKeywords(
        'SELECT Id FROM Account FOR UPDATE'
      );
      System.assert(false, 'Expected rejection of FOR UPDATE.');
    } catch (RecordHealthCheckSoqlTemplate.TemplateException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
  }

  @isTest
  static void systemModeRejectedByKeywordValidation() {
    // SCAN-03: WITH SYSTEM_MODE bypasses sharing/FLS and must be rejected.
    try {
      RecordHealthCheckSoqlTemplate.validateNoDisallowedKeywords(
        'SELECT Id FROM Account WITH SYSTEM_MODE'
      );
      System.assert(false, 'Expected rejection of WITH SYSTEM_MODE.');
    } catch (RecordHealthCheckSoqlTemplate.TemplateException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
  }

  @isTest
  static void systemModeRejectedByPrepareForExecution() {
    // SCAN-03: the rejection also fires on the shared execution chokepoint, so
    // the dual-SOQL and applicability paths (which skip validateNoDisallowedKeywords)
    // are protected too.
    try {
      RecordHealthCheckSoqlTemplate.prepareForExecution(
        'SELECT Id FROM Account WITH SYSTEM_MODE',
        2000
      );
      System.assert(false, 'Expected rejection of WITH SYSTEM_MODE.');
    } catch (RecordHealthCheckSoqlTemplate.TemplateException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
  }

  @isTest
  static void systemModeInSubqueryRejected() {
    // T-11 / SCAN-43: WITH SYSTEM_MODE nested in a subquery (parenthesis depth > 0)
    // must be rejected too — depth-0-only matching let it bypass validation.
    String nested =
      'SELECT Id FROM Account WHERE Id IN ' +
      '(SELECT AccountId FROM Contact WITH SYSTEM_MODE)';
    try {
      RecordHealthCheckSoqlTemplate.validateNoDisallowedKeywords(nested);
      System.assert(false, 'Expected rejection of nested WITH SYSTEM_MODE.');
    } catch (RecordHealthCheckSoqlTemplate.TemplateException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
    try {
      RecordHealthCheckSoqlTemplate.prepareForExecution(nested, 2000);
      System.assert(false, 'Expected rejection of nested WITH SYSTEM_MODE.');
    } catch (RecordHealthCheckSoqlTemplate.TemplateException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
  }

  @isTest
  static void systemModeInsideLiteralIsAllowed() {
    // The keyword inside a string value is not an access level — must not trip.
    RecordHealthCheckSoqlTemplate.validateNoDisallowedKeywords(
      'SELECT Id FROM Account WHERE Name = \'with system_mode\''
    );
  }

  // ─── prepareForExecution (integration) ─────────────────────────────────────

  @isTest
  static void prepareForExecutionHandlesChildSubqueryWithInnerOrderBy() {
    String out = RecordHealthCheckSoqlTemplate.prepareForExecution(
      'SELECT Id, (SELECT Id FROM Contacts ORDER BY LastName) FROM Account WHERE Id = \'001\'',
      2000
    );
    Integer wm = out.indexOf('WITH USER_MODE');
    Integer limitIdx = out.toUpperCase().indexOf('LIMIT');
    System.assert(
      out.contains('ORDER BY LastName)'),
      'Inner clause preserved: ' + out
    );
    System.assert(
      wm > out.indexOf(')'),
      'WITH USER_MODE outside subquery: ' + out
    );
    System.assert(limitIdx > wm, 'Outer LIMIT after WITH USER_MODE: ' + out);
    System.assert(out.toUpperCase().contains('LIMIT 2000'), out);
  }

  @isTest
  static void prepareForExecutionRejectsBlank() {
    try {
      RecordHealthCheckSoqlTemplate.prepareForExecution('   ', 2000);
      System.assert(false, 'Expected rejection of blank template.');
    } catch (RecordHealthCheckSoqlTemplate.TemplateException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
  }

  @isTest
  static void prepareForExecutionDefaultsCapWhenInvalid() {
    String out = RecordHealthCheckSoqlTemplate.prepareForExecution(
      'SELECT Id FROM Account',
      null
    );
    System.assert(
      out.toUpperCase()
        .contains('LIMIT ' + RecordHealthCheckConstants.FRAMEWORK_MAX_ROWS),
      out
    );
  }

  @isTest
  static void isAggregateQueryDetectsDepthZeroOnly() {
    System.assertEquals(
      true,
      RecordHealthCheckSoqlTemplate.isAggregateQuery(
        'SELECT COUNT(Id) FROM Contact'
      )
    );
    System.assertEquals(
      true,
      RecordHealthCheckSoqlTemplate.isAggregateQuery(
        'SELECT AccountId, COUNT(Id) FROM Contact GROUP BY AccountId'
      )
    );
    // Aggregate only inside a subquery → outer query is not aggregate.
    System.assertEquals(
      false,
      RecordHealthCheckSoqlTemplate.isAggregateQuery(
        'SELECT Id, (SELECT COUNT(Id) FROM Contacts) FROM Account'
      )
    );
  }
}
