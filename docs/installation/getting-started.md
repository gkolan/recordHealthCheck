# Getting Started

**You need:** Permission to edit Lightning record pages and manage Custom Metadata in Setup (typically **Customize Application** on your profile or permission set).  
**You do not need:** Apex, Flow, or command-line tools to complete this guide.

This guide gets Record Health Check running on a Salesforce org and walks you through your first working check.

> [!NOTE]
> **Setup labels vs API names:** Tables below show **Setup label** (what you click) and **API name** (what metadata XML and the LLM guide use). You only need the Setup column to configure checks in the UI.

## What you are building

Record Health Check adds a **card** to a record page (for example, an Account page). The card runs a list of **Rules** you define in Setup and shows whether each Rule passed, failed, was skipped, or could not run.

You configure two record types in **Setup → Custom Metadata Types**:

| Plain name | Setup name | API type | One sentence |
| ---------- | ---------- | -------- | ------------ |
| **Check Set** | Record Health Check Set | `Record_Health_Check_Set__mdt` | The panel: which object it runs on, when it runs, and how results display |
| **Rule** | Record Health Check Rule | `Record_Health_Check_Rule__mdt` | One check inside that panel (for example, “Billing City must not be blank”) |

The card does **not** block saves or change field values. It only **shows** health information.

## Prerequisites

- A Salesforce org where you can customize Lightning pages and edit Custom Metadata
- For **Record formula** checks (`CheckMethod__c` = `Formula`): org API **v63.0 or later** (Spring ’25). If you are unsure, use **Single query** checks instead: they work on older API versions.
- A way to deploy the package (see Step 1). **Option A** (CLI) deploys from the repository; **Option B** (metadata deploy through your org's normal process) works if you do not use the CLI.

> [!IMPORTANT]
> **API version:** The project ships at API **66.0** (`sfdx-project.json`). The v63.0 minimum applies to **FormulaEval** on the org, not the deploy package version.

After deployment, assign permission sets so users can run the component (see Step 1b).

## Step 1: Deploy the package

### Option A: Salesforce CLI

From the repository root:

**Clean install (recommended)** — the framework only, with no sample or example Check Sets. Best for production orgs:

```bash
sf project deploy start --manifest manifest/package-core.xml
```

Then add only the sample Check Sets you actually want, one manifest at a time:

```bash
sf project deploy start --manifest manifest/package-Account_Data_Quality.xml   # example: 4 formula rules
```

See [Sample Check Set packages](../examples/index.md#sample-check-set-packages) for all set manifests. The `Account_Examples_*` sets are teaching material — deploy them in a sandbox or scratch org to learn from, and leave them out of production.

**Full deploy** — the framework plus _every_ sample and example Check Set. Convenient for a scratch or dev org where you want the examples on hand:

```bash
sf project deploy start --source-dir force-app
```

Or via the catch-all manifest (it uses wildcards, so it also pulls in every sample and example record):

```bash
sf project deploy start --manifest manifest/package.xml
```

### Option B: Without the CLI

For a clean install, deploy `manifest/package-core.xml` first (framework only, no examples), then add individual `manifest/package-<CheckSet>.xml` files for any sample sets you want (see [Sample Check Set packages](../examples/index.md#sample-check-set-packages)). To get everything at once — examples included — deploy the `force-app` folder or `manifest/package.xml` through your org’s normal process: change set, DevOps Center, Copado, etc.

### After deployment you will have

- The **recordHealthCheck** Lightning component
- Custom Metadata Types for Check Sets and Rules
- The sample Check Sets and Rules you chose to deploy — none with the clean install; a full deploy adds all **10 sample** Check Sets (88 Rules) plus **4 example** Check Sets (34 Rules), all on Account, which you can copy or turn off
- Two permission sets (assign in Step 1b)

### Step 1b: Assign permission sets

Users need Apex access to run the component. Assign the least-privilege permission set that matches what they need:

| API name | Setup label | Assign when |
| -------- | ----------- | ----------- |
| `Record_Health_Check_User` | Record Health Check User | Run the card on record pages (no debug detail) |
| `Record_Health_Check_Admin` | Record Health Check Admin | Troubleshooting: includes `Record_Health_Check_Debug`. Required for [Debug Mode](../guides/debug-mode.md). |

In **Setup → Permission Sets**, open the set → **Manage Assignments** → **Add Assignments**.

`Record_Health_Check_User` grants Apex class access to `RecordHealthCheckController` and `RecordHealthCheck` only. It does **not** grant debug detail.

**Verify assignment (release gate):** After assigning `Record_Health_Check_User`, open an Account on a page with the component and confirm checks run with pass/fail rows only: no **Debug detail** expander and no `[RHC]` console block. Assign `Record_Health_Check_Admin` only when you need Debug Mode (see below).

**Debug Mode:** If you enable **Debug Mode** on a Check Set, you must also assign `Record_Health_Check_Admin` to see the extra lines on the card and console output. See [Debug Mode guide](../guides/debug-mode.md).

## Step 2: Add the component to a record page

1. Open **Setup → Lightning App Builder**.
2. Edit an **Account** record page (or whichever object matches your Check Set).
3. Drag **recordHealthCheck** onto the page.
4. In the component properties on the right, set **Check Set Developer Name** (`configName`) to the exact Developer Name of a Check Set, for example:

   ```text
   Account_Data_Quality
   ```

   This value is **case-sensitive** and must match the Check Set’s Developer Name in Setup: not the display title users see on the card.

5. **Save** and **Activate** the page. Assign the page to the right app and profiles if prompted.

The component only works on **record pages** because it needs the current record’s Id.

## Step 3: Verify with a sample Check Set

1. Open any Account on the page you edited.
2. If the Check Set **Run Checks When** (`RunChecksWhen__c`) is **Run automatically when the page opens**, checks run after the page loads. If it is **Wait for the user to click Run**, click **Run** on the card.
3. If the component is configured correctly, you will see a health check card with Rule rows and pass/fail results. When a Rule **fails**, look beneath the failure message for **Found** / **Expected** labelled chips (Query and Compare Two Queries checks) that show what the record produced versus what the rule required: no extra configuration needed. If you do not see the card at all, see [Configuration Guide: Troubleshooting](../guides/configuration-guide.md#13-troubleshooting).

**To view the sample configuration in Setup**

1. **Setup → Custom Metadata Types**
2. Next to **Record Health Check Set**, click **Manage Records**
3. Open `Account_Data_Quality`
4. Next to **Record Health Check Rule**, click **Manage Records** to see its Rules

## Step 4: Create your first Rule

The simplest Rule is a **Record formula** check: Billing City must not be blank.

1. **Setup → Custom Metadata Types → Record Health Check Rule → Manage Records → New**
2. Fill in:

   | Setup label | API name | Value |
   | ----------- | -------- | ----- |
   | Developer Name | `DeveloperName` | `My_Billing_City_Required` |
   | Label | Master Label | `Billing City Required` |
   | Check Name | `CheckName__c` | `Billing City Required` |
   | Check Set | `Record_Health_Check_Set__c` | Your Check Set |
   | Run Order | `RunOrder__c` | `100` (lower numbers run first) |
   | Active | `IsActive__c` | Checked |
   | Check Method | `CheckMethod__c` | `Record formula` |
   | Pass/Fail Formula | `PassFailFormula__c` | `NOT(ISBLANK(BillingCity))` |
   | Run This Check When | `RunThisCheckWhen__c` | `Always` |
   | Severity | `Severity__c` | `Error` |
   | Message When Failed | `MessageWhenFailed__c` | `Billing City is required.` |

3. **Save**, refresh the Account record page, and confirm the new Rule appears.

> [!TIP]
> To draft Rules faster, use the [LLM Configuration Guide](../guides/llm-configuration.md): ask for Section 4 tables, then copy values into Setup.

After you edit Check Set or Rule metadata in Setup, **refresh the record page** to load the changes.

For more patterns, see [Formula checks: example 1](../examples/formula/01-single-required-field.md).

## Step 5: Before go-live

Use the [Review Checklist](../guides/configuration-guide.md#14-review-checklist) in the Configuration Guide. At minimum:

- Check Set **Developer Name** matches the component property **exactly**
- **Base Object API Name** on the Check Set matches the record page object (for example, `Account`)
- **Debug Mode** is **unchecked** in production (troubleshooting only)

## Optional: Run a check from Apex

You do not need the record-page card to evaluate a single Rule:

- **Apex:** `RecordHealthCheck.run('My_Check_Set', 'My_Rule', recordId)`

The packaged Flow invocable action is **not included**. Call `RecordHealthCheck.run`
from a bulk-designed Apex invocable that groups records and evaluates them within
transaction limits, or from scheduled/batch Apex with an intentionally small scope.
Keep it out of a per-request loop, which multiplies governor cost.

Details: [Design Specification 13](../reference/record-health-check-design-spec.md#13-programmatic-api-recordhealthcheck).

## Next steps

| Goal | Document |
| ---- | -------- |
| Draft checks with AI | [LLM Configuration Guide](../guides/llm-configuration.md) |
| Understand every field | [Configuration Guide: field reference](../guides/configuration-guide.md#3-check-set-fields) |
| Copy working examples | [Examples index](../examples/index.md) |
| Review runtime contract | [Design Specification](../reference/record-health-check-design-spec.md) |
| Navigate source code | [Architecture Map](../reference/architecture-map.md) |
| Fix a failure | [Configuration Guide: troubleshooting](../guides/configuration-guide.md#13-troubleshooting) |
