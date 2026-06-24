/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Tests for AccountStrategicReadinessCheck — the Apex example that scores an
 * Account across four readiness criteria (25 points each) and passes when the
 * total meets a configurable threshold.
 */
@IsTest
private class AccountStrategicReadinessCheckTest {
  @IsTest
  static void bareAccountScoresZeroAndFails() {
    Account account = new Account(Name = 'RHC Readiness Bare');
    insert account;

    RecordHealthCheckResult result = evaluate(account.Id, null);

    System.assertEquals('FAIL', result.status);
    System.assertEquals('0', result.actualValue);
    System.assertEquals('80+', result.expectedValue);
  }

  @IsTest
  static void singleCriterionPassesWhenThresholdIsLow() {
    Account account = new Account(Name = 'RHC Readiness One Criterion');
    insert account;
    insert new Contact(LastName = 'Buyer', AccountId = account.Id);

    // One criterion = 25 points; a threshold of 1 is comfortably met.
    RecordHealthCheckResult result = evaluate(
      account.Id,
      new Map<String, Object>{ 'minScore' => 1 }
    );

    System.assertEquals('PASS', result.status);
  }

  @IsTest
  static void allCriteriaMetReachesFullScoreAndPasses() {
    Account account = new Account(
      Name = 'RHC Readiness Full',
      BillingStreet = '1 Market St',
      BillingCity = 'San Francisco',
      BillingCountry = 'USA'
    );
    insert account;

    insert new Contact(LastName = 'Buyer', AccountId = account.Id);
    insert new Opportunity(
      AccountId = account.Id,
      Name = 'Open pipeline',
      StageName = 'Prospecting',
      Amount = 50000,
      CloseDate = Date.today().addMonths(1)
    );
    insert new Task(
      WhatId = account.Id,
      Subject = 'Recent QBR',
      Status = 'Completed',
      ActivityDate = Date.today()
    );

    // All four criteria met = 100, clearing the default threshold of 80.
    RecordHealthCheckResult result = evaluate(account.Id, null);

    System.assertEquals('PASS', result.status);
  }

  @IsTest
  static void invalidParametersFallBackToDefaults() {
    Account account = new Account(Name = 'RHC Readiness Bad Params');
    insert account;
    insert new Contact(LastName = 'Buyer', AccountId = account.Id);

    // Unparseable and out-of-range values fall back to defaults (minScore 80),
    // so a lone 25-point criterion still fails.
    System.assertEquals(
      'FAIL',
      evaluate(
          account.Id,
          new Map<String, Object>{
            'minScore' => 'not-a-number',
            'activityDaysBack' => 999999
          }
        )
        .status
    );
  }

  private static RecordHealthCheckResult evaluate(
    Id recordId,
    Map<String, Object> parameters
  ) {
    RecordHealthCheckContext context = new RecordHealthCheckContext();
    context.recordId = recordId;
    context.objectApiName = 'Account';
    context.parameters = parameters;
    return new AccountStrategicReadinessCheck().evaluate(context);
  }
}
