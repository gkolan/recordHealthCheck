# 01 · Single required field

> Passes when Billing City is populated on the Account; fails when it is blank.

| | |
| --- | --- |
| **Evaluator** | Record formula |
| **Sample** | [`Billing_City_Is_Required`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Billing_City_Is_Required.md-meta.xml) |
| **Check Set** | `Account_Examples_Formula` · [`package-Account_Examples_Formula.xml`](../../../manifest/package-Account_Examples_Formula.xml) |

## What it checks

The Account must have a value in Billing City. The check evaluates only fields on the record under test: no related rows are queried.

## When to use this

Reach for this pattern when one field on the open record must never be empty and the condition is a simple blank test. This is the baseline formula check; every other formula example extends the same Pass/Fail Formula field with richer logic.

## Why this evaluator

The condition is entirely on the Account row. No child object, no aggregate, and no second query enter the rule.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `NOT(ISBLANK(BillingCity))` | **This example.** One field, one row, one boolean. |
| Single query | `SELECT COUNT() FROM Account WHERE Id = {!Id} AND BillingCity != null` | Reaches the same pass/fail but adds SOQL, merge tokens, and an operator for a value already on the record. |
| Compare two queries | | Nothing here compares two query results. |
| Custom Apex | Apex that reads `BillingCity` | Same outcome with code deployment and maintenance for a one-line formula. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Two interchangeable contact fields (Phone **or** Website) | [Either/or field](02-either-or-field.md) |
| Several fields must all be present | [Multiple required fields (AND)](04-multiple-required-and.md) |

**Verdict:** Record formula is the right evaluator whenever the rule reads fields on the record under test and nothing else. Step up to Query only when the evidence lives on related rows.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Billing City Is Required |
| Developer Name | Billing_City_Is_Required |
| Check Method | Record formula |
| Pass/Fail Formula | `NOT(ISBLANK(BillingCity))` |
| Run This Check When | Always |
| Severity | Error |
| Message When Failed | Billing City is missing. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change.

## How it works

The engine evaluates Pass/Fail Formula on the Account. A non-blank Billing City yields pass; blank yields fail.

```text
NOT(ISBLANK(BillingCity))
```

**What this demonstrates**

- **Single-field blank test**: `ISBLANK` covers null and empty string for text fields.
- **Always run**: no applicability gate; every Account is evaluated.

> [!NOTE]
> On fail, Expected shows the formula text; Found is omitted when the formula returns false without a scalar value to display.

## Get this example

This rule ships in the **`Account_Examples_Formula`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                    # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Formula.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Formula`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Clear Billing City on an Account to fail; enter any value to pass.

[← Examples index](../index.md) · [Next: Either/or field →](02-either-or-field.md)
