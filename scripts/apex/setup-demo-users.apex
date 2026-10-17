// SmartStay: role for the admin (Hotel CEO) and the five demo staff users.
// Run once:  sf apex run --file scripts/apex/setup-demo-users.apex
//
// - The administrator running this script becomes the Hotel CEO (top of the role hierarchy)
//   and gets the SmartStay Administrator permission set.
// - Demo users use the "SmartStay Hotel Staff" profile (Salesforce Platform license) plus
//   one role-specific permission set. Users are created only while Platform licenses are free;
//   the debug log lists any user that could not be created.
// - No welcome emails are sent. Their email is the admin's own address, so "Reset Password"
//   emails reach the person running the demo.

Map<String, Id> roleIds = new Map<String, Id>();
for (UserRole role : [SELECT Id, DeveloperName FROM UserRole WHERE DeveloperName LIKE 'SmartStay_%']) {
    roleIds.put(role.DeveloperName, role.Id);
}
Map<String, Id> permissionSetIds = new Map<String, Id>();
for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name LIKE 'SmartStay_%']) {
    permissionSetIds.put(ps.Name, ps.Id);
}
Id staffProfileId = [SELECT Id FROM Profile WHERE Name = 'SmartStay Hotel Staff' LIMIT 1].Id;

// 1. Administrator = Hotel CEO
User admin = [SELECT Id, UserRoleId FROM User WHERE Id = :UserInfo.getUserId()];
if (admin.UserRoleId != roleIds.get('SmartStay_CEO')) {
    update new User(Id = admin.Id, UserRoleId = roleIds.get('SmartStay_CEO'));
}
if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :admin.Id
     AND PermissionSetId = :permissionSetIds.get('SmartStay_Administrator')] == 0) {
    insert new PermissionSetAssignment(AssigneeId = admin.Id, PermissionSetId = permissionSetIds.get('SmartStay_Administrator'));
}

// 2. Demo staff users: alias, first name, last name, role, permission set
List<List<String>> demoUsers = new List<List<String>>{
    new List<String>{ 'ssmgr', 'Meera', 'Kapoor (Manager)', 'SmartStay_Hotel_Manager', 'SmartStay_Hotel_Manager' },
    new List<String>{ 'ssrec1', 'Arjun', 'Mehta (Reception 1)', 'SmartStay_Receptionist', 'SmartStay_Receptionist' },
    new List<String>{ 'ssrec2', 'Priya', 'Nair (Reception 2)', 'SmartStay_Receptionist', 'SmartStay_Receptionist' },
    new List<String>{ 'sshk', 'Sunil', 'Yadav (Housekeeping)', 'SmartStay_Housekeeping', 'SmartStay_Housekeeping' },
    new List<String>{ 'ssacc', 'Kavita', 'Joshi (Accounts)', 'SmartStay_Accounts', 'SmartStay_Accounts' }
};

UserLicense platform = [SELECT TotalLicenses, UsedLicenses FROM UserLicense WHERE Name = 'Salesforce Platform' LIMIT 1];
Integer freeLicenses = platform.TotalLicenses - platform.UsedLicenses;
System.debug('Salesforce Platform licenses free before creating users: ' + freeLicenses);

String orgSuffix = UserInfo.getOrganizationId().substring(10, 15).toLowerCase();
Set<String> existingAliases = new Set<String>();
for (User u : [SELECT Alias FROM User WHERE Username LIKE '%@smartstay-%.demo']) {
    existingAliases.add(u.Alias);
}

List<User> usersToCreate = new List<User>();
Map<String, String> permissionSetByAlias = new Map<String, String>();
for (List<String> spec : demoUsers) {
    String alias = spec[0];
    if (existingAliases.contains(alias)) {
        System.debug('Already exists: ' + alias);
        continue;
    }
    if (usersToCreate.size() >= freeLicenses) {
        System.debug('NOT CREATED (no free Salesforce Platform license): ' + spec[1] + ' ' + spec[2]);
        continue;
    }
    usersToCreate.add(new User(
        Alias = alias,
        FirstName = spec[1],
        LastName = spec[2],
        Email = UserInfo.getUserEmail(),
        Username = alias + '@smartstay-' + orgSuffix + '.demo',
        ProfileId = staffProfileId,
        UserRoleId = roleIds.get(spec[3]),
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_IN',
        TimeZoneSidKey = 'Asia/Kolkata',
        UserPermissionsSFContentUser = false
    ));
    permissionSetByAlias.put(alias, spec[4]);
}
insert usersToCreate;

List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
for (User u : usersToCreate) {
    assignments.add(new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = permissionSetIds.get(permissionSetByAlias.get(u.Alias))
    ));
    System.debug('Created ' + u.Username + ' with ' + permissionSetByAlias.get(u.Alias));
}
insert assignments;
