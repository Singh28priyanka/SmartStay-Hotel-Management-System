/**
 * Status lifecycle: allowed and blocked transitions, and the check-in rules.
 */
@IsTest
private class ReservationStatusServiceTest {
    @TestSetup
    static void setup() {
        insert new List<Room__c>{
            SmartStayTestDataFactory.buildRoom('Double', 2, 3000),
            SmartStayTestDataFactory.buildRoom('Deluxe', 3, 5000)
        };
        insert SmartStayTestDataFactory.buildGuest(1);
    }

    private static Id roomId(String roomType) {
        return [SELECT Id FROM Room__c WHERE Room_Type__c = :roomType LIMIT 1].Id;
    }

    private static Id guestId() {
        return [SELECT Id FROM Guest__c LIMIT 1].Id;
    }

    private static Exception updateExpectingError(Reservation__c reservation) {
        try {
            update reservation;
        } catch (DmlException e) {
            return e;
        }
        return null;
    }

    @IsTest
    static void fullStayLifecycleSucceeds() {
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), roomId('Double'), 0, 2);

        Test.startTest();
        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        update reservation;
        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_OUT;
        update reservation;
        Test.stopTest();

        Assert.areEqual(
            SmartStayConstants.STATUS_CHECKED_OUT,
            SmartStayTestDataFactory.reloadReservation(reservation.Id).Reservation_Status__c,
            'Confirmed -> Checked-In -> Checked-Out'
        );
    }

    @IsTest
    static void checkOutWithoutCheckInIsRejected() {
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), roomId('Double'), 0, 2);
        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_OUT;
        SmartStayTestDataFactory.assertDmlError(updateExpectingError(reservation), 'Allowed next status');
    }

    @IsTest
    static void cancelledReservationCannotBeReopened() {
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), roomId('Double'), 3, 5);
        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CANCELLED;
        update reservation;

        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CONFIRMED;
        SmartStayTestDataFactory.assertDmlError(updateExpectingError(reservation), 'reservations are final');
    }

    @IsTest
    static void checkedInGuestCannotBeCancelled() {
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), roomId('Double'), 0, 2);
        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        update reservation;

        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CANCELLED;
        SmartStayTestDataFactory.assertDmlError(updateExpectingError(reservation), 'Allowed next status: Checked-Out');
    }

    @IsTest
    static void checkInBeforeArrivalDateIsRejected() {
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), roomId('Double'), 3, 5);
        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        SmartStayTestDataFactory.assertDmlError(updateExpectingError(reservation), 'Check-in is only possible from');
    }

    @IsTest
    static void checkInWhileRoomIsBeingCleanedIsRejected() {
        Id doubleRoomId = roomId('Double');
        update new Room__c(Id = doubleRoomId, Room_Status__c = SmartStayConstants.ROOM_CLEANING);
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 0, 2);

        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        SmartStayTestDataFactory.assertDmlError(updateExpectingError(reservation), 'is still being cleaned');
    }

    @IsTest
    static void checkInToMaintenanceRoomIsRejected() {
        Id doubleRoomId = roomId('Double');
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 0, 2);
        update new Room__c(Id = doubleRoomId, Room_Status__c = SmartStayConstants.ROOM_MAINTENANCE);

        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        SmartStayTestDataFactory.assertDmlError(updateExpectingError(reservation), 'is under Maintenance');
    }

    @IsTest
    static void guestStillInRoomBlocksNextCheckIn() {
        Id doubleRoomId = roomId('Double');
        Reservation__c inHouse = SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 0, 1);
        inHouse.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        update inHouse;
        Reservation__c nextGuest = SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 1, 3);

        // Simulates the next morning: the previous guest has not checked out yet.
        // Dates are adjusted in memory only so the date-window rule passes.
        Reservation__c oldValue = nextGuest.clone(true, true, false, false);
        Reservation__c newValue = nextGuest.clone(true, true, false, false);
        newValue.Check_In_Date__c = Date.today();
        newValue.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        oldValue.Reservation_Status__c = SmartStayConstants.STATUS_CONFIRMED;

        ReservationStatusService.validateStatusChanges(
            new List<Reservation__c>{ newValue },
            new Map<Id, Reservation__c>{ oldValue.Id => oldValue }
        );

        Assert.isTrue(newValue.hasErrors(), 'Check-in blocked while another guest is in the room');
        Assert.isTrue(
            newValue.getErrors()[0].getMessage().contains('still has a checked-in guest'),
            newValue.getErrors()[0].getMessage()
        );
    }

    @IsTest
    static void historyIsLockedAfterCheckOut() {
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), roomId('Double'), 0, 2);
        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        update reservation;
        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_OUT;
        update reservation;

        reservation.Check_Out_Date__c = Date.today().addDays(4);
        SmartStayTestDataFactory.assertDmlError(updateExpectingError(reservation), 'are history');
    }

    @IsTest
    static void roomCannotChangeAfterCheckIn() {
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), roomId('Double'), 0, 2);
        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        update reservation;

        reservation.Room__c = roomId('Deluxe');
        SmartStayTestDataFactory.assertDmlError(updateExpectingError(reservation), 'After check-in');
    }

    @IsTest
    static void checkedInGuestCanExtendStay() {
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), roomId('Double'), 0, 2);
        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        update reservation;

        reservation.Check_Out_Date__c = Date.today().addDays(4);
        update reservation;
        Assert.areEqual(4, SmartStayTestDataFactory.reloadReservation(reservation.Id).Number_of_Nights__c, 'Extended');
    }

    @IsTest
    static void twoCheckInsForSameRoomInOneSaveAreRejected() {
        Id doubleRoomId = roomId('Double');
        Reservation__c first = SmartStayTestDataFactory.createReservation(guestId(), doubleRoomId, 0, 1);
        Reservation__c second = SmartStayTestDataFactory.createReservation(guestId(), roomId('Deluxe'), 0, 1);

        // The overlap rule already stops two bookings sharing a room and night, so this
        // guard is exercised directly on the service with in-memory values.
        Reservation__c firstOld = first.clone(true, true, false, false);
        Reservation__c secondOld = second.clone(true, true, false, false);
        Reservation__c firstNew = first.clone(true, true, false, false);
        Reservation__c secondNew = second.clone(true, true, false, false);
        firstOld.Reservation_Status__c = SmartStayConstants.STATUS_CONFIRMED;
        secondOld.Reservation_Status__c = SmartStayConstants.STATUS_CONFIRMED;
        firstNew.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        secondNew.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        secondNew.Room__c = doubleRoomId;

        ReservationStatusService.validateStatusChanges(
            new List<Reservation__c>{ firstNew, secondNew },
            new Map<Id, Reservation__c>{ first.Id => firstOld, second.Id => secondOld }
        );

        Assert.isFalse(firstNew.hasErrors(), 'First check-in accepted');
        Assert.isTrue(secondNew.hasErrors(), 'Second check-in into the same room rejected');
    }
}
