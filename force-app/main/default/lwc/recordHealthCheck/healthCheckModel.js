/*
 * Copyright 2026 Record Health Check contributors
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Pure domain logic for the Record Health Check component: result shaping,
 * response normalization, dependency-cycle detection, and run-id / error
 * parsing. None of these functions touch component state, so they are unit-
 * testable in isolation and keep the LWC class focused on orchestration.
 */

export const VALID_RESULT_STATUSES = new Set([
  "PASS",
  "FAIL",
  "SKIPPED",
  "UNABLE_TO_EVALUATE",
  "ERROR"
]);

/**
 * Builds a client-synthesized result for a check the server never evaluated
 * (skipped dependency, circular dependency, transport failure, etc.). Mirrors
 * the shape Apex returns so the rest of the pipeline treats it uniformly.
 */
export function synthesizeResult(check, status, reasonCode, message) {
  return {
    checkDeveloperName: check.developerName,
    label: check.label,
    status,
    reasonCode,
    message,
    priority: check.priority,
    evaluatorType: null
  };
}

/**
 * Guards against malformed Apex responses. Anything that is not an object with
 * a recognized status is replaced by a synthesized ERROR so the UI can never
 * render an undefined/unknown status.
 */
export function normalizeResult(result, check) {
  if (!result || typeof result !== "object") {
    return synthesizeResult(
      check,
      "ERROR",
      "MALFORMED_RESPONSE",
      "The server returned an invalid result. Contact your administrator."
    );
  }
  if (!VALID_RESULT_STATUSES.has(result.status)) {
    return synthesizeResult(
      check,
      "ERROR",
      "UNKNOWN_RESULT_STATUS",
      "The server returned an unsupported result status. Contact your administrator."
    );
  }
  return result;
}

/**
 * Returns the set of check developer names that participate in a dependency
 * cycle. These are pre-seeded as UNABLE_TO_EVALUATE so their promises resolve
 * immediately instead of awaiting each other forever.
 */
export function detectDependencyCycles(checks) {
  const depMap = {};
  for (const check of checks) {
    if (check.dependsOnCheckDeveloperName) {
      depMap[check.developerName] = check.dependsOnCheckDeveloperName;
    }
  }
  const cycleMembers = new Set();
  for (const check of checks) {
    if (!depMap[check.developerName]) continue;
    const path = [];
    const pathSet = new Set();
    let current = check.developerName;
    while (depMap[current] && !cycleMembers.has(current)) {
      if (pathSet.has(current)) {
        // Found a cycle — add only the nodes from where the cycle starts
        const cycleStart = path.indexOf(current);
        for (let i = cycleStart; i < path.length; i++) {
          cycleMembers.add(path[i]);
        }
        break;
      }
      path.push(current);
      pathSet.add(current);
      current = depMap[current];
    }
  }
  return cycleMembers;
}

/**
 * Extracts a user-facing message and reason code from an Aura/Apex error. The
 * controller serializes a JSON `{ reasonCode, message }` into the error body;
 * fall back to the raw body text (or a generic message) when it is not JSON.
 *
 * When no explicit reasonCode is present (non-JSON body, or JSON without one),
 * we default to the generic `LOAD_FAILED` rather than `CONFIG_NOT_FOUND`
 * (L-RC-02): an unparsed transport/Apex failure does not actually tell us the
 * Check Set was missing, so claiming CONFIG_NOT_FOUND would mislead admins
 * triaging from the diagnostics/log.
 */
export function parseAuraError(err) {
  try {
    const body = err.body && err.body.message ? err.body.message : "";
    const parsed = JSON.parse(body);
    return {
      reasonCode: parsed.reasonCode || "LOAD_FAILED",
      message: parsed.message || "An error occurred loading health checks."
    };
  } catch {
    return {
      reasonCode: "LOAD_FAILED",
      message:
        (err.body && err.body.message) ||
        "An error occurred loading health checks."
    };
  }
}

/**
 * Generates a correlation id sent to Apex and echoed in the debug log. Prefers
 * the platform UUID generator; falls back to a timestamp+random token if the
 * runtime restricts crypto (the value only needs to be unique enough to group
 * one run's log lines, not cryptographically strong).
 */
export function newRunId() {
  try {
    if (
      typeof crypto !== "undefined" &&
      crypto &&
      typeof crypto.randomUUID === "function"
    ) {
      return crypto.randomUUID();
    }
  } catch {
    // fall through to the timestamp-based id
  }
  return `rhc-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}
