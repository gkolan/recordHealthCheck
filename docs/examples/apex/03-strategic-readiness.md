# 03 · Strategic account readiness (composite score)

> Passes when a Strategic Account's weighted readiness score meets the configured minimum; fails when the score from contacts, pipeline, activity, and billing falls short.

| | |
| --- | --- |
| **Evaluator** | Custom Apex |
| **Sample** | [`AccountStrategicReadinessCheck.cls`](../../../force-app/main/default/classes/AccountStrategicReadinessCheck.cls) (in `package-Account_Examples_Apex.xml`) |
| **Check Set** | `Account_Examples_Apex` · [`package-Account_Examples_Apex.xml`](../../../manifest/package-Account_Examples_Apex.xml) |

## What it checks

For Accounts where Type is Strategic, a readiness score from zero to one hundred must meet a configurable minimum. Four criteria each contribute equal weight: at least one Contact, open pipeline greater than zero, recent completed Task or logged Event inside the activity window, and a complete billing address (Street, City, and Country). The check passes when the sum meets the minimum; it fails with the actual score against the threshold.

## When to use this

Reach for this pattern when the outcome must be **one collapsed pass/fail** driven by a **numeric readiness score** with partial credit: not four separate Rule rows. Each criterion alone can be a Formula or Query rule, but metadata cannot sum partial passes into a single score or tune the passing bar through JSON without re-wiring Rules.

## Why this evaluator

The reason this is Apex and not metadata is **weighted scoring**: four unrelated signals must collapse into one number, compared once against a tunable minimum.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Formula | `ISPICKVAL(Type, "Strategic")` as applicability only | Can gate **when** checks run, not score four unrelated signals. |
| Single query (four rules) | Contact `COUNT() > 0`; open pipeline `SUM(Amount) > 0`; billing field blanks; activity via Task query | Produces **four rows**. Each is pass/fail: no partial score such as 75 out of 100. Changing "need three of four" versus "need 80 points" means re-wiring Rules, not JSON. |
| Query + dependency chain | All four must pass in sequence | Still four rows. Failing one shows one failure: not "readiness score 50/80." Dependencies are AND between **Rules**, not weighted points. |
| Compare two queries | Compare pipeline SUM to a static threshold | One slice only. Does not add contact, activity, and billing into one score. |
| Custom Apex (example 01) | Task + Event activity in code | Solves activity OR across objects but not **adding** four criteria into one number. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Strategic Accounts must have contacts **and** pipeline **and** billing (all mandatory) | Four [Query](../query/01-child-count-minimum-one.md) or [Formula](../formula/01-single-required-field.md) Rules, or a dependency chain: accept four rows |
| Strategic Accounts need **any one** of several signals | Query Rules with applicability; no score |
| Single readiness **score** with partial credit | **Apex** (this example) |

**Verdict:** Apex earns its place when the outcome must be **one numeric readiness score** and **one** pass/fail row. Drop to metadata when each criterion should stay visible as its own Rule and "all must pass" (binary) is acceptable.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Strategic Account Is Ready |
| Developer Name | Strategic_Account_Is_Ready |
| Check Method | Custom Apex |
| Apex Class | `AccountStrategicReadinessCheck` |
| Apex Settings (JSON) | `{"minScore": 80, "activityDaysBack": 60}` |
| Run This Check When | Only when a formula is true |
| Run When Formula Is True | `ISPICKVAL(Type, "Strategic")` |
| Severity | Error |
| Message When Failed | `This strategic account is not ready: readiness score is below the required minimum.` |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. The sample rule sets the passing bar and activity window through `minScore` and `activityDaysBack`; change those values to retune the check, and the class reads them at run time.

## How it works

The class resolves both JSON parameters, loads billing fields on the Account, awards equal points for each criterion met, and compares the total to the minimum. On fail it sets Found/Expected to the actual score and the required minimum.

```apex
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
      context.parameters, 'minScore', DEFAULT_MIN_SCORE, MIN_SCORE, MAX_SCORE
    );
    Integer activityDays = resolveInt(
      context.parameters, 'activityDaysBack', DEFAULT_ACTIVITY_DAYS,
      MIN_ACTIVITY_DAYS, MAX_ACTIVITY_DAYS
    );

    Account acct = [
      SELECT BillingStreet, BillingCity, BillingCountry
      FROM Account WHERE Id = :context.recordId
      WITH USER_MODE
    ];

    Integer score = 0;
    if (hasContacts(context.recordId)) score += POINTS_PER_CRITERION;
    if (hasOpenPipeline(context.recordId)) score += POINTS_PER_CRITERION;
    if (hasRecentActivity(context.recordId, activityDays)) score += POINTS_PER_CRITERION;
    if (billingComplete(acct)) score += POINTS_PER_CRITERION;

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
      SELECT COUNT() FROM Contact WHERE AccountId = :accountId WITH USER_MODE
    ] > 0;
  }

  private static Boolean hasOpenPipeline(Id accountId) {
    AggregateResult ar = [
      SELECT SUM(Amount) total FROM Opportunity
      WHERE AccountId = :accountId AND IsClosed = FALSE
      WITH USER_MODE
    ];
    Decimal total = (Decimal) ar.get('total');
    return total != null && total > 0;
  }

  private static Boolean hasRecentActivity(Id accountId, Integer daysBack) {
    Date cutoff = Date.today().addDays(-daysBack);
    Integer tasks = [
      SELECT COUNT() FROM Task
      WHERE WhatId = :accountId AND IsClosed = TRUE AND ActivityDate >= :cutoff
      WITH USER_MODE
    ];
    Integer events = [
      SELECT COUNT() FROM Event
      WHERE WhatId = :accountId AND ActivityDate >= :cutoff
      WITH USER_MODE
    ];
    return tasks + events > 0;              // same OR pattern as example 01
  }

  private static Boolean billingComplete(Account acct) {
    return String.isNotBlank(acct.BillingStreet) &&
      String.isNotBlank(acct.BillingCity) &&
      String.isNotBlank(acct.BillingCountry);
  }

  private static Integer resolveInt(
    Map<String, Object> parameters, String key,
    Integer defaultValue, Integer min, Integer max
  ) {
    if (parameters == null) return defaultValue;
    Object raw = parameters.get(key);
    if (raw == null) return defaultValue;
    try {
      Integer parsed = Integer.valueOf(String.valueOf(raw));
      return parsed >= min && parsed <= max ? parsed : defaultValue;
    } catch (Exception ex) {
      return defaultValue;                  // unparseable falls back
    }
  }
}
```

**What this demonstrates**

- **Weighted scoring**: four criteria at equal weight; the passing bar changes through `minScore` in JSON without a code deploy.
- **Reuse of sub-patterns**: activity OR logic from example 01 inside a composite evaluator.
- **Applicability formula**: only Strategic Accounts invoke the queries.
- **Found/Expected on fail**: shows actual score versus required minimum.

> [!NOTE]
> Non-Strategic Accounts are skipped by the applicability formula: the Apex never runs for them.

## Get this example

This rule ships in the **`Account_Examples_Apex`** Check Set, whose manifest also bundles the `AccountStrategicReadinessCheck` class (it is not in core). Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                   # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Apex.xml  # this example's Check Set + class
```

Set the component's **Check Set Developer Name** to `Account_Examples_Apex`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

To make a passing Strategic Account fail, remove one or more criteria (for example, delete Contacts or clear billing fields) until the score drops below the minimum. To change the bar or activity window, edit `minScore` and `activityDaysBack` in the Apex Settings JSON.

[← Examples index](../index.md) · [← Prev: Open Opportunity health](02-open-opportunity-health.md) · [Next: Inactive approver →](04-inactive-approver.md) · [Apex plugin reference](../../apex/plugin-reference.md)
