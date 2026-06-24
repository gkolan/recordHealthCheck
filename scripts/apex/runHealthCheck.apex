// ─── Record Health Check — Execute Anonymous Runner ───────────────────────────
//
// Usage:
//   1. Set CONFIG_NAME to the DeveloperName of the Record_Health_Check_Set__mdt
//      you want to run (e.g. 'Account_Data_Quality').
//   2. Set RECORD_ID to the Salesforce Id of the record under test.
//   3. Run via: sf apex run --file scripts/apex/runHealthCheck.apex
//      or paste into Developer Console → Execute Anonymous.
//
// Output: structured results are written to System.debug. Open the debug log
// (or use --json with the CLI) to review every check's status, reason code,
// message, duration, and — if DebugMode__c is enabled on the Check Set —
// the full internal detail message.
// ─────────────────────────────────────────────────────────────────────────────

final String CONFIG_NAME = 'Account_Data_Quality'; // ← change me
final Id RECORD_ID = '001000000000001AAA'; // ← change me

// Correlation id stamped on every [RHC] log line for this run. Grep the debug
// log for it to isolate this run from everything else. Override with your own
// value (e.g. a ticket number) if you like.
final String RUN_ID =
  'anon-' +
  String.valueOf(Datetime.now().getTime()) +
  '-' +
  String.valueOf(Math.abs(Crypto.getRandomInteger()));

// NOTE: every [RHC] line is attributed to UserInfo.getUserId() — i.e. WHOEVER
// RUNS THIS SCRIPT. Anonymous Apex cannot impersonate another user; to evaluate
// as a specific user (their FLS + their id on the log), use an Apex test with
// System.runAs(thatUser). See the test snippet at the bottom of this file.

// ─── Bootstrap ───────────────────────────────────────────────────────────────

System.debug('');
System.debug(
  '╔══════════════════════════════════════════════════════════════╗'
);
System.debug(
  '║         RECORD HEALTH CHECK — EXECUTE ANONYMOUS RUNNER       ║'
);
System.debug(
  '╚══════════════════════════════════════════════════════════════╝'
);
System.debug('  Config  : ' + CONFIG_NAME);
System.debug('  Record  : ' + RECORD_ID);
System.debug('  Run id  : ' + RUN_ID + '   ← grep the debug log for this');
System.debug('  Run at  : ' + System.now());
System.debug(
  '  Run by  : ' + UserInfo.getUserName() + ' (' + UserInfo.getUserId() + ')'
);
System.debug('');

// ─── Load definition (validates config + record type) ────────────────────────

RecordHealthCheckConfigService configService = new RecordHealthCheckConfigService();
RecordHealthCheckDefinitionResponse defResponse;

try {
  defResponse = configService.getDefinitionResponse(CONFIG_NAME, RECORD_ID);
} catch (RecordHealthCheckConfigService.ConfigException ex) {
  System.debug(
    LoggingLevel.ERROR,
    '✗ CONFIG ERROR [' + ex.reasonCode + ']: ' + ex.getMessage()
  );
  return;
}

System.debug('  Title   : ' + defResponse.displayTitle);
System.debug(
  '  Checks  : ' +
    defResponse.checks.size() +
    (defResponse.checksOmittedByLimit
      ? ' (of ' + defResponse.totalAvailableCheckCount + ' — limit reached)'
      : '')
);
System.debug(
  '  Debug   : ' +
  (defResponse.debugMode == true
    ? 'ON ← adminDetailMessage will be populated'
    : 'off')
);
System.debug('');
System.debug('──────────────────────────────────────────────────────────────');

// ─── Run each check ───────────────────────────────────────────────────────────

RecordHealthCheckEngine engine = new RecordHealthCheckEngine();

Integer passCount = 0;
Integer failCount = 0;
Integer skipCount = 0;
Integer unableCount = 0;
Integer errorCount = 0;

Integer checkIndex = 0;
for (RecordHealthCheckDefinition def : defResponse.checks) {
  checkIndex++;
  RecordHealthCheckResult result = engine.evaluate(
    CONFIG_NAME,
    def.developerName,
    RECORD_ID,
    RUN_ID
  );

  // Status icon
  String icon;
  if (result.status == 'PASS') {
    icon = '✓';
    passCount++;
  } else if (result.status == 'FAIL') {
    icon = '✗';
    failCount++;
  } else if (result.status == 'SKIPPED') {
    icon = '–';
    skipCount++;
  } else if (result.status == 'UNABLE_TO_EVALUATE') {
    icon = '?';
    unableCount++;
  } else {
    icon = '!';
    errorCount++;
  }

  String statusLabel =
    result.status +
    (String.isNotBlank(result.severity) ? '/' + result.severity : '');

  // ── Check block ──────────────────────────────────────────────────────────
  System.debug('');
  System.debug('  Check ' + checkIndex + ' of ' + defResponse.checks.size());
  System.debug('  Name   : ' + def.label);
  System.debug('  Key    : ' + def.developerName);
  System.debug(
    '  Status : ' + icon + ' ' + statusLabel + '  (' + result.durationMs + 'ms)'
  );

  if (result.status != 'PASS' && String.isNotBlank(result.reasonCode)) {
    System.debug('  Reason : ' + result.reasonCode);
  }
  if (String.isNotBlank(result.message)) {
    System.debug('  Msg    : ' + result.message);
  }
  if (String.isNotBlank(result.adminDetailMessage)) {
    System.debug('  Detail : ' + result.adminDetailMessage);
  }

  System.debug('  ··········································');
}

// ─── Summary ─────────────────────────────────────────────────────────────────

System.debug('');
System.debug('──────────────────────────────────────────────────────────────');
System.debug('SUMMARY');
System.debug('  ✓ Passed        : ' + passCount);
System.debug('  ✗ Failed        : ' + failCount);
System.debug('  – Skipped       : ' + skipCount);
System.debug('  ? Unable        : ' + unableCount);
System.debug('  ! Errors        : ' + errorCount);
System.debug('  Total evaluated : ' + defResponse.checks.size());
System.debug('  Run id          : ' + RUN_ID);
System.debug('──────────────────────────────────────────────────────────────');

// ─────────────────────────────────────────────────────────────────────────────
// To evaluate AS A SPECIFIC USER (their FLS + their id on every [RHC] log line),
// anonymous Apex won't do it — System.runAs only works in a test. Add a method
// like this to an @isTest class and run it:
//
//   @isTest
//   static void runAsSpecificUser() {
//       User u = [SELECT Id FROM User WHERE Username = 'agent@acme.com' LIMIT 1];
//       System.runAs(u) {
//           // Inside this block UserInfo.getUserId() == u.Id, WITH USER_MODE
//           // enforces u's FLS, and every [RHC] line is attributed to u.
//           new RecordHealthCheckEngine().evaluate(
//               'Account_Data_Quality', 'Account_DQ_BillingCity',
//               someRecordId, 'runas-' + u.Id
//           );
//       }
//   }
// ─────────────────────────────────────────────────────────────────────────────
