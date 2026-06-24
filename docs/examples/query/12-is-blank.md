# 12 · Field must be blank

> Passes when Account Source is blank; fails when Account Source has any value.

| | |
| --- | --- |
| **Evaluator** | Single query |
| **Sample** | [`Account_Source_Not_Manually_Set`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Account_Source_Not_Manually_Set.md-meta.xml) |
| **Check Set** | `Account_Examples_Query` · [`package-Account_Examples_Query.xml`](../../../manifest/package-Account_Examples_Query.xml) |

## What it checks

Account Source must remain empty: the field is owned by automation and a populated value indicates manual override. Is empty passes when the field is blank.

## When to use this

Reach for this pattern when a field should stay empty: integration-owned fields, system-populated sources, or any "must not be touched" signal surfaced at read time. Inverse of example 11.

## Why this evaluator

Query-based blank-required check for fields audited via SOQL.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `ISBLANK(AccountSource)` | Simpler on-record equivalent. |
| Single query | One result + Is empty | **This example.** |
| Compare two queries | | No comparison pair. |
| Custom Apex | | Unnecessary. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Field must be populated | [Is not blank](11-is-not-blank.md) |
| On-record blank formula | [Single required field](../formula/01-single-required-field.md) inverted |

**Verdict:** Single query with Is empty fits query-centric sets that need a must-stay-blank rule. Record formula `ISBLANK(...)` is the lighter on-record option.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Account Source Not Manually Set |
| Developer Name | Account_Source_Not_Manually_Set |
| Check Method | Single query |
| Data Query | `SELECT AccountSource FROM Account WHERE Id = {!Id} LIMIT 1` |
| Field To Read | AccountSource |
| If Query Returns Multiple Rows | One result (or aggregate) |
| Operator | Is empty |
| Run This Check When | Always |
| Severity | Error |
| Message When Failed | Account Source has been manually set: this field is owned by automation. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change.

## How it works

The engine reads AccountSource and passes when Is empty is satisfied.

```sql
SELECT AccountSource FROM Account WHERE Id = {!Id} LIMIT 1
```

**What this demonstrates**

- **Is empty**: inverse of Is not empty; no compare value.
- **Error severity**: populated automation-owned field treated as a hard violation.

## Get this example

This rule ships in the **`Account_Examples_Query`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Query.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Query`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Populate Account Source to fail; clear it to pass.

[← Examples index](../index.md) · [← Prev: Is not blank](11-is-not-blank.md) · [Next: Count upper limit →](13-count-upper-limit.md)
