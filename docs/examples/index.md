# Record Health Check: Examples

Copy-paste patterns for every Check Method. For custom Apex checks, see the [Apex plugin reference](../apex/plugin-reference.md).

Open the document for the needed Check Method and use its configuration table in Setup.

This folder walks through every type of health check the framework supports, using Account as the base object throughout. Each example states **what** the check does, **how** to configure it in Setup, and **why** that pattern fits.

For field definitions and Setup guidance, see [Configuration Guide](../guides/configuration-guide.md). For the formal contract, see [Design Specification](../reference/record-health-check-design-spec.md). For first-time setup, see [Getting Started](../installation/getting-started.md).

**Install sample metadata:** Deploy [core](../../manifest/package-core.xml) first, then any [Check Set package](#sample-check-set-packages) below, or use `manifest/package.xml` for everything at once. Configuration tables can also be entered in Setup without deploying sample metadata.

## How to read the configuration tables

Configuration tables use **Setup labels**: the exact field names in **Setup → Custom Metadata Types**. The **Value** column is what to enter or select.

- **Picklist values** use Setup wording where it differs from the stored API value (for example **Record formula** stores as `Formula`).
- **API names** (`CheckMethod__c`, `RunOrder__c`, …) are in the [Configuration Guide](../guides/configuration-guide.md) and [Design Specification](../reference/record-health-check-design-spec.md) for metadata XML and LLM output.
- Per-example tables list only fields that matter for that pattern. Shared fields use the values in the table below unless an example overrides them.

## Common Rule Fields

Every Rule shares these fields. They are documented once here; individual examples show pattern-specific fields only.

| Setup label | API name | What it does | Why it exists |
| ----------- | -------- | ------------ | ------------- |
| Check Name | `CheckName__c` | Row title in the component | What end users see |
| Developer Name | `DeveloperName` | Stable API key | Dependencies and Apex reference this name |
| Label | Master Label | Name in Setup lists | Internal metadata identity |
| Check Set | `Record_Health_Check_Set__c` | Parent Check Set | Scopes the Rule to one object and component |
| Run Order | `RunOrder__c` | Run/display order (lower first) | Sequences checks and dependencies |
| Active | `IsActive__c` | Include in evaluation | Disable without deleting |
| Severity | `Severity__c` | Error, Warning, or Info on **fail** only | Visual weight of failures |
| Message When Failed | `MessageWhenFailed__c` | User message when the check fails | Actionable guidance |
| Run This Check When | `RunThisCheckWhen__c` | Always, Formula, or SOQL | Skip checks that do not apply |

**Defaults used in examples unless noted:** Run Order `100`, Active checked, Run This Check When `Always`, Severity `Error`, parent Check Set `Account_Data_Quality` (or the section-specific set name).

## Merge tokens in SOQL

Query, CompareTwoQueries, and SOQL applicability templates can embed **`{!FieldApiName}`** tokens. At run time the engine reads each value from the **current record** (the one on the record page), formats it for SOQL (quoted strings, unquoted numbers/dates/booleans), and substitutes it into the query. Relationship paths work too: `{!ParentId}`, `{!Parent.BillingCity}`, `{!Owner.Name}`.

**Standard and custom fields use the same syntax.** There is no special prefix or syntax for custom fields: use the field’s API name exactly as it appears in Setup (including the `__c` suffix). If the running user can read the field on the record, it can be a merge token in SOQL, applicability SOQL, or failure messages.

**Why most numbered examples use `{!Id}`:** Every example runs on an **Account record page**, and the dominant pattern is “find child rows for *this* account” → `WHERE AccountId = {!Id}` or `WHERE Id = {!Id}` when querying the Account itself. That is convention for clarity, **not a requirement**. The merge token can be any readable field the business rule requires.

| Token in template | Field type | Substituted as |
| ----------------- | ---------- | -------------- |
| `{!Id}` | Standard Id | Quoted Id literal |
| `{!OwnerId}` | Standard lookup | Quoted Id literal |
| `{!Industry}` | Standard picklist/text | Quoted string (escaped) |
| `{!AnnualRevenue}` | Standard number/currency | Unquoted numeric literal |
| `{!Customer_Tier__c}` | Custom picklist/text | Quoted string (escaped) |
| `{!Primary_Contact__c}` | Custom lookup | Quoted Id literal |
| `{!Health_Score__c}` | Custom number/percent | Unquoted numeric literal |
| `{!Contract_Renewal_Date__c}` | Custom date | Unquoted date literal (`yyyy-MM-dd`) |
| `{!ParentId}` | Standard lookup | Quoted Id literal |

The running user must have **read access** to every token field (FLS). Unresolvable tokens return `UNABLE_TO_EVALUATE` / `MISSING_BIND_VALUE`. Full contract: [Design Specification 11](../reference/record-health-check-design-spec.md#11-soql-safety).

### Custom fields (`__c`)

Custom fields behave identically to standard fields. Replace the placeholder API names below with fields that exist on the target object.

**Require a related record when a custom tier is set**: use this SOQL template when the child row must match a tier picklist on the Account:

```sql
SELECT COUNT() FROM Contract__c
WHERE Account__c = {!Id} AND Status__c = 'Active'
  AND Tier__c = {!Customer_Tier__c}
```

`{!Customer_Tier__c}` injects the Account’s custom tier picklist value into the WHERE clause. If the field is blank on the Account, the token becomes `null` in SOQL.

**Match child rows to a custom lookup on the Account**: target one designated contact by Id:

```sql
SELECT Email FROM Contact
WHERE Id = {!Primary_Contact__c} AND Email != null
```

`{!Primary_Contact__c}` resolves to the Id stored in a custom lookup on the Account: useful when the check should target one designated contact, not every contact on the account.

**Filter using a custom multi-select picklist (unquoted token)**: expand semicolon-delimited values into an `INCLUDES` list:

```sql
SELECT COUNT() FROM Case
WHERE AccountId = {!Id}
  AND Product_Line__c INCLUDES {!Supported_Regions__c}
```

For multi-select fields on the **base record**, an unquoted `{!Supported_Regions__c}` token expands semicolon-delimited values into an `INCLUDES ('A', 'B')` list. The same expansion applies to relationship paths (for example `{!Parent.Regions__c}`) when the related record is loaded and the field resolves. **Quoted** tokens keep the raw `'A;B;C'` string.

**Failure message with a custom field**: merge tokens use the same `{!Field}` syntax as SOQL:

```text
{!Name} is tier {!Customer_Tier__c} but has no active contract on file.
```

### When to use something other than `{!Id}` (standard fields)

**Filter child records by the Account owner (not the record Id)**: scope opportunities to the same owner as the Account:

```sql
SELECT COUNT() FROM Opportunity
WHERE AccountId = {!Id} AND OwnerId = {!OwnerId} AND IsClosed = false
```

Use when the check should only consider opportunities owned by the same user who owns the Account.

**Compare against the parent Account’s children**: used in [compare example 04](compare-two-queries/04-lists-overlap.md):

```sql
SELECT MailingCity FROM Contact
WHERE AccountId = {!ParentId} AND MailingCity != null
```

`{!ParentId}` scopes the query to the parent’s contact list while the check runs on a child Account.

**Peer lookup using a field value from the current record**: used in [query example 16](query/16-list-does-not-contain.md):

```sql
SELECT COUNT() FROM Account
WHERE Industry = {!Industry} AND Id != {!Id}
```

`{!Industry}` carries the current Account’s industry into the WHERE clause; `{!Id}` excludes the record under test.

Failure messages use the same `{!Field}` syntax (for example `{!Name}` to name the record); see [Configuration Guide 11](../guides/configuration-guide.md#11-merge-tokens).

## Example catalog

For when to reach for a health check instead of save-time enforcement, see [Configuration Guide: what it can check](../guides/configuration-guide.md#2-what-it-can-check).

### Formula (`formula/`): on-record fields only

| # | File | Pattern | Why Health Check |
| - | ---- | -------------- | ---------------- |
| 01 | [01-single-required-field.md](formula/01-single-required-field.md) | `NOT(ISBLANK(...))` | Read-time audit on legacy and imported data |
| 02 | [02-either-or-field.md](formula/02-either-or-field.md) | `OR()` | Coaching on view without save-time blocking |
| 03 | [03-numeric-threshold.md](formula/03-numeric-threshold.md) | `> 0` vs blank | Zero or null on existing records at open |
| 04 | [04-multiple-required-and.md](formula/04-multiple-required-and.md) | `AND()` | Address completeness when the record is opened |
| 05 | [05-two-fields-compared.md](formula/05-two-fields-compared.md) | Field equality + applicability | Consistency coaching across two fields |
| 06 | [06-type-scoped.md](formula/06-type-scoped.md) | `ISPICKVAL` gate | Partner-only guidance without other-type noise |
| 07 | [07-parent-field.md](formula/07-parent-field.md) | `Parent.Field` | Parent quality visible from the child page |
| 08 | [08-found-expected-values.md](formula/08-found-expected-values.md) | Found/Expected display + multi-line message | Show the two sides of a comparison, not just the formula |

### Query (`query/`): related records via SOQL

| # | File | Pattern |
| - | ---- | -------------- |
| 01 | [01-child-count-minimum-one.md](query/01-child-count-minimum-one.md) | `COUNT()` > 0 |
| 02 | [02-child-count-minimum-two.md](query/02-child-count-minimum-two.md) | `COUNT()` ≥ 2 |
| 03 | [03-empty-result-fail.md](query/03-empty-result-fail.md) | `WhenZeroRows` = Fail |
| 04 | [04-empty-result-skip.md](query/04-empty-result-skip.md) | `WhenZeroRows` = Skip |
| 05 | [05-any-row-static-threshold.md](query/05-any-row-static-threshold.md) | `AnyRowPasses` |
| 06 | [06-any-row-formula-threshold.md](query/06-any-row-formula-threshold.md) | Any row vs formula |
| 07 | [07-all-rows-static-threshold.md](query/07-all-rows-static-threshold.md) | `AllRowsPass` |
| 08 | [08-all-rows-account-field.md](query/08-all-rows-account-field.md) | All rows vs account field |
| 09 | [09-contains-substring.md](query/09-contains-substring.md) | `Contains` |
| 10 | [10-does-not-contain.md](query/10-does-not-contain.md) | `DoesNotContain` |
| 11 | [11-is-not-blank.md](query/11-is-not-blank.md) | `IsNotBlank` |
| 12 | [12-is-blank.md](query/12-is-blank.md) | `IsBlank` |
| 13 | [13-count-upper-limit.md](query/13-count-upper-limit.md) | Count cap |
| 14 | [14-not-equals-rating.md](query/14-not-equals-rating.md) | `NotEquals` |
| 15 | [15-list-contains-any.md](query/15-list-contains-any.md) | `ListContainsAny` |
| 16 | [16-list-does-not-contain.md](query/16-list-does-not-contain.md) | `ListDoesNotContainAny` |
| 17 | [17-count-vs-second-query.md](query/17-count-vs-second-query.md) | Query + `AnotherQuery` |

### Compare two queries (`compare-two-queries/`)

| # | File | Pattern |
| - | ---- | -------------- |
| 01 | [01-aggregate-counts.md](compare-two-queries/01-aggregate-counts.md) | COUNT vs COUNT |
| 02 | [02-aggregate-vs-account-scalar.md](compare-two-queries/02-aggregate-vs-account-scalar.md) | SUM vs Account field |
| 03 | [03-scalar-fields.md](compare-two-queries/03-scalar-fields.md) | Field vs field |
| 04 | [04-lists-overlap.md](compare-two-queries/04-lists-overlap.md) | `ListsOverlap` |
| 05 | [05-list-contains-all.md](compare-two-queries/05-list-contains-all.md) | `ListContainsAll` |
| 06 | [06-exact-list-match.md](compare-two-queries/06-exact-list-match.md) | `ExactListMatch` |

### Apex (`apex/`): walkthroughs only

Implementation: [Apex plugin reference](../apex/plugin-reference.md) · [Apex plugin contract](../apex/plugin-contract.md)

| # | File | Sample class (in core package) |
| - | ---- | ------------------------------ |
| 01 | [01-recent-activity.md](apex/01-recent-activity.md) | `AccountHasRecentActivityCheck` |
| 02 | [02-open-opportunity-health.md](apex/02-open-opportunity-health.md) | `AccountOpenOpportunityHealthCheck` |
| 03 | [03-strategic-readiness.md](apex/03-strategic-readiness.md) | `AccountStrategicReadinessCheck` |
| 04 | [04-inactive-approver.md](apex/04-inactive-approver.md) | `ApprovalInactiveApproverCheck` |

### Applicability, dependencies, and aggregates

Applicability gates and dependencies are per-Rule settings, covered in [Configuration Guide 10](../guides/configuration-guide.md#10-applicability-and-dependencies) with the type-scoped pattern in [formula/06](formula/06-type-scoped.md). Aggregate functions (`SUM`, `AVG`, `MIN`, `MAX`, `COUNT_DISTINCT`) are summarized in the [aggregate pattern reference](#pattern-reference-aggregates) below.

## Sample Check Set packages

Ten sample Check Sets ship with the repo, plus four example Check Sets that mirror the numbered walkthrough docs. Deploy in two steps, or copy tables from the docs into Setup.

```bash
# 1: Core (required): engine, Custom Metadata types, LWC, permission sets
sf project deploy start --manifest manifest/package-core.xml

# 2: One or more sample Check Sets (example: everyday patterns)
sf project deploy start --manifest manifest/package-Account_Everyday_Use_Cases.xml
```

Deploy everything at once: `sf project deploy start --manifest manifest/package.xml`

Set the component **Check Set Developer Name** to the deployed Check Set (for example `Account_Everyday_Use_Cases`).

| Check Set | Manifest | Rules | Start here |
| --------- | -------- | ----: | ---------- |
| `Account_Everyday_Use_Cases` | `package-Account_Everyday_Use_Cases.xml` | 16 | [formula/01-single-required-field.md](formula/01-single-required-field.md) |
| `Account_Compliance_Audit` | `package-Account_Compliance_Audit.xml` | 10 | [query/11-is-not-blank.md](query/11-is-not-blank.md) |
| `Account_Data_Quality` | `package-Account_Data_Quality.xml` | 4 | [formula/01-single-required-field.md](formula/01-single-required-field.md) |
| `Account_Relationships` | `package-Account_Relationships.xml` | 4 | [query/01-child-count-minimum-one.md](query/01-child-count-minimum-one.md) |
| `Account_Formula_Coverage` | `package-Account_Formula_Coverage.xml` | 7 | [formula/04-multiple-required-and.md](formula/04-multiple-required-and.md) |
| `Account_Query_Coverage` | `package-Account_Query_Coverage.xml` | 17 | [query/11-is-not-blank.md](query/11-is-not-blank.md) |
| `Account_Aggregate_Coverage` | `package-Account_Aggregate_Coverage.xml` | 6 | [aggregate reference](#pattern-reference-aggregates) |
| `Account_AppComp_Coverage` | `package-Account_AppComp_Coverage.xml` | 6 | [formula/06-type-scoped.md](formula/06-type-scoped.md) |
| `Account_Compare_Queries` | `package-Account_Compare_Queries.xml` | 10 | [compare-two-queries/01-aggregate-counts.md](compare-two-queries/01-aggregate-counts.md) |
| `Account_Advanced_Checks` | `package-Account_Advanced_Checks.xml` | 8 | [apex/01-recent-activity.md](apex/01-recent-activity.md) |

### Example doc Check Sets (numbered walkthroughs)

Deploy `package-core.xml` first, then the manifest for the relevant walkthrough set. Rules use the same Developer Names as the configuration tables in each example file.

| Check Set | Manifest | Rules | Start here |
| --------- | -------- | ----: | ---------- |
| `Account_Examples_Formula` | `package-Account_Examples_Formula.xml` | 8 | [formula/01-single-required-field.md](formula/01-single-required-field.md) |
| `Account_Examples_Query` | `package-Account_Examples_Query.xml` | 17 | [query/01-child-count-minimum-one.md](query/01-child-count-minimum-one.md) |
| `Account_Examples_Compare_Two_Queries` | `package-Account_Examples_Compare_Two_Queries.xml` | 6 | [compare-two-queries/01-aggregate-counts.md](compare-two-queries/01-aggregate-counts.md) |
| `Account_Examples_Apex` | `package-Account_Examples_Apex.xml` | 4 | [apex/01-recent-activity.md](apex/01-recent-activity.md) |

Deploy `package-Account_Examples_Apex.xml` for all four Apex sample classes (`AccountStrategicReadinessCheck` and `ApprovalInactiveApproverCheck` are not in `package-core.xml`).

## Seeing Found / Expected on a failing check

The **Found** / **Expected** block is computed at runtime: no new Custom Metadata fields. It appears on **failed** rows only, beneath `MessageWhenFailed__c`, as stacked labelled chips (uppercase **Found** / **Expected** captions beside monospace values).

| To see it | Check Set | Rule | Setup |
| --------- | --------- | ---- | ----- |
| Query scalar (both sides) | `Account_Query_Coverage` | `Account_QC_NotEquals` | Account with **Rating = Cold**: shows e.g. Found `"Cold"` / Expected `does not equal "Cold"` |
| Formula (Expected only) | `Account_Data_Quality` | `Account_DQ_BillingCity` | Account with blank **Billing City**: shows Expected `"NOT(ISBLANK(BillingCity))"` |
| Dual-query | `Account_Compare_Queries` | Any rule that fails on sample data | An account where primary and comparison queries disagree demonstrates the display |

## Pattern reference

| Pattern | CheckMethod__c | WhenMultipleRows__c | CompareAgainst__c | Notes |
|---|---|---|---|---|
| Single required field | Pass/Fail Formula | | | `NOT(ISBLANK(...))` |
| Either/or fields | Pass/Fail Formula | | | `OR(...)` |
| Numeric threshold | Pass/Fail Formula | | | `Field > 0` |
| Multiple required fields | Pass/Fail Formula | | | `AND(...)` |
| Two fields equal | Pass/Fail Formula | | | `Field1 = Field2` |
| Type-scoped rule | Pass/Fail Formula | | | Applicability: `ISPICKVAL(...)` |
| Parent field check | Pass/Fail Formula | | | `Parent.Field` dot notation |
| Count ≥ 1 | Single query | One result (or aggregate) | A fixed value | `SELECT COUNT()` |
| Count ≤ upper limit | Single query | One result (or aggregate) | A fixed value | Less than (`LessThan`) |
| Empty = Fail | Single query | At least one row must pass | A fixed value | `WhenZeroRows__c` = Fail |
| Empty = Skip | Single query | Every row must pass | A fixed value | `WhenZeroRows__c` = Skip |
| Any row > static | Single query | At least one row must pass | A fixed value | Fixed threshold |
| Any row > formula | Single query | At least one row must pass | A formula on the record | Per-account threshold |
| All rows > static | Single query | Every row must pass | A fixed value | Every row must pass |
| All rows = account field | Single query | Every row must pass | A formula on the record | `WhenZeroRows__c` = Pass |
| Contains substring | Single query | One result (or aggregate) | A fixed value | Contains text (`Contains`, **case-sensitive**) |
| Does not contain | Single query | One result (or aggregate) | A fixed value | Does not contain text (`DoesNotContain`, **case-sensitive**) |
| Is not empty | Single query | One result (or aggregate) | | No value needed (`IsNotBlank`) |
| Is empty | Single query | One result (or aggregate) | | No value needed (`IsBlank`) |
| Count vs second query | Single query | One result (or aggregate) | Another query | Two COUNT() queries |
| Scalar in child list | Single query | Compare as two lists | | ListContainsAny + `ValueToTest__c` |
| Scalar not in list | Single query | Compare as two lists | | ListDoesNotContainAny + `ValueToTest__c` |
| Two counts compared | Compare two queries | One result (or aggregate) | | COUNT vs COUNT |
| SUM vs Account scalar | Compare two queries | One result (or aggregate) | | Aggregate vs field |
| Two scalar fields | Compare two queries | One result (or aggregate) | | Field vs field |
| Lists overlap | Compare two queries | Compare as two lists | | At least one match |
| List contained by other | Compare two queries | Compare as two lists | | ListContainsAll |
| Exact list match | Compare two queries | Compare as two lists | | No extras on either side |
| Multi-condition logic | Custom Apex | | | [Apex example 01](apex/01-recent-activity.md) |

### Pattern reference: Aggregates

| Function | Returns | Use when |
|---|---|---|
| `COUNT()` | Total row count | Row count matters |
| `COUNT(DISTINCT field)` | Unique value count | Distinct values matter |
| `SUM(field)` | Sum of all values | Totals matter (pipeline, revenue, hours) |
| `AVG(field)` | Mean of all values | Population-level average matters |
| `MIN(field)` | Smallest / earliest value | Worst-case value in the set matters |
| `MAX(field)` | Largest / most recent value | Best-case value in the set matters |

> [!NOTE]
> All five aggregates return `null` when no rows match. Pair with a SOQL applicability gate (skip when the child set is empty) or **If A Value Is Empty = Ignore rows with empty values** (skip individual null results).

**Aliases are required for everything except `COUNT()`**: the framework looks up the value by field name, so `SELECT SUM(Amount) FROM ...` won't work. Write `SELECT SUM(Amount) myAlias FROM ...` and set Field To Read to `myAlias`.
