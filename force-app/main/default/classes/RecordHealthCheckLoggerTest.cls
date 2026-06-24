/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

@isTest
private class RecordHealthCheckLoggerTest {
  // The logger writes to the Apex debug log (a side effect we cannot read back in
  // a test context), so these tests exercise every branch for coverage and assert
  // that no path throws. The rendered output is verified by reading debug logs in
  // the org; here we guarantee the facade is exception-safe for all inputs.

  @isTest
  static void instanceLevelsAllExecuteWithoutError() {
    RecordHealthCheckLogger logger = new RecordHealthCheckLogger(
      'run-123',
      'Account_Data_Quality',
      UserInfo.getUserId()
    );

    Test.startTest();
    logger.debug(
      'Some_Check',
      'START',
      new Map<String, Object>{ 'type' => 'Formula', 'debugMode' => true }
    );
    logger.info(
      'Some_Check',
      'RESULT',
      new Map<String, Object>{ 'status' => 'FAIL' }
    );
    logger.warn('Some_Check', 'METADATA_INVALID', null);
    logger.error(
      'Some_Check',
      'UNHANDLED_EXCEPTION',
      null,
      new System.NullPointerException()
    );
    Test.stopTest();

    System.assert(true, 'All instance log levels executed without throwing.');
  }

  @isTest
  static void staticEntryPointExecutesWithoutError() {
    Test.startTest();
    RecordHealthCheckLogger.log(
      RecordHealthCheckLogger.Level.ERROR,
      'run-456',
      'Account_Data_Quality',
      UserInfo.getUserId(),
      null,
      'CONFIG_UNEXPECTED',
      null,
      new System.NullPointerException()
    );
    Test.stopTest();

    System.assert(true, 'Static log entry point executed without throwing.');
  }

  @isTest
  static void blankRunIdAndNullRecordAreHandled() {
    // Defensive paths: missing correlation id and no record context must not throw.
    RecordHealthCheckLogger logger = new RecordHealthCheckLogger(
      null,
      null,
      null
    );

    Test.startTest();
    logger.info(null, 'NO_CONTEXT', new Map<String, Object>());
    Test.stopTest();

    System.assert(
      true,
      'Logger tolerated blank runId, null config, and null record.'
    );
  }
}
