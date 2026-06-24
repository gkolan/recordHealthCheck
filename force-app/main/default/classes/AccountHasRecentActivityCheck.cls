/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Example implementation of RecordHealthCheckRule using the Apex evaluator.
 *
 * Checks whether an Account has at least one completed Task or logged Event
 * within a configurable look-back window. The number of days is read from
 * ApexSettingsJson__c so it can be tuned per rule without a code change:
 *
 *   ApexSettingsJson__c: {"daysBack": 90}
 *
 * Failure message, severity, and label all come from the CMT record — this
 * class only determines PASS or FAIL.
 */
public with sharing class AccountHasRecentActivityCheck implements RecordHealthCheckRule {
  private static final Integer DEFAULT_DAYS_BACK = 30;
  private static final Integer MIN_DAYS_BACK = 1;
  private static final Integer MAX_DAYS_BACK = 3650;

  public RecordHealthCheckResult evaluate(RecordHealthCheckContext context) {
    Integer daysBack = resolveDaysBack(context.parameters);
    Date cutoff = Date.today().addDays(-daysBack);

    Integer taskCount = [
      SELECT COUNT()
      FROM Task
      WHERE
        WhatId = :context.recordId
        AND IsClosed = TRUE
        AND ActivityDate >= :cutoff
      WITH USER_MODE
    ];

    Integer eventCount = [
      SELECT COUNT()
      FROM Event
      WHERE WhatId = :context.recordId AND ActivityDate >= :cutoff
      WITH USER_MODE
    ];

    RecordHealthCheckResult result = new RecordHealthCheckResult();
    result.status = (taskCount + eventCount > 0) ? 'PASS' : 'FAIL';
    return result;
  }

  private Integer resolveDaysBack(Map<String, Object> parameters) {
    if (parameters == null)
      return DEFAULT_DAYS_BACK;
    Object raw = parameters.get('daysBack');
    if (raw == null)
      return DEFAULT_DAYS_BACK;
    try {
      Integer parsed = Integer.valueOf(String.valueOf(raw));
      return parsed >= MIN_DAYS_BACK &&
        parsed <= MAX_DAYS_BACK
        ? parsed
        : DEFAULT_DAYS_BACK;
    } catch (Exception ex) {
      return DEFAULT_DAYS_BACK;
    }
  }
}
