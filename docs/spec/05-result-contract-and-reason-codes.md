> [!NOTE]
> **Canonical source:** Section numbers and anchors in the [full design specification](../reference/record-health-check-design-spec.md) are stable for cross-links.

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
| `actualValue` | What the record or query produced: the **Found** side in the UI. Populated on a determinate `PASS` or `FAIL` when the evaluator can name a primary value (Query, CompareTwoQueries, Apex when set). Left null for Formula checks unless `FoundValueFormula__c` is configured (then it carries that scalar). |
| `expectedValue` | The comparator and operand as readable text: the **Expected** side in the UI. Populated on a determinate `PASS` or `FAIL` for Query and CompareTwoQueries; for Formula checks, set to the resolved `ExpectedValueFormula__c` scalar when configured, otherwise to the quoted `PassFailFormula__c` condition text. Apex plugins may set either field. |
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
| Formula checks | By default no separable scalar "found" value: `expectedValue` carries the quoted formula text, `actualValue` stays null, only the Expected side renders. Optional `FoundValueFormula__c` / `ExpectedValueFormula__c` (display-only scalars) populate the two sides for balance/comparison checks; pass/fail is still decided solely by the Boolean `PassFailFormula__c`, and an unresolvable display formula falls back to the default. |
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
