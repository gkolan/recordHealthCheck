# 14 · Rating must not equal a specific value

> Passes when Account Rating is set and is not the excluded value; skipped when Rating is blank; fails when Rating equals the excluded value.

| | |
| --- | --- |
| **Evaluator** | Single query |
| **Sample** | [`Rating_Is_Not_Cold`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Rating_Is_Not_Cold.md-meta.xml) |
| **Check Set** | `Account_Examples_Query` · [`package-Account_Examples_Query.xml`](../../../manifest/package-Account_Examples_Query.xml) |

## What it checks

On Accounts where Rating is populated, the value must not equal the configured excluded picklist value. Blank Rating skips the check so an unset rating does not vacuously pass.

## When to use this

Reach for this pattern to flag a specific bad picklist or text value rather than testing presence alone. Does not equal with an applicability formula prevents blank from silently passing.

## Why this evaluator

Specific disallowed value on a field read via query, with blank guard.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `TEXT(Rating) != "Cold"` | On-record option when Rating is always set. |
| Single query | Does not equal + applicability | **This example.** |
| Compare two queries | | Single scalar vs fixed value. |
| Custom Apex | | Unnecessary. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Rating must be set at all | [Is not blank](11-is-not-blank.md) |
| Forbidden substring in text | [Does not contain](10-does-not-contain.md) |

**Verdict:** Single query with Does not equal suits disallowed picklist values when query-based evaluation is preferred. Add Run When Formula Is True when blank should skip rather than pass.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Rating Is Not Cold |
| Developer Name | Rating_Is_Not_Cold |
| Check Method | Single query |
| Data Query | `SELECT Rating FROM Account WHERE Id = {!Id} LIMIT 1` |
| Field To Read | Rating |
| If Query Returns Multiple Rows | One result (or aggregate) |
| Operator | Does not equal |
| Compare Against | A fixed value |
| Fixed Value | Cold |
| Run This Check When | Only when a formula is true |
| Run When Formula Is True | `NOT(ISBLANK(TEXT(Rating)))` |
| Severity | Warning |
| Message When Failed | Account Rating is Cold. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Fixed Value to change the disallowed picklist value.

## How it works

When Run When Formula Is True passes, the engine compares Rating to the fixed value with Does not equal.

```sql
SELECT Rating FROM Account WHERE Id = {!Id} LIMIT 1
```

```text
-- Applicability (Run When Formula Is True)
NOT(ISBLANK(TEXT(Rating)))
```

**What this demonstrates**

- **Does not equal**: flags one specific bad value.
- **TEXT() in applicability**: picklist blank guard for formula context.

## Get this example

This rule ships in the **`Account_Examples_Query`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Query.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Query`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Set Rating to the excluded value to fail; set any other Rating to pass. Clear Rating to see the check skipped.

[← Examples index](../index.md) · [← Prev: Count upper limit](13-count-upper-limit.md) · [Next: List contains any →](15-list-contains-any.md)
