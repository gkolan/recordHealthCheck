# 02 · Open Opportunity health (child aggregation)

> Passes when no open Opportunity on the Account is simultaneously stale, missing a Next Step, and scheduled outside the current quarter; fails when at least one open Opportunity matches all three conditions.

| | |
| --- | --- |
| **Evaluator** | Custom Apex |
| **Sample** | [`AccountOpenOpportunityHealthCheck.cls`](../../../force-app/main/default/classes/AccountOpenOpportunityHealthCheck.cls) (in `package-core.xml`) |
| **Check Set** | `Account_Examples_Apex` · [`package-Account_Examples_Apex.xml`](../../../manifest/package-Account_Examples_Apex.xml) |

## What it checks

Among **open** Opportunities on the Account, the check looks for rows that are unhealthy on **every** dimension at once: last activity is missing or older than the look-back window, Next Step is blank, and Close Date is missing or falls outside the current calendar quarter. The Account passes when no open Opportunity satisfies all three; it fails when at least one does.

## When to use this

Reach for this pattern when the business rule binds **multiple field conditions to the same child row**: not to the Account as a whole. Separate Query rules can flag stale Opportunities, missing Next Steps, or bad Close Dates independently, but they cannot require that the **same** Opportunity fail all three together. A single dense SOQL WHERE can approximate pass/fail, but per-row clarity, explicit quarter boundaries, and an unhealthy count on fail belong in Apex.

## Why this evaluator

The reason this is Apex and not metadata is **same-Opportunity AND**: one open Opportunity must be stale **and** lack a Next Step **and** sit outside this quarter before the check fails.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Formula | | Formula runs on the Account only. It cannot loop open Opportunities and apply three field conditions per child row. |
| Single query | One `COUNT()` WHERE with all three conditions AND-ed in SOQL | Can produce pass/fail, but the WHERE is hard to read and maintain; SOQL date literals must match the org calendar; blank Next Step handling is brittle; Found/Expected cannot show how many children matched without extra work. |
| Three queries (three rules) | One rule for stale opps, one for missing Next Step, one for Close Date | Produces **three rows**. An Account can pass stale on one Opportunity and fail Next Step on another: metadata cannot require the **same** child to fail all three. |
| Query + AllRowsPass | Every open Opportunity row must pass one comparator | Applies **one** comparison per row. Cannot AND three unrelated field conditions with different semantics per row. |
| Compare two queries | | Nothing here is "compare two query scalars or lists." |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| "Any open Opportunity is stale" (one condition) | [Query](../query/01-child-count-minimum-one.md) + `COUNT()` greater than zero |
| "Every open Opportunity has a Next Step" | [Query](../query/11-is-not-blank.md) + `AllRowsPass` or `AnyRowPasses` |
| Same Opportunity must fail all three checks together | **Apex** (this example) or one dense Query WHERE (harder to own) |

**Verdict:** Apex earns its place when the rule is **per-Opportunity combined logic** with maintainable code and an unhealthy count on fail. Drop to a single Query only if a long SOQL WHERE is acceptable and per-row clarity in the UI is not required.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Open Opportunities Are Healthy |
| Developer Name | Open_Opportunities_Are_Healthy |
| Check Method | Custom Apex |
| Apex Class | `AccountOpenOpportunityHealthCheck` |
| Apex Settings (JSON) | `{"staleDays": 30}` |
| Run This Check When | Only when a count query matches |
| Run When Count Query Matches | `SELECT COUNT() FROM Opportunity WHERE AccountId = {!Id} AND IsClosed = false` |
| Applicability Count Comparison | Greater than |
| Applicability Count Threshold | `0` |
| Severity | Error |
| Message When Failed | `One or more open opportunities are stale, missing a Next Step, or have no close date this quarter.` |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. The sample rule sets the stale window through `staleDays`; change that one value to retune how old `LastActivityDate` must be before an Opportunity counts as stale, and the class reads it at run time.

## How it works

The class reads the stale window from the metadata record, loads open Opportunities, evaluates the three conditions per row, and fails when any row matches all three. On fail it sets Found/Expected to show how many Opportunities were unhealthy.

```apex
public with sharing class AccountOpenOpportunityHealthCheck implements RecordHealthCheckRule {
  private static final Integer DEFAULT_STALE_DAYS = 30;
  private static final Integer MIN_STALE_DAYS = 1;
  private static final Integer MAX_STALE_DAYS = 3650;

  public RecordHealthCheckResult evaluate(RecordHealthCheckContext context) {
    Integer staleDays = resolveStaleDays(context.parameters);   // JSON → bounded Integer
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

  private static Boolean isUnhealthy(
    Opportunity opp, Date staleCutoff, Date quarterStart, Date quarterEnd
  ) {
    Boolean stale =
      opp.LastActivityDate == null || opp.LastActivityDate < staleCutoff;
    Boolean missingNextStep = String.isBlank(opp.NextStep);
    Boolean closeNotThisQuarter =
      opp.CloseDate == null ||
      opp.CloseDate < quarterStart ||
      opp.CloseDate > quarterEnd;
    return stale && missingNextStep && closeNotThisQuarter;   // all three on same row
  }

  private static Date getQuarterStart(Date reference) {
    Integer month = reference.month();
    Integer quarterMonth = ((Integer) Math.floor((month - 1) / 3.0) * 3) + 1;
    return Date.newInstance(reference.year(), quarterMonth, 1);
  }

  private Integer resolveStaleDays(Map<String, Object> parameters) {
    if (parameters == null) return DEFAULT_STALE_DAYS;
    Object raw = parameters.get('staleDays');
    if (raw == null) return DEFAULT_STALE_DAYS;
    try {
      Integer parsed = Integer.valueOf(String.valueOf(raw));
      return (parsed >= MIN_STALE_DAYS && parsed <= MAX_STALE_DAYS)
        ? parsed : DEFAULT_STALE_DAYS;
    } catch (Exception ex) {
      return DEFAULT_STALE_DAYS;
    }
  }
}
```

**What this demonstrates**

- **Run When Count Query Matches**: the Rule skips Apex when the Account has no open Opportunities.
- **Per-child boolean logic**: three conditions are AND-ed on each Opportunity in a loop instead of one opaque WHERE clause.
- **Found/Expected on fail**: surfaces how many children matched the combined bar.

> [!NOTE]
> Quarter boundaries use calendar quarters in Apex (`getQuarterStart`), not SOQL `THIS_QUARTER`. Both queries run `WITH USER_MODE`. The failure message comes from the configuration record; the class sets status and Found/Expected only.

## Get this example

This rule ships in the **`Account_Examples_Apex`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                   # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Apex.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Apex`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

To make a passing Account fail, add an open Opportunity with blank Next Step, `LastActivityDate` older than the stale window, and `CloseDate` outside the current quarter. Remove or fix that Opportunity to pass. To change the stale window, edit `staleDays` in the Apex Settings JSON.

[← Examples index](../index.md) · [← Prev: Recent activity](01-recent-activity.md) · [Next: Strategic readiness →](03-strategic-readiness.md) · [Apex plugin reference](../../apex/plugin-reference.md)
