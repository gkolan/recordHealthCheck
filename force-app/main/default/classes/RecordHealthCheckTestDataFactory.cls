/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

@isTest
public class RecordHealthCheckTestDataFactory {
  public static final String HEALTHY_ACCOUNT_NAME_PREFIX = 'Record Health Test Account';

  public static void createTestRecords() {
    String token = uniqueToken();
    Account healthyAccount = new Account(
      Name = HEALTHY_ACCOUNT_NAME_PREFIX + ' ' + token,
      BillingStreet = '1 Test Way',
      BillingCity = 'Chicago',
      BillingState = 'IL',
      BillingPostalCode = '60601',
      BillingCountry = 'USA',
      ShippingStreet = '1 Test Way',
      ShippingCity = 'Chicago',
      ShippingState = 'IL',
      ShippingPostalCode = '60601',
      ShippingCountry = 'USA',
      Website = 'https://' + token.toLowerCase() + '.example.com',
      Phone = '312-555-' + token.right(4),
      Industry = 'Technology',
      Rating = 'Hot',
      AnnualRevenue = 1000000,
      NumberOfEmployees = 25,
      AccountNumber = token
    );

    populateRequiredFields(healthyAccount);
    insertAllowingDuplicateRules(new List<SObject>{ healthyAccount });
  }

  public static void createCoverageTestRecords() {
    createTestRecords();

    Account accountRecord = getHealthyAccount();
    createContacts(
      new List<Contact>{
        new Contact(
          LastName = 'Alpha',
          AccountId = accountRecord.Id,
          Title = 'Primary Contact',
          Email = 'alpha@example.com',
          Phone = '312-555-0101',
          MailingCity = accountRecord.BillingCity,
          MailingState = accountRecord.BillingState
        ),
        new Contact(
          LastName = 'Beta',
          AccountId = accountRecord.Id,
          Title = 'Secondary Contact',
          Email = 'beta@example.com',
          Phone = '312-555-0102',
          MailingCity = 'Evanston',
          MailingState = accountRecord.BillingState
        )
      }
    );
    createOpportunity(accountRecord.Id, 'Coverage Opportunity', 50000);
    createCompletedTask(accountRecord.Id);
  }

  public static Account createAccount(String name) {
    Account accountRecord = new Account(Name = name);
    populateRequiredFields(accountRecord);
    insertAllowingDuplicateRules(new List<SObject>{ accountRecord });
    return accountRecord;
  }

  public static Account createDeletedAccount(String name) {
    Account accountRecord = createAccount(name);
    delete accountRecord;
    return accountRecord;
  }

  public static void createEmailCoverageContacts(Id accountId) {
    createContacts(
      new List<Contact>{
        new Contact(LastName = 'No Email', AccountId = accountId),
        new Contact(
          LastName = 'Has Email',
          AccountId = accountId,
          Email = 'healthy@example.com'
        )
      }
    );
  }

  public static void createMatchingCityContacts(
    Id accountId,
    String mailingCity
  ) {
    createContacts(
      new List<Contact>{
        new Contact(
          LastName = 'Chicago One',
          AccountId = accountId,
          MailingCity = mailingCity
        ),
        new Contact(
          LastName = 'Chicago Two',
          AccountId = accountId,
          MailingCity = mailingCity
        )
      }
    );
  }

  public static Opportunity createOpportunity(
    Id accountId,
    String name,
    Decimal amount
  ) {
    Opportunity opportunityRecord = new Opportunity(
      Name = name,
      AccountId = accountId,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      Amount = amount
    );
    populateRequiredFields(opportunityRecord);
    insertAllowingDuplicateRules(new List<SObject>{ opportunityRecord });
    return opportunityRecord;
  }

  public static Task createCompletedTask(Id whatId) {
    Task taskRecord = new Task(
      Subject = 'Coverage Task',
      WhatId = whatId,
      Status = 'Completed',
      ActivityDate = Date.today()
    );
    populateRequiredFields(taskRecord);
    insertAllowingDuplicateRules(new List<SObject>{ taskRecord });
    return taskRecord;
  }

  private static void createContacts(List<Contact> contacts) {
    List<SObject> records = new List<SObject>();
    for (Contact contactRecord : contacts) {
      populateRequiredFields(contactRecord);
      records.add(contactRecord);
    }
    insertAllowingDuplicateRules(records);
  }

  private static String uniqueToken() {
    String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    return token.length() > 8 ? token.right(8) : token;
  }

  private static void insertAllowingDuplicateRules(List<SObject> records) {
    Database.DMLOptions dmlOptions = new Database.DMLOptions();
    dmlOptions.DuplicateRuleHeader.allowSave = true;
    dmlOptions.DuplicateRuleHeader.runAsCurrentUser = true;

    Database.SaveResult[] saveResults = Database.insert(records, dmlOptions);
    for (Database.SaveResult saveResult : saveResults) {
      System.assertEquals(
        true,
        saveResult.isSuccess(),
        'Test data insert failed: ' + JSON.serialize(saveResult.getErrors())
      );
    }
  }

  private static void populateRequiredFields(SObject record) {
    Map<String, Schema.SObjectField> fields = record.getSObjectType()
      .getDescribe()
      .fields.getMap();
    for (String fieldName : fields.keySet()) {
      Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName)
        .getDescribe();
      if (
        record.get(fieldName) != null ||
        fieldName == 'Id' ||
        fieldDescribe.isNillable() ||
        fieldDescribe.isDefaultedOnCreate() ||
        !fieldDescribe.isCreateable()
      ) {
        continue;
      }

      Object value = sampleValueFor(fieldDescribe);
      if (value != null) {
        record.put(fieldName, value);
      }
    }
  }

  private static Object sampleValueFor(
    Schema.DescribeFieldResult fieldDescribe
  ) {
    Schema.DisplayType fieldType = fieldDescribe.getType();
    if (fieldType == Schema.DisplayType.String) {
      return 'Test ' + uniqueToken();
    }
    if (fieldType == Schema.DisplayType.TextArea) {
      return 'Test data';
    }
    if (fieldType == Schema.DisplayType.Email) {
      return 'record.health+' + uniqueToken().toLowerCase() + '@example.com';
    }
    if (fieldType == Schema.DisplayType.Phone) {
      return '312-555-' + uniqueToken().right(4);
    }
    if (fieldType == Schema.DisplayType.Url) {
      return 'https://' + uniqueToken().toLowerCase() + '.example.com';
    }
    if (fieldType == Schema.DisplayType.Boolean) {
      return false;
    }
    if (
      fieldType == Schema.DisplayType.Integer ||
      fieldType == Schema.DisplayType.Double ||
      fieldType == Schema.DisplayType.Currency ||
      fieldType == Schema.DisplayType.Percent
    ) {
      return 1;
    }
    if (fieldType == Schema.DisplayType.Date) {
      return Date.today();
    }
    if (fieldType == Schema.DisplayType.DateTime) {
      return System.now();
    }
    if (fieldType == Schema.DisplayType.Picklist) {
      for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
        if (entry.isActive()) {
          return entry.getValue();
        }
      }
    }
    return null;
  }

  public static Account getHealthyAccount() {
    String namePattern = HEALTHY_ACCOUNT_NAME_PREFIX + '%';
    return [
      SELECT
        Id,
        Name,
        BillingStreet,
        BillingCity,
        BillingState,
        BillingPostalCode,
        BillingCountry,
        ShippingStreet,
        ShippingCity,
        ShippingState,
        ShippingPostalCode,
        ShippingCountry,
        Website,
        Phone,
        Industry,
        Rating,
        AnnualRevenue
      FROM Account
      WHERE Name LIKE :namePattern
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  public static Record_Health_Check_Rule__mdt queryRule(String developerName) {
    return [
      SELECT
        DeveloperName,
        MasterLabel,
        CheckName__c,
        Tooltip__c,
        RunOrder__c,
        IsActive__c,
        CheckMethod__c,
        Severity__c,
        PassFailFormula__c,
        ValueToTest__c,
        DataQuery__c,
        FieldToRead__c,
        CompareAgainst__c,
        FixedValue__c,
        RecordFormulaValue__c,
        CompareToQuery__c,
        CompareToField__c,
        Operator__c,
        WhenMultipleRows__c,
        WhenZeroRows__c,
        WhenValueIsEmpty__c,
        MessageWhenFailed__c,
        MessageWhenCannotRun__c,
        ApexClass__c,
        ApexSettingsJson__c,
        MaxRows__c,
        RequiresCheck__c,
        RunThisCheckWhen__c,
        RunWhenFormula__c,
        RunWhenCountQuery__c,
        CountOperator__c,
        CountThreshold__c,
        Record_Health_Check_Set__c,
        Record_Health_Check_Set__r.IsActive__c,
        Record_Health_Check_Set__r.ObjectApiName__c
      FROM Record_Health_Check_Rule__mdt
      WHERE DeveloperName = :developerName
      LIMIT 1
    ];
  }
}
