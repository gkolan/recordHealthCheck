/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Parenthesis-depth-aware SOQL template normalizer (RB-08, M-01).
 *
 * The single source of truth for turning an admin-authored SOQL template into a
 * query that is safe to execute: it masks string literals, recognizes clauses
 * ONLY at the outermost (depth-0) level, validates a single outer SELECT, injects
 * WITH USER_MODE in the correct place, and enforces an effective outer row cap.
 *
 * Previously this logic was duplicated (and subtly different) across
 * RecordHealthCheckSoqlEvaluator, RecordHealthCheckDualSoqlEvaluator, and the
 * engine's applicability path, using substring/regex scans that ignored
 * parentheses. That allowed several real defects this class fixes:
 *   - an ORDER BY / GROUP BY / LIMIT inside a child subquery becoming the
 *     insertion point for the outer WITH USER_MODE (invalid SOQL);
 *   - a subquery/literal containing LIMIT making the outer query look capped;
 *   - a child aggregate making the outer query look like a pure aggregate and
 *     suppressing the cap;
 *   - an oversized outer LIMIT (e.g. 50000) consuming the governor limit before
 *     the post-query size check;
 *   - keyword rejection firing on words such as "update" inside a string literal.
 *
 * Methods are static and side-effect free. Callers map TemplateException.reasonCode
 * onto their own result/exception types.
 */
public with sharing class RecordHealthCheckSoqlTemplate {
  private static final Pattern PATTERN_DML_KEYWORD = Pattern.compile(
    '(?i)\\b(DELETE|INSERT|UPDATE|UNDELETE)\\b'
  );
  private static final Pattern PATTERN_SELECT = Pattern.compile(
    '(?i)\\bSELECT\\b'
  );
  private static final Pattern PATTERN_GROUP_BY = Pattern.compile(
    '(?i)\\bGROUP\\s+BY\\b'
  );
  private static final Pattern PATTERN_AGGREGATE_FUNC = Pattern.compile(
    '(?i)\\b(COUNT|COUNT_DISTINCT|SUM|AVG|MIN|MAX)\\s*\\('
  );
  private static final Pattern PATTERN_COUNT_EMPTY = Pattern.compile(
    '(?i)\\bSELECT\\s+COUNT\\(\\s*\\)'
  );
  private static final Pattern PATTERN_SCALAR_COUNT = Pattern.compile(
    '(?i)\\bSELECT\\s+COUNT\\s*\\(\\s*(?:Id)?\\s*\\)' +
    '(?:\\s+[A-Za-z_][A-Za-z0-9_]*)?\\s+FROM\\b'
  );
  private static final Pattern PATTERN_LIMIT = Pattern.compile(
    '(?i)\\bLIMIT\\s+(\\d+)'
  );
  private static final Pattern PATTERN_OFFSET = Pattern.compile(
    '(?i)\\bOFFSET\\b'
  );
  private static final Pattern PATTERN_WITH = Pattern.compile(
    '(?i)\\bWITH\\s+(USER_MODE|SECURITY_ENFORCED)\\b'
  );
  // SCAN-03: WITH SYSTEM_MODE runs the query without the sharing rules and FLS
  // that WITH USER_MODE enforces. An admin-authored Check Set template must never
  // be allowed to request it, so it is rejected outright rather than recognized.
  private static final Pattern PATTERN_SYSTEM_MODE = Pattern.compile(
    '(?i)\\bWITH\\s+SYSTEM_MODE\\b'
  );
  // Tail clauses, in the order they may legally appear, that WITH USER_MODE must precede.
  private static final List<Pattern> TAIL_CLAUSE_PATTERNS = new List<Pattern>{
    PATTERN_GROUP_BY,
    Pattern.compile('(?i)\\bORDER\\s+BY\\b'),
    Pattern.compile('(?i)\\bLIMIT\\b'),
    PATTERN_OFFSET
  };

  public class TemplateException extends Exception {
    public String reasonCode;
    public TemplateException(String reasonCode, String message) {
      this(message);
      this.reasonCode = reasonCode;
    }
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /**
   * Full preparation for execution: validate shape, rewrite bare COUNT(), enforce
   * the effective outer row cap, and inject WITH USER_MODE — all depth-0 aware.
   * Returns the query string to hand to Database.query().
   */
  public static String prepareForExecution(String soql, Integer maxRows) {
    if (String.isBlank(soql)) {
      throw new TemplateException(
        'INVALID_SOQL_TEMPLATE',
        'SOQL template is blank.'
      );
    }
    Integer cap = (maxRows == null ||
      maxRows <= 0)
      ? RecordHealthCheckConstants.FRAMEWORK_MAX_ROWS
      : maxRows;

    assertSingleOuterSelect(soql);
    rejectSystemMode(soql);
    String prepared = rewriteBareCount(soql);
    prepared = enforceRowCap(prepared, cap);
    prepared = injectUserMode(prepared);
    return prepared;
  }

  /**
   * Rejects DML / dangerous keywords, matching whole words at any depth but
   * IGNORING text inside string literals (so a literal 'Order by 5' or a value
   * containing "update" is never a false positive).
   */
  public static void validateNoDisallowedKeywords(String soql) {
    if (String.isBlank(soql)) {
      return;
    }
    String masked = maskStringLiterals(soql);
    Matcher dml = PATTERN_DML_KEYWORD.matcher(masked);
    if (dml.find()) {
      throw new TemplateException(
        'INVALID_SOQL_TEMPLATE',
        'SOQL contains disallowed keyword: ' + dml.group(1).toUpperCase()
      );
    }
    String upper = masked.toUpperCase();
    for (String phrase : new List<String>{ 'FOR UPDATE', 'ALL ROWS' }) {
      if (upper.contains(phrase)) {
        throw new TemplateException(
          'INVALID_SOQL_TEMPLATE',
          'SOQL contains disallowed phrase: ' + phrase
        );
      }
    }
    rejectSystemMode(soql);
  }

  /**
   * SCAN-03 / SCAN-43: rejects a `WITH SYSTEM_MODE` access level at ANY
   * parenthesis depth. SYSTEM_MODE bypasses the sharing rules and FLS that the
   * framework enforces via `WITH USER_MODE`, so an admin-authored template must
   * never request it — not at depth 0 and not inside a subquery. Relying on
   * Database.query to reject a nested SYSTEM_MODE (SCAN-43) is fragile and yields
   * an opaque error, so the keyword is forbidden everywhere. The literal mask
   * keeps the keyword inside a string value from being a false positive.
   */
  private static void rejectSystemMode(String soql) {
    if (String.isBlank(soql)) {
      return;
    }
    String masked = maskStringLiterals(soql);
    if (PATTERN_SYSTEM_MODE.matcher(masked).find()) {
      throw new TemplateException(
        'INVALID_SOQL_TEMPLATE',
        'SOQL access level WITH SYSTEM_MODE is not permitted; framework queries run WITH USER_MODE.'
      );
    }
  }

  /**
   * Injects WITH USER_MODE after the WHERE clause and before any depth-0 tail
   * clause (GROUP BY / ORDER BY / LIMIT / OFFSET). No-ops if a depth-0 WITH clause
   * already exists. Clauses inside subqueries (depth > 0) are ignored.
   */
  public static String injectUserMode(String soql) {
    if (String.isBlank(soql)) {
      return soql;
    }
    String masked = maskStringLiterals(soql);

    // Already has an outer WITH clause?
    if (firstDepth0Match(masked, PATTERN_WITH) >= 0) {
      return soql;
    }

    Integer insertAt = soql.length();
    for (Pattern tailPat : TAIL_CLAUSE_PATTERNS) {
      Integer idx = firstDepth0Match(masked, tailPat);
      if (idx >= 0 && idx < insertAt) {
        insertAt = idx;
      }
    }

    String beforeTail = soql.substring(0, insertAt).trim();
    String tail = soql.substring(insertAt).trim();
    return String.isBlank(tail)
      ? beforeTail + ' WITH USER_MODE'
      : beforeTail + ' WITH USER_MODE ' + tail;
  }

  /**
   * Returns a copy of the SOQL with every single-quoted string literal's contents
   * replaced by spaces (the quotes themselves kept). Length and every character
   * position are preserved so match indices map back onto the original. Escaped
   * quotes (\') inside a literal are handled.
   */
  public static String maskStringLiterals(String soql) {
    String masked = '';
    Boolean inQuote = false;
    Integer i = 0;
    while (i < soql.length()) {
      String ch = soql.substring(i, i + 1);
      if (inQuote) {
        if (ch == '\\' && i + 1 < soql.length()) {
          masked += '  '; // mask the backslash and the escaped character
          i += 2;
        } else if (ch == '\'') {
          masked += '\'';
          inQuote = false;
          i++;
        } else {
          masked += ' ';
          i++;
        }
      } else if (ch == '\'') {
        masked += '\'';
        inQuote = true;
        i++;
      } else {
        masked += ch;
        i++;
      }
    }
    return masked;
  }

  /** True if the query has a depth-0 aggregate function or GROUP BY. */
  public static Boolean isAggregateQuery(String soql) {
    if (String.isBlank(soql)) {
      return false;
    }
    String masked = maskStringLiterals(soql);
    return firstDepth0Match(masked, PATTERN_AGGREGATE_FUNC) >= 0 ||
      firstDepth0Match(masked, PATTERN_GROUP_BY) >= 0;
  }

  /** True only for a single scalar outer COUNT()/COUNT(Id) query without GROUP BY. */
  public static Boolean isScalarCountQuery(String soql) {
    if (String.isBlank(soql)) {
      return false;
    }
    String masked = maskStringLiterals(soql);
    if (firstDepth0Match(masked, PATTERN_GROUP_BY) >= 0) {
      return false;
    }
    return firstDepth0Match(masked, PATTERN_SCALAR_COUNT) >= 0;
  }

  // ─── Internal building blocks ───────────────────────────────────────────────

  /** Exactly one SELECT must appear at depth 0 (subquery SELECTs live at depth > 0). */
  @TestVisible
  private static void assertSingleOuterSelect(String soql) {
    String masked = maskStringLiterals(soql);
    Integer count = 0;
    Matcher m = PATTERN_SELECT.matcher(masked);
    while (m.find()) {
      if (depthAt(masked, m.start()) == 0) {
        count++;
      }
    }
    if (count == 0) {
      throw new TemplateException(
        'INVALID_SOQL_TEMPLATE',
        'SOQL has no outer SELECT.'
      );
    }
    if (count > 1) {
      throw new TemplateException(
        'INVALID_SOQL_TEMPLATE',
        'SOQL must contain a single outer SELECT; found ' + count + '.'
      );
    }
  }

  /** Rewrites a depth-0 bare SELECT COUNT() to SELECT COUNT(Id) so Database.query returns an AggregateResult. */
  @TestVisible
  private static String rewriteBareCount(String soql) {
    String masked = maskStringLiterals(soql);
    Matcher m = PATTERN_COUNT_EMPTY.matcher(masked);
    while (m.find()) {
      if (depthAt(masked, m.start()) == 0) {
        // Replace the matched span in the ORIGINAL string (masking preserves indices).
        return soql.substring(0, m.start()) +
          'SELECT COUNT(Id)' +
          soql.substring(m.end());
      }
    }
    return soql;
  }

  /**
   * Enforces an effective outer LIMIT no greater than `cap`:
   *   - pure aggregates (depth-0 aggregate, no depth-0 GROUP BY) get no LIMIT (illegal);
   *   - an existing depth-0 LIMIT greater than cap is lowered to cap;
   *   - otherwise a LIMIT of cap is added (before a depth-0 OFFSET if present).
   * Callers still probe with cap+1 by passing maxRows+1 — see the evaluators.
   */
  @TestVisible
  private static String enforceRowCap(String soql, Integer cap) {
    String masked = maskStringLiterals(soql);

    Boolean hasGroupBy = firstDepth0Match(masked, PATTERN_GROUP_BY) >= 0;
    Boolean hasAggregate =
      firstDepth0Match(masked, PATTERN_AGGREGATE_FUNC) >= 0;
    if (hasAggregate && !hasGroupBy) {
      // Pure aggregate — SOQL forbids LIMIT; leave as-is.
      return soql;
    }

    // Existing depth-0 LIMIT?
    Matcher limitMatcher = PATTERN_LIMIT.matcher(masked);
    while (limitMatcher.find()) {
      if (depthAt(masked, limitMatcher.start()) == 0) {
        Integer existing = Integer.valueOf(limitMatcher.group(1));
        if (existing <= cap) {
          return soql; // already within the cap
        }
        // Lower the oversized outer LIMIT to the cap.
        return soql.substring(0, limitMatcher.start()) +
          'LIMIT ' +
          cap +
          soql.substring(limitMatcher.end());
      }
    }

    // No outer LIMIT — add one, before a depth-0 OFFSET if present.
    Integer offsetAt = firstDepth0Match(masked, PATTERN_OFFSET);
    if (offsetAt >= 0) {
      String before = soql.substring(0, offsetAt).trim();
      String after = soql.substring(offsetAt).trim();
      return before + ' LIMIT ' + cap + ' ' + after;
    }
    return soql.trim() + ' LIMIT ' + cap;
  }

  /** Index of the first match of `pattern` that sits at parenthesis depth 0, or -1. */
  @TestVisible
  private static Integer firstDepth0Match(String masked, Pattern pattern) {
    Matcher m = pattern.matcher(masked);
    while (m.find()) {
      if (depthAt(masked, m.start()) == 0) {
        return m.start();
      }
    }
    return -1;
  }

  /** Parenthesis nesting depth at `index` in the (literal-masked) string. */
  @TestVisible
  private static Integer depthAt(String masked, Integer index) {
    Integer depth = 0;
    for (Integer i = 0; i < index && i < masked.length(); i++) {
      String c = masked.substring(i, i + 1);
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      }
    }
    return depth;
  }
}
