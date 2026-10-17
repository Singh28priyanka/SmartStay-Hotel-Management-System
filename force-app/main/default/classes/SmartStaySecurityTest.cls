/**
 * Security model: object permissions, field-level security and record sharing for
 * each SmartStay persona, checked as real users with System.runAs and USER_MODE
 * operations (plain Apex DML would run in system mode and prove nothing).
 */
@IsTest
private class SmartStaySecurityTest {
    /** Test users are created in setup with these aliases and an @smartstay.test username. */
    private static User staff(String alias) {
        return [SELECT Id FROM User WHERE Alias = :alias AND Username LIKE '%@smartstay.test' LIMIT 1];
    }

    @TestSetup
    static void setup() {
        User manager;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            manager = SmartStayTestDataFactory.createStaffUser(
                'ssmgr',
                'SmartStay_Hotel_Manager',
                new List<String>{ 'SmartStay_Hotel_Manager' }
            );
            SmartStayTestDataFactory.createStaffUser(
                'ssrec1',
                'SmartStay_Receptionist',
                new List<String>{ 'SmartStay_Receptionist' }
            );
            SmartStayTestDataFactory.createStaffUser(
                'ssrec2',
                'SmartStay_Receptionist',
                new List<String>{ 'SmartStay_Receptionist' }
            );
            SmartStayTestDataFactory.createStaffUser(
                'sshk',
                'SmartStay_Housekeeping',
                new List<String>{ 'SmartStay_Housekeeping' }
            );
            SmartStayTestDataFactory.createStaffUser(
                'ssacc',
                'SmartStay_Accounts',
                new List<String>{ 'SmartStay_Accounts' }
            );
        }
        // Rooms owned by a user inside the hotel role hierarchy, so the sharing rules apply.
        System.runAs(manager) {
            insert new List<Room__c>{
                SmartStayTestDataFactory.buildRoom('Double', 2, 3000),
                SmartStayTestDataFactory.buildRoom('Suite', 4, 9000)
            };
        }
    }

    /** Receptionist 1 creates a guest and a booking through user-mode DML. */
    private static Reservation__c bookAsReceptionist(User receptionist) {
        Reservation__c reservation;
        System.runAs(receptionist) {
            Guest__c guest = SmartStayTestDataFactory.buildGuest(1);
            Database.insert(guest, AccessLevel.USER_MODE);
            Id roomId = [SELECT Id FROM Room__c WHERE Room_Type__c = 'Double' WITH USER_MODE LIMIT 1].Id;
            reservation = SmartStayTestDataFactory.buildReservation(guest.Id, roomId, 3, 5, 2);
            Database.insert(reservation, AccessLevel.USER_MODE);
        }
        return reservation;
    }

    @IsTest
    static void receptionistCreatesAndEditsButCannotDeleteReservations() {
        User receptionist = staff('ssrec1');
        Reservation__c reservation = bookAsReceptionist(receptionist);

        System.runAs(receptionist) {
            Assert.isTrue(Schema.SObjectType.Reservation__c.isCreateable(), 'Create');
            Assert.isTrue(Schema.SObjectType.Reservation__c.isUpdateable(), 'Edit');
            Assert.isFalse(Schema.SObjectType.Reservation__c.isDeletable(), 'No delete');
            Assert.isFalse(Schema.SObjectType.Room__c.isUpdateable(), 'Rooms are read-only for the front desk');
            Assert.isFalse(
                Schema.SObjectType.Reservation__c.fields.Booked_Rate__c.isUpdateable(),
                'Booked rate is set by the system'
            );
            Assert.isTrue(Schema.SObjectType.Guest__c.fields.ID_Number__c.isAccessible(), 'Verifies guest ID');

            reservation.Special_Request__c = 'Ground floor please';
            Database.update(reservation, AccessLevel.USER_MODE);

            Boolean deleteBlocked = false;
            try {
                Database.DeleteResult result = Database.delete(reservation, false, AccessLevel.USER_MODE);
                deleteBlocked = !result.isSuccess();
            } catch (Exception e) {
                deleteBlocked = true;
            }
            Assert.isTrue(deleteBlocked, 'Receptionists cannot delete reservations');
        }
    }

    @IsTest
    static void receptionistsShareReservationsThroughSharingRule() {
        Reservation__c reservation = bookAsReceptionist(staff('ssrec1'));
        User secondReceptionist = staff('ssrec2');

        System.runAs(secondReceptionist) {
            List<Reservation__c> visible = [
                SELECT Id
                FROM Reservation__c
                WHERE Id = :reservation.Id
                WITH USER_MODE
            ];
            Assert.areEqual(1, visible.size(), 'Receptionist 2 sees Receptionist 1\'s booking (sharing rule)');
            Assert.isTrue(
                [SELECT RecordId, HasEditAccess FROM UserRecordAccess WHERE UserId = :secondReceptionist.Id AND RecordId = :reservation.Id]
                .HasEditAccess,
                'and can edit it for shift handover'
            );
        }
    }

    @IsTest
    static void housekeepingUpdatesRoomStatusOnly() {
        User housekeeper = staff('sshk');
        System.runAs(housekeeper) {
            Assert.isFalse(Schema.SObjectType.Reservation__c.isAccessible(), 'No reservation access');
            Assert.isFalse(Schema.SObjectType.Guest__c.isAccessible(), 'No guest access');
            Assert.isTrue(Schema.SObjectType.Room__c.fields.Room_Status__c.isUpdateable(), 'Can update status');
            Assert.isFalse(Schema.SObjectType.Room__c.fields.Room_Rate__c.isAccessible(), 'Cannot see rates');
            Assert.isFalse(Schema.SObjectType.Room__c.isCreateable(), 'Cannot create rooms');

            Room__c room = [SELECT Id FROM Room__c WHERE Room_Type__c = 'Suite' WITH USER_MODE LIMIT 1];
            room.Room_Status__c = SmartStayConstants.ROOM_CLEANING;
            Database.update(room, AccessLevel.USER_MODE);

            Boolean reservationQueryBlocked = false;
            try {
                List<Reservation__c> rows = [SELECT Id FROM Reservation__c WITH USER_MODE LIMIT 1];
            } catch (Exception e) {
                reservationQueryBlocked = true;
            }
            Assert.isTrue(reservationQueryBlocked, 'User-mode query of reservations is refused');
        }
        Assert.areEqual(
            SmartStayConstants.ROOM_CLEANING,
            [SELECT Room_Status__c FROM Room__c WHERE Room_Type__c = 'Suite' LIMIT 1].Room_Status__c
        );
    }

    @IsTest
    static void accountsReadsAmountsButNotIdentityOrRoomStatus() {
        Reservation__c reservation = bookAsReceptionist(staff('ssrec1'));
        User accounts = staff('ssacc');

        System.runAs(accounts) {
            Assert.isTrue(Schema.SObjectType.Reservation__c.fields.Estimated_Amount__c.isAccessible(), 'Sees amount');
            Assert.isFalse(Schema.SObjectType.Reservation__c.isUpdateable(), 'Read-only reservations');
            Assert.isFalse(Schema.SObjectType.Room__c.fields.Room_Status__c.isUpdateable(), 'Cannot change room status');
            Assert.isFalse(Schema.SObjectType.Guest__c.fields.ID_Number__c.isAccessible(), 'No guest ID number');
            Assert.isFalse(Schema.SObjectType.Guest__c.fields.Date_of_Birth__c.isAccessible(), 'No date of birth');

            Reservation__c visible = [
                SELECT Id, Estimated_Amount__c
                FROM Reservation__c
                WHERE Id = :reservation.Id
                WITH USER_MODE
            ];
            Assert.areEqual(6000, visible.Estimated_Amount__c, 'Shared read-only through the Accounts sharing rule');

            Guest__c guest = [SELECT Id, ID_Number__c FROM Guest__c LIMIT 1];
            SObject stripped = Security.stripInaccessible(AccessType.READABLE, new List<Guest__c>{ guest })
                .getRecords()[0];
            Assert.isFalse(stripped.isSet('ID_Number__c'), 'ID Number is removed for Accounts');
        }
    }

    @IsTest
    static void managerSeesAndManagesEverything() {
        Reservation__c reservation = bookAsReceptionist(staff('ssrec1'));
        User manager = staff('ssmgr');

        System.runAs(manager) {
            Assert.isTrue(Schema.SObjectType.Reservation__c.isDeletable(), 'Manager can delete');
            Assert.isTrue(Schema.SObjectType.Guest__c.fields.ID_Number__c.isAccessible(), 'Manager sees ID');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Reservation__c WHERE Id = :reservation.Id WITH USER_MODE],
                'View All Records'
            );
            reservation.Reservation_Status__c = SmartStayConstants.STATUS_CANCELLED;
            Database.update(reservation, AccessLevel.USER_MODE);
        }
        Assert.areEqual(
            SmartStayConstants.STATUS_CANCELLED,
            SmartStayTestDataFactory.reloadReservation(reservation.Id).Reservation_Status__c
        );
    }

    @IsTest
    static void soqlHelperEnforcesUserMode() {
        Reservation__c reservation = bookAsReceptionist(staff('ssrec1'));
        Id roomId = [SELECT Room__c FROM Reservation__c WHERE Id = :reservation.Id].Room__c;

        Boolean blocked = false;
        System.runAs(staff('sshk')) {
            try {
                SmartStayQueries.getReservationsForRoom(roomId);
            } catch (Exception e) {
                blocked = true;
            }
        }
        Assert.isTrue(blocked, 'Housekeeping cannot read reservations through the SOQL helper');
    }
}
