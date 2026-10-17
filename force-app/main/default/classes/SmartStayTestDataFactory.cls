/**
 * Builds fictional SmartStay records for Apex tests. Tests never rely on org data.
 * build* methods return unsaved records; create* methods insert them.
 */
@IsTest
public class SmartStayTestDataFactory {
    public static final String STAFF_PROFILE = 'SmartStay Hotel Staff';

    public static Room__c buildRoom(String roomType, Integer capacity, Decimal rate) {
        return new Room__c(
            Room_Type__c = roomType,
            Floor__c = 1,
            Capacity__c = capacity,
            Room_Rate__c = rate,
            Room_Status__c = SmartStayConstants.ROOM_AVAILABLE,
            Amenities__c = 'Wi-Fi;TV;AC'
        );
    }

    public static Room__c createRoom(String roomType, Integer capacity, Decimal rate) {
        Room__c room = buildRoom(roomType, capacity, rate);
        insert room;
        return room;
    }

    public static Guest__c buildGuest(Integer index) {
        String suffix = String.valueOf(index).leftPad(4, '0');
        return new Guest__c(
            First_Name__c = 'Test',
            Last_Name__c = 'Guest ' + suffix,
            Mobile__c = '+91 90000 0' + suffix,
            Email__c = 'test.guest' + suffix + '@example.com',
            Date_of_Birth__c = Date.newInstance(1990, 1, 15),
            ID_Type__c = 'Passport',
            ID_Number__c = 'TEST-ID-' + suffix
        );
    }

    public static Guest__c createGuest(Integer index) {
        Guest__c guest = buildGuest(index);
        insert guest;
        return guest;
    }

    /** Dates are offsets in days from today, so tests never depend on the run date. */
    public static Reservation__c buildReservation(
        Id guestId,
        Id roomId,
        Integer checkInOffset,
        Integer checkOutOffset,
        Integer guests
    ) {
        return new Reservation__c(
            Guest__c = guestId,
            Room__c = roomId,
            Check_In_Date__c = Date.today().addDays(checkInOffset),
            Check_Out_Date__c = Date.today().addDays(checkOutOffset),
            Number_of_Guests__c = guests
        );
    }

    public static Reservation__c createReservation(Id guestId, Id roomId, Integer checkInOffset, Integer checkOutOffset) {
        Reservation__c reservation = buildReservation(guestId, roomId, checkInOffset, checkOutOffset, 1);
        insert reservation;
        return reservation;
    }

    public static Hotel_Staff__c buildStaff(String name, String department, Boolean active) {
        return new Hotel_Staff__c(
            Name = name,
            Department__c = department,
            Mobile__c = '+91 98000 00000',
            Email__c = name.deleteWhitespace().toLowerCase() + '@example.com',
            Shift__c = 'Morning',
            Active__c = active
        );
    }

    public static Room__c reloadRoom(Id roomId) {
        return [SELECT Id, Name, Room_Status__c, Room_Rate__c FROM Room__c WHERE Id = :roomId];
    }

    public static Reservation__c reloadReservation(Id reservationId) {
        return [
            SELECT
                Id,
                Name,
                Reservation_Status__c,
                Booked_Rate__c,
                Number_of_Nights__c,
                Estimated_Amount__c,
                Confirmation_Email_Status__c,
                Room__c,
                Check_In_Date__c,
                Check_Out_Date__c
            FROM Reservation__c
            WHERE Id = :reservationId
        ];
    }

    /**
     * Creates a SmartStay staff user with a role and permission sets.
     * Call inside System.runAs(new User(Id = UserInfo.getUserId())) to avoid mixed-DML errors.
     */
    public static User createStaffUser(String alias, String roleDeveloperName, List<String> permissionSetNames) {
        Profile staffProfile = [SELECT Id FROM Profile WHERE Name = :STAFF_PROFILE LIMIT 1];
        UserRole role = [SELECT Id FROM UserRole WHERE DeveloperName = :roleDeveloperName LIMIT 1];
        String uniqueName = alias + '.' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@smartstay.test';
        User staffUser = new User(
            Alias = alias,
            Email = alias + '@example.com',
            EmailEncodingKey = 'UTF-8',
            FirstName = 'Test',
            LastName = alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_IN',
            ProfileId = staffProfile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            UserName = uniqueName,
            UserRoleId = role.Id,
            UserPermissionsSFContentUser = false
        );
        insert staffUser;

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet permissionSet : [SELECT Id FROM PermissionSet WHERE Name IN :permissionSetNames]) {
            assignments.add(new PermissionSetAssignment(AssigneeId = staffUser.Id, PermissionSetId = permissionSet.Id));
        }
        insert assignments;
        return staffUser;
    }

    /** Asserts that a DML exception was thrown and its message contains the expected text. */
    public static void assertDmlError(Exception caught, String expectedText) {
        Assert.isNotNull(caught, 'Expected the save to be rejected');
        Assert.isTrue(
            caught.getMessage().contains(expectedText),
            'Expected error containing "' + expectedText + '" but got: ' + caught.getMessage()
        );
    }
}
