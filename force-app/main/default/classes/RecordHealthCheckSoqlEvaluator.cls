/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

public with sharing class RecordHealthCheckSoqlEvaluator {
  private static final Integer DEFAULT_MAX_ROWS = 2000;

  // Compiled once per transaction — Pattern.compile() is expensive; never call it inline
  @TestVisible
  private static final Pattern PATTERN_TOKEN = Pattern.compile(
    '\\{!([A-Za-z0-9_\\.]+)\\}'
  );

  private RecordHealthCheckFormulaEvaluator formulaEvaluator = new RecordHealthCheckFormulaEvaluator();

  // ─── Public entry point ───────────────────────────────────────────────────

  public RecordHealthCheckResult evaluate(
    Record_Health_Check_Rule__mdt rule,
    Id recordId,
    SObject record
  ) {
    Long startMs = System.currentTimeMillis();
    RecordHealthCheckResult result = new RecordHealthCheckResult();
    result.checkDeveloperName = rule.DeveloperName;
    result.label = rule.CheckName__c;
    result.priority = rule.RunOrder__c;
    result.evaluatorType = 'Query';

    try {
      result = doEvaluate(rule, recordId, record, result);
    } catch (Exception ex) {
      result = applyEvaluationException(rule, result, ex);
    }

    result.durationMs = System.currentTimeMillis() - startMs;
    return result;
  }

  @TestVisible
  private RecordHealthCheckResult applyEvaluationException(
    Record_Health_Check_Rule__mdt rule,
    RecordHealthCheckResult result,
    Exception ex
  ) {
    if (ex instanceof RecordHealthCheckEvaluatorException) {
      RecordHealthCheckEvaluatorException evaluatorException = (RecordHealthCheckEvaluatorException) ex;
      result.status = 'UNABLE_TO_EVALUATE';
      result.reasonCode = evaluatorException.reasonCode;
    } else if (ex instanceof System.QueryException) {
      result.status = 'UNABLE_TO_EVALUATE';
      result.reasonCode = 'INVALID_SOQL_TEMPLATE';
    } else {
      result.status = 'ERROR';
      result.reasonCode = 'APEX_EVALUATOR_ERROR';
    }
    result.message = safeCannotEvaluateMessage(rule);
    result.detailMessage = ex.getMessage();
    return result;
  }

  // ─── Core evaluation ──────────────────────────────────────────────────────

  private RecordHealthCheckResult doEvaluate(
    Record_Health_Check_Rule__mdt rule,
    Id recordId,
    SObject record,
    RecordHealthCheckResult result
  ) {
    Boolean isListComparator =
      rule.Operator__c == 'ListContainsAny' ||
      rule.Operator__c == 'ListDoesNotContainAny';
    Boolean isUnaryComparator =
      rule.Operator__c == 'IsBlank' ||
      rule.Operator__c == 'IsNotBlank';
    Integer maxRows = rule.MaxRows__c != null
      ? (Integer) rule.MaxRows__c
      : DEFAULT_MAX_ROWS;

    // ── Resolve primary value / list ──────────────────────────────────────
    Object primaryValue = null;
    List<Object> primaryList = null;

    if (isListComparator) {
      // Tier 6: primary side comes from ValueToTest__c (scalar).
      try {
        primaryValue = formulaEvaluator.resolveScalar(
          rule.ValueToTest__c,
          record,
          rule.ScalarFormulaReturnType__c
        );
      } catch (RecordHealthCheckFormulaEvaluator.FormulaEvaluationException fex) {
        throw new RecordHealthCheckEvaluatorException(
          fex.reasonCode,
          fex.getMessage()
        );
      }
    } else {
      // Tiers 3–5, 8: primary side from DataQuery__c
      String soql = bindTokens(rule.DataQuery__c, record);
      List<SObject> rows = runQuery(soql, maxRows);

      if (rule.WhenMultipleRows__c == 'OneResult') {
        if (rows.isEmpty()) {
          // Aggregate COUNT() always returns 1 row (with count=0), so this branch
          // is only reached by non-aggregate queries with no matching rows.
          // Route through configured EmptyResultBehavior rather than returning 0.
          return buildEmptyOrNullResult(rule, result, null);
        } else if (rows.size() > 1) {
          throw new RecordHealthCheckEvaluatorException(
            'MULTIPLE_ROWS_RETURNED',
            'OneResult check returned ' + rows.size() + ' rows.'
          );
        } else {
          primaryValue = resolveScalarFromRow(rows[0], rule.FieldToRead__c);
        }
      } else {
        // AnyRowPasses, AllRowsPass, CompareAsLists
        primaryList = resolveFieldList(rows, rule.FieldToRead__c);
      }
    }

    // ── Resolve comparison value / list ───────────────────────────────────
    Object comparisonValue = null;
    List<Object> comparisonList = null;
    // P1-05 / SCAN-06: distinguishes a null comparison that came from a comparison
    // query returning zero rows (→ WhenZeroRows__c) from one where the field was
    // simply null on a present row (→ null-value, handled by WhenValueIsEmpty__c).
    Boolean comparisonQueryWasEmpty = false;

    if (!isUnaryComparator) {
      if (isListComparator) {
        // Comparison side: query result list
        String compSoql = bindTokens(rule.CompareToQuery__c, record);
        List<SObject> compRows = runQuery(compSoql, maxRows);
        comparisonList = resolveFieldList(compRows, rule.CompareToField__c);
      } else if (rule.CompareAgainst__c == 'FixedValue') {
        comparisonValue = rule.FixedValue__c;
      } else if (rule.CompareAgainst__c == 'RecordFormula') {
        try {
          comparisonValue = formulaEvaluator.resolveScalar(
            rule.RecordFormulaValue__c,
            record,
            rule.ScalarFormulaReturnType__c
          );
        } catch (RecordHealthCheckFormulaEvaluator.FormulaEvaluationException fex) {
          throw new RecordHealthCheckEvaluatorException(
            fex.reasonCode,
            fex.getMessage()
          );
        }
      } else if (rule.CompareAgainst__c == 'AnotherQuery') {
        String compSoql = bindTokens(rule.CompareToQuery__c, record);
        List<SObject> compRows = runQuery(compSoql, maxRows);
        if (compRows.isEmpty()) {
          comparisonValue = null;
          comparisonQueryWasEmpty = true;
        } else if (compRows.size() == 1) {
          comparisonValue = resolveScalarFromRow(
            compRows[0],
            rule.CompareToField__c
          );
        } else {
          throw new RecordHealthCheckEvaluatorException(
            'MULTIPLE_ROWS_RETURNED',
            'Comparison Query returned ' +
              compRows.size() +
              ' rows for a scalar comparison. ' +
              'Add a LIMIT 1 clause or use AnyRowPasses/AllRowsPass mode.'
          );
        }
      }
    }

    // ── Apply comparator ──────────────────────────────────────────────────
    Boolean passed;

    if (isListComparator) {
      passed = RecordHealthCheckComparatorEngine.applyListComparator(
        rule.Operator__c,
        primaryValue,
        comparisonList,
        rule
      );
    } else if (primaryList != null) {
      // Multi-row primary (AnyRowPasses / AllRowsPass / CompareAsLists)
      passed = RecordHealthCheckComparatorEngine.applyMultiRowComparator(
        rule,
        primaryList,
        comparisonValue,
        comparisonList
      );
    } else if (isUnaryComparator) {
      passed = RecordHealthCheckComparatorEngine.applyUnaryComparator(
        rule.Operator__c,
        primaryValue
      );
    } else {
      passed = RecordHealthCheckComparatorEngine.applySingleComparator(
        rule.Operator__c,
        primaryValue,
        comparisonValue,
        rule
      );
    }

    if (passed == null) {
      // P1-05 / SCAN-06: an indeterminate comparator result has two distinct
      // causes that must NOT be treated alike. A genuine zero-rows result is
      // governed by WhenZeroRows__c; a present-but-null value is governed by the
      // null behavior (WhenValueIsEmpty__c) and resolves to SKIPPED — routing it
      // through WhenZeroRows__c made "null value + WhenZeroRows=Fail" wrongly FAIL.
      Boolean zeroRows;
      if (isListComparator) {
        // List comparator's comparison side is a query; the primary is a scalar.
        // Indeterminate is zero-rows only when that query returned no rows.
        zeroRows = (comparisonList == null || comparisonList.isEmpty());
      } else if (primaryList != null) {
        // Multi-row primary: empty list = zero rows; a non-empty list that still
        // resolved to null means every row's value was null-skipped.
        zeroRows = primaryList.isEmpty();
      } else {
        // OneResult / single scalar: an empty PRIMARY result was already routed
        // above, so the only zero-rows cause left is an empty comparison query.
        zeroRows = comparisonQueryWasEmpty;
      }
      return zeroRows
        ? buildEmptyOrNullResult(rule, result, primaryList)
        : buildNullIndeterminateResult(rule, result);
    }

    // Capture what the record produced vs what the rule required so the UI can
    // show the comparison on a non-passing row (Section: actual vs expected).
    result.actualValue = primaryList != null
      ? RecordHealthCheckComparatorEngine.formatList(primaryList)
      : RecordHealthCheckComparatorEngine.formatValue(primaryValue);
    if (isListComparator) {
      result.expectedValue = RecordHealthCheckComparatorEngine.describeExpectedList(
        rule.Operator__c,
        comparisonList
      );
    } else {
      result.expectedValue = RecordHealthCheckComparatorEngine.describeExpected(
        rule.Operator__c,
        comparisonValue
      );
    }

    if (passed) {
      result.status = 'PASS';
    } else {
      result.status = 'FAIL';
      result.severity = rule.Severity__c;
      result.message = formulaEvaluator.resolveMergeFields(
        rule.MessageWhenFailed__c,
        record
      );
    }
    return result;
  }

  // ─── Token binding (Section 3.2) ──────────────────────────────────────────

  /**
   * Replaces {!FieldName} tokens with the record's field values.
   * Values are returned as a Map so Database.query can use them as bind vars.
   * Since Apex dynamic SOQL only supports real bind variables in code scope,
   * we inject field values directly — but we use String.escapeSingleQuotes
   * for string values and typed formatting for non-strings to prevent injection.
   */
  @TestVisible
  public String bindTokens(String soqlTemplate, SObject record) {
    if (String.isBlank(soqlTemplate)) {
      throw new RecordHealthCheckEvaluatorException(
        'INVALID_SOQL_TEMPLATE',
        'SOQL template is blank.'
      );
    }

    // Validate no disallowed DML keywords using word-boundary matching
    // so field names like IsDeleted or Last_Update__c are not false-positives.
    validateNoDisallowedKeywords(soqlTemplate);

    Matcher m = PATTERN_TOKEN.matcher(soqlTemplate);
    String bound = soqlTemplate;

    while (m.find()) {
      String token = m.group(0);
      String fieldPath = m.group(1);

      Object fieldValue;
      try {
        fieldValue = resolveFieldPath(record, fieldPath);
      } catch (System.SObjectException ex) {
        throw new RecordHealthCheckEvaluatorException(
          'MISSING_BIND_VALUE',
          'Field "' + fieldPath + '" could not be resolved on the record.'
        );
      }

      // A token can appear quoted ('{!Field}') AND unquoted ({!Field}) in the same
      // template, so resolve both quoting contexts independently. For most types the
      // two replacements are identical; only a multi-select picklist differs — its
      // unquoted form expands to an INCLUDES list while its quoted form keeps the
      // raw 'A;B;C' value.
      String quotedToken = '\'' + token + '\'';
      Boolean quotedPresent = bound.contains(quotedToken);

      // Safe substitution — each Apex type maps to the correct SOQL literal format.
      String unquotedReplacement;
      String quotedReplacement;
      if (fieldValue == null) {
        // Quoted context strips the outer quotes so the literal is a bare SOQL null.
        unquotedReplacement = 'null';
        quotedReplacement = 'null';
      } else if (fieldValue instanceof Date) {
        // SOQL Date literals: yyyy-MM-dd — no quotes required or allowed
        unquotedReplacement = String.valueOf((Date) fieldValue);
        quotedReplacement = unquotedReplacement;
      } else if (fieldValue instanceof DateTime) {
        // SOQL DateTime literals: yyyy-MM-ddTHH:mm:ssZ — no quotes required or allowed
        unquotedReplacement = ((DateTime) fieldValue)
          .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        quotedReplacement = unquotedReplacement;
      } else if (fieldValue instanceof Time) {
        // SOQL Time literals: HH:mm:ss.SSSz — no quotes required or allowed
        unquotedReplacement = String.valueOf((Time) fieldValue);
        quotedReplacement = unquotedReplacement;
      } else if (fieldValue instanceof Boolean) {
        // SOQL Boolean literals: true / false — no quotes
        unquotedReplacement = String.valueOf((Boolean) fieldValue);
        quotedReplacement = unquotedReplacement;
      } else if (
        fieldValue instanceof Integer ||
        fieldValue instanceof Long ||
        fieldValue instanceof Double ||
        fieldValue instanceof Decimal
      ) {
        // SOQL numeric literals — no quotes; Decimal handles Currency and Percent fields
        unquotedReplacement = String.valueOf(fieldValue);
        quotedReplacement = unquotedReplacement;
      } else {
        // String, Id, Picklist, Text Area, Auto Number, Encrypted Text, etc.
        String rawStr = String.valueOf(fieldValue);
        // Default: quoted string with single-quote escaping prevents injection.
        // Multi-select picklist in QUOTED context keeps the raw 'A;B;C' value,
        // suitable for exact-match (=) or INCLUDES ('A;B') AND-semantics queries.
        String quotedStr = '\'' + String.escapeSingleQuotes(rawStr) + '\'';
        quotedReplacement = quotedStr;
        if (isMultiSelectPicklist(record, fieldPath) && rawStr.contains(';')) {
          // Multi-select picklist in UNQUOTED context:
          //   Template:  WHERE Regions__c INCLUDES {!Regions__c}
          //   Value:     'North;South'
          //   Result:    WHERE Regions__c INCLUDES ('North', 'South')
          // Each semicolon-delimited value is individually quoted and comma-joined.
          //
          // An all-semicolon value (';' or ';;') has no segments after filtering, which
          // would produce '()' — invalid SOQL (INCLUDES ()). Empty quotedVals instead
          // raise MISSING_BIND_VALUE, same as an unresolved token.
          unquotedReplacement = buildMultiSelectIncludesClause(rawStr);
        } else {
          unquotedReplacement = quotedStr;
        }
      }

      // Replace the quoted form first so its inner {!token} is consumed before the
      // unquoted pass; then replace any remaining bare occurrences. Handling both
      // forms means a token appearing quoted AND unquoted in one template is fully
      // substituted (previously only the quoted form was replaced, leaving a stray
      // {!token} that broke the query). Date/Time/numeric/null literals must not be
      // double-quoted, so the quoted form strips the surrounding quotes.
      if (quotedPresent) {
        bound = bound.replace(quotedToken, quotedReplacement);
      }
      bound = bound.replace(token, unquotedReplacement);
    }

    return bound;
  }

  /**
   * Rejects SOQL containing DML/dangerous keywords matched as whole words only.
   * Uses \b word-boundary so field names like IsDeleted or Last_Update__c
   * do not trigger a false positive on DELETE or UPDATE.
   * Multi-word phrases (FOR UPDATE, ALL ROWS) are still matched literally.
   */
  @TestVisible
  private void validateNoDisallowedKeywords(String soql) {
    try {
      RecordHealthCheckSoqlTemplate.validateNoDisallowedKeywords(soql);
    } catch (RecordHealthCheckSoqlTemplate.TemplateException ex) {
      throw new RecordHealthCheckEvaluatorException(
        ex.reasonCode,
        ex.getMessage()
      );
    }
  }

  // ─── Query execution with row-cap safety (Section 5.1) ───────────────────

  @TestVisible
  private List<SObject> runQuery(String soql, Integer maxRows) {
    String queryToRun;
    try {
      queryToRun = RecordHealthCheckSoqlTemplate.prepareForExecution(
        soql,
        maxRows + 1
      );
    } catch (RecordHealthCheckSoqlTemplate.TemplateException ex) {
      throw new RecordHealthCheckEvaluatorException(
        ex.reasonCode,
        ex.getMessage()
      );
    }

    List<SObject> rows;
    try {
      rows = Database.query(queryToRun);
    } catch (System.QueryException qex) {
      throw new RecordHealthCheckEvaluatorException(
        RecordHealthCheckValueResolver.classifyQueryException(qex),
        qex.getMessage()
      );
    }

    if (rows.size() > maxRows) {
      throw new RecordHealthCheckEvaluatorException(
        'GOVERNOR_LIMIT_RISK',
        'Query returned more than ' +
          maxRows +
          ' rows. Reduce scope or lower Max Rows Override.'
      );
    }
    return rows;
  }

  // ─── Value resolution helpers ─────────────────────────────────────────────

  @TestVisible
  private Object resolveScalarFromRow(SObject row, String fieldName) {
    try {
      return RecordHealthCheckValueResolver.scalarFromRow(row, fieldName);
    } catch (RecordHealthCheckValueResolver.ResolverException ex) {
      throw new RecordHealthCheckEvaluatorException(
        ex.reasonCode,
        ex.getMessage()
      );
    }
  }

  @TestVisible
  private List<Object> resolveFieldList(List<SObject> rows, String fieldName) {
    try {
      return RecordHealthCheckValueResolver.scalarList(rows, fieldName);
    } catch (RecordHealthCheckValueResolver.ResolverException ex) {
      throw new RecordHealthCheckEvaluatorException(
        ex.reasonCode,
        ex.getMessage()
      );
    }
  }

  // ─── Empty / null result behavior ────────────────────────────────────────

  @TestVisible
  private RecordHealthCheckResult buildEmptyOrNullResult(
    Record_Health_Check_Rule__mdt rule,
    RecordHealthCheckResult result,
    List<Object> primaryList
  ) {
    String behavior = rule.WhenZeroRows__c;
    if (behavior == 'Pass') {
      result.status = 'PASS';
    } else if (behavior == 'Fail') {
      result.status = 'FAIL';
      result.severity = rule.Severity__c;
      result.message = String.isNotBlank(rule.MessageWhenFailed__c)
        ? rule.MessageWhenFailed__c
        : 'No matching records found.';
    } else if (behavior == 'UnableToEvaluate') {
      result.status = 'UNABLE_TO_EVALUATE';
      result.reasonCode = 'NO_ROWS_RETURNED';
      result.message = safeCannotEvaluateMessage(rule);
    } else {
      // Skip — CMT field default
      result.status = 'SKIPPED';
      result.reasonCode = 'APPLICABILITY_NOT_MET';
      result.message = 'Check skipped: no matching records.';
    }
    return result;
  }

  /**
   * P1-05 / SCAN-06: result for a present-but-null value the comparator could not
   * decide. Reaching this point means the null behavior (WhenValueIsEmpty__c)
   * resolved to Skip — Pass/Fail/MissingMeansNoMatch all yield a determinate
   * boolean earlier — so the check is reported as SKIPPED. This is deliberately
   * NOT governed by WhenZeroRows__c, which applies only to empty result sets.
   */
  @TestVisible
  private RecordHealthCheckResult buildNullIndeterminateResult(
    Record_Health_Check_Rule__mdt rule,
    RecordHealthCheckResult result
  ) {
    result.status = 'SKIPPED';
    result.reasonCode = 'VALUE_IS_EMPTY';
    result.message = 'Check skipped: the value under test was empty.';
    return result;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /**
   * Builds the parenthesized INCLUDES operand for an unquoted multi-select token.
   * @TestVisible so BIND-04 can assert semicolon-only values without a live field.
   */
  @TestVisible
  private String buildMultiSelectIncludesClause(String rawStr) {
    List<String> quotedVals = new List<String>();
    for (String v : rawStr.split(';')) {
      // SCAN-30: drop empty segments so 'A;' / 'A;;B' do not inject '' entries.
      if (String.isBlank(v)) {
        continue;
      }
      quotedVals.add('\'' + String.escapeSingleQuotes(v.trim()) + '\'');
    }
    if (quotedVals.isEmpty()) {
      throw new RecordHealthCheckEvaluatorException(
        'MISSING_BIND_VALUE',
        'Multi-select value has no non-empty segments after splitting on ";".'
      );
    }
    return '(' + String.join(quotedVals, ', ') + ')';
  }

  @TestVisible
  private Boolean isMultiSelectPicklist(SObject record, String fieldPath) {
    List<String> parts = fieldPath.split('\\.');
    Schema.SObjectType currentType = record.getSObjectType();
    for (Integer i = 0; i < parts.size(); i++) {
      Map<String, Schema.SObjectField> fieldMap = currentType.getDescribe()
        .fields.getMap();
      if (i == parts.size() - 1) {
        Schema.SObjectField field = fieldMap.get(parts[i]);
        return field != null &&
          field.getDescribe().getType() == Schema.DisplayType.MULTIPICKLIST;
      }
      Schema.SObjectField relationshipField;
      for (Schema.SObjectField candidate : fieldMap.values()) {
        Schema.DescribeFieldResult description = candidate.getDescribe();
        if (
          description.getRelationshipName() != null &&
          description.getRelationshipName().equalsIgnoreCase(parts[i])
        ) {
          relationshipField = candidate;
          break;
        }
      }
      if (relationshipField == null)
        return false;
      List<Schema.SObjectType> referenceTypes = relationshipField
        .getDescribe()
        .getReferenceTo();
      if (referenceTypes.isEmpty())
        return false;
      currentType = referenceTypes[0];
    }
    return false;
  }

  /**
   * Resolves a field path that may include relationship traversal
   * (e.g. "Account.Name", "Parent.ShippingCity", "Owner.IsActive").
   * Traverses getSObject() for each relationship segment; returns null
   * if any intermediate relationship is null rather than throwing.
   */
  @TestVisible
  private Object resolveFieldPath(SObject record, String fieldPath) {
    if (!fieldPath.contains('.')) {
      return record.get(fieldPath);
    }
    List<String> parts = fieldPath.split('\\.');
    SObject current = record;
    for (Integer i = 0; i < parts.size() - 1; i++) {
      current = current.getSObject(parts[i]);
      if (current == null) {
        return null;
      }
    }
    return current.get(parts[parts.size() - 1]);
  }

  @TestVisible
  private String safeCannotEvaluateMessage(Record_Health_Check_Rule__mdt rule) {
    return String.isNotBlank(rule.MessageWhenCannotRun__c)
      ? rule.MessageWhenCannotRun__c
      : 'This check could not be evaluated. Contact your administrator.';
  }
}
