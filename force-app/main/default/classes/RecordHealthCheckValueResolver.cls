/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Shared value extraction, coercion, and comparison for the SOQL evaluators (M-01).
 *
 * Both RecordHealthCheckSoqlEvaluator and RecordHealthCheckDualSoqlEvaluator
 * previously carried their own copies of scalar/list extraction, QueryException
 * classification, type coercion, equality, and ordered comparison — and the copies
 * had drifted (notably Date/DateTime coercion, H-07/L6). Centralizing them here
 * guarantees single-query and dual-query checks behave identically.
 *
 * Apex boxes Date values through the Datetime branch when they are held as Object,
 * so temporal comparisons consistently use Datetime semantics after the numeric
 * comparison attempt.
 */
public with sharing class RecordHealthCheckValueResolver {
  public class ResolverException extends Exception {
    public String reasonCode;
    public ResolverException(String reasonCode, String message) {
      this(message);
      this.reasonCode = reasonCode;
    }
  }

  // ─── Extraction ─────────────────────────────────────────────────────────────

  /**
   * Resolves a single value from a query row. Handles AggregateResult (COUNT()
   * → expr0, or a named alias) and relationship traversal in the field path
   * (e.g. "Account.Name") — a null intermediate relationship yields null rather
   * than throwing. A missing field surfaces as INVALID_SOQL_TEMPLATE.
   */
  public static Object scalarFromRow(SObject row, String fieldName) {
    if (row instanceof AggregateResult) {
      AggregateResult ar = (AggregateResult) row;
      return String.isBlank(fieldName) ? ar.get('expr0') : ar.get(fieldName);
    }
    if (String.isBlank(fieldName)) {
      throw new ResolverException(
        'INVALID_SOQL_TEMPLATE',
        'A query field is required for non-aggregate queries.'
      );
    }
    try {
      return traverse(row, fieldName);
    } catch (System.SObjectException ex) {
      throw new ResolverException(
        'INVALID_SOQL_TEMPLATE',
        'Field "' + fieldName + '" not found in query result.'
      );
    }
  }

  /** Resolves a list of raw values, one per row. */
  public static List<Object> scalarList(List<SObject> rows, String fieldName) {
    List<Object> values = new List<Object>();
    for (SObject row : rows) {
      values.add(scalarFromRow(row, fieldName));
    }
    return values;
  }

  /**
   * Resolves a list of string values, one per row. Null is included as '' so list
   * comparators can distinguish [A, null, B] from [A, B] rather than silently
   * collapsing them.
   */
  public static List<String> stringList(List<SObject> rows, String fieldName) {
    if (String.isBlank(fieldName)) {
      throw new ResolverException(
        'INVALID_SOQL_TEMPLATE',
        'A query field is required for list comparison queries.'
      );
    }
    List<String> values = new List<String>();
    for (SObject row : rows) {
      Object val = scalarFromRow(row, fieldName);
      values.add(val != null ? String.valueOf(val) : '');
    }
    return values;
  }

  @TestVisible
  private static Object traverse(SObject row, String fieldPath) {
    if (!fieldPath.contains('.')) {
      return row.get(fieldPath);
    }
    List<String> parts = fieldPath.split('\\.');
    SObject current = row;
    for (Integer i = 0; i < parts.size() - 1; i++) {
      current = current.getSObject(parts[i]);
      if (current == null) {
        return null;
      }
    }
    return current.get(parts[parts.size() - 1]);
  }

  /**
   * Maps a query failure to a reason code: access/permission issues vs bad SOQL.
   * Accepts any Exception (System.QueryException is not constructible with a custom
   * message, so the parameter is the base type) — only the message is inspected.
   */
  public static String classifyQueryException(Exception qex) {
    String m = qex.getMessage() == null ? '' : qex.getMessage();
    Boolean access =
      m.containsIgnoreCase('access') ||
      m.containsIgnoreCase('permission') ||
      m.containsIgnoreCase('insufficient privileges');
    return access ? 'FIELD_NOT_ACCESSIBLE' : 'INVALID_SOQL_TEMPLATE';
  }

  // ─── Equality ───────────────────────────────────────────────────────────────

  public static Boolean valuesEqual(Object primary, Object comparison) {
    if (primary == null || comparison == null) {
      return primary == comparison;
    }
    if (isNumericObject(primary) || isNumericObject(comparison)) {
      try {
        return Decimal.valueOf(String.valueOf(primary)) ==
          Decimal.valueOf(String.valueOf(comparison));
      } catch (Exception ex) {
        throw new ResolverException(
          'INCOMPATIBLE_COMPARISON_TYPES',
          'Numeric comparison value could not be parsed.'
        );
      }
    }
    if (primary instanceof Datetime || comparison instanceof Datetime) {
      try {
        return coerceDateTime(primary) == coerceDateTime(comparison);
      } catch (Exception ex) {
        throw new ResolverException(
          'INCOMPATIBLE_COMPARISON_TYPES',
          'DateTime comparison value could not be parsed.'
        );
      }
    }
    // Normalize both sides through coerceDateTime before comparing, so a Date on one
    // side and a Datetime on the other still match (a String.valueOf equality would
    // never match, e.g. 2024-01-15 vs midnight).
    if (primary instanceof Date || comparison instanceof Date) {
      try {
        return coerceDateTime(primary) == coerceDateTime(comparison);
      } catch (Exception ex) {
        throw new ResolverException(
          'INCOMPATIBLE_COMPARISON_TYPES',
          'Date comparison value could not be parsed.'
        );
      }
    }
    // Coerce both sides to Id before comparison, so a 15-char and an 18-char form of
    // the same Id match (String.valueOf would often compare them as unequal).
    if (primary instanceof Id || comparison instanceof Id) {
      try {
        return Id.valueOf(String.valueOf(primary)) ==
          Id.valueOf(String.valueOf(comparison));
      } catch (Exception ex) {
        return false;
      }
    }
    return String.valueOf(primary) == String.valueOf(comparison);
  }

  // ─── Ordered comparison ─────────────────────────────────────────────────────

  /**
   * Applies an ordered comparator (GreaterThan/…/LessThanOrEqual) by trying typed
   * ladders in order of specificity: Decimal → DateTime. Throws
   * INCOMPATIBLE_COMPARISON_TYPES rather than ever falling back to lexicographic
   * string order.
   */
  public static Boolean applyOrdered(
    String comparator,
    Object primary,
    Object comparison
  ) {
    try {
      Decimal p = Decimal.valueOf(String.valueOf(primary));
      Decimal c = Decimal.valueOf(String.valueOf(comparison));
      return orderedDecimal(comparator, p, c);
    } catch (ResolverException re) {
      throw re;
    } catch (Exception numEx) {
      try {
        return orderedDateTime(
          comparator,
          coerceDateTime(primary),
          coerceDateTime(comparison)
        );
      } catch (Exception dtEx) {
        throw new ResolverException(
          'INCOMPATIBLE_COMPARISON_TYPES',
          'Comparator "' +
            comparator +
            '" requires comparable numeric, Date, or DateTime values.'
        );
      }
    }
  }

  @TestVisible
  private static Boolean orderedDecimal(
    String comparator,
    Decimal p,
    Decimal c
  ) {
    if (comparator == 'GreaterThan')
      return p > c;
    if (comparator == 'GreaterThanOrEqual')
      return p >= c;
    if (comparator == 'LessThan')
      return p < c;
    if (comparator == 'LessThanOrEqual')
      return p <= c;
    throw new ResolverException(
      'INVALID_COMPARATOR',
      'Comparator "' + comparator + '" is not an ordered comparator.'
    );
  }

  @TestVisible
  private static Boolean orderedDateTime(
    String comparator,
    Datetime p,
    Datetime c
  ) {
    if (comparator == 'GreaterThan')
      return p > c;
    if (comparator == 'GreaterThanOrEqual')
      return p >= c;
    if (comparator == 'LessThan')
      return p < c;
    if (comparator == 'LessThanOrEqual')
      return p <= c;
    throw new ResolverException(
      'INVALID_COMPARATOR',
      'Comparator "' + comparator + '" is not an ordered comparator.'
    );
  }

  // ─── Coercion (strict — see class header) ──────────────────────────────────

  public static Boolean isNumericObject(Object value) {
    return value instanceof Integer ||
      value instanceof Long ||
      value instanceof Double ||
      value instanceof Decimal;
  }

  @TestVisible
  private static Datetime coerceDateTime(Object value) {
    // SCAN-10 (2026-06-23): in Apex a pure Date is `instanceof Datetime` (true),
    // but casting it to Datetime yields midnight GMT — not the running user's local
    // start of day — so a Date never compared equal to its same-day midnight
    // Datetime. A real Datetime is NOT `instanceof Date`, so this branch matches
    // only pure Date values; normalize them to local start of day.
    if (value instanceof Date) {
      return Datetime.newInstance((Date) value, Time.newInstance(0, 0, 0, 0));
    }
    if (value instanceof Datetime) {
      return (Datetime) value;
    }
    String textValue = String.valueOf(value);
    if (textValue.endsWith('Z')) {
      textValue = textValue.replace('T', ' ').replace('Z', '');
      return Datetime.valueOfGmt(textValue);
    }
    return Datetime.valueOf(textValue);
  }
}
