> [!NOTE]
> **Canonical source:** Section numbers and anchors in the [full design specification](../reference/record-health-check-design-spec.md) are stable for cross-links.

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

**Display formatting:** On a determinate `PASS` or `FAIL`, Query and CompareTwoQueries evaluators populate `actualValue` and `expectedValue` on the result using `RecordHealthCheckComparatorEngine` helpers (`humanComparator`, `formatValue`, `formatList`, `describeExpected`). `formatValue` wraps **every** non-blank scalar in double quotes (text, number, Boolean, date/time) so mixed-type comparisons read uniformly: e.g. `"1"` beside `at least "2"` instead of bare `1` beside `"2"`. `humanComparator` returns verb phrases for the expected side: e.g. `to equal "Technology"`, `at least "50000"`, `to be one of ["North", "South"]`. Null/blank values render as `(blank)`; empty lists as `(none)`. List previews cap at 10 values with a `(N total)` suffix when truncated. `IsBlank` / `IsNotBlank` show the comparator phrase only (no operand). Formula evaluators route `PassFailFormula__c` through `formatValue` for `expectedValue` (e.g. `"NOT(ISBLANK(BillingCity))"`). The LWC renders these on **non-passing** rows only as labelled **Found** / **Expected** chips (see [15](09-lwc-behavior.md#15-lwc-behavior)).

## 8. Applicability

| Mode | Contract |
| ---- | -------- |
| `Always` | Rule proceeds to evaluation. |
| `Formula` | `RunWhenFormula__c` must return Boolean `true` to proceed. |
| `SOQL` | `RunWhenCountQuery__c` returns a COUNT; `CountOperator__c` compares it to `CountThreshold__c`. |
