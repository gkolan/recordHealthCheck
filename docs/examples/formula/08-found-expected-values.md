# 08 · Found / Expected values on a Formula check

> Fails when an Account has fewer than 10 employees, and shows the actual count (**Found**) next to the required minimum (**Expected**) instead of just echoing the formula. Also demonstrates a multi-line failure message.

| | |
| --- | --- |
| **Evaluator** | Record formula |
| **Sample** | [`Employee_Count_Meets_Minimum`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Employee_Count_Meets_Minimum.md-meta.xml) |
| **Check Set** | `Account_Examples_Formula` · [`package-Account_Examples_Formula.xml`](../../../manifest/package-Account_Examples_Formula.xml) |

## What it checks

The Account must have at least 10 employees. On failure the row shows **Found** (the account's actual `NumberOfEmployees`) and **Expected** (the minimum, `10`) as labelled chips — the same Found/Expected display Query checks use — so the gap is obvious at a glance.

## When to use this

Add `FoundValueFormula__c` / `ExpectedValueFormula__c` whenever a Formula check **compares two values** — a balance, a threshold, an equality, or a date — and seeing both sides is more useful than reading the formula text. For a plain presence check (`NOT(ISBLANK(...))`) leave them blank; the default Expected (the quoted formula) is enough.

| Field | Setup label | Role |
| ----- | ----------- | ---- |
| `PassFailFormula__c` | Pass/Fail Formula | Decides pass/fail (must return Boolean). **Unchanged.** |
| `FoundValueFormula__c` | Found Value Formula | Optional scalar → **Found** (left side). |
| `ExpectedValueFormula__c` | Expected Value Formula | Optional scalar → **Expected** (right side). |

## Why this evaluator

Both the value and the threshold are on the record, so a Record formula resolves everything in one expression. Found/Expected are **display-only**: they do not change pass/fail.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula + Found/Expected | `NumberOfEmployees >= 10` with both sides shown | **This example.** One formula, readable numbers. |
| Single query | `COUNT()` vs FixedValue `10` | Works, but the value is already on the record — no query needed. |
| Custom Apex | Apex sets `actualValue` / `expectedValue` | Same display with unnecessary code. |

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Employee Count Meets Minimum |
| Developer Name | Employee_Count_Meets_Minimum |
| Check Method | Record formula |
| Pass/Fail Formula | `BLANKVALUE(NumberOfEmployees, 0) >= 10` |
| Found Value Formula | `BLANKVALUE(NumberOfEmployees, 0)` |
| Expected Value Formula | `10` |
| Scalar Formula Return Type | Number |
| Severity | Warning |
| Message When Failed | `{!Name} is below the staffing minimum.`<br>*(blank line)*<br>`Compare the Found and Expected values, then update the Employees field.` |

> [!CAUTION]
> **Keep the two display formulas consistent with Pass/Fail Formula.** The engine does **not** compare Found and Expected to each other — `PassFailFormula__c` alone decides pass/fail. If the display formulas describe a different comparison, the row can pass while Found ≠ Expected (or vice versa), which misleads. Mirror each side of the Pass/Fail comparison: here Found is the left operand (`NumberOfEmployees`) and Expected is the right (`10`).

## How it works

```text
-- Pass/Fail Formula (decides pass/fail; must be Boolean)
BLANKVALUE(NumberOfEmployees, 0) >= 10

-- Found Value Formula (display only → "Found")
BLANKVALUE(NumberOfEmployees, 0)

-- Expected Value Formula (display only → "Expected")
10
```

On an Account with 4 employees the check **fails** and the row shows **Found `"4"`** / **Expected `"10"`**, beneath a two-line failure message. When both display formulas are blank, the row falls back to the original behavior (Expected = the quoted Pass/Fail Formula, no Found). An unresolvable display formula also falls back silently — it never changes pass/fail.

**What this demonstrates**

- **Found / Expected on a Formula check**: scalar display values like a Query check, without rewriting the check as a query.
- **Any scalar type**: number, currency, percent, text, date, or boolean — set **Scalar Formula Return Type** to save FormulaEval calls in bulk runs.
- **Calculated-field operands**: Found/Expected may reference formula fields, roll-ups, and nested formula-of-formula chains — the engine loads the whole dependency chain (see [Configuration Guide §6](../../guides/configuration-guide.md#6-formula-rules)).
- **Multi-line message**: the failure message uses a blank line to separate the headline from the action (see [Configuration Guide §11a](../../guides/configuration-guide.md#11a-multi-line-messages)).

### Balance pattern (custom fields)

The canonical use is a balance check across custom currency fields:

```text
Pass/Fail Formula:      BLANKVALUE(Debit_Total__c, 0) = BLANKVALUE(Credit_Total__c, 0)
Found Value Formula:    BLANKVALUE(Debit_Total__c, 0)
Expected Value Formula: BLANKVALUE(Credit_Total__c, 0)
```

On a failing row this renders **Found `"100"`** / **Expected `"75"`** instead of the formula text. (Shown here for illustration — the deployable sample above uses standard Account fields so it installs in any org.)

## Get this example

This rule ships in the **`Account_Examples_Formula`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                      # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Formula.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Formula`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Set an Account's Employees to a value below 10 to fail and see **Found** vs **Expected**; set it to 10 or more to pass. Clear the two display formulas to confirm the row falls back to showing only the quoted Pass/Fail Formula.

[← Examples index](../index.md) · [← Prev: Parent field](07-parent-field.md)
