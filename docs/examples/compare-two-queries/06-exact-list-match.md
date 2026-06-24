# 06 · Two lists: exact same set of values

> Passes when Contact Mailing Cities on this Account exactly match those on the parent Account: no extras on either side; skipped when this Account has no parent; fails when the sets differ.

| | |
| --- | --- |
| **Evaluator** | Compare two queries |
| **Sample** | [`Ex_CTQ_ExactListMatch`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Ex_CTQ_ExactListMatch.md-meta.xml) |
| **Check Set** | `Account_Examples_Compare_Two_Queries` · [`package-Account_Examples_Compare_Two_Queries.xml`](../../../manifest/package-Account_Examples_Compare_Two_Queries.xml) |

## What it checks

Child Accounts with a parent must have the same set of Contact Mailing Cities as the parent Account: identical membership with no additional cities on either side. This is the strictest list operator in the Compare two queries family.

## When to use this

Reach for this pattern when parent and child Accounts are expected to be geographic mirrors: same city footprint, no drift in either direction. Step down to List includes all of or Lists share any value when partial overlap or one-way containment is acceptable.

## Why this evaluator

Exact set equality across two Accounts' Contact lists requires comparing two query result sets with the strictest list operator.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | | Cannot collect and compare two Contact city sets. |
| Single query | | One query sees only one Account's cities. |
| Compare two queries | Compare as two lists + Lists match exactly | **This example.** Strictest set equality. |
| Custom Apex | Apex set equality | Same outcome when list operators suffice. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| At least one shared city | [Lists overlap](04-lists-overlap.md) |
| Child cities ⊆ parent cities | [List contains all](05-list-contains-all.md) |

**Verdict:** Compare two queries with Lists match exactly is the right evaluator when two query lists must be identical sets. Use a looser list operator the moment extras on either side are allowed.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Contact Cities Exactly Match Parent Account |
| Developer Name | Ex_CTQ_ExactListMatch |
| Check Method | Compare two queries |
| Data Query | `SELECT MailingCity FROM Contact WHERE AccountId = {!Id} AND MailingCity != null` |
| Field To Read | MailingCity |
| Compare-To Query | `SELECT MailingCity FROM Contact WHERE AccountId = {!ParentId} AND MailingCity != null` |
| Compare-To Field | MailingCity |
| If Query Returns Multiple Rows | Compare as two lists |
| Operator | Lists match exactly |
| Run This Check When | Only when a count query matches |
| Run When Count Query Matches | `SELECT COUNT() FROM Account WHERE Id = {!Id} AND ParentId != null` |
| Applicability Count Comparison | Greater than |
| Applicability Count Threshold | `0` |
| Severity | Warning |
| Message When Failed | Contact cities do not exactly match the parent account: extra or missing values on one side. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change.

## How it works

When the applicability count confirms a parent Account exists, the engine builds two Mailing City lists and passes only when the sets are identical: same members, no extras on either side.

```sql
-- Data Query (this Account's cities)
SELECT MailingCity FROM Contact
WHERE AccountId = {!Id} AND MailingCity != null

-- Compare-To Query (parent Account's cities)
SELECT MailingCity FROM Contact
WHERE AccountId = {!ParentId} AND MailingCity != null

-- Applicability (Run When Count Query Matches)
SELECT COUNT() FROM Account WHERE Id = {!Id} AND ParentId != null
```

**What this demonstrates**

- **Lists match exactly**: strictest list operator; both sides must have the same set of values.
- **Operator progression**: examples 04-06 share the same queries; only Operator changes.

## Get this example

This rule ships in the **`Account_Examples_Compare_Two_Queries`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Compare_Two_Queries.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Compare_Two_Queries`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

On a child Account, add or remove a Contact Mailing City so the set differs from the parent's to fail; align both Contact city sets to pass. Clear Parent Account to see the check skipped.

[← Examples index](../index.md) · [← Prev: List contains all](05-list-contains-all.md)
