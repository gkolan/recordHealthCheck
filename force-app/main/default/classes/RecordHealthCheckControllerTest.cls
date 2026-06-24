/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

@isTest
private class RecordHealthCheckControllerTest {
  @testSetup
  static void setup() {
    RecordHealthCheckTestDataFactory.createTestRecords();
  }

  @isTest
  static void getCheckDefinitionsReturnsDefinitionResponse() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();

    Test.startTest();
    RecordHealthCheckDefinitionResponse response = RecordHealthCheckController.getCheckDefinitions(
      'Account_Data_Quality',
      accountRecord.Id,
      'test-run-1'
    );
    Test.stopTest();

    System.assertEquals('Account Data Quality', response.displayTitle);
    System.assert(
      response.checks.size() > 0,
      'Expected visible check definitions.'
    );
  }

  @isTest
  static void getCheckDefinitionsWrapsConfigErrorsForAura() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();

    try {
      RecordHealthCheckController.getCheckDefinitions(
        'Missing_Config',
        accountRecord.Id,
        'test-run-2'
      );
      System.assert(false, 'Expected AuraHandledException.');
    } catch (AuraHandledException ex) {
      System.assert(
        ex.getMessage().contains('CONFIG_NOT_FOUND'),
        'Expected serialized reason code in the Aura error message.'
      );
    }
  }

  @isTest
  static void evaluateCheckDoesNotThrowForMissingRule() {
    Account accountRecord = RecordHealthCheckTestDataFactory.getHealthyAccount();

    RecordHealthCheckResult result = RecordHealthCheckController.evaluateCheck(
      'Account_Data_Quality',
      'Missing_Rule',
      accountRecord.Id,
      'test-run-3'
    );

    System.assertEquals('UNABLE_TO_EVALUATE', result.status);
    System.assertEquals('CONFIG_NOT_FOUND', result.reasonCode);
  }
}
