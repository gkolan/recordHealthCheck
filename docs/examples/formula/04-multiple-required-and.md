# 04 · Multiple required fields (AND)

> Passes when Billing City, Billing State, and Billing Country are all populated; fails when any one is blank.

| | |
| --- | --- |
| **Evaluator** | Record formula |
| **Sample** | [`Billing_Address_Is_Complete`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Billing_Address_Is_Complete.md-meta.xml) |
| **Check Set** | `Account_Examples_Formula` · [`package-Account_Examples_Formula.xml`](../../../manifest/package-Account_Examples_Formula.xml) |

## What it checks

The Account billing address must be complete: City, State, and Country are all required. The check fails if any single component is missing.

## When to use this

Reach for this pattern when several on-record fields must all be present together: address completeness, identity triads, or any "all of these" rule. Add or remove `NOT(ISBLANK(...))` clauses inside `AND()` as the requirement grows.

## Why this evaluator

Every condition reads a field on the same Account row. `AND` composes them in one pass/fail row.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `AND(NOT(ISBLANK(...)), ...)` | **This example.** One row, all conditions on the record. |
| Single query | One rule per field (three Query rules) | Produces **three rows**; cannot express "all three missing = one failure" as a single coaching message without formula. |
| Compare two queries | | Nothing here compares two query results. |
| Custom Apex | Apex AND on three fields | Same outcome with unnecessary code. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Only one field required | [Single required field](01-single-required-field.md) |
| At least one of several fields | [Either/or field](02-either-or-field.md) |

**Verdict:** Record formula with `AND` is the right evaluator when every condition is an on-record blank test. Split into separate rules only when each missing field should surface as its own row.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Billing Address Is Complete |
| Developer Name | Billing_Address_Is_Complete |
| Check Method | Record formula |
| Pass/Fail Formula | `AND(NOT(ISBLANK(BillingCity)), NOT(ISBLANK(BillingState)), NOT(ISBLANK(BillingCountry)))` |
| Run This Check When | Always |
| Severity | Error |
| Message When Failed | Billing address is incomplete: City, State, and Country are all required. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change.

## How it works

The engine evaluates Pass/Fail Formula on the Account. All three billing components must be non-blank for pass.

```text
AND(
  NOT(ISBLANK(BillingCity)),
  NOT(ISBLANK(BillingState)),
  NOT(ISBLANK(BillingCountry))
)
```

**What this demonstrates**

- **`AND` composition**: extend or shrink the requirement by editing the formula list.
- **Error severity**: incomplete address is treated as a hard data-quality gap.

## Get this example

This rule ships in the **`Account_Examples_Formula`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                    # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Formula.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Formula`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Clear any one of Billing City, Billing State, or Billing Country to fail; populate all three to pass.

[← Examples index](../index.md) · [← Prev: Numeric threshold](03-numeric-threshold.md) · [Next: Two fields compared →](05-two-fields-compared.md)
