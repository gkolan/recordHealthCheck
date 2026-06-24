# 02 · Either/or field requirement

> Passes when the Account has Phone **or** Website populated; fails when both are blank.

| | |
| --- | --- |
| **Evaluator** | Record formula |
| **Sample** | [`Phone_Or_Website_Is_Required`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Phone_Or_Website_Is_Required.md-meta.xml) |
| **Check Set** | `Account_Examples_Formula` · [`package-Account_Examples_Formula.xml`](../../../manifest/package-Account_Examples_Formula.xml) |

## What it checks

The Account must have at least one of Phone or Website filled in. Either field alone is enough; the check fails only when both are empty.

## When to use this

Reach for this pattern when two fields are interchangeable for reachability (one channel is sufficient), and the rule should surface the gap at read time rather than require both. Swap in any pair of field API names; the `OR` structure stays the same.

## Why this evaluator

The decision is a boolean combination of two fields on the same row. No related data is involved.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `OR(NOT(ISBLANK(Phone)), NOT(ISBLANK(Website)))` | **This example.** Native `OR` on two on-record fields. |
| Single query | Two separate Query rules: one per field | Produces **two rows** instead of one combined pass/fail. |
| Compare two queries | | Nothing here compares two query results. |
| Custom Apex | Apex OR on two fields | Same outcome with unnecessary code. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Exactly one field must be present | [Single required field](01-single-required-field.md) |
| All of several fields required | [Multiple required fields (AND)](04-multiple-required-and.md) |

**Verdict:** Record formula with `OR` is the right evaluator for "at least one of these on-record fields." Split into separate rules only when each field deserves its own row in the component.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Phone or Website Is Required |
| Developer Name | Phone_Or_Website_Is_Required |
| Check Method | Record formula |
| Pass/Fail Formula | `OR(NOT(ISBLANK(Phone)), NOT(ISBLANK(Website)))` |
| Run This Check When | Always |
| Severity | Warning |
| Message When Failed | Neither Phone nor Website is set. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change.

## How it works

The engine evaluates Pass/Fail Formula on the Account. If either Phone or Website is non-blank, the check passes.

```text
OR(NOT(ISBLANK(Phone)), NOT(ISBLANK(Website)))
```

**What this demonstrates**

- **`OR` for interchangeable fields**: one populated field satisfies the whole check.
- **Warning severity**: missing both channels is flagged without the weight of Error.

## Get this example

This rule ships in the **`Account_Examples_Formula`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                    # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Formula.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Formula`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Clear both Phone and Website to fail; populate either one to pass.

[← Examples index](../index.md) · [← Prev: Single required field](01-single-required-field.md) · [Next: Numeric threshold →](03-numeric-threshold.md)
