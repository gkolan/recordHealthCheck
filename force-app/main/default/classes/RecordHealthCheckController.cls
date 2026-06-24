/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

public with sharing class RecordHealthCheckController {
  @TestVisible
  private static RecordHealthCheckConfigService configService = new RecordHealthCheckConfigService();
  @TestVisible
  private static RecordHealthCheckEngine engine = new RecordHealthCheckEngine();

  /**
   * Returns Check Set display settings and ordered check definitions.
   *
   * Not cacheable: metadata edits to Check Sets/Rules appear on the next
   * component load without requiring a page refresh.
   *
   * Throws AuraHandledException for all component-level failures:
   *   CONFIG_NOT_FOUND, CONFIG_INACTIVE, OBJECT_MISMATCH,
   *   NO_RECORD_CONTEXT, NO_ACTIVE_CHECKS, and LOAD_FAILED for any
   *   unexpected (non-ConfigException) error.
   */
  @AuraEnabled
  public static RecordHealthCheckDefinitionResponse getCheckDefinitions(
    String configName,
    Id recordId,
    String runId
  ) {
    // AUDIT (SCAN-21, 2026-06-23): normalize at controller boundary (engine also normalizes evaluate).
    configName = RecordHealthCheckLogger.normalizeIdentifier(configName, 80);
    runId = RecordHealthCheckLogger.normalizeIdentifier(runId, 120);
    if (String.isBlank(configName)) {
      throw buildAuraException(
        'CONFIG_NOT_FOUND',
        'Check Set Developer Name is required.'
      );
    }
    try {
      return configService.getDefinitionResponse(configName, recordId);
    } catch (RecordHealthCheckConfigService.ConfigException ex) {
      // Expected, admin-facing condition (e.g. CONFIG_NOT_FOUND) — log at DEBUG.
      RecordHealthCheckLogger.log(
        RecordHealthCheckLogger.Level.DEBUG,
        runId,
        configName,
        recordId,
        null,
        'CONFIG_EXCEPTION',
        new Map<String, Object>{ 'reasonCode' => ex.reasonCode },
        null
      );
      throw buildAuraException(ex.reasonCode, ex.getMessage());
    } catch (Exception ex) {
      RecordHealthCheckLogger.log(
        RecordHealthCheckLogger.Level.ERROR,
        runId,
        configName,
        recordId,
        null,
        'CONFIG_UNEXPECTED',
        null,
        ex
      );
      // SCAN-02: an unexpected failure here (governor limit, NPE, SOQL error) is
      // NOT a missing-config condition. Reporting CONFIG_NOT_FOUND would tell the
      // admin their Check Set does not exist when it does. Use LOAD_FAILED so the
      // LWC surfaces a generic load error (parseAuraError already treats unknown
      // codes as LOAD_FAILED); CONFIG_NOT_FOUND stays reserved for the explicit
      // not-found path raised as a ConfigException above.
      throw buildAuraException(
        'LOAD_FAILED',
        'An unexpected error occurred loading the health check configuration.'
      );
    }
  }

  /**
   * Evaluates a single check and returns exactly one RecordHealthCheckResult.
   * Catchable failures are normalized by RecordHealthCheckEngine
   * and surfaced as status = ERROR with a safe message.
   *
   * configName is validated server-side to confirm the rule belongs to the
   * named Check Set, preventing direct invocation of arbitrary rules.
   */
  @AuraEnabled
  public static RecordHealthCheckResult evaluateCheck(
    String configName,
    String checkDeveloperName,
    Id recordId,
    String runId
  ) {
    configName = RecordHealthCheckLogger.normalizeIdentifier(configName, 80);
    checkDeveloperName = RecordHealthCheckLogger.normalizeIdentifier(
      checkDeveloperName,
      80
    );
    runId = RecordHealthCheckLogger.normalizeIdentifier(runId, 120);
    try {
      return engine.evaluate(configName, checkDeveloperName, recordId, runId);
    } catch (Exception ex) {
      // Engine promises never to throw, but guard the boundary regardless
      RecordHealthCheckLogger.log(
        RecordHealthCheckLogger.Level.ERROR,
        runId,
        configName,
        recordId,
        checkDeveloperName,
        'CONTROLLER_BOUNDARY_ERROR',
        null,
        ex
      );
      RecordHealthCheckResult errorResult = new RecordHealthCheckResult();
      errorResult.checkDeveloperName = checkDeveloperName;
      errorResult.status = 'ERROR';
      errorResult.reasonCode = 'APEX_EVALUATOR_ERROR';
      errorResult.message = 'An unexpected error occurred. Contact your administrator.';
      return errorResult;
    }
  }

  // ─── Helper ───────────────────────────────────────────────────────────────

  private static AuraHandledException buildAuraException(
    String reasonCode,
    String message
  ) {
    // Surface a safe message to the LWC; reasonCode is embedded for diagnostic use.
    // Raw internal details are never passed through (Default Evaluation Rule 14).
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(
      JSON.serialize(
        new Map<String, String>{
          'reasonCode' => reasonCode,
          'message' => message
        }
      )
    );
    return ex;
  }
}
