> [!NOTE]
> **Canonical source:** Section numbers and anchors in the [full design specification](../reference/record-health-check-design-spec.md) are stable for cross-links.

## 18. Default Behavior Summary

| Field | CMT default | Runtime when blank on Rule |
| ----- | ----------- | -------------------------- |
| `WhenValueIsEmpty__c` | `SkipRecordsWithMissingValue` | Same: blank aligns with skip-on-null for row comparisons. |
| `WhenZeroRows__c` | `Skip` | Same: blank resolves to `Skip`. |

For `AnyRowPasses`, `AllRowsPass`, and `CompareAsLists`, set `WhenZeroRows__c` explicitly so intent is visible in metadata.

## 19. Resolved Issues (formerly 18)

These items were previously tracked as known bugs and are **fixed** in the current codebase:

| ID | Resolution |
| -- | ---------- |
| B1 | Blank `WhenValueIsEmpty__c` aligns with CMT default (`SkipRecordsWithMissingValue`). |
| B2 | Server-side `RequiresCheck__c` gate in `RecordHealthCheckEngine` (prerequisite re-evaluation can duplicate work; see [20](12-limitations-and-roadmap.md#20-open-limitations-and-edge-cases)). |
| B3 | `getCheckDefinitions` is no longer cacheable. |
| B4 | `RunChecksWhen__c` and `RowAppearance__c` validated at definition load in Config Service and Metadata Validator. |
| B5 | LWC `_runToken` discards stale in-flight results on rerun; `_loadDefinitions` resets run state on `recordId` change (H1). |
| B6 | `RecordHealthCheckConstants` centralizes valid-value sets and caps. |
| B7 | Applicability sub-fields validated at runtime and deploy-time. |
| B8 | `RecordHealthCheckSoqlTemplate` + `RecordHealthCheckValueResolver` extracted; all query paths (single-query, dual-query, applicability) wired. |
| B9 | Ordered comparisons use typed coercion; no string-sort fallback. |
| B10 | List membership and list-mode overlap comparators are case-insensitive (`Contains` / `DoesNotContain` remain case-sensitive). |
| B11 | Named aggregate aliases supported via `getPopulatedFieldsAsMap`. |
| B12 | Documentation uses `AccountHasRecentActivityCheck`. |
| B13 | LWC Automatic concurrency capped at 5 simultaneous `evaluateCheck` calls; queue for the rest. |
| B14 | Debug details gated by `Record_Health_Check_Debug` Custom Permission in Apex (`RecordHealthCheckAccess`). |
| B15 | Null `recordId` on evaluate path returns `NO_RECORD_CONTEXT`. |
| B17 | Manual mode shows pre-run guidance before the first run in **both** reveal modes (`showPreRunHint`). |
| B18 | Non-passing rows show **Found** / **Expected** labelled chips from `actualValue` / `expectedValue`; Formula checks show Expected (quoted formula text) only. |
| B19 | Row and summary-pill status icons are CSS-drawn (`rhc-status-icon--*`): not `lightning-icon`: for reliable rendering. |
| B20 | Summary pills list rule labels in hover/focus tooltips; standalone per-status footer notes removed. |
| B21 | Rule descriptions are tooltip-only (never inline); tooltips use `:focus-visible` to avoid double-tooltip on mouse click. |
| B22 | Action button stays visible during runs (disabled, spinner, label unchanged); label driven by **`hasCompletedRunOnce`**; busy text in `title` / `aria-label`. |
| B23 | `formatValue` quotes all non-blank scalars uniformly (numbers, Booleans, dates included). |
| B24 | LWC header icon removed; the icon field was dropped from the schema and the Apex definition response (no `IconName__c` / `iconName` exists today). |
| B25 | `PassedChecksDisplay__c` / `SkippedChecksDisplay__c`: `Hide` collapses rows from the list but still populates summary pills after run completion. |
| B26 | Card uses `--lwc-borderRadiusMedium` rounded corners; **`overflow: visible`** on the card shell with bottom radius on `.rhc-body > :last-child` so tooltips are not clipped. |
| B27 | Row status accent is a full-height `.rhc-row__accent` element flush to the left edge: not `border-left`, `box-shadow`, or row `::before`. |
| B28 | Row/summary tooltips wait **500ms** on mouse hover before showing; **150ms** on `:focus-visible`; hide immediately on leave. |
| B29 | Summary-pill tooltips span the stats bar (`left/right: 1rem`, same as rows); nubbin is `.rhc-stat__nubbin` in `.rhc-stat__nubbin-host` (grid sibling of footer anchor). |
| B30 | Tooltips use `z-index: 100+` and must remain fully visible outside the card boundary (no `overflow: hidden` on `.rhc-card`). |
| B31 | Action button visible label is **only** `Run` or `Rerun`: never `Running…`; in-flight busy state is **spinner + `aria-busy`**, with busy text in `title` / `aria-label`. Label tracks **`hasCompletedRunOnce`** so a re-run stays **Rerun** while in flight. |
| B32 | Action button `min-width` is **5rem** with a fixed **0.75rem** glyph slot: label must not shift when play swaps to spinner. |
| B33 | Summary-pill tooltip bubble must **wrap** at card width: never a narrow pill-width column (`position: relative` wrapper between anchor and stats bar). |
| B34 | Summary-pill nubbin must **attach to the tooltip bubble bottom** (`.rhc-stat__nubbin-host` sibling pattern): never float above the pill detached from the bubble. |
