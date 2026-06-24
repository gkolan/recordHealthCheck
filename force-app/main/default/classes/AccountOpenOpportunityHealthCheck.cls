/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Example RecordHealthCheckRule — flags open Opportunities that are simultaneously
 * stale, missing Next Step, and not closing this quarter. Tunable via:
 *
 *   {"staleDays": 30}
 */
public with sharing class AccountOpenOpportunityHealthCheck implements RecordHealthCheckRule {
  private static final Integer DEFAULT_STALE_DAYS = 30;
  private static final Integer MIN_STALE_DAYS = 1;
  private static final Integer MAX_STALE_DAYS = 3650;

  public RecordHealthCheckResult evaluate(RecordHealthCheckContext context) {
    Integer staleDays = resolveStaleDays(context.parameters);
    Date staleCutoff = Date.today().addDays(-staleDays);
    Date quarterStart = getQuarterStart(Date.today());
    Date quarterEnd = quarterStart.addMonths(3).addDays(-1);

    List<Opportunity> openOpps = [
      SELECT LastActivityDate, NextStep, CloseDate
      FROM Opportunity
      WHERE AccountId = :context.recordId AND IsClosed = FALSE
      WITH USER_MODE
    ];

    Integer unhealthyCount = 0;
    for (Opportunity opp : openOpps) {
      if (isUnhealthy(opp, staleCutoff, quarterStart, quarterEnd)) {
        unhealthyCount++;
      }
    }

    RecordHealthCheckResult result = new RecordHealthCheckResult();
    result.status = unhealthyCount == 0 ? 'PASS' : 'FAIL';
    if (unhealthyCount > 0) {
      result.actualValue = unhealthyCount + ' unhealthy';
      result.expectedValue = '0 unhealthy';
    }
    return result;
  }

  @TestVisible
  private static Boolean isUnhealthy(
    Opportunity opp,
    Date staleCutoff,
    Date quarterStart,
    Date quarterEnd
  ) {
    Boolean stale =
      opp.LastActivityDate == null ||
      opp.LastActivityDate < staleCutoff;
    Boolean missingNextStep = String.isBlank(opp.NextStep);
    Boolean closeNotThisQuarter =
      opp.CloseDate == null ||
      opp.CloseDate < quarterStart ||
      opp.CloseDate > quarterEnd;
    return stale && missingNextStep && closeNotThisQuarter;
  }

  @TestVisible
  private static Date getQuarterStart(Date reference) {
    Integer month = reference.month();
    Integer quarterMonth = ((Integer) Math.floor((month - 1) / 3.0) * 3) + 1;
    return Date.newInstance(reference.year(), quarterMonth, 1);
  }

  private Integer resolveStaleDays(Map<String, Object> parameters) {
    if (parameters == null)
      return DEFAULT_STALE_DAYS;
    Object raw = parameters.get('staleDays');
    if (raw == null)
      return DEFAULT_STALE_DAYS;
    try {
      Integer parsed = Integer.valueOf(String.valueOf(raw));
      return parsed >= MIN_STALE_DAYS &&
        parsed <= MAX_STALE_DAYS
        ? parsed
        : DEFAULT_STALE_DAYS;
    } catch (Exception ex) {
      return DEFAULT_STALE_DAYS;
    }
  }
}
