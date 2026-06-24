/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Example RecordHealthCheckRule — flags pending approval steps whose assigned
 * user is inactive, and names the offending user(s) in the failure message.
 *
 * Built for Salesforce Advanced Approvals (managed package "sbaa"), but every
 * object and field API name is read dynamically and may be overridden through
 * ApexSettingsJson__c. Because nothing references the managed package at compile
 * time, this class compiles and deploys in orgs that do NOT have Advanced
 * Approvals installed — it simply returns UNABLE_TO_EVALUATE there.
 *
 *   {"approvalObject":"sbaa__Approval__c","targetField":"sbaa__TargetRecordId__c",
 *    "userField":"sbaa__User__c","statusField":"sbaa__Status__c",
 *    "pendingStatuses":["Requested"],"maxNames":5}
 *
 * Unlike the other Apex examples, this class sets its own failure message so it
 * can list the inactive approver names. The dispatcher preserves a non-blank
 * plugin message; severity and label still come from the metadata record.
 */
public with sharing class ApprovalInactiveApproverCheck implements RecordHealthCheckRule {
  @TestVisible
  private static final String DEFAULT_APPROVAL_OBJECT = 'sbaa__Approval__c';
  @TestVisible
  private static final String DEFAULT_TARGET_FIELD = 'sbaa__TargetRecordId__c';
  @TestVisible
  private static final String DEFAULT_USER_FIELD = 'sbaa__User__c';
  @TestVisible
  private static final String DEFAULT_STATUS_FIELD = 'sbaa__Status__c';
  private static final List<String> DEFAULT_PENDING_STATUSES = new List<String>{
    'Requested'
  };
  private static final Integer DEFAULT_MAX_NAMES = 5;
  private static final Integer MIN_MAX_NAMES = 1;
  private static final Integer MAX_MAX_NAMES = 25;

  public RecordHealthCheckResult evaluate(RecordHealthCheckContext context) {
    Settings settings = resolveSettings(context.parameters);
    RecordHealthCheckResult result = new RecordHealthCheckResult();

    // Graceful degradation: the approval object is absent (Advanced Approvals
    // not installed, or a custom object name was mistyped).
    if (!Schema.getGlobalDescribe().containsKey(settings.approvalObject)) {
      result.status = 'UNABLE_TO_EVALUATE';
      result.reasonCode = 'OBJECT_NOT_FOUND';
      result.detailMessage =
        'Object ' +
        settings.approvalObject +
        ' is not present in this org.';
      return result;
    }

    Set<Id> assignedUserIds;
    try {
      assignedUserIds = fetchAssignedUserIds(context.recordId, settings);
    } catch (Exception ex) {
      // A bad field name or malformed dynamic query surfaces as can't-run, never
      // as a false PASS.
      result.status = 'UNABLE_TO_EVALUATE';
      result.reasonCode = 'INVALID_SOQL_TEMPLATE';
      result.detailMessage = ex.getMessage();
      return result;
    }

    return buildResult(assignedUserIds, result, settings);
  }

  /**
   * The only managed-package-dependent step: a dynamic query over the approval
   * object. Isolated so the rest of the logic stays unit-testable without the
   * package, and so a configuration error is caught and reported cleanly.
   */
  private Set<Id> fetchAssignedUserIds(Id recordId, Settings settings) {
    Set<Id> userIds = new Set<Id>();
    String soql =
      'SELECT ' +
      settings.userField +
      ' FROM ' +
      settings.approvalObject +
      ' WHERE ' +
      settings.targetField +
      ' = :recordId' +
      ' AND ' +
      settings.statusField +
      ' IN :pendingStatuses' +
      ' AND ' +
      settings.userField +
      ' != null';
    Map<String, Object> binds = new Map<String, Object>{
      'recordId' => recordId,
      'pendingStatuses' => settings.pendingStatuses
    };
    for (
      SObject row : Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)
    ) {
      Object raw = row.get(settings.userField);
      if (raw != null) {
        userIds.add((Id) raw);
      }
    }
    return userIds;
  }

  /**
   * Standard-object logic — fully unit-testable without the managed package.
   * Resolves which of the assigned users are inactive and shapes the result.
   */
  @TestVisible
  private RecordHealthCheckResult buildResult(
    Set<Id> assignedUserIds,
    RecordHealthCheckResult result,
    Settings settings
  ) {
    if (assignedUserIds == null || assignedUserIds.isEmpty()) {
      result.status = 'PASS';
      return result;
    }

    List<String> inactiveNames = new List<String>();
    for (User assignee : [
      SELECT Name
      FROM User
      WHERE Id IN :assignedUserIds AND IsActive = FALSE
      WITH USER_MODE
      ORDER BY Name
    ]) {
      inactiveNames.add(assignee.Name);
    }

    if (inactiveNames.isEmpty()) {
      result.status = 'PASS';
      return result;
    }

    result.status = 'FAIL';
    result.message = buildMessage(inactiveNames, settings.maxNames);
    result.actualValue = inactiveNames.size() + ' inactive';
    result.expectedValue = '0 inactive';
    return result;
  }

  @TestVisible
  private static String buildMessage(List<String> names, Integer maxNames) {
    Integer shown = Math.min(names.size(), maxNames);
    List<String> head = new List<String>();
    for (Integer i = 0; i < shown; i++) {
      head.add(names[i]);
    }
    String joined = String.join(head, ', ');
    Integer remaining = names.size() - shown;
    if (remaining > 0) {
      joined += ' (+' + remaining + ' more)';
    }
    return 'Approval chain blocked by inactive approver(s): ' +
      joined +
      '. Reassign the approver(s) before submitting for approval.';
  }

  @TestVisible
  private class Settings {
    public String approvalObject = DEFAULT_APPROVAL_OBJECT;
    public String targetField = DEFAULT_TARGET_FIELD;
    public String userField = DEFAULT_USER_FIELD;
    public String statusField = DEFAULT_STATUS_FIELD;
    public List<String> pendingStatuses = DEFAULT_PENDING_STATUSES.clone();
    public Integer maxNames = DEFAULT_MAX_NAMES;
  }

  @TestVisible
  private Settings resolveSettings(Map<String, Object> parameters) {
    Settings settings = new Settings();
    if (parameters == null) {
      return settings;
    }
    settings.approvalObject = stringOr(
      parameters.get('approvalObject'),
      settings.approvalObject
    );
    settings.targetField = stringOr(
      parameters.get('targetField'),
      settings.targetField
    );
    settings.userField = stringOr(
      parameters.get('userField'),
      settings.userField
    );
    settings.statusField = stringOr(
      parameters.get('statusField'),
      settings.statusField
    );

    Object statusesRaw = parameters.get('pendingStatuses');
    if (statusesRaw instanceof List<Object>) {
      List<String> statuses = new List<String>();
      for (Object value : (List<Object>) statusesRaw) {
        if (value != null && String.isNotBlank(String.valueOf(value))) {
          statuses.add(String.valueOf(value));
        }
      }
      if (!statuses.isEmpty()) {
        settings.pendingStatuses = statuses;
      }
    }

    Object maxRaw = parameters.get('maxNames');
    if (maxRaw != null) {
      try {
        Integer parsed = Integer.valueOf(String.valueOf(maxRaw));
        if (parsed >= MIN_MAX_NAMES && parsed <= MAX_MAX_NAMES) {
          settings.maxNames = parsed;
        }
      } catch (Exception ex) {
        // Out of range or unparseable keeps the default.
      }
    }
    return settings;
  }

  private static String stringOr(Object raw, String fallback) {
    if (raw instanceof String && String.isNotBlank((String) raw)) {
      return (String) raw;
    }
    return fallback;
  }
}
