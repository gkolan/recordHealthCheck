String report = RecordHealthCheckMetadataValidator.validateAsJson();
System.debug(LoggingLevel.INFO, report);
List<Object> issues = (List<Object>) JSON.deserializeUntyped(report);
for (Object issueValue : issues) {
  Map<String, Object> issue = (Map<String, Object>) issueValue;
  System.assertNotEquals('ERROR', issue.get('severity'), report);
}
