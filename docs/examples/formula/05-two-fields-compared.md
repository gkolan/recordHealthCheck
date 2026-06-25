# 05 · Two fields compared to each other

> Passes when Billing City equals Shipping City on Accounts that have a Shipping City; skipped when Shipping City is blank; fails when both are set but differ.

| | |
| --- | --- |
| **Evaluator** | Record formula |
| **Sample** | [`Billing_City_Matches_Shipping_City`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Billing_City_Matches_Shipping_City.md-meta.xml) |
| **Check Set** | `Account_Examples_Formula` · [`package-Account_Examples_Formula.xml`](../../../manifest/package-Account_Examples_Formula.xml) |

## What it checks

On Accounts where Shipping City is populated, Billing City must match it. Accounts with no Shipping City are skipped entirely: an empty shipping address does not produce a misleading pass from a vacuous equality.

## When to use this

Reach for this pattern when two fields on the same record should agree: billing vs shipping, legal name vs display name, or any pairwise consistency check. The applicability formula limits evaluation to rows where the comparison is meaningful.

## Why this evaluator

Both operands are fields on the Account. No child query is needed.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `BillingCity = ShippingCity` + applicability | **This example.** Equality and skip-when-empty in metadata. |
| Single query | | Query compares query results to fixed values or other queries: not two on-record text fields directly. |
| Compare two queries | Two scalar queries returning each city | Overkill: both values are already on the record. |
| Custom Apex | Apex string equality | Same outcome with unnecessary code. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Only check that one field is not blank | [Single required field](01-single-required-field.md) |
| Compare an aggregate to an Account field | [Compare aggregate vs Account scalar](../compare-two-queries/02-aggregate-vs-account-scalar.md) |

**Verdict:** Record formula with an applicability gate is the right evaluator for on-record field equality. Step up to Compare two queries only when one side of the comparison comes from a related query.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Billing City Matches Shipping City |
| Developer Name | Billing_City_Matches_Shipping_City |
| Check Method | Record formula |
| Pass/Fail Formula | `BillingCity = ShippingCity` |
| Run This Check When | Only when a formula is true |
| Run When Formula Is True | `NOT(ISBLANK(ShippingCity))` |
| Severity | Warning |
| Message When Failed | Billing City does not match Shipping City. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Run When Formula Is True to change when the comparison runs; edit Pass/Fail Formula to compare different fields.

## How it works

When Run When Formula Is True evaluates to true, the engine evaluates Pass/Fail Formula. Otherwise the check is skipped.

```text
-- Applicability (Run When Formula Is True)
NOT(ISBLANK(ShippingCity))

-- Pass/Fail Formula
BillingCity = ShippingCity
```

**What this demonstrates**

- **Field equality**: not a blank check; both sides must agree when the gate is open.
- **Applicability formula**: skips Accounts with no shipping city so empty Shipping City never silently passes.

> [!TIP]
> To show **which** values differed on a failure, add `FoundValueFormula__c = BillingCity` and `ExpectedValueFormula__c = ShippingCity`. The row then displays Found vs Expected instead of just the formula text. See [Found / Expected values](08-found-expected-values.md).

## Get this example

This rule ships in the **`Account_Examples_Formula`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                    # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Formula.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Formula`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

On an Account with Shipping City set, change Billing City to a different value to fail; make them match to pass. Clear Shipping City to see the check skipped.

[← Examples index](../index.md) · [← Prev: Multiple required fields](04-multiple-required-and.md) · [Next: Type-scoped rule →](06-type-scoped.md)
