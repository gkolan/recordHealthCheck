# 04 · Inactive approver in the approval chain

> Passes when no pending approval step is assigned to an inactive user; fails and names the offending approver(s) when one is. Can't-run when the Advanced Approvals package is absent.

| | |
| --- | --- |
| **Evaluator** | Custom Apex |
| **Sample** | [`ApprovalInactiveApproverCheck.cls`](../../../force-app/main/default/classes/ApprovalInactiveApproverCheck.cls) (in `package-Account_Examples_Apex.xml`) |
| **Check Set** | `Account_Examples_Apex` · [`package-Account_Examples_Apex.xml`](../../../manifest/package-Account_Examples_Apex.xml) |

## What it checks

Salesforce Advanced Approvals (the managed package `sbaa`) drives a record through multiple approval steps. Each step is an `sbaa__Approval__c` record whose assigned approver resolves to a user. When that user is deactivated, the step has no one to act on it and the chain silently stalls. This check looks at every **pending** approval step on the record, finds the ones whose assigned user is **inactive**, and fails: listing the inactive approver names in the message so the record owner knows exactly who to reassign.

Unlike the other Apex examples, this class sets **its own failure message** so it can name the users. The dispatcher preserves a non-blank message from the plugin; severity and label still come from the metadata record.

## When to use this

Reach for this pattern when a stalled approval is invisible until someone asks why a record has been "pending" for a week, and the fix is operational (reassign the approver), not a data correction on the record itself. Surfacing the blocked approver at read time turns a silent stall into an actionable card.

## Why this evaluator

Two requirements push this past declarative checks. First, the result must **name** the inactive user(s), which a `COUNT()` cannot do. Second, the object and field API names belong to a **managed package that may not be installed**, so the check must degrade gracefully rather than fail to compile or deploy.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Single query (count) | `SELECT COUNT() FROM sbaa__Approval__c WHERE … AND sbaa__User__r.IsActive = false`, compared to `= 0` | Detects the problem but returns only a number: it cannot tell the owner **which** approver is inactive. |
| Single query (read name) | `SELECT sbaa__User__r.Name FROM sbaa__Approval__c WHERE … IsActive = false`, Every row must pass + Is empty | Surfaces **one** name through the Found chip, but cannot list several, and the metadata still hard-references package fields. |
| Formula | | Cannot traverse to a related object's child approval rows, let alone the assigned user's `IsActive`. |
| Custom Apex | Dynamic query + named approvers | **This example.** Lists every inactive approver and compiles even without the package installed. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Pass/fail only, no names | [Single query count](../query/13-count-upper-limit.md) pattern, comparing to `= 0` |
| One name is enough, package always present | Single query reading `sbaa__User__r.Name` with **Every row must pass** + **Is empty** |

**Verdict:** Apex earns its place because the message must name the inactive approvers and the class must deploy in orgs that do not have Advanced Approvals. Drop to a Query check the moment a bare count is acceptable and the package is guaranteed present.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | No Inactive Approvers In Chain |
| Developer Name | Approval_No_Inactive_Approvers |
| Active | **Unchecked**: activate after confirming the field names below |
| Check Method | Custom Apex |
| Apex Class | `ApprovalInactiveApproverCheck` |
| Apex Settings (JSON) | `{"approvalObject":"sbaa__Approval__c","targetField":"sbaa__TargetRecordId__c","userField":"sbaa__User__c","statusField":"sbaa__Status__c","pendingStatuses":["Requested"],"maxNames":5}` |
| Run This Check When | Always |
| Severity | Error |
| Message When Failed | One or more pending approval steps are assigned to an inactive user. Reassign the approver before submitting for approval. |
| Message When It Can't Run | Could not check approvers: confirm Advanced Approvals is installed and the object and field API names in Apex Settings are correct for this org. |

> [!IMPORTANT]
> The sample rule ships **inactive**. The three API names in the JSON are managed-package members whose exact spelling varies by package version and configuration: confirm them in **Setup → Object Manager → `sbaa__Approval__c`** before activation:
> - **`approvalObject`**: the approval record object.
> - **`targetField`**: the lookup from the approval back to the record being approved (bound to the record's Id). For a Quote-based setup this may be a direct `sbaa__Quote__c`-style lookup instead.
> - **`userField`**: the **resolved assignee** lookup to `User`. This catches direct-user and related-user-field approvers. Group-type approvers have no single user here and are not evaluated.
> - **`statusField` / `pendingStatuses`**: the status field and the value(s) that mean "still waiting" (often `Requested`).

> [!NOTE]
> This table is the control panel for the check. Every API name lives in the Apex Settings JSON, so retargeting the check to a different object, lookup, or status set takes no code change: the class reads them at run time.

## How it works

The class reads the object and field names from the JSON (falling back to Advanced Approvals defaults), **guards on whether the object exists**, runs one dynamic query to collect the assigned user Ids of pending steps, then queries the standard `User` object for the inactive ones. Because no managed-package symbol appears in the code, the class compiles and deploys everywhere; the only package-dependent line is the dynamic query, isolated in `fetchAssignedUserIds`.

```apex
public RecordHealthCheckResult evaluate(RecordHealthCheckContext context) {
  Settings settings = resolveSettings(context.parameters);     // JSON → field names
  RecordHealthCheckResult result = new RecordHealthCheckResult();

  // Graceful degradation: the approval object is absent (package not installed).
  if (!Schema.getGlobalDescribe().containsKey(settings.approvalObject)) {
    result.status = 'UNABLE_TO_EVALUATE';
    result.reasonCode = 'OBJECT_NOT_FOUND';
    return result;
  }

  Set<Id> assignedUserIds;
  try {
    assignedUserIds = fetchAssignedUserIds(context.recordId, settings);  // dynamic SOQL
  } catch (Exception ex) {
    result.status = 'UNABLE_TO_EVALUATE';                      // bad field name, etc.
    result.reasonCode = 'INVALID_SOQL_TEMPLATE';
    return result;
  }

  return buildResult(assignedUserIds, result, settings);      // names the inactive users
}
```

`buildResult` queries the standard `User` object (testable without the package) and shapes the outcome:

```apex
for (User assignee : [
  SELECT Name FROM User
  WHERE Id IN :assignedUserIds AND IsActive = FALSE
  WITH USER_MODE
  ORDER BY Name
]) {
  inactiveNames.add(assignee.Name);
}
if (inactiveNames.isEmpty()) { result.status = 'PASS'; return result; }

result.status = 'FAIL';
result.message = buildMessage(inactiveNames, settings.maxNames);   // "blocked by … Jane Approver"
result.actualValue = inactiveNames.size() + ' inactive';           // Found chip
result.expectedValue = '0 inactive';                              // Expected chip
```

**What this demonstrates**

- **Graceful managed-package dependency**: `Schema.getGlobalDescribe().containsKey(...)` plus dynamic SOQL means the class deploys and runs in any org; without the package it returns `UNABLE_TO_EVALUATE`, never a false PASS.
- **Plugin-authored message**: the class sets `result.message` to list the offending approvers; the dispatcher keeps it because it is non-blank.
- **Found / Expected from Apex**: `actualValue` and `expectedValue` populate the comparison chips the same way as a Query check.
- **Configuration over code**: object, lookup, status, and the name cap are all JSON parameters.

> [!NOTE]
> The `User` query runs `WITH USER_MODE`, so it respects the running user's permissions. Group-type and queue approvers resolve to no single user and are out of scope for this example; extend `fetchAssignedUserIds` to expand group membership when group resolution is required.

## Get this example

This rule ships in the **`Account_Examples_Apex`** Check Set, **inactive by default**. Deploy the engine once, then the Check Set, then confirm the field names and activate:

```bash
sf project deploy start --manifest manifest/package-core.xml                   # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Apex.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Apex`. Then edit `Approval_No_Inactive_Approvers`, confirm the Apex Settings field names against the target org, and check **Active**. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

On a record with a pending approval whose assigned user is inactive, the check fails and names that user. Reassign the step to an active user, or reactivate the user, to pass. To target a different object, change `approvalObject`, `targetField`, and `userField` in the Apex Settings JSON; no redeploy of the class is needed.

[← Examples index](../index.md) · [← Prev: Strategic readiness](03-strategic-readiness.md) · [Apex plugin reference](../../apex/plugin-reference.md)
