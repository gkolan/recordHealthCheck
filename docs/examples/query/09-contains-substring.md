# 09 · Text contains a substring

> Passes when Website contains the configured substring; skipped when Website is blank; fails when Website is set but does not contain it.

| | |
| --- | --- |
| **Evaluator** | Single query |
| **Sample** | [`Website_Uses_HTTPS`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Website_Uses_HTTPS.md-meta.xml) |
| **Check Set** | `Account_Examples_Query` · [`package-Account_Examples_Query.xml`](../../../manifest/package-Account_Examples_Query.xml) |

## What it checks

On Accounts where Website is populated, the Website value must contain the configured substring. Blank Website skips the check via the applicability formula so an empty field does not produce a misleading failure.

## When to use this

Reach for this pattern for substring checks on a field read through SOQL: HTTPS in a URL, domain fragments, required prefixes. Contains text is case-sensitive. Pair with Run When Formula Is True when the check should run only when the field is populated.

## Why this evaluator

Substring test via query supports dependency chains and consistent query-based evaluation; formula `CONTAINS` is an alternative when the field is on the record and no query is needed.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `CONTAINS(Website, "https")` | Works on-record; query pattern shown for SOQL-based checks and chaining. |
| Single query | One result + Contains text | **This example.** Substring via operator. |
| Compare two queries | | Not comparing two query results. |
| Custom Apex | Apex string contains | Same outcome for a simple substring. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Field on Account, no query needed | Record formula with `CONTAINS` |
| Flag forbidden substring | [Does not contain](10-does-not-contain.md) |

**Verdict:** Single query with Contains text is the right evaluator for substring checks when evaluation should flow through Data Query. Use Record formula when the field is on the record and no query adds value.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Website Uses HTTPS |
| Developer Name | Website_Uses_HTTPS |
| Check Method | Single query |
| Data Query | `SELECT Website FROM Account WHERE Id = {!Id} LIMIT 1` |
| Field To Read | Website |
| If Query Returns Multiple Rows | One result (or aggregate) |
| Operator | Contains text |
| Compare Against | A fixed value |
| Fixed Value | https |
| Run This Check When | Only when a formula is true |
| Run When Formula Is True | `NOT(ISBLANK(Website))` |
| Severity | Warning |
| Message When Failed | Website does not use HTTPS. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Fixed Value to change the required substring.

## How it works

When Run When Formula Is True passes, the engine reads Website and applies Contains text against the fixed value.

```sql
SELECT Website FROM Account WHERE Id = {!Id} LIMIT 1
```

```text
-- Applicability (Run When Formula Is True)
NOT(ISBLANK(Website))
```

**What this demonstrates**

- **Contains text**: case-sensitive substring match.
- **Applicability formula**: skips Accounts with blank Website.

> [!NOTE]
> Contains text is case-sensitive. `HTTPS` in the URL will not match fixed value `https` unless the casing aligns.

## Get this example

This rule ships in the **`Account_Examples_Query`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Query.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Query`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Set Website to a value without the substring to fail; include the substring to pass. Clear Website to see the check skipped.

[← Examples index](../index.md) · [← Prev: All rows Account field](08-all-rows-account-field.md) · [Next: Does not contain →](10-does-not-contain.md)
