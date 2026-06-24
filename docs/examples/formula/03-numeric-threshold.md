# 03 · Numeric field threshold

> Passes when Employee Count is greater than zero; fails when it is zero or blank.

| | |
| --- | --- |
| **Evaluator** | Record formula |
| **Sample** | [`Employee_Count_Is_Positive`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Employee_Count_Is_Positive.md-meta.xml) |
| **Check Set** | `Account_Examples_Formula` · [`package-Account_Examples_Formula.xml`](../../../manifest/package-Account_Examples_Formula.xml) |

## What it checks

The Account must have a positive value in Number of Employees. Zero and blank both fail: for number fields, `ISBLANK` treats zero and null the same, so the formula uses an explicit greater-than comparison instead.

## When to use this

Reach for this pattern when zero is as invalid as missing for a numeric field. Use `NOT(ISBLANK(...))` when any non-null value (including zero) should pass; use a comparison like `> 0` when zero must fail.

## Why this evaluator

The threshold is a single numeric comparison on one Account field.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `NumberOfEmployees > 0` | **This example.** Distinguishes zero from blank in one expression. |
| Single query | `SELECT COUNT() FROM Account WHERE Id = {!Id} AND NumberOfEmployees > 0` | Same pass/fail via SOQL for a field already on the record. |
| Compare two queries | | Nothing here compares two query results. |
| Custom Apex | Apex numeric comparison | Same outcome with unnecessary code. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Any non-blank number is acceptable (zero passes) | `NOT(ISBLANK(NumberOfEmployees))` in [Single required field](01-single-required-field.md) |
| Threshold should track another field on the record | Single query with Compare Against = A formula on the record |

**Verdict:** Record formula with a numeric comparator is the right evaluator for a fixed threshold on an on-record number. Move to Query when the threshold must come from a related aggregate or another field via formula binding.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Employee Count Is Positive |
| Developer Name | Employee_Count_Is_Positive |
| Check Method | Record formula |
| Pass/Fail Formula | `NumberOfEmployees > 0` |
| Run This Check When | Always |
| Severity | Warning |
| Message When Failed | Employee count is zero or blank. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Pass/Fail Formula to change the field or comparison threshold.

## How it works

The engine evaluates Pass/Fail Formula on the Account. Values greater than zero pass; zero or blank fail.

```text
NumberOfEmployees > 0
```

**What this demonstrates**

- **Numeric comparison vs blank test**: `> 0` rejects zero; `NOT(ISBLANK(...))` would accept it.
- **Warning severity**: flags implausible headcount without blocking the page.

## Get this example

This rule ships in the **`Account_Examples_Formula`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                    # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Formula.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Formula`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Set Number of Employees to zero or clear it to fail; enter any positive integer to pass.

[← Examples index](../index.md) · [← Prev: Either/or field](02-either-or-field.md) · [Next: Multiple required fields →](04-multiple-required-and.md)
