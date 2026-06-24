# 02 · Aggregate compared to an Account scalar

> Passes when total open Opportunity Amount is greater than or equal to Annual Revenue; skipped when no open Opportunity has Amount; fails when pipeline sum falls below Annual Revenue.

| | |
| --- | --- |
| **Evaluator** | Compare two queries |
| **Sample** | [`Open_Pipeline_Covers_Annual_Revenue`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Open_Pipeline_Covers_Annual_Revenue.md-meta.xml) |
| **Check Set** | `Account_Examples_Compare_Two_Queries` · [`package-Account_Examples_Compare_Two_Queries.xml`](../../../manifest/package-Account_Examples_Compare_Two_Queries.xml) |

## What it checks

Among open Opportunities with a non-null Amount, the sum of Amount must be at least Annual Revenue on the Account. Accounts with no qualifying open Opportunities are skipped by the applicability count query.

## When to use this

Reach for this pattern when one side is an aggregate across child rows (SUM, AVG, MIN, MAX) and the other is a scalar field on the record under test. This is the most common Compare two queries shape for pipeline-vs-target rules.

## Why this evaluator

The comparison binds a rolled-up child currency field to a parent Account field: two query results, not one query against a fixed threshold.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | | Formula cannot SUM child Opportunity rows. |
| Single query | `COUNT()` or `AnyRowPasses` on Amount | Tests individual rows, not total pipeline against Annual Revenue. |
| Compare two queries | `SUM(Amount)` vs `AnnualRevenue` | **This example.** Aggregate alias on one side, Account scalar on the other. |
| Custom Apex | Apex rollup + compare | Same outcome when metadata expresses the SUM and gate. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Any open Opportunity exists | [Query child count minimum one](../query/01-child-count-minimum-one.md) |
| Two plain `COUNT()` values | [Two aggregate counts](01-aggregate-counts.md) |

**Verdict:** Compare two queries earns its place when one side is a child aggregate and the other is a field on the Account (or a second query). Single query fits when the threshold is a fixed literal, not a field value.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Open Pipeline Covers Annual Revenue |
| Developer Name | Open_Pipeline_Covers_Annual_Revenue |
| Check Method | Compare two queries |
| Data Query | `SELECT SUM(Amount) pipelineTotal FROM Opportunity WHERE AccountId = {!Id} AND IsClosed = false AND Amount != null` |
| Field To Read | pipelineTotal |
| Compare-To Query | `SELECT AnnualRevenue FROM Account WHERE Id = {!Id} LIMIT 1` |
| Compare-To Field | AnnualRevenue |
| If Query Returns Multiple Rows | One result (or aggregate) |
| Operator | Greater than or equal |
| Run This Check When | Only when a count query matches |
| Run When Count Query Matches | `SELECT COUNT() FROM Opportunity WHERE AccountId = {!Id} AND IsClosed = false AND Amount != null` |
| Applicability Count Comparison | Greater than |
| Applicability Count Threshold | `0` |
| Severity | Warning |
| Message When Failed | Total open pipeline is below Annual Revenue. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Data Query and Field To Read to change which aggregate is summed; edit Compare-To Field to compare against a different Account scalar.

## How it works

When the applicability count query returns greater than zero, the engine runs both queries, reads `pipelineTotal` from the SUM alias and `AnnualRevenue` from the Account row, and compares with greater than or equal.

```sql
-- Data Query
SELECT SUM(Amount) pipelineTotal
FROM Opportunity
WHERE AccountId = {!Id} AND IsClosed = false AND Amount != null

-- Compare-To Query
SELECT AnnualRevenue FROM Account WHERE Id = {!Id} LIMIT 1

-- Applicability (Run When Count Query Matches)
SELECT COUNT() FROM Opportunity
WHERE AccountId = {!Id} AND IsClosed = false AND Amount != null
```

**What this demonstrates**

- **SUM alias**: non-`COUNT()` aggregates require an alias; Field To Read must match it.
- **Applicability count gate**: skips Accounts with no qualifying open Opportunities.

> [!NOTE]
> When no rows match the SUM query, the aggregate is null and comparison behavior follows empty-value settings on the rule.

## Get this example

This rule ships in the **`Account_Examples_Compare_Two_Queries`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Compare_Two_Queries.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Compare_Two_Queries`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

On an Account with open Opportunities that have Amount, lower pipeline totals or raise Annual Revenue until the sum falls below it to fail; increase open pipeline or lower Annual Revenue to pass. Remove all qualifying open Opportunities to see the check skipped.

[← Examples index](../index.md) · [← Prev: Two aggregate counts](01-aggregate-counts.md) · [Next: Two scalar fields →](03-scalar-fields.md)
