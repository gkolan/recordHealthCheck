/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Tests for AccountOpenOpportunityHealthCheck — the Apex example that fails when
 * any open Opportunity is simultaneously stale, missing Next Step, and not
 * closing this quarter.
 */
@IsTest
private class AccountOpenOpportunityHealthCheckTest {
  @IsTest
  static void noOpenOpportunitiesPasses() {
    Account account = new Account(Name = 'RHC Opp Health None');
    insert account;

    RecordHealthCheckResult result = evaluate(account.Id, null);

    System.assertEquals('PASS', result.status);
  }

  @IsTest
  static void healthyOpenOpportunityPasses() {
    Account account = new Account(Name = 'RHC Opp Health Healthy');
    insert account;

    Date inQuarter = AccountOpenOpportunityHealthCheck.getQuarterStart(
      Date.today()
    );
    insert new Opportunity(
      AccountId = account.Id,
      Name = 'Healthy deal',
      StageName = 'Prospecting',
      NextStep = 'Schedule demo',
      CloseDate = inQuarter
    );

    RecordHealthCheckResult result = evaluate(account.Id, null);

    System.assertEquals(
      'PASS',
      result.status,
      'A deal with a Next Step closing this quarter is healthy.'
    );
  }

  @IsTest
  static void unhealthyOpenOpportunityFails() {
    Account account = new Account(Name = 'RHC Opp Health Unhealthy');
    insert account;

    // No Next Step, closing far in the future, and (by default) no activity —
    // stale, so the deal is unhealthy.
    insert new Opportunity(
      AccountId = account.Id,
      Name = 'Neglected deal',
      StageName = 'Prospecting',
      CloseDate = Date.today().addYears(2)
    );

    RecordHealthCheckResult result = evaluate(account.Id, null);

    System.assertEquals('FAIL', result.status);
    System.assertEquals('1 unhealthy', result.actualValue);
    System.assertEquals('0 unhealthy', result.expectedValue);
  }

  @IsTest
  static void isUnhealthyEvaluatesEachCriterion() {
    Date staleCutoff = Date.today().addDays(-30);
    Date quarterStart = AccountOpenOpportunityHealthCheck.getQuarterStart(
      Date.today()
    );
    Date quarterEnd = quarterStart.addMonths(3).addDays(-1);

    // LastActivityDate is a read-only system field and cannot be assigned in
    // Apex; a freshly constructed Opportunity already has it null, which counts
    // as stale.
    Opportunity unhealthy = new Opportunity(
      NextStep = null,
      CloseDate = quarterStart.addMonths(6)
    );
    System.assertEquals(
      true,
      AccountOpenOpportunityHealthCheck.isUnhealthy(
        unhealthy,
        staleCutoff,
        quarterStart,
        quarterEnd
      )
    );

    // A Next Step alone is enough to make it healthy (AND logic).
    Opportunity hasNextStep = new Opportunity(
      NextStep = 'Follow up',
      CloseDate = quarterStart.addMonths(6)
    );
    System.assertEquals(
      false,
      AccountOpenOpportunityHealthCheck.isUnhealthy(
        hasNextStep,
        staleCutoff,
        quarterStart,
        quarterEnd
      )
    );
  }

  @IsTest
  static void getQuarterStartReturnsFirstDayOfQuarter() {
    System.assertEquals(
      Date.newInstance(2026, 1, 1),
      AccountOpenOpportunityHealthCheck.getQuarterStart(
        Date.newInstance(2026, 2, 14)
      )
    );
    System.assertEquals(
      Date.newInstance(2026, 10, 1),
      AccountOpenOpportunityHealthCheck.getQuarterStart(
        Date.newInstance(2026, 12, 31)
      )
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
    return new AccountOpenOpportunityHealthCheck().evaluate(context);
  }
}
