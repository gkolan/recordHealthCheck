> [!NOTE]
> **Canonical source:** Section numbers and anchors in the [full design specification](../reference/record-health-check-design-spec.md) are stable for cross-links.

## 15. LWC Behavior

The `recordHealthCheck` bundle (`recordHealthCheck.js`, `healthCheckRunner.js`,
`healthCheckModel.js`, `healthCheckPresentation.js`) orchestrates definition load,
run lifecycle, and display. Presentation logic that LWC templates cannot express
lives in `healthCheckPresentation.js`.

### Lifecycle and run control

- Loads definitions once when inserted (deferred one macrotask so Automatic does not fire during initial mount).
- Reloads definitions when `recordId` or `configName` changes after the initial connect. On reload, invalidates any in-flight run (`_runToken` bump, run-state reset) so stale results cannot bleed across records (H1).
- Runs automatically for `Automatic` Check Sets; shows **Run** for `Manual`.
- Shows **Rerun** after any run completes (including Automatic). While a run is in flight the action button stays visible, is **disabled**, keeps **Run** on the first run or **Rerun** on later runs (see `hasCompletedRunOnce` below), and shows a **spinner** in place of the play glyph (it does not disappear or relabel to "Running…").
- Runs at most **5** `evaluateCheck` calls concurrently when `StopOnSystemError__c` is false; runs **sequentially** when `StopOnSystemError__c` is true.
- Reveals rows in priority order via a drain buffer.
- Enforces `RequiresCheck__c` client-side before calling Apex.
- Pre-seeds circular dependencies as `UNABLE_TO_EVALUATE` / `CIRCULAR_DEPENDENCY` without calling Apex.
- Discards stale results from prior runs via `_runToken`.
- Stores runtime state only in the component instance.

**Run-state flags (regression guard)**

| Flag | Set `true` when | Cleared when | Drives |
| ---- | --------------- | ------------ | ------ |
| `runComplete` | All checks in the current run have been revealed | A new run starts (`healthCheckRunner.run`) or definitions reload | Summary bar visibility, pre-run hint, debug diagnostics, `showRerunButton` |
| `hasCompletedRunOnce` | A run finishes (including zero-check sets) | Definitions reload (`recordId` / `configName` change) | Action button **visible label** (`Run` vs `Rerun`) and busy `title` / `aria-label` while a run is in flight |

`runComplete` clears at the start of every run so the summary bar hides during evaluation. **`hasCompletedRunOnce` must not clear when a re-run starts**: otherwise the button relabels to **Run** + spinner instead of **Rerun** + spinner.

**Not supported today:** automatic re-run on record save.

### Card chrome and header

- Renders as a custom card (`rhc-card`) with a visible border and elevation: not `slds-card`: so it reads as a contained panel on white Lightning tabs.
- **Rounded corners** match standard Lightning cards: `border-radius: var(--lwc-borderRadiusMedium, 0.25rem)`. The card uses **`overflow: visible`** so row and summary tooltips are **not clipped** at the card boundary (especially the last row's below-row bubble). Bottom corner rounding is applied to **`.rhc-body > :last-child`** so the outline still matches standard Lightning related lists and record panels without trapping popovers.
- **No header icon**: the card does not render a header icon. There is no icon field on the Check Set; titles are text-only.
- Header layout: **title** and **action button** share one row (vertically centered); **Display Description** spans the full width on the row beneath (eliminates a tall empty column beside a short button).
- Shows a **First 25 shown** badge when `checksOmittedByLimit` is true (does not show `totalAvailableCheckCount`).

### Row status accent

- Each resolved row carries a **3px-wide status accent** on the left edge, coloured by outcome (pass / fail / warning / info / skipped / unable).
- The accent is a dedicated **`.rhc-row__accent` element** (`position: absolute; left: 0; top: 0; bottom: 0; width: 3px`) so it spans the full row height flush to the card's left inner edge and renders reliably in LWC shadow DOM. Do **not** use `border-left`, inset `box-shadow`, or row `::before` for the accent: tooltip nubbins on described rows use `::before`.

### Action button

Native SLDS neutral button (`.rhc-action-button`, `slds-button_neutral`): **not** `lightning-button` (SVG play icon was unreliable in the target context).

**Visible label (regression guard)**

- The visible label is **only** `Run` (before the first completed run) or `Rerun` (after any run has completed). **Do not** relabel to `Running…`, `Running`, or any other in-flight text: that widened the button and left empty padding on `Run` / `Rerun`.
- The label **does not change when a run starts**: first run stays **Run** + spinner; subsequent runs stay **Rerun** + spinner (`hasCompletedRunOnce`: not `runComplete`, which clears during the run).
- Check count lives in `title` and in `aria-label` while busy (e.g. `Run 18 Checks`, `Running 18 Checks`, `Re-running 18 Checks`): not in the visible label.

**In-flight / busy state**

- Button **stays visible** and **disabled** for the whole run (Manual and Automatic).
- **CSS spinner** (`.rhc-action-button__spinner`) replaces the play glyph (`.rhc-action-button__play`) inside a fixed **`.rhc-action-button__glyph`** slot (`0.75rem`); do not show both at once.
- Set **`aria-busy="true"`** while a run is in flight; `aria-label` carries the busy phrase for screen readers.
- **Do not** hide the button during a run: that was the pre-June-2026 behavior this iteration replaced.

**Width and layout (regression guard)**

- **`min-width: 5rem`** with tighter horizontal padding: sized for **Rerun** + a fixed **0.75rem** glyph slot (`.rhc-action-button__glyph`) so `Run` and `Rerun` share the same compact footprint and the label **does not shift** when the play icon swaps to the spinner.
- **Do not** size `min-width` for a longer label such as `Running…` (the old `7rem` value).
- Fixed width prevents the card title from reflowing between one and two lines as the button state changes.

**Play glyph**

- CSS-drawn triangle (▶) after the label when idle: always renders and greys with disabled text when the button is disabled for other reasons.

### Pre-run hint

Before the first Manual run (both `OneAtATime` and `AllAtOnce`), shows one line:

> Click **Run** to evaluate this record against {count phrase}.

`{count phrase}` is pluralized (`1 check` / `18 checks`) or, when `checksOmittedByLimit` is true, **the first 25 checks**.

### Rows

- Renders each row's `Tooltip__c` as a hover/focus tooltip (`data-tooltip` on the `<li>`) when a description exists: **never inline**. Tooltip anchor classes are omitted when description is blank. Description is folded into `accessibleLabel` for screen readers.
- Row tooltip layout and nubbin behavior are defined in [Tooltips](#tooltips) below.
- Row status icons are **CSS-drawn** circles (`rhc-status-icon--*`): not `lightning-icon`.
- Always renders `FAIL` (Error), `Warning`, `Info`, and `UNABLE_TO_EVALUATE` outcomes as full rows: these are actionable and are never collapsed into the summary bar. Only `PASS` and `SKIPPED` outcomes can be collapsed (via `PassedChecksDisplay__c` / `SkippedChecksDisplay__c`).
- Applies `PassedChecksDisplay__c` and `SkippedChecksDisplay__c`: rows in `Hide` mode are filtered from the list even when `RowAppearance__c` is `AllAtOnce`.
- On resolved **non-passing** rows, shows a **Found** / **Expected** comparison block beneath `MessageWhenFailed__c` when the evaluator populated `actualValue` and/or `expectedValue`: rendered as stacked labelled chips (see [9](05-result-contract-and-reason-codes.md#comparison-display-contract)). Example: Found `"Cold"` on one line; Expected `does not equal "Cold"` on the next. Formula failures show Expected only (quoted formula text) unless `FoundValueFormula__c` / `ExpectedValueFormula__c` are configured, in which case both resolved scalars render. Not shown on `PASS`, `SKIPPED`, `UNABLE_TO_EVALUATE`, or `ERROR`.
- Renders `MessageWhenFailed__c` / `MessageWhenCannotRun__c` across multiple lines: newlines authored in Setup become separate visual lines (interior blank lines are preserved as spacing), and the lines are folded into one sentence for the row `aria-label`.
- Shows `adminDetailMessage` **inline** (no click-to-expand), per-row debug-meta, and console footnote when `DebugMode__c` is on **and** the user has `Record_Health_Check_Debug` (see [Debug Mode guide](../guides/debug-mode.md)).

### Summary bar

- After run completion, renders a single **summary bar** of per-outcome pills (`Passed`, `Failed`, `Warning`, `Info`, `Skipped`, `Unable`) when at least one bucket is non-zero.
- Each pill uses the **same CSS status icon** as rows (`rhc-status-icon--*`) for visual consistency (e.g. Unable = `?`, Skipped = `-`).
- Each pill is a hover/focus tooltip target; tooltip text is `{label}: {comma-separated rule labels}` (e.g. `2 Warnings: Website Uses HTTPS, Has at Least Two Contacts`). **Warning** pluralizes (`1 Warning` vs `2 Warnings`).
- Summary-pill tooltip layout and nubbin behavior are defined in [Tooltips](#tooltips) below.
- Replaces the removed standalone "N rules passed" / "N rules were skipped" footer notes. Rows hidden by `Hide` still contribute to their pill counts.

### Tooltips

CSS-drawn hover/focus popovers (`rhc-tooltip-anchor` + `::before` / `::after`). **Do not** switch to `lightning-helptext` or inline description text: the compact-row contract depends on this mechanism.

**Shared surface and interaction**

- Light-gray popover (`neutral-base-95`) with `border-base-3` edge, drop shadow, and `z-index: 100` (nubbin `101`) so bubbles layer above the card and adjacent page chrome.
- Trigger on **`:hover`** and **`:focus-visible`** only: **not** plain `:focus` (avoids a mouse-clicked row pinning its tooltip while hovering another).
- **Dwell delay:** **500ms** after the pointer rests before show; **150ms** on keyboard `:focus-visible`. Hide immediately when hover/focus leaves.

**Non-clipping (regression guard)**

- **Do not** set `overflow: hidden` on `.rhc-card` to "tidy" corners. That clips the last row's below-row tooltip and summary tooltips at the card edge.
- Card bottom rounding comes from **`.rhc-body > :last-child`**, not from trapping overflow on the card shell.

**Row tooltips** (`rhc-tooltip-anchor--row` on the `<li>`)

- Bubble appears **below** the row (`top: calc(100% + 0.5rem)`), pinned `left: 1rem; right: 1rem` so it spans the card width and wraps at any column width.
- **Upward nubbin** (`::before`): bordered square rotated 45°, pointing at the row. Row accent must remain a **`.rhc-row__accent` element**: not `::before` on the row.

**Summary-pill tooltips** (`.rhc-summary-pill` grid wrapper + `.rhc-tooltip-anchor--footer` on the pill `<span>`)

- Bubble appears **above** the stats bar (`bottom: 100%` on `.rhc-stats-bar`), pinned **`left: 1rem; right: 1rem`**: **same width and wrap behavior as row tooltips**.
- Pill anchor and `.rhc-summary-pill` wrapper must stay **`position: static`** so the bubble's containing block is `.rhc-stats-bar`, not the small pill. **Do not** wrap pills in `position: relative`: that squeezes `left/right` insets to pill width and produces a tall, narrow tooltip.
- **Downward nubbin** is **`.rhc-stat__nubbin`** inside **`.rhc-stat__nubbin-host`**: a **grid sibling** of the footer anchor (not an ancestor). Host is `position: relative` and pill-sized; footer anchor stays `position: static`. Nubbin sits at `bottom: calc(100% + 0.25rem)` on the host so it **meets the bubble bottom** (same 0.25rem / 0.5rem spacing as row tooltips). **Do not** place the nubbin on the pill top or detach it from the bubble.
- **Do not** center a `max-content` bubble on the pill with a very large `max-width`: that produces an unreadably wide one-line tooltip.

### Diagnostics (debug mode)

Requires `Record_Health_Check_Debug` plus **Debug Mode** on the Check Set. Per-row debug lines, **Debug detail** on errors, console footnote, and `[RHC]` browser console summary after run completion. See [Debug Mode guide](../guides/debug-mode.md).
- Error banner (setup/load failures) still uses `lightning-icon`.

### Component design property

| Property | Type | Purpose |
| -------- | ---- | ------- |
| `configName` | String | `DeveloperName` of the `Record_Health_Check_Set__mdt` record to run. Set in Lightning App Builder on the record page. |
