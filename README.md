# Record Health Check

[![Deploy to Salesforce](https://img.shields.io/badge/Deploy%20to-Salesforce-00A1E0?logo=salesforce&logoColor=white)](https://githubsfdeploy.herokuapp.com/?owner=gkolan&repo=recordHealthCheck&ref=main)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![CI](https://github.com/gkolan/recordHealthCheck/actions/workflows/ci.yml/badge.svg)](https://github.com/gkolan/recordHealthCheck/actions/workflows/ci.yml)
[![Salesforce API](https://img.shields.io/badge/Salesforce%20API-66.0-00A1E0.svg)](sfdx-project.json)

Record Health Check is a metadata-driven framework for running data-quality checks against a Salesforce record, right on its **record page**. It is **advisory** and read-only, so it never blocks a save and never writes a field. You define **Check Sets** and **Rules** in Custom Metadata; an Apex engine evaluates the open record, and the component shows each result as **pass**, **fail**, **skipped**, or **error**.

Validation rules and required fields enforce at save time, one record and one field at a time. Record Health Check complements them by running at read time, so it can evaluate across related records, compare aggregates, and surface data that predates your rules or entered the org another way.

## What it does

- **Formula checks** evaluate a formula over fields on the current record (requires org API **v63.0+**).
- **Query checks** run a SOQL query and compare the result to a value or a list.
- **Compare-two-queries checks** run two queries and compare their results.
- **Apex checks** call a custom Apex class for logic beyond formulas and SOQL.
- **Applicability gates and dependencies** decide per record whether a Rule runs, and let one Rule wait for another to pass first.
- **Automatic or on-demand runs** evaluate the record on page load or when you click **Run**.
- **Debug Mode** adds optional troubleshooting detail on the card and in the browser console. It needs **Debug Mode** on the Check Set plus the `Record_Health_Check_Debug` permission (from the `Record_Health_Check_Admin` permission set). See [Debug Mode](docs/guides/debug-mode.md).

## Example use cases

Ordered simplest → most advanced, from a single on-record formula to multi-query comparisons and custom Apex. Each links to a full walkthrough.

| #   | Use case                              | Check method        | What it's about                                                                                           | Example                                                                                            |
| --- | ------------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| 1   | Phone or Website required             | Record formula      | At least one of Phone or Website must be populated; both blank fails.                                     | [Either/or field](docs/examples/formula/02-either-or-field.md)                                     |
| 2   | At least one Contact                  | Single query        | The Account must have one or more related Contacts (`COUNT()` vs a fixed threshold).                      | [Child count minimum one](docs/examples/query/01-child-count-minimum-one.md)                       |
| 3   | Billing matches Shipping              | Record formula      | When Shipping City is set, Billing City must match; Accounts with no Shipping City are skipped.           | [Two fields compared](docs/examples/formula/05-two-fields-compared.md)                             |
| 4   | High-value open Opportunity           | Single query        | At least one open Opportunity must exceed a fixed Amount threshold.                                       | [Any row static threshold](docs/examples/query/05-any-row-static-threshold.md)                     |
| 5   | Partner Accounts need Billing Country | Record formula      | Billing Country is required only when Account Type is Partner; other types are skipped.                   | [Type-scoped rule](docs/examples/formula/06-type-scoped.md)                                        |
| 6   | Contact count vs open Opportunities   | Compare two queries | Contact count must not exceed the count of open Opportunities on the same Account.                        | [Two aggregate counts](docs/examples/compare-two-queries/01-aggregate-counts.md)                   |
| 7   | Child cities covered by parent        | Compare two queries | Every Contact Mailing City on a child Account must appear on the parent Account's Contacts.               | [List contains all](docs/examples/compare-two-queries/05-list-contains-all.md)                     |
| 8   | Recent Task or Event activity         | Custom Apex         | At least one completed Task or logged Event within a configurable look-back window.                       | [Recent activity](docs/examples/apex/01-recent-activity.md)                                        |
| 9   | Strategic account readiness score     | Custom Apex         | Strategic Accounts get one weighted readiness score (contacts, pipeline, activity, billing) vs a minimum. | [Strategic readiness](docs/examples/apex/03-strategic-readiness.md)                                |
| 10  | Open pipeline vs Account target       | Compare two queries | Sum of open Opportunity Amount is compared to a target field on the Account.                              | [Aggregate vs Account scalar](docs/examples/compare-two-queries/02-aggregate-vs-account-scalar.md) |

**Check method spread:** Record formula (3) · Single query (2) · Compare two queries (3) · Custom Apex (2)

The repo includes **10 sample Check Sets and 88 Rules** for Account. Deploy [core plus individual manifests](docs/examples/index.md#sample-check-set-packages) or the full `package.xml`. Full catalog: [docs/examples/index.md](docs/examples/index.md).

## Quick Start

The fastest path is the **[Deploy to Salesforce](https://githubsfdeploy.herokuapp.com/?owner=gkolan&repo=recordHealthCheck&ref=main)** button at the top of this page. Click it, log in to a **sandbox**, and click Deploy. No command line, no downloads.

The button installs the latest `main`. To pin a specific release, change `ref=main` to a release tag (for example `ref=v1.0.0`) in the button's link. A click-by-click walkthrough is in [Install in your sandbox](docs/installation/sandbox.md).

Prefer the CLI? Deploy the source directly:

```bash
git clone https://github.com/gkolan/recordHealthCheck.git
cd recordHealthCheck
sf project deploy start --source-dir force-app
sf org assign permset --name Record_Health_Check_User
```

No CLI and no button access? Deploy `force-app` through a change set, DevOps Center, or your deployment tool of choice. After deploying, follow [Getting Started](docs/installation/getting-started.md) to add the card and create your first Rule.

### Add the card to a page

On a Lightning **record page**, drag on the **recordHealthCheck** component and set its **Check Set Developer Name** property to a Check Set's Developer Name, for example `Account_Data_Quality`. It must match exactly; a mismatch is the single most common misconfiguration. Save and activate, then open a record to see the card evaluate it.

The component runs only on record pages, because it needs the current record's Id. It will not run on App or Home pages.

## How it works

Two Custom Metadata types drive everything:

- A **Check Set** (`Record_Health_Check_Set__mdt`) is one panel on one object. It holds display and run settings and groups Rules.
- A **Rule** (`Record_Health_Check_Rule__mdt`) is one individual check. Its **Check Method** picks the evaluator (`Formula`, `Query`, `CompareTwoQueries`, or `Apex`), and its other fields supply the query, comparison, applicability gate, dependency, severity, and messages.

You wire a Check Set's **Developer Name** into the component property on the record page. At read time the component loads the active Rules for that Check Set, evaluates each one, and renders the results. Because the component only reads records, deploying or changing a Check Set can never corrupt data.

The deep reference for every field, picklist value, and evaluator is the [Configuration Guide](docs/guides/configuration-guide.md), with the formal contract in the [Design Specification](docs/reference/record-health-check-design-spec.md).

## Technical snapshot

| Topic               | Detail                                                                                                           |
| ------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Metadata types      | `Record_Health_Check_Set__mdt`, `Record_Health_Check_Rule__mdt`                                                  |
| Sample Check Sets   | 10 sets, 88 Rules for Account ([install manifests](docs/examples/index.md#sample-check-set-packages))            |
| Project API version | 66.0 (`sfdx-project.json`); Formula checks require org **v63.0+**                                                |
| Run limits          | 25 active Rules per Check Set per run; up to 5 concurrent Apex evaluations from the LWC                          |
| Programmatic API    | `RecordHealthCheck.run(checkSetDevName, ruleDevName, recordId)` (no packaged Flow invocable)                     |
| Permission sets     | `Record_Health_Check_User`, `Record_Health_Check_Admin`                                                          |
| Formal contract     | [Design Specification](docs/reference/record-health-check-design-spec.md) · [split by topic](docs/spec/index.md) |

## Going further

Two optional paths once the basics are in place: let an AI assistant author the metadata, or call the engine from your own Apex.

### Configure checks with an AI assistant

You do not have to memorize every Custom Metadata field. The [LLM Configuration Guide](docs/guides/llm-configuration.md) is written to be pasted into ChatGPT, Gemini, Cursor, or a similar tool so the model can turn a business rule into correct Check Set and Rule records.

1. Copy the **system prompt** from Section 2 of the guide into your assistant.
2. Optionally attach the same file plus the [Configuration Guide](docs/guides/configuration-guide.md) and [Examples index](docs/examples/index.md) as reference.
3. Describe what you want in plain language: object, fields, what pass and fail mean, and whether zero related rows should pass, fail, or skip.
4. Ask for output using the **Section 4 template** (summary, Check Set table, Rule table, pattern citation). Tables must use **API field names** (`CheckMethod__c`, `PassFailFormula__c`, …), not Setup labels alone.
5. In Salesforce, create or edit records under **Setup → Custom Metadata Types → Record Health Check Set / Record Health Check Rule** to match the tables, then wire the Check Set Developer Name onto the record page.
6. Refresh and run. If something fails, compare against a [sample Check Set](docs/examples/index.md#sample-check-set-packages) or use [Troubleshooting](docs/guides/configuration-guide.md#13-troubleshooting).

Checks are advisory: if an assistant proposes blocking a save, use a validation rule or Flow for that instead.

### Run a check from Apex

The same engine is callable directly. `RecordHealthCheck.run` evaluates one Rule against one record and returns a structured result:

```apex
RecordHealthCheckResult r = RecordHealthCheck.run(
    'Account_Data_Quality',   // Check Set Developer Name
    'Account_DQ_BillingCity',  // Rule Developer Name
    accountId);

if (r.status == 'FAIL') {
    // r.message, r.reasonCode, r.actualValue, r.expectedValue, r.durationMs, …
}
```

Catchable failures come back as structured statuses (`FAIL`, `ERROR`, `UNABLE_TO_EVALUATE`, …); uncatchable governor-limit exceptions behave as they do anywhere in Apex. An optional overload accepts a custom run id for log correlation. Full contract: [Programmatic API in the design specification](docs/reference/record-health-check-design-spec.md#13-programmatic-api-recordhealthcheck).

There is **no packaged Flow invocable** in this release; it was descoped for governor safety. To call the engine from Flow, build a bulk-designed Apex invocable that groups records and evaluates them within transaction limits, or drive it from scheduled/batch Apex with an intentionally small scope. Do not wrap `run(...)` in a per-record loop.

## Documentation

Full documentation lives under `docs/`. Start with the pages below, then browse by folder.

| Document                | Path                                                                                                                                      |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Install in your sandbox | [`docs/installation/sandbox.md`](docs/installation/sandbox.md)                                                                            |
| Getting Started         | [`docs/installation/getting-started.md`](docs/installation/getting-started.md)                                                            |
| Configuration Guide     | [`docs/guides/configuration-guide.md`](docs/guides/configuration-guide.md)                                                                |
| Examples catalog        | [`docs/examples/index.md`](docs/examples/index.md)                                                                                        |
| Custom Metadata fields  | [`docs/metadata/index.md`](docs/metadata/index.md)                                                                                        |
| Debug Mode              | [`docs/guides/debug-mode.md`](docs/guides/debug-mode.md)                                                                                  |
| LLM Configuration Guide | [`docs/guides/llm-configuration.md`](docs/guides/llm-configuration.md)                                                                    |
| Apex plugin reference   | [`docs/apex/plugin-reference.md`](docs/apex/plugin-reference.md)                                                                          |
| Design Specification    | [`docs/reference/record-health-check-design-spec.md`](docs/reference/record-health-check-design-spec.md) · [by topic](docs/spec/index.md) |
| Architecture Map        | [`docs/reference/architecture-map.md`](docs/reference/architecture-map.md)                                                                |

Browse by folder: [`installation/`](docs/installation/) · [`guides/`](docs/guides/) · [`metadata/`](docs/metadata/) · [`apex/`](docs/apex/) · [`examples/`](docs/examples/) · [`reference/`](docs/reference/) · [`spec/`](docs/spec/)

## Development & contributing

For working on the framework itself rather than configuring checks in an org. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for documentation authoring standards.

### Repository layout

| Path                                     | Purpose                                                        |
| ---------------------------------------- | -------------------------------------------------------------- |
| `docs/`                                  | All user and technical documentation                           |
| `force-app/main/default/`                | Salesforce metadata and Apex                                   |
| `force-app/main/default/permissionsets/` | `Record_Health_Check_User`, `Record_Health_Check_Admin`        |
| `manifest/package.xml`                   | Full package manifest (wildcard; core + all sample Check Sets) |
| `manifest/package-core.xml`              | Engine, schema, LWC, and permissions only (generated)          |
| `manifest/package-<CheckSet>.xml`        | One sample Check Set and its Rules (10 files; generated)       |

### Local checks

```bash
npm run lint
npm test                    # 61 Jest tests
npm run test:unit:coverage  # enforces LWC coverage thresholds
npm run prettier:verify
```

Apex tests run against a Salesforce org target. See [CONTRIBUTING.md](CONTRIBUTING.md).

### Community & policies

- [Contributing](CONTRIBUTING.md) walks through reporting a bug, requesting a feature, and opening a pull request.
- [Releasing](RELEASING.md) explains how versioned releases are cut.
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security policy](SECURITY.md)
- [Changelog](CHANGELOG.md)

Created and maintained by [Gautam Kolan](https://github.com/gkolan). Project home: [github.com/gkolan/recordHealthCheck](https://github.com/gkolan/recordHealthCheck).

Licensed under the [Apache License, Version 2.0](LICENSE). See [NOTICE](NOTICE) for attribution.
