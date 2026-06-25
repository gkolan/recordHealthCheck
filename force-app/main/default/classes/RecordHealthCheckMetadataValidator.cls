/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

public with sharing class RecordHealthCheckMetadataValidator {
  // ─── Validation issue DTO ─────────────────────────────────────────────────

  public class ValidationIssue {
    public String severity; // ERROR, WARNING
    public String componentName; // DeveloperName of the CMT record
    public String fieldName; // field involved, null for cross-record issues
    public String message;
    public String reasonCode;

    public ValidationIssue(
      String severity,
      String componentName,
      String fieldName,
      String message,
      String reasonCode
    ) {
      this.severity = severity;
      this.componentName = componentName;
      this.fieldName = fieldName;
      this.message = message;
      this.reasonCode = reasonCode;
    }
  }

  // Valid-value sets and caps are owned by RecordHealthCheckConstants so this
  // deploy-time validator and RecordHealthCheckConfigService (runtime) can never
  // drift. Local aliases keep the call sites below readable.
  //
  // The per-type rule-validation decision tree lives in RecordHealthCheckRuleValidator;
  // this class keeps the baseline + Check Set + dependency-graph checks (inline) plus a
  // collect-all adapter (toIssue). The comparator/source/null-empty value sets live with
  // those producers.
  private static final Set<String> VALID_DISPLAY_MODES = RecordHealthCheckConstants.VALID_DISPLAY_MODES;
  private static final Set<String> VALID_TRIGGER_MODES = RecordHealthCheckConstants.VALID_TRIGGER_MODES;
  private static final Set<String> VALID_REVEAL_MODES = RecordHealthCheckConstants.VALID_REVEAL_MODES;
  private static final Set<String> VALID_APPLICABILITY_MODES = RecordHealthCheckConstants.VALID_APPLICABILITY_MODES;
  private static final Set<String> VALID_CHECK_TYPES = RecordHealthCheckConstants.VALID_CHECK_TYPES;
  private static final Set<String> VALID_SEVERITIES = RecordHealthCheckConstants.VALID_SEVERITIES;
  private static final Integer FRAMEWORK_MAX_ROWS = RecordHealthCheckConstants.FRAMEWORK_MAX_ROWS;

  // ─── Public API ───────────────────────────────────────────────────────────

  /**
   * Validates all active Check Sets and Rules in the org.
   * Returns a list of ValidationIssues — empty list means everything is valid.
   */
  public List<ValidationIssue> validate() {
    List<Record_Health_Check_Set__mdt> checkSets = [
      SELECT
        DeveloperName,
        MasterLabel,
        ObjectApiName__c,
        IsActive__c,
        RunChecksWhen__c,
        RowAppearance__c,
        PassedChecksDisplay__c,
        SkippedChecksDisplay__c,
        PanelHeading__c
      FROM Record_Health_Check_Set__mdt
      WHERE IsActive__c = TRUE
    ];

    List<Record_Health_Check_Rule__mdt> allRules = [
      SELECT
        DeveloperName,
        MasterLabel,
        CheckName__c,
        RunOrder__c,
        IsActive__c,
        CheckMethod__c,
        Severity__c,
        PassFailFormula__c,
        ValueToTest__c,
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
        ApexClass__c,
        ApexSettingsJson__c,
        MaxRows__c,
        RequiresCheck__c,
        RunThisCheckWhen__c,
        RunWhenFormula__c,
        RunWhenCountQuery__c,
        CountOperator__c,
        CountThreshold__c,
        Record_Health_Check_Set__c
      FROM Record_Health_Check_Rule__mdt
      WHERE IsActive__c = TRUE
      ORDER BY
        Record_Health_Check_Set__c ASC,
        RunOrder__c ASC NULLS LAST,
        DeveloperName ASC
    ];

    return validateRecordsForTest(checkSets, allRules);
  }

  /** Machine-readable entry point for setup tooling and CI. */
  // Not cacheable: callers always get fresh results, so validation never goes stale
  // after a metadata edit.
  @AuraEnabled
  public static String validateAsJson() {
    return JSON.serialize(new RecordHealthCheckMetadataValidator().validate());
  }

  @TestVisible
  private List<ValidationIssue> validateRecordsForTest(
    List<Record_Health_Check_Set__mdt> checkSets,
    List<Record_Health_Check_Rule__mdt> allRules
  ) {
    List<ValidationIssue> issues = new List<ValidationIssue>();

    // SCAN-49: removed an unused `checkSetDeveloperNames` Set that was populated
    // here but never read. Dependency validation scopes by Check Set Id below.
    for (Record_Health_Check_Set__mdt cs : checkSets) {
      issues.addAll(validateCheckSet(cs));
    }

    // Group rules by Check Set for dependency validation
    Map<String, List<Record_Health_Check_Rule__mdt>> rulesByCheckSet = new Map<String, List<Record_Health_Check_Rule__mdt>>();
    Map<String, Record_Health_Check_Rule__mdt> rulesByDevName = new Map<String, Record_Health_Check_Rule__mdt>();

    for (Record_Health_Check_Rule__mdt rule : allRules) {
      String csName = String.valueOf(rule.Record_Health_Check_Set__c);
      if (!rulesByCheckSet.containsKey(csName)) {
        rulesByCheckSet.put(csName, new List<Record_Health_Check_Rule__mdt>());
      }
      rulesByCheckSet.get(csName).add(rule);
      rulesByDevName.put(rule.DeveloperName, rule);
      issues.addAll(validateRule(rule));
    }

    // Dependency graph validation per Check Set
    for (String csName : rulesByCheckSet.keySet()) {
      List<Record_Health_Check_Rule__mdt> setRules = rulesByCheckSet.get(
        csName
      );
      if (setRules.size() > RecordHealthCheckConstants.FRAMEWORK_MAX_CHECKS) {
        issues.add(
          new ValidationIssue(
            'WARNING',
            csName,
            null,
            'Only the first ' +
              RecordHealthCheckConstants.FRAMEWORK_MAX_CHECKS +
              ' active rules are included in a run; remaining rules are omitted.',
            'CHECK_LIMIT_EXCEEDED'
          )
        );
        Set<String> included = new Set<String>();
        for (
          Integer i = 0;
          i < RecordHealthCheckConstants.FRAMEWORK_MAX_CHECKS;
          i++
        ) {
          included.add(setRules[i].DeveloperName);
        }
        for (
          Integer i = 0;
          i < RecordHealthCheckConstants.FRAMEWORK_MAX_CHECKS;
          i++
        ) {
          Record_Health_Check_Rule__mdt includedRule = setRules[i];
          if (
            String.isNotBlank(includedRule.RequiresCheck__c) &&
            !included.contains(includedRule.RequiresCheck__c.trim())
          ) {
            issues.add(
              new ValidationIssue(
                'WARNING',
                includedRule.DeveloperName,
                'RequiresCheck__c',
                'The dependency is outside the first-25 execution window, so this rule will be skipped.',
                'DEPENDENCY_NOT_IN_RUN'
              )
            );
          }
        }
      }
      issues.addAll(validateDependencyGraph(csName, setRules, rulesByDevName));
    }

    return issues;
  }

  // ─── Check Set validation ─────────────────────────────────────────────────

  private List<ValidationIssue> validateCheckSet(
    Record_Health_Check_Set__mdt cs
  ) {
    List<ValidationIssue> issues = new List<ValidationIssue>();

    if (String.isBlank(cs.ObjectApiName__c)) {
      issues.add(
        new ValidationIssue(
          'ERROR',
          cs.DeveloperName,
          'ObjectApiName__c',
          'Base Object API Name is required.',
          'MISSING_REQUIRED_FIELD'
        )
      );
    }
    if (
      String.isNotBlank(cs.ObjectApiName__c) &&
      !RecordHealthCheckConfigValidator.isValidObjectApiName(
        cs.ObjectApiName__c
      )
    ) {
      issues.add(
        new ValidationIssue(
          'ERROR',
          cs.DeveloperName,
          'ObjectApiName__c',
          'Object API Name does not identify an object in this org.',
          'INVALID_CONFIG'
        )
      );
    }

    if (String.isBlank(cs.PanelHeading__c)) {
      issues.add(
        new ValidationIssue(
          'ERROR',
          cs.DeveloperName,
          'PanelHeading__c',
          'Panel Heading is required.',
          'MISSING_REQUIRED_FIELD'
        )
      );
    }

    if (!VALID_DISPLAY_MODES.contains(cs.PassedChecksDisplay__c)) {
      issues.add(
        new ValidationIssue(
          'ERROR',
          cs.DeveloperName,
          'PassedChecksDisplay__c',
          'Passed Checks Display "' +
            cs.PassedChecksDisplay__c +
            '" is not recognized.',
          'INVALID_CONFIG'
        )
      );
    }

    if (!VALID_DISPLAY_MODES.contains(cs.SkippedChecksDisplay__c)) {
      issues.add(
        new ValidationIssue(
          'ERROR',
          cs.DeveloperName,
          'SkippedChecksDisplay__c',
          'Skipped Checks Display "' +
            cs.SkippedChecksDisplay__c +
            '" is not recognized.',
          'INVALID_CONFIG'
        )
      );
    }

    // Parity with RecordHealthCheckConfigService runtime validation so a Check
    // Set that deploys clean cannot still fail at definition-load time.
    if (!VALID_TRIGGER_MODES.contains(cs.RunChecksWhen__c)) {
      issues.add(
        new ValidationIssue(
          'ERROR',
          cs.DeveloperName,
          'RunChecksWhen__c',
          'Run Checks When "' +
            cs.RunChecksWhen__c +
            '" is not recognized. Valid values: Automatic, Manual.',
          'INVALID_CONFIG'
        )
      );
    }

    if (!VALID_REVEAL_MODES.contains(cs.RowAppearance__c)) {
      issues.add(
        new ValidationIssue(
          'ERROR',
          cs.DeveloperName,
          'RowAppearance__c',
          'Reveal Mode "' +
            cs.RowAppearance__c +
            '" is not recognized. Valid values: AllAtOnce, OneAtATime.',
          'INVALID_CONFIG'
        )
      );
    }

    return issues;
  }

  // ─── Rule validation ──────────────────────────────────────────────────────

  private List<ValidationIssue> validateRule(
    Record_Health_Check_Rule__mdt rule
  ) {
    List<ValidationIssue> issues = new List<ValidationIssue>();

    if (String.isBlank(rule.CheckName__c)) {
      issues.add(
        err(
          rule,
          'CheckName__c',
          'Label is required.',
          'MISSING_REQUIRED_FIELD'
        )
      );
    }
    if (rule.RunOrder__c == null) {
      issues.add(
        err(
          rule,
          'RunOrder__c',
          'Priority is required.',
          'MISSING_REQUIRED_FIELD'
        )
      );
    }
    if (
      String.isBlank(rule.Severity__c) ||
      !VALID_SEVERITIES.contains(rule.Severity__c)
    ) {
      issues.add(
        err(
          rule,
          'Severity__c',
          'Severity must be Error, Warning, or Info.',
          'INVALID_CONFIG'
        )
      );
    }
    if (String.isBlank(rule.MessageWhenFailed__c)) {
      issues.add(
        err(
          rule,
          'MessageWhenFailed__c',
          'Message When Failed is required.',
          'MISSING_REQUIRED_FIELD'
        )
      );
    }
    if (String.isBlank(rule.CheckMethod__c)) {
      issues.add(
        err(
          rule,
          'CheckMethod__c',
          'Check Method is required.',
          'MISSING_REQUIRED_FIELD'
        )
      );
      return issues; // can't validate further without CheckMethod
    }

    if (!VALID_CHECK_TYPES.contains(rule.CheckMethod__c)) {
      issues.add(
        err(
          rule,
          'CheckMethod__c',
          'Check Method "' + rule.CheckMethod__c + '" is not recognized.',
          'INVALID_CHECK_TYPE'
        )
      );
      return issues;
    }

    // ApplicabilityMode validation (null / blank == Always, which is valid)
    if (
      String.isNotBlank(rule.RunThisCheckWhen__c) &&
      !VALID_APPLICABILITY_MODES.contains(rule.RunThisCheckWhen__c)
    ) {
      issues.add(
        err(
          rule,
          'RunThisCheckWhen__c',
          'ApplicabilityMode "' +
            rule.RunThisCheckWhen__c +
            '" is not recognized. Valid values: Always, Formula, SOQL.',
          'INVALID_CONFIG'
        )
      );
    }

    // Applicability sub-field validation — parity with the runtime ConfigService
    // so a misconfigured gate is caught at deploy time, not first evaluation.
    issues.addAll(validateApplicability(rule));

    if (rule.CheckMethod__c == 'Formula') {
      issues.addAll(validateFormulaRule(rule));
    } else if (rule.CheckMethod__c == 'Query') {
      issues.addAll(validateQueryRule(rule));
    } else if (rule.CheckMethod__c == 'Apex') {
      issues.addAll(validateApexRule(rule));
    } else if (rule.CheckMethod__c == 'CompareTwoQueries') {
      issues.addAll(validateDualSoqlRule(rule));
    }

    // MaxRowsOverride (SCAN-20) + NullBehavior / EmptyResultBehavior — validated for ALL check
    // types at top level, exactly as before. Shared producers emit the findings; toIssue maps
    // each to this class's reason code / field.
    addIssues(
      issues,
      RecordHealthCheckRuleValidator.maxRowsFindings(rule),
      rule
    );
    addIssues(
      issues,
      RecordHealthCheckRuleValidator.nullEmptyFindings(rule),
      rule
    );

    return issues;
  }

  /** Maps each shared Finding to a ValidationIssue and appends it to `issues`. */
  private void addIssues(
    List<ValidationIssue> issues,
    List<RecordHealthCheckRuleValidator.Finding> findings,
    Record_Health_Check_Rule__mdt rule
  ) {
    for (RecordHealthCheckRuleValidator.Finding finding : findings) {
      issues.add(toIssue(finding, rule));
    }
  }

  // ─── Per-type validation — collect-all adapter over RecordHealthCheckRuleValidator ───
  //
  // The per-type decision tree lives in RecordHealthCheckRuleValidator; these wrappers collect
  // every finding and map each via toIssue. Issue order within a rule follows the shared
  // (ConfigService) ordering.

  private List<ValidationIssue> validateApplicability(
    Record_Health_Check_Rule__mdt rule
  ) {
    return toIssues(
      RecordHealthCheckRuleValidator.applicabilityFindings(rule),
      rule
    );
  }

  private List<ValidationIssue> validateFormulaRule(
    Record_Health_Check_Rule__mdt rule
  ) {
    return toIssues(RecordHealthCheckRuleValidator.formulaFindings(rule), rule);
  }

  private List<ValidationIssue> validateQueryRule(
    Record_Health_Check_Rule__mdt rule
  ) {
    return toIssues(RecordHealthCheckRuleValidator.queryFindings(rule), rule);
  }

  private List<ValidationIssue> validateApexRule(
    Record_Health_Check_Rule__mdt rule
  ) {
    return toIssues(RecordHealthCheckRuleValidator.apexFindings(rule), rule);
  }

  private List<ValidationIssue> validateDualSoqlRule(
    Record_Health_Check_Rule__mdt rule
  ) {
    return toIssues(RecordHealthCheckRuleValidator.dualFindings(rule), rule);
  }

  private List<ValidationIssue> toIssues(
    List<RecordHealthCheckRuleValidator.Finding> findings,
    Record_Health_Check_Rule__mdt rule
  ) {
    List<ValidationIssue> issues = new List<ValidationIssue>();
    addIssues(issues, findings, rule);
    return issues;
  }

  /**
   * Maps a shared Finding to this deploy-time path's ERROR ValidationIssue (field name, message,
   * reason code). This switch is the ONLY place MetadataValidator's output vocabulary lives — the
   * decision tree that produced the finding is shared. Field names / messages / reason codes here
   * are byte-for-byte the originals so packaged metadata still validates clean and the
   * reason-code-membership tests still pass.
   */
  private ValidationIssue toIssue(
    RecordHealthCheckRuleValidator.Finding finding,
    Record_Health_Check_Rule__mdt rule
  ) {
    String val = finding.offendingValue;
    switch on finding.code {
      // ── Applicability gate ──
      when APPLICABILITY_FORMULA_MISSING {
        return err(
          rule,
          'RunWhenFormula__c',
          'Applicability Formula is required when Applicability Mode is Formula.',
          'INVALID_FORMULA'
        );
      }
      when APPLICABILITY_SOQL_MISSING {
        return err(
          rule,
          'RunWhenCountQuery__c',
          'Applicability SOQL is required when Applicability Mode is SOQL.',
          'INVALID_SOQL_TEMPLATE'
        );
      }
      when APPLICABILITY_SOQL_NOT_SCALAR {
        return err(
          rule,
          'RunWhenCountQuery__c',
          'Applicability SOQL must be one scalar COUNT() or COUNT(Id) query without GROUP BY.',
          'INVALID_SOQL_TEMPLATE'
        );
      }
      when APPLICABILITY_COMPARATOR_MISSING {
        return err(
          rule,
          'CountOperator__c',
          'Applicability Comparator is required when Applicability Mode is SOQL.',
          'INVALID_COMPARATOR'
        );
      }
      when APPLICABILITY_COMPARATOR_INVALID {
        return err(
          rule,
          'CountOperator__c',
          'Applicability Comparator "' +
            val +
            '" is not recognized. Valid values: Equals, NotEquals, GreaterThan, GreaterThanOrEqual, LessThan, LessThanOrEqual.',
          'INVALID_COMPARATOR'
        );
      }
      when APPLICABILITY_THRESHOLD_MISSING {
        return err(
          rule,
          'CountThreshold__c',
          'Applicability Comparison Value is required when Applicability Mode is SOQL.',
          'MISSING_REQUIRED_FIELD'
        );
      }
      // ── Formula ──
      when FORMULA_MISSING {
        return err(
          rule,
          'PassFailFormula__c',
          'Formula is required for Formula checks.',
          'INVALID_FORMULA'
        );
      }
      // ── Query (single) ──
      when LIST_VALUE_TO_TEST_MISSING {
        return err(
          rule,
          'ValueToTest__c',
          'Value To Test is required as the primary value source for ListContainsAny/ListDoesNotContainAny.',
          'INVALID_FORMULA'
        );
      }
      when LIST_COMPARE_QUERY_MISSING {
        return err(
          rule,
          'CompareToQuery__c',
          'Comparison Query is required as the list source for ListContainsAny/ListDoesNotContainAny.',
          'INVALID_SOQL_TEMPLATE'
        );
      }
      when LIST_COMPARE_FIELD_MISSING {
        return err(
          rule,
          'CompareToField__c',
          'Comparison Query Field is required for list comparison queries.',
          'MISSING_REQUIRED_FIELD'
        );
      }
      when PRIMARY_QUERY_MISSING {
        return err(
          rule,
          'DataQuery__c',
          'Primary Query is required for Query checks (except ListContainsAny/ListDoesNotContainAny).',
          'INVALID_SOQL_TEMPLATE'
        );
      }
      when PRIMARY_QUERY_FIELD_MISSING {
        return err(
          rule,
          'FieldToRead__c',
          'Primary Query Field is required for non-aggregate queries.',
          'MISSING_REQUIRED_FIELD'
        );
      }
      when DUAL_COMPARATOR_ON_SINGLE {
        return err(
          rule,
          'Operator__c',
          'Operator "' + val + '" requires Check Method Compare two queries.',
          'INVALID_COMPARATOR'
        );
      }
      when COMPARATOR_INVALID {
        return err(
          rule,
          'Operator__c',
          'Comparator "' + val + '" is not recognized.',
          'INVALID_COMPARATOR'
        );
      }
      when COMPARATOR_MISSING {
        return err(
          rule,
          'Operator__c',
          'Comparator is required for Query checks.',
          'INVALID_COMPARATOR'
        );
      }
      when MULTI_ROWS_MISSING {
        return err(
          rule,
          'WhenMultipleRows__c',
          'Multiple Records Handling is required for Query checks.',
          'MISSING_REQUIRED_FIELD'
        );
      }
      when MULTI_ROWS_INVALID {
        return err(
          rule,
          'WhenMultipleRows__c',
          'Multiple Records Handling "' + val + '" is not recognized.',
          'INVALID_CONFIG'
        );
      }
      when COMPARE_AS_LISTS_ON_SINGLE {
        return err(
          rule,
          'WhenMultipleRows__c',
          'Compare as two lists requires Check Method Compare two queries, not Single query.',
          'INVALID_COMPARATOR'
        );
      }
      when COMPARE_AGAINST_MISSING {
        return err(
          rule,
          'CompareAgainst__c',
          'Comparison Value Source is required for Query checks except IsBlank/IsNotBlank.',
          'MISSING_REQUIRED_FIELD'
        );
      }
      when COMPARE_AGAINST_INVALID {
        return err(
          rule,
          'CompareAgainst__c',
          'Comparison Value Source "' + val + '" is not recognized.',
          'INVALID_CONFIG'
        );
      }
      when FIXED_VALUE_MISSING {
        return err(
          rule,
          'FixedValue__c',
          'Comparison Value is required when Comparison Value Source is Static Value.',
          'MISSING_REQUIRED_FIELD'
        );
      }
      when RECORD_FORMULA_MISSING {
        return err(
          rule,
          'RecordFormulaValue__c',
          'Comparison Formula is required when Comparison Value Source is Formula Result.',
          'INVALID_FORMULA'
        );
      }
      when ANOTHER_QUERY_MISSING {
        return err(
          rule,
          'CompareToQuery__c',
          'Comparison Query is required when Comparison Value Source is Query Result.',
          'INVALID_SOQL_TEMPLATE'
        );
      }
      when ANOTHER_QUERY_FIELD_MISSING {
        return err(
          rule,
          'CompareToField__c',
          'Comparison Query Field is required for non-aggregate queries.',
          'MISSING_REQUIRED_FIELD'
        );
      }
      // ── CompareTwoQueries (dual) ──
      when DUAL_PRIMARY_QUERY_MISSING {
        return err(
          rule,
          'DataQuery__c',
          'Primary Query is required for CompareTwoQueries checks.',
          'INVALID_SOQL_TEMPLATE'
        );
      }
      when DUAL_COMPARE_QUERY_MISSING {
        return err(
          rule,
          'CompareToQuery__c',
          'Comparison Query is required for CompareTwoQueries checks.',
          'INVALID_SOQL_TEMPLATE'
        );
      }
      when DUAL_PRIMARY_FIELD_MISSING {
        return err(
          rule,
          'FieldToRead__c',
          'Primary Query Field is required for non-aggregate primary queries.',
          'MISSING_REQUIRED_FIELD'
        );
      }
      when DUAL_COMPARE_FIELD_MISSING {
        return err(
          rule,
          'CompareToField__c',
          'Comparison Query Field is required for non-aggregate comparison queries.',
          'MISSING_REQUIRED_FIELD'
        );
      }
      when DUAL_COMPARATOR_MISSING {
        return err(
          rule,
          'Operator__c',
          'Comparator is required for CompareTwoQueries checks.',
          'INVALID_COMPARATOR'
        );
      }
      when DUAL_COMPARATOR_INVALID {
        return err(
          rule,
          'Operator__c',
          'Comparator "' + val + '" is not recognized.',
          'INVALID_COMPARATOR'
        );
      }
      when DUAL_MULTI_ROWS_MISSING {
        return err(
          rule,
          'WhenMultipleRows__c',
          'Multiple Records Handling is required for CompareTwoQueries checks.',
          'MISSING_REQUIRED_FIELD'
        );
      }
      when DUAL_MULTI_ROWS_INVALID {
        return err(
          rule,
          'WhenMultipleRows__c',
          'CompareTwoQueries requires Multiple Records Handling of OneResult or CompareAsLists.',
          'INVALID_COMPARATOR'
        );
      }
      when DUAL_LIST_MODE_NEEDS_LIST_COMPARATOR {
        return err(
          rule,
          'Operator__c',
          'CompareAsLists mode requires a list comparator: ListsOverlap, ListContainsAll, or ExactListMatch.',
          'INVALID_COMPARATOR'
        );
      }
      when DUAL_ONE_RESULT_NO_LIST_COMPARATOR {
        return err(
          rule,
          'Operator__c',
          'List comparators (ListsOverlap, ListContainsAll, ExactListMatch) require CompareAsLists mode.',
          'INVALID_COMPARATOR'
        );
      }
      // ── Apex ──
      when APEX_CLASS_MISSING {
        return err(
          rule,
          'ApexClass__c',
          'Apex Class Name is required for Apex checks.',
          'APEX_CLASS_NOT_FOUND'
        );
      }
      when APEX_CLASS_INVALID {
        return err(
          rule,
          'ApexClass__c',
          'Apex Class Name must identify an instantiable class implementing RecordHealthCheckRule.',
          'APEX_CLASS_NOT_FOUND'
        );
      }
      when APEX_PARAMS_INVALID {
        return err(
          rule,
          'ApexSettingsJson__c',
          'Apex Parameters must contain a valid JSON object.',
          'INVALID_APEX_PARAMETERS'
        );
      }
      // ── Cross-type ──
      when MAX_ROWS_INVALID {
        return err(
          rule,
          'MaxRows__c',
          'Max Rows Override must be a whole number between 1 and ' +
            FRAMEWORK_MAX_ROWS +
            '.',
          'INVALID_CONFIG'
        );
      }
      when NULL_BEHAVIOR_INVALID {
        return err(
          rule,
          'WhenValueIsEmpty__c',
          'Null Behavior "' +
            val +
            '" is not recognized. Valid values: MissingMeansNoMatch, SkipRecordsWithMissingValue, TreatMissingAsBlank.',
          'INVALID_CONFIG'
        );
      }
      when EMPTY_BEHAVIOR_INVALID {
        return err(
          rule,
          'WhenZeroRows__c',
          'Empty Result Behavior "' +
            val +
            '" is not recognized. Valid values: Pass, Fail, Skip, UnableToEvaluate.',
          'INVALID_CONFIG'
        );
      }
      when else {
        // Every FindingCode is mapped above; this is defensive only.
        return err(
          rule,
          null,
          'This check could not be validated.',
          'INVALID_CONFIG'
        );
      }
    }
  }

  // ─── Dependency graph validation ──────────────────────────────────────────

  private List<ValidationIssue> validateDependencyGraph(
    String checkSetName,
    List<Record_Health_Check_Rule__mdt> rules,
    Map<String, Record_Health_Check_Rule__mdt> rulesByDevName
  ) {
    List<ValidationIssue> issues = new List<ValidationIssue>();
    Map<String, String> dependsOnMap = new Map<String, String>(); // devName → dependsOnDevName

    for (Record_Health_Check_Rule__mdt rule : rules) {
      if (String.isBlank(rule.RequiresCheck__c)) {
        continue;
      }

      String depDevName = rule.RequiresCheck__c.trim();
      Record_Health_Check_Rule__mdt dep = rulesByDevName.get(depDevName);

      if (dep == null) {
        issues.add(
          err(
            rule,
            'RequiresCheck__c',
            'DependsOnCheck must reference an existing rule DeveloperName. ' +
              '"' +
              depDevName +
              '" was not found.',
            'INVALID_DEPENDENCY'
          )
        );
        continue;
      }

      // Must be in same Check Set. Use the relationship field value directly;
      // parent relationship traversal is not supported for all custom metadata operations.
      if (dep.Record_Health_Check_Set__c != rule.Record_Health_Check_Set__c) {
        issues.add(
          err(
            rule,
            'RequiresCheck__c',
            'DependsOnCheck must reference a rule in the same Check Set. ' +
              '"' +
              depDevName +
              '" belongs to a different Check Set.',
            'INVALID_DEPENDENCY'
          )
        );
        continue;
      }

      // Must have strictly lower Priority
      if (
        dep != null &&
        dep.RunOrder__c != null &&
        rule.RunOrder__c != null &&
        dep.RunOrder__c >= rule.RunOrder__c
      ) {
        issues.add(
          err(
            rule,
            'RequiresCheck__c',
            'DependsOnCheck must reference a rule with a strictly lower Priority. ' +
              '"' +
              depDevName +
              '" has Priority ' +
              dep.RunOrder__c +
              ' which is not lower than this rule\'s Priority ' +
              rule.RunOrder__c +
              '.',
            'INVALID_DEPENDENCY'
          )
        );
        continue;
      }

      dependsOnMap.put(rule.DeveloperName, depDevName);
    }

    // Cycle detection using DFS
    Set<String> visited = new Set<String>();
    Set<String> inStack = new Set<String>();

    for (String devName : dependsOnMap.keySet()) {
      if (!visited.contains(devName)) {
        List<String> cycle = detectCycle(
          devName,
          dependsOnMap,
          visited,
          inStack
        );
        if (!cycle.isEmpty()) {
          // cycle is the closed walk (e.g. [A, B, C, A]); the repeated start
          // node makes cycleStr read as a full loop ("A → B → C → A"). Dedupe
          // the members when emitting issues so each rule in the cycle gets
          // exactly one issue row rather than the start node getting two.
          // For display, drop the repeated closing node: "A → B → C" not "A → B → C → A".
          List<String> cycleForDisplay = new List<String>(cycle);
          if (
            cycleForDisplay.size() > 1 &&
            cycleForDisplay[0] == cycleForDisplay[cycleForDisplay.size() - 1]
          ) {
            cycleForDisplay.remove(cycleForDisplay.size() - 1);
          }
          String cycleStr = String.join(cycleForDisplay, ' → ');
          Set<String> reportedMembers = new Set<String>();
          for (String cycleMember : cycle) {
            if (!reportedMembers.add(cycleMember)) {
              continue;
            }
            Record_Health_Check_Rule__mdt r = rulesByDevName.get(cycleMember);
            if (r != null) {
              issues.add(
                err(
                  r,
                  'RequiresCheck__c',
                  'Dependency cycle detected: ' + cycleStr,
                  'INVALID_DEPENDENCY'
                )
              );
            }
          }
          break; // report once per set
        }
      }
    }

    return issues;
  }

  private List<String> detectCycle(
    String node,
    Map<String, String> dependsOnMap,
    Set<String> visited,
    Set<String> inStack
  ) {
    visited.add(node);
    inStack.add(node);

    String next = dependsOnMap.get(node);
    if (next != null) {
      if (!visited.contains(next)) {
        List<String> cycle = detectCycle(next, dependsOnMap, visited, inStack);
        if (!cycle.isEmpty()) {
          cycle.add(0, node);
          return cycle;
        }
      } else if (inStack.contains(next)) {
        return new List<String>{ node, next };
      }
    }

    inStack.remove(node);
    return new List<String>();
  }

  // ─── Convenience builder ──────────────────────────────────────────────────

  private ValidationIssue err(
    Record_Health_Check_Rule__mdt rule,
    String fieldName,
    String message,
    String reasonCode
  ) {
    return new ValidationIssue(
      'ERROR',
      rule.DeveloperName,
      fieldName,
      message,
      reasonCode
    );
  }
}
