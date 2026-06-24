# Record Health Check Design Specification

**Version:** 2026-06-22 (aligned with `force-app/` at this commit)

Record Health Check is a metadata-driven framework for evaluating Salesforce records from a Lightning record page. Check Sets and Rules live in Custom Metadata Types (CMTs). Apex validates and evaluates those Rules. A Lightning Web Component (LWC) orchestrates the run and displays results.

The framework is **read-only**. It does not block saves or mutate record data. Runtime outcomes live in LWC state and `[RHC]` debug logs only; nothing is persisted (see [14](#14-logging-and-observability)).

For Setup walkthroughs and field tables, see [Getting Started](../installation/getting-started.md) and the [Configuration Guide](../guides/configuration-guide.md). This document is the formal contract: runtime layout, evaluators, reason codes, and integration boundaries.

> [!NOTE]
> **June 2026 UI refresh:** Formal LWC contracts are in [15](#15-lwc-behavior) below.

> [!NOTE]
> **Modular reading:** The same content is split by topic in [`spec/`](../spec/index.md) for focused review (metadata models, LWC contracts, limitations, and so on). This file remains the canonical entry point: section numbers and anchors here are stable for cross-links.

## Related guides

| Goal | Start here |
| ---- | ---------- |
| Configure checks in Setup | [Getting Started](../installation/getting-started.md) → [Configuration Guide](../guides/configuration-guide.md) |
| Review runtime layout and contracts | Sections 1-3, 9-15, and the field reference in Sections 4-5 |
| Navigate source code | [Architecture Map](architecture-map.md) |
| Copying working patterns | [Examples index](../examples/index.md) |

Terminology is consistent across all documents:

- **Check Set**: one `Record_Health_Check_Set__mdt` record; controls a component instance.
- **Rule**: one `Record_Health_Check_Rule__mdt` record; one evaluable check.
- **Evaluator**: the Apex code path for a Rule (`Formula`, `Query`, `CompareTwoQueries`, or `Apex`).
- **Status**: the outcome of one Rule (`PASS`, `FAIL`, `SKIPPED`, `UNABLE_TO_EVALUATE`, or `ERROR`).

## 1. Goals

- Define record health checks in metadata without changing component code.
- Support formula, SOQL, two-query comparison, and custom Apex evaluation patterns.
- Return clear statuses for pass, fail, skipped, unable-to-evaluate, and unexpected errors.
- Enforce sharing, CRUD, field access, SOQL safety, and row limits.
- Keep the user experience predictable on record pages.
- Support programmatic single-check evaluation from Apex (including custom automation invoked from Flow, batch, or triggers).
- Keep configuration explicit in metadata and contracts reviewable in one place.

## 2. Non-Goals

- Blocking record saves.
- Replacing validation rules, duplicate rules, or flow automation.
- Translating labels and messages automatically.

**Out of scope today (with nuance):**

- **Full result history on the record page.** The LWC does not show past runs; nothing is persisted (see [14](#14-logging-and-observability)).
- **Background health monitoring as a product feature.** There is no built-in scheduler and no packaged Flow invocable. Individual checks **can** be invoked via `RecordHealthCheck.run` from Apex: including a **custom** invocable action built for Flow, scheduled flows, batch/queueable jobs, or triggers. Each call is one Rule on one record, with governor limits per invocation.

## 3. Runtime Architecture

| Layer | Responsibility |
| ----- | -------------- |
| Custom Metadata | Stores Check Sets and Rules. |
| `RecordHealthCheckConstants` | Single source of truth for valid-value sets and framework caps (25 checks, 2000 rows). |
| Apex Controller | Exposes definition loading and single-check evaluation to LWC. |
| `RecordHealthCheck` façade | One-line Apex entry point for single-check runs outside the record page; no packaged Flow invocable. |
| Config Service | Loads metadata and validates Check Set and Rule configuration. |
| Engine | Loads the current record, checks applicability and dependencies, routes to evaluators, and normalizes results. |
| Evaluators | Execute Formula, Query, CompareTwoQueries, or Apex checks. |
| `RecordHealthCheckSoqlTemplate` | Depth-0-aware SOQL normalizer (`WITH USER_MODE`, row cap, keyword rejection). Used by single-query evaluator, dual-query evaluator, and engine applicability SOQL. |
| `RecordHealthCheckComparatorEngine` | Shared scalar, multi-row, list, and unary comparators for the SOQL evaluators; also formats `actualValue` / `expectedValue` for the UI. |
| `RecordHealthCheckValueResolver` | Shared scalar/list extraction, query-exception classification, typed equality and ordered comparison. |
| Logger | Central logging sink (`RecordHealthCheckLogger`): all framework log lines flow here with `runId` correlation and running-user attribution. |
| LWC | Loads definitions, orchestrates check runs, respects dependencies, and renders results. |

Primary flow:

1. LWC calls `RecordHealthCheckController.getCheckDefinitions(configName, recordId)`.
2. Apex loads one active Check Set by `DeveloperName`.
3. Apex confirms the current record object matches `ObjectApiName__c`.
4. Apex returns ordered active Rule definitions.
5. LWC starts the run according to the Check Set trigger mode.
6. LWC calls `evaluateCheck` for each Rule through a five-request worker pool.
7. Apex validates, evaluates dependencies, and evaluates each Rule.
8. LWC reveals results in Check Set order.

**Deployment surfaces:**

| Surface | Entry point | Notes |
| ------- | ----------- | ----- |
| Lightning record page | LWC `recordHealthCheck` | Primary UX: requires `recordId` and `configName`. Exposed on `lightning__RecordPage` only. |
| Apex (any context) | `RecordHealthCheck.run(configName, checkDeveloperName, recordId)` | One Rule per call; catchable failures return result statuses. An optional overload adds a `runId` for log correlation. |

## 4. Check Set Model (`Record_Health_Check_Set__mdt`)

A Check Set defines one group of Rules for one component instance on one object.

> [!NOTE]
> Field reference (Setup labels, API names, picklist values): [Check Set fields](../metadata/check-set.md).

### 4.1 Framework limits (not configurable)

| Limit | Value | Behavior |
| ----- | ----- | -------- |
| Maximum active Rules per Check Set in one run | 25 | First 25 by `RunOrder__c` ascending, then `DeveloperName` ascending. `checksOmittedByLimit` is true when more active Rules exist. `totalAvailableCheckCount` is returned by Apex but **not displayed** in the LWC UI (the header shows a fixed “First 25 shown” badge). |
| Definition reload | Per component load or `recordId` change | `getCheckDefinitions` is **not** cacheable. Metadata edits appear on the next component load. After `connectedCallback`, a change to `recordId` also reloads definitions. A full page refresh reloads record field data as well. |
| Concurrent evaluations | Up to **5 in flight** when `StopOnSystemError__c` is false | The LWC queues all eligible checks (up to 25) but caps concurrent `evaluateCheck` Apex calls at `MAX_CONCURRENT_EVALUATIONS` (5); additional checks wait in a client-side queue. Display order remains priority-ordered via a drain buffer. When `StopOnSystemError__c` is true, checks run **sequentially** (one Apex call at a time). |
| Run isolation | Per run | LWC increments `_runToken` on each run so stale in-flight results from a prior run are discarded. |

## 5. Rule Model (`Record_Health_Check_Rule__mdt`)

A Rule defines one check inside a Check Set.

> [!NOTE]
> Field reference (Setup labels, API names, per-method fields): [Rule fields](../metadata/rule-fields.md).

### 5.1 Dependencies

Dependency contract:

- Prerequisite must be active and in the same Check Set.
- Prerequisite must have a strictly lower `RunOrder__c` (validated by `RecordHealthCheckMetadataValidator`).
- Dependent Rule runs only when prerequisite returns `PASS`.
- If prerequisite is missing, inactive, fails, errors, is skipped, or cannot be evaluated, dependent is `SKIPPED` with `DEPENDENCY_NOT_PASSED`.
- Cycles return `CIRCULAR_DEPENDENCY` with status `UNABLE_TO_EVALUATE` on both the LWC (client pre-seed, no Apex call) and direct Apex evaluation.
- Enforced **both** client-side (LWC, before each Apex call) and server-side (`RecordHealthCheckEngine`, for direct Apex/API callers). Server-side evaluation re-runs the prerequisite, which can duplicate work when the LWC already evaluated it.
- If prerequisite is omitted from the run because of the 25-check cap, dependent is `SKIPPED` with `DEPENDENCY_NOT_IN_RUN`.

### 5.2 Applicability (pre-evaluation gate)

Applicability is evaluated before the Rule evaluator. If false, the Rule returns `SKIPPED` with `APPLICABILITY_NOT_MET`. If it cannot be evaluated safely, the Rule returns `UNABLE_TO_EVALUATE`.

## 6. Check Methods

Setup field: **Check Method** (`CheckMethod__c`). Subsections below use API values; Setup picklist labels are in parentheses.

### Record formula (`Formula`)

Evaluates `PassFailFormula__c` against the loaded record. Formula must return Boolean.

| Formula result | Status |
| -------------- | ------ |
| `true` | `PASS` |
| `false` | `FAIL` |
| `null` (for example, null relationship traversal) | `UNABLE_TO_EVALUATE` |
| Non-boolean result | `UNABLE_TO_EVALUATE` |
| Formula error or inaccessible field | `UNABLE_TO_EVALUATE` |

Uses Salesforce FormulaEval API (`Formula.builder()`). Requires API v63.0+ (Spring '25). Salesforce platform limit: **100 FormulaEval calls per Apex transaction**. The framework tracks calls for the whole transaction and throws `FORMULA_EVAL_LIMIT` when the count reaches **95** (a 5-call safety margin). A single Rule can consume multiple FormulaEval calls (formula body, applicability, merge-field resolution). Flow or batch jobs that evaluate many checks in one transaction share one budget.

### Single query (`Query`)

Runs `DataQuery__c` and compares the extracted result to a static value, formula value, query value, unary blank check, or list.

Scalar aggregate SOQL is supported for `OneResult`. Supported functions: `COUNT`, `COUNT_DISTINCT`, `SUM`, `AVG`, `MIN`, `MAX`. Alias aggregate expressions and reference the alias from `FieldToRead__c` or `CompareToField__c`.

| `WhenMultipleRows__c` | Behavior |
| ---------------------------- | -------- |
| `OneResult` | Expects one row or one aggregate result. |
| `AnyRowPasses` | Passes when any primary row matches. |
| `AllRowsPass` | Passes when every primary row matches. |
| `CompareAsLists` | Full result treated as a list for list comparators. |

**List membership exception (`ListContainsAny` / `ListDoesNotContainAny`):** the primary scalar comes from `ValueToTest__c` (a formula on the record resolving to the value to test), and the comparison list comes from `CompareToQuery__c` / `CompareToField__c`. `DataQuery__c` is not used, and `PassFailFormula__c` is never read for Query checks. A blank `ValueToTest__c` yields `INVALID_FORMULA`.

### Compare two queries (`CompareTwoQueries`)

Runs `DataQuery__c` and `CompareToQuery__c`.

| Mode | Comparators |
| ---- | ----------- |
| `OneResult` | Scalar comparators (`Equals`, `GreaterThan`, `Contains`, and so on). |
| `CompareAsLists` | `ListsOverlap`, `ListContainsAll`, `ExactListMatch`. |

### Custom Apex (`Apex`)

Instantiates `ApexClass__c`, requires `RecordHealthCheckRule`, passes `RecordHealthCheckContext`. Custom Apex may return `PASS`, `FAIL`, `SKIPPED`, `UNABLE_TO_EVALUATE`, or `ERROR`. Any other status string is rejected with `APEX_EVALUATOR_ERROR`. Only `FAIL` is post-processed for metadata severity and failure message. Plugins may also set `actualValue` and `expectedValue` on the returned result; the engine passes them through unchanged.

**Plugin contract:** Implementations must use `with sharing`, enforce CRUD/FLS on
their own queries, avoid unbounded DML/callouts, and return only a documented
status. `context.record` contains Id plus fields the engine discovered for the
configured formula/query/message; it is not a fully populated record. Parameter
JSON must be an object and should be treated as a versioned, bounded input. The
current public interface supports same-namespace/source deployments; a managed
package intended for subscriber implementations would require a deliberately
versioned `global` contract.

**Shipped example:** `AccountHasRecentActivityCheck` checks closed Tasks and
Events in a look-back window. `daysBack` is bounded to 1-3650 and defaults to 30
when missing, malformed, or outside the range.

## 7. Operators (`Operator__c`)

Setup label: **Operator**. API values below; Setup picklist labels differ (for example `Equals` → **Equals**, `Contains` → **Contains text**, `IsBlank` → **Is empty**).

| Operator (API) | Meaning |
| ---------- | ------- |
| `Equals` | Primary equals comparison value. |
| `NotEquals` | Primary does not equal comparison value. |
| `GreaterThan` | Primary is greater than comparison value. |
| `GreaterThanOrEqual` | Primary is greater than or equal to comparison value. |
| `LessThan` | Primary is less than comparison value. |
| `LessThanOrEqual` | Primary is less than or equal to comparison value. |
| `Contains` | Primary text contains comparison text (**case-sensitive**). |
| `DoesNotContain` | Primary text does not contain comparison text (**case-sensitive**). |
| `IsBlank` | Primary value is blank. |
| `IsNotBlank` | Primary value is not blank. |
| `ListContainsAny` | Comparison list contains the primary scalar value. |
| `ListDoesNotContainAny` | Comparison list does not contain the primary scalar value. |
| `ListsOverlap` | Two lists share at least one value (case-insensitive). |
| `ListContainsAll` | Comparison list contains every value from the primary list (case-insensitive). |
| `ExactListMatch` | Two lists contain the same values and duplicate counts (case-insensitive). |

Ordered comparisons try `Decimal`, then `DateTime`, then `Date`. Incompatible types return `INCOMPATIBLE_COMPARISON_TYPES` rather than silent string sorting.

**Case sensitivity:** `Contains` and `DoesNotContain` are case-sensitive. `Equals` / `NotEquals` use typed comparison when possible; otherwise they compare string forms case-sensitively. List membership and list-mode overlap comparators (`ListContainsAny`, `ListDoesNotContainAny`, `ListsOverlap`, `ListContainsAll`, `ExactListMatch`) compare case-insensitively.

**Display formatting:** On a determinate `PASS` or `FAIL`, Query and CompareTwoQueries evaluators populate `actualValue` and `expectedValue` on the result using `RecordHealthCheckComparatorEngine` helpers (`humanComparator`, `formatValue`, `formatList`, `describeExpected`). `formatValue` wraps **every** non-blank scalar in double quotes (text, number, Boolean, date/time) so mixed-type comparisons read uniformly: e.g. `"1"` beside `at least "2"` instead of bare `1` beside `"2"`. `humanComparator` returns verb phrases for the expected side: e.g. `to equal "Technology"`, `at least "50000"`, `to be one of ["North", "South"]`. Null/blank values render as `(blank)`; empty lists as `(none)`. List previews cap at 10 values with a `(N total)` suffix when truncated. `IsBlank` / `IsNotBlank` show the comparator phrase only (no operand). Formula evaluators route `PassFailFormula__c` through `formatValue` for `expectedValue` (e.g. `"NOT(ISBLANK(BillingCity))"`). The LWC renders these on **non-passing** rows only as labelled **Found** / **Expected** chips (see [15](#15-lwc-behavior)).

## 8. Applicability

| Mode | Contract |
| ---- | -------- |
| `Always` | Rule proceeds to evaluation. |
| `Formula` | `RunWhenFormula__c` must return Boolean `true` to proceed. |
| `SOQL` | `RunWhenCountQuery__c` returns a COUNT; `CountOperator__c` compares it to `CountThreshold__c`. |

## 9. Result Contract (`RecordHealthCheckResult`)

| Field | Purpose |
| ----- | ------- |
| `checkDeveloperName` | Rule key. |
| `label` | User-facing Rule label. |
| `priority` | Display ordering value. |
| `evaluatorType` | `Formula`, `Query`, `CompareTwoQueries`, or `Apex`. |
| `status` | `PASS`, `FAIL`, `SKIPPED`, `UNABLE_TO_EVALUATE`, or `ERROR`. |
| `severity` | Populated for failed checks. |
| `reasonCode` | Machine-readable reason for skipped, unable, or error results. |
| `message` | Safe user-facing message (from `MessageWhenFailed__c` on `FAIL`, or unable/skip text otherwise). |
| `actualValue` | What the record or query produced: the **Found** side in the UI. Populated on a determinate `PASS` or `FAIL` when the evaluator can name a primary value (Query, CompareTwoQueries, Apex when set). Left null for Formula checks. |
| `expectedValue` | The comparator and operand as readable text: the **Expected** side in the UI. Populated on a determinate `PASS` or `FAIL` for Query and CompareTwoQueries; for Formula checks, set to `PassFailFormula__c` (condition text only: no separable record value). Apex plugins may set either field. |
| `detailMessage` | Diagnostic detail (server-side; not `@AuraEnabled`). |
| `adminDetailMessage` | Populated only when `DebugMode__c` is on **and** the user has **`Record_Health_Check_Debug`** (permission set `Record_Health_Check_Admin`). |
| `durationMs` | Evaluator execution time; excludes configuration, dependencies, base-record loading, applicability, and event delivery. |

### Comparison display contract

| Topic | Contract |
| ----- | -------- |
| Metadata | No CMT fields: values are computed at evaluation time from comparator, operand, and query results. |
| UI visibility | The LWC shows **Found** / **Expected** only on resolved **non-passing** rows (`FAIL`) when at least one side is present. Passing rows do not show the block even when values were captured. |
| UI layout | Each side renders as a **labelled chip**: an uppercase caption (`Found` / `Expected`) beside the value in a monospace chip. The two sides **stack vertically** (Found on its own line, then Expected) so layout does not reflow with value length. |
| Screen readers | Both sides are folded into the row `aria-label` when shown (`Found …`, `Expected …`). |
| Formula checks | No separable scalar "found" value: `expectedValue` carries the quoted formula text; `actualValue` stays null; only the Expected side renders. |
| Skipped / unable / error | Neither field is shown: these outcomes have no determinate comparison. |
| Programmatic API | `RecordHealthCheck.run` returns the same fields on `RecordHealthCheckResult`. |

| Status | Contract |
| ------ | -------- |
| `PASS` | Rule evaluated successfully and condition passed. |
| `FAIL` | Rule evaluated successfully and condition failed. |
| `SKIPPED` | Rule did not apply, dependency did not pass, or empty-result behavior chose skip. |
| `UNABLE_TO_EVALUATE` | Rule could not safely evaluate (metadata, data, SOQL, formula, access, or limits). |
| `ERROR` | Unexpected exception after normal validation paths. |

### Definition response (`RecordHealthCheckDefinitionResponse`)

| Field | Purpose |
| ----- | ------- |
| `displayTitle`, `displayDescription` | Header presentation from Check Set. |
| `triggerMode`, `revealMode` | Run and reveal behavior. |
| `successDisplayMode`, `skippedDisplayMode` | Row visibility rules. |
| `stopOnFirstError`, `debugMode` | Run control and diagnostics. |
| `totalAvailableCheckCount` | Active Rules before the 25-check cap. |
| `checksOmittedByLimit` | True when Rules were truncated. |
| `checks` | Ordered `RecordHealthCheckDefinition` list (`developerName`, `label`, `description`, `priority`, `dependsOnCheckDeveloperName`). |

## 10. Reason Codes

| Reason Code | Meaning |
| ----------- | ------- |
| `CONFIG_NOT_FOUND` | Check Set or Rule could not be found. |
| `CONFIG_INACTIVE` | Check Set is inactive. |
| `OBJECT_MISMATCH` | Record object does not match Check Set base object. |
| `NO_RECORD_CONTEXT` | No record Id was provided. |
| `NO_ACTIVE_CHECKS` | Check Set has no active Rules. |
| `INVALID_CONFIG` | Check Set or Rule configuration is invalid. |
| `INVALID_CHECK_TYPE` | Check Method is not recognized. |
| `INVALID_COMPARATOR` | Operator is missing, invalid, or invalid for the Rule shape. |
| `INVALID_FORMULA` | Formula is missing, malformed, or returns the wrong type. |
| `INVALID_SOQL_TEMPLATE` | SOQL is missing, malformed, or unsafe. |
| `MISSING_BIND_VALUE` | SOQL token could not be resolved from the current record. |
| `FIELD_NOT_ACCESSIBLE` | Running user cannot access a required object or field. |
| `RECORD_NOT_ACCESSIBLE` | Current record could not be loaded. |
| `MULTIPLE_ROWS_RETURNED` | A scalar check received multiple rows. |
| `NO_ROWS_RETURNED` | Empty result with `UnableToEvaluate` behavior. |
| `GOVERNOR_LIMIT_RISK` | Query result exceeded configured row safety. |
| `INCOMPATIBLE_COMPARISON_TYPES` | Ordered comparison across incompatible types. |
| `FORMULA_EVAL_LIMIT` | FormulaEval call budget exceeded in the transaction. |
| `APEX_CLASS_NOT_FOUND` | Apex class is missing or does not implement the required interface. |
| `INVALID_APEX_PARAMETERS` | Apex parameter JSON is invalid. |
| `APEX_EVALUATOR_ERROR` | Custom Apex or framework code threw unexpectedly. |
| `APPLICABILITY_NOT_MET` | Applicability returned false or empty-result skip. |
| `DEPENDENCY_NOT_PASSED` | Prerequisite Rule did not pass. |
| `STOPPED_AFTER_ERROR` | Run stopped after a framework error. |
| `DEPENDENCY_NOT_IN_RUN` | LWC only: prerequisite Rule excluded by the 25-check cap. |
| `CIRCULAR_DEPENDENCY` | Circular `RequiresCheck__c` graph; all surfaces return `UNABLE_TO_EVALUATE`. |
| `CLIENT_CALL_FAILED` | LWC `evaluateCheck` Aura call threw before a result was returned. |
| `SETUP_REQUIRED` | Component `configName` is blank. |
| `MISSING_REQUIRED_FIELD` | `RecordHealthCheckMetadataValidator` deployment-time validation. |
| `INVALID_DEPENDENCY` | Validator dependency graph validation. |
| `CHECK_LIMIT_EXCEEDED` | Metadata Validator only: Check Set has more than 25 active Rules; only the first 25 run. |

## 11. SOQL Safety

SOQL templates may use merge tokens on **any readable field** on the base record: standard or custom (API name, including `__c`):

```text
{!Id}
{!Name}
{!Parent.Name}
{!Customer_Tier__c}
{!Primary_Contact__c}
```

Safety contract:

- Token values are escaped or formatted before query execution.
- Date, DateTime, Time, Boolean, and numeric tokens are substituted without quotes; strings and Ids are quoted with `String.escapeSingleQuotes`.
- Multi-select picklist tokens in **unquoted** context on a field the engine can resolve expand semicolon-delimited values to `('A', 'B')` for INCLUDES-style queries (direct fields and relationship paths when the related record is loaded). **Quoted** tokens (`'{!Field}'`) substitute the raw `'A;B;C'` string. When the exact substring `'{!Field}'` appears inside a larger string literal (for example `Name LIKE '{!Name}%'`), that quoted form is replaced first: yielding `Name LIKE 'Acme%'`. A token may also appear both quoted and unquoted in one template; each form is substituted independently (multi-select picklists differ between the two forms).
- Queries run with `WITH USER_MODE` when not already present.
- Unsafe DML keywords and `FOR UPDATE` / `ALL ROWS` are rejected.
- Bare `SELECT COUNT()` is rewritten to `SELECT COUNT(Id)`.
- Non-aggregate queries receive `LIMIT maxRows + 1` when no explicit limit is present (default 2000, overridable via `MaxRows__c`).
- Results exceeding the row cap are rejected with `GOVERNOR_LIMIT_RISK`.

## 12. Message Tokens

Failure and unable-to-evaluate messages may use `{!FieldApiName}` merge tokens. Unresolved tokens are replaced with blank text. A bad message token does not change Rule status.

**Found / Expected is separate from merge tokens.** The engine builds `actualValue` and `expectedValue` automatically for Query and CompareTwoQueries checks (and optionally for Apex). These lines are not authored in metadata and do not need `{!Field}` tokens in `MessageWhenFailed__c` to show what the record produced versus what the rule required: though merge tokens remain useful for narrative context (record name, owner, and so on).

## 13. Programmatic API (`RecordHealthCheck`)

For adoption beyond the record page, `RecordHealthCheck` is the supported Apex entry point. It delegates to the same engine as the LWC. Catchable evaluation failures surface as result statuses (`ERROR`, `UNABLE_TO_EVALUATE`, etc.); uncatchable Apex governor limit exceptions behave like any other Apex API.

### Apex

```apex
RecordHealthCheckResult r = RecordHealthCheck.run(
    'Account_Data_Quality',      // Check Set DeveloperName
    'Account_DQ_BillingCity',    // Rule DeveloperName
    accountId);                  // record under test
```

Optional overload:

```apex
RecordHealthCheck.run(configName, checkName, recordId, 'ticket-12345'); // custom runId
```

| Parameter | Contract |
| --------- | -------- |
| `configName` | Check Set `DeveloperName`: required; scopes the Rule server-side. |
| `checkDeveloperName` | Rule `DeveloperName`: one Rule per call. |
| `recordId` | Record under test. |
| `runId` | Optional correlation id (for example, a ticket or batch-job id) so this run's `[RHC]` log lines group with related work. When blank, the façade generates `api-<timestamp>-<random>`. |

Checks always evaluate with the **running** user's access (`WITH USER_MODE`); to evaluate as another user, run while that user is current or wrap in `System.runAs(thatUser)` in a test.

Each call logs `RUN_INVOKED` and `RUN_COMPLETE` events through `RecordHealthCheckLogger`.

### Flow (not packaged)

There is **no packaged Flow invocable**; it was descoped for governor safety. To call the engine from Flow, build a bulk-designed Apex invocable that groups records and evaluates them within transaction limits, or drive it from scheduled/batch Apex with an intentionally small scope. Do not wrap `run(...)` in a per-record loop.

### Anonymous Apex runner

`scripts/apex/runHealthCheck.apex` loads a Check Set definition and evaluates every Rule in priority order, printing a structured report to the debug log. Set `CONFIG_NAME`, `RECORD_ID`, and optionally `RUN_ID`, then run via `sf apex run --file scripts/apex/runHealthCheck.apex`.

## 14. Logging and Observability

All framework log lines flow through `RecordHealthCheckLogger`: the engine, controller, and evaluators never call `System.debug` directly. The sink can be swapped in one place (for example, Nebula Logger) without touching other classes.

### Structured debug log format

```text
[RHC] <LEVEL> <EVENT> | runId=… user=… config=… check=… record=… <sorted key=value fields>
```

| Concept | Behavior |
| ------- | -------- |
| `runId` | Correlation id: one id is reused for an Automatic definition request and its automatic run; manual reruns receive a fresh id. Callers may supply one to `RecordHealthCheck.run`. Control characters and excessive lengths are removed by the logger. |
| `user` | `UserInfo.getUserId()`: authoritative, not client-supplied. |
| Levels | `ERROR`, `WARN`, `INFO`, `DEBUG` (maps to `FINE` in `System.debug`). |

### Client-side diagnostics (Debug Mode)

Requires **both** `DebugMode__c` on the Check Set **and** `Record_Health_Check_Debug` on the running user (included in permission set `Record_Health_Check_Admin`). See [Debug Mode guide](../guides/debug-mode.md).

When enabled, after a run completes the LWC:

- Renders a compact per-row debug-meta line under each result.
- Shows expandable **Debug detail** (`adminDetailMessage`) on errors.
- Shows footnote: **Check console (F12) for diagnostics.**
- Logs to the browser console: `[RHC] Health Check run …` with full run JSON and `console.table` of per-check results.

## 15. LWC Behavior

The `recordHealthCheck` bundle (`recordHealthCheck.js`, `healthCheckRunner.js`,
`healthCheckModel.js`, `healthCheckPresentation.js`) orchestrates definition load,
run lifecycle, and display. Presentation logic that LWC templates cannot express
lives in `healthCheckPresentation.js`.

### Lifecycle and run control

- Loads definitions once when inserted (deferred one macrotask so Automatic does not fire during initial mount).
- Reloads definitions when `recordId` or `configName` changes after the initial connect. On reload, invalidates any in-flight run (`_runToken` bump, run-state reset) so stale results cannot bleed across records (H1).
- Runs automatically for `Automatic` Check Sets; shows **Run** for `Manual`.
- Shows **Rerun** after any run completes (including Automatic). While a run is in flight the action button stays visible, is **disabled**, keeps **Run** on the first run or **Rerun** on later runs (see `hasCompletedRunOnce` below), and shows a **spinner** in place of the play glyph (it does not disappear or relabel to "Running…").
- Runs at most **5** `evaluateCheck` calls concurrently when `StopOnSystemError__c` is false; runs **sequentially** when `StopOnSystemError__c` is true.
- Reveals rows in priority order via a drain buffer.
- Enforces `RequiresCheck__c` client-side before calling Apex.
- Pre-seeds circular dependencies as `UNABLE_TO_EVALUATE` / `CIRCULAR_DEPENDENCY` without calling Apex.
- Discards stale results from prior runs via `_runToken`.
- Stores runtime state only in the component instance.

**Run-state flags (regression guard)**

| Flag | Set `true` when | Cleared when | Drives |
| ---- | --------------- | ------------ | ------ |
| `runComplete` | All checks in the current run have been revealed | A new run starts (`healthCheckRunner.run`) or definitions reload | Summary bar visibility, pre-run hint, debug diagnostics, `showRerunButton` |
| `hasCompletedRunOnce` | A run finishes (including zero-check sets) | Definitions reload (`recordId` / `configName` change) | Action button **visible label** (`Run` vs `Rerun`) and busy `title` / `aria-label` while a run is in flight |

`runComplete` clears at the start of every run so the summary bar hides during evaluation. **`hasCompletedRunOnce` must not clear when a re-run starts**: otherwise the button relabels to **Run** + spinner instead of **Rerun** + spinner.

**Not supported today:** automatic re-run on record save.

### Card chrome and header

- Renders as a custom card (`rhc-card`) with a visible border and elevation: not `slds-card`: so it reads as a contained panel on white Lightning tabs.
- **Rounded corners** match standard Lightning cards: `border-radius: var(--lwc-borderRadiusMedium, 0.25rem)`. The card uses **`overflow: visible`** so row and summary tooltips are **not clipped** at the card boundary (especially the last row's below-row bubble). Bottom corner rounding is applied to **`.rhc-body > :last-child`** so the outline still matches standard Lightning related lists and record panels without trapping popovers.
- **No header icon**: the card does not render a header icon. There is no icon field on the Check Set; titles are text-only.
- Header layout: **title** and **action button** share one row (vertically centered); **Display Description** spans the full width on the row beneath (eliminates a tall empty column beside a short button).
- Shows a **First 25 shown** badge when `checksOmittedByLimit` is true (does not show `totalAvailableCheckCount`).

### Row status accent

- Each resolved row carries a **3px-wide status accent** on the left edge, coloured by outcome (pass / fail / warning / info / skipped / unable).
- The accent is a dedicated **`.rhc-row__accent` element** (`position: absolute; left: 0; top: 0; bottom: 0; width: 3px`) so it spans the full row height flush to the card's left inner edge and renders reliably in LWC shadow DOM. Do **not** use `border-left`, inset `box-shadow`, or row `::before` for the accent: tooltip nubbins on described rows use `::before`.

### Action button

Native SLDS neutral button (`.rhc-action-button`, `slds-button_neutral`): **not** `lightning-button` (SVG play icon was unreliable in the target context).

**Visible label (regression guard)**

- The visible label is **only** `Run` (before the first completed run) or `Rerun` (after any run has completed). **Do not** relabel to `Running…`, `Running`, or any other in-flight text: that widened the button and left empty padding on `Run` / `Rerun`.
- The label **does not change when a run starts**: first run stays **Run** + spinner; subsequent runs stay **Rerun** + spinner (`hasCompletedRunOnce`: not `runComplete`, which clears during the run).
- Check count lives in `title` and in `aria-label` while busy (e.g. `Run 18 Checks`, `Running 18 Checks`, `Re-running 18 Checks`): not in the visible label.

**In-flight / busy state**

- Button **stays visible** and **disabled** for the whole run (Manual and Automatic).
- **CSS spinner** (`.rhc-action-button__spinner`) replaces the play glyph (`.rhc-action-button__play`) inside a fixed **`.rhc-action-button__glyph`** slot (`0.75rem`); do not show both at once.
- Set **`aria-busy="true"`** while a run is in flight; `aria-label` carries the busy phrase for screen readers.
- **Do not** hide the button during a run: that was the pre-June-2026 behavior this iteration replaced.

**Width and layout (regression guard)**

- **`min-width: 5rem`** with tighter horizontal padding: sized for **Rerun** + a fixed **0.75rem** glyph slot (`.rhc-action-button__glyph`) so `Run` and `Rerun` share the same compact footprint and the label **does not shift** when the play icon swaps to the spinner.
- **Do not** size `min-width` for a longer label such as `Running…` (the old `7rem` value).
- Fixed width prevents the card title from reflowing between one and two lines as the button state changes.

**Play glyph**

- CSS-drawn triangle (▶) after the label when idle: always renders and greys with disabled text when the button is disabled for other reasons.

### Pre-run hint

Before the first Manual run (both `OneAtATime` and `AllAtOnce`), shows one line:

> Click **Run** to evaluate this record against {count phrase}.

`{count phrase}` is pluralized (`1 check` / `18 checks`) or, when `checksOmittedByLimit` is true, **the first 25 checks**.

### Rows

- Renders each row's `Tooltip__c` as a hover/focus tooltip (`data-tooltip` on the `<li>`) when a description exists: **never inline**. Tooltip anchor classes are omitted when description is blank. Description is folded into `accessibleLabel` for screen readers.
- Row tooltip layout and nubbin behavior are defined in [Tooltips](#tooltips) below.
- Row status icons are **CSS-drawn** circles (`rhc-status-icon--*`): not `lightning-icon`.
- Always renders `FAIL` (Error), `Warning`, `Info`, and `UNABLE_TO_EVALUATE` outcomes as full rows: these are actionable and are never collapsed into the summary bar. Only `PASS` and `SKIPPED` outcomes can be collapsed (via `PassedChecksDisplay__c` / `SkippedChecksDisplay__c`).
- Applies `PassedChecksDisplay__c` and `SkippedChecksDisplay__c`: rows in `Hide` mode are filtered from the list even when `RowAppearance__c` is `AllAtOnce`.
- On resolved **non-passing** rows, shows a **Found** / **Expected** comparison block beneath `MessageWhenFailed__c` when the evaluator populated `actualValue` and/or `expectedValue`: rendered as stacked labelled chips (see [9](#comparison-display-contract)). Example: Found `"Cold"` on one line; Expected `does not equal "Cold"` on the next. Formula failures show Expected only (quoted formula text). Not shown on `PASS`, `SKIPPED`, `UNABLE_TO_EVALUATE`, or `ERROR`.
- Shows `adminDetailMessage`, per-row debug-meta, and console footnote when `DebugMode__c` is on **and** the user has `Record_Health_Check_Debug` (see [Debug Mode guide](../guides/debug-mode.md)).

### Summary bar

- After run completion, renders a single **summary bar** of per-outcome pills (`Passed`, `Failed`, `Warning`, `Info`, `Skipped`, `Unable`) when at least one bucket is non-zero.
- Each pill uses the **same CSS status icon** as rows (`rhc-status-icon--*`) for visual consistency (e.g. Unable = `?`, Skipped = `-`).
- Each pill is a hover/focus tooltip target; tooltip text is `{label}: {comma-separated rule labels}` (e.g. `2 Warnings: Website Uses HTTPS, Has at Least Two Contacts`). **Warning** pluralizes (`1 Warning` vs `2 Warnings`).
- Summary-pill tooltip layout and nubbin behavior are defined in [Tooltips](#tooltips) below.
- Replaces the removed standalone "N rules passed" / "N rules were skipped" footer notes. Rows hidden by `Hide` still contribute to their pill counts.

### Tooltips

CSS-drawn hover/focus popovers (`rhc-tooltip-anchor` + `::before` / `::after`). **Do not** switch to `lightning-helptext` or inline description text: the compact-row contract depends on this mechanism.

**Shared surface and interaction**

- Light-gray popover (`neutral-base-95`) with `border-base-3` edge, drop shadow, and `z-index: 100` (nubbin `101`) so bubbles layer above the card and adjacent page chrome.
- Trigger on **`:hover`** and **`:focus-visible`** only: **not** plain `:focus` (avoids a mouse-clicked row pinning its tooltip while hovering another).
- **Dwell delay:** **500ms** after the pointer rests before show; **150ms** on keyboard `:focus-visible`. Hide immediately when hover/focus leaves.

**Non-clipping (regression guard)**

- **Do not** set `overflow: hidden` on `.rhc-card` to "tidy" corners. That clips the last row's below-row tooltip and summary tooltips at the card edge.
- Card bottom rounding comes from **`.rhc-body > :last-child`**, not from trapping overflow on the card shell.

**Row tooltips** (`rhc-tooltip-anchor--row` on the `<li>`)

- Bubble appears **below** the row (`top: calc(100% + 0.5rem)`), pinned `left: 1rem; right: 1rem` so it spans the card width and wraps at any column width.
- **Upward nubbin** (`::before`): bordered square rotated 45°, pointing at the row. Row accent must remain a **`.rhc-row__accent` element**: not `::before` on the row.

**Summary-pill tooltips** (`.rhc-summary-pill` grid wrapper + `.rhc-tooltip-anchor--footer` on the pill `<span>`)

- Bubble appears **above** the stats bar (`bottom: 100%` on `.rhc-stats-bar`), pinned **`left: 1rem; right: 1rem`**: **same width and wrap behavior as row tooltips**.
- Pill anchor and `.rhc-summary-pill` wrapper must stay **`position: static`** so the bubble's containing block is `.rhc-stats-bar`, not the small pill. **Do not** wrap pills in `position: relative`: that squeezes `left/right` insets to pill width and produces a tall, narrow tooltip.
- **Downward nubbin** is **`.rhc-stat__nubbin`** inside **`.rhc-stat__nubbin-host`**: a **grid sibling** of the footer anchor (not an ancestor). Host is `position: relative` and pill-sized; footer anchor stays `position: static`. Nubbin sits at `bottom: calc(100% + 0.25rem)` on the host so it **meets the bubble bottom** (same 0.25rem / 0.5rem spacing as row tooltips). **Do not** place the nubbin on the pill top or detach it from the bubble.
- **Do not** center a `max-content` bubble on the pill with a very large `max-width`: that produces an unreadably wide one-line tooltip.

### Diagnostics (debug mode)

Requires `Record_Health_Check_Debug` plus **Debug Mode** on the Check Set. Per-row debug lines, **Debug detail** on errors, console footnote, and `[RHC]` browser console summary after run completion. See [Debug Mode guide](../guides/debug-mode.md).
- Error banner (setup/load failures) still uses `lightning-icon`.

### Component design property

| Property | Type | Purpose |
| -------- | ---- | ------- |
| `configName` | String | `DeveloperName` of the `Record_Health_Check_Set__mdt` record to run. Set in Lightning App Builder on the record page. |

## 16. Validation Rules

`RecordHealthCheckMetadataValidator` (deploy-time) and `RecordHealthCheckConfigService` (runtime) validate overlapping rules. Both alias valid-value sets from `RecordHealthCheckConstants`. The validator is a CI and Anonymous Apex utility; there is no Setup UI wired to it yet.

Both validate Check Set modes, objects/icons, Rule shape and required fields,
severity/source/handling values, scalar applicability COUNT shape and threshold,
query output fields, plugin class/interface/JSON, row caps, and dependencies. The
deploy-time validator warns when the first-25 cap omits rules or prerequisites and
exposes structured JSON through `validateAsJson()` for CI.

Validation must catch: missing required fields, unknown modes and Check Methods, invalid Operator / **If Query Returns Multiple Rows** combinations, invalid **If Query Returns Zero Rows** values, invalid Apex JSON, missing or cyclic dependencies, and row safety values outside framework caps.

## 17. Deployment Contents

- Apex classes and interfaces (including `RecordHealthCheck` façade, `RecordHealthCheckLogger`, `RecordHealthCheckConstants`, `RecordHealthCheckSoqlTemplate`, `RecordHealthCheckValueResolver`)
- Lightning Web Component
- Custom Metadata Type definitions and fields
- Sample Custom Metadata records (10 Check Sets, 88 Rules)
- Layout metadata for Custom Metadata editing
- Permission sets: `Record_Health_Check_User`, `Record_Health_Check_Admin`
- Documentation and anonymous Apex runner script

Deploy via `force-app` or `manifest/package.xml`.

## 18. Default Behavior Summary

| Field | CMT default | Runtime when blank on Rule |
| ----- | ----------- | -------------------------- |
| `WhenValueIsEmpty__c` | `SkipRecordsWithMissingValue` | Same: blank aligns with skip-on-null for row comparisons. |
| `WhenZeroRows__c` | `Skip` | Same: blank resolves to `Skip`. |

For `AnyRowPasses`, `AllRowsPass`, and `CompareAsLists`, set `WhenZeroRows__c` explicitly so intent is visible in metadata.

## 19. Resolved Issues (formerly 18)

These items were previously tracked as known bugs and are **fixed** in the current codebase:

| ID | Resolution |
| -- | ---------- |
| B1 | Blank `WhenValueIsEmpty__c` aligns with CMT default (`SkipRecordsWithMissingValue`). |
| B2 | Server-side `RequiresCheck__c` gate in `RecordHealthCheckEngine` (prerequisite re-evaluation can duplicate work; see [20](#20-open-limitations-and-edge-cases)). |
| B3 | `getCheckDefinitions` is no longer cacheable. |
| B4 | `RunChecksWhen__c` and `RowAppearance__c` validated at definition load in Config Service and Metadata Validator. |
| B5 | LWC `_runToken` discards stale in-flight results on rerun; `_loadDefinitions` resets run state on `recordId` change (H1). |
| B6 | `RecordHealthCheckConstants` centralizes valid-value sets and caps. |
| B7 | Applicability sub-fields validated at runtime and deploy-time. |
| B8 | `RecordHealthCheckSoqlTemplate` + `RecordHealthCheckValueResolver` extracted; all query paths (single-query, dual-query, applicability) wired. |
| B9 | Ordered comparisons use typed coercion; no string-sort fallback. |
| B10 | List membership and list-mode overlap comparators are case-insensitive (`Contains` / `DoesNotContain` remain case-sensitive). |
| B11 | Named aggregate aliases supported via `getPopulatedFieldsAsMap`. |
| B12 | Documentation uses `AccountHasRecentActivityCheck`. |
| B13 | LWC Automatic concurrency capped at 5 simultaneous `evaluateCheck` calls; queue for the rest. |
| B14 | Debug details gated by `Record_Health_Check_Debug` Custom Permission in Apex (`RecordHealthCheckAccess`). |
| B15 | Null `recordId` on evaluate path returns `NO_RECORD_CONTEXT`. |
| B17 | Manual mode shows pre-run guidance before the first run in **both** reveal modes (`showPreRunHint`). |
| B18 | Non-passing rows show **Found** / **Expected** labelled chips from `actualValue` / `expectedValue`; Formula checks show Expected (quoted formula text) only. |
| B19 | Row and summary-pill status icons are CSS-drawn (`rhc-status-icon--*`): not `lightning-icon`: for reliable rendering. |
| B20 | Summary pills list rule labels in hover/focus tooltips; standalone per-status footer notes removed. |
| B21 | Rule descriptions are tooltip-only (never inline); tooltips use `:focus-visible` to avoid double-tooltip on mouse click. |
| B22 | Action button stays visible during runs (disabled, spinner, label unchanged); label driven by **`hasCompletedRunOnce`**; busy text in `title` / `aria-label`. |
| B23 | `formatValue` quotes all non-blank scalars uniformly (numbers, Booleans, dates included). |
| B24 | LWC header icon removed; the icon field was dropped from the schema and the Apex definition response (no `IconName__c` / `iconName` exists today). |
| B25 | `PassedChecksDisplay__c` / `SkippedChecksDisplay__c`: `Hide` collapses rows from the list but still populates summary pills after run completion. |
| B26 | Card uses `--lwc-borderRadiusMedium` rounded corners; **`overflow: visible`** on the card shell with bottom radius on `.rhc-body > :last-child` so tooltips are not clipped. |
| B27 | Row status accent is a full-height `.rhc-row__accent` element flush to the left edge: not `border-left`, `box-shadow`, or row `::before`. |
| B28 | Row/summary tooltips wait **500ms** on mouse hover before showing; **150ms** on `:focus-visible`; hide immediately on leave. |
| B29 | Summary-pill tooltips span the stats bar (`left/right: 1rem`, same as rows); nubbin is `.rhc-stat__nubbin` in `.rhc-stat__nubbin-host` (grid sibling of footer anchor). |
| B30 | Tooltips use `z-index: 100+` and must remain fully visible outside the card boundary (no `overflow: hidden` on `.rhc-card`). |
| B31 | Action button visible label is **only** `Run` or `Rerun`: never `Running…`; in-flight busy state is **spinner + `aria-busy`**, with busy text in `title` / `aria-label`. Label tracks **`hasCompletedRunOnce`** so a re-run stays **Rerun** while in flight. |
| B32 | Action button `min-width` is **5rem** with a fixed **0.75rem** glyph slot: label must not shift when play swaps to spinner. |
| B33 | Summary-pill tooltip bubble must **wrap** at card width: never a narrow pill-width column (`position: relative` wrapper between anchor and stats bar). |
| B34 | Summary-pill nubbin must **attach to the tooltip bubble bottom** (`.rhc-stat__nubbin-host` sibling pattern): never float above the pill detached from the bubble. |

## 20. Open Limitations and Edge Cases

| Area | Behavior | Mitigation |
| ---- | -------- | ---------- |
| FormulaEval budget | Platform limit 100 calls/transaction; framework throws at 95 when the transaction-wide counter is reached. A single Rule can use multiple calls. | Prefer SOQL checks; keep formula-heavy Rules sparse per Check Set; avoid many formula checks in one Flow/batch transaction. |
| Declared scalar formula return type | `ScalarFormulaReturnType__c` (Auto default): when set, declares a comparison/value-to-test formula's return type so it resolves in **one** FormulaEval call instead of probing up to eight. The declared type is **trusted**: if it is wrong but the platform still coerces the formula to that type (e.g. declaring `Text` for a numeric formula yields the string `"1000"` rather than the number `1000`), the resolved value's type changes and ordered comparisons (`GreaterThan`, etc.) may switch to lexical semantics. A declared type that the platform **rejects** degrades safely back to the full probe. | Leave as `Auto` unless the formula's return type is known; set it only to the formula's actual type. Auto always resolves correctly: it only costs more FormulaEval calls. |
| Server dependency cost | Within one Apex transaction the engine memoizes prerequisite results in a static cache keyed by config + record + check. The LWC still evaluates each Rule in its own transaction, so a prerequisite may run twice (once as its own row, once when a dependent calls the server). | Accept cost for safety on the record-page path; direct Apex chains benefit from memoization. |
| Same-transaction re-evaluation | Dependency memoization cache is **cleared after each top-level** `evaluate()` / `run()`. A second call in the same Apex transaction reloads the record and re-evaluates. Memoization applies only **within** one evaluation when resolving `RequiresCheck__c` chains. | Safe for Flow/batch loops that call `run()` after DML; do not rely on cross-call memoization. |
| SOQL tokens inside partial literals | The exact substring `'{!Field}'` inside a larger literal is substituted (for example `Name LIKE '{!Name}%'` → `Name LIKE 'Acme%'`). Exotic nesting (multiple tokens in one literal, escaped quotes) is untested. | Prefer standalone `'{!Field}'` or unquoted `{!Field}` tokens; test wildcard patterns on representative data. |
| `WITH SYSTEM_MODE` in Rule SOQL templates | Rejected at **any** parenthesis depth before execution; framework queries run `WITH USER_MODE`. | Do not embed elevated access in Check Set templates. |
| Dual-query list null semantics | Under `MissingMeansNoMatch`, null list values use distinct internal sentinels (nulls do not match each other). All-null rows with `SkipRecordsWithMissingValue` → **SKIPPED**. CompareAsLists still applies `WhenZeroRows__c` when either side has **zero rows**, without distinguishing which side was empty. | Use applicability SOQL when only one side being empty should change the outcome. |
| Aggregate alias validation | Deploy-time validation allows a blank query field when any aggregate exists; runtime may require an explicit alias. | Set `FieldToRead__c` / `CompareToField__c` to the aggregate alias for every non-`COUNT()` expression. |
| Semicolon-only multi-select bind | A multi-select value of `;` only (or segments that trim to empty) can bind to invalid `INCLUDES ()` SOQL. | Ensure picklist values are non-blank; avoid binding empty multi-select fields in unquoted token context. |
| Query / formula access errors (i18n) | `FIELD_NOT_ACCESSIBLE` vs `INVALID_SOQL_TEMPLATE` / `INVALID_FORMULA` is inferred from **English** substrings in platform exception messages. | Non-English orgs may see generic reason codes; test in target locales. |
| Scalar vs list case sensitivity | Scalar `Contains` / `DoesNotContain` are **case-sensitive**; list comparators (`ListContainsAny`, dual list modes) normalize to lowercase. | Match casing in static values or use list comparators for case-insensitive membership. |
| DateTime token / comparison timezone | Ordered DateTime coercion treats values ending in `Z` as GMT; other strings use `Datetime.valueOf` (org/user context). Cross-type `Date` vs `DateTime` equality may not align. | Use consistent types; test with org timezone. |
| Apex recent-activity Events | `AccountHasRecentActivityCheck` filters Events on **`ActivityDate`**, not `StartDateTime`: timed events can appear active when start time is before the cutoff. | Tune `daysBack` or implement a custom check using `StartDateTime` if needed. |
| Flow/batch governor pressure | Each `RecordHealthCheck.run` or Flow input row is a full engine evaluation (record load + evaluator). Bulk flows multiply SOQL/FormulaEval cost. | Keep batch sizes small; prefer targeted Rules; monitor debug logs. |
| Multi-select picklist tokens | Unquoted `{!Field}` on a resolved multi-select expands to `('A', 'B')`; quoted `'{!Field}'` keeps `'A;B;C'`. Relationship paths behave the same when the related record is loaded. | Use direct field tokens when possible; ensure relationship fields are collected by the engine. |
| 25-check cap | Dependents skip with `DEPENDENCY_NOT_IN_RUN` if prerequisite is omitted. UI shows “First 25 shown” without the pre-cap total. Deploy-time validator emits `CHECK_LIMIT_EXCEEDED` WARNING when a Check Set has more than 25 active Rules and warns when a dependency target is outside the first-25 window. | Keep Check Sets ≤ 25 active Rules or raise priority of prerequisites. |
| Stop on first error | Only `ERROR` stops the run; `FAIL` and `UNABLE_TO_EVALUATE` do not. Enables sequential execution. | Document intent; use dependencies if sequencing matters. |
| Validator gaps | Metadata Validator does not reject blank `PanelHeading__c` at **runtime** (only at deploy-time). Apex class validation uses `Type.forName` at deploy/validate time. | Run `validateAsJson()` in CI plus manual review; test on representative records. |
| Static comparison values | `FixedValue__c` is untyped text. | Use simple literals; normalize in SOQL or Apex for locale-specific formats. |
| Blank `PanelHeading__c` at runtime | Required in CMT field metadata and caught by the validator, but **not** rejected by `getDefinitionResponse` if blank. | Always set Display Title before activation. |
| Record save | No automatic re-run after inline edit. | User clicks **Rerun** or refreshes the page. |
| Component placement | Record-page only (`lightning__RecordPage`). | Use `RecordHealthCheck.run` or Flow for non-record-page automation. |
| `checksOmittedByLimit` not logged | UI shows the badge but the framework does not emit a WARN log when Rules are truncated. | Review Check Set active Rule count during configuration. |
