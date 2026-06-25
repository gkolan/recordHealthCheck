# Record Health Check Configuration Guide

This guide explains how Check Sets and Rules wire to the Lightning record page card, how to choose a Check Method, and how to troubleshoot common misconfigurations. The card is advisory: it shows pass, fail, skipped, unable, or error for each Rule without blocking saves or persisting results. Prerequisites: Custom Metadata edit access in Setup and a deployed `recordHealthCheck` component.

> [!NOTE]
> **Setup labels vs API names:** Each table lists the **Setup label** you see in the metadata editor, the **API name** (`__c` or `DeveloperName`), and what to enter. Use the Setup label in conversation and checklists: for example **Check Method**, not informal terms like “check type.”

## Contents

| Section | What it covers |
| ------- | -------------- |
| [1. Mental model](#1-mental-model) | Check Set, Rule, and component wiring |
| [2. What it can check](#2-what-it-can-check) | Choosing the right Check Method |
| [3. Check Set fields](#3-check-set-fields) | Link to [Check Set field reference](../metadata/check-set.md) |
| [4. Rule fields](#4-rule-fields) | Link to [Rule field reference](../metadata/rule-fields.md) |
| [5. Result meanings](#5-result-meanings) | Status and severity |
| [6. Formula rules](#6-formula-rules) | Record-formula patterns |
| [7. Query rules](#7-query-rules) | Single-query patterns |
| [8. Compare two queries rules](#8-comparetwoqueries-rules) | Dual-query patterns |
| [9. Apex rules](#9-apex-rules) | Custom Apex patterns |
| [10. Applicability and dependencies](#10-applicability-and-dependencies) | Gating and prerequisites |
| [11. Merge tokens](#11-merge-tokens) | `{!Field}` in messages and SOQL |
| [12. Security and guardrails](#12-security-and-guardrails) | SOQL safety and permissions |
| [13. Troubleshooting](#13-troubleshooting) | Symptoms, causes, and fixes |
| [14. Review checklist](#14-review-checklist) | Pre-activation validation |
| [15. Runtime and integration](#15-runtime-and-integration) | Stack, programmatic API, edge cases |

For copy-paste examples of every pattern, see [Examples](../examples/index.md). For the formal contract, see [Design Specification](../reference/record-health-check-design-spec.md). For setup walkthrough, see [Getting Started](../installation/getting-started.md). For Debug Mode, see [Debug Mode](debug-mode.md).

## 1. Mental Model

| Piece | What it means |
| ----- | ------------- |
| Component instance | The Lightning record page component. It points to one Check Set through the **Check Set Developer Name** (`configName`) property in App Builder. |
| Check Set | A group of Rules for one base object (for example, Account). Stored in `Record_Health_Check_Set__mdt`. |
| Rule | One individual check inside a Check Set. Stored in `Record_Health_Check_Rule__mdt`. |
| Evaluator | The engine path for a Rule: Formula, Query, CompareTwoQueries, or Apex. |
| Result | The outcome shown after a Rule runs. |

Wiring example:

```text
Lightning component configName: Account_Data_Quality
Check Set DeveloperName: Account_Data_Quality
Rule DeveloperName: Account_DQ_BillingCity
```

**Where to place the component:** Lightning **record pages** only. The component needs a record context (`recordId`). It is not exposed on App or Home pages.

## 2. What It Can Check

| Check Method (Setup label) | API value | Use when |
| -------------------------- | --------- | -------- |
| **Record formula** | `Formula` | The answer is on the current record (or a parent field reachable by formula). |
| **Single query** | `Query` | One SOQL result must be compared to a static value, formula, second query, or list. |
| **Compare two queries** | `CompareTwoQueries` | Two independent SOQL results must be compared (scalar or list). |
| **Custom Apex** | `Apex` | Logic needs code (multi-object date math, scoring, external callouts in a custom plugin). |

Representative Account patterns (full walkthrough in the [Examples index](../examples/index.md)):

- Formula: Billing City is required.
- Formula + applicability: Partner Accounts must have Billing Country; others are skipped.
- Query + OneResult: Account has at least one Contact.
- Query + AnyRowPasses: At least one open Opportunity exceeds 10% of Annual Revenue.
- CompareTwoQueries: Contact count equals open Opportunity count.
- Dependency: Contact Email checked only after "has Contacts" passes.
- Apex: Recent activity via shipped class `AccountHasRecentActivityCheck`.

## 3. Check Set Fields

Every field on `Record_Health_Check_Set__mdt`: including picklist values for **Run Checks When**, display modes, and **Debug Mode**: is documented in **[Check Set fields](../metadata/check-set.md)**.

## 4. Rule Fields

Every field on `Record_Health_Check_Rule__mdt` is documented in **[Rule fields](../metadata/rule-fields.md)**.

## 5. Result Meanings

| Status | Meaning | Typical response |
| ------ | ------- | ---------------- |
| `PASS` | Rule ran and passed. | No action. |
| `FAIL` | Rule ran and found a data issue. | Record or process owner. |
| `SKIPPED` | Rule did not apply or dependency did not pass. | Review applicability or dependencies if unexpected. |
| `UNABLE_TO_EVALUATE` | Metadata, permissions, SOQL, or data blocked safe evaluation. | Review configuration, FLS, and reason code. |
| `ERROR` | Unexpected framework or Apex exception. | Review Apex plugin, debug logs, and reason code. |

| Severity | Use when |
| -------- | -------- |
| `Error` | Important problem to fix. |
| `Warning` | Should be reviewed. |
| `Info` | Contextual information. |

Severity applies **only** to `FAIL` results.

## 6. Formula Rules

Use Formula when the result is expressible with Salesforce formula syntax on the current or parent record.

- `null` formula result (for example, `Parent.Field` with no parent) → **Unable To Evaluate**, not Fail.
- Only explicit `false` fails the check.

Billing City required:

```text
PassFailFormula__c: NOT(ISBLANK(BillingCity))
MessageWhenFailed__c: {!Name} is missing Billing City.
```

Phone or Website required:

```text
PassFailFormula__c: OR(NOT(ISBLANK(Phone)), NOT(ISBLANK(Website)))
MessageWhenFailed__c: {!Name} needs either a Phone or Website.
```

### Formula operands can be formula or roll-up fields

`PassFailFormula__c` (and the optional formulas below) may reference **calculated fields** — formula fields, roll-up summaries, and even formulas of formulas — at any depth, for any type (number, text, date, boolean, picklist) and any standard function. The engine loads the whole dependency chain, so you reference the field API names you use in Setup; you do **not** rewrite checks to point at the underlying source fields.

### Showing Found vs Expected (optional)

By default a Formula check shows only **Expected** — the quoted formula text — and no **Found** value. For balance and comparison checks you can declare two optional scalar formulas so the row shows readable numbers (or text/dates) on each side, like a Query check:

| Field | Purpose |
| ----- | ------- |
| `FoundValueFormula__c` | Scalar formula → **Found** (left side — what the record has). |
| `ExpectedValueFormula__c` | Scalar formula → **Expected** (right side — what it should have). |

`PassFailFormula__c` still decides pass/fail (it must return Boolean); these two are display-only and additive.

```text
PassFailFormula__c:      BLANKVALUE(Debit_Total__c, 0) = BLANKVALUE(Credit_Total__c, 0)
FoundValueFormula__c:    BLANKVALUE(Debit_Total__c, 0)
ExpectedValueFormula__c: BLANKVALUE(Credit_Total__c, 0)
```

On a failing row this renders **Found "100"** / **Expected "75"** instead of echoing the formula.

- **When to use boolean-only:** the formula is a simple presence/condition check (`NOT(ISBLANK(...))`, `ISPICKVAL(...)`) where echoing the condition as Expected is enough.
- **When to add Found/Expected:** the formula compares two values (balance, threshold, equality, date) and seeing both sides is more actionable than the formula text.
- Leave both blank to keep the original behavior (Expected = quoted `PassFailFormula__c`, no Found).
- If a Found/Expected formula can't be resolved, the row silently falls back to the default display — it never changes pass/fail.
- Set **Scalar Formula Return Type** to the formulas' type (e.g. Number) to save FormulaEval calls in bulk/Flow runs; leave Auto if unsure.

## 7. Query Rules

Use Query when one SOQL result is the primary value.

At least one Contact:

```text
DataQuery__c: SELECT COUNT() FROM Contact WHERE AccountId = {!Id}
WhenMultipleRows__c: OneResult
Operator__c: GreaterThan
CompareAgainst__c: FixedValue
FixedValue__c: 0
```

Supported aggregates (alias required except bare `COUNT()`):

```text
COUNT(), COUNT(field), COUNT_DISTINCT(field), SUM(field), AVG(field), MIN(field), MAX(field)
```

SUM equals 10% of Annual Revenue:

```text
DataQuery__c: SELECT SUM(Amount) totalAmount FROM Opportunity WHERE AccountId = {!Id} AND IsClosed = false
FieldToRead__c: totalAmount
WhenMultipleRows__c: OneResult
Operator__c: Equals
CompareAgainst__c: RecordFormula
RecordFormulaValue__c: AnnualRevenue * 0.1
```

## 8. CompareTwoQueries Rules

Use when both sides come from SOQL.

- `OneResult` + scalar comparators for single values.
- `CompareAsLists` + `ListsOverlap`, `ListContainsAll`, or `ExactListMatch` for lists (**case-insensitive** list matching; `Contains` / `DoesNotContain` on scalar text are **case-sensitive**).

Contact count equals open Opportunity count:

```text
DataQuery__c: SELECT COUNT() FROM Contact WHERE AccountId = {!Id}
CompareToQuery__c: SELECT COUNT() FROM Opportunity WHERE AccountId = {!Id} AND IsClosed = false
WhenMultipleRows__c: OneResult
Operator__c: Equals
```

## 9. Apex Rules

Use Apex when metadata cannot express the rule safely or clearly. **Implementing a class:** [Apex plugin reference](../apex/plugin-reference.md). **Walkthroughs:** [examples catalog](../examples/index.md#example-catalog). **Contract:** [Apex plugin contract](../apex/plugin-contract.md).

**Shipped example classes:** `AccountHasRecentActivityCheck`, `AccountOpenOpportunityHealthCheck`. Deploy custom classes (for example the strategic readiness reference in [example 3](../examples/apex/03-strategic-readiness.md)) before referencing them in **Apex Class Name**.

| Setup label | API name | Role |
| ----------- | -------- | ---- |
| Apex Class | `ApexClass__c` | Class implementing `RecordHealthCheckRule` |
| Apex Settings (JSON) | `ApexSettingsJson__c` | Optional tuning map passed as `context.parameters` |

For AI-assisted drafting, see [LLM Configuration Guide: Apex](llm-configuration.md#54-apex-checkmethod__c--apex) and [recent-activity Apex pattern](llm-configuration.md#106-recent-taskevent-activity-apex-multi-object).

## 10. Applicability and Dependencies

**Applicability**: should this Rule run for this record?

| Mode | When to use |
| ---- | ----------- |
| `Always` | Universal data quality rules. |
| `Formula` | Condition is on the record (for example, `ISPICKVAL(Type, "Partner")`). |
| `SOQL` | Condition needs a related COUNT (for example, at least one open Opportunity exists). |

**Dependencies**: should this Rule run after another passes?

Set **Depends On Check** to the prerequisite `DeveloperName`. Use sparingly for checks that are misleading unless a foundation check passed first.

## 11. Merge Tokens

Messages and SOQL may use any readable field on the base record: **standard or custom**: by API name:

```text
{!Id}
{!Name}
{!BillingCity}
{!Parent.Name}
{!Customer_Tier__c}
{!Primary_Contact__c}
{!Contract_Renewal_Date__c}
```

- Use field API names exactly as shown in Setup (custom fields include the `__c` suffix).
- Missing message tokens become blank text.
- SOQL tokens are escaped and typed by the framework (strings quoted, numbers/dates/booleans unquoted).
- The engine loads every token field from the record before evaluation; if the running user lacks FLS, the check may return `RECORD_NOT_ACCESSIBLE` or `MISSING_BIND_VALUE`.

More examples: [Examples: Merge tokens in SOQL](../examples/index.md#merge-tokens-in-soql).

## 11a. Multi-line messages

**Message When Failed** and **Message When It Can't Run** support multiple lines. Press **Enter** in Setup to start a new line; each line renders as a separate line on the card. Use a blank line (press Enter twice) to add spacing between paragraphs.

```text
{!Name} is out of balance.

Debit total: {!Debit_Total__c}
Expected credit net: {!Credit_Net__c}

Contact Finance to reconcile.
```

- Merge tokens work on any line.
- Single-line messages are unchanged: no extra spacing is added.
- Messages are always plain text (HTML and links are not rendered), and screen readers announce the lines as one sentence with a pause between them.

## 12. Security and Guardrails

- Sharing, CRUD, and field access apply (`WITH USER_MODE` on dynamic SOQL).
- Keep queries narrow: clear `WHERE` clauses, merge tokens instead of hard-coded Ids.
- Editing `Record_Health_Check_Rule__mdt` is a privileged operation: anyone with Rule edit access can run SOQL as the viewing user.
- Do not put secrets or stack traces in user-facing messages.
- Unsafe SOQL (DML keywords, `FOR UPDATE`, `ALL ROWS`) is rejected.

## 13. Troubleshooting

| Symptom | Likely cause | What to check |
| ------- | ------------ | ------------- |
| Configuration not found | `configName` ≠ Check Set DeveloperName, or blank `ObjectApiName__c` on the Check Set | App Builder property, Check Set DeveloperName, and Base Object API Name. |
| Object mismatch | Wrong `ObjectApiName__c` | Check Set object vs record page object. |
| No checks run | Inactive Check Set or Rules | `IsActive__c` on Set and Rules. |
| Rule skipped | Applicability false or dependency not passed | Applicability fields and `RequiresCheck__c`. |
| Unable to evaluate | SOQL, formula, permissions, or limits | Rule fields, FLS, debug mode, reason code. |
| Rule error | Apex or framework exception | Apex class, debug logs, `DebugMode__c`. |
| Stale results after metadata edit | Component not reloaded | Refresh the record page. |
| Stale results after inline edit | No auto-rerun on record save | Click **Rerun** or refresh the page. |
| Prerequisite skipped | 25-check cap | Lower the prerequisite's Run Order so it runs within the first 25, or reduce active Rules. |
| Custom automation runs slowly or hits limits | Each `RecordHealthCheck.run` call is one full evaluation | Reduce batch size; evaluate fewer Rules per transaction; monitor debug logs. There is no packaged Flow invocable: only custom Apex. |
| Check passes in UI but fails from custom automation | Different running user (FLS) | Automation runs as the integration or invoking user: verify field access. |

For reason codes and open limitations, see [Design Specification: reason codes and open limitations](../reference/record-health-check-design-spec.md#10-reason-codes).

Pre-deployment metadata audit:

```apex
for (RecordHealthCheckMetadataValidator.ValidationIssue i :
        new RecordHealthCheckMetadataValidator().validate()) {
    System.debug(i.severity + ' ' + i.componentName + '.' + i.fieldName + ': ' + i.message);
}
```

## 14. Review Checklist

Before activating a Check Set:

- [ ] Permission set `Record_Health_Check_User` assigned to users who run the card (assign `Record_Health_Check_Admin` when Debug Mode is needed).
- [ ] Check Set DeveloperName matches component **Check Set Developer Name** in App Builder.
- [ ] `ObjectApiName__c` matches the record page object.
- [ ] Component is on a **record page** (not App/Home).
- [ ] Every active Rule has Check Name, Run Order, Check Method, Severity, and Message When Failed.
- [ ] Single query and Compare two queries Rules have required query fields and **If Query Returns Multiple Rows** set appropriately.
- [ ] `WhenZeroRows__c` is set for Any/All/CompareAsLists Rules.
- [ ] Apex Rules reference deployed `RecordHealthCheckRule` implementations.
- [ ] Dependencies reference active Rules with lower Run Order in the same Check Set.
- [ ] `DebugMode__c` is off for production unless actively troubleshooting (requires `Record_Health_Check_Debug`: see [Debug Mode guide](debug-mode.md)).
- [ ] Tested on records that pass, fail, skip, and unable-to-evaluate.

## 15. Runtime and Integration

**Stack:** Custom Metadata → Apex (Constants, Config Service, Engine, Evaluators, SoqlTemplate, ValueResolver, Logger) → LWC. Programmatic entry is the `RecordHealthCheck` façade; there is no packaged Flow invocable.

**Runtime flow (record page):**

1. LWC calls `getCheckDefinitions(configName, recordId, runId)` (not cacheable).
2. Apex loads active Check Set, validates object, returns ordered Rule definitions.
3. LWC orchestrates runs (dependencies, concurrency, display modes, run token).
4. Apex evaluates each Rule (applicability, dependencies, evaluator routing).
5. LWC renders results and summaries.

**Programmatic flow (Apex):**

1. Caller invokes `RecordHealthCheck.run` with Check Set name, Rule name, and record Id.
2. Façade logs `RUN_INVOKED`, delegates to the engine (same path as LWC `evaluateCheck`).
3. Result returned: catchable failures normalize to result statuses; uncatchable governor limits behave like any Apex API.

**Boundaries:**

- Record-page results live in component state for the session; nothing is persisted.
- Read-only: no record mutations from evaluation.
- Formula checks require API v63.0+ (FormulaEval). Package source API version is 66.0.
- Up to **5** concurrent Apex evaluations per LWC run (queued beyond that) when Stop On First Error is off; fully sequential when it is on.
- Each programmatic call (`RecordHealthCheck.run` or one Flow input row) is its own evaluation: bulk flows multiply governor cost.
- `recordId` changes after connect reload definitions; record-save does not auto-rerun checks.
- Server-side dependency gate re-evaluates prerequisites (safe for direct Apex calls; may duplicate work from the LWC path).
- Unsupported Apex plugin status strings are rejected with `APEX_EVALUATOR_ERROR`.
- All framework logs use `[RHC]` prefix with `runId` and running-user attribution via `RecordHealthCheckLogger`.

**Edge cases to plan for:**

| Scenario | Behavior |
| -------- | -------- |
| Child subquery with inner `ORDER BY`/`LIMIT` on any query-based check | Handled by depth-0-aware `RecordHealthCheckSoqlTemplate` on all paths |
| Multi-select picklist tokens | Unquoted `{!Field}` on a resolved multi-select expands to `('A', 'B')`; quoted `'{!Field}'` keeps `'A;B;C'`. Relationship paths follow the same rules when the related record is loaded. |
| Same `{!Field}` token used quoted and unquoted in one SOQL template | Each form substituted independently (2026-06-22). `Name LIKE '{!Name}%'` works when the exact `'{!Name}'` substring appears in the template. |
| Null field on existing row (multi-row Query) | Rows returned but value null + `SkipRecordsWithMissingValue` → **SKIPPED** / `VALUE_IS_EMPTY` (not `WhenZeroRows__c`) |
| CompareTwoQueries empty query side (OneResult) | Governed by **`WhenZeroRows__c`** before null-field logic: distinct from null on a returned row |
| Semicolon-only multi-select bind | Value `;` alone can produce invalid `INCLUDES ()` SOQL: avoid blank multi-select values in bind tokens |
| Apex plugin `context.record` | Engine loads merge/formula fields referenced in messages and applicability; plugins needing other fields must query by `context.recordId` |
| Managed-package Apex class names | `Type.forName` without namespace may not resolve classes in a managed namespace: use fully qualified API names when required |
| Prerequisite Rule outside the 25-check cap | Dependents skip with `DEPENDENCY_NOT_IN_RUN` (LWC only) |
| Stop On First Error | Stops only on `ERROR`, not `FAIL` or `UNABLE_TO_EVALUATE` |
| Empty multi-row query result | Defaults to `Skip` when `WhenZeroRows__c` is blank |
| Static comparison values with locale formatting | Untyped text: may fall through to string comparison |

## Related

- [Getting Started](../installation/getting-started.md): first install and first Rule
- [Examples index](../examples/index.md): copy-paste patterns
- [Design Specification](../reference/record-health-check-design-spec.md): formal contract
