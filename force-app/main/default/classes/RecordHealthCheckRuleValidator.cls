/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Shared rule-validation decision tree for Record Health Check.
 *
 * AUDIT (Q-01 / IMP-01 / D1, 2026-06-23):
 * BEFORE: RecordHealthCheckConfigService (runtime, first-fail → RecordHealthCheckResult)
 *   and RecordHealthCheckMetadataValidator (deploy-time, collect-all → ValidationIssue)
 *   each carried a near-identical ~800-line copy of the per-type query/dual/applicability/
 *   formula/apex/MaxRows/null-empty validation logic, kept in sync only by discipline.
 * AFTER: the decision tree lives here exactly once. Producers emit neutral Findings in a
 *   single canonical order (= ConfigService's historical first-fail order). Each caller maps
 *   FindingCode → its own output contract:
 *     - ConfigService takes findings[0] (first failure) and maps via toResult(...).
 *     - MetadataValidator collects every finding and maps via toIssue(...).
 *   The per-class reason codes / messages / field names — the intentional divergence between
 *   the two paths — now live only in those two mapping tables, not in the branching logic.
 *
 * Scope note: the small "baseline" checks (Label, Priority, Message When Failed, Check Method,
 * Severity, Applicability Mode) deliberately stay inline in each caller. They have genuinely
 * divergent ordering, granularity (ConfigService combines Label+Priority into one message), and
 * short-circuit semantics (MetadataValidator validates Severity/Message before its terminating
 * bad-Check-Method return). Sharing them would risk a subtle per-rule output change, so only the
 * per-type tree below — the bulk of the duplication — is extracted.
 *
 * MaxRows and null/empty-behavior are standalone producers because the two callers scope them
 * differently: ConfigService checks them only for Query/CompareTwoQueries; MetadataValidator
 * checks them once at top level for all types. Keeping them separate lets each caller compose
 * them where it always has, with no double-counting and no new findings on the runtime path.
 */
public with sharing class RecordHealthCheckRuleValidator {
  // Valid-value sets are owned by RecordHealthCheckConstants so this validator and its two
  // callers can never drift. Local aliases keep the producers below readable.
  private static final Set<String> VALID_COMPARATORS = RecordHealthCheckConstants.VALID_COMPARATORS;
  private static final Set<String> DUAL_QUERY_COMPARATORS = RecordHealthCheckConstants.DUAL_QUERY_COMPARATORS;
  private static final Set<String> VALID_COMPARISON_VALUE_SOURCES = RecordHealthCheckConstants.VALID_COMPARISON_VALUE_SOURCES;
  private static final Set<String> VALID_MULTIPLE_RECORDS_HANDLING = RecordHealthCheckConstants.VALID_MULTIPLE_RECORDS_HANDLING;
  private static final Set<String> VALID_NULL_BEHAVIORS = RecordHealthCheckConstants.VALID_NULL_BEHAVIORS;
  private static final Set<String> VALID_EMPTY_BEHAVIORS = RecordHealthCheckConstants.VALID_EMPTY_BEHAVIORS;
  private static final Set<String> VALID_APPLICABILITY_COMPARATORS = RecordHealthCheckConstants.VALID_APPLICABILITY_COMPARATORS;
  private static final Integer FRAMEWORK_MAX_ROWS = RecordHealthCheckConstants.FRAMEWORK_MAX_ROWS;

  // ─── Finding model ────────────────────────────────────────────────────────

  /**
   * One distinct validation condition across both callers. The enum is the single source of
   * truth for "what is invalid"; the per-caller mapping tables turn each code into a reason
   * code, message, and (deploy-time only) field name.
   */
  public enum FindingCode {
    // Applicability gate
    APPLICABILITY_FORMULA_MISSING,
    APPLICABILITY_SOQL_MISSING,
    APPLICABILITY_SOQL_NOT_SCALAR,
    APPLICABILITY_COMPARATOR_MISSING,
    APPLICABILITY_COMPARATOR_INVALID,
    APPLICABILITY_THRESHOLD_MISSING,
    // Formula
    FORMULA_MISSING,
    // Query (single)
    LIST_VALUE_TO_TEST_MISSING,
    LIST_COMPARE_QUERY_MISSING,
    LIST_COMPARE_FIELD_MISSING,
    PRIMARY_QUERY_MISSING,
    PRIMARY_QUERY_FIELD_MISSING,
    DUAL_COMPARATOR_ON_SINGLE,
    COMPARATOR_INVALID,
    COMPARATOR_MISSING,
    MULTI_ROWS_MISSING,
    MULTI_ROWS_INVALID,
    COMPARE_AS_LISTS_ON_SINGLE,
    COMPARE_AGAINST_MISSING,
    COMPARE_AGAINST_INVALID,
    FIXED_VALUE_MISSING,
    RECORD_FORMULA_MISSING,
    ANOTHER_QUERY_MISSING,
    ANOTHER_QUERY_FIELD_MISSING,
    // CompareTwoQueries (dual)
    DUAL_PRIMARY_QUERY_MISSING,
    DUAL_COMPARE_QUERY_MISSING,
    DUAL_PRIMARY_FIELD_MISSING,
    DUAL_COMPARE_FIELD_MISSING,
    DUAL_COMPARATOR_MISSING,
    DUAL_COMPARATOR_INVALID,
    DUAL_MULTI_ROWS_MISSING,
    DUAL_MULTI_ROWS_INVALID,
    DUAL_LIST_MODE_NEEDS_LIST_COMPARATOR,
    DUAL_ONE_RESULT_NO_LIST_COMPARATOR,
    // Apex
    APEX_CLASS_MISSING,
    APEX_CLASS_INVALID,
    APEX_PARAMS_INVALID,
    // Cross-type
    MAX_ROWS_INVALID,
    NULL_BEHAVIOR_INVALID,
    EMPTY_BEHAVIOR_INVALID
  }

  /**
   * A single validation hit. `offendingValue` carries the field value to interpolate into the
   * "...\"x\" is not recognized." messages; it is null for findings whose message is fixed.
   */
  public class Finding {
    public FindingCode code;
    public String offendingValue;
    public Finding(FindingCode code, String offendingValue) {
      this.code = code;
      this.offendingValue = offendingValue;
    }
  }

  private static Finding f(FindingCode code) {
    return new Finding(code, null);
  }

  private static Finding f(FindingCode code, String offendingValue) {
    return new Finding(code, offendingValue);
  }

  // ─── Shared comparator predicates ─────────────────────────────────────────

  public static Boolean isListComparator(String operator) {
    return operator == 'ListContainsAny' || operator == 'ListDoesNotContainAny';
  }

  public static Boolean isUnaryComparator(String operator) {
    return operator == 'IsBlank' || operator == 'IsNotBlank';
  }

  public static Boolean isMaxRowsInvalid(Decimal maxRows) {
    return maxRows != null &&
      (maxRows <= 0 ||
      maxRows > FRAMEWORK_MAX_ROWS ||
      maxRows != maxRows.intValue());
  }

  // ─── Applicability gate ───────────────────────────────────────────────────

  /**
   * Sub-field validation for the Applicability Mode gate:
   *   Formula → RunWhenFormula__c required
   *   SOQL    → RunWhenCountQuery__c required + scalar COUNT, CountOperator__c a recognized
   *             count comparator, CountThreshold__c present.
   * Findings are emitted in ConfigService's historical order.
   */
  public static List<Finding> applicabilityFindings(
    Record_Health_Check_Rule__mdt rule
  ) {
    List<Finding> out = new List<Finding>();
    if (rule.RunThisCheckWhen__c == 'Formula') {
      if (String.isBlank(rule.RunWhenFormula__c)) {
        out.add(f(FindingCode.APPLICABILITY_FORMULA_MISSING));
      }
    } else if (rule.RunThisCheckWhen__c == 'SOQL') {
      if (String.isBlank(rule.RunWhenCountQuery__c)) {
        out.add(f(FindingCode.APPLICABILITY_SOQL_MISSING));
      } else if (
        !RecordHealthCheckSoqlTemplate.isScalarCountQuery(
          rule.RunWhenCountQuery__c
        )
      ) {
        out.add(f(FindingCode.APPLICABILITY_SOQL_NOT_SCALAR));
      }
      if (String.isBlank(rule.CountOperator__c)) {
        out.add(f(FindingCode.APPLICABILITY_COMPARATOR_MISSING));
      } else if (
        !VALID_APPLICABILITY_COMPARATORS.contains(rule.CountOperator__c)
      ) {
        out.add(
          f(FindingCode.APPLICABILITY_COMPARATOR_INVALID, rule.CountOperator__c)
        );
      }
      if (rule.CountThreshold__c == null) {
        out.add(f(FindingCode.APPLICABILITY_THRESHOLD_MISSING));
      }
    }
    return out;
  }

  // ─── Per-type producers ───────────────────────────────────────────────────

  public static List<Finding> formulaFindings(
    Record_Health_Check_Rule__mdt rule
  ) {
    List<Finding> out = new List<Finding>();
    if (String.isBlank(rule.PassFailFormula__c)) {
      out.add(f(FindingCode.FORMULA_MISSING));
    }
    return out;
  }

  public static List<Finding> apexFindings(Record_Health_Check_Rule__mdt rule) {
    List<Finding> out = new List<Finding>();
    if (String.isBlank(rule.ApexClass__c)) {
      out.add(f(FindingCode.APEX_CLASS_MISSING));
    } else if (
      !RecordHealthCheckConfigValidator.isValidApexPlugin(rule.ApexClass__c)
    ) {
      out.add(f(FindingCode.APEX_CLASS_INVALID));
    }
    if (
      !RecordHealthCheckConfigValidator.isJsonObject(rule.ApexSettingsJson__c)
    ) {
      out.add(f(FindingCode.APEX_PARAMS_INVALID));
    }
    return out;
  }

  /**
   * Single-Query checks, in ConfigService's first-fail order. Mutually-exclusive condition
   * groups (operator, multiple-rows-handling, comparison-value-source) use if/else-if so the
   * collect-all caller never doubles up, and the isNotBlank(...) guards on the *-FIELD-MISSING
   * findings are no-ops for the first-fail caller (which returns before reaching them).
   * MaxRows and null/empty are NOT included here — callers compose those separately.
   */
  public static List<Finding> queryFindings(
    Record_Health_Check_Rule__mdt rule
  ) {
    List<Finding> out = new List<Finding>();
    Boolean isList = isListComparator(rule.Operator__c);
    Boolean isUnary = isUnaryComparator(rule.Operator__c);

    // Primary value source: ValueToTest__c for list comparators, else DataQuery__c.
    if (isList) {
      if (String.isBlank(rule.ValueToTest__c)) {
        out.add(f(FindingCode.LIST_VALUE_TO_TEST_MISSING));
      }
      if (String.isBlank(rule.CompareToQuery__c)) {
        out.add(f(FindingCode.LIST_COMPARE_QUERY_MISSING));
      }
      if (String.isBlank(rule.CompareToField__c)) {
        out.add(f(FindingCode.LIST_COMPARE_FIELD_MISSING));
      }
    } else {
      if (String.isBlank(rule.DataQuery__c)) {
        out.add(f(FindingCode.PRIMARY_QUERY_MISSING));
      }
      if (
        String.isNotBlank(rule.DataQuery__c) &&
        String.isBlank(rule.FieldToRead__c) &&
        !RecordHealthCheckSoqlTemplate.isAggregateQuery(rule.DataQuery__c)
      ) {
        out.add(f(FindingCode.PRIMARY_QUERY_FIELD_MISSING));
      }
    }

    // Comparator — at most one finding (mutually exclusive by value).
    if (String.isBlank(rule.Operator__c)) {
      out.add(f(FindingCode.COMPARATOR_MISSING));
    } else if (DUAL_QUERY_COMPARATORS.contains(rule.Operator__c)) {
      out.add(f(FindingCode.DUAL_COMPARATOR_ON_SINGLE, rule.Operator__c));
    } else if (!VALID_COMPARATORS.contains(rule.Operator__c)) {
      out.add(f(FindingCode.COMPARATOR_INVALID, rule.Operator__c));
    }

    // Multiple Records Handling — at most one finding.
    if (String.isBlank(rule.WhenMultipleRows__c)) {
      out.add(f(FindingCode.MULTI_ROWS_MISSING));
    } else if (
      !VALID_MULTIPLE_RECORDS_HANDLING.contains(rule.WhenMultipleRows__c)
    ) {
      out.add(f(FindingCode.MULTI_ROWS_INVALID, rule.WhenMultipleRows__c));
    } else if (rule.WhenMultipleRows__c == 'CompareAsLists' && !isList) {
      out.add(f(FindingCode.COMPARE_AS_LISTS_ON_SINGLE));
    }

    // Comparison Value Source — required unless IsBlank/IsNotBlank or a list comparator.
    Boolean needsSource = !isUnary && !isList;
    if (needsSource && String.isBlank(rule.CompareAgainst__c)) {
      out.add(f(FindingCode.COMPARE_AGAINST_MISSING));
    } else if (
      needsSource &&
      !VALID_COMPARISON_VALUE_SOURCES.contains(rule.CompareAgainst__c)
    ) {
      out.add(f(FindingCode.COMPARE_AGAINST_INVALID, rule.CompareAgainst__c));
    }

    // Source-specific required fields.
    if (
      rule.CompareAgainst__c == 'FixedValue' &&
      String.isBlank(rule.FixedValue__c)
    ) {
      out.add(f(FindingCode.FIXED_VALUE_MISSING));
    }
    if (
      rule.CompareAgainst__c == 'RecordFormula' &&
      String.isBlank(rule.RecordFormulaValue__c)
    ) {
      out.add(f(FindingCode.RECORD_FORMULA_MISSING));
    }
    if (
      rule.CompareAgainst__c == 'AnotherQuery' &&
      String.isBlank(rule.CompareToQuery__c)
    ) {
      out.add(f(FindingCode.ANOTHER_QUERY_MISSING));
    }
    if (
      rule.CompareAgainst__c == 'AnotherQuery' &&
      String.isNotBlank(rule.CompareToQuery__c) &&
      String.isBlank(rule.CompareToField__c) &&
      !RecordHealthCheckSoqlTemplate.isAggregateQuery(rule.CompareToQuery__c)
    ) {
      out.add(f(FindingCode.ANOTHER_QUERY_FIELD_MISSING));
    }

    return out;
  }

  /**
   * CompareTwoQueries checks, in ConfigService's first-fail order. MaxRows and null/empty are
   * composed by callers, not included here.
   */
  public static List<Finding> dualFindings(Record_Health_Check_Rule__mdt rule) {
    List<Finding> out = new List<Finding>();

    if (String.isBlank(rule.DataQuery__c)) {
      out.add(f(FindingCode.DUAL_PRIMARY_QUERY_MISSING));
    }
    if (String.isBlank(rule.CompareToQuery__c)) {
      out.add(f(FindingCode.DUAL_COMPARE_QUERY_MISSING));
    }
    if (
      String.isNotBlank(rule.DataQuery__c) &&
      String.isBlank(rule.FieldToRead__c) &&
      !RecordHealthCheckSoqlTemplate.isAggregateQuery(rule.DataQuery__c)
    ) {
      out.add(f(FindingCode.DUAL_PRIMARY_FIELD_MISSING));
    }
    if (
      String.isNotBlank(rule.CompareToQuery__c) &&
      String.isBlank(rule.CompareToField__c) &&
      !RecordHealthCheckSoqlTemplate.isAggregateQuery(rule.CompareToQuery__c)
    ) {
      out.add(f(FindingCode.DUAL_COMPARE_FIELD_MISSING));
    }

    // Comparator — at most one finding.
    if (String.isBlank(rule.Operator__c)) {
      out.add(f(FindingCode.DUAL_COMPARATOR_MISSING));
    } else if (!VALID_COMPARATORS.contains(rule.Operator__c)) {
      out.add(f(FindingCode.DUAL_COMPARATOR_INVALID, rule.Operator__c));
    }

    // Multiple Records Handling — only OneResult / CompareAsLists are valid.
    if (String.isBlank(rule.WhenMultipleRows__c)) {
      out.add(f(FindingCode.DUAL_MULTI_ROWS_MISSING));
    } else if (
      rule.WhenMultipleRows__c != 'OneResult' &&
      rule.WhenMultipleRows__c != 'CompareAsLists'
    ) {
      out.add(f(FindingCode.DUAL_MULTI_ROWS_INVALID));
    }

    // Tier 9 (CompareAsLists) needs a list comparator; Tier 7 (OneResult) must not use one.
    // The isNotBlank(Operator) guards mirror MetadataValidator so a blank operator yields only
    // DUAL_COMPARATOR_MISSING; they are no-ops for the first-fail caller.
    if (
      rule.WhenMultipleRows__c == 'CompareAsLists' &&
      String.isNotBlank(rule.Operator__c) &&
      !DUAL_QUERY_COMPARATORS.contains(rule.Operator__c)
    ) {
      out.add(f(FindingCode.DUAL_LIST_MODE_NEEDS_LIST_COMPARATOR));
    }
    if (
      rule.WhenMultipleRows__c == 'OneResult' &&
      String.isNotBlank(rule.Operator__c) &&
      DUAL_QUERY_COMPARATORS.contains(rule.Operator__c)
    ) {
      out.add(f(FindingCode.DUAL_ONE_RESULT_NO_LIST_COMPARATOR));
    }

    return out;
  }

  // ─── Cross-type producers ─────────────────────────────────────────────────

  public static List<Finding> maxRowsFindings(
    Record_Health_Check_Rule__mdt rule
  ) {
    List<Finding> out = new List<Finding>();
    if (isMaxRowsInvalid(rule.MaxRows__c)) {
      out.add(f(FindingCode.MAX_ROWS_INVALID));
    }
    return out;
  }

  public static List<Finding> nullEmptyFindings(
    Record_Health_Check_Rule__mdt rule
  ) {
    List<Finding> out = new List<Finding>();
    if (
      String.isNotBlank(rule.WhenValueIsEmpty__c) &&
      !VALID_NULL_BEHAVIORS.contains(rule.WhenValueIsEmpty__c)
    ) {
      out.add(f(FindingCode.NULL_BEHAVIOR_INVALID, rule.WhenValueIsEmpty__c));
    }
    if (
      String.isNotBlank(rule.WhenZeroRows__c) &&
      !VALID_EMPTY_BEHAVIORS.contains(rule.WhenZeroRows__c)
    ) {
      out.add(f(FindingCode.EMPTY_BEHAVIOR_INVALID, rule.WhenZeroRows__c));
    }
    return out;
  }
}
