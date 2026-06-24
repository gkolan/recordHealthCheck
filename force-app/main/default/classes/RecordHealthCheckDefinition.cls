/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

public class RecordHealthCheckDefinition {
  @AuraEnabled
  public String developerName;
  @AuraEnabled
  public String label;
  @AuraEnabled
  public String description;
  @AuraEnabled
  public Decimal priority;
  @AuraEnabled
  public String dependsOnCheckDeveloperName; // null when no dependency
}
