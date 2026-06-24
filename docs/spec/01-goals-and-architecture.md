> [!NOTE]
> **Canonical source:** Section numbers and anchors in the [full design specification](../reference/record-health-check-design-spec.md) are stable for cross-links.

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

- **Full result history on the record page.** The LWC does not show past runs; nothing is persisted (see [14](08-logging-and-observability.md#14-logging-and-observability)).
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
