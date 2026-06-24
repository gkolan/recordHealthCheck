# 07 · Parent field traversal

> Passes when the parent Account has Billing City populated; skipped when this Account has no parent; fails when a parent exists but its Billing City is blank.

| | |
| --- | --- |
| **Evaluator** | Record formula |
| **Sample** | [`Parent_Account_Has_Billing_City`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Parent_Account_Has_Billing_City.md-meta.xml) |
| **Check Set** | `Account_Examples_Formula` · [`package-Account_Examples_Formula.xml`](../../../manifest/package-Account_Examples_Formula.xml) |

## What it checks

Child Accounts with a parent must have a parent Account whose Billing City is populated. Top-level Accounts (no Parent Account) are skipped: the check does not apply to them.

## When to use this

Reach for this pattern when quality on a related parent record should surface on the child record page: parent address completeness, parent tier, or any `Parent.Field` dot notation read. The applicability gate ensures only child Accounts are evaluated.

## Why this evaluator

`Parent.BillingCity` is available in formula context on Account. No separate query is required to reach the parent field.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `NOT(ISBLANK(Parent.BillingCity))` + ParentId gate | **This example.** Parent field via dot notation on the child. |
| Single query | `SELECT BillingCity FROM Account WHERE Id = {!ParentId}` | Can read the parent field but adds SOQL and operator wiring for a value formula already exposes. |
| Compare two queries | | Nothing here compares two query results. |
| Custom Apex | Apex parent lookup | Same outcome with unnecessary code when `Parent.Field` resolves in formula. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Check Billing City on this Account only | [Single required field](01-single-required-field.md) |
| Compare parent aggregate to child field | [Compare two queries](../compare-two-queries/01-aggregate-counts.md) |

**Verdict:** Record formula with `Parent.Field` is the right evaluator when the parent field is readable from the child via dot notation. Step up to Query when the parent data requires a filter the formula cannot express.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Parent Account Has Billing City |
| Developer Name | Parent_Account_Has_Billing_City |
| Check Method | Record formula |
| Pass/Fail Formula | `NOT(ISBLANK(Parent.BillingCity))` |
| Run This Check When | Only when a formula is true |
| Run When Formula Is True | `NOT(ISBLANK(ParentId))` |
| Severity | Warning |
| Message When Failed | The parent account is missing Billing City. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Run When Formula Is True to change when parent traversal runs; edit Pass/Fail Formula to test a different parent field.

## How it works

When Run When Formula Is True evaluates to true (Parent Account is set), the engine evaluates Pass/Fail Formula against the parent field via dot notation.

```text
-- Applicability (Run When Formula Is True)
NOT(ISBLANK(ParentId))

-- Pass/Fail Formula
NOT(ISBLANK(Parent.BillingCity))
```

**What this demonstrates**

- **`Parent.Field` traversal**: reads a parent Account field from the child record context.
- **ParentId gate**: top-level Accounts skip the check entirely.

> [!NOTE]
> Parent fields must be accessible to the running context. If the parent relationship or field cannot be resolved, the check may return unable to evaluate.

## Get this example

This rule ships in the **`Account_Examples_Formula`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                    # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Formula.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Formula`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

On a child Account, clear Billing City on the parent record to fail; populate it to pass. Remove Parent Account to see the check skipped.

[← Examples index](../index.md) · [← Prev: Type-scoped rule](06-type-scoped.md)
