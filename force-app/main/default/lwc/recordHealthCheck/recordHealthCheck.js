/*
 * Copyright 2026 Record Health Check contributors
 * SPDX-License-Identifier: Apache-2.0
 */

import { LightningElement, api, track } from "lwc";
import USER_ID from "@salesforce/user/Id";
import getCheckDefinitions from "@salesforce/apex/RecordHealthCheckController.getCheckDefinitions";
import { parseAuraError } from "./healthCheckModel";
import { annotateCheck, buildSummaryStats } from "./healthCheckPresentation";
import { HealthCheckRunner } from "./healthCheckRunner";

export default class RecordHealthCheck extends LightningElement {
  // ─── @api properties (Section 6.4) ───────────────────────────────────────
  _configName;

  @api
  get configName() {
    return this._configName;
  }
  set configName(value) {
    const changed = value !== this._configName;
    this._configName = value;
    if (this._connected && changed) {
      this._loadDefinitions();
    }
  }

  // recordId is a getter/setter so the component reloads when the record page
  // swaps the underlying record without remounting the component (e.g. console
  // navigation, dynamic record pages). Without this, results would be stale or
  // belong to the previously-viewed record.
  _recordId;
  _connected = false;

  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    const changed = value !== this._recordId;
    this._recordId = value;
    // Only reload on a genuine change after the initial connectedCallback load;
    // the first load is owned by connectedCallback so it can defer one macrotask.
    if (this._connected && changed) {
      this._loadDefinitions();
    }
  }

  // ─── Check Set level state (Section 6.6) ─────────────────────────────────
  @track displayTitle;
  @track displayDescription;
  @track triggerMode;
  @track revealMode;
  @track successDisplayMode;
  @track skippedDisplayMode;
  @track stopOnFirstError;
  @track debugMode = false;
  @track totalCheckCount = 0;
  @track completedCheckCount = 0;
  @track runComplete = false;
  /** Stays true after the first completed run until definitions reload — drives
   *  the Run/Rerun label while a subsequent run is in flight (runComplete is
   *  false during that window). */
  @track hasCompletedRunOnce = false;
  @track componentError = null; // safe user-facing message
  @track componentErrorCode = null; // Section 6.1 reason code
  @track checksOmittedByLimit = false;
  @track isLoading = true;

  // ─── Per-check state ──────────────────────────────────────────────────────
  @track checks = [];

  // ─── Internal state ───────────────────────────────────────────────────────
  // Run orchestration (result buffer, reveal pointer, concurrency pool, run id,
  // and the run token that discards stale in-flight results) lives in the runner;
  // the component owns lifecycle, definition loading, display, and diagnostics.
  _runner = new HealthCheckRunner(this);
  _loadToken = 0;
  _initialLoadTimer;
  _tooltipListenersBound = false;
  // LWC-38: memoize summaryStats keyed on the checks array reference. The runner
  // always reassigns this.checks (.map(...)) when a result lands, so reference
  // equality is a sound cache key and avoids re-running buildSummaryStats on
  // every getter access (showSummaryStats + the template loop) within a render.
  _summaryStatsSource = null;
  _summaryStatsCache = [];

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  connectedCallback() {
    this._connected = true;
    // Defer one macrotask so the record page frame finishes its initial render
    // before we fire Apex calls. Without this, Automatic mode sends up to 25
    // concurrent requests while the page is still mounting other components.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._initialLoadTimer = setTimeout(() => this._loadDefinitions(), 0);
  }

  disconnectedCallback() {
    this._connected = false;
    this._loadToken++;
    if (this._initialLoadTimer) {
      clearTimeout(this._initialLoadTimer);
      this._initialLoadTimer = null;
    }
    // Bump the run token and clear the concurrency pool so any in-flight
    // evaluation resolves to a discarded result instead of mutating a dead component.
    this._runner.invalidate();
    if (this._tooltipListenersBound) {
      // LWC-24: the listener is added as `mouseenter` with capture=true (see
      // renderedCallback). removeEventListener only unbinds when the event name
      // AND the capture flag match the add — removing `mouseover` (the old name,
      // bubbling phase) left the real listener attached. Mirror the add exactly.
      this.template.removeEventListener(
        "mouseenter",
        this._positionTooltip,
        true
      );
      this.template.removeEventListener("focusin", this._positionTooltip);
      this.template.removeEventListener("mouseout", this._clearTooltipFlip);
      this.template.removeEventListener("focusout", this._clearTooltipFlip);
      this._tooltipListenersBound = false;
    }
  }

  renderedCallback() {
    if (this._tooltipListenersBound) {
      return;
    }
    this._tooltipListenersBound = true;
    // Tooltips open downward by default (pure CSS). On hover/focus we measure the
    // anchor against the viewport and add --flip-up when there is not enough room
    // below, so a tooltip near the bottom of the screen opens upward instead of
    // being clipped. Delegated on the template root — mouseover and focusin both
    // bubble, so one listener pair covers every rule row and summary pill.
    // AUDIT (LWC-15, 2026-06-23):
    // BEFORE: mouseover fired on every child boundary crossing inside an anchor.
    // AFTER: mouseenter fires once per anchor entry (focusin unchanged).
    this.template.addEventListener("mouseenter", this._positionTooltip, true);
    this.template.addEventListener("focusin", this._positionTooltip);
    // LWC-04: reset the flip direction when leaving an anchor so a row flipped
    // upward does not keep that state after the pointer/focus moves away.
    this.template.addEventListener("mouseout", this._clearTooltipFlip);
    this.template.addEventListener("focusout", this._clearTooltipFlip);
  }

  // Removes the flip-up modifier once the pointer/focus leaves the anchor entirely
  // (ignoring moves between the anchor's own children), so the next open recomputes
  // direction from the default downward position instead of a stale flipped state.
  _clearTooltipFlip = (event) => {
    const anchor =
      event.target && event.target.closest
        ? event.target.closest(".rhc-tooltip-anchor")
        : null;
    if (!anchor) {
      return;
    }
    const movingTo = event.relatedTarget;
    if (movingTo && anchor.contains(movingTo)) {
      return;
    }
    anchor.classList.remove("rhc-tooltip-anchor--flip-up");
  };

  // Decide open direction for the hovered/focused tooltip anchor. Flips upward only
  // when the space below the anchor is tight AND there is more room above, so the
  // default (downward, matching the rule rows) is preserved everywhere it fits.
  _positionTooltip = (event) => {
    const target = event.target;
    const anchor =
      target && target.closest ? target.closest(".rhc-tooltip-anchor") : null;
    if (!anchor) {
      return;
    }
    const rect = anchor.getBoundingClientRect();
    const viewportHeight =
      window.innerHeight || document.documentElement.clientHeight || 0;
    const spaceBelow = viewportHeight - rect.bottom;
    const spaceAbove = rect.top;
    // Roomy enough for the multi-line summary/rule bubbles; below this we flip.
    const ESTIMATED_TOOLTIP_HEIGHT = 180;
    const flipUp =
      spaceBelow < ESTIMATED_TOOLTIP_HEIGHT && spaceAbove > spaceBelow;
    anchor.classList.toggle("rhc-tooltip-anchor--flip-up", flipUp);
  };

  async _loadDefinitions() {
    const loadToken = ++this._loadToken;
    const requestedConfigName = this.configName;
    const requestedRecordId = this.recordId;
    // LWC-40: this method runs from both the deferred initial-load timer AND a
    // reactive setter change. Clear the pending timer so a fast setter change
    // that calls _loadDefinitions directly does not also let the queued timer
    // fire a second, redundant getCheckDefinitions request.
    if (this._initialLoadTimer) {
      clearTimeout(this._initialLoadTimer);
      this._initialLoadTimer = null;
    }
    // Invalidate any run still in flight from a previously-viewed record. This
    // method is the entry point for both the first load AND the in-place record
    // swap (console navigation / dynamic record pages), so without this reset a
    // stale evaluateCheck result from record A could drain into record B's rows
    // (the run token guards stale results, and B reuses A's developerName keys),
    // and a leftover in-progress run would suppress B's Automatic run entirely.
    this._runner.invalidate();
    this.runComplete = false;
    this.hasCompletedRunOnce = false;
    this.completedCheckCount = 0;
    // LWC-25: drop the previous record's rows immediately on (re)load entry.
    // The check list is not gated by isLoading, so without this the prior
    // record's rows stay on screen until the new definitions resolve — during a
    // console record swap that shows stale results under the new record.
    this.checks = [];

    this.isLoading = true;
    this.componentError = null;
    this.componentErrorCode = null;

    // LWC-36: a whitespace-only configName is truthy, so it slipped past the
    // blank guard and reached the server as a non-empty-but-invalid name.
    if (!this.configName || !this.configName.trim()) {
      this.isLoading = false;
      this.componentError =
        "No Config Name has been set for this component. " +
        "Open App Builder, select the Record Health Check component, and set " +
        "the Config Name property to the Developer Name of a " +
        "Record_Health_Check_Set__mdt record.";
      this.componentErrorCode = "SETUP_REQUIRED";
      return;
    }

    const runId = this._runner.beginRunId();

    try {
      const response = await getCheckDefinitions({
        configName: requestedConfigName,
        recordId: requestedRecordId,
        runId
      });

      if (loadToken !== this._loadToken || !this._connected) return;
      if (!response || !Array.isArray(response.checks)) {
        throw new Error(
          "The server returned an invalid health-check definition response."
        );
      }

      // LWC-03: developerName is the for:each key AND the dependency/result-buffer
      // key, so a blank or duplicate name silently corrupts rendering and gating.
      // Reject a malformed shape up front; the catch maps it to LOAD_FAILED.
      const seenNames = new Set();
      for (const def of response.checks) {
        if (!def || !def.developerName) {
          throw new Error(
            "A health-check definition is missing its developer name."
          );
        }
        if (seenNames.has(def.developerName)) {
          throw new Error(
            `Duplicate health-check developer name: ${def.developerName}.`
          );
        }
        seenNames.add(def.developerName);
      }

      this.displayTitle = response.displayTitle;
      this.displayDescription = response.displayDescription;
      // LWC-27: normalize to a known trigger mode. The run affordances key off
      // exactly "Manual" (Run button) and "Automatic" (auto-run); an unrecognized
      // or blank value would render neither, leaving the checks unrunnable. Mirror
      // the revealMode normalization below: anything not Automatic falls back to
      // Manual so the user always has a way to run.
      this.triggerMode =
        response.triggerMode === "Automatic" ? "Automatic" : "Manual";
      // LWC-09: normalize to a known reveal mode. Anything other than the
      // explicit progressive mode falls back to AllAtOnce (show every row) rather
      // than silently driving the OneAtATime reveal logic for an unrecognized or
      // blank value, which would hide rows behind a reveal pointer unexpectedly.
      this.revealMode =
        response.revealMode === "OneAtATime" ? "OneAtATime" : "AllAtOnce";
      this.successDisplayMode = response.successDisplayMode;
      this.skippedDisplayMode = response.skippedDisplayMode;
      this.stopOnFirstError = response.stopOnFirstError;
      this.debugMode = response.debugMode === true;
      this.totalCheckCount = response.checks.length;
      this.checksOmittedByLimit = response.checksOmittedByLimit || false;

      // Build per-check rows — all start PENDING
      this.checks = response.checks.map((def) => ({
        developerName: def.developerName,
        label: def.label,
        description: def.description,
        priority: def.priority,
        dependsOnCheckDeveloperName: def.dependsOnCheckDeveloperName || null,
        uiState: "PENDING",
        result: null
      }));

      this.isLoading = false;
      this.componentError = null;
      this.componentErrorCode = null;

      if (this.triggerMode === "Automatic") {
        this._runner.run(true);
      }
    } catch (err) {
      if (loadToken !== this._loadToken || !this._connected) return;
      this.isLoading = false;
      const parsed = parseAuraError(err);
      this.componentError = parsed.message;
      this.componentErrorCode = parsed.reasonCode;
    }
  }

  // ─── Computed getters for template ────────────────────────────────────────

  get hasComponentError() {
    return !!this.componentError;
  }

  get isSetupError() {
    return this.componentErrorCode === "SETUP_REQUIRED";
  }

  get errorBannerIcon() {
    return this.isSetupError ? "utility:setup" : "utility:error";
  }

  // LWC-28: the icon swaps to utility:setup for a setup error, so its assistive
  // text must match — a "Setup required" graphic announced as "Error" misleads
  // screen-reader users about why the panel is blocked.
  get errorBannerIconAltText() {
    return this.isSetupError ? "Setup required" : "Error";
  }

  get errorBannerTitle() {
    return this.isSetupError
      ? "Component Not Configured"
      : "Health Check Unavailable";
  }

  get showRunButton() {
    // Stays rendered while a run is in progress (disabled + spinner; label stays
    // Run or Rerun per hasCompletedRunOnce — see actionButtonLabel).
    return this.triggerMode === "Manual" && !this.runComplete;
  }

  get showRerunButton() {
    return this.runComplete;
  }

  get isAllAtOnce() {
    return this.revealMode === "AllAtOnce";
  }

  get isOneAtATime() {
    return this.revealMode === "OneAtATime";
  }

  get visibleChecks() {
    let filtered;
    if (this.isAllAtOnce) {
      filtered = this.checks.filter((c) => {
        if (this._isHiddenSkipped(c)) {
          return false;
        }
        if (this._isHiddenSuccess(c)) {
          return false;
        }
        return true;
      });
    } else {
      // OneAtATime: reveal every resolved (non-hidden) row as soon as it lands
      // (LWC-02) — a ready visible result must not wait behind a slow, possibly
      // hidden check ahead of it. A single in-progress spinner is shown for the
      // first not-yet-resolved check, so only one row loads at a time even though
      // checks run concurrently.
      const nextPending = this.checks.find((c) => c.uiState !== "RESOLVED");
      const revealName = nextPending ? nextPending.developerName : null;
      filtered = this.checks.filter((c) => {
        if (c.uiState === "RESOLVED") {
          if (this._isHiddenSkipped(c)) {
            return false;
          }
          if (this._isHiddenSuccess(c)) {
            return false;
          }
          return true;
        }
        return (
          (c.uiState === "LOADING" ||
            (c.uiState === "PENDING" && this._runner.isRunning)) &&
          c.developerName === revealName
        );
      });
    }
    // Annotate each check with computed display properties for the template
    return filtered.map((c) => annotateCheck(c, this.debugMode));
  }

  get checkCountLabel() {
    const n = this.totalCheckCount;
    return `${n} ${n === 1 ? "Check" : "Checks"}`;
  }

  // Count phrase for the pre-run hint: pluralized, and when the set exceeds the
  // 25-rule cap it makes clear only the first 25 will run (matching the
  // "First 25 shown" badge).
  get checkCountPhrase() {
    if (this.checksOmittedByLimit) {
      return "the first 25 checks";
    }
    const n = this.totalCheckCount;
    return `${n} ${n === 1 ? "check" : "checks"}`;
  }

  get showActionButton() {
    return this.showRunButton || this.showRerunButton;
  }

  get showPreRunHint() {
    // Shown before the first Manual run in BOTH reveal modes for a consistent
    // call to action: OneAtATime shows the hint alone (no rows yet),
    // AllAtOnce shows it above the already-listed rows.
    return (
      this.triggerMode === "Manual" &&
      !this.isLoading &&
      !this.runComplete &&
      !this._runner.isRunning &&
      this.checks.length > 0
    );
  }

  get showSummaryStats() {
    return this.runComplete && this.summaryStats.length > 0;
  }

  get actionTitle() {
    // Check count lives in the hover tooltip; while a run is in flight the title
    // carries the busy state because the visible label stays "Run" / "Rerun".
    if (this._runner.isRunning) {
      return this.hasCompletedRunOnce
        ? `Re-running ${this.checkCountLabel}`
        : `Running ${this.checkCountLabel}`;
    }
    return this.hasCompletedRunOnce
      ? `Re-run ${this.checkCountLabel}`
      : `Run ${this.checkCountLabel}`;
  }

  get actionButtonLabel() {
    return this.hasCompletedRunOnce ? "Rerun" : "Run";
  }

  get actionButtonAriaLabel() {
    if (this._runner.isRunning) {
      return this.actionTitle;
    }
    return this.actionButtonLabel;
  }

  get actionButtonBusy() {
    return this._runner.isRunning;
  }

  // While a run is in flight the button stays put but is disabled, so it reads
  // as busy instead of vanishing.
  get actionButtonDisabled() {
    return this._runner.isRunning;
  }

  handleAction() {
    this._runner.run(false);
  }

  get summaryStats() {
    if (this._summaryStatsSource !== this.checks) {
      this._summaryStatsSource = this.checks;
      this._summaryStatsCache = buildSummaryStats(this.checks);
    }
    return this._summaryStatsCache;
  }

  get showLimitNotice() {
    return this.checksOmittedByLimit;
  }

  // ─── Internal helpers ─────────────────────────────────────────────────────

  _isSkipped(check) {
    return (
      check &&
      check.uiState === "RESOLVED" &&
      check.result &&
      check.result.status === "SKIPPED"
    );
  }

  _isHiddenSkipped(check) {
    return this._isSkipped(check) && this.skippedDisplayMode === "Hide";
  }

  _isSuccess(check) {
    return (
      check &&
      check.uiState === "RESOLVED" &&
      check.result &&
      check.result.status === "PASS"
    );
  }

  _isHiddenSuccess(check) {
    return this._isSuccess(check) && this.successDisplayMode === "Hide";
  }

  get showDebugConsoleHint() {
    return this.debugMode && this.runComplete;
  }

  // ─── Debug console summary (debug mode only) ─────────────────────────────

  _buildRunDiagnostics() {
    return {
      runId: this._runner.runId,
      userId: USER_ID,
      recordId: this.recordId,
      configName: this.configName,
      generatedAt: new Date().toISOString(),
      checks: this.checks.map((c) => {
        const r = c.result || {};
        return {
          check: c.developerName,
          status: r.status || c.uiState,
          severity: r.severity || null,
          reasonCode: r.reasonCode || null,
          // LWC-22 / LWC-23: ?? (not ||) so falsy-but-valid values survive in debug diagnostics.
          actualValue: r.actualValue ?? null,
          expectedValue: r.expectedValue ?? null,
          durationMs: r.durationMs != null ? r.durationMs : null,
          evaluatorType: r.evaluatorType ?? null
        };
      })
    };
  }

  _logRunDiagnostics() {
    const diag = this._buildRunDiagnostics();
    const configLabel = diag.configName || "(unset configName)";
    console.group(
      `[RHC] Health Check run ${diag.runId} — config ${configLabel} — user ${diag.userId} — record ${diag.recordId}`
    );
    console.log(diag);
    console.table(diag.checks);
    console.groupEnd();
  }
}
