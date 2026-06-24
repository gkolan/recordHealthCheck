/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

@isTest
private class RecordHealthCheckFacadeTest {
  @testSetup
  static void setup() {
    RecordHealthCheckTestDataFactory.createTestRecords();
  }

  @isTest
  static void runOneLinerReturnsAResult() {
    Account acct = RecordHealthCheckTestDataFactory.getHealthyAccount();

    Test.startTest();
    RecordHealthCheckResult result = RecordHealthCheck.run(
      'Account_Data_Quality',
      'Account_DQ_BillingCity',
      acct.Id
    );
    Test.stopTest();

    System.assertNotEquals(
      null,
      result,
      'Facade should always return a result.'
    );
    System.assertEquals(
      'Account_DQ_BillingCity',
      result.checkDeveloperName,
      'Result should be for the requested check.'
    );
    System.assertNotEquals(
      null,
      result.status,
      'Result should carry a status.'
    );
  }

  @isTest
  static void runWithExplicitRunIdIsAccepted() {
    Account acct = RecordHealthCheckTestDataFactory.getHealthyAccount();

    Test.startTest();
    RecordHealthCheckResult correlated = RecordHealthCheck.run(
      'Account_Data_Quality',
      'Account_DQ_BillingCity',
      acct.Id,
      'ticket-12345'
    );
    Test.stopTest();

    System.assertEquals(
      'Account_DQ_BillingCity',
      correlated.checkDeveloperName
    );
  }

  @isTest
  static void runSurfacesUnknownConfigAsReason() {
    Account acct = RecordHealthCheckTestDataFactory.getHealthyAccount();

    Test.startTest();
    RecordHealthCheckResult result = RecordHealthCheck.run(
      'No_Such_Config',
      'No_Such_Check',
      acct.Id
    );
    Test.stopTest();

    System.assertEquals(
      'UNABLE_TO_EVALUATE',
      result.status,
      'Unknown config should be a clean UNABLE_TO_EVALUATE, not an exception.'
    );
    System.assertEquals('CONFIG_NOT_FOUND', result.reasonCode);
  }
}
