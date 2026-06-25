/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Shared comparator + null/empty-behavior engine for the SOQL evaluators.
 *
 * The scalar comparator core (Equals / NotEquals / Contains / ordered), value
 * equality, and EmptyResultBehavior resolution were previously duplicated in
 * RecordHealthCheckSoqlEvaluator and RecordHealthCheckDualSoqlEvaluator (and had
 * drifted). They now live here as pure static functions so single-query and
 * dual-query checks compare values identically. The richer single-query
 * comparators (multi-row, list, unary, NullBehavior-aware) live here too so all
 * comparator logic has one home.
 *
 * Throws RecordHealthCheckEvaluatorException so both evaluators map the same
 * reason codes onto UNABLE_TO_EVALUATE results.
 */
public with sharing class RecordHealthCheckComparatorEngine {
  // ─── Scalar comparator core (shared by both evaluators) ───────────────────

  /**
   * The scalar comparator core: Equals / NotEquals / Contains / DoesNotContain
   * and the ordered comparators. No NullBehavior handling — callers that need it
   * use applySingleComparator. Ordered comparisons defer to the value resolver's
   * typed ladder (Decimal → DateTime) so values never compare lexicographically.
   */
  public static Boolean applyScalarComparator(
    String comparator,
    Object primary,
    Object comparison
  ) {
    String pStr = String.valueOf(primary);
    String cStr = String.valueOf(comparison);

    if (comparator == 'Equals')
      return valuesEqual(primary, comparison);
    if (comparator == 'NotEquals')
      return !valuesEqual(primary, comparison);
    if (comparator == 'Contains')
      return pStr.contains(cStr);
    if (comparator == 'DoesNotContain')
      return !pStr.contains(cStr);

    if (
      comparator != 'GreaterThan' &&
      comparator != 'GreaterThanOrEqual' &&
      comparator != 'LessThan' &&
      comparator != 'LessThanOrEqual'
    ) {
      throw new RecordHealthCheckEvaluatorException(
        'INVALID_COMPARATOR',
        'Comparator "' + comparator + '" is not recognized.'
      );
    }

    try {
      return RecordHealthCheckValueResolver.applyOrdered(
        comparator,
        primary,
        comparison
      );
    } catch (RecordHealthCheckValueResolver.ResolverException ex) {
      throw new RecordHealthCheckEvaluatorException(
        ex.reasonCode,
        ex.getMessage()
      );
    }
  }

  public static Boolean valuesEqual(Object primary, Object comparison) {
    try {
      return RecordHealthCheckValueResolver.valuesEqual(primary, comparison);
    } catch (RecordHealthCheckValueResolver.ResolverException ex) {
      throw new RecordHealthCheckEvaluatorException(
        ex.reasonCode,
        ex.getMessage()
      );
    }
  }

  /**
   * Returns true (Pass), false (Fail), null (Skip or UnableToEvaluate).
   * Null signals the caller to use EmptyResultBehavior to set the final status.
   */
  public static Boolean resolveEmptyBehavior(String behavior) {
    if (behavior == 'Pass')
      return true;
    if (behavior == 'Fail')
      return false;
    if (behavior == 'Skip')
      return null;
    if (behavior == 'UnableToEvaluate')
      return null;
    // No explicit config — treat as indeterminate (Skip is the CMT default)
    return null;
  }

  // ─── Single-query comparators (NullBehavior-aware) ────────────────────────

  public static Boolean applyUnaryComparator(String comparator, Object value) {
    Boolean isBlank = (value == null || String.valueOf(value).trim() == '');
    if (comparator == 'IsBlank')
      return isBlank;
    if (comparator == 'IsNotBlank')
      return !isBlank;
    // SCAN-28: an unrecognized unary operator is a configuration error, not an
    // indeterminate value. Returning null here previously misrouted it to the
    // empty/zero-rows behavior; fail loudly so it surfaces as UNABLE instead.
    throw new RecordHealthCheckEvaluatorException(
      'INVALID_COMPARATOR',
      'Unary comparator "' + comparator + '" is not recognized.'
    );
  }

  public static Boolean applySingleComparator(
    String comparator,
    Object primary,
    Object comparison,
    Record_Health_Check_Rule__mdt rule
  ) {
    // Handle null per WhenValueIsEmpty__c
    if (primary == null || comparison == null) {
      if (rule.WhenValueIsEmpty__c == 'TreatMissingAsBlank') {
        // Substitute null with '' and continue with the real comparator
        primary = primary != null ? primary : '';
        comparison = comparison != null ? comparison : '';
      } else {
        return applyNullBehavior(rule.WhenValueIsEmpty__c, primary, comparison);
      }
    }

    return applyScalarComparator(comparator, primary, comparison);
  }

  public static Boolean applyMultiRowComparator(
    Record_Health_Check_Rule__mdt rule,
    List<Object> primaryList,
    Object comparisonValue,
    List<Object> comparisonList
  ) {
    if (primaryList.isEmpty()) {
      return resolveEmptyBehavior(rule.WhenZeroRows__c);
    }

    String mode = rule.WhenMultipleRows__c;

    if (mode == 'AnyRowPasses') {
      Boolean sawEvaluableRecord = false;
      for (Object val : primaryList) {
        Boolean match = applyRowComparator(rule, val, comparisonValue);
        if (match == null)
          continue;
        sawEvaluableRecord = true;
        if (match == true)
          return true;
      }
      if (!sawEvaluableRecord)
        return null;
      return false;
    }

    if (mode == 'AllRowsPass') {
      Boolean sawEvaluableRecord = false;
      for (Object val : primaryList) {
        Boolean match = applyRowComparator(rule, val, comparisonValue);
        if (match == null)
          continue;
        sawEvaluableRecord = true;
        if (match != true)
          return false;
      }
      if (!sawEvaluableRecord)
        return null;
      return true;
    }

    if (mode == 'CompareAsLists') {
      // CompareAsLists requires two separate queries — use CheckType CompareTwoQueries.
      // ConfigService.validateQueryRule blocks this at config time; guard at runtime too.
      throw new RecordHealthCheckEvaluatorException(
        'INVALID_COMPARATOR',
        'Compare as two lists is only supported when Check Method is Compare two queries.'
      );
    }

    throw new RecordHealthCheckEvaluatorException(
      'INVALID_COMPARATOR',
      'Multiple Records Handling "' + mode + '" is not recognized.'
    );
  }

  public static Boolean applyRowComparator(
    Record_Health_Check_Rule__mdt rule,
    Object primary,
    Object comparison
  ) {
    if (
      primary == null &&
      rule.WhenValueIsEmpty__c == 'SkipRecordsWithMissingValue'
    ) {
      return null;
    }
    if (rule.Operator__c == 'IsBlank' || rule.Operator__c == 'IsNotBlank') {
      return applyUnaryComparator(rule.Operator__c, primary);
    }
    return applySingleComparatorNullSafe(
      rule.Operator__c,
      primary,
      comparison,
      rule
    );
  }

  public static Boolean applySingleComparatorNullSafe(
    String comparator,
    Object primary,
    Object comparison,
    Record_Health_Check_Rule__mdt rule
  ) {
    if (primary == null) {
      String nb = rule.WhenValueIsEmpty__c;
      if (nb == 'SkipRecordsWithMissingValue')
        return null;
      if (nb == 'MissingMeansNoMatch')
        return false;
      if (nb == 'TreatMissingAsBlank')
        primary = '';
    }
    return applySingleComparator(comparator, primary, comparison, rule);
  }

  public static Boolean applyListComparator(
    String comparator,
    Object primaryValue,
    List<Object> comparisonList,
    Record_Health_Check_Rule__mdt rule
  ) {
    if (comparisonList == null || comparisonList.isEmpty()) {
      return resolveEmptyBehavior(rule.WhenZeroRows__c);
    }

    if (primaryValue == null) {
      if (rule.WhenValueIsEmpty__c == 'TreatMissingAsBlank') {
        primaryValue = '';
      } else if (rule.WhenValueIsEmpty__c == 'MissingMeansNoMatch') {
        return comparator == 'ListDoesNotContainAny';
      } else {
        return null;
      }
    }
    String pStr = String.valueOf(primaryValue);

    if (comparator == 'ListContainsAny') {
      // B8 fix: case-insensitive comparison
      String pLower = pStr.toLowerCase();
      for (Object item : comparisonList) {
        if (item != null && String.valueOf(item).toLowerCase() == pLower)
          return true;
      }
      return false;
    }

    if (comparator == 'ListDoesNotContainAny') {
      // B8 fix: case-insensitive comparison
      String pLower = pStr.toLowerCase();
      for (Object item : comparisonList) {
        if (item != null && String.valueOf(item).toLowerCase() == pLower)
          return false;
      }
      return true;
    }

    throw new RecordHealthCheckEvaluatorException(
      'INVALID_COMPARATOR',
      'Comparator "' + comparator + '" is not valid for list operations.'
    );
  }

  // ─── Human-readable comparison descriptions (actual vs expected) ──────────
  // These build the actualValue / expectedValue strings shown alongside a
  // non-passing result so the user sees what the record produced versus what
  // the rule required, without an admin hand-authoring it into MessageWhenFailed__c.

  private static final Integer LIST_PREVIEW_CAP = 10;

  /**
   * Maps a comparator API name to a sentence-friendly verb phrase. The phrases
   * are designed to read naturally after the word "expected" when the LWC wraps
   * the comparison as "Found {actualValue}, expected {expectedValue}" — e.g.
   * "expected to equal …", "expected at least 2", "expected to be one of […]".
   */
  public static String humanComparator(String comparator) {
    if (comparator == 'Equals')
      return 'to equal';
    if (comparator == 'NotEquals')
      return 'to not equal';
    if (comparator == 'Contains')
      return 'to contain';
    if (comparator == 'DoesNotContain')
      return 'to not contain';
    if (comparator == 'GreaterThan')
      return 'more than';
    if (comparator == 'GreaterThanOrEqual')
      return 'at least';
    if (comparator == 'LessThan')
      return 'less than';
    if (comparator == 'LessThanOrEqual')
      return 'at most';
    if (comparator == 'IsBlank')
      return 'to be blank';
    if (comparator == 'IsNotBlank')
      return 'to not be blank';
    if (comparator == 'ListContainsAny')
      return 'to be one of';
    if (comparator == 'ListDoesNotContainAny')
      return 'to be none of';
    if (comparator == 'ListsOverlap')
      return 'to overlap with';
    if (comparator == 'ListContainsAll')
      return 'to contain all of';
    if (comparator == 'ExactListMatch')
      return 'to exactly match';
    // SCAN-40 (2026-06-23, re-opened): an unknown comparator falls back to its
    // raw API name. Config validation blocks unknown operators upstream, so this
    // is purely defensive; surfacing the literal name keeps a misconfiguration
    // diagnosable rather than dressing it up as a sentence fragment ("using …").
    return comparator;
  }

  /**
   * Renders a single value for display; null/blank shows as "(blank)". Every
   * non-blank value — text, numeric, Boolean, or date/time — is wrapped in
   * double quotes so the comparison reads consistently regardless of type. This
   * matters because the two sides of one comparison can be different Apex types:
   * a COUNT check yields an Integer actual (1) but a String operand ("2") from
   * metadata, and leaving numbers bare produced the jarring `Found 1 … at least
   * "2"`. Uniform quoting renders that as `Found "1" … at least "2"`, and also
   * delimits values with surrounding spaces or embedded punctuation.
   */
  public static String formatValue(Object value) {
    if (value == null)
      return '(blank)';
    String s = String.valueOf(value);
    if (s == null || s.trim() == '')
      return '(blank)';
    return '"' + s + '"';
  }

  /** Renders a list for display, capped so a large query result stays readable. */
  public static String formatList(List<Object> values) {
    if (values == null || values.isEmpty())
      return '(none)';
    List<String> parts = new List<String>();
    for (Integer i = 0; i < values.size() && i < LIST_PREVIEW_CAP; i++) {
      parts.add(formatValue(values[i]));
    }
    String joined = '[' + String.join(parts, ', ');
    if (values.size() > LIST_PREVIEW_CAP) {
      // Ellipsis sits inside the bracket without an extra comma gap.
      joined += ' … (' + values.size() + ' total)';
    }
    return joined + ']';
  }

  /** Expected-value description: comparator phrase plus the comparison operand. */
  public static String describeExpected(String comparator, Object comparison) {
    if (comparator == 'IsBlank' || comparator == 'IsNotBlank') {
      return humanComparator(comparator);
    }
    return humanComparator(comparator) + ' ' + formatValue(comparison);
  }

  /** Expected-value description for list comparators (operand is a list). */
  public static String describeExpectedList(
    String comparator,
    List<Object> comparison
  ) {
    return humanComparator(comparator) + ' ' + formatList(comparison);
  }

  public static Boolean applyNullBehavior(
    String nullBehavior,
    Object primary,
    Object comparison
  ) {
    if (nullBehavior == 'MissingMeansNoMatch')
      return false;
    if (nullBehavior == 'SkipRecordsWithMissingValue')
      return null;
    // B1 fix: blank WhenValueIsEmpty__c aligns with CMT field default (SkipRecordsWithMissingValue → Skip)
    return null;
  }
}
