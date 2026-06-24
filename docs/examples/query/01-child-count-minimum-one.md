# 01 · Child record count: must have at least one

> Passes when the Account has at least one Contact; fails when the Contact count is zero.

| | |
| --- | --- |
| **Evaluator** | Single query |
| **Sample** | [`Has_At_Least_One_Contact`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Has_At_Least_One_Contact.md-meta.xml) |
| **Check Set** | `Account_Examples_Query` · [`package-Account_Examples_Query.xml`](../../../manifest/package-Account_Examples_Query.xml) |

## What it checks

The Account must have at least one related Contact. A `COUNT()` query returns a single number compared against a fixed threshold with a greater-than operator.

## When to use this

Reach for this pattern when the business rule is "at least one child row exists": contacts on an account, opportunities on an account, or any related object where presence matters. This is the baseline Single query relationship check.

## Why this evaluator

The evidence lives on related rows, not on a field the formula can read directly.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | | Formula cannot count child Contacts. |
| Single query | `COUNT()` greater than fixed value | **This example.** One number, one threshold. |
| Compare two queries | Two `COUNT()` queries compared | Needed only when the threshold is a second query, not a fixed value. |
| Custom Apex | Apex child count | Same outcome when `COUNT()` suffices. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Field blank test on the Account itself | [Single required field](../formula/01-single-required-field.md) |
| Minimum of two (or more) child rows | [Child count minimum two](02-child-count-minimum-two.md) |

**Verdict:** Single query with `COUNT()` and One result mode is the right evaluator for "at least N related rows." Use Compare two queries when the right-hand side is another query count, not a fixed literal.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Has At Least One Contact |
| Developer Name | Has_At_Least_One_Contact |
| Check Method | Single query |
| Data Query | `SELECT COUNT() FROM Contact WHERE AccountId = {!Id}` |
| If Query Returns Multiple Rows | One result (or aggregate) |
| Operator | Greater than |
| Compare Against | A fixed value |
| Fixed Value | 0 |
| Run This Check When | Always |
| Severity | Warning |
| Message When Failed | This account has no Contacts. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Fixed Value and Operator to change the minimum count threshold.

## How it works

The engine runs Data Query, reads the `COUNT()` result, and compares it to the fixed value.

```sql
SELECT COUNT() FROM Contact WHERE AccountId = {!Id}
```

**What this demonstrates**

- **`COUNT()` + One result**: aggregate returns one scalar for comparison.
- **Greater than zero**: strictly more than the fixed value means at least one Contact.

## Get this example

This rule ships in the **`Account_Examples_Query`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Query.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Query`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Remove all Contacts from an Account to fail; add one Contact to pass.

[← Examples index](../index.md) · [Next: Child count minimum two →](02-child-count-minimum-two.md)
