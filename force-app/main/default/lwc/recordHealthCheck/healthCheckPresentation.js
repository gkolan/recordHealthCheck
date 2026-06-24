/*
 * Copyright 2026 Record Health Check contributors
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Pure view-formatting helpers for the Record Health Check component. These map
 * raw check/result data into the template-ready flags, class strings, and
 * summary rows the markup binds to. LWC templates can't evaluate expressions,
 * so all of that branching lives here instead of in the HTML.
 */

// status/severity → display label and CSS modifier suffix. Order is irrelevant;
// lookup is keyed by the resolved outcome computed in annotateCheck.
const OUTCOME_STYLES = {
  pass: { label: "Pass", modifier: "pass", message: false },
  error: { label: "Failed", modifier: "error", message: true },
  warning: { label: "Warning", modifier: "warning", message: true },
  info: { label: "Info", modifier: "info", message: true },
  skipped: { label: "Skipped", modifier: "skipped", message: false },
  unable: { label: "Unable to Check", modifier: "unable", message: true }
};

// Summary-bar rows, rendered in this fixed order when their count is non-zero.
// `suffix` is shared with the per-row status icon modifier (rhc-status-icon--*)
// so the pill icon is rendered by the SAME CSS as the row icon — identical
// symbol/colour in both places (✓ ! i – ?), and no dependency on lightning-icon.
const SUMMARY_ROWS = [
  { key: "pass", suffix: "pass", label: (n) => `${n} Passed` },
  { key: "error", suffix: "error", label: (n) => `${n} Failed` },
  {
    key: "warn",
    suffix: "warning",
    label: (n) => `${n} ${n === 1 ? "Warning" : "Warnings"}`
  },
  { key: "info", suffix: "info", label: (n) => `${n} Info` },
  { key: "skip", suffix: "skipped", label: (n) => `${n} Skipped` },
  { key: "unable", suffix: "unable", label: (n) => `${n} Unable` }
];

/**
 * Classifies a resolved check into one of the OUTCOME_STYLES keys. Returns null
 * for rows that are still pending/loading or have no result yet.
 */
function classifyOutcome(status, severity) {
  switch (status) {
    case "PASS":
      return "pass";
    case "FAIL":
      if (severity === "Warning") return "warning";
      if (severity === "Info") return "info";
      // L-UI-01: a FAIL with Error severity OR a missing/unrecognized severity
      // defaults to error styling, so a failing check is never rendered as an
      // unstyled row or miscounted as "Unable" in the summary bar.
      return "error";
    case "SKIPPED":
      return "skipped";
    case "UNABLE_TO_EVALUATE":
    case "ERROR":
      return "unable";
    default:
      return null;
  }
}

/**
 * Adds template-ready computed boolean flags and display strings to a check
 * object. Called from the visibleChecks getter so the template can use simple
 * property bindings instead of inline expressions (which LWC doesn't support).
 */
export function annotateCheck(c, debugMode) {
  const uiState = c.uiState;
  const result = c.result || {};
  const status = result.status || "";
  const severity = result.severity || "";

  const isPending = uiState === "PENDING";
  const isLoading = uiState === "LOADING";
  const isResolved = uiState === "RESOLVED";

  const outcome = isResolved ? classifyOutcome(status, severity) : null;
  const style = outcome ? OUTCOME_STYLES[outcome] : null;

  // isPass gates the message/comparison blocks below; the other outcome booleans
  // (isFailError/isFailWarning/isFailInfo/isSkipped/isUnable) were never read by
  // the template and have been removed (LWC-13).
  const isPass = outcome === "pass";

  const statusLabel = style ? style.label : "";
  let statusIconClass = "rhc-status-icon ";
  let rowClass = "rhc-row";
  let messageClass = "rhc-row__message";
  let rowAccentClass = "";

  if (style) {
    statusIconClass += `rhc-status-icon--${style.modifier}`;
    rowClass += ` rhc-row--${style.modifier}`;
    rowAccentClass = `rhc-row__accent rhc-row__accent--${style.modifier}`;
    if (style.message) {
      messageClass += ` rhc-row__message--${style.modifier}`;
    }
  } else if (isLoading) {
    rowClass += " rhc-row--loading";
  } else if (isPending) {
    rowClass += " rhc-row--pending";
  }

  // The row description is shown only as a hover/focus tooltip (Section 15) to
  // keep rows compact. Add the tooltip-anchor classes only when a description
  // exists, otherwise the empty `data-tooltip` would render a blank bubble.
  if (c.description) {
    rowClass += " rhc-tooltip-anchor rhc-tooltip-anchor--row";
  }

  // LWC-05: only rows that carry a tooltip (a description) are keyboard tab stops,
  // so a focus pass reaches the hover content. Rows without a tooltip have nothing
  // to reveal on focus and should not add an empty stop to the tab order.
  const tabIndex = c.description ? 0 : -1;

  const showMessage = isResolved && !isPass && !!(c.result && c.result.message);

  // Actual-vs-expected comparison, shown on a non-passing resolved row when the
  // evaluator captured it. Either side may be absent (e.g. Formula checks carry
  // only the expected condition), so each part renders independently.
  // LWC-07: use nullish checks, not truthiness — a legitimate actual/expected of
  // 0 or "" must still render. Only null/undefined counts as "no value captured".
  const actualValue =
    isResolved && result.actualValue != null ? result.actualValue : null;
  const expectedValue =
    isResolved && result.expectedValue != null ? result.expectedValue : null;
  const showComparison =
    isResolved && !isPass && (actualValue != null || expectedValue != null);

  // The comparison renders as labelled key/value chips ("Found" + actual,
  // "Expected" + expected) so the template can style the captions and the
  // monospaced values independently. Either side may be absent — Formula
  // failures carry only the expected condition, so they render "Expected …"
  // alone. (The screen-reader sentence is folded into accessibleLabel below.)
  const showActual = showComparison && actualValue != null;
  const showExpected = showComparison && expectedValue != null;

  // P1-05 a11y: the <li> carries aria-label, which overrides its descendant text
  // for screen readers — so the actionable failure/skip message must be folded
  // into the accessible name or it is never announced.
  const accessibleLabel = [
    c.label,
    isLoading ? "Evaluating" : isPending ? "Pending" : statusLabel,
    c.description,
    showMessage ? c.result.message : null,
    showComparison && actualValue != null ? `Found ${actualValue}` : null,
    showComparison && expectedValue != null ? `Expected ${expectedValue}` : null
  ]
    .filter(Boolean)
    .join(". ");

  const adminDetailMessage =
    (isResolved && c.result && c.result.adminDetailMessage) || null;
  const showAdminDetail = debugMode && !!adminDetailMessage;

  // Compact per-check diagnostics line (debug mode only): the machine-readable
  // facts an admin needs — status, reason code, evaluator, and timing.
  const r = c.result || {};
  const debugMeta =
    debugMode && isResolved
      ? [
          r.status,
          r.reasonCode,
          r.durationMs != null ? `${r.durationMs}ms` : null,
          r.evaluatorType
        ]
          .filter(Boolean)
          .join(" · ")
      : "";
  const showDebugMeta = !!debugMeta;
  const showRowAccent = !!rowAccentClass;

  return {
    ...c,
    isPending,
    isLoading,
    isResolved,
    statusLabel,
    statusIconClass,
    rowClass,
    tabIndex,
    showRowAccent,
    rowAccentClass,
    messageClass,
    showMessage,
    actualValue,
    expectedValue,
    showComparison,
    showActual,
    showExpected,
    adminDetailMessage,
    showAdminDetail,
    debugMeta,
    showDebugMeta,
    accessibleLabel
  };
}

/**
 * Tallies resolved checks into the summary-bar rows. FAIL is split by severity:
 * Warning and Info get their own buckets, while a FAIL with Error severity OR a
 * missing/unrecognized severity counts as "error" (Failed) — see L-UI-01 in
 * classifyOutcome. SKIPPED is its own bucket; UNABLE_TO_EVALUATE, ERROR, and any
 * unrecognized status fall through to "unable".
 */
export function buildSummaryStats(checks) {
  const buckets = {
    pass: [],
    error: [],
    warn: [],
    info: [],
    skip: [],
    unable: []
  };
  for (const c of checks) {
    if (!c.result) continue;
    const outcome = classifyOutcome(c.result.status, c.result.severity);
    let key;
    if (outcome === "pass") key = "pass";
    else if (outcome === "error") key = "error";
    else if (outcome === "warning") key = "warn";
    else if (outcome === "info") key = "info";
    else if (outcome === "skipped") key = "skip";
    else key = "unable";
    buckets[key].push(c.label);
  }

  // Each pill is a hover/focus tooltip anchor listing the rules in its bucket —
  // this is the single summary surface (the old per-status footer notes are
  // gone). The label string ("13 Passed") prefixes the names so the tooltip is
  // self-describing.
  return SUMMARY_ROWS.filter((row) => buckets[row.key].length > 0).map(
    (row) => {
      const names = buckets[row.key];
      const label = row.label(names.length);
      return {
        key: row.key,
        label,
        cssClass: `rhc-stat rhc-stat--${row.suffix} rhc-tooltip-anchor rhc-tooltip-anchor--footer rhc-tooltip-anchor--stat`,
        tooltip: `${label}: ${tooltipNames(names)}`,
        iconClass: `rhc-status-icon rhc-status-icon--${row.suffix}`
      };
    }
  );
}

// LWC-19: a bucket can hold up to 25 rule labels; listing them all produces an
// unwieldy tooltip. Show at most the first few names and summarize the rest as
// "and N more" so the bubble stays readable.
const TOOLTIP_NAME_CAP = 5;
function tooltipNames(names) {
  if (names.length <= TOOLTIP_NAME_CAP) {
    return names.join(", ");
  }
  const shown = names.slice(0, TOOLTIP_NAME_CAP).join(", ");
  return `${shown}, and ${names.length - TOOLTIP_NAME_CAP} more`;
}
