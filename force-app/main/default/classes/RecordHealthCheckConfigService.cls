/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

public with sharing class RecordHealthCheckConfigService {
  // ─── Reason codes (Section 4.3) ──────────────────────────────────────────

  public static final String RC_CONFIG_NOT_FOUND = 'CONFIG_NOT_FOUND';
  public static final String RC_CONFIG_INACTIVE = 'CONFIG_INACTIVE';
  public static final String RC_OBJECT_MISMATCH = 'OBJECT_MISMATCH';
  public static final String RC_NO_RECORD_CONTEXT = 'NO_RECORD_CONTEXT';
  public static final String RC_NO_ACTIVE_CHECKS = 'NO_ACTIVE_CHECKS';
  public static final String RC_UNABLE_TO_EVALUATE = 'UNABLE_TO_EVALUATE';
  public static final String RC_INVALID_CONFIG = 'INVALID_CONFIG';

  // Valid-value sets and caps are owned by RecordHealthCheckConstants so this
  // runtime validator and RecordHealthCheckMetadataValidator (deploy-time) can
  // never drift. Local aliases keep the call sites below readable.
  //
  // The per-type rule-validation decision tree lives in RecordHealthCheckRuleValidator;
  // this class keeps only the baseline checks below (inline) plus a first-fail adapter
  // (toResult). The comparator/source/null-empty value sets live with those producers.
  private static final Set<String> VALID_DISPLAY_MODES = RecordHealthCheckConstants.VALID_DISPLAY_MODES;
  private static final Set<String> VALID_TRIGGER_MODES = RecordHealthCheckConstants.VALID_TRIGGER_MODES;
  private static final Set<String> VALID_REVEAL_MODES = RecordHealthCheckConstants.VALID_REVEAL_MODES;
  private static final Set<String> VALID_APPLICABILITY_MODES = RecordHealthCheckConstants.VALID_APPLICABILITY_MODES;
  private static final Set<String> VALID_CHECK_TYPES = RecordHealthCheckConstants.VALID_CHECK_TYPES;
  private static final Set<String> VALID_SEVERITIES = RecordHealthCheckConstants.VALID_SEVERITIES;

  private static final Integer FRAMEWORK_MAX_CHECKS = RecordHealthCheckConstants.FRAMEWORK_MAX_CHECKS;
  private static final Integer FRAMEWORK_MAX_ROWS = RecordHealthCheckConstants.FRAMEWORK_MAX_ROWS;

  // ─── Component-level exception ────────────────────────────────────────────

  public class ConfigException extends Exception {
    public String reasonCode;
    public ConfigException(String message, String reasonCode) {
      this(message);
      this.reasonCode = reasonCode;
    }
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  /**
   * Loads and validates a Check Set and its active rules.
   * Throws ConfigException for component-level failures (CONFIG_NOT_FOUND,
   * CONFIG_INACTIVE, OBJECT_MISMATCH, NO_RECORD_CONTEXT, NO_ACTIVE_CHECKS).
   * Returns a fully populated RecordHealthCheckDefinitionResponse on success.
   */
  public RecordHealthCheckDefinitionResponse getDefinitionResponse(
    String configName,
    Id recordId
  ) {
    // Normalize at the service boundary so whitespace/blank is rejected before SOQL;
    // blank → CONFIG_NOT_FOUND.
    configName = RecordHealthCheckLogger.normalizeIdentifier(configName, 80);
    if (String.isBlank(configName)) {
      throw new ConfigException(
        'Check Set Developer Name is required.',
        RC_CONFIG_NOT_FOUND
      );
    }

    if (recordId == null) {
      throw new ConfigException(
        'No record context provided.',
        RC_NO_RECORD_CONTEXT
      );
    }

    // Load Check Set
    List<Record_Health_Check_Set__mdt> checkSets = [
      SELECT
        DeveloperName,
        MasterLabel,
        PanelHeading__c,
        PanelSubheading__c,
        ObjectApiName__c,
        IsActive__c,
        RunChecksWhen__c,
        PassedChecksDisplay__c,
        SkippedChecksDisplay__c,
        RowAppearance__c,
        StopOnSystemError__c,
        DebugMode__c
      FROM Record_Health_Check_Set__mdt
      WHERE DeveloperName = :configName
      LIMIT 1
    ];

    if (checkSets.isEmpty()) {
      throw new ConfigException(
        'No Check Set found for configName: ' + configName,
        RC_CONFIG_NOT_FOUND
      );
    }

    Record_Health_Check_Set__mdt checkSet = checkSets[0];
    validateCheckSetForDefinition(checkSet, configName, recordId);

    // Load active rules — only the fields needed to build RecordHealthCheckDefinition.
    // Full evaluation fields are fetched per-rule at evaluation time via loadRule().
    List<Record_Health_Check_Rule__mdt> allRules = [
      SELECT
        DeveloperName,
        CheckName__c,
        Tooltip__c,
        RunOrder__c,
        RequiresCheck__c
      FROM Record_Health_Check_Rule__mdt
      WHERE
        Record_Health_Check_Set__r.DeveloperName = :configName
        AND IsActive__c = TRUE
      ORDER BY RunOrder__c ASC NULLS LAST, DeveloperName ASC
    ];

    validateActiveRulesForDefinition(allRules, configName);

    Integer totalAvailable = allRules.size();
    Boolean checksOmitted = totalAvailable > FRAMEWORK_MAX_CHECKS;
    List<Record_Health_Check_Rule__mdt> rulesForRun = selectRulesForRun(
      allRules
    );

    // Build response
    RecordHealthCheckDefinitionResponse response = new RecordHealthCheckDefinitionResponse();
    response.displayTitle = checkSet.PanelHeading__c;
    response.displayDescription = checkSet.PanelSubheading__c;
    response.triggerMode = checkSet.RunChecksWhen__c;
    response.revealMode = checkSet.RowAppearance__c;
    response.successDisplayMode = checkSet.PassedChecksDisplay__c;
    response.skippedDisplayMode = checkSet.SkippedChecksDisplay__c;
    response.stopOnFirstError = checkSet.StopOnSystemError__c;
    response.debugMode =
      checkSet.DebugMode__c == true &&
      RecordHealthCheckAccess.canViewDebugDetails();
    response.totalAvailableCheckCount = totalAvailable;
    response.checksOmittedByLimit = checksOmitted;

    // Emit WARN when active rules exceed FRAMEWORK_MAX_CHECKS, so truncation is
    // visible server-side and not only in the LWC "First 25 shown" badge.
    if (checksOmitted) {
      RecordHealthCheckLogger.log(
        RecordHealthCheckLogger.Level.WARN,
        null,
        configName,
        recordId,
        null,
        'CHECK_LIMIT_EXCEEDED',
        new Map<String, Object>{
          'totalAvailable' => totalAvailable,
          'maxPerRun' => FRAMEWORK_MAX_CHECKS,
          'omitted' => totalAvailable - FRAMEWORK_MAX_CHECKS
        },
        null
      );
    }

    response.checks = new List<RecordHealthCheckDefinition>();

    for (Record_Health_Check_Rule__mdt rule : rulesForRun) {
      RecordHealthCheckDefinition def = new RecordHealthCheckDefinition();
      def.developerName = rule.DeveloperName;
      def.label = rule.CheckName__c;
      def.description = rule.Tooltip__c;
      def.priority = rule.RunOrder__c;
      def.dependsOnCheckDeveloperName = String.isNotBlank(rule.RequiresCheck__c)
        ? rule.RequiresCheck__c.trim()
        : null;
      response.checks.add(def);
    }

    return response;
  }

  @TestVisible
  private void validateCheckSetForDefinition(
    Record_Health_Check_Set__mdt checkSet,
    String configName,
    Id recordId
  ) {
    if (checkSet.IsActive__c == false) {
      throw new ConfigException(
        'Check Set "' + configName + '" is inactive.',
        RC_CONFIG_INACTIVE
      );
    }

    if (String.isBlank(checkSet.ObjectApiName__c)) {
      // A blank Base Object is a misconfiguration of an existing Check Set, not a
      // missing Check Set — classify it as INVALID_CONFIG for consistency with the
      // non-existent-object branch below (L-RC-01).
      throw new ConfigException(
        'Check Set "' + configName + '" has a blank BaseObjectApiName.',
        RC_INVALID_CONFIG
      );
    }
    if (
      !RecordHealthCheckConfigValidator.isValidObjectApiName(
        checkSet.ObjectApiName__c
      )
    ) {
      throw new ConfigException(
        'Base Object API Name "' +
          checkSet.ObjectApiName__c +
          '" does not exist.',
        RC_INVALID_CONFIG
      );
    }

    String recordObjectType = recordId.getSObjectType().getDescribe().getName();
    if (!recordObjectType.equalsIgnoreCase(checkSet.ObjectApiName__c)) {
      throw new ConfigException(
        'Check Set targets "' +
          checkSet.ObjectApiName__c +
          '" but record is a "' +
          recordObjectType +
          '".',
        RC_OBJECT_MISMATCH
      );
    }

    if (!VALID_DISPLAY_MODES.contains(checkSet.PassedChecksDisplay__c)) {
      throw new ConfigException(
        'SuccessDisplayMode "' +
          checkSet.PassedChecksDisplay__c +
          '" is not recognized.',
        RC_INVALID_CONFIG
      );
    }
    if (!VALID_DISPLAY_MODES.contains(checkSet.SkippedChecksDisplay__c)) {
      throw new ConfigException(
        'SkippedDisplayMode "' +
          checkSet.SkippedChecksDisplay__c +
          '" is not recognized.',
        RC_INVALID_CONFIG
      );
    }
    if (!VALID_TRIGGER_MODES.contains(checkSet.RunChecksWhen__c)) {
      throw new ConfigException(
        'TriggerMode "' +
          checkSet.RunChecksWhen__c +
          '" is not recognized. Valid values: Automatic, Manual.',
        RC_INVALID_CONFIG
      );
    }
    if (!VALID_REVEAL_MODES.contains(checkSet.RowAppearance__c)) {
      throw new ConfigException(
        'RevealMode "' +
          checkSet.RowAppearance__c +
          '" is not recognized. Valid values: AllAtOnce, OneAtATime.',
        RC_INVALID_CONFIG
      );
    }
  }

  @TestVisible
  private void validateActiveRulesForDefinition(
    List<Record_Health_Check_Rule__mdt> rules,
    String configName
  ) {
    if (rules.isEmpty()) {
      throw new ConfigException(
        'Check Set "' + configName + '" has no active checks.',
        RC_NO_ACTIVE_CHECKS
      );
    }
  }

  @TestVisible
  private List<Record_Health_Check_Rule__mdt> selectRulesForRun(
    List<Record_Health_Check_Rule__mdt> allRules
  ) {
    List<Record_Health_Check_Rule__mdt> rulesForRun = new List<Record_Health_Check_Rule__mdt>();
    Integer rulesToInclude = Math.min(FRAMEWORK_MAX_CHECKS, allRules.size());
    for (Integer i = 0; i < rulesToInclude; i++) {
      rulesForRun.add(allRules[i]);
    }
    return rulesForRun;
  }

  /**
   * Validates a single rule's metadata configuration for runtime evaluation.
   * Returns a UNABLE_TO_EVALUATE RecordHealthCheckResult if the rule is invalid,
   * or null if the rule is valid and may proceed to the evaluator.
   */
  public RecordHealthCheckResult validateRuleForEvaluation(
    Record_Health_Check_Rule__mdt rule
  ) {
    if (String.isBlank(rule.CheckName__c) || rule.RunOrder__c == null) {
      return buildUnableResult(
        rule,
        RC_INVALID_CONFIG,
        'Label and Priority are required on every rule.'
      );
    }
    if (String.isBlank(rule.MessageWhenFailed__c)) {
      return buildUnableResult(
        rule,
        RC_INVALID_CONFIG,
        'Message When Failed is required on every rule.'
      );
    }
    // Unknown check type
    if (!VALID_CHECK_TYPES.contains(rule.CheckMethod__c)) {
      return buildUnableResult(
        rule,
        'INVALID_CHECK_TYPE',
        'Check Method "' + rule.CheckMethod__c + '" is not recognized.'
      );
    }

    // Severity required
    if (
      String.isBlank(rule.Severity__c) ||
      !VALID_SEVERITIES.contains(rule.Severity__c)
    ) {
      return buildUnableResult(
        rule,
        RC_INVALID_CONFIG,
        'Severity must be Error, Warning, or Info.'
      );
    }

    // ApplicabilityMode validation (null / blank == Always, which is valid)
    if (
      String.isNotBlank(rule.RunThisCheckWhen__c) &&
      !VALID_APPLICABILITY_MODES.contains(rule.RunThisCheckWhen__c)
    ) {
      return buildUnableResult(
        rule,
        'INVALID_CONFIG',
        'ApplicabilityMode "' +
          rule.RunThisCheckWhen__c +
          '" is not recognized. Valid values: Always, Formula, SOQL.'
      );
    }

    // Applicability sub-field validation — surface a misconfigured gate here as a
    // clear config error rather than letting the engine reach it at evaluation time.
    RecordHealthCheckResult applicabilityIssue = validateApplicability(rule);
    if (applicabilityIssue != null) {
      return applicabilityIssue;
    }

    // Per-type required-field validation
    if (rule.CheckMethod__c == 'Formula') {
      return validateFormulaRule(rule);
    } else if (rule.CheckMethod__c == 'Query') {
      return validateQueryRule(rule);
    } else if (rule.CheckMethod__c == 'Apex') {
      return validateApexRule(rule);
    } else if (rule.CheckMethod__c == 'CompareTwoQueries') {
      return validateDualSoqlRule(rule);
    }

    return null;
  }

  /**
   * Loads a single rule by DeveloperName, scoped to the named Check Set.
   * Returns null if the rule is not found, inactive, or does not belong to
   * the specified Check Set — preventing evaluation of unauthorized rules.
   * Also fetches check set fields needed for object-type validation in the engine.
   */
  public Record_Health_Check_Rule__mdt loadRule(
    String checkDeveloperName,
    String configName
  ) {
    List<Record_Health_Check_Rule__mdt> rules = [
      SELECT
        DeveloperName,
        MasterLabel,
        CheckName__c,
        Tooltip__c,
        RunOrder__c,
        IsActive__c,
        CheckMethod__c,
        Severity__c,
        PassFailFormula__c,
        FoundValueFormula__c,
        ExpectedValueFormula__c,
        ValueToTest__c,
        ScalarFormulaReturnType__c,
        DataQuery__c,
        FieldToRead__c,
        CompareAgainst__c,
        FixedValue__c,
        RecordFormulaValue__c,
        CompareToQuery__c,
        CompareToField__c,
        Operator__c,
        WhenMultipleRows__c,
        WhenZeroRows__c,
        WhenValueIsEmpty__c,
        MessageWhenFailed__c,
        MessageWhenCannotRun__c,
        ApexClass__c,
        ApexSettingsJson__c,
        MaxRows__c,
        RequiresCheck__c,
        RunThisCheckWhen__c,
        RunWhenFormula__c,
        RunWhenCountQuery__c,
        CountOperator__c,
        CountThreshold__c,
        Record_Health_Check_Set__c,
        Record_Health_Check_Set__r.IsActive__c,
        Record_Health_Check_Set__r.ObjectApiName__c,
        Record_Health_Check_Set__r.DebugMode__c
      FROM Record_Health_Check_Rule__mdt
      WHERE
        DeveloperName = :checkDeveloperName
        AND Record_Health_Check_Set__r.DeveloperName = :configName
        AND IsActive__c = TRUE
      LIMIT 1
    ];
    return rules.isEmpty() ? null : rules[0];
  }

  // ─── Per-type validation — first-fail adapter over RecordHealthCheckRuleValidator ───
  //
  // The per-type decision tree lives in RecordHealthCheckRuleValidator; these wrappers take
  // the FIRST finding (first-fail order) and map it via toResult. MaxRows and null/empty-behavior
  // are appended only for Query / CompareTwoQueries.

  /**
   * Validates the ApplicabilityMode gate (Formula / SOQL sub-fields). Returns null when the
   * gate is well-formed (or mode is Always/blank). Kept @TestVisible for parity with prior API.
   */
  @TestVisible
  private RecordHealthCheckResult validateApplicability(
    Record_Health_Check_Rule__mdt rule
  ) {
    return firstResult(
      RecordHealthCheckRuleValidator.applicabilityFindings(rule),
      rule
    );
  }

  private RecordHealthCheckResult validateFormulaRule(
    Record_Health_Check_Rule__mdt rule
  ) {
    return firstResult(
      RecordHealthCheckRuleValidator.formulaFindings(rule),
      rule
    );
  }

  private RecordHealthCheckResult validateQueryRule(
    Record_Health_Check_Rule__mdt rule
  ) {
    List<RecordHealthCheckRuleValidator.Finding> findings = RecordHealthCheckRuleValidator.queryFindings(
      rule
    );
    findings.addAll(RecordHealthCheckRuleValidator.maxRowsFindings(rule));
    findings.addAll(RecordHealthCheckRuleValidator.nullEmptyFindings(rule));
    return firstResult(findings, rule);
  }

  private RecordHealthCheckResult validateApexRule(
    Record_Health_Check_Rule__mdt rule
  ) {
    return firstResult(RecordHealthCheckRuleValidator.apexFindings(rule), rule);
  }

  private RecordHealthCheckResult validateDualSoqlRule(
    Record_Health_Check_Rule__mdt rule
  ) {
    List<RecordHealthCheckRuleValidator.Finding> findings = RecordHealthCheckRuleValidator.dualFindings(
      rule
    );
    findings.addAll(RecordHealthCheckRuleValidator.maxRowsFindings(rule));
    findings.addAll(RecordHealthCheckRuleValidator.nullEmptyFindings(rule));
    return firstResult(findings, rule);
  }

  private RecordHealthCheckResult firstResult(
    List<RecordHealthCheckRuleValidator.Finding> findings,
    Record_Health_Check_Rule__mdt rule
  ) {
    return findings.isEmpty() ? null : toResult(findings[0], rule);
  }

  /**
   * Maps a shared Finding to this runtime path's UNABLE_TO_EVALUATE reason code and detail
   * message. This switch is the ONLY place the runtime output vocabulary lives — the decision
   * tree that produced the finding is shared. Reason codes and messages here are byte-for-byte
   * the originals so the engine and every pinned test see identical results.
   */
  private RecordHealthCheckResult toResult(
    RecordHealthCheckRuleValidator.Finding finding,
    Record_Health_Check_Rule__mdt rule
  ) {
    String val = finding.offendingValue;
    switch on finding.code {
      // ── Applicability gate ──
      when APPLICABILITY_FORMULA_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_FORMULA',
          'Applicability Formula is required when Applicability Mode is Formula.'
        );
      }
      when APPLICABILITY_SOQL_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_SOQL_TEMPLATE',
          'Applicability SOQL is required when Applicability Mode is SOQL.'
        );
      }
      when APPLICABILITY_SOQL_NOT_SCALAR {
        return buildUnableResult(
          rule,
          'INVALID_SOQL_TEMPLATE',
          'Applicability SOQL must be one scalar COUNT() or COUNT(Id) query without GROUP BY.'
        );
      }
      when APPLICABILITY_COMPARATOR_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_COMPARATOR',
          'Applicability Comparator is required when Applicability Mode is SOQL.'
        );
      }
      when APPLICABILITY_COMPARATOR_INVALID {
        return buildUnableResult(
          rule,
          'INVALID_COMPARATOR',
          'Applicability Comparator "' +
            val +
            '" is not recognized. Valid values: Equals, NotEquals, GreaterThan, GreaterThanOrEqual, LessThan, LessThanOrEqual.'
        );
      }
      when APPLICABILITY_THRESHOLD_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_CONFIG',
          'Applicability Comparison Value is required when Applicability Mode is SOQL.'
        );
      }
      // ── Formula ──
      when FORMULA_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_FORMULA',
          'Formula checks require Formula to be populated.'
        );
      }
      // ── Query (single) ──
      when LIST_VALUE_TO_TEST_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_FORMULA',
          'ListContainsAny and ListDoesNotContainAny require Value To Test to provide the primary value.'
        );
      }
      when LIST_COMPARE_QUERY_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_SOQL_TEMPLATE',
          'ListContainsAny and ListDoesNotContainAny require Comparison Query to provide the list.'
        );
      }
      when LIST_COMPARE_FIELD_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_SOQL_TEMPLATE',
          'Comparison Query Field is required for list comparison queries.'
        );
      }
      when PRIMARY_QUERY_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_SOQL_TEMPLATE',
          'Query checks require Primary Query to be populated.'
        );
      }
      when PRIMARY_QUERY_FIELD_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_SOQL_TEMPLATE',
          'Primary Query Field is required for non-aggregate queries.'
        );
      }
      when DUAL_COMPARATOR_ON_SINGLE {
        return buildUnableResult(
          rule,
          'INVALID_COMPARATOR',
          'Operator "' + val + '" requires Check Method Compare two queries.'
        );
      }
      when COMPARATOR_INVALID {
        return buildUnableResult(
          rule,
          'INVALID_COMPARATOR',
          'Comparator "' + val + '" is not recognized.'
        );
      }
      when COMPARATOR_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_COMPARATOR',
          'Comparator is required for Query checks.'
        );
      }
      when MULTI_ROWS_MISSING {
        return buildUnableResult(
          rule,
          RC_UNABLE_TO_EVALUATE,
          'Multiple Records Handling is required for Query checks.'
        );
      }
      when MULTI_ROWS_INVALID {
        return buildUnableResult(
          rule,
          RC_INVALID_CONFIG,
          'Multiple Records Handling "' + val + '" is not recognized.'
        );
      }
      when COMPARE_AS_LISTS_ON_SINGLE {
        return buildUnableResult(
          rule,
          'INVALID_COMPARATOR',
          'Compare as two lists requires Check Method Compare two queries, not Single query.'
        );
      }
      when COMPARE_AGAINST_MISSING {
        return buildUnableResult(
          rule,
          RC_UNABLE_TO_EVALUATE,
          'Comparison Value Source is required for Query checks except IsBlank/IsNotBlank.'
        );
      }
      when COMPARE_AGAINST_INVALID {
        return buildUnableResult(
          rule,
          RC_INVALID_CONFIG,
          'Comparison Value Source "' + val + '" is not recognized.'
        );
      }
      when FIXED_VALUE_MISSING {
        return buildUnableResult(
          rule,
          RC_UNABLE_TO_EVALUATE,
          'Comparison Value is required when Comparison Value Source is Static Value.'
        );
      }
      when RECORD_FORMULA_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_FORMULA',
          'Comparison Formula is required when Comparison Value Source is Formula Result.'
        );
      }
      when ANOTHER_QUERY_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_SOQL_TEMPLATE',
          'Comparison Query is required when Comparison Value Source is Query Result.'
        );
      }
      when ANOTHER_QUERY_FIELD_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_SOQL_TEMPLATE',
          'Comparison Query Field is required for non-aggregate comparison queries.'
        );
      }
      // ── CompareTwoQueries (dual) ──
      when DUAL_PRIMARY_QUERY_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_SOQL_TEMPLATE',
          'CompareTwoQueries checks require Primary Query to be populated.'
        );
      }
      when DUAL_COMPARE_QUERY_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_SOQL_TEMPLATE',
          'CompareTwoQueries checks require Comparison Query to be populated.'
        );
      }
      when DUAL_PRIMARY_FIELD_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_SOQL_TEMPLATE',
          'Primary Query Field is required for non-aggregate primary queries.'
        );
      }
      when DUAL_COMPARE_FIELD_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_SOQL_TEMPLATE',
          'Comparison Query Field is required for non-aggregate comparison queries.'
        );
      }
      when DUAL_COMPARATOR_MISSING {
        return buildUnableResult(
          rule,
          'INVALID_COMPARATOR',
          'Comparator is required for CompareTwoQueries checks.'
        );
      }
      when DUAL_COMPARATOR_INVALID {
        return buildUnableResult(
          rule,
          'INVALID_COMPARATOR',
          'Comparator "' + val + '" is not recognized.'
        );
      }
      when DUAL_MULTI_ROWS_MISSING {
        return buildUnableResult(
          rule,
          RC_UNABLE_TO_EVALUATE,
          'Multiple Records Handling is required for CompareTwoQueries checks.'
        );
      }
      when DUAL_MULTI_ROWS_INVALID {
        return buildUnableResult(
          rule,
          'INVALID_COMPARATOR',
          'CompareTwoQueries requires Multiple Records Handling of OneResult or CompareAsLists.'
        );
      }
      when DUAL_LIST_MODE_NEEDS_LIST_COMPARATOR {
        return buildUnableResult(
          rule,
          'INVALID_COMPARATOR',
          'CompareAsLists mode requires a list comparator: ListsOverlap, ListContainsAll, or ExactListMatch.'
        );
      }
      when DUAL_ONE_RESULT_NO_LIST_COMPARATOR {
        return buildUnableResult(
          rule,
          'INVALID_COMPARATOR',
          'List comparators (ListsOverlap, ListContainsAll, ExactListMatch) require CompareAsLists mode.'
        );
      }
      // ── Apex ──
      when APEX_CLASS_MISSING {
        return buildUnableResult(
          rule,
          'APEX_CLASS_NOT_FOUND',
          'Apex checks require Apex Class Name to be populated.'
        );
      }
      when APEX_CLASS_INVALID {
        return buildUnableResult(
          rule,
          'APEX_CLASS_NOT_FOUND',
          'Apex Class Name must identify an instantiable class implementing RecordHealthCheckRule.'
        );
      }
      when APEX_PARAMS_INVALID {
        return buildUnableResult(
          rule,
          'INVALID_APEX_PARAMETERS',
          'Apex Parameters must contain valid JSON object syntax.'
        );
      }
      // ── Cross-type ──
      when MAX_ROWS_INVALID {
        return buildUnableResult(
          rule,
          'GOVERNOR_LIMIT_RISK',
          'Max Rows Override must be a whole number between 1 and ' +
            FRAMEWORK_MAX_ROWS +
            '.'
        );
      }
      when NULL_BEHAVIOR_INVALID {
        return buildUnableResult(
          rule,
          'INVALID_CONFIG',
          'NullBehavior "' +
            val +
            '" is not recognized. Valid values: MissingMeansNoMatch, SkipRecordsWithMissingValue, TreatMissingAsBlank.'
        );
      }
      when EMPTY_BEHAVIOR_INVALID {
        return buildUnableResult(
          rule,
          'INVALID_CONFIG',
          'EmptyResultBehavior "' +
            val +
            '" is not recognized. Valid values: Pass, Fail, Skip, UnableToEvaluate.'
        );
      }
      when else {
        // Every FindingCode is mapped above; this is defensive only.
        return buildUnableResult(
          rule,
          RC_INVALID_CONFIG,
          'This check could not be evaluated. Contact your administrator.'
        );
      }
    }
  }

  // ─── Result builder ───────────────────────────────────────────────────────

  private RecordHealthCheckResult buildUnableResult(
    Record_Health_Check_Rule__mdt rule,
    String reasonCode,
    String detail
  ) {
    RecordHealthCheckResult r = new RecordHealthCheckResult();
    r.checkDeveloperName = rule.DeveloperName;
    r.label = rule.CheckName__c;
    r.status = 'UNABLE_TO_EVALUATE';
    r.reasonCode = reasonCode;
    r.detailMessage = detail;
    r.evaluatorType = rule.CheckMethod__c;
    r.priority = rule.RunOrder__c;
    r.message = String.isNotBlank(rule.MessageWhenCannotRun__c)
      ? rule.MessageWhenCannotRun__c
      : 'This check could not be evaluated. Contact your administrator.';
    return r;
  }
}
