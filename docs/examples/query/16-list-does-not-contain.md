# 16 · Primary value must not appear in any other list

> Passes when Account Industry does not appear among other Accounts' Industry values; fails when at least one other Account shares the same Industry.

| | |
| --- | --- |
| **Evaluator** | Single query |
| **Sample** | [`Industry_Is_Unique_Across_Accounts`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Industry_Is_Unique_Across_Accounts.md-meta.xml) |
| **Check Set** | `Account_Examples_Query` · [`package-Account_Examples_Query.xml`](../../../manifest/package-Account_Examples_Query.xml) |

## What it checks

The Account's Industry must not appear in the Industry values of any other Account in the org. Value To Test resolves Industry from the record under test; Compare-To Query loads peer Industries excluding the current Account.

## When to use this

Reach for this pattern for uniqueness or exclusion rules: industry should not duplicate peers, code must not appear in a forbidden set, value must be absent from a reference list built by SOQL.

## Why this evaluator

Scalar tested for absence across a query-built list spanning other records.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | | Cannot query peer Account Industries. |
| Single query | Value To Test + List excludes all of | **This example.** |
| Duplicate rules | Duplicate rule on Industry | Save-time only; does not surface the overlap at read time across the peer set. |
| Custom Apex | Apex uniqueness scan | Same outcome when list operator suffices. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Scalar must appear in child list | [List contains any](15-list-contains-any.md) |
| Two query lists compared | [Lists overlap](../compare-two-queries/04-lists-overlap.md) |

**Verdict:** Single query with List excludes all of is the right evaluator when a record field must be absent from a Compare-To Query list. Use List includes any of for the positive membership case.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Industry Is Unique Across Accounts |
| Developer Name | Industry_Is_Unique_Across_Accounts |
| Check Method | Single query |
| Value To Test (List Checks) | Industry |
| Compare-To Query | `SELECT Industry FROM Account WHERE Id != {!Id} AND Industry != null` |
| Compare-To Field | Industry |
| If Query Returns Multiple Rows | Compare as two lists |
| Operator | List excludes all of |
| Run This Check When | Always |
| Severity | Info |
| Message When Failed | This Industry is shared with one or more other accounts. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change.

## How it works

The engine resolves Value To Test from the Account, loads Industries from Compare-To Query, and passes only when List excludes all of finds no match.

```sql
-- Compare-To Query
SELECT Industry FROM Account
WHERE Id != {!Id} AND Industry != null
```

```text
-- Value To Test (List Checks): resolved from the Account
Industry
```

**What this demonstrates**

- **List excludes all of**: scalar must not appear in the comparison list.
- **Peer query**: `{!Id}` excluded so the current Account is not in the reference set.

## Get this example

This rule ships in the **`Account_Examples_Query`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Query.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Query`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Create another Account with the same Industry to fail; ensure no peer Account shares Industry to pass.

[← Examples index](../index.md) · [← Prev: List contains any](15-list-contains-any.md) · [Next: Count vs second query →](17-count-vs-second-query.md)
