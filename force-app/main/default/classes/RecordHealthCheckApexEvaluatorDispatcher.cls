/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

public with sharing class RecordHealthCheckApexEvaluatorDispatcher {
  private static final Set<String> VALID_APEX_STATUSES = new Set<String>{
    'PASS',
    'FAIL',
    'SKIPPED',
    'UNABLE_TO_EVALUATE',
    'ERROR'
  };

  private RecordHealthCheckFormulaEvaluator formulaEvaluator = new RecordHealthCheckFormulaEvaluator();

  // ─── Public entry point ───────────────────────────────────────────────────

  public RecordHealthCheckResult evaluate(
    Record_Health_Check_Rule__mdt rule,
    Id recordId,
    SObject record
  ) {
    Long startMs = System.currentTimeMillis();
    RecordHealthCheckResult result = new RecordHealthCheckResult();
    result.checkDeveloperName = rule.DeveloperName;
    result.label = rule.CheckName__c;
    result.priority = rule.RunOrder__c;
    result.evaluatorType = 'Apex';

    try {
      result = doDispatch(rule, recordId, record, result);
    } catch (Exception ex) {
      // Last-resort catch — the inner dispatch should never surface here,
      // but platform-level failures (e.g. Type.forName on a missing class
      // when already handled) must not escape the Controller boundary.
      result.status = 'ERROR';
      result.reasonCode = 'APEX_EVALUATOR_ERROR';
      result.message = safeCannotEvaluateMessage(rule);
      result.detailMessage = ex.getMessage();
    }

    result.durationMs = System.currentTimeMillis() - startMs;
    return result;
  }

  // ─── Dispatch logic ───────────────────────────────────────────────────────

  private RecordHealthCheckResult doDispatch(
    Record_Health_Check_Rule__mdt rule,
    Id recordId,
    SObject record,
    RecordHealthCheckResult result
  ) {
    // 1. Resolve the Apex class
    if (String.isBlank(rule.ApexClass__c)) {
      result.status = 'UNABLE_TO_EVALUATE';
      result.reasonCode = 'APEX_CLASS_NOT_FOUND';
      result.message = safeCannotEvaluateMessage(rule);
      result.detailMessage = 'Apex Class Name is blank.';
      return result;
    }

    Type evaluatorType = Type.forName(rule.ApexClass__c);
    if (evaluatorType == null) {
      result.status = 'UNABLE_TO_EVALUATE';
      result.reasonCode = 'APEX_CLASS_NOT_FOUND';
      result.message = safeCannotEvaluateMessage(rule);
      result.detailMessage = 'Class "' + rule.ApexClass__c + '" was not found.';
      return result;
    }

    Object instance;
    try {
      instance = evaluatorType.newInstance();
    } catch (Exception ex) {
      result.status = 'UNABLE_TO_EVALUATE';
      result.reasonCode = 'APEX_CLASS_NOT_FOUND';
      result.message = safeCannotEvaluateMessage(rule);
      result.detailMessage =
        'Could not instantiate "' +
        rule.ApexClass__c +
        '": ' +
        ex.getMessage();
      return result;
    }

    if (!(instance instanceof RecordHealthCheckRule)) {
      result.status = 'UNABLE_TO_EVALUATE';
      result.reasonCode = 'APEX_CLASS_NOT_FOUND';
      result.message = safeCannotEvaluateMessage(rule);
      result.detailMessage =
        '"' +
        rule.ApexClass__c +
        '" does not implement RecordHealthCheckRule.';
      return result;
    }

    // 2. Parse ApexSettingsJson__c
    Map<String, Object> parameters = new Map<String, Object>();
    if (String.isNotBlank(rule.ApexSettingsJson__c)) {
      try {
        Object parsed = JSON.deserializeUntyped(rule.ApexSettingsJson__c);
        if (parsed instanceof Map<String, Object>) {
          parameters = (Map<String, Object>) parsed;
        } else {
          result.status = 'UNABLE_TO_EVALUATE';
          result.reasonCode = 'INVALID_APEX_PARAMETERS';
          result.message = safeCannotEvaluateMessage(rule);
          result.detailMessage = 'ApexSettingsJson__c must be a JSON object, not an array or scalar.';
          return result;
        }
      } catch (JSONException jex) {
        result.status = 'UNABLE_TO_EVALUATE';
        result.reasonCode = 'INVALID_APEX_PARAMETERS';
        result.message = safeCannotEvaluateMessage(rule);
        result.detailMessage =
          'ApexSettingsJson__c is not valid JSON: ' + jex.getMessage();
        return result;
      }
    }

    // 3. Build context and invoke
    RecordHealthCheckContext context = new RecordHealthCheckContext();
    context.recordId = recordId;
    context.objectApiName = recordId.getSObjectType().getDescribe().getName();
    context.record = record;
    context.parameters = parameters;
    context.checkDeveloperName = rule.DeveloperName;

    return invokeAndFinalize(
      (RecordHealthCheckRule) instance,
      context,
      rule,
      record,
      result
    );
  }

  @TestVisible
  private RecordHealthCheckResult invokeAndFinalize(
    RecordHealthCheckRule evaluator,
    RecordHealthCheckContext context,
    Record_Health_Check_Rule__mdt rule,
    SObject record,
    RecordHealthCheckResult fallbackResult
  ) {
    RecordHealthCheckResult apexResult;
    try {
      apexResult = evaluator.evaluate(context);
    } catch (Exception ex) {
      // Pluggable Apex must catch its own exceptions, but if it doesn't,
      // we catch here and return ERROR with a safe message (Section 4.4).
      fallbackResult.status = 'ERROR';
      fallbackResult.reasonCode = 'APEX_EVALUATOR_ERROR';
      fallbackResult.message = safeCannotEvaluateMessage(rule);
      fallbackResult.detailMessage = ex.getMessage();
      return fallbackResult;
    }

    if (apexResult == null) {
      fallbackResult.status = 'ERROR';
      fallbackResult.reasonCode = 'APEX_EVALUATOR_ERROR';
      fallbackResult.message = safeCannotEvaluateMessage(rule);
      fallbackResult.detailMessage =
        '"' +
        rule.ApexClass__c +
        '" returned a null result.';
      return fallbackResult;
    }

    return finalizeApexResult(rule, record, fallbackResult, apexResult);
  }

  // ─── Helper ───────────────────────────────────────────────────────────────

  @TestVisible
  private RecordHealthCheckResult finalizeApexResult(
    Record_Health_Check_Rule__mdt rule,
    SObject record,
    RecordHealthCheckResult fallbackResult,
    RecordHealthCheckResult apexResult
  ) {
    // Validate the status the plugin returned. A custom class can return
    // any string; an unrecognized value would silently mislabel the row
    // in the LWC (it falls into the "Unable to Check" bucket). Reject it
    // with a clear config error instead.
    if (!VALID_APEX_STATUSES.contains(apexResult.status)) {
      fallbackResult.status = 'ERROR';
      fallbackResult.reasonCode = 'APEX_EVALUATOR_ERROR';
      fallbackResult.message = safeCannotEvaluateMessage(rule);
      fallbackResult.detailMessage =
        '"' +
        rule.ApexClass__c +
        '" returned an unsupported status: "' +
        apexResult.status +
        '". Expected one of PASS, FAIL, SKIPPED, UNABLE_TO_EVALUATE, ERROR.';
      return fallbackResult;
    }

    // Post-process FAIL: metadata controls severity; message only when plugin omitted one.
    // AUDIT (SCAN-35, 2026-06-23):
    // BEFORE: always overwrote apexResult.message with MessageWhenFailed__c merge.
    // AFTER: preserve a non-blank plugin message; metadata fills in when blank.
    if (apexResult.status == 'FAIL') {
      apexResult.severity = rule.Severity__c;
      if (String.isBlank(apexResult.message)) {
        String resolved = formulaEvaluator.resolveMergeFields(
          rule.MessageWhenFailed__c,
          record
        );
        apexResult.message = String.isNotBlank(resolved)
          ? resolved
          : 'Check failed.';
      }
    }

    // Ensure identifying fields are always set from metadata (Apex may omit them)
    apexResult.checkDeveloperName = rule.DeveloperName;
    apexResult.label = rule.CheckName__c;
    apexResult.priority = rule.RunOrder__c;
    apexResult.evaluatorType = 'Apex';

    return apexResult;
  }

  private String safeCannotEvaluateMessage(Record_Health_Check_Rule__mdt rule) {
    return String.isNotBlank(rule.MessageWhenCannotRun__c)
      ? rule.MessageWhenCannotRun__c
      : 'This check could not be evaluated. Contact your administrator.';
  }
}
