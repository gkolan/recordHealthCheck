# 04 · Two lists: at least one value overlaps

> Passes when at least one Contact Mailing City on this Account also appears among the parent Account's Contact Mailing Cities; skipped when this Account has no parent; fails when the two city lists share no values.

| | |
| --- | --- |
| **Evaluator** | Compare two queries |
| **Sample** | [`Ex_CTQ_ListsOverlap`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Ex_CTQ_ListsOverlap.md-meta.xml) |
| **Check Set** | `Account_Examples_Compare_Two_Queries` · [`package-Account_Examples_Compare_Two_Queries.xml`](../../../manifest/package-Account_Examples_Compare_Two_Queries.xml) |

## What it checks

Child Accounts with a parent must have at least one Contact Mailing City in common with Contacts on the parent Account. This is the loosest list operator: one shared value is enough; extras on either side are allowed.

## When to use this

Reach for this pattern for a basic geographic alignment check between parent and child Accounts: "some overlap exists" without requiring full containment or exact equality. Tighten the operator to List includes all of or Lists match exactly when the business rule demands stricter set logic.

## Why this evaluator

Both sides are multi-row query results that must be compared as sets. Scalar One result mode cannot express overlap.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | | Formula cannot collect Mailing City from Contacts on two Accounts. |
| Single query | One Contact list query | Sees only one Account's cities; parent set is invisible. |
| Compare two queries | Compare as two lists + Lists share any value | **This example.** Set overlap in metadata. |
| Custom Apex | Apex set intersection | Same outcome when list operators suffice. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Every child city must exist on parent | [List contains all](05-list-contains-all.md) |
| Identical city sets on both sides | [Exact list match](06-exact-list-match.md) |

**Verdict:** Compare two queries with Compare as two lists is the right evaluator when two query result sets must be compared. Choose Lists share any value for the loosest overlap test; step up operators as the rule tightens.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Contact Cities Overlap With Parent Account |
| Developer Name | Ex_CTQ_ListsOverlap |
| Check Method | Compare two queries |
| Data Query | `SELECT MailingCity FROM Contact WHERE AccountId = {!Id} AND MailingCity != null` |
| Field To Read | MailingCity |
| Compare-To Query | `SELECT MailingCity FROM Contact WHERE AccountId = {!ParentId} AND MailingCity != null` |
| Compare-To Field | MailingCity |
| If Query Returns Multiple Rows | Compare as two lists |
| Operator | Lists share any value |
| Run This Check When | Only when a count query matches |
| Run When Count Query Matches | `SELECT COUNT() FROM Account WHERE Id = {!Id} AND ParentId != null` |
| Applicability Count Comparison | Greater than |
| Applicability Count Threshold | `0` |
| Severity | Warning |
| Message When Failed | No Contact cities are shared with the parent account. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Change Operator to tighten overlap requirements without rewriting the queries.

## How it works

When the applicability count confirms a parent Account exists, the engine collects Mailing City from both Contact lists and tests whether any value appears on both sides.

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

- **Compare as two lists**: multi-row results become sets before operator evaluation.
- **`{!ParentId}` merge token**: scopes the comparison query to the parent Account while the check runs on the child.

## Get this example

This rule ships in the **`Account_Examples_Compare_Two_Queries`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Compare_Two_Queries.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Compare_Two_Queries`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

On a child Account, give Contacts cities that none of the parent's Contacts share to fail; add at least one matching Mailing City on either side to pass. Clear Parent Account to see the check skipped.

[← Examples index](../index.md) · [← Prev: Two scalar fields](03-scalar-fields.md) · [Next: List contains all →](05-list-contains-all.md)
