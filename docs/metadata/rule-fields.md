# Rule fields (`Record_Health_Check_Rule__mdt`)

One individual check inside a Check Set. Walkthroughs by Check Method: [Configuration Guide: result meanings through Apex rules](../guides/configuration-guide.md#5-result-meanings).

> [!NOTE]
> This reference is the source of truth for Rule fields. Guides and examples link here rather than restating these values.

## Field reference

Fields below apply to **all** Rules unless marked otherwise.

### Identity, order, and presentation

| Setup label | API name | Type | Required | Description |
| ----------- | -------- | ---- | -------- | ----------- |
| Developer Name | `DeveloperName` | Text | Yes | Stable API identifier (for example, `Account_DQ_BillingCity`). Referenced by **Depends On Check** and Apex evaluation. |
| Label | Master Label | Text | Yes | Setup list name. Convention: spaces instead of underscores. Internal metadata identity. |
| Check Set | `Record_Health_Check_Set__c` | Metadata relationship | Yes | Parent Check Set. Scopes the Rule to one object and one component configuration. |
| Priority | `RunOrder__c` | Number | Yes | Run and display order (lower first). Use increments of 10. Controls sequence and dependency ordering. |
| Active | `IsActive__c` | Checkbox | No | Include Rule in evaluation when checked. Defaults to checked. Disable without deleting. |
| Check Name | `CheckName__c` | Text | Yes | User-facing row title in the component (for example, `Billing City Present`). |
| Description | `Tooltip__c` | Text | No | Help text shown as a hover/focus tooltip on the row (not inline under the label). Announced to screen readers via the row accessible name. |

> [!NOTE]
> **Two Label fields:** Setup shows **Label** (Master Label) on the record header and **Check Name** (`CheckName__c`) in the rule details. Master Label is the metadata list name in Setup; `CheckName__c` is what appears on the record page.

### Check Method and messages

| Setup label | API name | Type | Required | Description |
| ----------- | -------- | ---- | -------- | ----------- |
| Check Method | `CheckMethod__c` | Picklist | Yes | **Record formula** (`Formula`), **Single query** (`Query`), **Compare two queries** (`CompareTwoQueries`), or **Custom Apex** (`Apex`). Chooses evaluator and which fields below are required. |
| Severity | `Severity__c` | Picklist | Yes | `Error`, `Warning`, or `Info`: **only when the Rule fails**. Visual weight of failures; does not affect pass/fail logic. |
| Message When Failed | `MessageWhenFailed__c` | Text | Yes | User message on failure. Supports `{!Field}` tokens. |
| Message When It Can't Run | `MessageWhenCannotRun__c` | Text | No | Overrides default unable-to-evaluate text when SOQL or permissions block the check. |

**Found / Expected (automatic, not a metadata field):** When a Query or Compare Two Queries check fails, the card also shows what the record produced (**Found**) and what the rule required (**Expected**) as stacked labelled chips beneath **Message When Failed**: for example Found `"Cold"` and Expected `does not equal "Cold"`. Values are quoted uniformly (numbers included). These lines are not configurable; the engine derives them from the comparator and comparison value. Formula failures show **Expected** only (quoted formula text). Skipped, unable, and error rows do not show comparison. See [Design Specification: comparison display](../reference/record-health-check-design-spec.md#comparison-display-contract) and [Examples: seeing Found / Expected](../examples/index.md#seeing-found--expected-on-a-failing-check).

### Dependencies

| Setup label | API name | Type | Required | Description |
| ----------- | -------- | ---- | -------- | ----------- |
| Depends On Check | `RequiresCheck__c` | Text | No | `DeveloperName` of a prerequisite Rule in the **same** Check Set. Run this Rule only after another returns `PASS`. Prerequisite must have lower **Priority**. Enforced in the LWC before each Apex call and again on the server. Circular dependencies show as `ERROR` in the LWC and `UNABLE_TO_EVALUATE` on direct Apex evaluation. |

### Applicability (all Rules)

Applicability runs **before** the evaluator. If the gate is false, the Rule is `SKIPPED` and the evaluator does not run.

| Setup label | API name | Type | Required | Description |
| ----------- | -------- | ---- | -------- | ----------- |
| Run This Check When | `RunThisCheckWhen__c` | Picklist | Yes | `Always`, `Formula`, or `SOQL`. Skip checks that do not apply to this record. |
| Applicability Formula | `RunWhenFormula__c` | Text | When mode = Formula | Boolean formula; `true` = run the check. On-record gate without SOQL. |
| Applicability SOQL | `RunWhenCountQuery__c` | Text | When mode = SOQL | COUNT query; use `SELECT COUNT()` or `SELECT COUNT(Id)` with **no alias**. Gate based on related data. |
| Applicability Count Comparison | `CountOperator__c` | Picklist | When mode = SOQL | Setup labels: Equals, Does not equal, Greater than, Greater than or equal, Less than, Less than or equal. Compare COUNT to threshold. |
| Applicability Comparison Value | `CountThreshold__c` | Number | When mode = SOQL | Whole number (for example, `0`). Threshold for the gate. |

### Formula Rules (`CheckMethod__c` = Formula)

| Setup label | API name | Type | Required | Description |
| ----------- | -------- | ---- | -------- | ----------- |
| Formula | `PassFailFormula__c` | Text | Yes | Boolean Salesforce formula. `true` = pass, `false` = fail. Record formula checks only: list membership Query checks use **Value To Test**. |

### Query and Compare Two Queries Rules

| Setup label | API name | Type | Required | Description |
| ----------- | -------- | ---- | -------- | ----------- |
| Primary Query | `DataQuery__c` | Text | Yes* | SOQL template with `{!Id}` tokens. Retrieves values to evaluate. *Exception: `ListContainsAny` / `ListDoesNotContainAny` use **Value To Test** as the primary scalar instead. |
| Primary Query Field | `FieldToRead__c` | Text | When query returns field values | Field or aggregate alias from Primary Query. Omit for bare `COUNT()`. |
| Value To Test | `ValueToTest__c` | Text | `ListContainsAny` / `ListDoesNotContainAny` | Formula returning the scalar value to test, e.g. `BillingCountry`. Primary scalar for single-query list membership checks. |
| Comparison Query | `CompareToQuery__c` | Text | CompareTwoQueries; or Query with `AnotherQuery` | Second SOQL template. Second data source. |
| Comparison Query Field | `CompareToField__c` | Text | When comparison query returns field values | Field or alias from Comparison Query. |
| If Query Returns Multiple Rows | `WhenMultipleRows__c` | Picklist | Yes for Single query | Setup labels: One result (or aggregate), At least one row must pass, Every row must pass, Compare as two lists. API: `OneResult`, `AnyRowPasses`, `AllRowsPass`, `CompareAsLists`. How multi-row results are interpreted. |
| Operator | `Operator__c` | Picklist | Yes | Comparison operator (see [Design Specification: operators](../reference/record-health-check-design-spec.md#7-operators-operator__c)). |
| Compare Against | `CompareAgainst__c` | Picklist | When the Operator needs a right-hand side | Setup labels: A fixed value, A formula on the record, Another query. Not used for Is empty / Is not empty. |
| Comparison Value | `FixedValue__c` | Text | When source = FixedValue | Literal (for example, `0`, `Approved`). Fixed threshold. |
| Comparison Formula | `RecordFormulaValue__c` | Text | When source = RecordFormula | Formula on the base record. Per-record threshold. |
| If Query Returns Zero Rows | `WhenZeroRows__c` | Picklist | Required for Any/All/CompareAsLists | Setup labels: Treat as passed, Treat as failed, Mark as skipped, Mark as can't run. Default and blank runtime behavior: Mark as skipped (`Skip`). |
| If A Value Is Empty | `WhenValueIsEmpty__c` | Picklist | Recommended for row comparisons | Setup labels: Ignore rows with empty values, Treat empty as blank, Empty never matches. Default: Ignore rows with empty values (`SkipRecordsWithMissingValue`). How nulls behave row-by-row. |
| Max Rows Override | `MaxRows__c` | Number | No | 1-2000; lowers default 2000 row cap. Cannot exceed 2000. Tighter safety on broad queries. |

> [!IMPORTANT]
> **Null vs empty rows:** **`WhenZeroRows__c`** applies when a query returns **no rows** (or, for CompareTwoQueries OneResult, when either side's query is empty). When rows exist but a field under test is null and the comparator cannot decide (typically **`SkipRecordsWithMissingValue`**), the check is **SKIPPED** with reason `VALUE_IS_EMPTY`: governed by **`WhenValueIsEmpty__c`**, not `WhenZeroRows__c`. See [Design Specification: open limitations](../reference/record-health-check-design-spec.md#20-open-limitations-and-edge-cases).

### Apex Rules (`CheckMethod__c` = Apex)

| Setup label | API name | Type | Required | Description |
| ----------- | -------- | ---- | -------- | ----------- |
| Apex Class | `ApexClass__c` | Text | Yes | Class implementing `RecordHealthCheckRule` (for example, `AccountHasRecentActivityCheck`). |
| Apex Settings (JSON) | `ApexSettingsJson__c` | Text | No | JSON object (for example, `{"daysBack": 90}`). Configure Apex without code changes. Invalid JSON → unable to evaluate. |

## See also

- [Check Set fields](check-set.md)
- [Configuration Guide](../guides/configuration-guide.md)
- [Apex plugin reference](../apex/plugin-reference.md)
