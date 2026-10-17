/**
 * Reservation status lifecycle:
 *
 *     Confirmed --> Checked-In --> Checked-Out
 *         \
 *          `----> Cancelled
 *
 * Checked-Out and Cancelled are final. New reservations always start as Confirmed.
 *
 * Check-in is allowed only when:
 *   - today is on or after the Check-In Date and before the Check-Out Date,
 *   - the room is not under Maintenance and not still being Cleaned,
 *   - no other guest is currently checked in to the same room.
 * Users with the SmartStay_Historical_Data_Load custom permission may record
 * check-ins outside the date window (for loading past stays); the room rules
 * still apply to them.
 *
 * Runs WITHOUT SHARING so the "room already has a checked-in guest" check sees
 * every reservation, not only the ones the current user can see.
 */
public without sharing class ReservationStatusService {
    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        SmartStayConstants.STATUS_CONFIRMED => new Set<String>{
            SmartStayConstants.STATUS_CHECKED_IN,
            SmartStayConstants.STATUS_CANCELLED
        },
        SmartStayConstants.STATUS_CHECKED_IN => new Set<String>{ SmartStayConstants.STATUS_CHECKED_OUT },
        SmartStayConstants.STATUS_CHECKED_OUT => new Set<String>(),
        SmartStayConstants.STATUS_CANCELLED => new Set<String>()
    };

    /** Before insert: every new reservation starts as Confirmed. */
    public static void prepareNewReservations(List<Reservation__c> newRecords) {
        for (Reservation__c reservation : newRecords) {
            if (String.isBlank(reservation.Reservation_Status__c)) {
                reservation.Reservation_Status__c = SmartStayConstants.STATUS_CONFIRMED;
            } else if (reservation.Reservation_Status__c != SmartStayConstants.STATUS_CONFIRMED) {
                reservation.Reservation_Status__c.addError(
                    'New reservations must be created as Confirmed. Use Check In, Check Out or Cancel Reservation afterwards.'
                );
            }
        }
    }

    /** Before update: only allowed status moves; check-ins must meet the check-in rules. */
    public static void validateStatusChanges(List<Reservation__c> newRecords, Map<Id, Reservation__c> oldMap) {
        List<Reservation__c> checkIns = new List<Reservation__c>();
        for (Reservation__c reservation : newRecords) {
            String oldStatus = oldMap.get(reservation.Id).Reservation_Status__c;
            String newStatus = reservation.Reservation_Status__c;
            if (newStatus == oldStatus) {
                continue;
            }
            if (String.isBlank(newStatus)) {
                reservation.Reservation_Status__c.addError('Reservation Status is required.');
                continue;
            }
            Set<String> allowed = ALLOWED_TRANSITIONS.get(oldStatus);
            if (allowed == null || !allowed.contains(newStatus)) {
                reservation.Reservation_Status__c.addError(describeInvalidMove(oldStatus, newStatus, allowed));
                continue;
            }
            if (newStatus == SmartStayConstants.STATUS_CHECKED_IN) {
                checkIns.add(reservation);
            }
        }
        if (!checkIns.isEmpty()) {
            validateCheckIns(checkIns);
        }
    }

    private static String describeInvalidMove(String oldStatus, String newStatus, Set<String> allowed) {
        String message = 'A reservation cannot move from ' + oldStatus + ' to ' + newStatus + '.';
        if (allowed == null || allowed.isEmpty()) {
            return message + ' ' + oldStatus + ' reservations are final.';
        }
        return message + ' Allowed next status: ' + String.join(new List<String>(allowed), ' or ') + '.';
    }

    private static void validateCheckIns(List<Reservation__c> checkIns) {
        Set<Id> roomIds = new Set<Id>();
        Set<Id> checkInIds = new Set<Id>();
        for (Reservation__c reservation : checkIns) {
            roomIds.add(reservation.Room__c);
            checkInIds.add(reservation.Id);
        }

        Map<Id, Room__c> rooms = new Map<Id, Room__c>(
            [SELECT Id, Name, Room_Status__c FROM Room__c WHERE Id IN :roomIds]
        );
        Map<Id, Reservation__c> guestAlreadyInRoom = new Map<Id, Reservation__c>();
        for (Reservation__c inHouse : [
            SELECT Id, Name, Room__c
            FROM Reservation__c
            WHERE
                Room__c IN :roomIds
                AND Reservation_Status__c = :SmartStayConstants.STATUS_CHECKED_IN
                AND Id NOT IN :checkInIds
        ]) {
            guestAlreadyInRoom.put(inHouse.Room__c, inHouse);
        }

        Boolean mayRecordPastStays = FeatureManagement.checkPermission(SmartStayConstants.HISTORICAL_LOAD_PERMISSION);
        Date today = Date.today();
        Set<Id> roomsCheckedInNow = new Set<Id>();

        for (Reservation__c reservation : checkIns) {
            Room__c room = rooms.get(reservation.Room__c);
            if (room == null) {
                reservation.addError('Check-in failed: the reservation has no valid room.');
                continue;
            }
            if (
                !mayRecordPastStays &&
                (today < reservation.Check_In_Date__c || today >= reservation.Check_Out_Date__c)
            ) {
                reservation.Reservation_Status__c.addError(
                    'Check-in is only possible from the Check-In Date (' + reservation.Check_In_Date__c.format() +
                    ') until the day before the Check-Out Date (' + reservation.Check_Out_Date__c.format() + ').'
                );
                continue;
            }
            if (room.Room_Status__c == SmartStayConstants.ROOM_MAINTENANCE) {
                reservation.Reservation_Status__c.addError(
                    'Room ' + room.Name + ' is under Maintenance. Move the reservation to another room before check-in.'
                );
                continue;
            }
            if (room.Room_Status__c == SmartStayConstants.ROOM_CLEANING) {
                reservation.Reservation_Status__c.addError(
                    'Room ' + room.Name + ' is still being cleaned. Housekeeping must mark it ready before check-in.'
                );
                continue;
            }
            if (guestAlreadyInRoom.containsKey(room.Id) || roomsCheckedInNow.contains(room.Id)) {
                Reservation__c inHouse = guestAlreadyInRoom.get(room.Id);
                reservation.Reservation_Status__c.addError(
                    'Room ' + room.Name + ' still has a checked-in guest' +
                    (inHouse == null ? '' : ' (' + inHouse.Name + ')') + '. Check that guest out first.'
                );
                continue;
            }
            roomsCheckedInNow.add(room.Id);
        }
    }
}
