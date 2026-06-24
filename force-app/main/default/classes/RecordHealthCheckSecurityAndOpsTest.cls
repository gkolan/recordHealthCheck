/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

@isTest
private class RecordHealthCheckSecurityAndOpsTest {
  @isTest
  static void debugDetailRequiresCustomPermission() {
    RecordHealthCheckResult result = new RecordHealthCheckResult();
    result.detailMessage = 'sensitive query detail';
    RecordHealthCheckEngine engine = new RecordHealthCheckEngine();

    RecordHealthCheckAccess.debugPermissionOverride = false;
    System.assertEquals(false, RecordHealthCheckAccess.canViewDebugDetails());
    System.assertEquals(
      null,
      engine.applyDebugMode(result, true).adminDetailMessage
    );

    RecordHealthCheckAccess.debugPermissionOverride = true;
    System.assertEquals(true, RecordHealthCheckAccess.canViewDebugDetails());
    System.assertEquals(
      'sensitive query detail',
      engine.applyDebugMode(result, true).adminDetailMessage
    );
    RecordHealthCheckAccess.debugPermissionOverride = null;
    System.assertNotEquals(
      null,
      RecordHealthCheckAccess.canViewDebugDetails(),
      'The platform permission check must always return a Boolean.'
    );
  }

  @isTest
  static void structuredLogValuesCannotForgeNewLines() {
    System.assertEquals(
      'ticket forged value',
      RecordHealthCheckLogger.sanitize('ticket\nforged\tvalue', 120)
    );
    System.assertEquals(
      '12345',
      RecordHealthCheckLogger.sanitize('123456789', 5)
    );
  }

  @isTest
  static void fieldPlanningIgnoresLiteralsAndInvalidMessageTokens() {
    Record_Health_Check_Rule__mdt rule = new Record_Health_Check_Rule__mdt(
      CheckMethod__c = 'Formula',
      PassFailFormula__c = 'CONTAINS(Website, "example.com") && NOT(ISBLANK(Parent.Name))',
      MessageWhenFailed__c = 'Bad token stays blank: {!Parent.Missing__c}'
    );

    Set<String> fields = new RecordHealthCheckEngine()
      .collectRecordFields(rule, Account.SObjectType);

    System.assert(fields.contains('Website'));
    System.assert(fields.contains('Parent.Name'));
    System.assert(!fields.contains('example.com'));
    System.assert(!fields.contains('Parent.Missing__c'));
  }

  @isTest
  static void sharedValidatorCoversObjectsPluginsAndJson() {
    System.assert(
      RecordHealthCheckConfigValidator.isValidObjectApiName('Account')
    );
    System.assert(
      !RecordHealthCheckConfigValidator.isValidObjectApiName('Nope__c')
    );
    System.assert(
      RecordHealthCheckConfigValidator.isValidApexPlugin(
        'AccountHasRecentActivityCheck'
      )
    );
    System.assert(
      !RecordHealthCheckConfigValidator.isValidApexPlugin('String')
    );
    System.assert(
      RecordHealthCheckConfigValidator.isJsonObject('{"daysBack":90}')
    );
    System.assert(!RecordHealthCheckConfigValidator.isJsonObject('[1,2,3]'));
  }
}
