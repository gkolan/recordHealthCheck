# 06 · Any child record matches a per-account formula threshold

> Passes when at least one open Opportunity exceeds the per-Account formula threshold; fails when none qualify.

| | |
| --- | --- |
| **Evaluator** | Single query |
| **Sample** | [`Has_Significant_Open_Opportunity`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Has_Significant_Open_Opportunity.md-meta.xml) |
| **Check Set** | `Account_Examples_Query` · [`package-Account_Examples_Query.xml`](../../../manifest/package-Account_Examples_Query.xml) |

## What it checks

At least one open Opportunity must have Amount greater than a threshold derived from the Account's own Annual Revenue at run time. Larger Accounts require proportionally larger deals to pass.

## When to use this

Reach for this pattern when the right-hand side of the comparison should come from a formula on the record under test: percentage of revenue, tier-based minimum, or any per-Account bar. Compare Against = A formula on the record resolves Record Formula Value on each evaluation.

## Why this evaluator

Child row Amount must be compared to a parent field expression, not a fixed org-wide number.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | | Cannot scan child Opportunity rows. |
| Single query | Any row passes + Record Formula Value | **This example.** Per-Account threshold from parent fields. |
| Compare two queries | SUM vs Annual Revenue | Compares totals, not "any single deal exceeds X% of revenue." |
| Custom Apex | Apex percent check | Same outcome when formula threshold suffices. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Same threshold for every Account | [Any row static threshold](05-any-row-static-threshold.md) |
| Total pipeline vs Annual Revenue | [Aggregate vs Account scalar](../compare-two-queries/02-aggregate-vs-account-scalar.md) |

**Verdict:** Single query with Compare Against = A formula on the record is the right evaluator when any child row must clear a bar computed from the Account. Use Compare two queries when comparing two query scalars (for example SUM vs field).

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Has Significant Open Opportunity |
| Developer Name | Has_Significant_Open_Opportunity |
| Check Method | Single query |
| Data Query | `SELECT Amount FROM Opportunity WHERE AccountId = {!Id} AND IsClosed = false AND Amount != null` |
| Field To Read | Amount |
| If Query Returns Multiple Rows | At least one row must pass |
| Operator | Greater than |
| Compare Against | A formula on the record |
| Record Formula Value | `AnnualRevenue * 0.1` |
| Run This Check When | Always |
| Severity | Warning |
| Message When Failed | No open opportunity exceeds 10% of Annual Revenue. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Record Formula Value to change how the per-Account threshold is calculated.

## How it works

For each open Opportunity row, the engine compares Amount to Record Formula Value evaluated on the Account. Any row that clears the bar passes the check.

```sql
SELECT Amount FROM Opportunity
WHERE AccountId = {!Id} AND IsClosed = false AND Amount != null
```

```text
-- Record Formula Value (evaluated on the Account)
AnnualRevenue * 0.1
```

**What this demonstrates**

- **Formula threshold**: right-hand side varies per Account.
- **Any row passes**: one qualifying Opportunity is enough.

## Get this example

This rule ships in the **`Account_Examples_Query`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Query.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Query`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Lower all open Opportunity Amounts below the formula threshold to fail; raise one above the threshold to pass.

[← Examples index](../index.md) · [← Prev: Any row static threshold](05-any-row-static-threshold.md) · [Next: All rows static threshold →](07-all-rows-static-threshold.md)
