/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Tests for AccountHasRecentActivityCheck — the Apex example that passes when an
 * Account has a completed Task or logged Event inside a tunable window.
 */
@IsTest
private class AccountHasRecentActivityCheckTest {
  @IsTest
  static void completedTaskInsideWindowPasses() {
    Account account = new Account(Name = 'RHC Recent Activity Pass');
    insert account;

    insert new Task(
      WhatId = account.Id,
      Subject = 'Recent call',
      Status = 'Completed',
      ActivityDate = Date.today()
    );

    RecordHealthCheckResult result = evaluate(account.Id, null);

    System.assertEquals('PASS', result.status);
  }

  @IsTest
  static void noActivityFails() {
    Account account = new Account(Name = 'RHC Recent Activity Fail');
    insert account;

    RecordHealthCheckResult result = evaluate(account.Id, null);

    System.assertEquals('FAIL', result.status);
  }

  @IsTest
  static void activityOutsideWindowFails() {
    Account account = new Account(Name = 'RHC Recent Activity Stale');
    insert account;

    insert new Task(
      WhatId = account.Id,
      Subject = 'Old call',
      Status = 'Completed',
      ActivityDate = Date.today().addDays(-400)
    );

    // A 90-day window excludes the 400-day-old task.
    RecordHealthCheckResult result = evaluate(
      account.Id,
      new Map<String, Object>{ 'daysBack' => 90 }
    );

    System.assertEquals('FAIL', result.status);
  }

  @IsTest
  static void invalidDaysBackFallsBackToDefault() {
    Account account = new Account(Name = 'RHC Recent Activity Default');
    insert account;

    insert new Task(
      WhatId = account.Id,
      Subject = 'Recent call',
      Status = 'Completed',
      ActivityDate = Date.today()
    );

    // Out-of-range and unparseable values both fall back to the 30-day default,
    // which still includes today's task.
    System.assertEquals(
      'PASS',
      evaluate(account.Id, new Map<String, Object>{ 'daysBack' => 999999 })
        .status
    );
    System.assertEquals(
      'PASS',
      evaluate(account.Id, new Map<String, Object>{ 'daysBack' => 'abc' })
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
    return new AccountHasRecentActivityCheck().evaluate(context);
  }
}
