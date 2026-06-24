/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

// SCAN-39: declare a sharing model explicitly for consistency with the rest of
// the framework. This is a pure data holder (no SOQL/DML), so the keyword has no
// behavioral effect — it just removes the "sharing not specified" ambiguity.
public with sharing class RecordHealthCheckContext {
  public Id recordId;
  public String objectApiName;
  public SObject record;
  public Map<String, Object> parameters; // parsed from ApexSettingsJson__c; empty map when blank
  public String checkDeveloperName;
}
