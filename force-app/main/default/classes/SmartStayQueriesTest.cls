/**
 * Verifies each documented SOQL query returns the expected records.
 * The queries run WITH USER_MODE, so every test runs as a Hotel Manager user
 * (object and field access from the SmartStay_Hotel_Manager permission set)
 * rather than depending on the permissions of whoever runs the tests.
 */
@IsTest
private class SmartStayQueriesTest {
    @TestSetup
    static void setup() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            SmartStayTestDataFactory.createStaffUser(
                'ssqmgr',
                'SmartStay_Hotel_Manager',
                new List<String>{ 'SmartStay_Hotel_Manager' }
            );
        }
        Room__c doubleRoom = SmartStayTestDataFactory.buildRoom('Double', 2, 3000);
        Room__c suite = SmartStayTestDataFactory.buildRoom('Suite', 4, 9000);
        insert new List<Room__c>{ doubleRoom, suite };
        Guest__c anita = SmartStayTestDataFactory.buildGuest(1);
        Guest__c rahul = SmartStayTestDataFactory.buildGuest(2);
        insert new List<Guest__c>{ anita, rahul };

        List<Reservation__c> reservations = new List<Reservation__c>{
            SmartStayTestDataFactory.buildReservation(anita.Id, doubleRoom.Id, 2, 4, 1), // active
            SmartStayTestDataFactory.buildReservation(rahul.Id, doubleRoom.Id, 6, 9, 2), // will be cancelled
            SmartStayTestDataFactory.buildReservation(anita.Id, suite.Id, 10, 12, 3) // active
        };
        insert reservations;
        reservations[1].Reservation_Status__c = SmartStayConstants.STATUS_CANCELLED;
        update reservations[1];
    }

    private static User manager() {
        return [SELECT Id FROM User WHERE Alias = 'ssqmgr' AND Username LIKE '%@smartstay.test' LIMIT 1];
    }

    private static Room__c room(String roomType) {
        return [SELECT Id FROM Room__c WHERE Room_Type__c = :roomType LIMIT 1];
    }

    private static Guest__c guest(String lastName) {
        return [SELECT Id FROM Guest__c WHERE Last_Name__c = :lastName LIMIT 1];
    }

    @IsTest
    static void query1ReservationsForRoom() {
        System.runAs(manager()) {
            List<Reservation__c> rows = SmartStayQueries.getReservationsForRoom(room('Double').Id);
            Assert.areEqual(2, rows.size(), 'Both reservations of the room, including cancelled');
            Assert.isTrue(rows[0].Check_In_Date__c > rows[1].Check_In_Date__c, 'Newest stay first');
        }
    }

    @IsTest
    static void query2ReservationsForGuest() {
        System.runAs(manager()) {
            List<Reservation__c> rows = SmartStayQueries.getReservationsForGuest(guest('Guest 0001').Id);
            Assert.areEqual(2, rows.size(), 'Guest 0001 has two stays');
            Assert.areEqual('Suite', rows[0].Room_Type__c, 'Most recent stay is in the suite');
        }
    }

    @IsTest
    static void query3ActiveReservationsForRoom() {
        System.runAs(manager()) {
            List<Reservation__c> rows = SmartStayQueries.getActiveReservationsForRoom(room('Double').Id);
            Assert.areEqual(1, rows.size(), 'Cancelled reservation excluded');
            Assert.areEqual(SmartStayConstants.STATUS_CONFIRMED, rows[0].Reservation_Status__c);
        }
    }

    @IsTest
    static void query4ReservationsInDateRange() {
        System.runAs(manager()) {
            Date today = Date.today();
            Assert.areEqual(1, SmartStayQueries.getReservationsInDateRange(today, today.addDays(5)).size(), 'Days 2-4');
            Assert.areEqual(3, SmartStayQueries.getReservationsInDateRange(today, today.addDays(12)).size(), 'All three');
            Assert.areEqual(0, SmartStayQueries.getReservationsInDateRange(today.addDays(3), today.addDays(5)).size());

            Boolean rejected = false;
            try {
                SmartStayQueries.getReservationsInDateRange(today.addDays(5), today);
            } catch (IllegalArgumentException e) {
                rejected = true;
            }
            Assert.isTrue(rejected, 'End date before start date is rejected');
        }
    }

    @IsTest
    static void query5ParentToChildRoomWithReservations() {
        System.runAs(manager()) {
            Room__c result = SmartStayQueries.getRoomWithReservations(room('Double').Id);
            Assert.areEqual(2, result.Reservations__r.size(), 'Child reservations returned in the same query');
            Assert.isNull(SmartStayQueries.getRoomWithReservations(null), 'Unknown room returns null');
        }
    }

    @IsTest
    static void query6ChildToParentReservationsWithRoomAndGuest() {
        System.runAs(manager()) {
            List<Reservation__c> rows = SmartStayQueries.getReservationsWithRoomAndGuest(Date.today());
            Assert.areEqual(3, rows.size());
            Reservation__c first = rows[0];
            Assert.areEqual('Double', first.Room__r.Room_Type__c, 'Parent room field');
            Assert.areEqual(3000, first.Room__r.Room_Rate__c, 'Parent room rate');
            Assert.isTrue(first.Room__r.Name.startsWith('RM-'), 'Parent room number');
            Assert.areEqual('Test', first.Guest__r.First_Name__c, 'Parent guest field');
        }
    }

    @IsTest
    static void query7GuestWithReservations() {
        System.runAs(manager()) {
            Guest__c result = SmartStayQueries.getGuestWithReservations(guest('Guest 0001').Id);
            Assert.areEqual(2, result.Reservations__r.size());
        }
    }

    @IsTest
    static void query8CountByRoomType() {
        System.runAs(manager()) {
            Map<String, Integer> counts = SmartStayQueries.countReservationsByRoomType();
            Assert.areEqual(1, counts.get('Double'), 'Cancelled reservation not counted');
            Assert.areEqual(1, counts.get('Suite'));
        }
    }
}
