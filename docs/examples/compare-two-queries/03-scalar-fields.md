# 03 · Two scalar field values

> Passes when the oldest Contact's Mailing City equals the Account Billing City; skipped when the Account has no Contacts; fails when both are set but differ.

| | |
| --- | --- |
| **Evaluator** | Compare two queries |
| **Sample** | [`Oldest_Contact_City_Matches_Billing_City`](../../../force-app/main/default/customMetadata/Record_Health_Check_Rule__mdt.Oldest_Contact_City_Matches_Billing_City.md-meta.xml) |
| **Check Set** | `Account_Examples_Compare_Two_Queries` · [`package-Account_Examples_Compare_Two_Queries.xml`](../../../manifest/package-Account_Examples_Compare_Two_Queries.xml) |

## What it checks

Among Accounts with at least one Contact, the Mailing City on the oldest Contact (by Created Date) must equal Billing City on the Account. Neither side is an aggregate: both are single field reads from different objects.

## When to use this

Reach for this pattern when two scalar values from different queries must be compared field-to-field: oldest child value vs parent field, primary contact vs Account attribute, or any paired single-row reads. Use Record formula instead when both fields are reachable via dot notation on one object.

## Why this evaluator

Each side comes from a different query with its own sort and limit. Formula cannot ORDER BY Created Date on a child collection.

| Alternative | How it compares | Fit for this check |
| ----------- | --------------- | ------------------ |
| Record formula | `BillingCity = ShippingCity` on Account | Both fields on one row: does not reach oldest Contact by Created Date. |
| Single query | One query returning one Contact | Cannot simultaneously read Billing City from Account in the same One result comparison without a second query. |
| Compare two queries | Ordered Contact query vs Account query | **This example.** Two scalars, Equals operator. |
| Custom Apex | Apex that finds oldest Contact | Same outcome when SOQL ORDER BY and LIMIT express the pick. |

**When the simpler option is enough**

| Need | Use instead |
| ---- | ----------- |
| Two fields on the same Account row | [Two fields compared](../formula/05-two-fields-compared.md) |
| Two `COUNT()` values | [Two aggregate counts](01-aggregate-counts.md) |

**Verdict:** Compare two queries is the right evaluator when each side is a single field from a different query. Drop to Record formula when both operands live on the record under test.

## Configuration

| Setup label | Value |
| ----------- | ----- |
| Check Name | Oldest Contact City Matches Billing City |
| Developer Name | Oldest_Contact_City_Matches_Billing_City |
| Check Method | Compare two queries |
| Data Query | `SELECT MailingCity FROM Contact WHERE AccountId = {!Id} ORDER BY CreatedDate ASC LIMIT 1` |
| Field To Read | MailingCity |
| Compare-To Query | `SELECT BillingCity FROM Account WHERE Id = {!Id} LIMIT 1` |
| Compare-To Field | BillingCity |
| If Query Returns Multiple Rows | One result (or aggregate) |
| Operator | Equals |
| Run This Check When | Only when a count query matches |
| Run When Count Query Matches | `SELECT COUNT() FROM Contact WHERE AccountId = {!Id}` |
| Applicability Count Comparison | Greater than |
| Applicability Count Threshold | `0` |
| Severity | Info |
| Message When Failed | Oldest contact's Mailing City does not match Account Billing City. |

> [!NOTE]
> This table is the control panel for the check: the single source of truth for every value, so edits here take effect with no code change. Edit Data Query ordering to change which Contact row is selected; edit Field To Read and Compare-To Field to compare different columns.

## How it works

When the applicability count query returns greater than zero, the engine runs both queries, reads one scalar from each, and applies Equals.

```sql
-- Data Query
SELECT MailingCity FROM Contact
WHERE AccountId = {!Id}
ORDER BY CreatedDate ASC
LIMIT 1

-- Compare-To Query
SELECT BillingCity FROM Account WHERE Id = {!Id} LIMIT 1

-- Applicability (Run When Count Query Matches)
SELECT COUNT() FROM Contact WHERE AccountId = {!Id}
```

**What this demonstrates**

- **Scalar field comparison**: no aggregate; Field To Read and Compare-To Field name the columns.
- **ORDER BY + LIMIT**: selects a specific child row before comparison.

## Get this example

This rule ships in the **`Account_Examples_Compare_Two_Queries`** Check Set. Deploy the engine once, then the Check Set, then wire the component to it:

```bash
sf project deploy start --manifest manifest/package-core.xml                              # engine + types: once per org
sf project deploy start --manifest manifest/package-Account_Examples_Compare_Two_Queries.xml  # this example's Check Set
```

Set the component's **Check Set Developer Name** to `Account_Examples_Compare_Two_Queries`. See the [example catalog](../index.md#example-doc-check-sets-numbered-walkthroughs) for every Check Set and what it contains.

## Try it

On an Account with Contacts, set the oldest Contact's Mailing City to differ from Billing City to fail; make them match to pass. Remove all Contacts to see the check skipped.

[← Examples index](../index.md) · [← Prev: Aggregate vs Account scalar](02-aggregate-vs-account-scalar.md) · [Next: Lists overlap →](04-lists-overlap.md)
