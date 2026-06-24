/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

@isTest
private class RecordHealthCheckEngineTest {
  @testSetup
  static void setup() {
    RecordHealthCheckTestDataFactory.createTestRecords();
  }

  @isTest
  static void evaluateReturnsUnableWhenRuleIsMissing() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();

    Test.startTest();
    RecordHealthCheckResult result = new RecordHealthCheckEngine()
      .evaluate('Account_Data_Quality', 'Does_Not_Exist', accountRecord.Id);
    Test.stopTest();

    System.assertEquals('UNABLE_TO_EVALUATE', result.status);
    System.assertEquals('CONFIG_NOT_FOUND', result.reasonCode);
    System.assertEquals('Does_Not_Exist', result.checkDeveloperName);
    System.assertNotEquals(null, result.durationMs);
  }

  @isTest
  static void evaluateRunsQueryCheckAgainstSharedAccountData() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();

    Test.startTest();
    RecordHealthCheckResult result = new RecordHealthCheckEngine()
      .evaluate(
        'Account_Query_Coverage',
        'Account_QC_IsNotBlank',
        accountRecord.Id
      );
    Test.stopTest();

    System.assertEquals('PASS', result.status);
    System.assertEquals('Account_QC_IsNotBlank', result.checkDeveloperName);
    System.assertEquals('Query', result.evaluatorType);
  }

  @isTest
  static void queryEvaluatorComparesRelatedSumToFormulaResult() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckTestDataFactory.createOpportunity(
      accountRecord.Id,
      'Record Health Sum Test',
      accountRecord.AnnualRevenue * 0.1
    );

    Record_Health_Check_Rule__mdt rule = new Record_Health_Check_Rule__mdt(
      DeveloperName = 'Test_Related_Sum_Matches_Formula',
      MasterLabel = 'Test Related Sum Matches Formula',
      CheckName__c = 'Related Sum Matches Formula',
      CheckMethod__c = 'Query',
      Severity__c = 'Warning',
      DataQuery__c = 'SELECT SUM(Amount) totalAmount FROM Opportunity WHERE AccountId = {!Id}',
      FieldToRead__c = 'totalAmount',
      WhenMultipleRows__c = 'OneResult',
      Operator__c = 'Equals',
      CompareAgainst__c = 'RecordFormula',
      RecordFormulaValue__c = 'AnnualRevenue * 0.1',
      WhenZeroRows__c = 'Fail',
      WhenValueIsEmpty__c = 'MissingMeansNoMatch',
      MessageWhenFailed__c = 'Related opportunity amount does not match expected revenue.',
      RunOrder__c = 10
    );

    Test.startTest();
    RecordHealthCheckResult result = new RecordHealthCheckSoqlEvaluator()
      .evaluate(rule, accountRecord.Id, accountRecord);
    Test.stopTest();

    System.assertEquals(
      'PASS',
      result.status,
      'Unexpected result detail: ' + result.detailMessage
    );
    System.assertEquals('Query', result.evaluatorType);
  }

  @isTest
  static void queryEvaluatorSkipsNullRowsForAllRecordsMatch() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckTestDataFactory.createEmailCoverageContacts(
      accountRecord.Id
    );

    Record_Health_Check_Rule__mdt rule = new Record_Health_Check_Rule__mdt(
      DeveloperName = 'Test_All_Contacts_With_Email',
      MasterLabel = 'Test All Contacts With Email',
      CheckName__c = 'All Contacts With Email',
      CheckMethod__c = 'Query',
      Severity__c = 'Warning',
      DataQuery__c = 'SELECT Email FROM Contact WHERE AccountId = {!Id}',
      FieldToRead__c = 'Email',
      WhenMultipleRows__c = 'AllRowsPass',
      Operator__c = 'IsNotBlank',
      WhenZeroRows__c = 'Fail',
      WhenValueIsEmpty__c = 'SkipRecordsWithMissingValue',
      MessageWhenFailed__c = 'A contact is missing email.',
      RunOrder__c = 11
    );

    Test.startTest();
    RecordHealthCheckResult result = new RecordHealthCheckSoqlEvaluator()
      .evaluate(rule, accountRecord.Id, accountRecord);
    Test.stopTest();

    System.assertEquals(
      'PASS',
      result.status,
      'Null rows should be skipped; detail: ' + result.detailMessage
    );
  }

  @isTest
  static void dualQueryExactListMatchHonorsDuplicateCounts() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckTestDataFactory.createMatchingCityContacts(
      accountRecord.Id,
      accountRecord.BillingCity
    );

    Record_Health_Check_Rule__mdt rule = new Record_Health_Check_Rule__mdt(
      DeveloperName = 'Test_Exact_List_Duplicates',
      MasterLabel = 'Test Exact List Duplicates',
      CheckName__c = 'Exact List Duplicates',
      CheckMethod__c = 'CompareTwoQueries',
      Severity__c = 'Warning',
      DataQuery__c = 'SELECT MailingCity FROM Contact WHERE AccountId = {!Id}',
      FieldToRead__c = 'MailingCity',
      CompareToQuery__c = 'SELECT BillingCity FROM Account WHERE Id = {!Id}',
      CompareToField__c = 'BillingCity',
      WhenMultipleRows__c = 'CompareAsLists',
      Operator__c = 'ExactListMatch',
      WhenZeroRows__c = 'Fail',
      WhenValueIsEmpty__c = 'MissingMeansNoMatch',
      MessageWhenFailed__c = 'Contact city list does not exactly match.',
      RunOrder__c = 12
    );

    Test.startTest();
    RecordHealthCheckResult result = new RecordHealthCheckDualSoqlEvaluator()
      .evaluate(rule, accountRecord.Id, accountRecord);
    Test.stopTest();

    System.assertEquals(
      'FAIL',
      result.status,
      'Duplicate city rows must not collapse into a single set value.'
    );
  }

  @isTest
  static void dualQueryOrderedComparisonSupportsDateTimeValues() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();

    Record_Health_Check_Rule__mdt rule = new Record_Health_Check_Rule__mdt(
      DeveloperName = 'Test_DateTime_Order',
      MasterLabel = 'Test DateTime Order',
      CheckName__c = 'DateTime Order',
      CheckMethod__c = 'CompareTwoQueries',
      Severity__c = 'Warning',
      DataQuery__c = 'SELECT CreatedDate FROM Account WHERE Id = {!Id}',
      FieldToRead__c = 'CreatedDate',
      CompareToQuery__c = 'SELECT LastModifiedDate FROM Account WHERE Id = {!Id}',
      CompareToField__c = 'LastModifiedDate',
      WhenMultipleRows__c = 'OneResult',
      Operator__c = 'LessThanOrEqual',
      WhenZeroRows__c = 'Fail',
      WhenValueIsEmpty__c = 'MissingMeansNoMatch',
      MessageWhenFailed__c = 'CreatedDate should not be after LastModifiedDate.',
      RunOrder__c = 13
    );

    Test.startTest();
    RecordHealthCheckResult result = new RecordHealthCheckDualSoqlEvaluator()
      .evaluate(rule, accountRecord.Id, accountRecord);
    Test.stopTest();

    System.assertEquals(
      'PASS',
      result.status,
      'DateTime comparison should use temporal ordering; detail: ' +
      result.detailMessage
    );
  }

  @isTest
  static void apexRuleUsesDefaultsForMissingAndOutOfRangeParameters() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckTestDataFactory.createCompletedTask(accountRecord.Id);
    AccountHasRecentActivityCheck rule = new AccountHasRecentActivityCheck();
    RecordHealthCheckContext context = new RecordHealthCheckContext();
    context.recordId = accountRecord.Id;

    context.parameters = null;
    System.assertEquals('PASS', rule.evaluate(context).status);
    context.parameters = new Map<String, Object>();
    System.assertEquals('PASS', rule.evaluate(context).status);
    context.parameters = new Map<String, Object>{ 'daysBack' => 0 };
    System.assertEquals('PASS', rule.evaluate(context).status);
    context.parameters = new Map<String, Object>{ 'daysBack' => 'bad' };
    System.assertEquals('PASS', rule.evaluate(context).status);
  }

  @isTest
  static void evaluateRejectsRuleFromDifferentCheckSet() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();

    RecordHealthCheckResult result = new RecordHealthCheckEngine()
      .evaluate(
        'Account_Data_Quality',
        'Account_QC_IsNotBlank',
        accountRecord.Id
      );

    System.assertEquals('UNABLE_TO_EVALUATE', result.status);
    System.assertEquals('CONFIG_NOT_FOUND', result.reasonCode);
  }

  /**
   * T-03: second top-level evaluate() in the same transaction must not return
   * a memoized result from the first call (P1-01 cache clear).
   */
  @isTest
  static void secondTopLevelEvaluateReEvaluatesAfterRecordChange() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckEngine engine = new RecordHealthCheckEngine();

    RecordHealthCheckResult first = engine.evaluate(
      'Account_Data_Quality',
      'Account_DQ_BillingCity',
      accountRecord.Id
    );
    System.assertEquals('PASS', first.status);

    accountRecord.BillingCity = null;
    update accountRecord;

    RecordHealthCheckResult second = engine.evaluate(
      'Account_Data_Quality',
      'Account_DQ_BillingCity',
      accountRecord.Id
    );
    System.assertEquals(
      'FAIL',
      second.status,
      'Cache must clear between top-level evaluate() calls.'
    );
  }

  @isTest
  static void bindTokensMixedQuotedAndUnquotedSubstitutesBoth() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckSoqlEvaluator evaluator = new RecordHealthCheckSoqlEvaluator();
    String template = 'SELECT Id FROM Account WHERE Name = \'{!Name}\' OR Name = {!Name}';
    String bound = evaluator.bindTokens(template, accountRecord);
    String escaped = String.escapeSingleQuotes(accountRecord.Name);
    System.assert(
      bound.contains('\'' + escaped + '\''),
      'Quoted token should remain a quoted literal.'
    );
    System.assert(
      !bound.contains('{!Name}'),
      'Both quoted and unquoted token forms must be consumed.'
    );
  }

  @isTest
  static void bindTokensRejectsSemicolonOnlyMultiSelectSegments() {
    RecordHealthCheckSoqlEvaluator evaluator = new RecordHealthCheckSoqlEvaluator();
    try {
      evaluator.buildMultiSelectIncludesClause(';');
      System.assert(
        false,
        'Expected MISSING_BIND_VALUE for semicolon-only value.'
      );
    } catch (RecordHealthCheckEvaluatorException ex) {
      System.assertEquals('MISSING_BIND_VALUE', ex.reasonCode);
    }
    System.assertEquals(
      '(\'North\', \'South\')',
      evaluator.buildMultiSelectIncludesClause('North;South')
    );
  }

  @isTest
  static void valuesEqualNormalizesDateAndDatetime() {
    Date d = Date.newInstance(2024, 6, 15);
    Datetime dt = Datetime.newInstance(2024, 6, 15, 0, 0, 0);
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.valuesEqual(d, dt)
    );
  }

  @isTest
  static void valuesEqualNormalizesIdAndString() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    System.assertEquals(
      true,
      RecordHealthCheckComparatorEngine.valuesEqual(
        accountRecord.Id,
        String.valueOf(accountRecord.Id)
      )
    );
  }
}
