# 01 · Two aggregate counts

> Passes when Contact count is less than or equal to open Opportunity count on the Account; fails when Contacts outnumber open Opportunities.

| | |
| --- | --- |
| **Evaluator** | Compare two queries |
| **Sample** | [`Ex_CTQ_ContactVsOppCount`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Ex_CTQ_ContactVsOppCount.md-meta.xml) |
| **Check Set** | `Account_Examples_Compare_Two_Queries` · [`package-Account_Examples_Compare_Two_Queries.xml`](../../../manifest/package-Account_Examples_Compare_Two_Queries.xml) |

## What it checks

The Account's Contact count must not exceed its open Opportunity count. Both sides are `COUNT()` aggregates from different child objects; the engine compares the two scalar results with a less-than-or-equal operator.

## When to use this

Reach for this pattern when the business rule compares two independent counts from related objects: staffing vs pipeline slots, child rows vs capacity, or any "side A must not exceed side B" rule where both sides are aggregate counts. Neither side needs a field alias because `COUNT()` returns a single value by default.

## Why this evaluator

Two separate `COUNT()` queries each return one number. Compare two queries is built to compare scalar results from Data Query and Compare-To Query directly.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | | Formula cannot run two SOQL counts and compare them. |
| Single query | One `COUNT()` with a subquery | SOQL subqueries cannot count two unrelated child objects in one expression for this pattern. |
| Compare two queries | `COUNT()` vs `COUNT()` with Less than or equal | **This example.** Baseline dual-aggregate comparison. |
| Custom Apex | Apex that runs two counts | Same outcome with code when metadata handles it. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Only "at least one Contact exists" | [Query child count minimum one](../query/01-child-count-minimum-one.md) |
| Compare a SUM to an Account field | [Aggregate vs Account scalar](02-aggregate-vs-account-scalar.md) |

**Verdict:** Compare two queries is the right evaluator when two independent query scalars (especially paired `COUNT()` results) must be compared. Use Single query when only one side needs counting.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Contact Count Does Not Exceed Open Opportunity Count |
| Developer Name | Ex_CTQ_ContactVsOppCount |
| Check Method | Compare two queries |
| Data Query | `SELECT COUNT() FROM Contact WHERE AccountId = {!Id}` |
| Compare-To Query | `SELECT COUNT() FROM Opportunity WHERE AccountId = {!Id} AND IsClosed = false` |
| If Query Returns Multiple Rows | One result (or aggregate) |
| Operator | Less than or equal |
| Run This Check When | Always |
| Severity | Info |
| Message When Failed | Contact count exceeds open opportunity count. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change.

## How it works

The engine runs Data Query and Compare-To Query, reads one scalar from each, and applies the operator.

```sql
-- Data Query
SELECT COUNT() FROM Contact WHERE AccountId = {!Id}

-- Compare-To Query
SELECT COUNT() FROM Opportunity WHERE AccountId = {!Id} AND IsClosed = false
```

**What this demonstrates**

- **Dual `COUNT()` comparison**: neither query needs Field To Read; `COUNT()` is implicit.
- **One result mode**: both queries collapse to a single scalar before comparison.

## Get this example

This rule ships in the **`Account_Examples_Compare_Two_Queries`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Compare_Two_Queries.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Compare_Two_Queries`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Add Contacts until their count exceeds open Opportunities to fail; remove Contacts or add open Opportunities until the Contact count is less than or equal to restore pass.

[← Examples index](../index.md) · [Next: Aggregate vs Account scalar →](02-aggregate-vs-account-scalar.md)
