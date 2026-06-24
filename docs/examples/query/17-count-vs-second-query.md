# 17 · Primary count compared against a second query count

> Passes when Contact count is greater than or equal to open Case count; fails when open Cases outnumber Contacts.

| | |
| --- | --- |
| **Evaluator** | Single query |
| **Sample** | [`Contact_Count_Covers_Open_Case_Count`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Contact_Count_Covers_Open_Case_Count.md-meta.xml) |
| **Check Set** | `Account_Examples_Query` · [`package-Account_Examples_Query.xml`](../../../manifest/package-Account_Examples_Query.xml) |

## What it checks

Contact count on the Account must be greater than or equal to open Case count. Data Query supplies the primary `COUNT()`; Compare Against = Another query runs a second `COUNT()` for the comparison side before the operator applies.

## When to use this

Reach for this pattern when the right-hand side of a count comparison is a second SOQL result rather than a fixed literal or Account formula: staffing vs workload, coverage ratios, or any "count A vs count B" rule inside Single query. Compare two queries is the alternative when both queries are first-class Data Query and Compare-To Query fields.

## Why this evaluator

Two dynamic counts from different child objects compared in one Single query rule via Another query.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | | Cannot count Contacts and Cases. |
| Single query | Data Query `COUNT()` vs Compare-To Query `COUNT()` | **This example.** Another query as compare side. |
| Compare two queries | Data Query + Compare-To Query both `COUNT()` | Equivalent dual-count pattern with Compare two queries check method. |
| Custom Apex | Apex two counts | Same outcome when metadata chains queries. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Count vs fixed literal | [Child count minimum one](01-child-count-minimum-one.md) |
| Dual `COUNT()` as Compare two queries | [Two aggregate counts](../compare-two-queries/01-aggregate-counts.md) |

**Verdict:** Single query with Compare Against = Another query suits count-vs-count when Data Query is the primary count. Use Compare two queries when neither side is "primary + compare-to" and both queries are peers.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Contact Count Covers Open Case Count |
| Developer Name | Contact_Count_Covers_Open_Case_Count |
| Check Method | Single query |
| Data Query | `SELECT COUNT() FROM Contact WHERE AccountId = {!Id}` |
| If Query Returns Multiple Rows | One result (or aggregate) |
| Operator | Greater than or equal |
| Compare Against | Another query |
| Compare-To Query | `SELECT COUNT() FROM Case WHERE AccountId = {!Id} AND IsClosed = false` |
| Run This Check When | Always |
| Severity | Warning |
| Message When Failed | Open case count exceeds contact count. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Compare-To Query to change what the primary count is compared against.

## How it works

The engine runs Data Query and Compare-To Query, reads one `COUNT()` from each, and applies greater than or equal.

```sql
-- Data Query
SELECT COUNT() FROM Contact WHERE AccountId = {!Id}

-- Compare-To Query
SELECT COUNT() FROM Case
WHERE AccountId = {!Id} AND IsClosed = false
```

**What this demonstrates**

- **Another query compare side**: second `COUNT()` without switching to Compare two queries check method.
- **Ratio-style policy**: Contacts must cover open Case volume.

## Get this example

This rule ships in the **`Account_Examples_Query`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Query.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Query`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Add open Cases until Case count exceeds Contact count to fail; add Contacts or close Cases until Contact count is greater than or equal to open Case count to pass.

[← Examples index](../index.md) · [← Prev: List does not contain](16-list-does-not-contain.md)
