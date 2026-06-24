/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Tests for ApprovalInactiveApproverCheck.
 *
 * The Advanced Approvals managed package is not assumed to be installed, so the
 * package-dependent dynamic query is exercised against a standard object
 * (Account configured as the "approval" object) and the inactive-user logic is
 * exercised directly with real inactive User records.
 */
@IsTest
private class ApprovalInactiveApproverCheckTest {
  @IsTest
  static void missingApprovalObjectReturnsUnableToEvaluate() {
    RecordHealthCheckContext context = new RecordHealthCheckContext();
    context.recordId = UserInfo.getUserId();
    context.parameters = new Map<String, Object>{
      'approvalObject' => 'sbaa__Definitely_Not_Installed__c'
    };

    RecordHealthCheckResult result = new ApprovalInactiveApproverCheck()
      .evaluate(context);

    System.assertEquals('UNABLE_TO_EVALUATE', result.status);
    System.assertEquals('OBJECT_NOT_FOUND', result.reasonCode);
  }

  @IsTest
  static void badFieldNameReturnsUnableToEvaluate() {
    Account account = new Account(Name = 'RHC Approval Bad Field');
    insert account;

    RecordHealthCheckContext context = new RecordHealthCheckContext();
    context.recordId = account.Id;
    context.parameters = new Map<String, Object>{
      'approvalObject' => 'Account',
      'targetField' => 'Id',
      'userField' => 'Not_A_Real_Field__c',
      'statusField' => 'Name',
      'pendingStatuses' => new List<Object>{ account.Name }
    };

    RecordHealthCheckResult result = new ApprovalInactiveApproverCheck()
      .evaluate(context);

    System.assertEquals('UNABLE_TO_EVALUATE', result.status);
    System.assertEquals('INVALID_SOQL_TEMPLATE', result.reasonCode);
  }

  @IsTest
  static void dynamicQueryAgainstActiveOwnerPasses() {
    // Drive the dynamic query path without the managed package by treating
    // Account as the approval object: the owner (running, active user) stands in
    // for the assigned approver, so the check passes.
    Account account = new Account(Name = 'RHC Approval Active Owner');
    insert account;

    RecordHealthCheckContext context = new RecordHealthCheckContext();
    context.recordId = account.Id;
    context.parameters = new Map<String, Object>{
      'approvalObject' => 'Account',
      'targetField' => 'Id',
      'userField' => 'OwnerId',
      'statusField' => 'Name',
      'pendingStatuses' => new List<Object>{ account.Name }
    };

    RecordHealthCheckResult result = new ApprovalInactiveApproverCheck()
      .evaluate(context);

    System.assertEquals(
      'PASS',
      result.status,
      'An active assigned user should pass.'
    );
  }

  @IsTest
  static void emptyAssignedUsersPasses() {
    ApprovalInactiveApproverCheck check = new ApprovalInactiveApproverCheck();
    ApprovalInactiveApproverCheck.Settings settings = check.resolveSettings(
      null
    );

    RecordHealthCheckResult passNull = check.buildResult(
      null,
      new RecordHealthCheckResult(),
      settings
    );
    System.assertEquals('PASS', passNull.status);

    RecordHealthCheckResult passEmpty = check.buildResult(
      new Set<Id>(),
      new RecordHealthCheckResult(),
      settings
    );
    System.assertEquals('PASS', passEmpty.status);
  }

  @IsTest
  static void allAssignedUsersActivePasses() {
    ApprovalInactiveApproverCheck check = new ApprovalInactiveApproverCheck();
    ApprovalInactiveApproverCheck.Settings settings = check.resolveSettings(
      null
    );

    RecordHealthCheckResult result = check.buildResult(
      new Set<Id>{ UserInfo.getUserId() },
      new RecordHealthCheckResult(),
      settings
    );

    System.assertEquals(
      'PASS',
      result.status,
      'The running user is active, so there are no inactive approvers.'
    );
  }

  @IsTest
  static void inactiveAssignedUserFailsAndNamesTheUser() {
    User inactive = createInactiveUser();
    // Name is a derived field, populated on the persisted record (FirstName +
    // LastName), so read it back to compare against the message.
    String inactiveName = [SELECT Name FROM User WHERE Id = :inactive.Id].Name;

    ApprovalInactiveApproverCheck check = new ApprovalInactiveApproverCheck();
    ApprovalInactiveApproverCheck.Settings settings = check.resolveSettings(
      null
    );

    RecordHealthCheckResult result = check.buildResult(
      new Set<Id>{ inactive.Id, UserInfo.getUserId() },
      new RecordHealthCheckResult(),
      settings
    );

    System.assertEquals('FAIL', result.status);
    System.assertEquals('1 inactive', result.actualValue);
    System.assertEquals('0 inactive', result.expectedValue);
    System.assert(
      result.message.contains(inactiveName),
      'Message should name the inactive approver: ' + result.message
    );
  }

  @IsTest
  static void resolveSettingsReadsAllOverrides() {
    ApprovalInactiveApproverCheck check = new ApprovalInactiveApproverCheck();

    ApprovalInactiveApproverCheck.Settings defaults = check.resolveSettings(
      new Map<String, Object>()
    );
    System.assertEquals(
      ApprovalInactiveApproverCheck.DEFAULT_APPROVAL_OBJECT,
      defaults.approvalObject
    );
    System.assertEquals(1, defaults.pendingStatuses.size());

    ApprovalInactiveApproverCheck.Settings custom = check.resolveSettings(
      new Map<String, Object>{
        'approvalObject' => 'My_Approval__c',
        'targetField' => 'My_Target__c',
        'userField' => 'My_User__c',
        'statusField' => 'My_Status__c',
        'pendingStatuses' => new List<Object>{ 'Requested', 'Pending', '  ' },
        'maxNames' => '3'
      }
    );
    System.assertEquals('My_Approval__c', custom.approvalObject);
    System.assertEquals('My_Target__c', custom.targetField);
    System.assertEquals('My_User__c', custom.userField);
    System.assertEquals('My_Status__c', custom.statusField);
    System.assertEquals(2, custom.pendingStatuses.size());
    System.assertEquals(3, custom.maxNames);

    // Blank strings and out-of-range / unparseable maxNames keep defaults.
    ApprovalInactiveApproverCheck.Settings fallback = check.resolveSettings(
      new Map<String, Object>{
        'approvalObject' => '   ',
        'maxNames' => 'not-a-number',
        'pendingStatuses' => new List<Object>{}
      }
    );
    System.assertEquals(
      ApprovalInactiveApproverCheck.DEFAULT_APPROVAL_OBJECT,
      fallback.approvalObject
    );
    System.assertEquals(5, fallback.maxNames);
    System.assertEquals(1, fallback.pendingStatuses.size());

    ApprovalInactiveApproverCheck.Settings outOfRange = check.resolveSettings(
      new Map<String, Object>{ 'maxNames' => '999' }
    );
    System.assertEquals(5, outOfRange.maxNames);
  }

  @IsTest
  static void buildMessageTruncatesLongLists() {
    List<String> two = new List<String>{ 'Ann Aaron', 'Ben Boyd' };
    String shortMessage = ApprovalInactiveApproverCheck.buildMessage(two, 5);
    System.assert(shortMessage.contains('Ann Aaron'));
    System.assert(shortMessage.contains('Ben Boyd'));
    System.assert(
      !shortMessage.contains('more'),
      'No overflow indicator when every name fits.'
    );

    List<String> many = new List<String>{
      'Ann Aaron',
      'Ben Boyd',
      'Cy Cole',
      'Di Dale'
    };
    String longMessage = ApprovalInactiveApproverCheck.buildMessage(many, 2);
    System.assert(longMessage.contains('Ann Aaron'));
    System.assert(longMessage.contains('Ben Boyd'));
    System.assert(
      longMessage.contains('(+2 more)'),
      'Overflow indicator should report the hidden count: ' + longMessage
    );
  }

  private static User createInactiveUser() {
    List<Profile> standardProfiles = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    Profile standard = standardProfiles.isEmpty()
      ? [SELECT Id FROM Profile LIMIT 1]
      : standardProfiles[0];
    String unique = 'rhc.inactive.' + DateTime.now().getTime();
    User inactive = new User(
      FirstName = 'Inactive',
      LastName = 'Approver',
      Alias = 'rhcinact',
      Email = 'rhc.inactive.approver@example.com',
      Username = unique + '@example.com.invalid',
      ProfileId = standard.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      IsActive = false
    );
    insert inactive;
    return inactive;
  }
}
