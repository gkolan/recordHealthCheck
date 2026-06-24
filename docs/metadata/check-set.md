# Check Set fields (`Record_Health_Check_Set__mdt`)

Parent metadata record for one health-check panel on a record page. The Lightning component points at a Check Set through **Check Set Developer Name** (`configName`).

> [!NOTE]
> This reference is the source of truth for Check Set fields. Guides and examples link here rather than restating these values.

Walkthroughs: [Configuration Guide](../guides/configuration-guide.md). Troubleshooting: [Debug Mode](../guides/debug-mode.md).

## Field reference

### Identity and display

| Setup label | API name | Type | Required | Description |
| ----------- | -------- | ---- | -------- | ----------- |
| Developer Name | `DeveloperName` | Text | Yes | API key the Lightning component uses (`configName`). Stable link between the page and metadata; survives label changes. |
| Label | Master Label | Text | Yes | Name shown in Setup record lists. Standard metadata identity; not shown to end users in the component. |
| Display Title | `PanelHeading__c` | Text | Yes | Card header title (for example, `Account Health Check`). Required on the Custom Metadata Type; enforced by the validator. Runtime definition load does not reject a blank value. |
| Display Description | `PanelSubheading__c` | Text | No | One-line subtitle beneath the title row (full card width). Brief context without opening each Rule. |

### Scope

| Setup label | API name | Type | Required | Description |
| ----------- | -------- | ---- | -------- | ----------- |
| Base Object API Name | `ObjectApiName__c` | Text | Yes | Object API name (for example, `Account`). Prevents running Account checks on Contact pages. Must match the record page object. Blank value causes `CONFIG_NOT_FOUND` at definition load. |
| Active | `IsActive__c` | Checkbox | No | When unchecked, the Check Set does not load. Defaults to checked. Disable a configuration without deleting Rules or removing the component. |

### Run behavior

| Setup label | API name | Type | Required | Description |
| ----------- | -------- | ---- | -------- | ----------- |
| Run Checks When | `RunChecksWhen__c` | Picklist | Yes | `Automatic`: run after page load. `Manual`: wait for **Run** / **Rerun**. While checks run the button shows a spinner; the label stays **Run** (first run) or **Rerun** (after any completed run), never "Running…". Busy detail is in `title` / `aria-label`. See [picklist values](#run-checks-when-runcheckswhen__c). |
| Reveal Mode | `RowAppearance__c` | Picklist | Yes | `AllAtOnce`: eligible rows visible immediately. `OneAtATime`: rows appear as the run progresses. Rows hidden by Passed/Skipped display modes stay hidden in both modes. |
| Stop On First Error | `StopOnSystemError__c` | Checkbox | No | Stops remaining checks after the first `ERROR` status and runs checks sequentially (one Apex call at a time). Does **not** stop on `FAIL`, `SKIPPED`, or `UNABLE_TO_EVALUATE`. |

### Result presentation

| Setup label | API name | Type | Required | Description |
| ----------- | -------- | ---- | -------- | ----------- |
| Passed Checks Display | `PassedChecksDisplay__c` | Picklist | Yes | `Show` or `Hide` for passed rows. When hidden, rows disappear from the list but the **Passed** summary pill still shows the count (hover for rule labels). |
| Skipped Checks Display | `SkippedChecksDisplay__c` | Picklist | Yes | Same options for `SKIPPED` rows. Skipped rows collapse into the **Skipped** summary pill. |
| Debug Mode | `DebugMode__c` | Checkbox | No | When checked **and** the viewer has **`Record_Health_Check_Debug`** (from permission set `Record_Health_Check_Admin`), shows extra troubleshooting detail on the card and in the browser console. Does **not** affect what regular users see. Walkthrough: [Debug Mode](../guides/debug-mode.md). |

### Framework limits (not fields)

- **25 active Rules maximum** per run (lowest **Priority** first, then `DeveloperName`). When Rules are omitted, the header shows a **“First 25 shown”** badge. Apex also returns `totalAvailableCheckCount`, but the component does not display that number today.
- **Metadata reload:** `getCheckDefinitions` is not cacheable. Reload the page to pick up metadata edits. After the component connects, a change to `recordId` also reloads definitions (for example, navigating to a different record on the same page).
- **Concurrency:** up to **5** in-flight `evaluateCheck` calls when Stop On First Error is unchecked (remaining checks queue client-side; up to 25 Rules may be scheduled per run). When Stop On First Error is checked, checks run sequentially (one Apex call at a time).
- **Dependencies outside the cap:** if a prerequisite Rule is among the omitted Rules, dependents are skipped with reason `DEPENDENCY_NOT_IN_RUN` (LWC only; this reason code is not emitted by Apex).

## Picklist values

### Run Checks When (`RunChecksWhen__c`)

| Value (API) | Setup label | Behavior |
| ----------- | ----------- | -------- |
| `Automatic` | Run automatically when the page opens | Checks run when the page loads (after a short deferral). |
| `Manual` | Wait for the user to click Run | User clicks **Run**. Use for expensive checks. |

### Passed and Skipped Checks Display (`PassedChecksDisplay__c`, `SkippedChecksDisplay__c`)

| Value (API) | Setup label | Behavior |
| ----------- | ----------- | -------- |
| `Show` | Show each row | Rows stay in the list. |
| `Hide` | Hide rows, show count only | Rows hidden from the list. After the run completes, counts appear in the summary bar pill for that outcome (**Passed** or **Skipped**). Hover or keyboard-focus the pill to see the rule labels. |

Use `Hide` on Check Sets like `Account_Data_Quality` when a failures-only row list is needed but an at-a-glance pass count in the summary bar is still required.

### Reveal Mode (`RowAppearance__c`)

| Value (API) | Behavior |
| ----------- | -------- |
| `AllAtOnce` | Eligible rows appear immediately (pending, loading, or done). Rows hidden by Passed or Skipped display modes are still hidden. |
| `OneAtATime` | Eligible rows appear as the ordered run advances. |

## See also

- [Rule fields](rule-fields.md)
- [Configuration Guide](../guides/configuration-guide.md)
- [Design Specification](../reference/record-health-check-design-spec.md)
