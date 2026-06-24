> [!NOTE]
> **Canonical source:** Section numbers and anchors in the [full design specification](../reference/record-health-check-design-spec.md) are stable for cross-links.

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
