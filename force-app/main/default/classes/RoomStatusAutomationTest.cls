/**
 * Room status automation end to end: Apex (RoomStatusService, trigger, nightly job)
 * and the record-triggered Flows that run in the same transactions:
 *   Flow 1 Reservation Confirmation, Flow 2 Check-In, Flow 3 Check-Out,
 *   Flow 4 Room Availability, Flow 5 Cancellation, Flow 6 Staff Assignment Guard.
 */
@IsTest
private class RoomStatusAutomationTest {
    @TestSetup
    static void setup() {
        insert new List<Room__c>{
            SmartStayTestDataFactory.buildRoom('Double', 2, 3000),
            SmartStayTestDataFactory.buildRoom('Suite', 4, 9000)
        };
        insert SmartStayTestDataFactory.buildGuest(1);
    }

    private static Id roomId(String roomType) {
        return [SELECT Id FROM Room__c WHERE Room_Type__c = :roomType LIMIT 1].Id;
    }

    private static Id guestId() {
        return [SELECT Id FROM Guest__c LIMIT 1].Id;
    }

    private static String statusOf(Id roomId) {
        return SmartStayTestDataFactory.reloadRoom(roomId).Room_Status__c;
    }

    private static void setReservationStatus(Reservation__c reservation, String status) {
        reservation.Reservation_Status__c = status;
        update reservation;
    }

    // 12. Room status logic: arrival today -> Reserved -> Occupied -> Cleaning -> Available
    @IsTest
    static void roomFollowsTheGuestThroughTheStay() {
        Id doubleRoomId = roomId('Double');

        Test.startTest();
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 0, 2);
        Assert.areEqual(SmartStayConstants.ROOM_RESERVED, statusOf(doubleRoomId), 'Arrival today reserves the room');

        setReservationStatus(reservation, SmartStayConstants.STATUS_CHECKED_IN);
        Assert.areEqual(SmartStayConstants.ROOM_OCCUPIED, statusOf(doubleRoomId), 'Flow 2: check-in -> Occupied');

        setReservationStatus(reservation, SmartStayConstants.STATUS_CHECKED_OUT);
        Assert.areEqual(SmartStayConstants.ROOM_CLEANING, statusOf(doubleRoomId), 'Flow 3: check-out -> Cleaning');

        update new Room__c(Id = doubleRoomId, Room_Status__c = SmartStayConstants.ROOM_AVAILABLE);
        Test.stopTest();

        Assert.areEqual(SmartStayConstants.ROOM_AVAILABLE, statusOf(doubleRoomId), 'Housekeeping marks it ready');
        Assert.areEqual(
            SmartStayConstants.STATUS_CHECKED_OUT,
            SmartStayTestDataFactory.reloadReservation(reservation.Id).Reservation_Status__c,
            'Reservation history is preserved'
        );
    }

    @IsTest
    static void futureBookingLeavesRoomAvailableToday() {
        Id doubleRoomId = roomId('Double');
        SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 5, 7);
        Assert.areEqual(
            SmartStayConstants.ROOM_AVAILABLE,
            statusOf(doubleRoomId),
            'Room status describes today; future bookings are protected by dates, not status'
        );
    }

    // Flow 1: confirmation email sent once and recorded
    @IsTest
    static void confirmationFlowEmailsGuestOnce() {
        Test.startTest();
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), roomId('Double'), 3, 5);
        Test.stopTest();

        Reservation__c saved = SmartStayTestDataFactory.reloadReservation(reservation.Id);
        Assert.areEqual('Sent', saved.Confirmation_Email_Status__c, 'Flow 1 sent the email and recorded it');

        // Editing the reservation must not send another email (Flow 1 runs on create only,
        // and only while the status field is blank).
        reservation.Special_Request__c = 'Airport pickup';
        update reservation;
        Assert.areEqual('Sent', SmartStayTestDataFactory.reloadReservation(reservation.Id).Confirmation_Email_Status__c);
    }

    @IsTest
    static void suppressedReservationsAreNotEmailed() {
        Reservation__c reservation = SmartStayTestDataFactory.buildReservation(guestId(), roomId('Double'), 3, 5, 1);
        reservation.Confirmation_Email_Status__c = 'Suppressed';
        insert reservation;
        Assert.areEqual(
            'Suppressed',
            SmartStayTestDataFactory.reloadReservation(reservation.Id).Confirmation_Email_Status__c,
            'Flow 1 entry criteria skip records that already have a status'
        );
    }

    // Flow 5: cancellation frees the room only when nothing else needs it
    @IsTest
    static void cancellingTodaysArrivalFreesTheRoom() {
        Id doubleRoomId = roomId('Double');
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 0, 2);
        Assert.areEqual(SmartStayConstants.ROOM_RESERVED, statusOf(doubleRoomId));

        Test.startTest();
        setReservationStatus(reservation, SmartStayConstants.STATUS_CANCELLED);
        Test.stopTest();

        Assert.areEqual(SmartStayConstants.ROOM_AVAILABLE, statusOf(doubleRoomId), 'Flow 5 recalculated the room');
    }

    @IsTest
    static void cancellationKeepsMaintenance() {
        Id doubleRoomId = roomId('Double');
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 0, 2);
        update new Room__c(Id = doubleRoomId, Room_Status__c = SmartStayConstants.ROOM_MAINTENANCE);

        setReservationStatus(reservation, SmartStayConstants.STATUS_CANCELLED);

        Assert.areEqual(SmartStayConstants.ROOM_MAINTENANCE, statusOf(doubleRoomId), 'Maintenance is never overridden');
    }

    @IsTest
    static void cancellingOneBookingKeepsRoomReservedForAnotherArrival() {
        Id doubleRoomId = roomId('Double');
        Reservation__c tomorrow = SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 1, 3);
        Reservation__c today = SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 0, 1);
        Assert.areEqual(SmartStayConstants.ROOM_RESERVED, statusOf(doubleRoomId));

        // Cancelling tomorrow's booking must not free a room someone arrives in today.
        setReservationStatus(tomorrow, SmartStayConstants.STATUS_CANCELLED);
        Assert.areEqual(SmartStayConstants.ROOM_RESERVED, statusOf(doubleRoomId), 'Today\'s arrival still needs it');

        setReservationStatus(today, SmartStayConstants.STATUS_CANCELLED);
        Assert.areEqual(SmartStayConstants.ROOM_AVAILABLE, statusOf(doubleRoomId), 'Nothing needs it any more');
    }

    @IsTest
    static void movingTodaysBookingUpdatesBothRooms() {
        Id doubleRoomId = roomId('Double');
        Id suiteId = roomId('Suite');
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 0, 2);

        reservation.Room__c = suiteId;
        update reservation;

        Assert.areEqual(SmartStayConstants.ROOM_AVAILABLE, statusOf(doubleRoomId), 'Old room released');
        Assert.areEqual(SmartStayConstants.ROOM_RESERVED, statusOf(suiteId), 'New room reserved');
    }

    // Flow 4: a room cannot be made Available while a guest is in it
    @IsTest
    static void occupiedRoomCannotBeMarkedAvailable() {
        Id doubleRoomId = roomId('Double');
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 0, 2);
        setReservationStatus(reservation, SmartStayConstants.STATUS_CHECKED_IN);

        Exception caught;
        try {
            update new Room__c(Id = doubleRoomId, Room_Status__c = SmartStayConstants.ROOM_AVAILABLE);
        } catch (DmlException e) {
            caught = e;
        }
        SmartStayTestDataFactory.assertDmlError(caught, 'is still checked in');
    }

    @IsTest
    static void cleanedRoomWithArrivalTodayBecomesReserved() {
        Id doubleRoomId = roomId('Double');
        SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 0, 2);
        update new Room__c(Id = doubleRoomId, Room_Status__c = SmartStayConstants.ROOM_CLEANING);

        update new Room__c(Id = doubleRoomId, Room_Status__c = SmartStayConstants.ROOM_AVAILABLE);

        Assert.areEqual(SmartStayConstants.ROOM_RESERVED, statusOf(doubleRoomId), 'Flow 4 keeps it Reserved');
    }

    // Flow 6: inactive or non-housekeeping staff cannot be assigned
    @IsTest
    static void onlyActiveHousekeepersCanBeAssigned() {
        Hotel_Staff__c activeHousekeeper = SmartStayTestDataFactory.buildStaff('Asha Housekeeper', 'Housekeeping', true);
        Hotel_Staff__c inactiveHousekeeper = SmartStayTestDataFactory.buildStaff('Ravi Former', 'Housekeeping', false);
        Hotel_Staff__c receptionist = SmartStayTestDataFactory.buildStaff('Neha Desk', 'Reception', true);
        insert new List<Hotel_Staff__c>{ activeHousekeeper, inactiveHousekeeper, receptionist };
        Id doubleRoomId = roomId('Double');

        update new Room__c(Id = doubleRoomId, Assigned_Housekeeper__c = activeHousekeeper.Id);
        Assert.areEqual(
            activeHousekeeper.Id,
            [SELECT Assigned_Housekeeper__c FROM Room__c WHERE Id = :doubleRoomId].Assigned_Housekeeper__c
        );

        Exception inactiveError;
        try {
            update new Room__c(Id = doubleRoomId, Assigned_Housekeeper__c = inactiveHousekeeper.Id);
        } catch (DmlException e) {
            inactiveError = e;
        }
        SmartStayTestDataFactory.assertDmlError(inactiveError, 'is inactive');

        Exception departmentError;
        try {
            insert new Room__c(
                Room_Type__c = 'Single',
                Floor__c = 1,
                Capacity__c = 1,
                Room_Rate__c = 2000,
                Assigned_Housekeeper__c = receptionist.Id
            );
        } catch (DmlException e) {
            departmentError = e;
        }
        SmartStayTestDataFactory.assertDmlError(departmentError, 'Only Housekeeping staff');
    }

    // Nightly job: statuses that went stale (for example because the date changed) are corrected
    @IsTest
    static void nightlyJobRecalculatesRooms() {
        Id doubleRoomId = roomId('Double');
        Id suiteId = roomId('Suite');
        SmartStayTestDataFactory.createReservation(guestId(), suiteId, 0, 2);
        // Stale values written directly (no Flow handles these transitions).
        update new List<Room__c>{
            new Room__c(Id = doubleRoomId, Room_Status__c = SmartStayConstants.ROOM_RESERVED),
            new Room__c(Id = suiteId, Room_Status__c = SmartStayConstants.ROOM_OCCUPIED)
        };

        Test.startTest();
        Database.executeBatch(new RoomStatusRefreshJob(), 200);
        Test.stopTest();

        Assert.areEqual(SmartStayConstants.ROOM_AVAILABLE, statusOf(doubleRoomId), 'No arrival today');
        Assert.areEqual(SmartStayConstants.ROOM_RESERVED, statusOf(suiteId), 'Arrival due today, nobody checked in');
    }

    @IsTest
    static void nightlyJobCanBeScheduled() {
        Test.startTest();
        Id jobId = RoomStatusRefreshJob.scheduleDaily('SmartStay Room Status Refresh (test)');
        Test.stopTest();

        CronTrigger cron = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        Assert.areEqual(RoomStatusRefreshJob.DAILY_CRON, cron.CronExpression);
    }

    @IsTest
    static void statusRulesInOrder() {
        List<Reservation__c> none = new List<Reservation__c>();
        List<Reservation__c> arrival = new List<Reservation__c>{
            new Reservation__c(Reservation_Status__c = SmartStayConstants.STATUS_CONFIRMED)
        };
        List<Reservation__c> inHouse = new List<Reservation__c>{
            new Reservation__c(Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN)
        };
        Assert.areEqual('Maintenance', RoomStatusService.determineStatus('Maintenance', inHouse));
        Assert.areEqual('Occupied', RoomStatusService.determineStatus('Cleaning', inHouse));
        Assert.areEqual('Cleaning', RoomStatusService.determineStatus('Cleaning', arrival));
        Assert.areEqual('Reserved', RoomStatusService.determineStatus('Available', arrival));
        Assert.areEqual('Available', RoomStatusService.determineStatus('Occupied', none));
        Assert.areEqual('Available', RoomStatusService.determineStatus('Reserved', none));
    }

    @IsTest
    static void invocableActionRecalculates() {
        Id doubleRoomId = roomId('Double');
        update new Room__c(Id = doubleRoomId, Room_Status__c = SmartStayConstants.ROOM_RESERVED);

        RoomStatusService.RecalculateRequest request = new RoomStatusService.RecalculateRequest();
        request.roomId = doubleRoomId;
        RoomStatusService.recalculateFromFlow(new List<RoomStatusService.RecalculateRequest>{ request });

        Assert.areEqual(SmartStayConstants.ROOM_AVAILABLE, statusOf(doubleRoomId), 'No reservations -> Available');
    }
}
