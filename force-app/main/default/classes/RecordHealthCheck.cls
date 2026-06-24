/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * One-line entry point to run a SINGLE Record Health Check from anywhere —
 * Apex triggers, batch/queueable, scheduled jobs, anonymous Apex, other classes,
 * or tests. This is the simplest adoption surface: no LWC, no record page.
 *
 *   RecordHealthCheckResult r = RecordHealthCheck.run(
 *       'Account_Data_Quality', 'Account_DQ_BillingCity', accountId);
 *
 *   if (r.status == 'FAIL') { ... }
 *
 * Like the LWC path, the call is correlated by a generated `runId` and every
 * `[RHC]` log line is attributed to the actual running user.
 */
public with sharing class RecordHealthCheck {
  @TestVisible
  private static RecordHealthCheckEngine engine = new RecordHealthCheckEngine();

  /**
   * Run one check. The headline one-liner.
   * Normalizes catchable evaluation failures as result statuses. Apex governor
   * limit exceptions remain uncatchable, as they are for every Apex API.
   */
  public static RecordHealthCheckResult run(
    String configName,
    String checkDeveloperName,
    Id recordId
  ) {
    return run(configName, checkDeveloperName, recordId, null);
  }

  /**
   * Full control: supply your own correlation `runId` (e.g. a ticket number or a
   * batch job id) so this run's log lines group with related work.
   */
  public static RecordHealthCheckResult run(
    String configName,
    String checkDeveloperName,
    Id recordId,
    String runId
  ) {
    String effectiveRunId = String.isBlank(runId) ? newRunId() : runId;

    RecordHealthCheckLogger.log(
      RecordHealthCheckLogger.Level.INFO,
      effectiveRunId,
      configName,
      recordId,
      checkDeveloperName,
      'RUN_INVOKED',
      new Map<String, Object>{ 'via' => 'RecordHealthCheck.run' },
      null
    );

    RecordHealthCheckResult result = engine.evaluate(
      configName,
      checkDeveloperName,
      recordId,
      effectiveRunId
    );

    RecordHealthCheckLogger.log(
      RecordHealthCheckLogger.Level.INFO,
      effectiveRunId,
      configName,
      recordId,
      checkDeveloperName,
      'RUN_COMPLETE',
      new Map<String, Object>{
        'status' => result.status,
        'reasonCode' => result.reasonCode,
        'durationMs' => result.durationMs
      },
      null
    );

    return result;
  }

  // Correlation id for runs that don't supply one. Unique enough to group a
  // single run's log lines; not security-sensitive.
  private static String newRunId() {
    return 'api-' +
      String.valueOf(Datetime.now().getTime()) +
      '-' +
      String.valueOf(Math.abs(Crypto.getRandomInteger()));
  }
}
