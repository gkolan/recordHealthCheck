# Install Record Health Check in your sandbox

This guide installs Record Health Check into a Salesforce **sandbox** with no coding and no command line.

> [!NOTE]
> **What is a "sandbox"?** A sandbox is a safe copy of Salesforce for testing. Nothing you
> do here touches real customer data or your live (production) org. It is the right place to
> try something new.

## Before you start

You need:

- **A Salesforce sandbox you can log in to** (whoever provisions sandboxes in your org can create one).
- **Permission to customize pages and Setup** in that sandbox: typically **Customize Application** on your profile.
- **Who runs the Deploy button:** the person clicking **Deploy to Salesforce** must be able to install Apex into the target org (deploy tools may require **Author Apex** on that user's profile).
- **Do not close the browser tab partway through the deploy.**

Right after install, **Step 4** assigns the **Record Health Check User** permission set so you can run the card: that is separate from deploy permissions.

You do **not** need: the Salesforce CLI, Git, VS Code, or any download.

## Step 1: Click the Deploy button

On the project's main page (the [README](../../README.md)), find the button that says
**Deploy to Salesforce** and click it.

It opens a website called **githubsfdeploy**. This is a well-known, free tool that copies
the project's files into a Salesforce org for you. It does not see your data: it only
installs the component.

## Step 2: Log in to your sandbox

The deploy page asks you to log in.

1. Click **Login to Salesforce**.
2. Log in to the **sandbox**, not production: the login page should say **test.salesforce.com** at the top, or pick the **Sandbox** option
   if it asks. If only production login appears, request the sandbox login URL from whoever manages sandboxes
   (it usually ends in `.sandbox.my.salesforce.com`).
3. Enter your sandbox username and password and approve any verification prompt.

> [!WARNING]
> **Safety check:** If you are ever unsure whether you are in production or sandbox, **stop
> and confirm with the org owner.** It is always safe to install into a sandbox; only install into
> production after the org has reviewed it.

## Step 3: Click Deploy and wait

1. After logging in you will see a page listing the components to install (Apex classes, a
   Lightning component, Custom Metadata Types, and sample data). You do not need to
   understand each line.
2. Click **Deploy**.
3. Wait until the deploy finishes and you see a green **success** message.

If you see a red error message instead, take a screenshot and send it to whoever shared this
project with you, or see [Troubleshooting](#if-something-goes-wrong) below.

**What the deploy installed:**

- The **recordHealthCheck** card you can add to a record page
- Setup areas for **Check Sets** and **Rules** (the things you configure)
- **Sample checks** (10 Check Sets and 88 Rules, all on the Account object) so you have something
  to look at immediately
- Two **permission sets** that control who can use it

## Step 4: Give yourself permission to use it

Installing the files is not enough: Salesforce also needs to grant you permission to run
the card.

1. In your sandbox, click the **gear icon** (top right) → **Setup**.
2. In the **Quick Find** box on the left, type **Permission Sets** and click it.
3. Click **Record Health Check User**.
4. Click **Manage Assignments** → **Add Assignment**.
5. Check the box next to **your own name**, then click **Assign** → **Done**.

> Two permission sets were installed. **`Record_Health_Check_User`** is enough to run the card. **`Record_Health_Check_Admin`** adds troubleshooting (`Record_Health_Check_Debug`). See [Getting Started: Step 1b](getting-started.md#step-1b-assign-permission-sets).

## Step 5: Add the card to a page and see it work

1. Open any **Account** record in your sandbox (Accounts tab → click any account; create one
   if the sandbox is empty).
2. Click the **gear icon** (top right) → **Edit Page**. This opens the Lightning App Builder.
3. On the left, find **recordHealthCheck** in the component list and **drag it** onto the
   page (a sidebar or the main area both work).
4. With the card selected, look at the right-hand panel. In the **Check Set Developer Name**
   box, type exactly:

   ```text
   Account_Data_Quality
   ```

   This must match **exactly**: it is case-sensitive. It is the name of one of the sample
   Check Sets that came with the install.
5. Click **Save**. If it asks you to **Activate**, click **Activate** and accept the
   defaults.
6. Click **Back** to return to the Account.

You should now see a **Record Health Check** card showing a list of checks with green
(passed) and red (failed) results.

That is the whole product. Everything else is configuring your own checks.

## What to do next

You now have a working installation. To start building your own checks:

| You want to… | Go to |
| ------------ | ----- |
| Understand the basics and build your first check | [Getting Started](getting-started.md) |
| Draft checks with an AI assistant | [LLM Configuration Guide](../guides/llm-configuration.md) |
| Copy ready-made examples | [Examples](../examples/index.md) |
| See every setting explained in plain language | [Configuration Guide](../guides/configuration-guide.md) |

## If something goes wrong

| What you see | What it usually means | What to do |
| ------------ | --------------------- | ---------- |
| The deploy page shows a **red error** | A component could not install (often a permissions or API-version issue) | Take a screenshot and send it to the person who shared this project. Note: **Formula** checks need org API **v63.0 or later** (Spring '25). |
| Install succeeded but **you don't see the card** on the page | The card was not added, or the Check Set name is wrong | Re-check **Step 5**. The **Check Set Developer Name** must be exactly `Account_Data_Quality`. |
| You see the card but it says you **don't have access** | The permission set is not assigned | Go back to **Step 4** and confirm **Record Health Check User** is assigned to you. |
| You logged in and it deployed to the **wrong org** | You logged in to production or a different sandbox by mistake | The component is harmless and changes no data, but to remove it, contact whoever manages that org. Next time, double-check the login URL in **Step 2**. |

More detailed help: [Configuration Guide: Troubleshooting](../guides/configuration-guide.md#13-troubleshooting).
