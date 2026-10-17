/**
 * Booking rules: valid/invalid inserts, overlap prevention (insert, update, room
 * change, bulk), cancelled bookings not blocking, maintenance and capacity rules,
 * booked rate capture.
 */
@IsTest
private class ReservationBookingServiceTest {
    @TestSetup
    static void setup() {
        insert new List<Room__c>{
            SmartStayTestDataFactory.buildRoom('Double', 2, 3000),
            SmartStayTestDataFactory.buildRoom('Suite', 4, 9000),
            SmartStayTestDataFactory.buildRoom('Single', 1, 2000)
        };
        insert new List<Guest__c>{ SmartStayTestDataFactory.buildGuest(1), SmartStayTestDataFactory.buildGuest(2) };
    }

    private static Room__c room(String roomType) {
        return [SELECT Id, Name, Room_Rate__c FROM Room__c WHERE Room_Type__c = :roomType LIMIT 1];
    }

    private static Id guestId() {
        return [SELECT Id FROM Guest__c ORDER BY Last_Name__c LIMIT 1].Id;
    }

    private static Exception insertExpectingError(Reservation__c reservation) {
        try {
            insert reservation;
        } catch (DmlException e) {
            return e;
        }
        return null;
    }

    // 1. Valid reservation insertion succeeds
    @IsTest
    static void validReservationIsSavedWithBookedRateAndAmount() {
        Room__c doubleRoom = room('Double');
        Test.startTest();
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 5, 8);
        Test.stopTest();

        Reservation__c saved = SmartStayTestDataFactory.reloadReservation(reservation.Id);
        Assert.areEqual(SmartStayConstants.STATUS_CONFIRMED, saved.Reservation_Status__c, 'Default status');
        Assert.areEqual(3000, saved.Booked_Rate__c, 'Rate captured from the room');
        Assert.areEqual(3, saved.Number_of_Nights__c, 'Nights formula');
        Assert.areEqual(9000, saved.Estimated_Amount__c, '3 nights x 3000');
    }

    // 2. Invalid reservation insertion is rejected (check-out before check-in)
    @IsTest
    static void checkOutBeforeCheckInIsRejected() {
        Reservation__c invalid = SmartStayTestDataFactory.buildReservation(guestId(), room('Double').Id, 5, 3, 1);
        SmartStayTestDataFactory.assertDmlError(
            insertExpectingError(invalid),
            'Check-Out Date must be later than Check-In Date'
        );
    }

    @IsTest
    static void sameDayCheckOutIsRejected() {
        Reservation__c invalid = SmartStayTestDataFactory.buildReservation(guestId(), room('Double').Id, 5, 5, 1);
        SmartStayTestDataFactory.assertDmlError(
            insertExpectingError(invalid),
            'Check-Out Date must be later than Check-In Date'
        );
    }

    @IsTest
    static void zeroGuestsIsRejected() {
        Reservation__c invalid = SmartStayTestDataFactory.buildReservation(guestId(), room('Double').Id, 5, 6, 0);
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(invalid), 'Number of Guests must be at least 1');
    }

    @IsTest
    static void pastCheckInIsRejectedForNormalUsers() {
        Reservation__c invalid = SmartStayTestDataFactory.buildReservation(guestId(), room('Double').Id, -3, 2, 1);
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(invalid), 'Check-In Date cannot be in the past');
    }

    @IsTest
    static void newReservationMustStartConfirmed() {
        Reservation__c invalid = SmartStayTestDataFactory.buildReservation(guestId(), room('Double').Id, 0, 2, 1);
        invalid.Reservation_Status__c = SmartStayConstants.STATUS_CHECKED_IN;
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(invalid), 'must be created as Confirmed');
    }

    // 3. Overlapping reservation is rejected
    @IsTest
    static void overlappingReservationIsRejected() {
        Room__c doubleRoom = room('Double');
        Reservation__c existing = SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 5, 8);
        String existingNumber = SmartStayTestDataFactory.reloadReservation(existing.Id).Name;

        List<List<Integer>> overlappingStays = new List<List<Integer>>{
            new List<Integer>{ 6, 9 }, // starts inside
            new List<Integer>{ 3, 6 }, // ends inside
            new List<Integer>{ 4, 10 }, // surrounds
            new List<Integer>{ 6, 7 }, // inside
            new List<Integer>{ 5, 8 } // identical
        };
        for (List<Integer> stay : overlappingStays) {
            Reservation__c clash = SmartStayTestDataFactory.buildReservation(
                guestId(),
                doubleRoom.Id,
                stay[0],
                stay[1],
                1
            );
            Exception caught = insertExpectingError(clash);
            SmartStayTestDataFactory.assertDmlError(caught, 'is already booked');
            SmartStayTestDataFactory.assertDmlError(caught, existingNumber);
        }
    }

    // 4. Non-overlapping reservation succeeds (including same-day turnover)
    @IsTest
    static void backToBackAndSeparateStaysAreAllowed() {
        Room__c doubleRoom = room('Double');
        SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 5, 8);

        Test.startTest();
        Reservation__c checkInOnCheckOutDay = SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 8, 10);
        Reservation__c checkOutOnCheckInDay = SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 2, 5);
        Reservation__c otherRoomSameDates = SmartStayTestDataFactory.createReservation(guestId(), room('Suite').Id, 5, 8);
        Test.stopTest();

        Assert.isNotNull(checkInOnCheckOutDay.Id, 'Arriving on the previous guest\'s check-out date is allowed');
        Assert.isNotNull(checkOutOnCheckInDay.Id, 'Leaving on the next guest\'s check-in date is allowed');
        Assert.isNotNull(otherRoomSameDates.Id, 'Same dates in a different room are allowed');
    }

    // 5. Cancelled reservation no longer blocks a valid booking
    @IsTest
    static void cancelledReservationDoesNotBlockDates() {
        Room__c doubleRoom = room('Double');
        Reservation__c original = SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 5, 8);
        original.Reservation_Status__c = SmartStayConstants.STATUS_CANCELLED;
        update original;

        Test.startTest();
        Reservation__c rebooking = SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 5, 8);
        Test.stopTest();

        Assert.isNotNull(rebooking.Id, 'Dates of a cancelled reservation can be booked again');
    }

    // 6. Updating reservation dates to create a conflict is rejected
    @IsTest
    static void movingDatesIntoAnotherStayIsRejected() {
        Room__c doubleRoom = room('Double');
        SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 5, 8);
        Reservation__c later = SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 10, 12);

        later.Check_In_Date__c = Date.today().addDays(7);
        Exception caught;
        try {
            update later;
        } catch (DmlException e) {
            caught = e;
        }
        SmartStayTestDataFactory.assertDmlError(caught, 'is already booked');
    }

    // 7. Changing the room is handled correctly
    @IsTest
    static void changingRoomChecksTheNewRoomAndRecapturesRate() {
        Room__c doubleRoom = room('Double');
        Room__c suite = room('Suite');
        SmartStayTestDataFactory.createReservation(guestId(), suite.Id, 5, 8);
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 6, 9);

        // Moving into the suite clashes with the suite's booking.
        reservation.Room__c = suite.Id;
        Exception caught;
        try {
            update reservation;
        } catch (DmlException e) {
            caught = e;
        }
        SmartStayTestDataFactory.assertDmlError(caught, 'is already booked');

        // Moving into the suite after the clash is resolved by changing dates succeeds.
        reservation.Check_In_Date__c = Date.today().addDays(8);
        reservation.Check_Out_Date__c = Date.today().addDays(11);
        update reservation;

        Reservation__c saved = SmartStayTestDataFactory.reloadReservation(reservation.Id);
        Assert.areEqual(suite.Id, saved.Room__c, 'Room changed');
        Assert.areEqual(9000, saved.Booked_Rate__c, 'Rate re-captured from the new room');
        Assert.areEqual(27000, saved.Estimated_Amount__c, '3 nights x 9000');
    }

    @IsTest
    static void roomRateChangeDoesNotAlterExistingBooking() {
        Room__c doubleRoom = room('Double');
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 5, 7);

        doubleRoom.Room_Rate__c = 5000;
        update doubleRoom;

        Reservation__c saved = SmartStayTestDataFactory.reloadReservation(reservation.Id);
        Assert.areEqual(3000, saved.Booked_Rate__c, 'Booked rate is frozen');
        Assert.areEqual(6000, saved.Estimated_Amount__c, '2 nights x booked rate 3000');
    }

    // 8. Multiple reservations are processed in one transaction
    @IsTest
    static void bulkInsertOf200ReservationsUsesFewQueries() {
        List<Room__c> rooms = new List<Room__c>();
        for (Integer i = 0; i < 20; i++) {
            rooms.add(SmartStayTestDataFactory.buildRoom('Double', 2, 3000));
        }
        insert rooms;
        Id guest = guestId();

        // 10 consecutive 2-night stays per room = 200 reservations, none overlapping.
        List<Reservation__c> reservations = new List<Reservation__c>();
        for (Room__c bulkRoom : rooms) {
            for (Integer stay = 0; stay < 10; stay++) {
                Reservation__c reservation = SmartStayTestDataFactory.buildReservation(
                    guest,
                    bulkRoom.Id,
                    1 + stay * 2,
                    3 + stay * 2,
                    2
                );
                // Bulk data load: skip guest emails (the confirmation flow honours this flag).
                reservation.Confirmation_Email_Status__c = 'Suppressed';
                reservations.add(reservation);
            }
        }

        Test.startTest();
        insert reservations;
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(200, [SELECT COUNT() FROM Reservation__c WHERE Room__c IN :rooms], 'All saved');
        Assert.isTrue(queriesUsed <= 10, 'Bulk-safe: query count must not grow with record count, used ' + queriesUsed);
    }

    @IsTest
    static void overlapsInsideOneSaveAreDetected() {
        Room__c doubleRoom = room('Double');
        Id guest = guestId();
        List<Reservation__c> batch = new List<Reservation__c>{
            SmartStayTestDataFactory.buildReservation(guest, doubleRoom.Id, 5, 8, 1),
            SmartStayTestDataFactory.buildReservation(guest, doubleRoom.Id, 7, 9, 1), // clashes with the first
            SmartStayTestDataFactory.buildReservation(guest, doubleRoom.Id, 8, 10, 1) // back-to-back with the first
        };

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(batch, false);
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess(), 'First booking wins');
        Assert.isFalse(results[1].isSuccess(), 'Second booking overlaps the first in the same save');
        Assert.isTrue(results[1].getErrors()[0].getMessage().contains('booked twice'), results[1].getErrors()[0].getMessage());
        Assert.isTrue(results[2].isSuccess(), 'Third booking starts on the first one\'s check-out date');
    }

    // 9. Reservation for a room under Maintenance is rejected
    @IsTest
    static void maintenanceRoomCannotBeBooked() {
        Room__c doubleRoom = room('Double');
        doubleRoom.Room_Status__c = SmartStayConstants.ROOM_MAINTENANCE;
        update doubleRoom;

        Reservation__c reservation = SmartStayTestDataFactory.buildReservation(guestId(), doubleRoom.Id, 5, 8, 1);
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(reservation), 'is under Maintenance');
    }

    @IsTest
    static void existingBookingStaysEditableWhenRoomGoesIntoMaintenance() {
        Room__c doubleRoom = room('Double');
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 5, 8);
        doubleRoom.Room_Status__c = SmartStayConstants.ROOM_MAINTENANCE;
        update doubleRoom;

        reservation.Special_Request__c = 'Late arrival';
        update reservation;
        reservation.Reservation_Status__c = SmartStayConstants.STATUS_CANCELLED;
        update reservation;

        Assert.areEqual(
            SmartStayConstants.STATUS_CANCELLED,
            SmartStayTestDataFactory.reloadReservation(reservation.Id).Reservation_Status__c,
            'A booking in a room that later went into maintenance can still be managed'
        );
    }

    // 10. Guest count exceeding room capacity is rejected
    @IsTest
    static void guestCountAboveCapacityIsRejected() {
        Reservation__c reservation = SmartStayTestDataFactory.buildReservation(guestId(), room('Single').Id, 5, 8, 2);
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(reservation), 'exceeds the capacity');
    }

    @IsTest
    static void guestCountAtCapacityIsAllowed() {
        Reservation__c reservation = SmartStayTestDataFactory.buildReservation(guestId(), room('Suite').Id, 5, 8, 4);
        insert reservation;
        Assert.isNotNull(reservation.Id, 'Exactly at capacity is allowed');
    }

    // 11. Valid reservation updates succeed
    @IsTest
    static void validUpdatesSucceed() {
        Room__c doubleRoom = room('Double');
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 5, 8);

        reservation.Number_of_Guests__c = 2;
        reservation.Special_Request__c = 'Extra pillows';
        reservation.Check_Out_Date__c = Date.today().addDays(10); // extend stay, nothing else booked
        update reservation;

        Reservation__c saved = SmartStayTestDataFactory.reloadReservation(reservation.Id);
        Assert.areEqual(5, saved.Number_of_Nights__c, 'Extended to 5 nights');
        Assert.areEqual(15000, saved.Estimated_Amount__c, '5 x 3000');
    }

    @IsTest
    static void unchangedUpdateSkipsOverlapQuery() {
        Room__c doubleRoom = room('Double');
        Reservation__c reservation = SmartStayTestDataFactory.createReservation(guestId(), doubleRoom.Id, 5, 8);

        Test.startTest();
        reservation.Special_Request__c = 'Quiet room';
        update reservation;
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(0, queriesUsed, 'No booking queries when room and dates are unchanged');
    }

    @IsTest
    static void overlapHelperTreatsCheckOutDayAsFree() {
        Reservation__c first = new Reservation__c(
            Check_In_Date__c = Date.newInstance(2030, 1, 1),
            Check_Out_Date__c = Date.newInstance(2030, 1, 4)
        );
        Reservation__c nextGuest = new Reservation__c(
            Check_In_Date__c = Date.newInstance(2030, 1, 4),
            Check_Out_Date__c = Date.newInstance(2030, 1, 6)
        );
        Reservation__c clash = new Reservation__c(
            Check_In_Date__c = Date.newInstance(2030, 1, 3),
            Check_Out_Date__c = Date.newInstance(2030, 1, 5)
        );
        Assert.isFalse(ReservationBookingService.overlaps(first, nextGuest), 'Turnover day is not an overlap');
        Assert.isTrue(ReservationBookingService.overlaps(first, clash), 'Shared night is an overlap');
    }
}
