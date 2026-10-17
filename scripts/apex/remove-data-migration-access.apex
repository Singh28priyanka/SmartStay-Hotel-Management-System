// Removes the temporary SmartStay Data Migration permission set from the current user
// after load-sample-data.apex has run. Without it, past-dated bookings are blocked again.
delete [
    SELECT Id FROM PermissionSetAssignment
    WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSet.Name = 'SmartStay_Data_Migration'
];
System.debug('SmartStay Data Migration access removed.');
