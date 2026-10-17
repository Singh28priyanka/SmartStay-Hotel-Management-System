/**
 * Booking rules that need other records, which validation rules cannot see:
 *   - a room under Maintenance cannot be booked,
 *   - two active (not Cancelled) reservations for the same room must not overlap,
 *   - the room's nightly rate is captured in Booked_Rate__c when the room is booked.
 *
 * Overlap definition (stay = [Check-In Date, Check-Out Date), guest leaves on the
 * check-out date, so a same-day turnover is allowed):
 *     other.Check_In_Date__c  < this.Check_Out_Date__c
 * AND other.Check_Out_Date__c > this.Check_In_Date__c
 * AND same room, other is not Cancelled, other is not this record.
 *
 * Concurrency: two users can save conflicting bookings at the same moment; each
 * transaction's overlap query would miss the other's uncommitted row. To prevent
 * that, the booked rooms are locked with SELECT ... FOR UPDATE before the overlap
 * query. A second transaction for the same room waits until the first commits,
 * then its query sees the committed booking and rejects the conflict. If the wait
 * exceeds Salesforce's lock timeout (about 10 seconds), the second save fails with
 * UNABLE_TO_LOCK_ROW and the user simply retries. Data written by paths that skip
 * triggers (none exist in this app) would not be protected.
 *
 * Runs WITHOUT SHARING on purpose: a conflict must be found even when the
 * conflicting reservation belongs to a user the current user cannot see. Only the
 * other reservation's number and dates are revealed in the error message.
 */
public without sharing class ReservationBookingService {
    /**
     * Validates reservations in before insert and before update.
     * @param newRecords Trigger.new
     * @param oldMap     Trigger.oldMap, or null on insert
     */
    public static void validateBookings(List<Reservation__c> newRecords, Map<Id, Reservation__c> oldMap) {
        Set<Integer> candidateIndexes = new Set<Integer>();
        Set<Id> roomIds = new Set<Id>();
        for (Integer i = 0; i < newRecords.size(); i++) {
            Reservation__c reservation = newRecords[i];
            if (needsBookingCheck(reservation, oldValueOf(reservation, oldMap))) {
                candidateIndexes.add(i);
                roomIds.add(reservation.Room__c);
            }
        }
        if (candidateIndexes.isEmpty()) {
            return;
        }

        Map<Id, Room__c> lockedRooms = lockRooms(roomIds);

        Set<Integer> eligibleIndexes = new Set<Integer>();
        for (Integer i : candidateIndexes) {
            Reservation__c reservation = newRecords[i];
            if (applyRoomRules(reservation, oldValueOf(reservation, oldMap), lockedRooms.get(reservation.Room__c))) {
                eligibleIndexes.add(i);
            }
        }
        rejectOverlaps(newRecords, eligibleIndexes, lockedRooms);
    }

    /**
     * A booking is (re)checked when it is new, or when its room or dates change.
     * Records with missing or inverted dates are left to the required-field and
     * validation-rule errors, so the user sees one clear message.
     */
    @TestVisible
    private static Boolean needsBookingCheck(Reservation__c reservation, Reservation__c oldReservation) {
        if (!hasValidStay(reservation)) {
            return false;
        }
        if (
            reservation.Reservation_Status__c == SmartStayConstants.STATUS_CANCELLED ||
            reservation.Reservation_Status__c == SmartStayConstants.STATUS_CHECKED_OUT
        ) {
            return false;
        }
        if (oldReservation == null) {
            return true;
        }
        return reservation.Room__c != oldReservation.Room__c ||
            reservation.Check_In_Date__c != oldReservation.Check_In_Date__c ||
            reservation.Check_Out_Date__c != oldReservation.Check_Out_Date__c ||
            oldReservation.Reservation_Status__c == SmartStayConstants.STATUS_CANCELLED;
    }

    /** Locks the rooms being booked for the rest of this transaction (see class comment). */
    private static Map<Id, Room__c> lockRooms(Set<Id> roomIds) {
        return new Map<Id, Room__c>(
            [SELECT Id, Name, Room_Status__c, Room_Rate__c FROM Room__c WHERE Id IN :roomIds FOR UPDATE]
        );
    }

    /**
     * Rejects bookings into a Maintenance room and captures the nightly rate.
     * Only applies when the room is newly chosen; a room that goes into Maintenance
     * after booking does not break edits of existing reservations (check-in is
     * blocked separately by ReservationStatusService).
     * @return true if the reservation should continue to the overlap check
     */
    private static Boolean applyRoomRules(Reservation__c reservation, Reservation__c oldReservation, Room__c room) {
        if (room == null) {
            reservation.Room__c.addError('The selected room does not exist or was deleted.');
            return false;
        }
        Boolean roomChosenNow = oldReservation == null || oldReservation.Room__c != reservation.Room__c;
        if (!roomChosenNow) {
            return true;
        }
        if (room.Room_Status__c == SmartStayConstants.ROOM_MAINTENANCE) {
            reservation.Room__c.addError(
                'Room ' + room.Name + ' is under Maintenance and cannot be booked. Choose another room.'
            );
            return false;
        }
        // Rate is frozen at booking time so later room-rate changes do not alter this booking.
        reservation.Booked_Rate__c = room.Room_Rate__c;
        return true;
    }

    private static void rejectOverlaps(
        List<Reservation__c> newRecords,
        Set<Integer> eligibleIndexes,
        Map<Id, Room__c> rooms
    ) {
        if (eligibleIndexes.isEmpty()) {
            return;
        }

        Set<Id> roomIds = new Set<Id>();
        Date earliestCheckIn;
        Date latestCheckOut;
        for (Integer i : eligibleIndexes) {
            Reservation__c reservation = newRecords[i];
            roomIds.add(reservation.Room__c);
            if (earliestCheckIn == null || reservation.Check_In_Date__c < earliestCheckIn) {
                earliestCheckIn = reservation.Check_In_Date__c;
            }
            if (latestCheckOut == null || reservation.Check_Out_Date__c > latestCheckOut) {
                latestCheckOut = reservation.Check_Out_Date__c;
            }
        }

        // Records in this save are compared using their new values below, so their
        // saved (old) values must not be compared as well.
        Set<Id> idsInThisSave = new Set<Id>();
        for (Reservation__c reservation : newRecords) {
            if (reservation.Id != null) {
                idsInThisSave.add(reservation.Id);
            }
        }

        // One query for the whole batch: every active booking of these rooms that
        // touches the batch's overall date window.
        Map<Id, List<Reservation__c>> savedBookingsByRoom = new Map<Id, List<Reservation__c>>();
        for (Reservation__c saved : [
            SELECT Id, Name, Room__c, Check_In_Date__c, Check_Out_Date__c
            FROM Reservation__c
            WHERE
                Room__c IN :roomIds
                AND Reservation_Status__c != :SmartStayConstants.STATUS_CANCELLED
                AND Check_In_Date__c < :latestCheckOut
                AND Check_Out_Date__c > :earliestCheckIn
                AND Id NOT IN :idsInThisSave
        ]) {
            if (!savedBookingsByRoom.containsKey(saved.Room__c)) {
                savedBookingsByRoom.put(saved.Room__c, new List<Reservation__c>());
            }
            savedBookingsByRoom.get(saved.Room__c).add(saved);
        }

        // Bookings in this save that keep their dates (not re-checked) still hold them.
        List<Reservation__c> acceptedInThisSave = new List<Reservation__c>();
        for (Integer i = 0; i < newRecords.size(); i++) {
            if (!eligibleIndexes.contains(i) && holdsDates(newRecords[i])) {
                acceptedInThisSave.add(newRecords[i]);
            }
        }

        // Earlier records in the list win over later ones in the same save.
        for (Integer i = 0; i < newRecords.size(); i++) {
            if (!eligibleIndexes.contains(i)) {
                continue;
            }
            Reservation__c reservation = newRecords[i];
            String roomName = rooms.get(reservation.Room__c).Name;

            Reservation__c clash = findClash(reservation, savedBookingsByRoom.get(reservation.Room__c));
            if (clash != null) {
                reservation.addError(
                    'Room ' + roomName + ' is already booked from ' + clash.Check_In_Date__c.format() +
                    ' to ' + clash.Check_Out_Date__c.format() + ' (' + clash.Name + '). ' +
                    'A new stay can start on the previous guest\'s check-out date. Choose other dates or another room.'
                );
                continue;
            }
            clash = findClash(reservation, acceptedInThisSave);
            if (clash != null) {
                reservation.addError(
                    'Room ' + roomName + ' is booked twice for overlapping dates in this same save (' +
                    clash.Check_In_Date__c.format() + ' to ' + clash.Check_Out_Date__c.format() + ').'
                );
                continue;
            }
            acceptedInThisSave.add(reservation);
        }
    }

    private static Reservation__c findClash(Reservation__c reservation, List<Reservation__c> others) {
        if (others == null) {
            return null;
        }
        for (Reservation__c other : others) {
            if (other !== reservation && other.Room__c == reservation.Room__c && overlaps(reservation, other)) {
                return other;
            }
        }
        return null;
    }

    @TestVisible
    private static Boolean overlaps(Reservation__c first, Reservation__c second) {
        return first.Check_In_Date__c < second.Check_Out_Date__c && first.Check_Out_Date__c > second.Check_In_Date__c;
    }

    private static Boolean holdsDates(Reservation__c reservation) {
        return hasValidStay(reservation) && reservation.Reservation_Status__c != SmartStayConstants.STATUS_CANCELLED;
    }

    private static Boolean hasValidStay(Reservation__c reservation) {
        return reservation.Room__c != null &&
            reservation.Check_In_Date__c != null &&
            reservation.Check_Out_Date__c != null &&
            reservation.Check_Out_Date__c > reservation.Check_In_Date__c;
    }

    private static Reservation__c oldValueOf(Reservation__c reservation, Map<Id, Reservation__c> oldMap) {
        return oldMap == null ? null : oldMap.get(reservation.Id);
    }
}
