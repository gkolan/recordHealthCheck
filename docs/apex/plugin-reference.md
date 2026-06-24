# Apex plugin reference

How a plugin class reads the record, parses JSON parameters, structures `evaluate`, and returns results. For the interface summary see [Apex plugin contract](plugin-contract.md). For business examples see the [examples index](../examples/index.md).

> [!NOTE]
> This reference is the source of truth for Apex plugin behavior. Guides and examples link here rather than restating these contracts.

## Invocation order

The engine calls the plugin in this order:

```text
Record page (recordId)
  → Engine loads partial base record
  → RecordHealthCheckApexEvaluatorDispatcher
      → parses ApexSettingsJson__c → context.parameters
      → builds RecordHealthCheckContext
      → pluginClass.evaluate(context)
      → finalizes status, severity, message
```

Each Rule evaluation receives **one** `RecordHealthCheckContext`. The Rule metadata object is **not** passed into `evaluate`: tunable values belong in **Apex Settings (JSON)** or as constants in Apex.

## 1. Getting `recordId`

The Id of the record on the Lightning page is always available on `context`:

```apex
Id recordId = context.recordId;
String objectApiName = context.objectApiName; // e.g. "Account"
```

Use `context.recordId` in SOQL bind variables:

```apex
Integer contactCount = [
  SELECT COUNT()
  FROM Contact
  WHERE AccountId = :context.recordId
  WITH USER_MODE
];
```

`context.recordId` is the same Id the LWC passes from the page. It is **never null** when the dispatcher calls the plugin (null `recordId` is rejected earlier with `RECORD_NOT_ACCESSIBLE`).

`context.record.Id` is also available, but **`context.recordId`** is preferred for queries: it is explicit and works even when `context.record` is minimal.

## 2. Reading fields on the current record

### `context.record` is partial: do not assume all fields are loaded

The engine loads only fields it knows the Rule needs:

| Source on the Rule | Fields added to `context.record` |
| ------------------ | -------------------------------- |
| `{!Field}` merge tokens in **Message When Failed** / **Message When Cannot Run** | Those token paths (e.g. `Name`, `Customer_Tier__c`) |
| **Run When Formula** (applicability) | Fields referenced in that formula |
| SOQL templates on Query rules | Merge tokens in those queries |

For a typical **Apex** Rule with applicability **Always** and message `{!Name} has no recent activity`, `context.record` may contain only **`Id`** and **`Name`**.

`BillingCity`, custom fields, or `Parent.BillingCity` are **not** guaranteed on `context.record` unless they appear in merge tokens or applicability formulas on that Rule.

### When `context.record` is enough

When the required field is already loaded:

```apex
Account acct = (Account) context.record;
String name = acct.Name;
```

For dynamic access:

```apex
Object tier = context.record.get('Customer_Tier__c');
```

### When to query in the plugin (recommended for most Apex checks)

When fields are not guaranteed on `context.record`, query by `context.recordId`:

```apex
Account acct = [
  SELECT
    Id,
    Name,
    Type,
    BillingCity,
    AnnualRevenue,
    Customer_Tier__c
  FROM Account
  WHERE Id = :context.recordId
  WITH USER_MODE
];
```

All plugin SOQL must use **`WITH USER_MODE`** so the running context's CRUD/FLS apply.

## 3. Parent fields and relationships

### Option A: relationship in SOQL SELECT (preferred)

```apex
Account acct = [
  SELECT
    Id,
    Name,
    ParentId,
    Parent.Name,
    Parent.BillingCity,
    Parent.Industry
  FROM Account
  WHERE Id = :context.recordId
  WITH USER_MODE
];

String parentCity = acct.Parent?.BillingCity;
Id parentId = acct.ParentId;
```

Use the relationship name from Schema (`Parent` on Account, `Account` on Contact, etc.).

### Option B: `getSObject` on a dynamic SObject

```apex
SObject parent = context.record.getSObject('Parent');
if (parent != null) {
  String parentCity = (String) parent.get('BillingCity');
}
```

This only works when the engine **pre-loaded** `Parent.BillingCity` on `context.record` (uncommon for Apex Rules unless `{!Parent.BillingCity}` appears in a message token).

### Custom lookup to another record

```apex
Account acct = [
  SELECT Primary_Contact__c, Primary_Contact__r.Email
  FROM Account
  WHERE Id = :context.recordId
  WITH USER_MODE
];
String primaryEmail = acct.Primary_Contact__r?.Email;
```

Replace `Primary_Contact__c` with the lookup API name for the object in use.

### Child records

Query children separately: `context.record` does not include child lists:

```apex
List<Opportunity> openOpps = [
  SELECT Id, Name, Amount, CloseDate
  FROM Opportunity
  WHERE AccountId = :context.recordId AND IsClosed = false
  WITH USER_MODE
];
```

## 4. Apex Settings JSON (`ApexSettingsJson__c`)

### Setup

On the Rule record in Custom Metadata:

| Setup label | API name | Example |
| ----------- | -------- | ------- |
| Apex Settings (JSON) | `ApexSettingsJson__c` | `{"daysBack": 90, "minScore": 80}` |

The dispatcher parses this **before** calling the plugin and passes it as `context.parameters` (`Map<String, Object>`). When the field is blank, `context.parameters` is an **empty map** (not null).

### Rules

| Rule | Detail |
| ---- | ------ |
| Must be a JSON **object** | `{"key": "value"}`: not `[]` or `"string"` |
| Keys are strings | Access with `parameters.get('daysBack')` |
| Types after `JSON.deserializeUntyped` | Strings stay strings; numbers may be `Integer` or `Decimal`; booleans are `Boolean` |
| Invalid JSON | Rule returns `UNABLE_TO_EVALUATE` / `INVALID_APEX_PARAMETERS`: the plugin class is **not** called |

### Recommended parsing pattern (defaults + bounds)

Shipped classes use **constants in Apex** for defaults and **JSON for per-Rule overrides**:

```apex
private static final Integer DEFAULT_DAYS_BACK = 30;
private static final Integer MIN_DAYS_BACK = 1;
private static final Integer MAX_DAYS_BACK = 3650;

public RecordHealthCheckResult evaluate(RecordHealthCheckContext context) {
  Integer daysBack = resolveDaysBack(context.parameters);
  // ...
}

private Integer resolveDaysBack(Map<String, Object> parameters) {
  if (parameters == null) {
    return DEFAULT_DAYS_BACK;
  }
  Object raw = parameters.get('daysBack');
  if (raw == null) {
    return DEFAULT_DAYS_BACK;
  }
  try {
    Integer parsed = Integer.valueOf(String.valueOf(raw));
    if (parsed >= MIN_DAYS_BACK && parsed <= MAX_DAYS_BACK) {
      return parsed;
    }
  } catch (Exception ex) {
    // fall through to default
  }
  return DEFAULT_DAYS_BACK;
}
```

**Why `String.valueOf`:** JSON may deserialize `90` as `Integer` or `Decimal`. `String.valueOf` normalizes before `Integer.valueOf`.

### Example JSON documents

| Intent | `ApexSettingsJson__c` | `parameters.get(...)` |
| ------ | ----------------------- | ------------------------ |
| Look-back window | `{"daysBack": 90}` | `daysBack` → 90 |
| Stale threshold | `{"staleDays": 30}` | `staleDays` → 30 |
| Score gate | `{"minScore": 80, "activityDaysBack": 60}` | two keys |
| Feature flag | `{"strictMode": true}` | cast to Boolean |
| Omit key | `{}` or leave blank | use Apex default |

### Boolean and Decimal helpers

```apex
private static Boolean resolveBoolean(
  Map<String, Object> parameters,
  String key,
  Boolean defaultValue
) {
  if (parameters == null || !parameters.containsKey(key)) {
    return defaultValue;
  }
  Object raw = parameters.get(key);
  if (raw instanceof Boolean) {
    return (Boolean) raw;
  }
  return Boolean.valueOf(String.valueOf(raw));
}

private static Decimal resolveDecimal(
  Map<String, Object> parameters,
  String key,
  Decimal defaultValue
) {
  if (parameters == null || !parameters.containsKey(key)) {
    return defaultValue;
  }
  Object raw = parameters.get(key);
  if (raw == null) {
    return defaultValue;
  }
  return Decimal.valueOf(String.valueOf(raw));
}
```

## 5. Recommended class structure

```apex
/**
 * One-line description. Tunable via ApexSettingsJson__c: {"daysBack": 90}
 */
public with sharing class MyAccountCheck implements RecordHealthCheckRule {
  // ── Defaults (Apex): JSON overrides per Rule ─────────────────────────
  private static final Integer DEFAULT_DAYS_BACK = 30;

  // ── Entry point ───────────────────────────────────────────────────────
  public RecordHealthCheckResult evaluate(RecordHealthCheckContext context) {
    Integer daysBack = resolveDaysBack(context.parameters);

    // 1. Load data (query WITH USER_MODE; bind context.recordId)
    // 2. Apply business logic
    // 3. Build and return result
    RecordHealthCheckResult result = new RecordHealthCheckResult();
    result.status = /* 'PASS' or 'FAIL' */;
    return result;
  }

  // ── Private helpers ─────────────────────────────────────────────────────
  private Integer resolveDaysBack(Map<String, Object> parameters) {
    // safe parse with default; see 4
    return DEFAULT_DAYS_BACK;
  }
}
```

| Practice | Why |
| -------- | --- |
| `public with sharing class` | Matches framework; respects user sharing |
| `implements RecordHealthCheckRule` | Required: dispatcher checks `instanceof` |
| Defaults as `private static final` | JSON overrides without redeploying for every tweak |
| Private `resolve*` methods | One place for bounds checking and bad JSON values |
| No DML / callouts unless intentional | Health checks are read-time advisory |
| Catch handleable exceptions | Uncaught exceptions → `ERROR` / `APEX_EVALUATOR_ERROR` |

## 6. Returning `RecordHealthCheckResult`

### Normal path: set `status` only

For most checks, return only pass/fail. Metadata supplies label, severity, and failure message:

```apex
RecordHealthCheckResult result = new RecordHealthCheckResult();
result.status = (taskCount + eventCount > 0) ? 'PASS' : 'FAIL';
return result;
```

On **`FAIL`**, the dispatcher sets:

- **`severity`** from Rule `Severity__c` (not set by the plugin)
- **`message`** from `result.message` when non-blank; otherwise **Message When Failed** with `{!Field}` merge tokens resolved

### Found / Expected (optional, on fail)

When a single failure message is not enough, set comparison chips on the card:

```apex
result.status = 'FAIL';
result.actualValue = '2 unhealthy';
result.expectedValue = '0 unhealthy';
```

See [Design spec 9 comparison display](../reference/record-health-check-design-spec.md#comparison-display-contract).

### Custom failure message from Apex (rare)

Only when the metadata message is insufficient:

```apex
result.status = 'FAIL';
result.message = 'Custom detail for this run only.';
```

When `message` is blank, metadata **Message When Failed** wins.

### Status values

| Status | When the plugin returns it |
| ------ | -------------------------- |
| `PASS` | Check succeeded |
| `FAIL` | Check failed (normal) |
| `SKIPPED` | Rare in plugins: usually dependencies skip in LWC |
| `UNABLE_TO_EVALUATE` | Rare: config/data detected inside the plugin |
| `ERROR` | Avoid: uncaught exceptions map here automatically |

Any other string → dispatcher converts to `ERROR` / `APEX_EVALUATOR_ERROR`.

### Fields the plugin does not set

| Field | Who sets it |
| ----- | ----------- |
| `label`, `checkDeveloperName`, `priority` | Dispatcher from Rule metadata |
| `severity` | Dispatcher from Rule on `FAIL` |
| `evaluatorType` | Always `Apex` |
| `durationMs` | Dispatcher |
| `reasonCode` | Framework (plugins rarely need this) |

## 7. Complete minimal example

**Rule metadata:** `ApexClass__c = AccountHasRecentActivityCheck`, `ApexSettingsJson__c = {"daysBack": 90}`

```apex
public with sharing class AccountHasRecentActivityCheck implements RecordHealthCheckRule {
  private static final Integer DEFAULT_DAYS_BACK = 30;

  public RecordHealthCheckResult evaluate(RecordHealthCheckContext context) {
    Integer daysBack = resolveDaysBack(context.parameters);
    Date cutoff = Date.today().addDays(-daysBack);

    Integer activity = [
        SELECT COUNT()
        FROM Task
        WHERE WhatId = :context.recordId AND IsClosed = TRUE AND ActivityDate >= :cutoff
        WITH USER_MODE
      ] +
      [
        SELECT COUNT()
        FROM Event
        WHERE WhatId = :context.recordId AND ActivityDate >= :cutoff
        WITH USER_MODE
      ];

    RecordHealthCheckResult result = new RecordHealthCheckResult();
    result.status = activity > 0 ? 'PASS' : 'FAIL';
    return result;
  }

  private Integer resolveDaysBack(Map<String, Object> parameters) {
    // full implementation in force-app/.../AccountHasRecentActivityCheck.cls
    return DEFAULT_DAYS_BACK;
  }
}
```

Walkthrough: [01: Recent activity](../examples/apex/01-recent-activity.md).

## 8. Checklist before deploy

- [ ] Class implements `RecordHealthCheckRule` and is **`public`** (so `Type.newInstance()` works).
- [ ] All SOQL uses **`WITH USER_MODE`** and binds **`:context.recordId`** (or fields from a plugin query).
- [ ] JSON keys documented in class header comment; defaults in Apex when JSON is blank or invalid.
- [ ] Returns only valid `status` values; normal checks use `PASS` / `FAIL` only.
- [ ] Apex test class covers `evaluate` with at least pass and fail paths.
- [ ] Rule **Apex Class** API name matches deployed class exactly.

## Related

| Doc | Purpose |
| --- | ------- |
| [Apex plugin contract](plugin-contract.md) | Short reference |
| [01: Recent activity](../examples/apex/01-recent-activity.md) | Multi-object + JSON |
| [02: Opportunity health](../examples/apex/02-open-opportunity-health.md) | Child loop + Found/Expected |
| [03: Strategic readiness](../examples/apex/03-strategic-readiness.md) | Scoring + JSON |
| [LLM guide 4.5](../guides/llm-configuration.md#45-class-sketch-apex-only) | AI output template |
| [Configuration guide 9](../guides/configuration-guide.md#9-apex-rules) | Setup fields |

[← Examples index](../examples/index.md)
