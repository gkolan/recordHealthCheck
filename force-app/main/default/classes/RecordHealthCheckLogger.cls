/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Single logging facade for the Record Health Check framework.
 *
 * EVERY framework log line flows through this class. The engine, controller, and
 * evaluators never call System.debug directly — they call this logger — so the
 * destination ("sink") can be changed in exactly one place. To adopt Nebula
 * Logger (or any other logging framework) later, replace the body of `emit`
 * with the equivalent Nebula calls; no other class needs to change.
 *
 * Two things make a line useful for debugging:
 *   - runId  — a correlation id generated once per page load / run in the LWC and
 *              threaded through every Apex call, so an admin can filter a debug
 *              log down to a single user interaction.
 *   - user   — captured automatically from UserInfo.getUserId(), so every line is
 *              attributable to the running user without any caller passing it in.
 *              This is authoritative (it cannot be spoofed by the client) and means
 *              "show me everything that happened for user X" is a simple log filter.
 */
public with sharing class RecordHealthCheckLogger {
  /**
   * Framework-level severity. Kept independent of System.LoggingLevel so the
   * sink can map it however the target framework expects. DEBUG maps to FINE.
   */
  public enum Level {
    ERROR,
    WARN,
    INFO,
    DEBUG
  }

  private static final String PREFIX = '[RHC]';

  // Correlation keys carried for the life of one evaluate()/load call so that
  // individual log statements stay terse.
  private final String runId;
  private final String configName;
  private final String recordId;

  public RecordHealthCheckLogger(String runId, String configName, Id recordId) {
    this.runId = sanitize(String.isBlank(runId) ? 'no-run-id' : runId, 120);
    this.configName = sanitize(configName, 120);
    this.recordId = recordId == null ? null : String.valueOf(recordId);
  }

  // ─── Instance API (used by the engine, which holds a context) ──────────────

  public void error(
    String checkName,
    String event,
    Map<String, Object> fields,
    Exception ex
  ) {
    emit(Level.ERROR, checkName, event, fields, ex);
  }

  public void warn(String checkName, String event, Map<String, Object> fields) {
    emit(Level.WARN, checkName, event, fields, null);
  }

  public void info(String checkName, String event, Map<String, Object> fields) {
    emit(Level.INFO, checkName, event, fields, null);
  }

  public void debug(
    String checkName,
    String event,
    Map<String, Object> fields
  ) {
    emit(Level.DEBUG, checkName, event, fields, null);
  }

  // ─── Static API (used at boundaries that don't hold a context instance) ────

  public static void log(
    Level lvl,
    String runId,
    String configName,
    Id recordId,
    String checkName,
    String event,
    Map<String, Object> fields,
    Exception ex
  ) {
    new RecordHealthCheckLogger(runId, configName, recordId)
      .emit(lvl, checkName, event, fields, ex);
  }

  // ─── Sink ──────────────────────────────────────────────────────────────────

  private void emit(
    Level lvl,
    String checkName,
    String event,
    Map<String, Object> fields,
    Exception ex
  ) {
    String line = render(lvl, checkName, event, fields, ex);

    // The ONE place that decides where framework logs go. To switch to Nebula
    // Logger, replace this switch with (roughly):
    //   Logger.newEntry(toSystemLevel(lvl), line);
    //   // Logger.saveLog() is then called once at the transaction boundary
    //   // (controller) so async work is not flushed mid-evaluation.
    switch on lvl {
      when ERROR {
        System.debug(LoggingLevel.ERROR, line);
      }
      when WARN {
        System.debug(LoggingLevel.WARN, line);
      }
      when INFO {
        System.debug(LoggingLevel.INFO, line);
      }
      when DEBUG {
        System.debug(LoggingLevel.FINE, line);
      }
    }
  }

  /**
   * Renders one structured, greppable line:
   *   [RHC] WARN METADATA_INVALID | runId=.. user=.. config=.. check=.. <fields>
   * Fields are sorted by key so output is deterministic regardless of map order.
   */
  private String render(
    Level lvl,
    String checkName,
    String event,
    Map<String, Object> fields,
    Exception ex
  ) {
    List<String> parts = new List<String>();
    parts.add('runId=' + runId);
    parts.add('user=' + UserInfo.getUserId());
    if (String.isNotBlank(configName)) {
      parts.add('config=' + configName);
    }
    if (String.isNotBlank(checkName)) {
      parts.add('check=' + sanitize(checkName, 120));
    }
    if (recordId != null) {
      parts.add('record=' + recordId);
    }
    if (fields != null && !fields.isEmpty()) {
      List<String> keys = new List<String>(fields.keySet());
      keys.sort();
      for (String k : keys) {
        parts.add(
          sanitize(k, 80) + '=' + sanitize(String.valueOf(fields.get(k)), 500)
        );
      }
    }

    String line =
      PREFIX +
      ' ' +
      lvl.name() +
      ' ' +
      sanitize(event, 120) +
      ' | ' +
      String.join(parts, ' ');

    if (ex != null) {
      line +=
        ' | ' +
        sanitize(ex.getTypeName(), 120) +
        ': ' +
        sanitize(ex.getMessage(), 1000) +
        ' stack=' +
        sanitize(ex.getStackTraceString(), 2000);
    }
    return line;
  }

  @TestVisible
  private static String sanitize(String value, Integer maxLength) {
    if (value == null)
      return null;
    String cleaned = value.replaceAll('[\\r\\n\\t]', ' ').trim();
    Integer effectiveMax = maxLength == null || maxLength < 1 ? 500 : maxLength;
    return cleaned.length() <= effectiveMax
      ? cleaned
      : cleaned.substring(0, effectiveMax);
  }

  /** Normalizes caller-supplied correlation/configuration identifiers. */
  public static String normalizeIdentifier(String value, Integer maxLength) {
    return sanitize(value, maxLength);
  }
}
