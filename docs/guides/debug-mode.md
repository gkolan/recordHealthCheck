# Debug Mode: Troubleshooting Guide

Debug Mode shows extra technical detail on the health check card and in the browser console. It is for troubleshooting only: leave it **off** on production Check Sets when not actively investigating a problem.

Debug Mode does **not** save history and does **not** write any records: it only adds on-screen and console detail for the current run.

> [!WARNING]
> Turning on **Debug Mode** on the Check Set alone does **nothing** visible. Both the Check Set flag **and** the `Record_Health_Check_Debug` permission are required.

## Both steps are required

| Step | What to do | Where in Setup |
| ---- | ---------- | -------------- |
| **1. Check Set** | Check **Debug Mode** | **Custom Metadata Types** → **Record Health Check Set** → open your Check Set → **Debug Mode** (`DebugMode__c`) |
| **2. User** | Assign permission set `Record_Health_Check_Admin` | **Permission Sets** → open `Record_Health_Check_Admin` → **Manage Assignments** → add the troubleshooting user |

Step 2 grants the **`Record_Health_Check_Debug`** custom permission. That permission is what unlocks debug output on the card.

### Permission sets: which one unlocks debug detail?

| API name | Setup label | Debug Mode detail? |
| -------- | ----------- | ------------------ |
| `Record_Health_Check_User` | Record Health Check User | **No**: can run the card, but sees only normal pass/fail messages |
| `Record_Health_Check_Admin` | Record Health Check Admin | **Yes**: includes `Record_Health_Check_Debug` |

If you checked Debug Mode on the Check Set but still see a normal card, the most common cause is missing **`Record_Health_Check_Admin`** on the viewing user.

After changing the Check Set or permission set assignment, **refresh the record page**.

## What you see on the health check card

After you **run** the checks (automatic or manual), and only when both steps above are complete:

| What | Description |
| ---- | ----------- |
| **Gray line under each result** | Compact summary, for example `FAIL · FORMULA_FALSE · 38ms · Formula`: status, reason code, time taken, Check Method (API value) |
| **Debug detail** | On checks that errored or could not run, a **Debug detail** block showing the technical message inline (SOQL problems, missing field access, and similar) — no need to click to expand it |
| **Found / Expected** | On failing checks, labelled chips when the engine captured values (visible to all users on failures: not unique to debug mode) |
| **Console hint** | Small footnote at the bottom of the card: **Check console (F12) for diagnostics.** |

Users **without** `Record_Health_Check_Debug` never see the gray lines, Debug detail panels, or the console hint: even when Debug Mode is checked on the Check Set. This is intentional so technical detail is not exposed to everyday users.

## What you see in the browser console

1. Open a record page that has the health check card.
2. Press **F12** (Windows/Linux) or open **Developer Tools** (Mac) and select the **Console** tab.
3. Run the health checks on the card.
4. When the run finishes, find a group titled **`[RHC] Health Check run …: config Your_Check_Set_Name …`** (the **config** segment is the **Check Set Developer Name** from App Builder: use it to tell multiple health check cards apart on the same page).

Inside that group you will see:

- **Full run summary**: run id, your user id, record id, check set name, timestamp, and a list of every check with status, reason code, severity, found/expected values, duration, and evaluator type.
- **Table view**: the same per-check data in a tabular layout.

Use the **run id** to match lines in **Setup → Debug Logs** when Apex logging is enabled for your user.

## Checklist

- [ ] **Debug Mode** checked on the **same** Check Set the component uses (App Builder **Check Set Developer Name** must match).
- [ ] **`Record_Health_Check_Admin`** assigned to the user viewing the page.
- [ ] Record page **refreshed** after metadata or permission changes.
- [ ] Checks **run** to completion (debug detail appears after the run, not on first load while rows are still pending).
- [ ] **Debug Mode turned off** on production Check Sets when troubleshooting is finished.

## Related documentation

| Document | Use when |
| -------- | -------- |
| [Getting Started: permission sets](../installation/getting-started.md#step-1b-assign-permission-sets) | First install and assigning permission sets |
| [Configuration Guide: Check Set fields](../guides/configuration-guide.md#3-check-set-fields) | Every Check Set field explained |
| [Configuration Guide: Troubleshooting](../guides/configuration-guide.md#13-troubleshooting) | When a check fails or cannot run |
