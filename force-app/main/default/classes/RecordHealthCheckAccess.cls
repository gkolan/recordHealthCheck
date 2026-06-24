/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/** Central authorization checks for privileged Record Health Check features. */
public with sharing class RecordHealthCheckAccess {
  @TestVisible
  private static Boolean debugPermissionOverride;

  /** Raw evaluator/query/plugin details are restricted even when metadata enables debug mode. */
  public static Boolean canViewDebugDetails() {
    if (Test.isRunningTest() && debugPermissionOverride != null) {
      return debugPermissionOverride;
    }
    return FeatureManagement.checkPermission('Record_Health_Check_Debug');
  }
}
