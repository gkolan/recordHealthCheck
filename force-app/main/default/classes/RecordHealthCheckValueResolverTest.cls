/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Unit tests for RecordHealthCheckValueResolver. Pure in-memory logic — no DML.
 * Focuses on the consolidated behavior the evaluators will share, especially the
 * L6 parity fix (a native Date is compared as a Date, never a midnight DateTime)
 * and H-07 (relationship-path extraction + missing-field classification).
 */
@isTest
private class RecordHealthCheckValueResolverTest {
  // ─── Extraction ────────────────────────────────────────────────────────────

  @isTest
  static void scalarFromRowReadsSimpleField() {
    Account a = new Account(Name = 'Acme');
    System.assertEquals(
      'Acme',
      RecordHealthCheckValueResolver.scalarFromRow(a, 'Name')
    );
  }

  @isTest
  static void scalarFromRowTraversesRelationshipPath() {
    // Build a nested SObject in memory via JSON so getSObject('Parent') resolves.
    Account a = (Account) JSON.deserialize(
      '{"attributes":{"type":"Account"},"Name":"Child","Parent":{"attributes":{"type":"Account"},"Name":"ParentCo"}}',
      Account.class
    );
    System.assertEquals(
      'ParentCo',
      RecordHealthCheckValueResolver.scalarFromRow(a, 'Parent.Name')
    );
  }

  @isTest
  static void scalarFromRowNullRelationshipYieldsNull() {
    Account a = new Account(Name = 'Child');
    System.assertEquals(
      null,
      RecordHealthCheckValueResolver.scalarFromRow(a, 'Parent.Name')
    );
  }

  @isTest
  static void scalarFromRowMissingFieldThrowsInvalidTemplate() {
    Account a = new Account(Name = 'Acme');
    try {
      RecordHealthCheckValueResolver.scalarFromRow(a, 'Not_A_Field__c');
      System.assert(false, 'Expected ResolverException.');
    } catch (RecordHealthCheckValueResolver.ResolverException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
  }

  @isTest
  static void stringListIncludesNullAsEmpty() {
    List<SObject> rows = new List<SObject>{
      new Account(Name = 'A'),
      new Account()
    };
    List<String> out = RecordHealthCheckValueResolver.stringList(rows, 'Name');
    System.assertEquals(2, out.size());
    System.assertEquals('A', out[0]);
    System.assertEquals('', out[1], 'Null becomes empty string.');
  }

  // ─── Equality ──────────────────────────────────────────────────────────────

  @isTest
  static void valuesEqualNumericAcrossTypes() {
    System.assertEquals(
      true,
      RecordHealthCheckValueResolver.valuesEqual(1, 1.0)
    );
    System.assertEquals(
      false,
      RecordHealthCheckValueResolver.valuesEqual(1, 2)
    );
  }

  @isTest
  static void valuesEqualNullSafe() {
    System.assertEquals(
      true,
      RecordHealthCheckValueResolver.valuesEqual(null, null)
    );
    System.assertEquals(
      false,
      RecordHealthCheckValueResolver.valuesEqual(null, 'x')
    );
  }

  @isTest
  static void valuesEqualDates() {
    System.assertEquals(
      true,
      RecordHealthCheckValueResolver.valuesEqual(
        Date.newInstance(2026, 1, 1),
        Date.newInstance(2026, 1, 1)
      )
    );
  }

  // ─── Ordered comparison ────────────────────────────────────────────────────

  @isTest
  static void orderedNumeric() {
    System.assertEquals(
      true,
      RecordHealthCheckValueResolver.applyOrdered('GreaterThan', 5, 3)
    );
    System.assertEquals(
      true,
      RecordHealthCheckValueResolver.applyOrdered('LessThanOrEqual', 3, 3)
    );
  }

  @isTest
  static void orderedNativeDateUsesDateLadderNotMidnightDateTime() {
    // L6: two native Dates must compare as Dates.
    Date earlier = Date.newInstance(2026, 1, 1);
    Date later = Date.newInstance(2026, 6, 19);
    System.assertEquals(
      true,
      RecordHealthCheckValueResolver.applyOrdered('LessThan', earlier, later)
    );
    System.assertEquals(
      false,
      RecordHealthCheckValueResolver.applyOrdered('GreaterThan', earlier, later)
    );
  }

  @isTest
  static void orderedDateTime() {
    Datetime earlier = Datetime.newInstance(2026, 1, 1, 0, 0, 0);
    Datetime later = Datetime.newInstanceGmt(2026, 1, 1, 10, 0, 0);
    System.assertEquals(
      true,
      RecordHealthCheckValueResolver.applyOrdered('LessThan', earlier, later)
    );
  }

  @isTest
  static void orderedIncompatibleTypesThrows() {
    try {
      RecordHealthCheckValueResolver.applyOrdered(
        'GreaterThan',
        'not-a-number',
        'also-not'
      );
      System.assert(false, 'Expected INCOMPATIBLE_COMPARISON_TYPES.');
    } catch (RecordHealthCheckValueResolver.ResolverException ex) {
      System.assertEquals('INCOMPATIBLE_COMPARISON_TYPES', ex.reasonCode);
    }
  }

  // ─── Misc ──────────────────────────────────────────────────────────────────

  @isTest
  static void isNumericObjectClassifies() {
    System.assertEquals(
      true,
      RecordHealthCheckValueResolver.isNumericObject(5)
    );
    System.assertEquals(
      true,
      RecordHealthCheckValueResolver.isNumericObject(5.0)
    );
    System.assertEquals(
      false,
      RecordHealthCheckValueResolver.isNumericObject('5')
    );
  }

  @isTest
  static void classifyQueryExceptionDistinguishesAccess() {
    System.assertEquals(
      'INVALID_SOQL_TEMPLATE',
      RecordHealthCheckValueResolver.classifyQueryException(
        new TestQueryException('malformed query')
      )
    );
    System.assertEquals(
      'FIELD_NOT_ACCESSIBLE',
      RecordHealthCheckValueResolver.classifyQueryException(
        new TestQueryException('insufficient access rights on field')
      )
    );
  }

  @isTest
  static void remainingTypedBranchesAreCovered() {
    try {
      RecordHealthCheckValueResolver.stringList(
        new List<SObject>{ new Account(Name = 'A') },
        null
      );
      System.assert(false, 'Expected a required-field error.');
    } catch (RecordHealthCheckValueResolver.ResolverException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }

    Datetime earlier = Datetime.newInstance(2026, 1, 1, 0, 0, 0);
    Datetime earlierGmt = Datetime.newInstanceGmt(2026, 1, 1, 0, 0, 0);
    Datetime later = earlier.addHours(1);
    Date earlierDate = Date.newInstance(2026, 1, 1);
    Date laterDate = earlierDate.addDays(1);

    System.assert(
      RecordHealthCheckValueResolver.valuesEqual(earlier, '2026-01-01 00:00:00')
    );
    assertIncompatibleEquality(earlier, 'not-a-datetime');
    assertIncompatibleEquality(earlierDate, 'not-a-date');

    for (
      String comparator : new List<String>{
        'GreaterThan',
        'GreaterThanOrEqual',
        'LessThan',
        'LessThanOrEqual'
      }
    ) {
      RecordHealthCheckValueResolver.orderedDecimal(comparator, 2, 1);
      RecordHealthCheckValueResolver.orderedDateTime(
        comparator,
        later,
        earlier
      );
    }

    assertInvalidOrderedComparator('Decimal');
    assertInvalidOrderedComparator('DateTime');
    System.assertEquals(
      earlierGmt,
      RecordHealthCheckValueResolver.coerceDateTime('2026-01-01T00:00:00Z')
    );
    try {
      RecordHealthCheckValueResolver.applyOrdered('Nope', 1, 1);
      System.assert(false, 'Expected an invalid ordered comparator.');
    } catch (RecordHealthCheckValueResolver.ResolverException ex) {
      System.assertEquals('INVALID_COMPARATOR', ex.reasonCode);
    }
  }

  private static void assertIncompatibleEquality(Object left, Object right) {
    try {
      RecordHealthCheckValueResolver.valuesEqual(left, right);
      System.assert(false, 'Expected incompatible equality operands.');
    } catch (RecordHealthCheckValueResolver.ResolverException ex) {
      System.assertEquals('INCOMPATIBLE_COMPARISON_TYPES', ex.reasonCode);
    }
  }

  private static void assertInvalidOrderedComparator(String valueType) {
    try {
      if (valueType == 'Decimal') {
        RecordHealthCheckValueResolver.orderedDecimal('Nope', 1, 1);
      } else if (valueType == 'DateTime') {
        RecordHealthCheckValueResolver.orderedDateTime(
          'Nope',
          System.now(),
          System.now()
        );
      } else {
        RecordHealthCheckValueResolver.orderedDateTime(
          'Nope',
          System.now(),
          System.now()
        );
      }
      System.assert(false, 'Expected an invalid comparator.');
    } catch (RecordHealthCheckValueResolver.ResolverException ex) {
      System.assertEquals('INVALID_COMPARATOR', ex.reasonCode);
    }
  }

  // Lets us construct a QueryException with a controlled message.
  private class TestQueryException extends Exception {
  }
}
