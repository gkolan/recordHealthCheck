# 11 · Field must not be blank (via query)

> Passes when Account Rating is populated; fails when Rating is blank.

| | |
| --- | --- |
| **Evaluator** | Single query |
| **Sample** | [`Rating_Is_Set`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Rating_Is_Set.md-meta.xml) |
| **Check Set** | `Account_Examples_Query` · [`package-Account_Examples_Query.xml`](../../../manifest/package-Account_Examples_Query.xml) |

## What it checks

Account Rating must be set: non-blank. The Is not empty operator needs no Compare Against or Fixed Value; the operator alone tests population.

## When to use this

Reach for this pattern when a query-based blank check is preferred over Record formula: for example to feed a Requires Passing Check dependency chain or to keep all checks in Single query form. For a simple on-record blank test, Record formula is usually shorter.

## Why this evaluator

Query path for a blank test on a field readable via SOQL on the same record.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `NOT(ISBLANK(TEXT(Rating)))` | Simpler for on-record picklist blank test. |
| Single query | One result + Is not empty | **This example.** Query-based blank check. |
| Compare two queries | | No second value to compare. |
| Custom Apex | | Unnecessary for blank test. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Text field blank on Account | [Single required field](../formula/01-single-required-field.md) |
| Must be blank | [Is blank](12-is-blank.md) |

**Verdict:** Single query with Is not empty suits query-centric check sets and dependency wiring. Use Record formula for the same on-record blank test with less configuration.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Rating Is Set |
| Developer Name | Rating_Is_Set |
| Check Method | Single query |
| Data Query | `SELECT Rating FROM Account WHERE Id = {!Id} LIMIT 1` |
| Field To Read | Rating |
| If Query Returns Multiple Rows | One result (or aggregate) |
| Operator | Is not empty |
| Run This Check When | Always |
| Severity | Warning |
| Message When Failed | Account Rating has not been set. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change.

## How it works

The engine reads Rating from Data Query and passes when Is not empty is satisfied.

```sql
SELECT Rating FROM Account WHERE Id = {!Id} LIMIT 1
```

**What this demonstrates**

- **Is not empty**: no fixed value or formula compare side required.
- **Query on same record**: `{!Id}` scopes to the Account under test.

## Get this example

This rule ships in the **`Account_Examples_Query`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Query.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Query`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Clear Rating to fail; set any Rating value to pass.

[← Examples index](../index.md) · [← Prev: Does not contain](10-does-not-contain.md) · [Next: Is blank →](12-is-blank.md)
