/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/** Shared, side-effect-free validation primitives used at runtime and in CI. */
public with sharing class RecordHealthCheckConfigValidator {
  public static Boolean isValidObjectApiName(String objectApiName) {
    return String.isNotBlank(objectApiName) &&
      Schema.getGlobalDescribe().containsKey(objectApiName);
  }

  public static Boolean isValidApexPlugin(String className) {
    if (String.isBlank(className))
      return false;
    try {
      Type pluginType = Type.forName(className);
      return pluginType != null &&
        pluginType.newInstance() instanceof RecordHealthCheckRule;
    } catch (Exception ex) {
      return false;
    }
  }

  public static Boolean isJsonObject(String jsonText) {
    if (String.isBlank(jsonText))
      return true;
    try {
      Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
        jsonText
      );
      return parsed != null;
    } catch (Exception ex) {
      return false;
    }
  }
}
