# 05 · Two lists: primary list fully contained in comparison list

> Passes when every Contact Mailing City on this Account also appears among the parent Account's Contact Mailing Cities; skipped when this Account has no parent; fails when any child city is missing from the parent list.

| | |
| --- | --- |
| **Evaluator** | Compare two queries |
| **Sample** | [`Ex_CTQ_ListContainsAll`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Ex_CTQ_ListContainsAll.md-meta.xml) |
| **Check Set** | `Account_Examples_Compare_Two_Queries` · [`package-Account_Examples_Compare_Two_Queries.xml`](../../../manifest/package-Account_Examples_Compare_Two_Queries.xml) |

## What it checks

Child Accounts with a parent must have Contact Mailing Cities that are fully covered by the parent Account's Contact Mailing Cities. Every value on the primary (child) side must exist on the comparison (parent) side; the parent may have additional cities not present on the child.

## When to use this

Reach for this pattern when the child Account's geographic footprint must be a subset of the parent's: stricter than overlap, looser than exact match. Use when missing coverage on the parent is the failure mode, not extra cities on the parent.

## Why this evaluator

Set containment requires comparing two full lists from two queries. One scalar or count comparison cannot express "every child value ⊆ parent values."

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | | Cannot enumerate Contact cities from two Accounts. |
| Single query | Count child cities | Does not test membership against the parent's city set. |
| Compare two queries | Compare as two lists + List includes all of | **This example.** Primary list must be contained in comparison list. |
| Custom Apex | Apex subset test | Same outcome when list operators suffice. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Only one shared city required | [Lists overlap](04-lists-overlap.md) |
| Identical sets, no extras either way | [Exact list match](06-exact-list-match.md) |

**Verdict:** Compare two queries with List includes all of is the right evaluator when the primary query's values must all appear in the comparison query's values. Use Lists share any value when a single overlap is enough.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | All Contact Cities Covered by Parent Account |
| Developer Name | Ex_CTQ_ListContainsAll |
| Check Method | Compare two queries |
| Data Query | `SELECT MailingCity FROM Contact WHERE AccountId = {!Id} AND MailingCity != null` |
| Field To Read | MailingCity |
| Compare-To Query | `SELECT MailingCity FROM Contact WHERE AccountId = {!ParentId} AND MailingCity != null` |
| Compare-To Field | MailingCity |
| If Query Returns Multiple Rows | Compare as two lists |
| Operator | List includes all of |
| Run This Check When | Only when a count query matches |
| Run When Count Query Matches | `SELECT COUNT() FROM Account WHERE Id = {!Id} AND ParentId != null` |
| Applicability Count Comparison | Greater than |
| Applicability Count Threshold | `0` |
| Severity | Warning |
| Message When Failed | One or more Contact cities are not present on the parent account. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Change Operator to Lists share any value or Lists match exactly to relax or tighten the set rule without new queries.

## How it works

When the applicability count confirms a parent Account exists, the engine builds two Mailing City lists and passes only when every child city appears in the parent list.

```sql
-- Data Query (child: must be ⊆ parent)
SELECT MailingCity FROM Contact
WHERE AccountId = {!Id} AND MailingCity != null

-- Compare-To Query (parent: superset)
SELECT MailingCity FROM Contact
WHERE AccountId = {!ParentId} AND MailingCity != null

-- Applicability (Run When Count Query Matches)
SELECT COUNT() FROM Account WHERE Id = {!Id} AND ParentId != null
```

**What this demonstrates**

- **List includes all of**: primary list values must all exist in the comparison list; extras on the comparison side are allowed.
- **Same queries as overlap/example 04**: operator choice alone changes strictness.

## Get this example

This rule ships in the **`Account_Examples_Compare_Two_Queries`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Compare_Two_Queries.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Compare_Two_Queries`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

On a child Account, add a Contact Mailing City that no parent Contact shares to fail; ensure every child city exists on a parent Contact to pass. Clear Parent Account to see the check skipped.

[← Examples index](../index.md) · [← Prev: Lists overlap](04-lists-overlap.md) · [Next: Exact list match →](06-exact-list-match.md)
