/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

public with sharing class RecordHealthCheckDualSoqlEvaluator {
  private static final Integer DEFAULT_MAX_ROWS = 2000;

  // P1-04: sentinel representing a missing value under MissingMeansNoMatch in a
  // list comparison. The reserved leading-space token will not realistically
  // collide with field data, and toStringList appends the side + a per-null index
  // so every missing value is distinct — a null then matches nothing, not even
  // another null. See toStringList.
  private static final String MISSING_NO_MATCH_SENTINEL = ' __rhc_missing__:';

  // Delegate token binding and query execution to the existing SOQL evaluator
  private RecordHealthCheckSoqlEvaluator soqlEvaluator = new RecordHealthCheckSoqlEvaluator();

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
    result.evaluatorType = 'CompareTwoQueries';

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
    Integer maxRows = rule.MaxRows__c != null
      ? (Integer) rule.MaxRows__c
      : DEFAULT_MAX_ROWS;

    String primarySoql = soqlEvaluator.bindTokens(rule.DataQuery__c, record);
    String comparisonSoql = soqlEvaluator.bindTokens(
      rule.CompareToQuery__c,
      record
    );

    List<SObject> primaryRows = runQuery(primarySoql, maxRows);
    List<SObject> comparisonRows = runQuery(comparisonSoql, maxRows);

    String mode = rule.WhenMultipleRows__c;
    Boolean passed;

    if (mode == 'OneResult') {
      // Tier 7 — both sides resolve to a single value.
      // SCAN-46: a zero-row query is governed by WhenZeroRows__c, NOT by the
      // null-value behavior (WhenValueIsEmpty__c). evaluateSingleVsSingle
      // collapses an empty query and a present-but-null field to the same null,
      // so without this early route an empty side with MissingMeansNoMatch would
      // wrongly FAIL (and TreatMissingAsBlank would wrongly compare '') instead
      // of honoring WhenZeroRows__c. Mirrors the single-query evaluator, which
      // routes an empty primary to buildEmptyOrNullResult up front.
      if (primaryRows.isEmpty() || comparisonRows.isEmpty()) {
        return buildEmptyOrNullResult(rule, result);
      }
      passed = evaluateSingleVsSingle(rule, primaryRows, comparisonRows);
    } else if (mode == 'CompareAsLists') {
      // Tier 9 — both sides resolve to lists; list-vs-list set operations
      passed = evaluateListVsList(rule, primaryRows, comparisonRows);
    } else {
      throw new RecordHealthCheckEvaluatorException(
        'INVALID_COMPARATOR',
        'CompareTwoQueries does not support Multiple Records Handling "' +
          mode +
          '".' +
          ' Use OneResult (Tier 7) or CompareAsLists (Tier 9).'
      );
    }

    if (passed == null) {
      // P1-05 / SCAN-06: separate a genuine zero-rows result (governed by
      // WhenZeroRows__c) from a present-but-null value (governed by the null
      // behavior, resolving to SKIPPED). For OneResult an empty query is already
      // routed above (SCAN-46), so a null here is a present-row null field;
      // CompareAsLists returns null when a side is empty (zero rows).
      Boolean zeroRows = primaryRows.isEmpty() || comparisonRows.isEmpty();
      return zeroRows
        ? buildEmptyOrNullResult(rule, result)
        : buildNullIndeterminateResult(rule, result);
    }

    // Capture actual vs expected from the rows already fetched (no extra query)
    // so the UI can show the comparison on a non-passing row.
    setComparisonValues(rule, result, primaryRows, comparisonRows, mode);

    if (passed) {
      result.status = 'PASS';
    } else {
      result.status = 'FAIL';
      result.severity = rule.Severity__c;
      // Merge-field resolution is handled by the Engine (Section 5.1 / S55),
      // but the SOQL evaluator also sets it here for consistency
      result.message = String.isNotBlank(rule.MessageWhenFailed__c)
        ? rule.MessageWhenFailed__c
        : 'Check failed.';
    }
    return result;
  }

  // ─── Actual vs expected display values ────────────────────────────────────

  /**
   * Populates result.actualValue / result.expectedValue from the rows already
   * fetched. Called only after the comparator returned a determinate boolean, so
   * resolveSingleValue cannot throw here for the OneResult path.
   */
  @TestVisible
  private void setComparisonValues(
    Record_Health_Check_Rule__mdt rule,
    RecordHealthCheckResult result,
    List<SObject> primaryRows,
    List<SObject> comparisonRows,
    String mode
  ) {
    if (mode == 'OneResult') {
      Object primaryValue = resolveSingleValue(
        primaryRows,
        rule.FieldToRead__c,
        'primary'
      );
      Object comparisonValue = resolveSingleValue(
        comparisonRows,
        rule.CompareToField__c,
        'comparison'
      );
      result.actualValue = RecordHealthCheckComparatorEngine.formatValue(
        primaryValue
      );
      result.expectedValue = RecordHealthCheckComparatorEngine.describeExpected(
        rule.Operator__c,
        comparisonValue
      );
    } else {
      // CompareAsLists — show both result sets
      List<Object> primaryList = RecordHealthCheckValueResolver.scalarList(
        primaryRows,
        rule.FieldToRead__c
      );
      List<Object> comparisonList = RecordHealthCheckValueResolver.scalarList(
        comparisonRows,
        rule.CompareToField__c
      );
      result.actualValue = RecordHealthCheckComparatorEngine.formatList(
        primaryList
      );
      result.expectedValue = RecordHealthCheckComparatorEngine.describeExpectedList(
        rule.Operator__c,
        comparisonList
      );
    }
  }

  // ─── Tier 7 — single-value vs single-value ────────────────────────────────

  @TestVisible
  private Boolean evaluateSingleVsSingle(
    Record_Health_Check_Rule__mdt rule,
    List<SObject> primaryRows,
    List<SObject> comparisonRows
  ) {
    // Both sides must resolve to exactly one row (or an aggregate)
    Object primaryValue = resolveSingleValue(
      primaryRows,
      rule.FieldToRead__c,
      'primary'
    );
    Object comparisonValue = resolveSingleValue(
      comparisonRows,
      rule.CompareToField__c,
      'comparison'
    );

    if (primaryValue == null || comparisonValue == null) {
      String nb = rule.WhenValueIsEmpty__c;
      if (nb == 'SkipRecordsWithMissingValue')
        return null;
      if (nb == 'TreatMissingAsBlank') {
        primaryValue = primaryValue != null ? primaryValue : '';
        comparisonValue = comparisonValue != null ? comparisonValue : '';
      } else if (nb == 'MissingMeansNoMatch') {
        return false;
      } else {
        // B1 fix: blank WhenValueIsEmpty__c aligns with CMT field default (SkipRecordsWithMissingValue → Skip)
        return null;
      }
    }

    return RecordHealthCheckComparatorEngine.applyScalarComparator(
      rule.Operator__c,
      primaryValue,
      comparisonValue
    );
  }

  @TestVisible
  private Object resolveSingleValue(
    List<SObject> rows,
    String fieldName,
    String side
  ) {
    if (rows.isEmpty()) {
      // SELECT COUNT(Id) always returns 1 row even with 0 matching records,
      // so this branch is only reached by non-aggregate queries with no rows.
      return null; // NullBehavior on the caller decides what to do
    }
    if (rows.size() > 1) {
      throw new RecordHealthCheckEvaluatorException(
        'MULTIPLE_ROWS_RETURNED',
        'CompareTwoQueries OneResult: ' +
          side +
          ' query returned ' +
          rows.size() +
          ' rows.'
      );
    }
    try {
      return RecordHealthCheckValueResolver.scalarFromRow(rows[0], fieldName);
    } catch (RecordHealthCheckValueResolver.ResolverException ex) {
      throw new RecordHealthCheckEvaluatorException(
        ex.reasonCode,
        ex.getMessage()
      );
    }
  }

  // ─── Tier 9 — list vs list ────────────────────────────────────────────────

  @TestVisible
  private Boolean evaluateListVsList(
    Record_Health_Check_Rule__mdt rule,
    List<SObject> primaryRows,
    List<SObject> comparisonRows
  ) {
    if (primaryRows.isEmpty() || comparisonRows.isEmpty()) {
      return RecordHealthCheckComparatorEngine.resolveEmptyBehavior(
        rule.WhenZeroRows__c
      );
    }

    List<String> primaryList = toStringList(
      primaryRows,
      rule.FieldToRead__c,
      'primary',
      rule.WhenValueIsEmpty__c
    );
    List<String> comparisonList = toStringList(
      comparisonRows,
      rule.CompareToField__c,
      'comparison',
      rule.WhenValueIsEmpty__c
    );

    // SCAN-44: rows existed (the zero-row guard above already returned), but a
    // side's values were ALL null and dropped by SkipRecordsWithMissingValue,
    // leaving an empty list. That is indeterminate — every value under test was
    // missing — not a determinate FAIL/PASS from comparing empty sets. Return
    // null so the null behavior governs it (SKIPPED via buildNullIndeterminateResult)
    // rather than silently FAILing ListsOverlap / passing ListContainsAll.
    if (primaryList.isEmpty() || comparisonList.isEmpty()) {
      return null;
    }

    // B8 fix: normalise to lowercase so set operations are case-insensitive
    Set<String> primarySet = new Set<String>();
    for (String s : primaryList) {
      primarySet.add(s != null ? s.toLowerCase() : '');
    }
    Set<String> comparisonSet = new Set<String>();
    for (String s : comparisonList) {
      comparisonSet.add(s != null ? s.toLowerCase() : '');
    }

    String comparator = rule.Operator__c;

    if (comparator == 'ListsOverlap') {
      // At least one value appears in both lists (S31)
      for (String val : primarySet) {
        if (comparisonSet.contains(val))
          return true;
      }
      return false;
    }

    if (comparator == 'ListContainsAll') {
      // Every value in the primary list appears somewhere in the comparison list (S32)
      for (String val : primarySet) {
        if (!comparisonSet.contains(val))
          return false;
      }
      return true;
    }

    if (comparator == 'ExactListMatch') {
      // Exact means same normalized values and the same duplicate counts.
      return frequencyMapsEqual(
        toFrequencyMap(primaryList),
        toFrequencyMap(comparisonList)
      );
    }

    throw new RecordHealthCheckEvaluatorException(
      'INVALID_COMPARATOR',
      'Comparator "' +
        comparator +
        '" is not valid for CompareAsLists on CompareTwoQueries.' +
        ' Use ListsOverlap, ListContainsAll, or ExactListMatch.'
    );
  }

  @TestVisible
  private List<String> toStringList(
    List<SObject> rows,
    String fieldName,
    String side,
    String nullBehavior
  ) {
    List<String> values = new List<String>();
    Integer missingIndex = 0;
    try {
      for (
        Object val : RecordHealthCheckValueResolver.scalarList(rows, fieldName)
      ) {
        if (val != null) {
          values.add(String.valueOf(val));
          continue;
        }
        // P1-04: null handling now depends on the configured null behavior.
        if (nullBehavior == 'SkipRecordsWithMissingValue') {
          // Drop the missing value from the list entirely.
          continue;
        }
        if (nullBehavior == 'MissingMeansNoMatch') {
          // A missing value must match nothing — not even another missing value.
          // Coercing to '' (the old behavior) let two null fields "match" as
          // blanks and wrongly satisfy ListsOverlap / ExactListMatch. Emit a
          // unique, non-data sentinel instead so each null stays distinct.
          values.add(MISSING_NO_MATCH_SENTINEL + side + ':' + missingIndex++);
          continue;
        }
        // TreatMissingAsBlank and the CMT blank default treat a missing value as
        // a matchable blank.
        values.add('');
      }
    } catch (RecordHealthCheckValueResolver.ResolverException ex) {
      throw new RecordHealthCheckEvaluatorException(
        ex.reasonCode,
        ex.getMessage()
      );
    }
    return values;
  }

  @TestVisible
  private Map<String, Integer> toFrequencyMap(List<String> values) {
    Map<String, Integer> frequencies = new Map<String, Integer>();
    for (String value : values) {
      String normalized = value != null ? value.toLowerCase() : '';
      Integer currentCount = frequencies.containsKey(normalized)
        ? frequencies.get(normalized)
        : 0;
      frequencies.put(normalized, currentCount + 1);
    }
    return frequencies;
  }

  @TestVisible
  private Boolean frequencyMapsEqual(
    Map<String, Integer> left,
    Map<String, Integer> right
  ) {
    if (left.size() != right.size())
      return false;
    for (String key : left.keySet()) {
      if (!right.containsKey(key) || right.get(key) != left.get(key))
        return false;
    }
    return true;
  }

  // ─── Query execution with row-cap safety ─────────────────────────────────

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

  // ─── Empty/null result helpers ────────────────────────────────────────────

  @TestVisible
  private RecordHealthCheckResult buildEmptyOrNullResult(
    Record_Health_Check_Rule__mdt rule,
    RecordHealthCheckResult result
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
      result.status = 'SKIPPED';
      result.reasonCode = 'APPLICABILITY_NOT_MET';
      result.message = 'Check skipped: empty result per configuration.';
    }
    return result;
  }

  /**
   * P1-05 / SCAN-06: result for a present-but-null value (both queries returned
   * rows, but a field under test was null and the null behavior resolves to Skip).
   * Reported as SKIPPED and deliberately NOT governed by WhenZeroRows__c.
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

  @TestVisible
  private String safeCannotEvaluateMessage(Record_Health_Check_Rule__mdt rule) {
    return String.isNotBlank(rule.MessageWhenCannotRun__c)
      ? rule.MessageWhenCannotRun__c
      : 'This check could not be evaluated. Contact your administrator.';
  }
}
