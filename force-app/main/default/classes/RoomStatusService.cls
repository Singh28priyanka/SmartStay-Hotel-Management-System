/**
 * Single source of truth for what a room's status should be, given its reservations.
 *
 * Rules, applied in order:
 *   1. Maintenance stays Maintenance (only staff take a room out of maintenance).
 *   2. A checked-in reservation               -> Occupied
 *   3. Cleaning stays Cleaning (housekeeping marks the room ready).
 *   4. A Confirmed reservation covering today  -> Reserved (guest arriving / due in)
 *   5. Otherwise                                -> Available
 *
 * Future bookings do not make a room Reserved: room status describes today, while
 * double-booking is prevented by dates in ReservationBookingService, never by status.
 *
 * Called from:
 *   - ReservationTriggerHandler (after a booking's room or dates change),
 *   - the "SmartStay - Reservation Cancellation" Flow (invocable action),
 *   - RoomStatusRefreshJob (nightly, because "today" moves).
 *
 * Runs WITHOUT SHARING: it is a system process that must see every reservation
 * of the room, whichever user's action started it.
 */
public without sharing class RoomStatusService {
    /** Recalculates and updates (only when different) the status of the given rooms. */
    public static void recalculate(Set<Id> roomIds) {
        Set<Id> ids = new Set<Id>(roomIds);
        ids.remove(null);
        if (ids.isEmpty()) {
            return;
        }

        Date today = Date.today();
        List<Room__c> roomsToUpdate = new List<Room__c>();
        for (Room__c room : [
            SELECT
                Id,
                Room_Status__c,
                (
                    SELECT Reservation_Status__c
                    FROM Reservations__r
                    WHERE
                        Reservation_Status__c = :SmartStayConstants.STATUS_CHECKED_IN
                        OR (Reservation_Status__c = :SmartStayConstants.STATUS_CONFIRMED
                        AND Check_In_Date__c <= :today
                        AND Check_Out_Date__c > :today)
                )
            FROM Room__c
            WHERE Id IN :ids
        ]) {
            String target = determineStatus(room.Room_Status__c, room.Reservations__r);
            if (target != room.Room_Status__c) {
                roomsToUpdate.add(new Room__c(Id = room.Id, Room_Status__c = target));
            }
        }
        if (!roomsToUpdate.isEmpty()) {
            update roomsToUpdate;
        }
    }

    /**
     * @param currentStatus           the room's status now
     * @param reservationsAffectingToday checked-in reservations and Confirmed ones covering today
     */
    @TestVisible
    private static String determineStatus(String currentStatus, List<Reservation__c> reservationsAffectingToday) {
        if (currentStatus == SmartStayConstants.ROOM_MAINTENANCE) {
            return SmartStayConstants.ROOM_MAINTENANCE;
        }
        Boolean hasGuestInHouse = false;
        Boolean hasArrivalDue = false;
        for (Reservation__c reservation : reservationsAffectingToday) {
            if (reservation.Reservation_Status__c == SmartStayConstants.STATUS_CHECKED_IN) {
                hasGuestInHouse = true;
            } else {
                hasArrivalDue = true;
            }
        }
        if (hasGuestInHouse) {
            return SmartStayConstants.ROOM_OCCUPIED;
        }
        if (currentStatus == SmartStayConstants.ROOM_CLEANING) {
            return SmartStayConstants.ROOM_CLEANING;
        }
        return hasArrivalDue ? SmartStayConstants.ROOM_RESERVED : SmartStayConstants.ROOM_AVAILABLE;
    }

    /** Flow input: one room to recalculate. */
    public class RecalculateRequest {
        @InvocableVariable(label='Room Id' description='Room whose status should be recalculated' required=true)
        public Id roomId;
    }

    /** Lets Flows reuse the same rules instead of duplicating them. */
    @InvocableMethod(
        label='Recalculate Room Status'
        description='Sets the room status from its reservations, keeping Maintenance and Cleaning.'
        category='SmartStay'
    )
    public static void recalculateFromFlow(List<RecalculateRequest> requests) {
        Set<Id> roomIds = new Set<Id>();
        for (RecalculateRequest request : requests) {
            roomIds.add(request.roomId);
        }
        recalculate(roomIds);
    }
}
