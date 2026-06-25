/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

@IsTest
private class RecordHealthCheckCoverageTest {
  private class ThrowingRule implements RecordHealthCheckRule {
    public RecordHealthCheckResult evaluate(RecordHealthCheckContext context) {
      throw new IllegalArgumentException('Test plugin failure.');
    }
  }

  private class NullRule implements RecordHealthCheckRule {
    public RecordHealthCheckResult evaluate(RecordHealthCheckContext context) {
      return null;
    }
  }

  @testSetup
  static void setup() {
    RecordHealthCheckTestDataFactory.createCoverageTestRecords();
  }

  @IsTest
  static void dtoAndContextFieldsRoundTrip() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();

    RecordHealthCheckDefinition definition = new RecordHealthCheckDefinition();
    definition.developerName = 'Definition_Key';
    definition.label = 'Definition Label';
    definition.description = 'Definition Description';
    definition.priority = 1;
    definition.dependsOnCheckDeveloperName = 'Prereq';

    RecordHealthCheckDefinitionResponse response = new RecordHealthCheckDefinitionResponse();
    response.displayTitle = 'Title';
    response.displayDescription = 'Description';
    response.triggerMode = 'Manual';
    response.revealMode = 'AllAtOnce';
    response.successDisplayMode = 'Show';
    response.skippedDisplayMode = 'Hide';
    response.stopOnFirstError = true;
    response.totalAvailableCheckCount = 1;
    response.checksOmittedByLimit = false;
    response.debugMode = true;
    response.checks = new List<RecordHealthCheckDefinition>{ definition };

    RecordHealthCheckContext context = new RecordHealthCheckContext();
    context.recordId = accountRecord.Id;
    context.objectApiName = 'Account';
    context.record = accountRecord;
    context.parameters = new Map<String, Object>{ 'mode' => 'PASS' };
    context.checkDeveloperName = 'Definition_Key';

    RecordHealthCheckResult result = new RecordHealthCheckResult();
    result.checkDeveloperName = definition.developerName;
    result.label = definition.label;
    result.status = 'PASS';
    result.severity = 'Info';
    result.message = 'Message';
    result.detailMessage = 'Detail';
    result.adminDetailMessage = 'Admin';
    result.reasonCode = 'REASON';
    result.priority = 1;
    result.durationMs = 10;
    result.evaluatorType = 'Test';

    System.assertEquals('Definition_Key', response.checks[0].developerName);
    System.assertEquals(accountRecord.Id, context.recordId);
    System.assertEquals('PASS', result.status);
  }

  @IsTest
  static void configServiceValidationCoversInvalidBranches() {
    RecordHealthCheckConfigService service = new RecordHealthCheckConfigService();

    assertUnable(
      service.validateRuleForEvaluation(baseRule('Bad_Type', 'Bogus')),
      'INVALID_CHECK_TYPE'
    );

    Record_Health_Check_Rule__mdt formulaRule = baseRule(
      'Missing_Formula',
      'Formula'
    );
    formulaRule.PassFailFormula__c = null;
    assertUnable(
      service.validateRuleForEvaluation(formulaRule),
      'INVALID_FORMULA'
    );

    Record_Health_Check_Rule__mdt noSeverity = baseRule(
      'No_Severity',
      'Formula'
    );
    noSeverity.Severity__c = null;
    assertUnable(
      service.validateRuleForEvaluation(noSeverity),
      RecordHealthCheckConfigService.RC_INVALID_CONFIG
    );

    Record_Health_Check_Rule__mdt invalidApplicability = baseRule(
      'Bad_Applicability',
      'Formula'
    );
    invalidApplicability.RunThisCheckWhen__c = 'Sometimes';
    assertUnable(
      service.validateRuleForEvaluation(invalidApplicability),
      'INVALID_CONFIG'
    );

    Record_Health_Check_Rule__mdt queryMissingPrimary = queryRule(
      'Query_Missing_Primary'
    );
    queryMissingPrimary.DataQuery__c = null;
    assertUnable(
      service.validateRuleForEvaluation(queryMissingPrimary),
      'INVALID_SOQL_TEMPLATE'
    );

    Record_Health_Check_Rule__mdt queryDualComparator = queryRule(
      'Query_Dual_Comparator'
    );
    queryDualComparator.Operator__c = 'ExactListMatch';
    assertUnable(
      service.validateRuleForEvaluation(queryDualComparator),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt queryInvalidComparator = queryRule(
      'Query_Invalid_Comparator'
    );
    queryInvalidComparator.Operator__c = 'Around';
    assertUnable(
      service.validateRuleForEvaluation(queryInvalidComparator),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt queryMissingComparator = queryRule(
      'Query_Missing_Comparator'
    );
    queryMissingComparator.Operator__c = null;
    assertUnable(
      service.validateRuleForEvaluation(queryMissingComparator),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt queryMissingMode = queryRule(
      'Query_Missing_Mode'
    );
    queryMissingMode.WhenMultipleRows__c = null;
    assertUnable(
      service.validateRuleForEvaluation(queryMissingMode),
      RecordHealthCheckConfigService.RC_UNABLE_TO_EVALUATE
    );

    Record_Health_Check_Rule__mdt queryBadListMode = queryRule(
      'Query_Bad_List_Mode'
    );
    queryBadListMode.WhenMultipleRows__c = 'CompareAsLists';
    assertUnable(
      service.validateRuleForEvaluation(queryBadListMode),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt queryMissingSource = queryRule(
      'Query_Missing_Source'
    );
    queryMissingSource.CompareAgainst__c = null;
    assertUnable(
      service.validateRuleForEvaluation(queryMissingSource),
      RecordHealthCheckConfigService.RC_UNABLE_TO_EVALUATE
    );

    Record_Health_Check_Rule__mdt queryMissingStatic = queryRule(
      'Query_Missing_Static'
    );
    queryMissingStatic.FixedValue__c = null;
    assertUnable(
      service.validateRuleForEvaluation(queryMissingStatic),
      RecordHealthCheckConfigService.RC_UNABLE_TO_EVALUATE
    );

    Record_Health_Check_Rule__mdt queryMissingFormula = queryRule(
      'Query_Missing_Comparison_Formula'
    );
    queryMissingFormula.CompareAgainst__c = 'RecordFormula';
    queryMissingFormula.RecordFormulaValue__c = null;
    assertUnable(
      service.validateRuleForEvaluation(queryMissingFormula),
      'INVALID_FORMULA'
    );

    Record_Health_Check_Rule__mdt queryMissingComparisonQuery = queryRule(
      'Query_Missing_Comparison_Query'
    );
    queryMissingComparisonQuery.CompareAgainst__c = 'AnotherQuery';
    queryMissingComparisonQuery.CompareToQuery__c = null;
    assertUnable(
      service.validateRuleForEvaluation(queryMissingComparisonQuery),
      'INVALID_SOQL_TEMPLATE'
    );

    Record_Health_Check_Rule__mdt queryBadMax = queryRule('Query_Bad_Max');
    queryBadMax.MaxRows__c = 2001;
    assertUnable(
      service.validateRuleForEvaluation(queryBadMax),
      'GOVERNOR_LIMIT_RISK'
    );

    Record_Health_Check_Rule__mdt queryBadNull = queryRule('Query_Bad_Null');
    queryBadNull.WhenValueIsEmpty__c = 'Magic';
    assertUnable(
      service.validateRuleForEvaluation(queryBadNull),
      'INVALID_CONFIG'
    );

    Record_Health_Check_Rule__mdt queryBadEmpty = queryRule('Query_Bad_Empty');
    queryBadEmpty.WhenZeroRows__c = 'Maybe';
    assertUnable(
      service.validateRuleForEvaluation(queryBadEmpty),
      'INVALID_CONFIG'
    );

    Record_Health_Check_Rule__mdt listComparator = queryRule(
      'Query_List_Comparator'
    );
    listComparator.Operator__c = 'ListContainsAny';
    listComparator.WhenMultipleRows__c = 'CompareAsLists';
    listComparator.DataQuery__c = null;
    listComparator.ValueToTest__c = null;
    assertUnable(
      service.validateRuleForEvaluation(listComparator),
      'INVALID_FORMULA'
    );
    listComparator.ValueToTest__c = 'BillingCity';
    listComparator.CompareToQuery__c = null;
    assertUnable(
      service.validateRuleForEvaluation(listComparator),
      'INVALID_SOQL_TEMPLATE'
    );

    Record_Health_Check_Rule__mdt apexRule = baseRule(
      'Apex_Missing_Class',
      'Apex'
    );
    apexRule.ApexClass__c = null;
    assertUnable(
      service.validateRuleForEvaluation(apexRule),
      'APEX_CLASS_NOT_FOUND'
    );

    assertUnable(
      service.validateRuleForEvaluation(dualRule('Dual_Missing_Primary')),
      'INVALID_SOQL_TEMPLATE'
    );

    Record_Health_Check_Rule__mdt dualMissingComparison = dualRule(
      'Dual_Missing_Comparison'
    );
    dualMissingComparison.DataQuery__c = 'SELECT COUNT(Id) totalCount FROM Contact WHERE AccountId = {!Id}';
    dualMissingComparison.CompareToQuery__c = null;
    assertUnable(
      service.validateRuleForEvaluation(dualMissingComparison),
      'INVALID_SOQL_TEMPLATE'
    );

    Record_Health_Check_Rule__mdt dualMissingComparator = validDualRule(
      'Dual_Missing_Comparator'
    );
    dualMissingComparator.Operator__c = null;
    assertUnable(
      service.validateRuleForEvaluation(dualMissingComparator),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt dualInvalidComparator = validDualRule(
      'Dual_Invalid_Comparator'
    );
    dualInvalidComparator.Operator__c = 'Near';
    assertUnable(
      service.validateRuleForEvaluation(dualInvalidComparator),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt dualMissingMode = validDualRule(
      'Dual_Missing_Mode'
    );
    dualMissingMode.WhenMultipleRows__c = null;
    assertUnable(
      service.validateRuleForEvaluation(dualMissingMode),
      RecordHealthCheckConfigService.RC_UNABLE_TO_EVALUATE
    );

    Record_Health_Check_Rule__mdt dualBadMode = validDualRule('Dual_Bad_Mode');
    dualBadMode.WhenMultipleRows__c = 'AnyRowPasses';
    assertUnable(
      service.validateRuleForEvaluation(dualBadMode),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt dualBadListComparator = validDualRule(
      'Dual_Bad_List_Comparator'
    );
    dualBadListComparator.WhenMultipleRows__c = 'CompareAsLists';
    dualBadListComparator.Operator__c = 'Equals';
    assertUnable(
      service.validateRuleForEvaluation(dualBadListComparator),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt dualBadScalarComparator = validDualRule(
      'Dual_Bad_Scalar_Comparator'
    );
    dualBadScalarComparator.WhenMultipleRows__c = 'OneResult';
    dualBadScalarComparator.Operator__c = 'ExactListMatch';
    assertUnable(
      service.validateRuleForEvaluation(dualBadScalarComparator),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt dualBadMax = validDualRule('Dual_Bad_Max');
    dualBadMax.MaxRows__c = 0;
    assertUnable(
      service.validateRuleForEvaluation(dualBadMax),
      'GOVERNOR_LIMIT_RISK'
    );

    System.assertEquals(
      null,
      service.validateRuleForEvaluation(queryRule('Valid_Query'))
    );
    System.assertEquals(
      null,
      service.validateRuleForEvaluation(validDualRule('Valid_Dual'))
    );
  }

  @IsTest
  static void metadataValidatorCoversInvalidInMemoryMetadata() {
    RecordHealthCheckMetadataValidator validator = new RecordHealthCheckMetadataValidator();
    Id setAId = [
      SELECT Id
      FROM Record_Health_Check_Set__mdt
      WHERE DeveloperName = 'Account_Data_Quality'
      LIMIT 1
    ]
    .Id;
    Id setBId = [
      SELECT Id
      FROM Record_Health_Check_Set__mdt
      WHERE DeveloperName = 'Account_Query_Coverage'
      LIMIT 1
    ]
    .Id;

    List<Record_Health_Check_Set__mdt> checkSets = new List<Record_Health_Check_Set__mdt>{
      new Record_Health_Check_Set__mdt(
        DeveloperName = 'Set_A',
        MasterLabel = 'Set A',
        ObjectApiName__c = '',
        PanelHeading__c = '',
        PassedChecksDisplay__c = 'Maybe',
        SkippedChecksDisplay__c = 'Sometimes'
      )
    };

    Record_Health_Check_Rule__mdt missingBasics = new Record_Health_Check_Rule__mdt(
      DeveloperName = 'Missing_Basics',
      MasterLabel = 'Missing Basics',
      Record_Health_Check_Set__c = setAId
    );

    Record_Health_Check_Rule__mdt invalidType = baseRule(
      'Invalid_Type_For_Validator',
      'Unknown'
    );
    invalidType.Record_Health_Check_Set__c = setAId;

    Record_Health_Check_Rule__mdt invalidApplicability = baseRule(
      'Invalid_Applicability_For_Validator',
      'Formula'
    );
    invalidApplicability.Record_Health_Check_Set__c = setAId;
    invalidApplicability.RunThisCheckWhen__c = 'WhenLucky';

    Record_Health_Check_Rule__mdt missingFormula = baseRule(
      'Missing_Formula_For_Validator',
      'Formula'
    );
    missingFormula.Record_Health_Check_Set__c = setAId;
    missingFormula.PassFailFormula__c = null;

    Record_Health_Check_Rule__mdt invalidQuery = queryRule(
      'Invalid_Query_For_Validator'
    );
    invalidQuery.Record_Health_Check_Set__c = setAId;
    invalidQuery.Operator__c = 'ExactListMatch';
    invalidQuery.DataQuery__c = null;
    invalidQuery.WhenMultipleRows__c = 'CompareAsLists';
    invalidQuery.CompareAgainst__c = null;
    invalidQuery.FixedValue__c = null;
    invalidQuery.RecordFormulaValue__c = null;
    invalidQuery.CompareToQuery__c = null;
    invalidQuery.MaxRows__c = 2001;
    invalidQuery.WhenValueIsEmpty__c = 'InvalidNullBehavior';
    invalidQuery.WhenZeroRows__c = 'InvalidEmptyBehavior';

    Record_Health_Check_Rule__mdt queryMissingComparator = queryRule(
      'Validator_Query_Missing_Comparator'
    );
    queryMissingComparator.Record_Health_Check_Set__c = setAId;
    queryMissingComparator.Operator__c = null;

    Record_Health_Check_Rule__mdt queryUnknownComparator = queryRule(
      'Validator_Query_Unknown_Comparator'
    );
    queryUnknownComparator.Record_Health_Check_Set__c = setAId;
    queryUnknownComparator.Operator__c = 'Around';

    Record_Health_Check_Rule__mdt queryMissingMode = queryRule(
      'Validator_Query_Missing_Mode'
    );
    queryMissingMode.Record_Health_Check_Set__c = setAId;
    queryMissingMode.WhenMultipleRows__c = null;

    Record_Health_Check_Rule__mdt queryMissingStatic = queryRule(
      'Validator_Query_Missing_Static'
    );
    queryMissingStatic.Record_Health_Check_Set__c = setAId;
    queryMissingStatic.FixedValue__c = null;

    Record_Health_Check_Rule__mdt queryMissingFormula = queryRule(
      'Validator_Query_Missing_Formula'
    );
    queryMissingFormula.Record_Health_Check_Set__c = setAId;
    queryMissingFormula.CompareAgainst__c = 'RecordFormula';
    queryMissingFormula.RecordFormulaValue__c = null;

    Record_Health_Check_Rule__mdt queryMissingComparisonQuery = queryRule(
      'Validator_Query_Missing_Comparison_Query'
    );
    queryMissingComparisonQuery.Record_Health_Check_Set__c = setAId;
    queryMissingComparisonQuery.CompareAgainst__c = 'AnotherQuery';
    queryMissingComparisonQuery.CompareToQuery__c = null;

    Record_Health_Check_Rule__mdt invalidListQuery = queryRule(
      'Invalid_List_Query_For_Validator'
    );
    invalidListQuery.Record_Health_Check_Set__c = setAId;
    invalidListQuery.Operator__c = 'ListContainsAny';
    invalidListQuery.ValueToTest__c = null;
    invalidListQuery.CompareToQuery__c = null;

    Record_Health_Check_Rule__mdt invalidApex = baseRule(
      'Invalid_Apex_For_Validator',
      'Apex'
    );
    invalidApex.Record_Health_Check_Set__c = setAId;
    invalidApex.ApexClass__c = null;

    Record_Health_Check_Rule__mdt invalidDual = validDualRule(
      'Invalid_Dual_For_Validator'
    );
    invalidDual.Record_Health_Check_Set__c = setAId;
    invalidDual.DataQuery__c = null;
    invalidDual.CompareToQuery__c = null;
    invalidDual.Operator__c = 'ListContainsAll';
    invalidDual.WhenMultipleRows__c = 'OneResult';

    Record_Health_Check_Rule__mdt dualMissingComparator = validDualRule(
      'Validator_Dual_Missing_Comparator'
    );
    dualMissingComparator.Record_Health_Check_Set__c = setAId;
    dualMissingComparator.Operator__c = null;

    Record_Health_Check_Rule__mdt dualUnknownComparator = validDualRule(
      'Validator_Dual_Unknown_Comparator'
    );
    dualUnknownComparator.Record_Health_Check_Set__c = setAId;
    dualUnknownComparator.Operator__c = 'Around';

    Record_Health_Check_Rule__mdt dualMissingMode = validDualRule(
      'Validator_Dual_Missing_Mode'
    );
    dualMissingMode.Record_Health_Check_Set__c = setAId;
    dualMissingMode.WhenMultipleRows__c = null;

    Record_Health_Check_Rule__mdt dualUnknownMode = validDualRule(
      'Validator_Dual_Unknown_Mode'
    );
    dualUnknownMode.Record_Health_Check_Set__c = setAId;
    dualUnknownMode.WhenMultipleRows__c = 'AnyRowPasses';

    Record_Health_Check_Rule__mdt dualBadListMode = validDualRule(
      'Validator_Dual_Bad_List_Mode'
    );
    dualBadListMode.Record_Health_Check_Set__c = setAId;
    dualBadListMode.WhenMultipleRows__c = 'CompareAsLists';
    dualBadListMode.Operator__c = 'Equals';

    Record_Health_Check_Rule__mdt missingDependency = baseRule(
      'Missing_Dependency_For_Validator',
      'Formula'
    );
    missingDependency.Record_Health_Check_Set__c = setAId;
    missingDependency.RequiresCheck__c = 'No_Such_Rule';

    Record_Health_Check_Rule__mdt sameSetDependency = baseRule(
      'Same_Set_Dependency_For_Validator',
      'Formula'
    );
    sameSetDependency.Record_Health_Check_Set__c = setAId;
    sameSetDependency.RunOrder__c = 5;
    sameSetDependency.RequiresCheck__c = 'Invalid_Type_For_Validator';

    Record_Health_Check_Rule__mdt cycleA = baseRule(
      'Cycle_A_For_Validator',
      'Formula'
    );
    cycleA.Record_Health_Check_Set__c = setAId;
    cycleA.RunOrder__c = null;
    cycleA.RequiresCheck__c = 'Cycle_B_For_Validator';

    Record_Health_Check_Rule__mdt cycleB = baseRule(
      'Cycle_B_For_Validator',
      'Formula'
    );
    cycleB.Record_Health_Check_Set__c = setAId;
    cycleB.RunOrder__c = null;
    cycleB.RequiresCheck__c = 'Cycle_A_For_Validator';

    Record_Health_Check_Rule__mdt crossSetTarget = baseRule(
      'Cross_Set_Target_For_Validator',
      'Formula'
    );
    crossSetTarget.Record_Health_Check_Set__c = setBId;
    crossSetTarget.RunOrder__c = 1;

    Record_Health_Check_Rule__mdt crossSetSource = baseRule(
      'Cross_Set_Source_For_Validator',
      'Formula'
    );
    crossSetSource.Record_Health_Check_Set__c = setAId;
    crossSetSource.RunOrder__c = 2;
    crossSetSource.RequiresCheck__c = 'Cross_Set_Target_For_Validator';

    List<RecordHealthCheckMetadataValidator.ValidationIssue> issues = validator.validateRecordsForTest(
      checkSets,
      new List<Record_Health_Check_Rule__mdt>{
        missingBasics,
        invalidType,
        invalidApplicability,
        missingFormula,
        invalidQuery,
        queryMissingComparator,
        queryUnknownComparator,
        queryMissingMode,
        queryMissingStatic,
        queryMissingFormula,
        queryMissingComparisonQuery,
        invalidListQuery,
        invalidApex,
        invalidDual,
        dualMissingComparator,
        dualUnknownComparator,
        dualMissingMode,
        dualUnknownMode,
        dualBadListMode,
        missingDependency,
        sameSetDependency,
        cycleA,
        cycleB,
        crossSetTarget,
        crossSetSource
      }
    );

    System.assert(issues.size() > 20, 'Expected broad validation coverage.');
    Set<String> reasonCodes = new Set<String>();
    for (RecordHealthCheckMetadataValidator.ValidationIssue issue : issues) {
      reasonCodes.add(issue.reasonCode);
    }
    System.assert(reasonCodes.contains('MISSING_REQUIRED_FIELD'));
    System.assert(reasonCodes.contains('INVALID_CHECK_TYPE'));
    System.assert(reasonCodes.contains('INVALID_CONFIG'));
    System.assert(reasonCodes.contains('INVALID_COMPARATOR'));
    System.assert(reasonCodes.contains('INVALID_DEPENDENCY'));
  }

  @IsTest
  static void soqlEvaluatorCoversComparatorAndQueryBranches() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckSoqlEvaluator evaluator = new RecordHealthCheckSoqlEvaluator();

    String bound = evaluator.bindTokens(
      'SELECT Id FROM Account WHERE Name = {!Name} AND AnnualRevenue >= {!AnnualRevenue}',
      accountRecord
    );
    System.assert(
      bound.contains(String.escapeSingleQuotes(accountRecord.Name))
    );
    System.assert(bound.contains(String.valueOf(accountRecord.AnnualRevenue)));

    assertStatus(
      evaluator.evaluate(
        queryRule('Q_Equals_Pass'),
        accountRecord.Id,
        accountRecord
      ),
      'PASS'
    );

    Record_Health_Check_Rule__mdt notEquals = queryRule('Q_NotEquals_Fail');
    notEquals.Operator__c = 'NotEquals';
    notEquals.FixedValue__c = accountRecord.BillingCity;
    RecordHealthCheckResult notEqualsResult = evaluator.evaluate(
      notEquals,
      accountRecord.Id,
      accountRecord
    );
    assertStatus(notEqualsResult, 'FAIL');
    // A non-passing single-query result carries the actual value and the
    // comparator-described expectation so the UI can show both.
    System.assertEquals(
      '"' + accountRecord.BillingCity + '"',
      notEqualsResult.actualValue,
      'actualValue should reflect the queried record value (text is quoted)'
    );
    System.assertEquals(
      'to not equal "' + accountRecord.BillingCity + '"',
      notEqualsResult.expectedValue,
      'expectedValue should describe the comparator and operand'
    );

    Record_Health_Check_Rule__mdt contains = queryRule('Q_Contains_Pass');
    contains.Operator__c = 'Contains';
    contains.FixedValue__c = 'hic';
    assertStatus(
      evaluator.evaluate(contains, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt doesNotContain = queryRule(
      'Q_Does_Not_Contain_Fail'
    );
    doesNotContain.Operator__c = 'DoesNotContain';
    doesNotContain.FixedValue__c = 'hic';
    assertStatus(
      evaluator.evaluate(doesNotContain, accountRecord.Id, accountRecord),
      'FAIL'
    );

    Record_Health_Check_Rule__mdt greaterThan = queryRule('Q_Greater_Than');
    greaterThan.DataQuery__c = 'SELECT AnnualRevenue FROM Account WHERE Id = {!Id}';
    greaterThan.FieldToRead__c = 'AnnualRevenue';
    greaterThan.Operator__c = 'GreaterThan';
    greaterThan.FixedValue__c = '10';
    assertStatus(
      evaluator.evaluate(greaterThan, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt aggregateCount = queryRule(
      'Q_Aggregate_Count'
    );
    aggregateCount.DataQuery__c = 'SELECT COUNT() FROM Contact WHERE AccountId = {!Id}';
    aggregateCount.FieldToRead__c = null;
    aggregateCount.Operator__c = 'GreaterThan';
    aggregateCount.FixedValue__c = '0';
    assertStatus(
      evaluator.evaluate(aggregateCount, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt numericParseError = queryRule(
      'Q_Numeric_Parse_Error'
    );
    numericParseError.DataQuery__c = 'SELECT AnnualRevenue FROM Account WHERE Id = {!Id}';
    numericParseError.FieldToRead__c = 'AnnualRevenue';
    numericParseError.Operator__c = 'Equals';
    numericParseError.FixedValue__c = 'not-a-number';
    assertReason(
      evaluator.evaluate(numericParseError, accountRecord.Id, accountRecord),
      'INCOMPATIBLE_COMPARISON_TYPES'
    );

    Record_Health_Check_Rule__mdt dateCompare = queryRule('Q_Date_Compare');
    dateCompare.DataQuery__c = 'SELECT CloseDate FROM Opportunity WHERE AccountId = {!Id} LIMIT 1';
    dateCompare.FieldToRead__c = 'CloseDate';
    dateCompare.Operator__c = 'LessThanOrEqual';
    dateCompare.CompareAgainst__c = 'RecordFormula';
    dateCompare.RecordFormulaValue__c = 'TODAY() + 60';
    assertStatus(
      evaluator.evaluate(dateCompare, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt textOrder = queryRule('Q_Text_Order');
    textOrder.Operator__c = 'GreaterThan';
    textOrder.FixedValue__c = 'Alpha';
    assertReason(
      evaluator.evaluate(textOrder, accountRecord.Id, accountRecord),
      'INCOMPATIBLE_COMPARISON_TYPES'
    );

    Record_Health_Check_Rule__mdt isBlank = queryRule('Q_IsBlank');
    isBlank.DataQuery__c = 'SELECT Description FROM Account WHERE Id = {!Id}';
    isBlank.FieldToRead__c = 'Description';
    isBlank.Operator__c = 'IsBlank';
    isBlank.CompareAgainst__c = null;
    assertStatus(
      evaluator.evaluate(isBlank, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt isNotBlank = queryRule('Q_IsNotBlank');
    isNotBlank.Operator__c = 'IsNotBlank';
    isNotBlank.CompareAgainst__c = null;
    assertStatus(
      evaluator.evaluate(isNotBlank, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt nullAsBlank = queryRule('Q_Null_As_Blank');
    nullAsBlank.DataQuery__c = 'SELECT Description FROM Account WHERE Id = {!Id}';
    nullAsBlank.FieldToRead__c = 'Description';
    nullAsBlank.Operator__c = 'Equals';
    nullAsBlank.FixedValue__c = '';
    nullAsBlank.WhenValueIsEmpty__c = 'TreatMissingAsBlank';
    assertStatus(
      evaluator.evaluate(nullAsBlank, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt nullNoMatch = nullAsBlank.clone();
    nullNoMatch.DeveloperName = 'Q_Null_No_Match';
    nullNoMatch.WhenValueIsEmpty__c = 'MissingMeansNoMatch';
    assertStatus(
      evaluator.evaluate(nullNoMatch, accountRecord.Id, accountRecord),
      'FAIL'
    );

    Record_Health_Check_Rule__mdt anyPass = queryRule('Q_Any_Pass');
    anyPass.DataQuery__c = 'SELECT Email FROM Contact WHERE AccountId = {!Id}';
    anyPass.FieldToRead__c = 'Email';
    anyPass.WhenMultipleRows__c = 'AnyRowPasses';
    anyPass.Operator__c = 'Contains';
    anyPass.FixedValue__c = '@example.com';
    assertStatus(
      evaluator.evaluate(anyPass, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt anyFail = anyPass.clone();
    anyFail.DeveloperName = 'Q_Any_Fail';
    anyFail.FixedValue__c = '@missing.example';
    assertStatus(
      evaluator.evaluate(anyFail, accountRecord.Id, accountRecord),
      'FAIL'
    );

    Record_Health_Check_Rule__mdt allFail = anyPass.clone();
    allFail.DeveloperName = 'Q_All_Fail';
    allFail.WhenMultipleRows__c = 'AllRowsPass';
    assertStatus(
      evaluator.evaluate(allFail, accountRecord.Id, accountRecord),
      'PASS'
    );

    // allBlankFail exercises IsNotBlank + AllRowsPass expecting FAIL because at
    // least one Contact email is blank. The shared factory gives every seeded
    // Contact an email, so add a deterministic blank-email Contact for this
    // assertion and remove it afterward so later checks see the original data.
    Contact blankEmailContact = new Contact(
      LastName = 'Blank Email Coverage',
      AccountId = accountRecord.Id
    );
    insert blankEmailContact;
    Record_Health_Check_Rule__mdt allBlankFail = queryRule('Q_All_Blank_Fail');
    allBlankFail.DataQuery__c = 'SELECT Email FROM Contact WHERE AccountId = {!Id}';
    allBlankFail.FieldToRead__c = 'Email';
    allBlankFail.WhenMultipleRows__c = 'AllRowsPass';
    allBlankFail.Operator__c = 'IsNotBlank';
    allBlankFail.CompareAgainst__c = null;
    allBlankFail.WhenValueIsEmpty__c = 'MissingMeansNoMatch';
    assertStatus(
      evaluator.evaluate(allBlankFail, accountRecord.Id, accountRecord),
      'FAIL'
    );
    delete blankEmailContact;

    Record_Health_Check_Rule__mdt anyAllSkipped = queryRule(
      'Q_Any_All_Skipped'
    );
    anyAllSkipped.DataQuery__c = 'SELECT Description FROM Account WHERE Id = {!Id}';
    anyAllSkipped.FieldToRead__c = 'Description';
    anyAllSkipped.WhenMultipleRows__c = 'AnyRowPasses';
    anyAllSkipped.Operator__c = 'Equals';
    anyAllSkipped.FixedValue__c = 'anything';
    anyAllSkipped.WhenValueIsEmpty__c = 'SkipRecordsWithMissingValue';
    anyAllSkipped.WhenZeroRows__c = 'Skip';
    assertStatus(
      evaluator.evaluate(anyAllSkipped, accountRecord.Id, accountRecord),
      'SKIPPED'
    );

    // P1-05 / SCAN-06: a PRESENT row whose field-under-test is null with the
    // null behavior set to Skip is indeterminate because of the null VALUE, not
    // because of zero rows. It must SKIP even when WhenZeroRows = Fail — routing
    // the null value through WhenZeroRows previously made this wrongly FAIL.
    Record_Health_Check_Rule__mdt nullSkipNotFail = queryRule(
      'Q_Null_Skip_Not_Fail'
    );
    nullSkipNotFail.DataQuery__c = 'SELECT Description FROM Account WHERE Id = {!Id}';
    nullSkipNotFail.FieldToRead__c = 'Description';
    nullSkipNotFail.Operator__c = 'Equals';
    nullSkipNotFail.FixedValue__c = 'anything';
    nullSkipNotFail.WhenValueIsEmpty__c = 'SkipRecordsWithMissingValue';
    nullSkipNotFail.WhenZeroRows__c = 'Fail';
    assertStatus(
      evaluator.evaluate(nullSkipNotFail, accountRecord.Id, accountRecord),
      'SKIPPED'
    );

    Record_Health_Check_Rule__mdt emptyPass = queryRule('Q_Empty_Pass');
    emptyPass.DataQuery__c = 'SELECT Id FROM Contact WHERE AccountId = null';
    emptyPass.FieldToRead__c = 'Id';
    emptyPass.WhenZeroRows__c = 'Pass';
    assertStatus(
      evaluator.evaluate(emptyPass, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt emptyUnable = emptyPass.clone();
    emptyUnable.DeveloperName = 'Q_Empty_Unable';
    emptyUnable.WhenZeroRows__c = 'UnableToEvaluate';
    RecordHealthCheckResult emptyUnableResult = evaluator.evaluate(
      emptyUnable,
      accountRecord.Id,
      accountRecord
    );
    assertStatus(emptyUnableResult, 'UNABLE_TO_EVALUATE');
    System.assertEquals('NO_ROWS_RETURNED', emptyUnableResult.reasonCode);

    Record_Health_Check_Rule__mdt emptySkip = emptyPass.clone();
    emptySkip.DeveloperName = 'Q_Empty_Skip';
    emptySkip.WhenZeroRows__c = 'Skip';
    assertStatus(
      evaluator.evaluate(emptySkip, accountRecord.Id, accountRecord),
      'SKIPPED'
    );

    Record_Health_Check_Rule__mdt queryResult = queryRule('Q_Query_Result');
    queryResult.CompareAgainst__c = 'AnotherQuery';
    queryResult.CompareToQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}';
    queryResult.CompareToField__c = 'BillingCity';
    assertStatus(
      evaluator.evaluate(queryResult, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt queryResultMultiple = queryResult.clone();
    queryResultMultiple.DeveloperName = 'Q_Query_Result_Multiple';
    queryResultMultiple.CompareToQuery__c = 'SELECT MailingCity FROM Contact WHERE AccountId = {!Id}';
    assertReason(
      evaluator.evaluate(queryResultMultiple, accountRecord.Id, accountRecord),
      'MULTIPLE_ROWS_RETURNED'
    );

    Record_Health_Check_Rule__mdt listContains = queryRule('Q_List_Contains');
    listContains.Operator__c = 'ListContainsAny';
    listContains.ValueToTest__c = 'BillingCity';
    listContains.DataQuery__c = null;
    listContains.WhenMultipleRows__c = 'CompareAsLists';
    listContains.CompareToQuery__c = 'SELECT MailingCity FROM Contact WHERE AccountId = {!Id}';
    listContains.CompareToField__c = 'MailingCity';
    assertStatus(
      evaluator.evaluate(listContains, accountRecord.Id, accountRecord),
      'PASS'
    );

    // List checks read only ValueToTest__c — PassFailFormula__c is ignored (no fallback).
    // A valid ValueToTest__c passes even when PassFailFormula__c holds a non-matching value.
    Record_Health_Check_Rule__mdt listIgnoresPassFail = listContains.clone();
    listIgnoresPassFail.DeveloperName = 'Q_List_Ignores_PassFail';
    listIgnoresPassFail.PassFailFormula__c = '"Missing City"';
    assertStatus(
      evaluator.evaluate(listIgnoresPassFail, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt listDoesNotContain = listContains.clone();
    listDoesNotContain.DeveloperName = 'Q_List_Does_Not_Contain';
    listDoesNotContain.Operator__c = 'ListDoesNotContainAny';
    listDoesNotContain.ValueToTest__c = '"Missing City"';
    assertStatus(
      evaluator.evaluate(listDoesNotContain, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt listDoesContainFail = listContains.clone();
    listDoesContainFail.DeveloperName = 'Q_List_Does_Contain_Fail';
    listDoesContainFail.Operator__c = 'ListDoesNotContainAny';
    assertStatus(
      evaluator.evaluate(listDoesContainFail, accountRecord.Id, accountRecord),
      'FAIL'
    );

    Record_Health_Check_Rule__mdt listEmptyPass = listContains.clone();
    listEmptyPass.DeveloperName = 'Q_List_Empty_Pass';
    listEmptyPass.CompareToQuery__c = 'SELECT MailingCity FROM Contact WHERE AccountId = null';
    listEmptyPass.WhenZeroRows__c = 'Pass';
    assertStatus(
      evaluator.evaluate(listEmptyPass, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt badMode = queryRule('Q_Bad_Mode_Runtime');
    badMode.WhenMultipleRows__c = 'SomethingElse';
    assertReason(
      evaluator.evaluate(badMode, accountRecord.Id, accountRecord),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt compareAsLists = queryRule(
      'Q_Compare_As_Lists_Runtime'
    );
    compareAsLists.WhenMultipleRows__c = 'CompareAsLists';
    assertReason(
      evaluator.evaluate(compareAsLists, accountRecord.Id, accountRecord),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt invalidField = queryRule('Q_Invalid_Field');
    invalidField.FieldToRead__c = 'NotAField__c';
    assertReason(
      evaluator.evaluate(invalidField, accountRecord.Id, accountRecord),
      'INVALID_SOQL_TEMPLATE'
    );

    Record_Health_Check_Rule__mdt missingField = queryRule('Q_Missing_Field');
    missingField.FieldToRead__c = null;
    assertReason(
      evaluator.evaluate(missingField, accountRecord.Id, accountRecord),
      'INVALID_SOQL_TEMPLATE'
    );

    Record_Health_Check_Rule__mdt missingBind = queryRule('Q_Missing_Bind');
    missingBind.DataQuery__c = 'SELECT Id FROM Account WHERE Id = {!DoesNotExist__c}';
    assertReason(
      evaluator.evaluate(missingBind, accountRecord.Id, accountRecord),
      'MISSING_BIND_VALUE'
    );

    Record_Health_Check_Rule__mdt badKeyword = queryRule('Q_Bad_Keyword');
    badKeyword.DataQuery__c = 'SELECT Id FROM Account WHERE Name = DELETE';
    assertReason(
      evaluator.evaluate(badKeyword, accountRecord.Id, accountRecord),
      'INVALID_SOQL_TEMPLATE'
    );

    Record_Health_Check_Rule__mdt badPhrase = queryRule('Q_Bad_Phrase');
    badPhrase.DataQuery__c = 'SELECT Id FROM Account ALL ROWS';
    assertReason(
      evaluator.evaluate(badPhrase, accountRecord.Id, accountRecord),
      'INVALID_SOQL_TEMPLATE'
    );

    Record_Health_Check_Rule__mdt maxRows = queryRule('Q_Max_Rows');
    maxRows.DataQuery__c = 'SELECT Id FROM Contact WHERE AccountId = {!Id}';
    maxRows.FieldToRead__c = 'Id';
    maxRows.WhenMultipleRows__c = 'AnyRowPasses';
    maxRows.MaxRows__c = 1;
    assertReason(
      evaluator.evaluate(maxRows, accountRecord.Id, accountRecord),
      'GOVERNOR_LIMIT_RISK'
    );
  }

  @IsTest
  static void dualSoqlEvaluatorCoversScalarListAndErrorBranches() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckDualSoqlEvaluator evaluator = new RecordHealthCheckDualSoqlEvaluator();

    assertStatus(
      evaluator.evaluate(
        validDualRule('D_Counts_Equal'),
        accountRecord.Id,
        accountRecord
      ),
      'PASS'
    );

    Record_Health_Check_Rule__mdt notEquals = validDualRule('D_Not_Equals');
    notEquals.Operator__c = 'NotEquals';
    notEquals.CompareToQuery__c = 'SELECT COUNT(Id) totalCount FROM Opportunity WHERE AccountId = {!Id}';
    assertStatus(
      evaluator.evaluate(notEquals, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt contains = validDualRule('D_Contains');
    contains.DataQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}';
    contains.FieldToRead__c = 'BillingCity';
    contains.CompareToQuery__c = 'SELECT BillingState FROM Account WHERE Id = {!Id}';
    contains.CompareToField__c = 'BillingState';
    contains.Operator__c = 'DoesNotContain';
    assertStatus(
      evaluator.evaluate(contains, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt containsPositive = validDualRule(
      'D_Contains_Positive'
    );
    containsPositive.DataQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}';
    containsPositive.FieldToRead__c = 'BillingCity';
    containsPositive.CompareToQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}';
    containsPositive.CompareToField__c = 'BillingCity';
    containsPositive.Operator__c = 'Contains';
    assertStatus(
      evaluator.evaluate(containsPositive, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt numericOrder = validDualRule(
      'D_Numeric_Order'
    );
    numericOrder.DataQuery__c = 'SELECT AnnualRevenue FROM Account WHERE Id = {!Id}';
    numericOrder.FieldToRead__c = 'AnnualRevenue';
    numericOrder.CompareToQuery__c = 'SELECT COUNT(Id) totalCount FROM Contact WHERE AccountId = {!Id}';
    numericOrder.Operator__c = 'GreaterThan';
    assertStatus(
      evaluator.evaluate(numericOrder, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt dateOrder = validDualRule('D_Date_Order');
    dateOrder.DataQuery__c = 'SELECT CloseDate FROM Opportunity WHERE AccountId = {!Id} LIMIT 1';
    dateOrder.FieldToRead__c = 'CloseDate';
    dateOrder.CompareToQuery__c = 'SELECT CloseDate FROM Opportunity WHERE AccountId = {!Id} LIMIT 1';
    dateOrder.CompareToField__c = 'CloseDate';
    dateOrder.Operator__c = 'LessThanOrEqual';
    assertStatus(
      evaluator.evaluate(dateOrder, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt nullSkip = validDualRule('D_Null_Skip');
    nullSkip.DataQuery__c = 'SELECT Description FROM Account WHERE Id = {!Id}';
    nullSkip.FieldToRead__c = 'Description';
    nullSkip.CompareToQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}';
    nullSkip.CompareToField__c = 'BillingCity';
    nullSkip.WhenValueIsEmpty__c = 'SkipRecordsWithMissingValue';
    nullSkip.WhenZeroRows__c = 'Skip';
    assertStatus(
      evaluator.evaluate(nullSkip, accountRecord.Id, accountRecord),
      'SKIPPED'
    );

    Record_Health_Check_Rule__mdt nullFail = nullSkip.clone();
    nullFail.DeveloperName = 'D_Null_Fail';
    nullFail.WhenValueIsEmpty__c = 'MissingMeansNoMatch';
    assertStatus(
      evaluator.evaluate(nullFail, accountRecord.Id, accountRecord),
      'FAIL'
    );

    Record_Health_Check_Rule__mdt nullBlank = nullSkip.clone();
    nullBlank.DeveloperName = 'D_Null_Blank';
    nullBlank.WhenValueIsEmpty__c = 'TreatMissingAsBlank';
    nullBlank.Operator__c = 'Equals';
    nullBlank.CompareToQuery__c = 'SELECT Description FROM Account WHERE Id = {!Id}';
    nullBlank.CompareToField__c = 'Description';
    assertStatus(
      evaluator.evaluate(nullBlank, accountRecord.Id, accountRecord),
      'PASS'
    );

    // SCAN-46 (T-04): a zero-row query in OneResult is governed by
    // WhenZeroRows__c, NOT by the null-value behavior. The impossible Name filter
    // guarantees an empty primary regardless of org data. Before the fix, an empty
    // side with MissingMeansNoMatch wrongly FAILed instead of honoring WhenZeroRows.
    Record_Health_Check_Rule__mdt emptyPrimarySkip = validDualRule(
      'D_Empty_Primary_Skip'
    );
    emptyPrimarySkip.DataQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id} AND Name = \'__rhc_no_match__\'';
    emptyPrimarySkip.FieldToRead__c = 'BillingCity';
    emptyPrimarySkip.CompareToQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}';
    emptyPrimarySkip.CompareToField__c = 'BillingCity';
    emptyPrimarySkip.Operator__c = 'Equals';
    emptyPrimarySkip.WhenValueIsEmpty__c = 'MissingMeansNoMatch';
    emptyPrimarySkip.WhenZeroRows__c = 'Skip';
    assertStatus(
      evaluator.evaluate(emptyPrimarySkip, accountRecord.Id, accountRecord),
      'SKIPPED'
    );

    Record_Health_Check_Rule__mdt emptyPrimaryFail = emptyPrimarySkip.clone();
    emptyPrimaryFail.DeveloperName = 'D_Empty_Primary_Fail';
    emptyPrimaryFail.WhenZeroRows__c = 'Fail';
    assertStatus(
      evaluator.evaluate(emptyPrimaryFail, accountRecord.Id, accountRecord),
      'FAIL'
    );

    // WhenZeroRows = UnableToEvaluate on an empty side surfaces NO_ROWS_RETURNED.
    Record_Health_Check_Rule__mdt emptyPrimaryUnable = emptyPrimarySkip.clone();
    emptyPrimaryUnable.DeveloperName = 'D_Empty_Primary_Unable';
    emptyPrimaryUnable.WhenZeroRows__c = 'UnableToEvaluate';
    RecordHealthCheckResult unableResult = evaluator.evaluate(
      emptyPrimaryUnable,
      accountRecord.Id,
      accountRecord
    );
    assertStatus(unableResult, 'UNABLE_TO_EVALUATE');
    System.assertEquals('NO_ROWS_RETURNED', unableResult.reasonCode);

    // An invalid query field surfaces through the dual runQuery error path.
    Record_Health_Check_Rule__mdt badQuery = emptyPrimarySkip.clone();
    badQuery.DeveloperName = 'D_Bad_Query';
    badQuery.DataQuery__c = 'SELECT NoSuchField__zzz FROM Account WHERE Id = {!Id}';
    badQuery.FieldToRead__c = 'NoSuchField__zzz';
    RecordHealthCheckResult badQueryResult = evaluator.evaluate(
      badQuery,
      accountRecord.Id,
      accountRecord
    );
    assertStatus(badQueryResult, 'UNABLE_TO_EVALUATE');

    Record_Health_Check_Rule__mdt listOverlap = validDualRule('D_List_Overlap');
    listOverlap.WhenMultipleRows__c = 'CompareAsLists';
    listOverlap.Operator__c = 'ListsOverlap';
    listOverlap.DataQuery__c = 'SELECT MailingCity FROM Contact WHERE AccountId = {!Id}';
    listOverlap.FieldToRead__c = 'MailingCity';
    listOverlap.CompareToQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}';
    listOverlap.CompareToField__c = 'BillingCity';
    assertStatus(
      evaluator.evaluate(listOverlap, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt containsAll = listOverlap.clone();
    containsAll.DeveloperName = 'D_List_Contains_All';
    containsAll.Operator__c = 'ListContainsAll';
    assertStatus(
      evaluator.evaluate(containsAll, accountRecord.Id, accountRecord),
      'FAIL'
    );

    Record_Health_Check_Rule__mdt containsAllPass = listOverlap.clone();
    containsAllPass.DeveloperName = 'D_List_Contains_All_Pass';
    containsAllPass.Operator__c = 'ListContainsAll';
    containsAllPass.CompareToQuery__c = 'SELECT MailingCity FROM Contact WHERE AccountId = {!Id}';
    containsAllPass.CompareToField__c = 'MailingCity';
    assertStatus(
      evaluator.evaluate(containsAllPass, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt exactMatch = listOverlap.clone();
    exactMatch.DeveloperName = 'D_Exact_Match';
    exactMatch.Operator__c = 'ExactListMatch';
    exactMatch.CompareToQuery__c = 'SELECT MailingCity FROM Contact WHERE AccountId = {!Id}';
    exactMatch.CompareToField__c = 'MailingCity';
    assertStatus(
      evaluator.evaluate(exactMatch, accountRecord.Id, accountRecord),
      'PASS'
    );

    // SCAN-44: CompareAsLists where every primary value is null and dropped by
    // SkipRecordsWithMissingValue → empty list with non-empty rows → SKIPPED
    // (indeterminate), not a silent FAIL from comparing empty sets.
    Record_Health_Check_Rule__mdt allNullSkip = listOverlap.clone();
    allNullSkip.DeveloperName = 'D_List_All_Null_Skip';
    allNullSkip.DataQuery__c = 'SELECT Description FROM Account WHERE Id = {!Id}';
    allNullSkip.FieldToRead__c = 'Description';
    allNullSkip.CompareToQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}';
    allNullSkip.CompareToField__c = 'BillingCity';
    allNullSkip.WhenValueIsEmpty__c = 'SkipRecordsWithMissingValue';
    assertStatus(
      evaluator.evaluate(allNullSkip, accountRecord.Id, accountRecord),
      'SKIPPED'
    );

    // MissingMeansNoMatch keeps null values as distinct sentinels (non-empty
    // list), so an all-null primary cannot overlap a real comparison value.
    Record_Health_Check_Rule__mdt allNullNoMatch = allNullSkip.clone();
    allNullNoMatch.DeveloperName = 'D_List_All_Null_NoMatch';
    allNullNoMatch.WhenValueIsEmpty__c = 'MissingMeansNoMatch';
    assertStatus(
      evaluator.evaluate(allNullNoMatch, accountRecord.Id, accountRecord),
      'FAIL'
    );

    // TreatMissingAsBlank coerces a null value to '' (a matchable blank).
    Record_Health_Check_Rule__mdt allNullBlank = allNullSkip.clone();
    allNullBlank.DeveloperName = 'D_List_All_Null_Blank';
    allNullBlank.WhenValueIsEmpty__c = 'TreatMissingAsBlank';
    allNullBlank.Operator__c = 'ListContainsAll';
    allNullBlank.CompareToQuery__c = 'SELECT Description FROM Account WHERE Id = {!Id}';
    allNullBlank.CompareToField__c = 'Description';
    assertStatus(
      evaluator.evaluate(allNullBlank, accountRecord.Id, accountRecord),
      'PASS'
    );

    // WhenZeroRows = Pass on a genuinely empty side.
    Record_Health_Check_Rule__mdt emptyPass = listOverlap.clone();
    emptyPass.DeveloperName = 'D_List_Empty_Pass';
    emptyPass.DataQuery__c = 'SELECT MailingCity FROM Contact WHERE AccountId = {!Id} AND LastName = \'__rhc_no_match__\'';
    emptyPass.WhenZeroRows__c = 'Pass';
    assertStatus(
      evaluator.evaluate(emptyPass, accountRecord.Id, accountRecord),
      'PASS'
    );

    // OneResult FAIL with a blank MessageWhenFailed falls back to the default text.
    Record_Health_Check_Rule__mdt blankMsgFail = validDualRule(
      'D_Blank_Msg_Fail'
    );
    blankMsgFail.DataQuery__c = 'SELECT AnnualRevenue FROM Account WHERE Id = {!Id}';
    blankMsgFail.FieldToRead__c = 'AnnualRevenue';
    blankMsgFail.CompareToQuery__c = 'SELECT AnnualRevenue FROM Account WHERE Id = {!Id}';
    blankMsgFail.CompareToField__c = 'AnnualRevenue';
    blankMsgFail.Operator__c = 'GreaterThan';
    blankMsgFail.MessageWhenFailed__c = null;
    RecordHealthCheckResult blankMsgResult = evaluator.evaluate(
      blankMsgFail,
      accountRecord.Id,
      accountRecord
    );
    assertStatus(blankMsgResult, 'FAIL');
    System.assertEquals('Check failed.', blankMsgResult.message);

    // A template-invalid query (disallowed access level) surfaces through the
    // dual runQuery TemplateException path.
    Record_Health_Check_Rule__mdt templateBad = validDualRule('D_Template_Bad');
    templateBad.DataQuery__c = 'SELECT Id FROM Account WHERE Id = {!Id} WITH SYSTEM_MODE';
    RecordHealthCheckResult templateBadResult = evaluator.evaluate(
      templateBad,
      accountRecord.Id,
      accountRecord
    );
    assertStatus(templateBadResult, 'UNABLE_TO_EVALUATE');

    Record_Health_Check_Rule__mdt exactMismatch = exactMatch.clone();
    exactMismatch.DeveloperName = 'D_Exact_Mismatch';
    exactMismatch.CompareToQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}';
    exactMismatch.CompareToField__c = 'BillingCity';
    assertStatus(
      evaluator.evaluate(exactMismatch, accountRecord.Id, accountRecord),
      'FAIL'
    );

    Record_Health_Check_Rule__mdt listsNoOverlap = listOverlap.clone();
    listsNoOverlap.DeveloperName = 'D_Lists_No_Overlap';
    listsNoOverlap.CompareToQuery__c = 'SELECT BillingState FROM Account WHERE Id = {!Id}';
    listsNoOverlap.CompareToField__c = 'BillingState';
    assertStatus(
      evaluator.evaluate(listsNoOverlap, accountRecord.Id, accountRecord),
      'FAIL'
    );

    Record_Health_Check_Rule__mdt emptyListPass = listOverlap.clone();
    emptyListPass.DeveloperName = 'D_Empty_List_Pass';
    emptyListPass.DataQuery__c = 'SELECT MailingCity FROM Contact WHERE AccountId = null';
    emptyListPass.WhenZeroRows__c = 'Pass';
    assertStatus(
      evaluator.evaluate(emptyListPass, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt emptyListUnable = emptyListPass.clone();
    emptyListUnable.DeveloperName = 'D_Empty_List_Unable';
    emptyListUnable.WhenZeroRows__c = 'UnableToEvaluate';
    assertStatus(
      evaluator.evaluate(emptyListUnable, accountRecord.Id, accountRecord),
      'UNABLE_TO_EVALUATE'
    );

    Record_Health_Check_Rule__mdt emptyListSkip = emptyListPass.clone();
    emptyListSkip.DeveloperName = 'D_Empty_List_Skip';
    emptyListSkip.WhenZeroRows__c = 'Skip';
    assertStatus(
      evaluator.evaluate(emptyListSkip, accountRecord.Id, accountRecord),
      'SKIPPED'
    );

    Record_Health_Check_Rule__mdt multipleRows = validDualRule(
      'D_Multiple_Rows'
    );
    multipleRows.DataQuery__c = 'SELECT Id FROM Contact WHERE AccountId = {!Id}';
    multipleRows.FieldToRead__c = 'Id';
    assertReason(
      evaluator.evaluate(multipleRows, accountRecord.Id, accountRecord),
      'MULTIPLE_ROWS_RETURNED'
    );

    Record_Health_Check_Rule__mdt missingFieldName = validDualRule(
      'D_Missing_Field_Name'
    );
    missingFieldName.DataQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}';
    missingFieldName.FieldToRead__c = null;
    assertReason(
      evaluator.evaluate(missingFieldName, accountRecord.Id, accountRecord),
      'INVALID_SOQL_TEMPLATE'
    );

    Record_Health_Check_Rule__mdt badFieldName = listOverlap.clone();
    badFieldName.DeveloperName = 'D_Bad_Field_Name';
    badFieldName.FieldToRead__c = 'Missing__c';
    assertReason(
      evaluator.evaluate(badFieldName, accountRecord.Id, accountRecord),
      'INVALID_SOQL_TEMPLATE'
    );

    Record_Health_Check_Rule__mdt invalidMode = validDualRule(
      'D_Invalid_Mode_Runtime'
    );
    invalidMode.WhenMultipleRows__c = 'Bogus';
    assertReason(
      evaluator.evaluate(invalidMode, accountRecord.Id, accountRecord),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt invalidListComparator = listOverlap.clone();
    invalidListComparator.DeveloperName = 'D_Invalid_List_Comparator_Runtime';
    invalidListComparator.Operator__c = 'Equals';
    assertReason(
      evaluator.evaluate(
        invalidListComparator,
        accountRecord.Id,
        accountRecord
      ),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt incompatible = validDualRule(
      'D_Incompatible'
    );
    incompatible.DataQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}';
    incompatible.FieldToRead__c = 'BillingCity';
    incompatible.CompareToQuery__c = 'SELECT BillingState FROM Account WHERE Id = {!Id}';
    incompatible.CompareToField__c = 'BillingState';
    incompatible.Operator__c = 'GreaterThan';
    assertReason(
      evaluator.evaluate(incompatible, accountRecord.Id, accountRecord),
      'INCOMPATIBLE_COMPARISON_TYPES'
    );

    Record_Health_Check_Rule__mdt maxRows = validDualRule('D_Max_Rows');
    maxRows.DataQuery__c = 'SELECT Id FROM Contact WHERE AccountId = {!Id}';
    maxRows.FieldToRead__c = 'Id';
    maxRows.MaxRows__c = 1;
    assertReason(
      evaluator.evaluate(maxRows, accountRecord.Id, accountRecord),
      'GOVERNOR_LIMIT_RISK'
    );
  }

  @IsTest
  static void formulaEvaluatorCoversPassFailUnableAndMergeFields() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckFormulaEvaluator evaluator = new RecordHealthCheckFormulaEvaluator();

    Record_Health_Check_Rule__mdt passRule = baseRule('F_Pass', 'Formula');
    passRule.PassFailFormula__c = 'NOT(ISBLANK(BillingCity))';
    assertStatus(
      evaluator.evaluate(passRule, accountRecord.Id, accountRecord),
      'PASS'
    );

    Record_Health_Check_Rule__mdt failRule = baseRule('F_Fail', 'Formula');
    failRule.PassFailFormula__c = 'ISBLANK(BillingCity)';
    failRule.MessageWhenFailed__c = '{!Name} city is {!BillingCity} and bad token {!Missing__c}.';
    RecordHealthCheckResult failResult = evaluator.evaluate(
      failRule,
      accountRecord.Id,
      accountRecord
    );
    assertStatus(failResult, 'FAIL');
    System.assert(failResult.message.contains(accountRecord.Name));
    // Formula checks surface the expression as the expected condition, quoted
    // for uniformity with every other expected value.
    System.assertEquals(
      '"ISBLANK(BillingCity)"',
      failResult.expectedValue,
      'Formula FAIL should expose the formula as the expected condition'
    );

    Record_Health_Check_Rule__mdt nonBoolean = baseRule(
      'F_Non_Boolean',
      'Formula'
    );
    nonBoolean.PassFailFormula__c = 'BillingCity';
    assertReason(
      evaluator.evaluate(nonBoolean, accountRecord.Id, accountRecord),
      'INVALID_FORMULA'
    );

    String[] reasonOut = new List<String>{ '' };
    System.assertEquals(
      true,
      evaluator.evaluateApplicabilityFormula(
        'NOT(ISBLANK(BillingCity))',
        accountRecord,
        reasonOut
      )
    );
    System.assertEquals(
      null,
      evaluator.evaluateApplicabilityFormula(
        'BillingCity',
        accountRecord,
        reasonOut
      )
    );
    System.assertEquals('INVALID_FORMULA', reasonOut[0]);

    System.assertEquals(
      accountRecord.BillingCity,
      evaluator.resolveScalar('BillingCity', accountRecord)
    );
    System.assertEquals(
      accountRecord.AnnualRevenue,
      evaluator.resolveScalar('AnnualRevenue', accountRecord)
    );
    System.assertNotEquals(
      null,
      evaluator.resolveScalar('TODAY()', accountRecord)
    );
    System.assertNotEquals(
      null,
      evaluator.resolveScalar('NOW()', accountRecord)
    );
    System.assertEquals(
      null,
      evaluator.resolveMergeFields(null, accountRecord)
    );

    try {
      evaluator.resolveScalar('Definitely_Not_A_Field__c', accountRecord);
      System.assert(false, 'Expected invalid formula exception.');
    } catch (RecordHealthCheckFormulaEvaluator.FormulaEvaluationException ex) {
      System.assertEquals('FIELD_NOT_ACCESSIBLE', ex.reasonCode);
    }

    RecordHealthCheckFormulaEvaluator.formulaEvalCallCount = 95;
    try {
      evaluator.resolveScalar('BillingCity', accountRecord);
      System.assert(false, 'Expected FormulaEval limit guard.');
    } catch (RecordHealthCheckFormulaEvaluator.FormulaEvaluationException ex) {
      System.assertEquals('FORMULA_EVAL_LIMIT', ex.reasonCode);
    } finally {
      RecordHealthCheckFormulaEvaluator.formulaEvalCallCount = 0;
    }
  }

  @IsTest
  static void formulaEvaluatorHonorsDeclaredReturnType() {
    // SCAN-01: a declared scalar return type (ScalarFormulaReturnType__c) resolves
    // the formula in a single FormulaEval call instead of probing up to eight types.
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckFormulaEvaluator evaluator = new RecordHealthCheckFormulaEvaluator();

    // Each picklist value maps to its FormulaReturnType; Auto/blank/unknown → null.
    System.assertEquals(
      formulaeval.FormulaReturnType.STRING,
      evaluator.mapDeclaredReturnType('Text')
    );
    System.assertEquals(
      formulaeval.FormulaReturnType.DECIMAL,
      evaluator.mapDeclaredReturnType('Number')
    );
    System.assertEquals(
      formulaeval.FormulaReturnType.BOOLEAN,
      evaluator.mapDeclaredReturnType('Boolean')
    );
    System.assertEquals(
      formulaeval.FormulaReturnType.DATE,
      evaluator.mapDeclaredReturnType('Date')
    );
    System.assertEquals(
      formulaeval.FormulaReturnType.DATETIME,
      evaluator.mapDeclaredReturnType('DateTime')
    );
    System.assertEquals(null, evaluator.mapDeclaredReturnType('Auto'));
    System.assertEquals(null, evaluator.mapDeclaredReturnType(null));
    System.assertEquals(null, evaluator.mapDeclaredReturnType('Bogus'));

    // Correct declaration ('Text' for a text field) → exactly one FormulaEval call.
    RecordHealthCheckFormulaEvaluator.formulaEvalCallCount = 0;
    RecordHealthCheckFormulaEvaluator.resolvedReturnTypeByFormula.clear();
    System.assertEquals(
      accountRecord.BillingCity,
      evaluator.resolveScalar('BillingCity', accountRecord, 'Text')
    );
    System.assertEquals(
      1,
      RecordHealthCheckFormulaEvaluator.formulaEvalCallCount,
      'Declared Text type should resolve a string formula in one FormulaEval call.'
    );

    // Auto (no declared type) probes multiple types but resolves the same value.
    RecordHealthCheckFormulaEvaluator.formulaEvalCallCount = 0;
    RecordHealthCheckFormulaEvaluator.resolvedReturnTypeByFormula.clear();
    System.assertEquals(
      accountRecord.BillingCity,
      evaluator.resolveScalar('BillingCity', accountRecord, null)
    );
    System.assert(
      RecordHealthCheckFormulaEvaluator.formulaEvalCallCount > 1,
      'Auto (no declared type) should probe multiple return types.'
    );

    // A mis-declared type ('Number' for a text field) degrades to a full probe
    // and still returns the correct value rather than failing the check.
    RecordHealthCheckFormulaEvaluator.formulaEvalCallCount = 0;
    RecordHealthCheckFormulaEvaluator.resolvedReturnTypeByFormula.clear();
    System.assertEquals(
      accountRecord.BillingCity,
      evaluator.resolveScalar('BillingCity', accountRecord, 'Number')
    );
    System.assert(
      RecordHealthCheckFormulaEvaluator.formulaEvalCallCount > 1,
      'A wrong declared type should fall back to probing and still resolve.'
    );
  }

  @IsTest
  static void engineHelpersCoverApplicabilityAndRecordLoading() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckEngine engine = new RecordHealthCheckEngine();

    Record_Health_Check_Rule__mdt always = queryRule('E_Always');
    always.RunThisCheckWhen__c = 'Always';
    System.assertEquals(
      null,
      engine.checkApplicability(always, accountRecord.Id, accountRecord)
    );

    Record_Health_Check_Rule__mdt formulaSkip = queryRule('E_Formula_Skip');
    formulaSkip.RunThisCheckWhen__c = 'Formula';
    formulaSkip.RunWhenFormula__c = 'FALSE';
    assertStatus(
      engine.checkApplicability(formulaSkip, accountRecord.Id, accountRecord),
      'SKIPPED'
    );

    Record_Health_Check_Rule__mdt formulaPass = formulaSkip.clone();
    formulaPass.DeveloperName = 'E_Formula_Pass';
    formulaPass.RunWhenFormula__c = 'TRUE';
    System.assertEquals(
      null,
      engine.checkApplicability(formulaPass, accountRecord.Id, accountRecord)
    );

    Record_Health_Check_Rule__mdt formulaUnable = formulaSkip.clone();
    formulaUnable.DeveloperName = 'E_Formula_Unable';
    formulaUnable.RunWhenFormula__c = 'BillingCity';
    assertReason(
      engine.checkApplicability(formulaUnable, accountRecord.Id, accountRecord),
      'INVALID_FORMULA'
    );

    Record_Health_Check_Rule__mdt soqlPass = queryRule('E_SOQL_Pass');
    soqlPass.RunThisCheckWhen__c = 'SOQL';
    soqlPass.RunWhenCountQuery__c = 'SELECT COUNT(Id) totalCount FROM Contact WHERE AccountId = {!Id}';
    soqlPass.CountOperator__c = 'GreaterThan';
    soqlPass.CountThreshold__c = 0;
    System.assertEquals(
      null,
      engine.checkApplicability(soqlPass, accountRecord.Id, accountRecord)
    );

    Record_Health_Check_Rule__mdt soqlSkip = soqlPass.clone();
    soqlSkip.DeveloperName = 'E_SOQL_Skip';
    soqlSkip.CountOperator__c = 'Equals';
    soqlSkip.CountThreshold__c = 999;
    assertStatus(
      engine.checkApplicability(soqlSkip, accountRecord.Id, accountRecord),
      'SKIPPED'
    );

    Record_Health_Check_Rule__mdt soqlMissing = soqlPass.clone();
    soqlMissing.DeveloperName = 'E_SOQL_Missing';
    soqlMissing.RunWhenCountQuery__c = null;
    assertReason(
      engine.checkApplicability(soqlMissing, accountRecord.Id, accountRecord),
      'INVALID_SOQL_TEMPLATE'
    );

    Record_Health_Check_Rule__mdt soqlBadComparator = soqlPass.clone();
    soqlBadComparator.DeveloperName = 'E_SOQL_Bad_Comparator';
    soqlBadComparator.CountOperator__c = 'Around';
    assertReason(
      engine.checkApplicability(
        soqlBadComparator,
        accountRecord.Id,
        accountRecord
      ),
      'INVALID_COMPARATOR'
    );

    Record_Health_Check_Rule__mdt invalidMode = soqlPass.clone();
    invalidMode.DeveloperName = 'E_Invalid_Mode';
    invalidMode.RunThisCheckWhen__c = 'Bogus';
    assertReason(
      engine.checkApplicability(invalidMode, accountRecord.Id, accountRecord),
      'INVALID_CONFIG'
    );

    System.assertEquals(
      true,
      engine.applyApplicabilityComparator('Equals', 1, 1)
    );
    System.assertEquals(
      true,
      engine.applyApplicabilityComparator('NotEquals', 1, 2)
    );
    System.assertEquals(
      true,
      engine.applyApplicabilityComparator('GreaterThanOrEqual', 2, 2)
    );
    System.assertEquals(
      true,
      engine.applyApplicabilityComparator('LessThan', 1, 2)
    );
    System.assertEquals(
      true,
      engine.applyApplicabilityComparator('LessThanOrEqual', 2, 2)
    );
    System.assertEquals(
      null,
      engine.applyApplicabilityComparator('Nope', 1, 1)
    );

    Record_Health_Check_Rule__mdt fieldRule = queryRule('E_Field_Collection');
    fieldRule.PassFailFormula__c = 'AND(NOT(ISBLANK(BillingCity)), NOT(ISBLANK(Parent.BillingCity)))';
    fieldRule.MessageWhenFailed__c = '{!Name} {!BillingCity} {!Parent.BillingCity}';
    fieldRule.MessageWhenCannotRun__c = '{!Phone}';
    fieldRule.RunThisCheckWhen__c = 'Formula';
    fieldRule.RunWhenFormula__c = 'NOT(ISBLANK(Website))';
    Set<String> fields = engine.collectRecordFields(
      fieldRule,
      Account.SObjectType
    );
    System.assert(fields.contains('Id'));
    System.assert(fields.contains('BillingCity'));
    System.assert(fields.contains('Parent.BillingCity'));
    System.assertNotEquals(
      null,
      engine.loadRecord(accountRecord.Id, fieldRule)
    );
  }

  @IsTest
  static void apexDispatcherAndExampleRuleCoverPluginBranches() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckApexEvaluatorDispatcher dispatcher = new RecordHealthCheckApexEvaluatorDispatcher();

    assertReason(
      dispatcher.evaluate(
        apexRule('A_Blank', null, null),
        accountRecord.Id,
        accountRecord
      ),
      'APEX_CLASS_NOT_FOUND'
    );
    assertReason(
      dispatcher.evaluate(
        apexRule('A_Missing', 'MissingClassName', null),
        accountRecord.Id,
        accountRecord
      ),
      'APEX_CLASS_NOT_FOUND'
    );
    assertReason(
      dispatcher.evaluate(
        apexRule('A_Not_Interface', 'RecordHealthCheckResult', null),
        accountRecord.Id,
        accountRecord
      ),
      'APEX_CLASS_NOT_FOUND'
    );
    assertReason(
      dispatcher.evaluate(
        apexRule('A_Null_Record', 'AccountHasRecentActivityCheck', null),
        null,
        accountRecord
      ),
      'APEX_EVALUATOR_ERROR'
    );

    Record_Health_Check_Rule__mdt finalizeRule = apexRule(
      'A_Finalize',
      'AccountHasRecentActivityCheck',
      null
    );
    RecordHealthCheckResult fallback = new RecordHealthCheckResult();
    RecordHealthCheckResult invalidStatus = new RecordHealthCheckResult();
    invalidStatus.status = 'NOT_REAL';
    assertReason(
      dispatcher.finalizeApexResult(
        finalizeRule,
        accountRecord,
        fallback,
        invalidStatus
      ),
      'APEX_EVALUATOR_ERROR'
    );

    RecordHealthCheckResult skippedStatus = new RecordHealthCheckResult();
    skippedStatus.status = 'SKIPPED';
    assertStatus(
      dispatcher.finalizeApexResult(
        finalizeRule,
        accountRecord,
        new RecordHealthCheckResult(),
        skippedStatus
      ),
      'SKIPPED'
    );
    assertReason(
      dispatcher.evaluate(
        apexRule(
          'A_Bad_Params',
          'AccountHasRecentActivityCheck',
          '["not-object"]'
        ),
        accountRecord.Id,
        accountRecord
      ),
      'INVALID_APEX_PARAMETERS'
    );
    assertReason(
      dispatcher.evaluate(
        apexRule('A_Bad_Json', 'AccountHasRecentActivityCheck', '{"daysBack":'),
        accountRecord.Id,
        accountRecord
      ),
      'INVALID_APEX_PARAMETERS'
    );

    // The shared @testSetup seeds a completed Task on the account, so remove all
    // activity here to make the no-recent-activity FAIL path deterministic and
    // independent of the factory and org automation. The PASS path below
    // re-adds a completed Task via createCompletedTask.
    delete [SELECT Id FROM Task WHERE WhatId = :accountRecord.Id];
    delete [SELECT Id FROM Event WHERE WhatId = :accountRecord.Id];

    RecordHealthCheckResult failResult = dispatcher.evaluate(
      apexRule('A_Fail', 'AccountHasRecentActivityCheck', '{"daysBack":90}'),
      accountRecord.Id,
      accountRecord
    );
    assertStatus(failResult, 'FAIL');
    System.assertEquals('Warning', failResult.severity);
    System.assertEquals(
      'Apex failure for ' + accountRecord.Name,
      failResult.message
    );

    RecordHealthCheckContext context = new RecordHealthCheckContext();
    context.recordId = accountRecord.Id;
    context.parameters = new Map<String, Object>{ 'daysBack' => '90' };
    assertStatus(new AccountHasRecentActivityCheck().evaluate(context), 'FAIL');

    RecordHealthCheckTestDataFactory.createCompletedTask(accountRecord.Id);
    assertStatus(new AccountHasRecentActivityCheck().evaluate(context), 'PASS');
    assertStatus(
      dispatcher.evaluate(
        apexRule('A_Pass', 'AccountHasRecentActivityCheck', '{"daysBack":90}'),
        accountRecord.Id,
        accountRecord
      ),
      'PASS'
    );

    context.parameters = new Map<String, Object>{ 'daysBack' => 'invalid' };
    assertStatus(new AccountHasRecentActivityCheck().evaluate(context), 'PASS');
  }

  @IsTest
  static void exampleApexRuleCoversOpenOpportunityHealth() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();

    // The @testSetup seeds an open "Coverage Opportunity" with a null NextStep and
    // a null (read-only) LastActivityDate, which AccountOpenOpportunityHealthCheck
    // also flags as unhealthy on run dates where its CloseDate lands outside the
    // current quarter. Make every pre-seeded open Opp healthy so this test isolates
    // the single unhealthy Opp it creates below (a NextStep alone clears the flag;
    // the in-quarter CloseDate keeps it healthy regardless of the run date).
    Date inQuarter = AccountOpenOpportunityHealthCheck.getQuarterStart(
        Date.today()
      )
      .addDays(15);
    List<Opportunity> seededOpenOpps = [
      SELECT Id
      FROM Opportunity
      WHERE AccountId = :accountRecord.Id AND IsClosed = FALSE
    ];
    for (Opportunity seeded : seededOpenOpps) {
      seeded.NextStep = 'Seeded follow up';
      seeded.CloseDate = inQuarter;
    }
    update seededOpenOpps;

    Opportunity unhealthyOpp = RecordHealthCheckTestDataFactory.createOpportunity(
      accountRecord.Id,
      'Unhealthy Opp',
      1000
    );
    // LastActivityDate is a read-only system field (derived from activities) and cannot be
    // assigned in Apex. A freshly created Opportunity already has LastActivityDate == null,
    // which AccountOpenOpportunityHealthCheck.isUnhealthy treats as stale — so a null NextStep
    // plus an out-of-quarter CloseDate is sufficient to make this Opp unhealthy.
    unhealthyOpp.NextStep = null;
    unhealthyOpp.CloseDate = Date.today().addDays(120);
    update unhealthyOpp;

    RecordHealthCheckContext oppContext = new RecordHealthCheckContext();
    oppContext.recordId = accountRecord.Id;
    oppContext.parameters = new Map<String, Object>{ 'staleDays' => 30 };
    RecordHealthCheckResult oppFail = new AccountOpenOpportunityHealthCheck()
      .evaluate(oppContext);
    assertStatus(oppFail, 'FAIL');
    System.assertEquals('1 unhealthy', oppFail.actualValue);

    unhealthyOpp.NextStep = 'Follow up';
    update unhealthyOpp;
    assertStatus(
      new AccountOpenOpportunityHealthCheck().evaluate(oppContext),
      'PASS'
    );

    Date quarterStart = AccountOpenOpportunityHealthCheck.getQuarterStart(
      Date.today()
    );
    System.assertEquals(
      Date.newInstance(Date.today().year(), quarterStart.month(), 1),
      quarterStart
    );
  }

  // Evaluating every check of all packaged Check Sets in a single transaction
  // exceeds the 100-SOQL governor limit (88 checks, each loading the record).
  // Production runs each Check Set in its own request, so the sweep is split
  // across several @IsTest methods (separate transactions) grouped to stay
  // under the limit while still exercising every packaged check.
  private static void sweepPackagedConfigs(List<String> configNames) {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    Map<String, RecordHealthCheckDefinitionResponse> responsesByConfig = new Map<String, RecordHealthCheckDefinitionResponse>();
    for (String configName : configNames) {
      try {
        responsesByConfig.put(
          configName,
          RecordHealthCheckController.getCheckDefinitions(
            configName,
            accountRecord.Id,
            'cov-run'
          )
        );
      } catch (Exception ex) {
        System.assert(
          false,
          'Packaged config failed to load: ' +
            configName +
            ' ' +
            ex.getMessage()
        );
      }
    }

    System.assert(
      !responsesByConfig.isEmpty(),
      'Expected packaged definition responses.'
    );
    for (String configName : responsesByConfig.keySet()) {
      for (
        RecordHealthCheckDefinition definition : responsesByConfig.get(
            configName
          )
          .checks
      ) {
        RecordHealthCheckResult result = RecordHealthCheckController.evaluateCheck(
          configName,
          definition.developerName,
          accountRecord.Id,
          'cov-run'
        );
        System.assertNotEquals(null, result.status);
      }
    }
  }

  @IsTest
  static void engineAndControllerCoverPackagedMetadataPaths() {
    sweepPackagedConfigs(
      new List<String>{
        'Account_Query_Coverage',
        'Account_Relationships',
        'Account_Data_Quality'
      }
    );
  }

  @IsTest
  static void engineAndControllerCoverPackagedMetadataPathsGroupTwo() {
    sweepPackagedConfigs(
      new List<String>{
        'Account_Everyday_Use_Cases',
        'Account_Aggregate_Coverage'
      }
    );
  }

  @IsTest
  static void engineAndControllerCoverPackagedMetadataPathsGroupThree() {
    sweepPackagedConfigs(
      new List<String>{ 'Account_Compare_Queries', 'Account_Advanced_Checks' }
    );
  }

  @IsTest
  static void engineAndControllerCoverErrorAndBoundaryPaths() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckEngine engine = new RecordHealthCheckEngine();

    sweepPackagedConfigs(
      new List<String>{
        'Account_Compliance_Audit',
        'Account_AppComp_Coverage',
        'Account_Formula_Coverage'
      }
    );

    assertReason(
      engine.evaluate('Missing_Config', 'Missing_Check', accountRecord.Id),
      'CONFIG_NOT_FOUND'
    );
    assertReason(
      engine.evaluate(
        'Account_Data_Quality',
        'Missing_Check',
        accountRecord.Id
      ),
      'CONFIG_NOT_FOUND'
    );
    assertReason(
      engine.evaluate(
        'Account_Data_Quality',
        'Account_QC_IsNotBlank',
        UserInfo.getUserId()
      ),
      'CONFIG_NOT_FOUND'
    );
    assertReason(
      engine.evaluate('Account_Data_Quality', 'Account_DQ_BillingCity', null),
      'NO_RECORD_CONTEXT'
    );

    try {
      RecordHealthCheckController.getCheckDefinitions(
        'Missing_Config',
        accountRecord.Id,
        'cov-run'
      );
      System.assert(false, 'Expected missing config exception.');
    } catch (AuraHandledException ex) {
      System.assert(ex.getMessage().contains('CONFIG_NOT_FOUND'));
    }

    RecordHealthCheckConfigService originalService = RecordHealthCheckController.configService;
    RecordHealthCheckEngine originalEngine = RecordHealthCheckController.engine;
    try {
      RecordHealthCheckController.configService = null;
      try {
        RecordHealthCheckController.getCheckDefinitions(
          'Account_Data_Quality',
          accountRecord.Id,
          'cov-run'
        );
        System.assert(false, 'Expected generic definition exception.');
      } catch (AuraHandledException ex) {
        // SCAN-02: an unexpected internal failure (here a null configService
        // NPE) surfaces as LOAD_FAILED, not CONFIG_NOT_FOUND, which stays
        // reserved for the explicit not-found ConfigException path.
        System.assert(
          ex.getMessage().contains('LOAD_FAILED'),
          'Expected LOAD_FAILED for unexpected load error, got: ' +
          ex.getMessage()
        );
      }

      RecordHealthCheckController.engine = null;
      RecordHealthCheckResult boundaryResult = RecordHealthCheckController.evaluateCheck(
        'Account_Data_Quality',
        'Account_DQ_BillingCity',
        accountRecord.Id,
        'cov-run'
      );
      assertReason(boundaryResult, 'APEX_EVALUATOR_ERROR');
    } finally {
      RecordHealthCheckController.configService = originalService;
      RecordHealthCheckController.engine = originalEngine;
    }
  }

  @IsTest
  static void mergeTokensResolveForNonFormulaCheckMessages() {
    // Regression (Task D): {!FieldName} merge tokens in MessageWhenCannotRun__c
    // and MessageWhenFailed__c must resolve for non-Formula check types too. The
    // packaged Query check Account_QC_ERB_UnableToEvaluate carries
    // "{!Name} has no open cases to evaluate. …" — the literal token must never
    // reach the UI. Isolated in its own test so it has fresh governor limits.
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();

    Test.startTest();
    RecordHealthCheckResult result = RecordHealthCheckController.evaluateCheck(
      'Account_Query_Coverage',
      'Account_QC_ERB_UnableToEvaluate',
      accountRecord.Id,
      'merge-token-run'
    );
    Test.stopTest();

    System.assertNotEquals(
      null,
      result.message,
      'Expected a user-facing message for the ERB check.'
    );
    System.assert(
      !result.message.contains('{!'),
      'Merge tokens must be resolved before reaching the UI: ' + result.message
    );
    if (result.status == 'UNABLE_TO_EVALUATE' || result.status == 'FAIL') {
      System.assert(
        result.message.contains(accountRecord.Name),
        'Resolved message should include the account name: ' + result.message
      );
    }
  }

  @IsTest
  static void evaluatorHelpersCoverRemainingEdgeBranches() {
    Account accountRecord = [
      SELECT Id, Name, BillingCity, BillingState, Description, AnnualRevenue
      FROM Account
      WHERE Id = :RecordHealthCheckTestDataFactory.getHealthyAccount().Id
    ];
    List<SObject> accountRows = new List<SObject>{ accountRecord };
    List<SObject> duplicateRows = new List<SObject>{
      accountRecord,
      accountRecord
    };
    List<SObject> emptyRows = new List<SObject>();

    RecordHealthCheckSoqlEvaluator soql = new RecordHealthCheckSoqlEvaluator();
    Exception queryException;
    try {
      Database.query('SELECT Missing__c FROM Account');
    } catch (System.QueryException ex) {
      queryException = ex;
    }
    System.assertNotEquals(null, queryException);
    assertReason(
      soql.applyEvaluationException(
        queryRule('Isolated_Query_Exception'),
        new RecordHealthCheckResult(),
        queryException
      ),
      'INVALID_SOQL_TEMPLATE'
    );
    assertReason(
      soql.applyEvaluationException(
        queryRule('Isolated_Evaluator_Exception'),
        new RecordHealthCheckResult(),
        new RecordHealthCheckEvaluatorException(
          'ISOLATED_SOQL',
          'isolated evaluator error'
        )
      ),
      'ISOLATED_SOQL'
    );
    assertReason(
      soql.applyEvaluationException(
        queryRule('Isolated_Generic_Exception'),
        new RecordHealthCheckResult(),
        new IllegalArgumentException('generic SOQL error')
      ),
      'APEX_EVALUATOR_ERROR'
    );
    Record_Health_Check_Rule__mdt query = queryRule('Helper_Query');
    query.WhenZeroRows__c = 'Fail';

    soql.validateNoDisallowedKeywords(
      'SELECT Last_Update__c FROM Account WHERE IsDeleted = false'
    );
    try {
      soql.validateNoDisallowedKeywords('SELECT Id FROM Account FOR UPDATE');
      System.assert(false, 'Expected disallowed phrase.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }

    System.assertEquals(
      1,
      soql.runQuery('SELECT COUNT() FROM Contact WHERE AccountId = null', 1)
        .size()
    );
    try {
      soql.runQuery('SELECT Id FROM Account', 0);
      System.assert(false, 'Expected row cap exception.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('GOVERNOR_LIMIT_RISK', ex.reasonCode);
    }
    try {
      soql.runQuery('SELECT NotAField__c FROM Account', 1);
      System.assert(false, 'Expected invalid query exception.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }

    System.assertEquals(
      accountRecord.BillingCity,
      soql.resolveScalarFromRow(accountRecord, 'BillingCity')
    );
    try {
      soql.resolveScalarFromRow(accountRecord, null);
      System.assert(false, 'Expected missing field exception.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
    System.assertEquals(
      1,
      soql.resolveFieldList(accountRows, 'BillingCity').size()
    );

    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applyUnaryComparator('IsBlank', ' ')
    );
    System.assertEquals(
      false,
      RecordHealthCheckComparatorEngine.applyUnaryComparator('IsNotBlank', null)
    );
    try {
      RecordHealthCheckComparatorEngine.applyUnaryComparator('Bogus', 'x');
      System.assert(false, 'Expected an invalid unary comparator exception.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_COMPARATOR', ex.reasonCode);
    }
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applySingleComparator(
        'Equals',
        5,
        '5',
        query
      )
    );
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applySingleComparator(
        'GreaterThanOrEqual',
        5,
        5,
        query
      )
    );
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applySingleComparator(
        'LessThan',
        Date.today(),
        Date.today().addDays(1),
        query
      )
    );
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applySingleComparator(
        'LessThanOrEqual',
        Datetime.now(),
        Datetime.now().addSeconds(1),
        query
      )
    );
    Record_Health_Check_Rule__mdt missingMeansNoMatch = query.clone();
    missingMeansNoMatch.WhenValueIsEmpty__c = 'MissingMeansNoMatch';
    System.assertEquals(
      false,
      RecordHealthCheckComparatorEngine.applySingleComparatorNullSafe(
        'Equals',
        null,
        'x',
        missingMeansNoMatch
      )
    );
    query.WhenValueIsEmpty__c = 'TreatMissingAsBlank';
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applySingleComparatorNullSafe(
        'Equals',
        null,
        '',
        query
      )
    );
    query.WhenValueIsEmpty__c = 'SkipRecordsWithMissingValue';
    System.assertEquals(
      null,
      RecordHealthCheckComparatorEngine.applySingleComparatorNullSafe(
        'Equals',
        null,
        '',
        query
      )
    );

    Record_Health_Check_Rule__mdt emptyPassRule = queryRule(
      'Helper_Empty_Pass'
    );
    emptyPassRule.WhenZeroRows__c = 'Pass';
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applyMultiRowComparator(
        emptyPassRule,
        emptyRows,
        'x',
        null
      )
    );
    Record_Health_Check_Rule__mdt anySkipped = queryRule('Helper_Any_Skipped');
    anySkipped.WhenMultipleRows__c = 'AnyRowPasses';
    anySkipped.WhenValueIsEmpty__c = 'SkipRecordsWithMissingValue';
    System.assertEquals(
      null,
      RecordHealthCheckComparatorEngine.applyMultiRowComparator(
        anySkipped,
        new List<Object>{ null },
        'x',
        null
      )
    );
    Record_Health_Check_Rule__mdt allSkipped = anySkipped.clone();
    allSkipped.DeveloperName = 'Helper_All_Skipped';
    allSkipped.WhenMultipleRows__c = 'AllRowsPass';
    System.assertEquals(
      null,
      RecordHealthCheckComparatorEngine.applyMultiRowComparator(
        allSkipped,
        new List<Object>{ null },
        'x',
        null
      )
    );
    Record_Health_Check_Rule__mdt badMode = anySkipped.clone();
    badMode.DeveloperName = 'Helper_Bad_Mode';
    badMode.WhenMultipleRows__c = 'Nope';
    try {
      RecordHealthCheckComparatorEngine.applyMultiRowComparator(
        badMode,
        new List<Object>{ 'x' },
        'x',
        null
      );
      System.assert(false, 'Expected invalid mode.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_COMPARATOR', ex.reasonCode);
    }

    query.WhenValueIsEmpty__c = 'MissingMeansNoMatch';
    System.assertEquals(
      false,
      RecordHealthCheckComparatorEngine.applyListComparator(
        'ListContainsAny',
        null,
        new List<Object>{ 'a' },
        query
      )
    );
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applyListComparator(
        'ListDoesNotContainAny',
        null,
        new List<Object>{ 'a' },
        query
      )
    );
    try {
      RecordHealthCheckComparatorEngine.applyListComparator(
        'BadList',
        'a',
        new List<Object>{ 'a' },
        query
      );
      System.assert(false, 'Expected invalid list comparator.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_COMPARATOR', ex.reasonCode);
    }
    System.assertEquals(
      false,
      RecordHealthCheckComparatorEngine.applyNullBehavior(
        'MissingMeansNoMatch',
        null,
        'x'
      )
    );
    System.assertEquals(
      null,
      RecordHealthCheckComparatorEngine.applyNullBehavior(
        'SkipRecordsWithMissingValue',
        null,
        'x'
      )
    );
    System.assertEquals(
      null,
      RecordHealthCheckComparatorEngine.applyNullBehavior(null, null, 'x')
    );
    System.assertEquals(
      false,
      RecordHealthCheckComparatorEngine.resolveEmptyBehavior('Fail')
    );
    System.assertEquals(
      null,
      RecordHealthCheckComparatorEngine.resolveEmptyBehavior('UnableToEvaluate')
    );
    System.assertEquals(
      'FAIL',
      soql.buildEmptyOrNullResult(query, new RecordHealthCheckResult(), null)
        .status
    );
    query.WhenZeroRows__c = 'Pass';
    System.assertEquals(
      'PASS',
      soql.buildEmptyOrNullResult(query, new RecordHealthCheckResult(), null)
        .status
    );
    query.WhenZeroRows__c = 'UnableToEvaluate';
    assertReason(
      soql.buildEmptyOrNullResult(query, new RecordHealthCheckResult(), null),
      'NO_ROWS_RETURNED'
    );
    System.assertEquals(
      true,
      RecordHealthCheckValueResolver.isNumericObject(Decimal.valueOf('1.5'))
    );
    System.assertEquals(
      false,
      RecordHealthCheckValueResolver.isNumericObject('1.5')
    );

    // ── Actual-vs-expected description helpers ──────────────────────────────
    System.assertEquals(
      'to equal',
      RecordHealthCheckComparatorEngine.humanComparator('Equals')
    );
    System.assertEquals(
      'at least',
      RecordHealthCheckComparatorEngine.humanComparator('GreaterThanOrEqual')
    );
    // Unknown comparator falls back to the raw API name
    System.assertEquals(
      'Mystery',
      RecordHealthCheckComparatorEngine.humanComparator('Mystery')
    );
    System.assertEquals(
      '(blank)',
      RecordHealthCheckComparatorEngine.formatValue(null)
    );
    System.assertEquals(
      '(blank)',
      RecordHealthCheckComparatorEngine.formatValue('   ')
    );
    System.assertEquals(
      '"Technology"',
      RecordHealthCheckComparatorEngine.formatValue('Technology')
    );
    // Numbers and Booleans are quoted too, so a mixed-type comparison such as
    // a COUNT check reads consistently (Found "1" … at least "2").
    System.assertEquals(
      '"1"',
      RecordHealthCheckComparatorEngine.formatValue(1)
    );
    System.assertEquals(
      '"true"',
      RecordHealthCheckComparatorEngine.formatValue(true)
    );
    System.assertEquals(
      '(none)',
      RecordHealthCheckComparatorEngine.formatList(new List<Object>())
    );
    System.assertEquals(
      '["A", "B"]',
      RecordHealthCheckComparatorEngine.formatList(new List<Object>{ 'A', 'B' })
    );
    // Over the preview cap, the list is truncated with a total count
    List<Object> big = new List<Object>();
    for (Integer i = 0; i < 12; i++) {
      big.add(i);
    }
    System.assert(
      RecordHealthCheckComparatorEngine.formatList(big).contains('(12 total)'),
      'Long lists should show a total count'
    );
    System.assertEquals(
      'to equal "Technology"',
      RecordHealthCheckComparatorEngine.describeExpected('Equals', 'Technology')
    );
    // Unary comparators have no operand
    System.assertEquals(
      'to not be blank',
      RecordHealthCheckComparatorEngine.describeExpected('IsNotBlank', null)
    );
    System.assertEquals(
      'to be one of ["North", "South"]',
      RecordHealthCheckComparatorEngine.describeExpectedList(
        'ListContainsAny',
        new List<Object>{ 'North', 'South' }
      )
    );

    RecordHealthCheckDualSoqlEvaluator dual = new RecordHealthCheckDualSoqlEvaluator();
    assertReason(
      dual.applyEvaluationException(
        validDualRule('Isolated_Dual_Query_Exception'),
        new RecordHealthCheckResult(),
        queryException
      ),
      'INVALID_SOQL_TEMPLATE'
    );
    assertReason(
      dual.applyEvaluationException(
        validDualRule('Isolated_Dual_Evaluator_Exception'),
        new RecordHealthCheckResult(),
        new RecordHealthCheckEvaluatorException(
          'ISOLATED_DUAL',
          'isolated dual error'
        )
      ),
      'ISOLATED_DUAL'
    );
    assertReason(
      dual.applyEvaluationException(
        validDualRule('Isolated_Dual_Generic_Exception'),
        new RecordHealthCheckResult(),
        new IllegalArgumentException('generic dual error')
      ),
      'APEX_EVALUATOR_ERROR'
    );
    Record_Health_Check_Rule__mdt dualRule = validDualRule('Helper_Dual');
    dualRule.WhenZeroRows__c = 'Fail';
    dualRule.FieldToRead__c = 'BillingCity';
    dualRule.CompareToField__c = 'BillingCity';
    dualRule.WhenValueIsEmpty__c = 'MissingMeansNoMatch';

    System.assertEquals(
      false,
      dual.evaluateSingleVsSingle(dualRule, emptyRows, accountRows)
    );
    dualRule.WhenValueIsEmpty__c = 'TreatMissingAsBlank';
    System.assertEquals(
      true,
      dual.evaluateSingleVsSingle(dualRule, emptyRows, emptyRows)
    );
    dualRule.WhenValueIsEmpty__c = null;
    System.assertEquals(
      null,
      dual.evaluateSingleVsSingle(dualRule, emptyRows, accountRows)
    );
    try {
      dual.resolveSingleValue(duplicateRows, 'Id', 'primary');
      System.assert(false, 'Expected multiple row exception.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('MULTIPLE_ROWS_RETURNED', ex.reasonCode);
    }
    try {
      dual.resolveSingleValue(accountRows, null, 'primary');
      System.assert(false, 'Expected missing field exception.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }

    Record_Health_Check_Rule__mdt dualList = validDualRule('Helper_Dual_List');
    dualList.WhenMultipleRows__c = 'CompareAsLists';
    dualList.FieldToRead__c = 'BillingCity';
    dualList.CompareToField__c = 'BillingState';
    dualList.Operator__c = 'ListsOverlap';
    System.assertEquals(
      false,
      dual.evaluateListVsList(dualList, accountRows, accountRows)
    );
    dualList.Operator__c = 'ListContainsAll';
    dualList.CompareToField__c = 'BillingCity';
    System.assertEquals(
      true,
      dual.evaluateListVsList(dualList, accountRows, accountRows)
    );
    dualList.Operator__c = 'ExactListMatch';
    System.assertEquals(
      true,
      dual.evaluateListVsList(dualList, accountRows, accountRows)
    );
    dualList.Operator__c = 'BadList';
    try {
      dual.evaluateListVsList(dualList, accountRows, accountRows);
      System.assert(false, 'Expected invalid dual list comparator.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_COMPARATOR', ex.reasonCode);
    }
    try {
      dual.toStringList(accountRows, null, 'primary', 'TreatMissingAsBlank');
      System.assert(false, 'Expected missing list field exception.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
    try {
      dual.toStringList(
        accountRows,
        'Missing__c',
        'primary',
        'TreatMissingAsBlank'
      );
      System.assert(false, 'Expected invalid list field exception.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }

    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applyScalarComparator(
        'NotEquals',
        'a',
        'b'
      )
    );
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applyScalarComparator(
        'Contains',
        'abc',
        'b'
      )
    );
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applyScalarComparator(
        'DoesNotContain',
        'abc',
        'z'
      )
    );
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applyScalarComparator(
        'GreaterThanOrEqual',
        2,
        2
      )
    );
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applyScalarComparator(
        'LessThanOrEqual',
        Datetime.now(),
        Datetime.now().addSeconds(1)
      )
    );
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.applyScalarComparator(
        'LessThan',
        Date.today(),
        Date.today().addDays(1)
      )
    );
    try {
      RecordHealthCheckComparatorEngine.applyScalarComparator('Nope', 'a', 'b');
      System.assert(false, 'Expected invalid scalar comparator.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_COMPARATOR', ex.reasonCode);
    }
    try {
      RecordHealthCheckComparatorEngine.applyScalarComparator(
        'GreaterThan',
        'a',
        'b'
      );
      System.assert(false, 'Expected incompatible scalar comparator.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INCOMPATIBLE_COMPARISON_TYPES', ex.reasonCode);
    }

    System.assertEquals(
      false,
      dual.frequencyMapsEqual(
        dual.toFrequencyMap(new List<String>{ 'a' }),
        dual.toFrequencyMap(new List<String>{ 'a', 'a' })
      )
    );
    try {
      RecordHealthCheckComparatorEngine.valuesEqual(
        Date.today(),
        String.valueOf(Date.today())
      );
      System.assert(false, 'Expected Date coercion incompatibility.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assert(
        ex.reasonCode == 'INCOMPATIBLE_COMPARISON_TYPES',
        'Expected a typed comparison error.'
      );
    }
    System.assertEquals(
      true,
      RecordHealthCheckValueResolver.isNumericObject(Decimal.valueOf('1'))
    );
    System.assertEquals(
      false,
      RecordHealthCheckValueResolver.isNumericObject('1')
    );
    try {
      dual.runQuery('SELECT Id FROM Account', 0);
      System.assert(false, 'Expected dual row cap exception.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('GOVERNOR_LIMIT_RISK', ex.reasonCode);
    }
    try {
      dual.runQuery('SELECT Missing__c FROM Account', 1);
      System.assert(false, 'Expected dual invalid query exception.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
    System.assertEquals(
      false,
      RecordHealthCheckComparatorEngine.resolveEmptyBehavior('Fail')
    );
    System.assertEquals(
      null,
      RecordHealthCheckComparatorEngine.resolveEmptyBehavior('Skip')
    );
    System.assertEquals(
      'FAIL',
      dual.buildEmptyOrNullResult(dualRule, new RecordHealthCheckResult())
        .status
    );
    dualRule.WhenZeroRows__c = 'UnableToEvaluate';
    assertReason(
      dual.buildEmptyOrNullResult(dualRule, new RecordHealthCheckResult()),
      'NO_ROWS_RETURNED'
    );

    RecordHealthCheckFormulaEvaluator formula = new RecordHealthCheckFormulaEvaluator();
    Record_Health_Check_Rule__mdt formulaMessageRule = baseRule(
      'Formula_Message',
      'Formula'
    );
    formulaMessageRule.MessageWhenCannotRun__c = null;
    System.assertEquals(
      'This check could not be evaluated. Contact your administrator.',
      formula.safeCannotEvaluateMessage(formulaMessageRule)
    );
    System.assertEquals(
      accountRecord.BillingCity,
      formula.resolveFieldPath(accountRecord, 'BillingCity')
    );
    System.assertEquals(
      'INVALID_FORMULA',
      formula.classifyFormulaException(
        new RecordHealthCheckFormulaEvaluator.FormulaEvaluationException(
          'X',
          'ordinary parse problem'
        )
      )
    );
    System.assertEquals(
      'FIELD_NOT_ACCESSIBLE',
      formula.classifyFormulaException(
        new RecordHealthCheckFormulaEvaluator.FormulaEvaluationException(
          'X',
          'access denied'
        )
      )
    );
  }

  @IsTest
  static void isolatedResultAndRoutingHelpersCoverDefensiveBranches() {
    Account accountRecord = [
      SELECT Id, Name, BillingCity, BillingState, Description, AnnualRevenue
      FROM Account
      WHERE Id = :RecordHealthCheckTestDataFactory.getHealthyAccount().Id
    ];

    RecordHealthCheckConfigService configService = new RecordHealthCheckConfigService();
    Record_Health_Check_Set__mdt validSet = new Record_Health_Check_Set__mdt(
      DeveloperName = 'Isolated_Set',
      MasterLabel = 'Isolated Set',
      IsActive__c = true,
      ObjectApiName__c = 'Account',
      PassedChecksDisplay__c = 'Show',
      SkippedChecksDisplay__c = 'Hide',
      RunChecksWhen__c = 'Manual',
      RowAppearance__c = 'AllAtOnce'
    );
    configService.validateCheckSetForDefinition(
      validSet,
      'Isolated_Set',
      accountRecord.Id
    );

    List<Record_Health_Check_Set__mdt> invalidSets = new List<Record_Health_Check_Set__mdt>();
    List<String> invalidReasons = new List<String>();
    Record_Health_Check_Set__mdt inactiveSet = validSet.clone();
    inactiveSet.IsActive__c = false;
    invalidSets.add(inactiveSet);
    invalidReasons.add(RecordHealthCheckConfigService.RC_CONFIG_INACTIVE);
    Record_Health_Check_Set__mdt blankObjectSet = validSet.clone();
    blankObjectSet.ObjectApiName__c = null;
    invalidSets.add(blankObjectSet);
    // L-RC-01: a blank Base Object is now INVALID_CONFIG, not CONFIG_NOT_FOUND.
    invalidReasons.add(RecordHealthCheckConfigService.RC_INVALID_CONFIG);
    Record_Health_Check_Set__mdt mismatchSet = validSet.clone();
    mismatchSet.ObjectApiName__c = 'Contact';
    invalidSets.add(mismatchSet);
    invalidReasons.add(RecordHealthCheckConfigService.RC_OBJECT_MISMATCH);
    Record_Health_Check_Set__mdt successSet = validSet.clone();
    successSet.PassedChecksDisplay__c = 'Maybe';
    invalidSets.add(successSet);
    invalidReasons.add(RecordHealthCheckConfigService.RC_INVALID_CONFIG);
    Record_Health_Check_Set__mdt skippedSet = validSet.clone();
    skippedSet.SkippedChecksDisplay__c = 'Maybe';
    invalidSets.add(skippedSet);
    invalidReasons.add(RecordHealthCheckConfigService.RC_INVALID_CONFIG);
    Record_Health_Check_Set__mdt triggerSet = validSet.clone();
    triggerSet.RunChecksWhen__c = 'Sometimes';
    invalidSets.add(triggerSet);
    invalidReasons.add(RecordHealthCheckConfigService.RC_INVALID_CONFIG);
    Record_Health_Check_Set__mdt revealSet = validSet.clone();
    revealSet.RowAppearance__c = 'Eventually';
    invalidSets.add(revealSet);
    invalidReasons.add(RecordHealthCheckConfigService.RC_INVALID_CONFIG);
    for (Integer i = 0; i < invalidSets.size(); i++) {
      try {
        configService.validateCheckSetForDefinition(
          invalidSets[i],
          'Isolated_Set',
          accountRecord.Id
        );
        System.assert(false, 'Expected invalid Check Set at index ' + i);
      } catch (RecordHealthCheckConfigService.ConfigException ex) {
        System.assertEquals(invalidReasons[i], ex.reasonCode);
      }
    }
    try {
      configService.validateActiveRulesForDefinition(
        new List<Record_Health_Check_Rule__mdt>(),
        'Isolated_Set'
      );
      System.assert(false, 'Expected no-active-checks error.');
    } catch (RecordHealthCheckConfigService.ConfigException ex) {
      System.assertEquals(
        RecordHealthCheckConfigService.RC_NO_ACTIVE_CHECKS,
        ex.reasonCode
      );
    }
    List<Record_Health_Check_Rule__mdt> thirtyRules = new List<Record_Health_Check_Rule__mdt>();
    for (Integer i = 0; i < 30; i++) {
      thirtyRules.add(baseRule('Rule_' + i, 'Formula'));
    }
    System.assertEquals(
      25,
      configService.selectRulesForRun(thirtyRules).size()
    );

    RecordHealthCheckFormulaEvaluator formula = new RecordHealthCheckFormulaEvaluator();
    Record_Health_Check_Rule__mdt formulaRule = baseRule(
      'Isolated_Formula',
      'Formula'
    );
    assertReason(
      formula.applyEvaluationResult(
        formulaRule,
        accountRecord,
        new RecordHealthCheckResult(),
        null
      ),
      'INVALID_FORMULA'
    );
    assertReason(
      formula.applyEvaluationException(
        formulaRule,
        new RecordHealthCheckResult(),
        new IllegalArgumentException('isolated formula error')
      ),
      'INVALID_FORMULA'
    );
    assertStatus(
      formula.applyEvaluationResult(
        formulaRule,
        accountRecord,
        new RecordHealthCheckResult(),
        true
      ),
      'PASS'
    );
    RecordHealthCheckResult formulaFail = formula.applyEvaluationResult(
      formulaRule,
      accountRecord,
      new RecordHealthCheckResult(),
      false
    );
    assertStatus(formulaFail, 'FAIL');
    System.assert(formulaFail.message.contains(accountRecord.Name));
    assertReason(
      formula.applyEvaluationResult(
        formulaRule,
        accountRecord,
        new RecordHealthCheckResult(),
        'not boolean'
      ),
      'INVALID_FORMULA'
    );
    System.assertEquals(
      null,
      formula.resolveFieldPath(
        new Account(Name = 'No Parent'),
        'Parent.BillingCity'
      )
    );

    RecordHealthCheckApexEvaluatorDispatcher dispatcher = new RecordHealthCheckApexEvaluatorDispatcher();
    Record_Health_Check_Rule__mdt apex = apexRule(
      'Isolated_Apex',
      'TestOnlyRule',
      null
    );
    RecordHealthCheckContext context = new RecordHealthCheckContext();
    context.recordId = accountRecord.Id;
    context.record = accountRecord;
    assertReason(
      dispatcher.invokeAndFinalize(
        new ThrowingRule(),
        context,
        apex,
        accountRecord,
        new RecordHealthCheckResult()
      ),
      'APEX_EVALUATOR_ERROR'
    );
    assertReason(
      dispatcher.invokeAndFinalize(
        new NullRule(),
        context,
        apex,
        accountRecord,
        new RecordHealthCheckResult()
      ),
      'APEX_EVALUATOR_ERROR'
    );
    RecordHealthCheckResult blankFailure = new RecordHealthCheckResult();
    blankFailure.status = 'FAIL';
    apex.MessageWhenFailed__c = null;
    System.assertEquals(
      'Check failed.',
      dispatcher.finalizeApexResult(
          apex,
          accountRecord,
          new RecordHealthCheckResult(),
          blankFailure
        )
        .message
    );
    apex.MessageWhenCannotRun__c = null;
    assertReason(
      dispatcher.evaluate(apex, accountRecord.Id, accountRecord),
      'APEX_CLASS_NOT_FOUND'
    );
    assertReason(
      dispatcher.evaluate(
        apexRule('A_Interface', 'RecordHealthCheckRule', null),
        accountRecord.Id,
        accountRecord
      ),
      'APEX_CLASS_NOT_FOUND'
    );

    RecordHealthCheckEngine engine = new RecordHealthCheckEngine();
    System.assertEquals(
      false,
      engine
        .validateCheckSetContext(
          null,
          'Isolated_Set',
          'Isolated_Check',
          accountRecord.Id
        )
        .debugMode
    );
    Record_Health_Check_Set__mdt activeContextSet = new Record_Health_Check_Set__mdt(
      DeveloperName = 'Isolated_Context_Set',
      MasterLabel = 'Isolated Context Set',
      IsActive__c = true,
      DebugMode__c = true,
      ObjectApiName__c = 'Account'
    );
    System.assertEquals(
      true,
      engine
        .validateCheckSetContext(
          activeContextSet,
          'Isolated_Set',
          'Isolated_Check',
          accountRecord.Id
        )
        .debugMode
    );
    Record_Health_Check_Set__mdt inactiveContextSet = activeContextSet.clone();
    inactiveContextSet.IsActive__c = false;
    assertReason(
      engine
        .validateCheckSetContext(
          inactiveContextSet,
          'Isolated_Set',
          'Isolated_Check',
          accountRecord.Id
        )
        .result,
      'CONFIG_INACTIVE'
    );
    Record_Health_Check_Set__mdt mismatchContextSet = activeContextSet.clone();
    mismatchContextSet.ObjectApiName__c = 'Contact';
    assertReason(
      engine
        .validateCheckSetContext(
          mismatchContextSet,
          'Isolated_Set',
          'Isolated_Check',
          accountRecord.Id
        )
        .result,
      'OBJECT_MISMATCH'
    );
    assertStatus(
      engine.routeEvaluator(formulaRule, accountRecord.Id, accountRecord),
      'PASS'
    );
    assertStatus(
      engine.routeEvaluator(
        queryRule('Isolated_Query'),
        accountRecord.Id,
        accountRecord
      ),
      'PASS'
    );
    assertStatus(
      engine.routeEvaluator(
        validDualRule('Isolated_Dual'),
        accountRecord.Id,
        accountRecord
      ),
      'PASS'
    );
    RecordHealthCheckResult routedApex = engine.routeEvaluator(
      apexRule(
        'Isolated_Routed_Apex',
        'AccountHasRecentActivityCheck',
        '{"daysBack":90}'
      ),
      accountRecord.Id,
      accountRecord
    );
    System.assert(
      routedApex.status == 'PASS' || routedApex.status == 'FAIL',
      'Expected the Apex route to evaluate.'
    );
    assertReason(
      engine.routeEvaluator(
        baseRule('Isolated_Invalid_Type', 'Bogus'),
        accountRecord.Id,
        accountRecord
      ),
      'INVALID_CHECK_TYPE'
    );
    assertStatus(
      engine.evaluate(
        'Account_Advanced_Checks',
        'Account_Adv_ContactHasEmail',
        accountRecord.Id
      ),
      'PASS'
    );
    Account accountWithoutContacts = RecordHealthCheckTestDataFactory.createAccount(
      'No Contacts Account'
    );
    RecordHealthCheckResult dependencySkipped = engine.evaluate(
      'Account_Advanced_Checks',
      'Account_Adv_ContactHasEmail',
      accountWithoutContacts.Id
    );
    assertStatus(dependencySkipped, 'SKIPPED');
    assertReason(dependencySkipped, 'DEPENDENCY_NOT_PASSED');

    Account deletedAccount = RecordHealthCheckTestDataFactory.createDeletedAccount(
      'Deleted Coverage Account'
    );
    assertReason(
      engine.evaluate(
        'Account_Data_Quality',
        'Account_DQ_BillingCity',
        deletedAccount.Id
      ),
      'RECORD_NOT_ACCESSIBLE'
    );
    assertReason(
      engine.evaluate(
        'Account_Data_Quality',
        'Account_DQ_BillingCity',
        UserInfo.getUserId()
      ),
      'OBJECT_MISMATCH'
    );
    Account circularDependencyAccount = RecordHealthCheckTestDataFactory.createAccount(
      'Circular Dependency Account'
    );
    assertReason(
      new RecordHealthCheckEngine()
        .doEvaluate(
          'Account_Advanced_Checks',
          'Account_Adv_ContactHasEmail',
          circularDependencyAccount.Id,
          new Set<String>{ 'Account_Adv_HasContact' },
          new RecordHealthCheckLogger(
            'coverage-run',
            'Account_Advanced_Checks',
            circularDependencyAccount.Id
          )
        ),
      'CIRCULAR_DEPENDENCY'
    );

    RecordHealthCheckResult debugResult = new RecordHealthCheckResult();
    debugResult.detailMessage = 'admin detail';
    RecordHealthCheckAccess.debugPermissionOverride = true;
    System.assertEquals(
      'admin detail',
      engine.applyDebugMode(debugResult, true).adminDetailMessage
    );
    RecordHealthCheckResult noDebugResult = new RecordHealthCheckResult();
    noDebugResult.detailMessage = 'hidden detail';
    System.assertEquals(
      null,
      engine.applyDebugMode(noDebugResult, false).adminDetailMessage
    );
    RecordHealthCheckAccess.debugPermissionOverride = null;
    Set<String> blankFieldSet = new Set<String>();
    engine.addReadableField(
      blankFieldSet,
      Account.SObjectType.getDescribe().fields.getMap(),
      null
    );
    System.assertEquals(0, blankFieldSet.size());

    Record_Health_Check_Rule__mdt skippedRule = queryRule('Isolated_Skipped');
    skippedRule.RunThisCheckWhen__c = 'Unexpected';
    assertStatus(engine.buildSkippedResult(skippedRule), 'SKIPPED');
    skippedRule.MessageWhenCannotRun__c = null;
    assertReason(
      engine.buildUnableResult(
        skippedRule,
        'ISOLATED_REASON',
        'isolated detail'
      ),
      'ISOLATED_REASON'
    );

    RecordHealthCheckSoqlEvaluator soql = new RecordHealthCheckSoqlEvaluator();
    try {
      soql.bindTokens(null, accountRecord);
      System.assert(false, 'Expected blank template error.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
    System.assertEquals(
      'SELECT Id FROM Account WHERE Description = null',
      soql.bindTokens(
        'SELECT Id FROM Account WHERE Description = {!Description}',
        accountRecord
      )
    );
    Opportunity opportunityRecord = [
      SELECT Id, CloseDate, CreatedDate
      FROM Opportunity
      WHERE AccountId = :accountRecord.Id
      LIMIT 1
    ];
    System.assert(
      soql.bindTokens(
          'SELECT Id FROM Opportunity WHERE CloseDate = {!CloseDate}',
          opportunityRecord
        )
        .contains(String.valueOf(opportunityRecord.CloseDate))
    );
    System.assert(
      soql.bindTokens(
          'SELECT Id FROM Opportunity WHERE CreatedDate = {!CreatedDate}',
          opportunityRecord
        )
        .contains('T')
    );
    User currentUser = [
      SELECT Id, IsActive
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ];
    System.assert(
      soql.bindTokens(
          'SELECT Id FROM User WHERE IsActive = {!IsActive}',
          currentUser
        )
        .contains('true')
    );
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.valuesEqual(null, null)
    );
    try {
      RecordHealthCheckComparatorEngine.valuesEqual(
        Decimal.valueOf('1'),
        'not numeric'
      );
      System.assert(false, 'Expected numeric parse error.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INCOMPATIBLE_COMPARISON_TYPES', ex.reasonCode);
    }
    System.assertEquals(
      false,
      RecordHealthCheckComparatorEngine.applyListComparator(
        'ListContainsAny',
        'missing',
        new List<Object>{ 'present' },
        queryRule('Isolated_List')
      )
    );
    System.assertEquals(
      false,
      RecordHealthCheckComparatorEngine.applyListComparator(
        'ListDoesNotContainAny',
        'present',
        new List<Object>{ 'present' },
        queryRule('Isolated_List_Not')
      )
    );
    Record_Health_Check_Rule__mdt skipEmpty = queryRule('Isolated_Empty_Skip');
    skipEmpty.WhenZeroRows__c = 'Skip';
    assertStatus(
      soql.buildEmptyOrNullResult(
        skipEmpty,
        new RecordHealthCheckResult(),
        null
      ),
      'SKIPPED'
    );
    System.assertEquals(
      null,
      soql.resolveFieldPath(new Account(Name = 'No Parent'), 'Parent.Name')
    );
    System.assertEquals(
      false,
      soql.isMultiSelectPicklist(accountRecord, 'Parent.Name')
    );

    RecordHealthCheckDualSoqlEvaluator dual = new RecordHealthCheckDualSoqlEvaluator();
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.valuesEqual(null, null)
    );
    try {
      RecordHealthCheckComparatorEngine.valuesEqual(
        Decimal.valueOf('1'),
        'not numeric'
      );
      System.assert(false, 'Expected dual numeric parse error.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INCOMPATIBLE_COMPARISON_TYPES', ex.reasonCode);
    }
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.resolveEmptyBehavior('Pass')
    );
    Record_Health_Check_Rule__mdt dualSkip = validDualRule(
      'Isolated_Dual_Skip'
    );
    dualSkip.WhenZeroRows__c = 'Skip';
    assertStatus(
      dual.buildEmptyOrNullResult(dualSkip, new RecordHealthCheckResult()),
      'SKIPPED'
    );
  }

  @IsTest
  static void formulaEvaluatorCoversNullAndMergeFieldBranches() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckFormulaEvaluator evaluator = new RecordHealthCheckFormulaEvaluator();
    String[] reasonCode = new List<String>{ null };

    System.assertEquals(
      null,
      evaluator.evaluateApplicabilityFormula('NULL', accountRecord, reasonCode)
    );
    System.assertEquals('INVALID_FORMULA', reasonCode[0]);

    Account nullTextAccount = new Account(Name = 'null');
    System.assertEquals(
      'Name: ',
      evaluator.resolveMergeFields('Name: {!Name}', nullTextAccount)
    );
    Account child = (Account) JSON.deserialize(
      '{"attributes":{"type":"Account"},"Parent":{"attributes":{"type":"Account"},"Name":"Parent"}}',
      Account.class
    );
    System.assertEquals(
      'Parent',
      evaluator.resolveFieldPath(child, 'Parent.Name')
    );
    RecordHealthCheckResult result = evaluator.applyEvaluationException(
      baseRule('Formula_Limit', 'Formula'),
      new RecordHealthCheckResult(),
      new RecordHealthCheckFormulaEvaluator.FormulaEvaluationException(
        'FORMULA_EVAL_LIMIT',
        'limit'
      )
    );
    assertReason(result, 'FORMULA_EVAL_LIMIT');
  }

  @IsTest
  static void configServiceCoversRemainingValidationBranches() {
    RecordHealthCheckConfigService service = new RecordHealthCheckConfigService();
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();

    Record_Health_Check_Set__mdt invalidObject = new Record_Health_Check_Set__mdt(
      DeveloperName = 'Invalid_Object',
      IsActive__c = true,
      ObjectApiName__c = 'Missing__c'
    );
    assertConfigException(
      service,
      invalidObject,
      accountRecord.Id,
      RecordHealthCheckConfigService.RC_INVALID_CONFIG
    );

    Record_Health_Check_Rule__mdt rule = baseRule('Missing_Basics', 'Formula');
    rule.CheckName__c = null;
    assertUnable(
      service.validateRuleForEvaluation(rule),
      RecordHealthCheckConfigService.RC_INVALID_CONFIG
    );
    rule = baseRule('Missing_Failure', 'Formula');
    rule.MessageWhenFailed__c = null;
    assertUnable(
      service.validateRuleForEvaluation(rule),
      RecordHealthCheckConfigService.RC_INVALID_CONFIG
    );

    rule = baseRule('App_Formula_Missing', 'Formula');
    rule.RunThisCheckWhen__c = 'Formula';
    rule.RunWhenFormula__c = null;
    assertUnable(service.validateRuleForEvaluation(rule), 'INVALID_FORMULA');

    rule = baseRule('App_Soql_Missing', 'Formula');
    rule.RunThisCheckWhen__c = 'SOQL';
    assertUnable(
      service.validateRuleForEvaluation(rule),
      'INVALID_SOQL_TEMPLATE'
    );
    rule.RunWhenCountQuery__c = 'SELECT Id FROM Account';
    assertUnable(
      service.validateRuleForEvaluation(rule),
      'INVALID_SOQL_TEMPLATE'
    );
    rule.RunWhenCountQuery__c = 'SELECT COUNT(Id) FROM Contact';
    assertUnable(service.validateRuleForEvaluation(rule), 'INVALID_COMPARATOR');
    rule.CountOperator__c = 'Around';
    assertUnable(service.validateRuleForEvaluation(rule), 'INVALID_COMPARATOR');
    rule.CountOperator__c = 'GreaterThan';
    assertUnable(
      service.validateRuleForEvaluation(rule),
      RecordHealthCheckConfigService.RC_INVALID_CONFIG
    );

    rule = queryRule('Query_Missing_Primary_Field');
    rule.FieldToRead__c = null;
    assertUnable(
      service.validateRuleForEvaluation(rule),
      'INVALID_SOQL_TEMPLATE'
    );
    rule = queryRule('Query_Invalid_Mode');
    rule.WhenMultipleRows__c = 'Nope';
    assertUnable(
      service.validateRuleForEvaluation(rule),
      RecordHealthCheckConfigService.RC_INVALID_CONFIG
    );
    rule = queryRule('Query_Invalid_Source');
    rule.CompareAgainst__c = 'Magic';
    assertUnable(
      service.validateRuleForEvaluation(rule),
      RecordHealthCheckConfigService.RC_INVALID_CONFIG
    );
    rule = queryRule('Query_Result_Missing_Field');
    rule.CompareAgainst__c = 'AnotherQuery';
    rule.CompareToQuery__c = 'SELECT BillingCity FROM Account';
    rule.CompareToField__c = null;
    assertUnable(
      service.validateRuleForEvaluation(rule),
      'INVALID_SOQL_TEMPLATE'
    );
    rule = queryRule('Query_List_Missing_Field');
    rule.Operator__c = 'ListContainsAny';
    rule.WhenMultipleRows__c = 'CompareAsLists';
    rule.DataQuery__c = null;
    rule.ValueToTest__c = 'BillingCity';
    rule.CompareToQuery__c = 'SELECT MailingCity FROM Contact';
    rule.CompareToField__c = null;
    assertUnable(
      service.validateRuleForEvaluation(rule),
      'INVALID_SOQL_TEMPLATE'
    );

    rule = apexRule('Apex_Invalid_Class', 'String', '{}');
    assertUnable(
      service.validateRuleForEvaluation(rule),
      'APEX_CLASS_NOT_FOUND'
    );
    rule = apexRule('Apex_Invalid_Json', 'AccountHasRecentActivityCheck', '[]');
    assertUnable(
      service.validateRuleForEvaluation(rule),
      'INVALID_APEX_PARAMETERS'
    );

    rule = validDualRule('Dual_Missing_Primary_Field');
    rule.DataQuery__c = 'SELECT BillingCity FROM Account';
    rule.FieldToRead__c = null;
    assertUnable(
      service.validateRuleForEvaluation(rule),
      'INVALID_SOQL_TEMPLATE'
    );
    rule = validDualRule('Dual_Missing_Comparison_Field');
    rule.CompareToQuery__c = 'SELECT BillingCity FROM Account';
    rule.CompareToField__c = null;
    assertUnable(
      service.validateRuleForEvaluation(rule),
      'INVALID_SOQL_TEMPLATE'
    );
  }

  @IsTest
  static void metadataValidatorCoversRemainingValidationBranches() {
    RecordHealthCheckMetadataValidator validator = new RecordHealthCheckMetadataValidator();
    Id setId = [
      SELECT Id
      FROM Record_Health_Check_Set__mdt
      WHERE DeveloperName = 'Account_Data_Quality'
      LIMIT 1
    ]
    .Id;
    List<Record_Health_Check_Rule__mdt> rules = new List<Record_Health_Check_Rule__mdt>();

    for (Integer i = 0; i < 26; i++) {
      Record_Health_Check_Rule__mdt limitRule = baseRule(
        'Limit_Rule_' + i,
        'Formula'
      );
      limitRule.Record_Health_Check_Set__c = setId;
      limitRule.RunOrder__c = i;
      if (i == 0) {
        limitRule.RequiresCheck__c = 'Limit_Rule_25';
      }
      rules.add(limitRule);
    }

    Record_Health_Check_Rule__mdt rule = baseRule(
      'Metadata_App_Formula',
      'Formula'
    );
    rule.Record_Health_Check_Set__c = setId;
    rule.RunThisCheckWhen__c = 'Formula';
    rule.RunWhenFormula__c = null;
    rules.add(rule);

    for (Integer variant = 0; variant < 4; variant++) {
      rule = baseRule('Metadata_App_Soql_' + variant, 'Formula');
      rule.Record_Health_Check_Set__c = setId;
      rule.RunThisCheckWhen__c = 'SOQL';
      if (variant > 0) {
        rule.RunWhenCountQuery__c = variant == 1
          ? 'SELECT Id FROM Account'
          : 'SELECT COUNT(Id) FROM Account';
      }
      if (variant > 1) {
        rule.CountOperator__c = variant == 2 ? 'Around' : 'GreaterThan';
      }
      rules.add(rule);
    }

    rule = queryRule('Metadata_Query_Missing_Primary_Field');
    rule.Record_Health_Check_Set__c = setId;
    rule.FieldToRead__c = null;
    rules.add(rule);
    rule = queryRule('Metadata_Query_Invalid_Mode');
    rule.Record_Health_Check_Set__c = setId;
    rule.WhenMultipleRows__c = 'Nope';
    rules.add(rule);
    rule = queryRule('Metadata_Query_Invalid_Source');
    rule.Record_Health_Check_Set__c = setId;
    rule.CompareAgainst__c = 'Magic';
    rules.add(rule);
    rule = queryRule('Metadata_Query_Result_Missing_Field');
    rule.Record_Health_Check_Set__c = setId;
    rule.CompareAgainst__c = 'AnotherQuery';
    rule.CompareToQuery__c = 'SELECT BillingCity FROM Account';
    rule.CompareToField__c = null;
    rules.add(rule);
    rule = apexRule('Metadata_Apex_Invalid', 'String', '[]');
    rule.Record_Health_Check_Set__c = setId;
    rules.add(rule);
    rule = validDualRule('Metadata_Dual_Missing_Fields');
    rule.Record_Health_Check_Set__c = setId;
    rule.DataQuery__c = 'SELECT BillingCity FROM Account';
    rule.FieldToRead__c = null;
    rule.CompareToQuery__c = 'SELECT BillingCity FROM Account';
    rule.CompareToField__c = null;
    rules.add(rule);

    List<RecordHealthCheckMetadataValidator.ValidationIssue> issues = validator.validateRecordsForTest(
      new List<Record_Health_Check_Set__mdt>{
        new Record_Health_Check_Set__mdt(
          DeveloperName = String.valueOf(setId),
          ObjectApiName__c = 'Missing__c',
          PanelHeading__c = 'Invalid',
          RunChecksWhen__c = 'Manual',
          RowAppearance__c = 'AllAtOnce',
          PassedChecksDisplay__c = 'Show',
          SkippedChecksDisplay__c = 'Show'
        )
      },
      rules
    );
    Set<String> reasonCodes = new Set<String>();
    for (RecordHealthCheckMetadataValidator.ValidationIssue issue : issues) {
      reasonCodes.add(issue.reasonCode);
    }
    System.assert(reasonCodes.contains('CHECK_LIMIT_EXCEEDED'));
    System.assert(reasonCodes.contains('DEPENDENCY_NOT_IN_RUN'));
    System.assert(reasonCodes.contains('INVALID_APEX_PARAMETERS'));
  }

  @IsTest
  static void engineAndSoqlCoverRemainingDefensiveBranches() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckEngine engine = new RecordHealthCheckEngine();

    RecordHealthCheckEngine throwingEngine = new RecordHealthCheckEngine();
    throwingEngine.configService = null;
    assertReason(
      throwingEngine.evaluate(
        'Account_Data_Quality',
        'Account_DQ_BillingCity',
        accountRecord.Id
      ),
      'APEX_EVALUATOR_ERROR'
    );

    RecordHealthCheckResult invalidMetadata = new RecordHealthCheckResult();
    invalidMetadata.status = 'UNABLE_TO_EVALUATE';
    invalidMetadata.reasonCode = 'INVALID_CONFIG';
    invalidMetadata.detailMessage = 'forced invalid metadata';
    RecordHealthCheckEngine invalidMetadataEngine = new RecordHealthCheckEngine();
    invalidMetadataEngine.validationResultOverride = invalidMetadata;
    assertReason(
      invalidMetadataEngine.evaluate(
        'Account_Data_Quality',
        'Account_DQ_BillingCity',
        accountRecord.Id
      ),
      'INVALID_CONFIG'
    );

    Account dependencyAccount = RecordHealthCheckTestDataFactory.createAccount(
      'Cached Circular Dependency Account'
    );
    RecordHealthCheckResult circularPrerequisite = new RecordHealthCheckResult();
    circularPrerequisite.status = 'UNABLE_TO_EVALUATE';
    circularPrerequisite.reasonCode = 'CIRCULAR_DEPENDENCY';
    RecordHealthCheckEngine.transactionResultCache.put(
      'Account_Advanced_Checks|' +
        dependencyAccount.Id +
        '|Account_Adv_HasContact',
      circularPrerequisite
    );
    assertReason(
      new RecordHealthCheckEngine()
        .evaluate(
          'Account_Advanced_Checks',
          'Account_Adv_ContactHasEmail',
          dependencyAccount.Id
        ),
      'CIRCULAR_DEPENDENCY'
    );
    RecordHealthCheckEngine.transactionResultCache.clear();

    Record_Health_Check_Rule__mdt applicability = baseRule(
      'Engine_App_Non_Scalar',
      'Formula'
    );
    applicability.RunThisCheckWhen__c = 'SOQL';
    applicability.RunWhenCountQuery__c = 'SELECT Id FROM Account';
    assertReason(
      engine.checkSoqlApplicability(applicability, accountRecord),
      'INVALID_SOQL_TEMPLATE'
    );
    applicability.RunWhenCountQuery__c = 'SELECT COUNT(Id) FROM Contact';
    assertReason(
      engine.checkSoqlApplicability(applicability, accountRecord),
      'INVALID_CONFIG'
    );
    applicability.CountThreshold__c = 0;
    applicability.CountOperator__c = 'Nope';
    assertReason(
      engine.checkSoqlApplicability(applicability, accountRecord),
      'INVALID_COMPARATOR'
    );
    applicability.RunWhenCountQuery__c = 'SELECT COUNT(Id) FROM Missing__c';
    assertReason(
      engine.checkSoqlApplicability(applicability, accountRecord),
      'INVALID_SOQL_TEMPLATE'
    );
    applicability.RunWhenCountQuery__c = 'SELECT COUNT(Id) FROM Contact WHERE AccountId = {!Missing__c}';
    assertReason(
      engine.checkSoqlApplicability(applicability, accountRecord),
      'MISSING_BIND_VALUE'
    );

    applicability.RunThisCheckWhen__c = 'Other';
    System.assertEquals(
      'SKIPPED',
      engine.buildSkippedResult(applicability).status
    );
    applicability.MessageWhenCannotRun__c = null;
    System.assertEquals(
      'This check could not be evaluated. Contact your administrator.',
      engine.buildUnableResult(applicability, 'TEST', 'detail').message
    );

    Set<String> plannedFields = new Set<String>();
    engine.addReadableField(plannedFields, Account.SObjectType, null);
    engine.addReadableField(plannedFields, Account.SObjectType, 'Parent.Name');
    engine.addReadableField(plannedFields, Account.SObjectType, 'Bogus.Name');
    engine.addReadableField(
      plannedFields,
      Account.SObjectType.getDescribe().fields.getMap(),
      'Parent.Name'
    );
    engine.addReadableField(
      plannedFields,
      Account.SObjectType.getDescribe().fields.getMap(),
      'Name'
    );
    System.assert(plannedFields.contains('Parent.Name'));
    System.assert(plannedFields.contains('Name'));

    RecordHealthCheckTestDataFactory.createAccount('Second Query Account');
    RecordHealthCheckSoqlEvaluator soql = new RecordHealthCheckSoqlEvaluator();
    Record_Health_Check_Rule__mdt invalidListFormula = queryRule(
      'Soql_Invalid_List_Formula'
    );
    invalidListFormula.Operator__c = 'ListContainsAny';
    invalidListFormula.WhenMultipleRows__c = 'CompareAsLists';
    invalidListFormula.DataQuery__c = null;
    invalidListFormula.ValueToTest__c = 'Not A Formula(';
    invalidListFormula.CompareToQuery__c = 'SELECT MailingCity FROM Contact';
    invalidListFormula.CompareToField__c = 'MailingCity';
    assertReason(
      soql.evaluate(invalidListFormula, accountRecord.Id, accountRecord),
      'INVALID_FORMULA'
    );
    Record_Health_Check_Rule__mdt query = queryRule(
      'Soql_Multiple_Primary_Rows'
    );
    query.DataQuery__c = 'SELECT Name FROM Account';
    query.FieldToRead__c = 'Name';
    assertReason(
      soql.evaluate(query, accountRecord.Id, accountRecord),
      'MULTIPLE_ROWS_RETURNED'
    );

    query = queryRule('Soql_Invalid_Comparison_Formula');
    query.CompareAgainst__c = 'RecordFormula';
    query.RecordFormulaValue__c = 'Not A Formula(';
    assertReason(
      soql.evaluate(query, accountRecord.Id, accountRecord),
      'INVALID_FORMULA'
    );
    query = queryRule('Soql_Empty_Comparison_Query');
    query.CompareAgainst__c = 'AnotherQuery';
    query.CompareToQuery__c = 'SELECT BillingCity FROM Account WHERE Name = \'does not exist\'';
    query.CompareToField__c = 'BillingCity';
    assertStatus(soql.evaluate(query, accountRecord.Id, accountRecord), 'FAIL');

    try {
      soql.runQuery('', 1);
      System.assert(false, 'Expected a template error.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
    try {
      soql.resolveFieldList(new List<SObject>{ accountRecord }, null);
      System.assert(false, 'Expected a missing field error.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_SOQL_TEMPLATE', ex.reasonCode);
    }
    try {
      RecordHealthCheckComparatorEngine.applySingleComparator(
        'Nope',
        'a',
        'b',
        query
      );
      System.assert(false, 'Expected an invalid comparator.');
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('INVALID_COMPARATOR', ex.reasonCode);
    }
    query.WhenValueIsEmpty__c = 'TreatMissingAsBlank';
    RecordHealthCheckComparatorEngine.applyListComparator(
      'ListContainsAny',
      null,
      new List<Object>{ '' },
      query
    );
    query.WhenValueIsEmpty__c = 'SkipRecordsWithMissingValue';
    System.assertEquals(
      null,
      RecordHealthCheckComparatorEngine.applyListComparator(
        'ListContainsAny',
        null,
        new List<Object>{ 'a' },
        query
      )
    );
    System.assertEquals(
      null,
      RecordHealthCheckComparatorEngine.resolveEmptyBehavior('Skip')
    );
    System.assertEquals(
      null,
      RecordHealthCheckComparatorEngine.resolveEmptyBehavior(null)
    );
    query.WhenZeroRows__c = 'Fail';
    query.MessageWhenFailed__c = null;
    System.assertEquals(
      'No matching records found.',
      soql.buildEmptyOrNullResult(query, new RecordHealthCheckResult(), null)
        .message
    );
    System.assertEquals(
      false,
      soql.isMultiSelectPicklist(accountRecord, 'Bogus.Name')
    );
    Account child = (Account) JSON.deserialize(
      '{"attributes":{"type":"Account"},"Parent":{"attributes":{"type":"Account"},"Name":"Parent"}}',
      Account.class
    );
    System.assertEquals('Parent', soql.resolveFieldPath(child, 'Parent.Name'));
    query.MessageWhenCannotRun__c = null;
    System.assertEquals(
      'This check could not be evaluated. Contact your administrator.',
      soql.safeCannotEvaluateMessage(query)
    );
  }

  private static void assertConfigException(
    RecordHealthCheckConfigService service,
    Record_Health_Check_Set__mdt checkSet,
    Id recordId,
    String reasonCode
  ) {
    try {
      service.validateCheckSetForDefinition(
        checkSet,
        checkSet.DeveloperName,
        recordId
      );
      System.assert(false, 'Expected a config exception.');
    } catch (RecordHealthCheckConfigService.ConfigException ex) {
      System.assertEquals(reasonCode, ex.reasonCode);
    }
  }

  private static Record_Health_Check_Rule__mdt baseRule(
    String developerName,
    String checkType
  ) {
    return new Record_Health_Check_Rule__mdt(
      DeveloperName = developerName,
      MasterLabel = developerName,
      CheckName__c = developerName,
      CheckMethod__c = checkType,
      Severity__c = 'Warning',
      PassFailFormula__c = checkType == 'Formula' ? 'TRUE' : null,
      MessageWhenFailed__c = 'Apex failure for {!Name}',
      MessageWhenCannotRun__c = 'Cannot evaluate test rule.',
      RunOrder__c = 10,
      RunThisCheckWhen__c = 'Always',
      WhenZeroRows__c = 'Fail',
      WhenValueIsEmpty__c = 'SkipRecordsWithMissingValue'
    );
  }

  private static Record_Health_Check_Rule__mdt queryRule(String developerName) {
    Record_Health_Check_Rule__mdt rule = baseRule(developerName, 'Query');
    rule.DataQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}';
    rule.FieldToRead__c = 'BillingCity';
    rule.WhenMultipleRows__c = 'OneResult';
    rule.Operator__c = 'Equals';
    rule.CompareAgainst__c = 'FixedValue';
    rule.FixedValue__c = 'Chicago';
    return rule;
  }

  private static Record_Health_Check_Rule__mdt dualRule(String developerName) {
    return baseRule(developerName, 'CompareTwoQueries');
  }

  private static Record_Health_Check_Rule__mdt validDualRule(
    String developerName
  ) {
    Record_Health_Check_Rule__mdt rule = dualRule(developerName);
    rule.DataQuery__c = 'SELECT COUNT(Id) totalCount FROM Contact WHERE AccountId = {!Id}';
    rule.FieldToRead__c = 'totalCount';
    rule.CompareToQuery__c = 'SELECT COUNT(Id) totalCount FROM Contact WHERE AccountId = {!Id}';
    rule.CompareToField__c = 'totalCount';
    rule.WhenMultipleRows__c = 'OneResult';
    rule.Operator__c = 'Equals';
    return rule;
  }

  private static Record_Health_Check_Rule__mdt apexRule(
    String developerName,
    String className,
    String parameters
  ) {
    Record_Health_Check_Rule__mdt rule = baseRule(developerName, 'Apex');
    rule.ApexClass__c = className;
    rule.ApexSettingsJson__c = parameters;
    return rule;
  }

  private static void assertUnable(
    RecordHealthCheckResult result,
    String reasonCode
  ) {
    System.assertNotEquals(null, result, 'Expected an unable result.');
    System.assertEquals('UNABLE_TO_EVALUATE', result.status);
    System.assertEquals(reasonCode, result.reasonCode);
  }

  private static void assertStatus(
    RecordHealthCheckResult result,
    String status
  ) {
    System.assertNotEquals(null, result, 'Expected a result.');
    System.assertEquals(
      status,
      result.status,
      'Unexpected detail: ' + result.detailMessage
    );
  }

  @IsTest
  static void formulaFieldPlanningScansTokensAndExpandsDependencies() {
    RecordHealthCheckEngine engine = new RecordHealthCheckEngine();

    // scanFormulaFieldTokens: relationship paths captured whole, function words
    // and double-quoted literals excluded, single fields kept, de-duplicated.
    List<String> tokens = engine.scanFormulaFieldTokens(
      'AND(NOT(ISBLANK(BillingCity)), CONTAINS(Website, "example.com"), NOT(ISBLANK(Parent.BillingCity)))'
    );
    Set<String> tokenSet = new Set<String>(tokens);
    System.assert(
      tokenSet.contains('BillingCity'),
      tokens + ' should keep BillingCity'
    );
    System.assert(
      tokenSet.contains('Website'),
      tokens + ' should keep Website'
    );
    System.assert(
      tokenSet.contains('Parent.BillingCity'),
      tokens + ' should keep the relationship path whole'
    );
    System.assert(!tokenSet.contains('AND'), 'Function words must be excluded');
    System.assert(
      !tokenSet.contains('CONTAINS'),
      'Function words must be excluded'
    );
    System.assert(
      !tokenSet.contains('example'),
      'Masked string-literal contents must not be scanned as fields'
    );

    // describeFieldPath: single field, relationship path, case-insensitivity,
    // and null for a non-existent path.
    System.assertNotEquals(
      null,
      engine.describeFieldPath(Account.SObjectType, 'BillingCity')
    );
    System.assertNotEquals(
      null,
      engine.describeFieldPath(Account.SObjectType, 'Parent.Name'),
      'Relationship paths must resolve'
    );
    System.assertNotEquals(
      null,
      engine.describeFieldPath(Account.SObjectType, 'billingcity'),
      'Field lookup must be case-insensitive'
    );
    System.assertEquals(
      null,
      engine.describeFieldPath(Account.SObjectType, 'No_Such_Field__c'),
      'A missing field must resolve to null, not throw'
    );
    System.assertEquals(
      null,
      engine.describeFieldPath(Account.SObjectType, 'Bogus.Name'),
      'A missing relationship must resolve to null'
    );

    // collectRecordFields: a formula over plain + relationship operands still
    // plans every operand (regression — the recursive walk must not drop fields
    // that are not calculated), regardless of operand case.
    Record_Health_Check_Rule__mdt rule = new Record_Health_Check_Rule__mdt(
      CheckMethod__c = 'Formula',
      PassFailFormula__c = 'AND(NOT(ISBLANK(billingcity)), NOT(ISBLANK(Parent.BillingCity)))'
    );
    Set<String> planned = engine.collectRecordFields(rule, Account.SObjectType);
    System.assert(planned.contains('Id'));
    System.assert(
      planned.contains('billingcity'),
      'Case-insensitive operand must be planned: ' + planned
    );
    System.assert(
      planned.contains('Parent.BillingCity'),
      'Relationship operand must be planned: ' + planned
    );

    // Calculated-field dependency expansion: when the org exposes any formula
    // field on Account, a check that references only that field must also plan
    // the fields ITS definition depends on — otherwise FormulaEval cannot
    // regenerate it. Deterministic where such a field exists; a no-op assertion
    // otherwise so the test stays green on orgs without Account formula fields.
    Schema.DescribeFieldResult calcField = findCalculatedAccountField();
    if (calcField != null) {
      List<String> nestedTokens = engine.scanFormulaFieldTokens(
        calcField.getCalculatedFormula()
      );
      Record_Health_Check_Rule__mdt calcRule = new Record_Health_Check_Rule__mdt(
        CheckMethod__c = 'Formula',
        PassFailFormula__c = 'NOT(ISBLANK(' + calcField.getName() + '))'
      );
      Set<String> calcPlanned = engine.collectRecordFields(
        calcRule,
        Account.SObjectType
      );
      System.assert(
        calcPlanned.contains(calcField.getName()),
        'The formula field itself must be planned: ' + calcPlanned
      );
      for (String dep : nestedTokens) {
        // Only single-segment, real Account fields are expected in the SELECT;
        // relationship and literal tokens are validated by the scans above.
        if (
          !dep.contains('.') &&
          engine.describeFieldPath(Account.SObjectType, dep) != null
        ) {
          System.assert(
            calcPlanned.contains(dep),
            'Dependency ' +
              dep +
              ' of ' +
              calcField.getName() +
              ' must be planned: ' +
              calcPlanned
          );
        }
      }
    }
  }

  // Returns any calculated (formula) field on Account the running org exposes, or
  // null if there are none — used to exercise dependency expansion deterministically
  // where possible without requiring a packaged test formula field.
  private static Schema.DescribeFieldResult findCalculatedAccountField() {
    for (
      Schema.SObjectField f : Account.SObjectType.getDescribe()
        .fields.getMap()
        .values()
    ) {
      Schema.DescribeFieldResult d = f.getDescribe();
      if (d.isCalculated() && String.isNotBlank(d.getCalculatedFormula())) {
        return d;
      }
    }
    return null;
  }

  @IsTest
  static void formulaCheckPopulatesFoundAndExpectedFromScalarFormulas() {
    Account a = new Account(Name = 'Balance Co', NumberOfEmployees = 100);
    insert a;
    Account record = [
      SELECT Id, NumberOfEmployees, AnnualRevenue
      FROM Account
      WHERE Id = :a.Id
    ];
    RecordHealthCheckFormulaEvaluator evaluator = new RecordHealthCheckFormulaEvaluator();

    // Found + Expected resolve from explicit scalar formulas, formatted like
    // Query checks.
    Record_Health_Check_Rule__mdt rule = new Record_Health_Check_Rule__mdt(
      CheckMethod__c = 'Formula',
      PassFailFormula__c = 'NumberOfEmployees > 0',
      FoundValueFormula__c = 'BLANKVALUE(NumberOfEmployees, 0)',
      ExpectedValueFormula__c = 'BLANKVALUE(NumberOfEmployees, 0) + 5',
      ScalarFormulaReturnType__c = 'Number'
    );
    RecordHealthCheckResult result = new RecordHealthCheckResult();
    evaluator.applyFoundExpectedValues(rule, record, result);
    System.assert(
      result.actualValue != null && result.actualValue.contains('100'),
      'Found should be the resolved left-side scalar: ' + result.actualValue
    );
    System.assert(
      result.expectedValue != null && result.expectedValue.contains('105'),
      'Expected should be the resolved right-side scalar: ' +
      result.expectedValue
    );

    // Blank Found/Expected → original behavior: no Found, Expected echoes the
    // boolean formula text.
    Record_Health_Check_Rule__mdt plain = new Record_Health_Check_Rule__mdt(
      CheckMethod__c = 'Formula',
      PassFailFormula__c = 'NumberOfEmployees > 0'
    );
    RecordHealthCheckResult plainResult = new RecordHealthCheckResult();
    evaluator.applyFoundExpectedValues(plain, record, plainResult);
    System.assertEquals(
      null,
      plainResult.actualValue,
      'No Found formula → no Found value'
    );
    System.assertEquals(
      '"NumberOfEmployees > 0"',
      plainResult.expectedValue,
      'Expected echoes the quoted Pass/Fail formula when no Expected formula'
    );

    // An unresolvable Found/Expected formula degrades to the default — it must
    // never throw or change pass/fail.
    Record_Health_Check_Rule__mdt bad = new Record_Health_Check_Rule__mdt(
      CheckMethod__c = 'Formula',
      PassFailFormula__c = 'NumberOfEmployees > 0',
      FoundValueFormula__c = 'No_Such_Field__c + 1'
    );
    RecordHealthCheckResult badResult = new RecordHealthCheckResult();
    evaluator.applyFoundExpectedValues(bad, record, badResult);
    System.assertEquals(
      null,
      badResult.actualValue,
      'Unresolvable Found formula leaves Found empty'
    );
    System.assertEquals(
      '"NumberOfEmployees > 0"',
      badResult.expectedValue,
      'Falls back to the formula echo when Expected is blank'
    );

    // End-to-end: evaluate() wires Found/Expected onto a real PASS result.
    RecordHealthCheckResult full = evaluator.evaluate(rule, record.Id, record);
    System.assertEquals('PASS', full.status);
    System.assert(
      full.actualValue != null && full.actualValue.contains('100'),
      'evaluate() should surface Found: ' + full.actualValue
    );

    // collectRecordFields plans the operands of BOTH new formulas (so Task 2's
    // dependency expansion applies to them too).
    Record_Health_Check_Rule__mdt planRule = new Record_Health_Check_Rule__mdt(
      CheckMethod__c = 'Formula',
      PassFailFormula__c = 'NumberOfEmployees > 0',
      FoundValueFormula__c = 'BLANKVALUE(NumberOfEmployees, 0)',
      ExpectedValueFormula__c = 'BLANKVALUE(AnnualRevenue, 0)'
    );
    Set<String> planned = new RecordHealthCheckEngine()
      .collectRecordFields(planRule, Account.SObjectType);
    System.assert(
      planned.contains('NumberOfEmployees'),
      'Found-formula operand must be planned: ' + planned
    );
    System.assert(
      planned.contains('AnnualRevenue'),
      'Expected-formula operand must be planned: ' + planned
    );
  }

  private static void assertReason(
    RecordHealthCheckResult result,
    String reasonCode
  ) {
    System.assertNotEquals(null, result, 'Expected a result.');
    System.assertEquals(
      reasonCode,
      result.reasonCode,
      'Unexpected status/detail: ' + result.status + ' ' + result.detailMessage
    );
  }
}
