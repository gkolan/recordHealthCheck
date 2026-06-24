# 01 · Recent activity across Task and Event

> Passes when the Account has at least one completed Task **or** logged Event inside the look-back window; fails when it has neither.

| | |
| --- | --- |
| **Evaluator** | Custom Apex |
| **Sample** | [`AccountHasRecentActivityCheck.cls`](../../../force-app/main/default/classes/AccountHasRecentActivityCheck.cls) (in `package-core.xml`) |
| **Check Set** | `Account_Examples_Apex` · [`package-Account_Examples_Apex.xml`](../../../manifest/package-Account_Examples_Apex.xml) |

## What it checks

The Account has at least one **completed Task** or **logged Event** within a configurable look-back window. The two activity types use different filters: a Task must be closed to count; an Event counts as soon as its activity date falls inside the window. Either one passing is enough for the whole check to pass.

## When to use this

Reach for this pattern when one row on the card must mean "any qualifying activity, Task or Event," with type-specific filters and a tunable window without a code change. If two separate rows ("has recent Task" and "has recent Event") are acceptable, two Query rules do the job with less machinery.

## Why this evaluator

The reason this is Apex and not metadata is a single requirement: **one** pass/fail that means "Task **or** Event," with a **different filter per object**. No single declarative rule expresses that.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Formula | `NOT(ISBLANK(LastActivityDate))` on the Account | Reads the rolled-up activity field only. Cannot separate completed Tasks from logged Events, and the rollup can disagree with the underlying timelines. |
| Single query | `SELECT COUNT() FROM Task WHERE WhatId = {!Id} AND IsClosed = true AND ActivityDate >= LAST_N_DAYS:90`, compared to `> 0` | Sees **Tasks only**. Events on the same Account are invisible. The mirror query sees Events only. |
| Two queries (two rules) | One rule counts Tasks, one counts Events | Produces **two rows**. There is no declarative way to merge them into a single "recent activity" pass/fail. |
| Compare two queries | Compare Task `COUNT()` against Event `COUNT()` | Compares two numbers against each other. It cannot answer "is **either** count greater than zero?": that is OR logic, which `GreaterThan` does not express. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| "Account `LastActivityDate` is recent" is sufficient | Formula on `LastActivityDate`; the `Account_Everyday_Use_Cases` sample set ships `Account_EU_RecentAccountActivity` |
| "Has recent Task" and "Has recent Event" as separate rows | Two [Query](../query/01-child-count-minimum-one.md) rules |

**Verdict:** Apex earns its place here only because the result must be **one** combined row with per-object filters and a tunable window. Drop to two Query rules the moment two separate rows are acceptable.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Has Recent Activity |
| Developer Name | Has_Recent_Activity |
| Check Method | Custom Apex |
| Apex Class | `AccountHasRecentActivityCheck` |
| Apex Settings (JSON) | `{"daysBack": 90}` |
| Run This Check When | Always |
| Severity | Warning |
| Message When Failed | `{!Name} has no completed tasks or logged events in the last 90 days.` |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. The sample rule `Has_Recent_Activity` sets the window to 90 through `daysBack`; change that one value to retune the check, and the class reads it at run time.

## How it works

The class reads the window from the metadata record, derives a cutoff date, runs one count per object type, and passes if their sum is greater than zero. It sets **only** the status: the message, severity, and label all come from the configuration record above.

```apex
public with sharing class AccountHasRecentActivityCheck implements RecordHealthCheckRule {
  private static final Integer DEFAULT_DAYS_BACK = 30;
  private static final Integer MIN_DAYS_BACK = 1;
  private static final Integer MAX_DAYS_BACK = 3650;

  public RecordHealthCheckResult evaluate(RecordHealthCheckContext context) {
    Integer daysBack = resolveDaysBack(context.parameters);   // JSON → bounded Integer
    Date cutoff = Date.today().addDays(-daysBack);

    Integer taskCount = [
      SELECT COUNT() FROM Task
      WHERE WhatId = :context.recordId
        AND IsClosed = TRUE                 // Tasks must be completed
        AND ActivityDate >= :cutoff
      WITH USER_MODE
    ];
    Integer eventCount = [
      SELECT COUNT() FROM Event
      WHERE WhatId = :context.recordId       // Events: no IsClosed filter
        AND ActivityDate >= :cutoff
      WITH USER_MODE
    ];

    RecordHealthCheckResult result = new RecordHealthCheckResult();
    result.status = (taskCount + eventCount > 0) ? 'PASS' : 'FAIL';
    return result;                           // status only; copy comes from metadata
  }

  private Integer resolveDaysBack(Map<String, Object> parameters) {
    if (parameters == null) return DEFAULT_DAYS_BACK;
    Object raw = parameters.get('daysBack');
    if (raw == null) return DEFAULT_DAYS_BACK;
    try {
      Integer parsed = Integer.valueOf(String.valueOf(raw));
      return (parsed >= MIN_DAYS_BACK && parsed <= MAX_DAYS_BACK)
        ? parsed : DEFAULT_DAYS_BACK;        // out-of-range falls back
    } catch (Exception ex) {
      return DEFAULT_DAYS_BACK;              // unparseable falls back
    }
  }
}
```

**What this demonstrates**

- **JSON parameters**: `daysBack` is accepted only within 1-3650; anything missing, out of range, or unparseable falls back to 30.
- **Two queries, one outcome**: Task and Event counts collapse into a single pass/fail.
- **Status-only result**: the class never sets copy; the failure message is owned by the metadata record.

> [!NOTE]
> Both queries run `WITH USER_MODE`, so they respect the running context's object and field permissions. The class does not set Found/Expected values: a failure shows the configured message alone.

## Get this example

This rule ships in the **`Account_Examples_Apex`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                   # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Apex.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Apex`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

To make a passing Account fail, remove (or push outside the window) every completed Task and logged Event on it; add either one back inside the window to pass. To change the window, edit `daysBack` in the Apex Settings JSON.

[← Examples index](../index.md) · [Next: Open Opportunity health →](02-open-opportunity-health.md) · [Apex plugin reference](../../apex/plugin-reference.md)
