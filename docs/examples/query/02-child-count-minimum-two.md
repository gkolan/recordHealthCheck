# 02 · Child record count: minimum of two

> Passes when the Account has at least two Contacts; fails when the Contact count is below two.

| | |
| --- | --- |
| **Evaluator** | Single query |
| **Sample** | [`Has_At_Least_Two_Contacts`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Has_At_Least_Two_Contacts.md-meta.xml) |
| **Check Set** | `Account_Examples_Query` · [`package-Account_Examples_Query.xml`](../../../manifest/package-Account_Examples_Query.xml) |

## What it checks

The Account must have at least two related Contacts. The same `COUNT()` query as example 01 uses a greater-than-or-equal operator so the threshold itself is inclusive.

## When to use this

Reach for this pattern when the minimum child count is two or higher and the threshold should be explicit in Fixed Value. Greater than or equal reads naturally as "at least N" when N is the literal in configuration.

## Why this evaluator

Same as example 01 (child row count), with a different operator and threshold.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | | Formula cannot count child Contacts. |
| Single query | `COUNT()` greater than or equal to fixed value | **This example.** Inclusive minimum threshold. |
| Compare two queries | | Threshold is a fixed literal, not a second query. |
| Custom Apex | Apex count ≥ 2 | Same outcome when metadata suffices. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| At least one Contact | [Child count minimum one](01-child-count-minimum-one.md) |
| Upper bound on count | [Count upper limit](13-count-upper-limit.md) |

**Verdict:** Single query with greater than or equal and a static Fixed Value is the right evaluator for an inclusive minimum child count. Use greater than with threshold zero when "at least one" is enough.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Has At Least Two Contacts |
| Developer Name | Has_At_Least_Two_Contacts |
| Check Method | Single query |
| Data Query | `SELECT COUNT() FROM Contact WHERE AccountId = {!Id}` |
| If Query Returns Multiple Rows | One result (or aggregate) |
| Operator | Greater than or equal |
| Compare Against | A fixed value |
| Fixed Value | 2 |
| Run This Check When | Always |
| Severity | Warning |
| Message When Failed | This account needs at least two Contacts. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Fixed Value to change the minimum required count.

## How it works

The engine runs Data Query, reads the `COUNT()` result, and passes when it is greater than or equal to the fixed value.

```sql
SELECT COUNT() FROM Contact WHERE AccountId = {!Id}
```

**What this demonstrates**

- **Greater than or equal**: threshold value is inclusive ("two or more").
- **Same query, different bar**: only Operator and Fixed Value change from example 01.

## Get this example

This rule ships in the **`Account_Examples_Query`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Query.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Query`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Leave only one Contact on an Account to fail; add a second Contact to pass.

[← Examples index](../index.md) · [← Prev: Child count minimum one](01-child-count-minimum-one.md) · [Next: Empty result fail →](03-empty-result-fail.md)
