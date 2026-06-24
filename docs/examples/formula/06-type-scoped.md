# 06 · Type-scoped rule

> Passes when Partner Accounts have Billing Country populated; skipped for all other Account types; fails for Partners with blank Billing Country.

| | |
| --- | --- |
| **Evaluator** | Record formula |
| **Sample** | [`Partner_Has_Billing_Country`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Partner_Has_Billing_Country.md-meta.xml) |
| **Check Set** | `Account_Examples_Formula` · [`package-Account_Examples_Formula.xml`](../../../manifest/package-Account_Examples_Formula.xml) |

## What it checks

Partner Accounts must have Billing Country set. All other Account types are skipped: the pass/fail formula is a simple blank test; the type filter lives entirely in the applicability formula.

## When to use this

Reach for this pattern when a field requirement applies only to one picklist value: a record type, tier, or segment. `ISPICKVAL` in Run When Formula Is True scopes the check without duplicating rules per type.

## Why this evaluator

The blank test and the type gate both read fields on the Account.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `NOT(ISBLANK(BillingCountry))` + `ISPICKVAL(Type, "Partner")` | **This example.** Type gate and field test in one rule. |
| Single query | `SELECT COUNT() FROM Account WHERE Id = {!Id} AND Type = 'Partner' AND BillingCountry != null` | Same outcome via SOQL for on-record fields. |
| Compare two queries | | Nothing here compares two query results. |
| Custom Apex | Apex type check + field read | Same outcome with unnecessary code. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Billing Country required on every Account | [Single required field](01-single-required-field.md) with `BillingCountry` |
| Gate on a numeric or count condition | Run This Check When = Only when a count query matches; see [Configuration Guide 10](../../guides/configuration-guide.md#10-applicability-and-dependencies) |

**Verdict:** Record formula with `ISPICKVAL` applicability is the right evaluator for picklist-scoped on-record rules. Use count-query applicability when the gate depends on related row counts instead of a field value.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Partner Has Billing Country |
| Developer Name | Partner_Has_Billing_Country |
| Check Method | Record formula |
| Pass/Fail Formula | `NOT(ISBLANK(BillingCountry))` |
| Run This Check When | Only when a formula is true |
| Run When Formula Is True | `ISPICKVAL(Type, "Partner")` |
| Severity | Error |
| Message When Failed | Partner accounts must have Billing Country set. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Run When Formula Is True to change which Account type is in scope; edit Pass/Fail Formula to test a different field.

## How it works

When Run When Formula Is True evaluates to true (Account Type is Partner), the engine evaluates Pass/Fail Formula. All other types are skipped.

```text
-- Applicability (Run When Formula Is True)
ISPICKVAL(Type, "Partner")

-- Pass/Fail Formula
NOT(ISBLANK(BillingCountry))
```

**What this demonstrates**

- **`ISPICKVAL` gate**: limits the check to one picklist value without separate rules per type.
- **Simple pass/fail under a scope**: the formula stays a basic blank test; scope is metadata-driven.

## Get this example

This rule ships in the **`Account_Examples_Formula`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                    # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Formula.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Formula`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Set Account Type to Partner and clear Billing Country to fail; set Billing Country to pass. Change Type away from Partner to see the check skipped.

[← Examples index](../index.md) · [← Prev: Two fields compared](05-two-fields-compared.md) · [Next: Parent field →](07-parent-field.md)
