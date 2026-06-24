# 10 · Text must not contain a substring

> Passes when Website does not contain the forbidden substring; skipped when Website is blank; fails when Website includes it.

| | |
| --- | --- |
| **Evaluator** | Single query |
| **Sample** | [`Website_Does_Not_Use_Plain_HTTP`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Website_Does_Not_Use_Plain_HTTP.md-meta.xml) |
| **Check Set** | `Account_Examples_Query` · [`package-Account_Examples_Query.xml`](../../../manifest/package-Account_Examples_Query.xml) |

## What it checks

On Accounts where Website is populated, the value must not contain the configured insecure prefix. This complements the HTTPS contains check by explicitly flagging plain HTTP URLs.

## When to use this

Reach for this pattern when a forbidden substring must be absent: insecure protocols, deprecated domains, disallowed tokens. Does not contain text is the inverse of Contains text; both are case-sensitive.

## Why this evaluator

Forbidden-substring rule on a field loaded via query, with applicability when Website is blank.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `NOT(CONTAINS(Website, "http://"))` | On-record alternative; query shown for SOQL-based pattern. |
| Single query | One result + Does not contain text | **This example.** |
| Compare two queries | | Not a dual-query comparison. |
| Custom Apex | Apex string guard | Same outcome for simple substring exclusion. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Require presence of substring | [Contains substring](09-contains-substring.md) |
| Picklist not equal to value | [Not equals rating](14-not-equals-rating.md) |

**Verdict:** Single query with Does not contain text is the right evaluator to flag forbidden substrings via Data Query. Pair with example 09 for full HTTP/HTTPS coverage.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Website Does Not Use Plain HTTP |
| Developer Name | Website_Does_Not_Use_Plain_HTTP |
| Check Method | Single query |
| Data Query | `SELECT Website FROM Account WHERE Id = {!Id} LIMIT 1` |
| Field To Read | Website |
| If Query Returns Multiple Rows | One result (or aggregate) |
| Operator | Does not contain text |
| Compare Against | A fixed value |
| Fixed Value | http:// |
| Run This Check When | Only when a formula is true |
| Run When Formula Is True | `NOT(ISBLANK(Website))` |
| Severity | Warning |
| Message When Failed | Website uses an insecure HTTP prefix. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Fixed Value to change the forbidden substring.

## How it works

When Run When Formula Is True passes, the engine reads Website and fails if Does not contain text is violated.

```sql
SELECT Website FROM Account WHERE Id = {!Id} LIMIT 1
```

```text
-- Applicability (Run When Formula Is True)
NOT(ISBLANK(Website))
```

**What this demonstrates**

- **Does not contain text**: inverse substring operator.
- **Paired with example 09**: require `https` and forbid `http://` for layered URL policy.

## Get this example

This rule ships in the **`Account_Examples_Query`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Query.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Query`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

Set Website to a URL containing the forbidden prefix to fail; use HTTPS-only URLs without the prefix to pass. Clear Website to see the check skipped.

[← Examples index](../index.md) · [← Prev: Contains substring](09-contains-substring.md) · [Next: Is not blank →](11-is-not-blank.md)
