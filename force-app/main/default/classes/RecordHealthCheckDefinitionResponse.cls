/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

public class RecordHealthCheckDefinitionResponse {
  @AuraEnabled
  public String displayTitle;
  @AuraEnabled
  public String displayDescription;
  @AuraEnabled
  public String triggerMode; // Automatic, Manual
  @AuraEnabled
  public String revealMode; // AllAtOnce, OneAtATime
  @AuraEnabled
  public String successDisplayMode; // Show, Hide
  @AuraEnabled
  public String skippedDisplayMode; // Show, Hide
  @AuraEnabled
  public Boolean stopOnFirstError;
  @AuraEnabled
  public Integer totalAvailableCheckCount; // active checks before framework cap truncation
  @AuraEnabled
  public Boolean checksOmittedByLimit; // true when active checks were omitted
  @AuraEnabled
  public Boolean debugMode; // mirrors DebugMode__c — tells LWC to show adminDetailMessage
  @AuraEnabled
  public List<RecordHealthCheckDefinition> checks;
}
