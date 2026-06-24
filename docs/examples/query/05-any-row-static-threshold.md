# 05 · Any child record matches a static threshold

> Passes when at least one open Opportunity has Amount above the fixed threshold; fails when none qualify.

| | |
| --- | --- |
| **Evaluator** | Single query |
| **Sample** | [`Has_High_Value_Open_Opportunity`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Has_High_Value_Open_Opportunity.md-meta.xml) |
| **Check Set** | `Account_Examples_Query` · [`package-Account_Examples_Query.xml`](../../../manifest/package-Account_Examples_Query.xml) |

## What it checks

At least one open Opportunity on the Account must have Amount greater than the configured fixed threshold. One qualifying row is enough; the rest do not need to pass.

## When to use this

Reach for this pattern when the business rule is "at least one child clears a bar": a whale deal in the pipeline, a premium-tier contact, any single row that proves the condition. The threshold is the same for every Account in the org.

## Why this evaluator

Scans child rows for any match against a fixed number.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | | Cannot read child Opportunity Amounts. |
| Single query | At least one row must pass + fixed threshold | **This example.** Any-row OR with a static bar. |
| Compare two queries | | Threshold is fixed, not a second query or field. |
| Custom Apex | Apex `anyMatch` | Same outcome when Any row passes suffices. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Threshold should scale per Account | [Any row formula threshold](06-any-row-formula-threshold.md) |
| Every row must pass | [All rows static threshold](07-all-rows-static-threshold.md) |

**Verdict:** Single query with At least one row must pass and Compare Against = A fixed value is the right evaluator for "any child exceeds an org-wide threshold." Step to A formula on the record when the bar depends on the Account.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Has High-Value Open Opportunity |
| Developer Name | Has_High_Value_Open_Opportunity |
| Check Method | Single query |
| Data Query | `SELECT Amount FROM Opportunity WHERE AccountId = {!Id} AND IsClosed = false AND Amount != null` |
| Field To Read | Amount |
| If Query Returns Multiple Rows | At least one row must pass |
| Operator | Greater than |
| Compare Against | A fixed value |
| Fixed Value | 50000 |
| Run This Check When | Always |
| Severity | Warning |
| Message When Failed | No open opportunity exceeds $50,000. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Fixed Value to change the Amount bar.

## How it works

The engine loads open Opportunities with non-null Amount and passes if any row's Amount is greater than the fixed value.

```sql
SELECT Amount FROM Opportunity
WHERE AccountId = {!Id} AND IsClosed = false AND Amount != null
```

**What this demonstrates**

- **At least one row must pass**: one qualifying Opportunity is sufficient.
- **Static Fixed Value**: same threshold for every Account.

## Get this example

This rule ships in the **`Account_Examples_Query`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Query.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Query`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Ensure no open Opportunity Amount exceeds the threshold to fail; raise one open Opportunity above the threshold to pass.

[← Examples index](../index.md) · [← Prev: Empty result skip](04-empty-result-skip.md) · [Next: Any row formula threshold →](06-any-row-formula-threshold.md)
