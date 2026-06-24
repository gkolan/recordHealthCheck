/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Reference RecordHealthCheckRule — weighted readiness score for Strategic Accounts.
 * Not included in package-core.xml; deploy this class before referencing it in a Rule.
 *
 *   {"minScore": 80, "activityDaysBack": 60}
 */
public with sharing class AccountStrategicReadinessCheck implements RecordHealthCheckRule {
  private static final Integer DEFAULT_MIN_SCORE = 80;
  private static final Integer DEFAULT_ACTIVITY_DAYS = 30;
  private static final Integer MIN_SCORE = 1;
  private static final Integer MAX_SCORE = 100;
  private static final Integer MIN_ACTIVITY_DAYS = 1;
  private static final Integer MAX_ACTIVITY_DAYS = 3650;
  private static final Integer POINTS_PER_CRITERION = 25;

  public RecordHealthCheckResult evaluate(RecordHealthCheckContext context) {
    Integer minScore = resolveInt(
      context.parameters,
      'minScore',
      DEFAULT_MIN_SCORE,
      MIN_SCORE,
      MAX_SCORE
    );
    Integer activityDays = resolveInt(
      context.parameters,
      'activityDaysBack',
      DEFAULT_ACTIVITY_DAYS,
      MIN_ACTIVITY_DAYS,
      MAX_ACTIVITY_DAYS
    );

    Account acct = [
      SELECT BillingStreet, BillingCity, BillingCountry
      FROM Account
      WHERE Id = :context.recordId
      WITH USER_MODE
    ];

    Integer score = 0;
    if (hasContacts(context.recordId)) {
      score += POINTS_PER_CRITERION;
    }
    if (hasOpenPipeline(context.recordId)) {
      score += POINTS_PER_CRITERION;
    }
    if (hasRecentActivity(context.recordId, activityDays)) {
      score += POINTS_PER_CRITERION;
    }
    if (billingComplete(acct)) {
      score += POINTS_PER_CRITERION;
    }

    RecordHealthCheckResult result = new RecordHealthCheckResult();
    result.status = score >= minScore ? 'PASS' : 'FAIL';
    if (score < minScore) {
      result.actualValue = String.valueOf(score);
      result.expectedValue = String.valueOf(minScore) + '+';
    }
    return result;
  }

  private static Boolean hasContacts(Id accountId) {
    return [
        SELECT COUNT()
        FROM Contact
        WHERE AccountId = :accountId
        WITH USER_MODE
      ] > 0;
  }

  private static Boolean hasOpenPipeline(Id accountId) {
    AggregateResult ar = [
      SELECT SUM(Amount) total
      FROM Opportunity
      WHERE AccountId = :accountId AND IsClosed = FALSE
      WITH USER_MODE
    ];
    Decimal total = (Decimal) ar.get('total');
    return total != null && total > 0;
  }

  private static Boolean hasRecentActivity(Id accountId, Integer daysBack) {
    Date cutoff = Date.today().addDays(-daysBack);
    Integer tasks = [
      SELECT COUNT()
      FROM Task
      WHERE WhatId = :accountId AND IsClosed = TRUE AND ActivityDate >= :cutoff
      WITH USER_MODE
    ];
    Integer events = [
      SELECT COUNT()
      FROM Event
      WHERE WhatId = :accountId AND ActivityDate >= :cutoff
      WITH USER_MODE
    ];
    return tasks + events > 0;
  }

  private static Boolean billingComplete(Account acct) {
    return String.isNotBlank(acct.BillingStreet) &&
      String.isNotBlank(acct.BillingCity) &&
      String.isNotBlank(acct.BillingCountry);
  }

  private static Integer resolveInt(
    Map<String, Object> parameters,
    String key,
    Integer defaultValue,
    Integer min,
    Integer max
  ) {
    if (parameters == null) {
      return defaultValue;
    }
    Object raw = parameters.get(key);
    if (raw == null) {
      return defaultValue;
    }
    try {
      Integer parsed = Integer.valueOf(String.valueOf(raw));
      return parsed >= min && parsed <= max ? parsed : defaultValue;
    } catch (Exception ex) {
      return defaultValue;
    }
  }
}
