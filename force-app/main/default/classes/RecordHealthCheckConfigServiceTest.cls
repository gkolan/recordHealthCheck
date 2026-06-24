/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

@isTest
private class RecordHealthCheckConfigServiceTest {
  @testSetup
  static void setup() {
    RecordHealthCheckTestDataFactory.createTestRecords();
  }

  @isTest
  static void getDefinitionResponseLoadsSettingsAndAppliesCheckLimit() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();
    RecordHealthCheckConfigService service = new RecordHealthCheckConfigService();

    Test.startTest();
    RecordHealthCheckDefinitionResponse response = service.getDefinitionResponse(
      'Account_Data_Quality',
      accountRecord.Id
    );
    Test.stopTest();

    System.assertEquals('Account Data Quality', response.displayTitle);
    System.assertEquals('Automatic', response.triggerMode);
    System.assertNotEquals(null, response.checks);
    System.assert(response.checks.size() > 0, 'Expected at least one check.');
    System.assert(
      response.checks.size() <= 25,
      'Definitions must respect the framework check cap.'
    );
    System.assertEquals(
      response.totalAvailableCheckCount > response.checks.size(),
      response.checksOmittedByLimit
    );
  }

  @isTest
  static void getDefinitionResponseRejectsObjectMismatch() {
    RecordHealthCheckConfigService service = new RecordHealthCheckConfigService();

    try {
      service.getDefinitionResponse(
        'Account_Data_Quality',
        UserInfo.getUserId()
      );
      System.assert(false, 'Expected an object mismatch exception.');
    } catch (RecordHealthCheckConfigService.ConfigException ex) {
      System.assertEquals(
        RecordHealthCheckConfigService.RC_OBJECT_MISMATCH,
        ex.reasonCode
      );
    }
  }

  @isTest
  static void getDefinitionResponseRejectsMissingRecordContext() {
    RecordHealthCheckConfigService service = new RecordHealthCheckConfigService();

    try {
      service.getDefinitionResponse('Account_Data_Quality', null);
      System.assert(false, 'Expected a missing record context exception.');
    } catch (RecordHealthCheckConfigService.ConfigException ex) {
      System.assertEquals(
        RecordHealthCheckConfigService.RC_NO_RECORD_CONTEXT,
        ex.reasonCode
      );
    }
  }

  @isTest
  static void validateRuleForEvaluationReturnsUnableForInvalidQueryRule() {
    Record_Health_Check_Rule__mdt rule = new Record_Health_Check_Rule__mdt(
      DeveloperName = 'Invalid_Query_Test',
      MasterLabel = 'Invalid Query Test',
      CheckName__c = 'Invalid Query Test',
      CheckMethod__c = 'Query',
      Severity__c = 'Warning',
      Operator__c = 'Equals',
      WhenMultipleRows__c = 'OneResult',
      CompareAgainst__c = 'FixedValue',
      FixedValue__c = 'Hot',
      MessageWhenFailed__c = 'Invalid query failed.',
      RunOrder__c = 10
    );

    RecordHealthCheckResult result = new RecordHealthCheckConfigService()
      .validateRuleForEvaluation(rule);

    System.assertEquals('UNABLE_TO_EVALUATE', result.status);
    System.assertEquals('INVALID_SOQL_TEMPLATE', result.reasonCode);
    System.assertEquals('Invalid_Query_Test', result.checkDeveloperName);
  }
}
