/**
 * Documented SOQL queries for SmartStay (project requirement: SOQL demonstration).
 *
 * Every query runs WITH USER_MODE, so the running user's object permissions,
 * field-level security and record sharing are enforced: a Housekeeping user
 * gets an error instead of reservation data, and an Accounts user cannot read
 * guest identification fields.
 *
 * Relationship names used below:
 *   Reservation__c.Room__c  -> parent Room__c,  child relationship Reservations__r
 *   Reservation__c.Guest__c -> parent Guest__c, child relationship Reservations__r
 *
 * Run scripts/apex/soql-demo.apex to see each query's output in an org.
 */
public with sharing class SmartStayQueries {
    /**
     * Query 1: all reservations for one room, newest stay first.
     * Expected: every reservation of the room, any status (room history).
     */
    public static List<Reservation__c> getReservationsForRoom(Id roomId) {
        return [
            SELECT
                Id,
                Name,
                Guest_Name__c,
                Check_In_Date__c,
                Check_Out_Date__c,
                Number_of_Guests__c,
                Reservation_Status__c,
                Estimated_Amount__c
            FROM Reservation__c
            WHERE Room__c = :roomId
            WITH USER_MODE
            ORDER BY Check_In_Date__c DESC
        ];
    }

    /**
     * Query 2: all reservations of one guest, newest stay first.
     * Expected: the guest's complete stay history across rooms.
     */
    public static List<Reservation__c> getReservationsForGuest(Id guestId) {
        return [
            SELECT
                Id,
                Name,
                Room_Number__c,
                Room_Type__c,
                Check_In_Date__c,
                Check_Out_Date__c,
                Reservation_Status__c,
                Estimated_Amount__c
            FROM Reservation__c
            WHERE Guest__c = :guestId
            WITH USER_MODE
            ORDER BY Check_In_Date__c DESC
        ];
    }

    /**
     * Query 3: active reservations of one room: the guest currently checked in,
     * plus Confirmed bookings that have not ended. Cancelled and Checked-Out
     * reservations are excluded.
     */
    public static List<Reservation__c> getActiveReservationsForRoom(Id roomId) {
        return [
            SELECT Id, Name, Guest_Name__c, Check_In_Date__c, Check_Out_Date__c, Reservation_Status__c
            FROM Reservation__c
            WHERE
                Room__c = :roomId
                AND (Reservation_Status__c = :SmartStayConstants.STATUS_CHECKED_IN
                OR (Reservation_Status__c = :SmartStayConstants.STATUS_CONFIRMED
                AND Check_Out_Date__c >= TODAY))
            WITH USER_MODE
            ORDER BY Check_In_Date__c ASC
        ];
    }

    /**
     * Query 4: reservations whose whole stay falls inside [startDate, endDate]:
     * check-in on/after startDate and check-out on/before endDate.
     * @throws IllegalArgumentException if a date is missing or endDate < startDate
     */
    public static List<Reservation__c> getReservationsInDateRange(Date startDate, Date endDate) {
        if (startDate == null || endDate == null || endDate < startDate) {
            throw new IllegalArgumentException('Provide a start date and an end date on or after the start date.');
        }
        return [
            SELECT Id, Name, Guest_Name__c, Room_Number__c, Check_In_Date__c, Check_Out_Date__c, Reservation_Status__c
            FROM Reservation__c
            WHERE Check_In_Date__c >= :startDate AND Check_Out_Date__c <= :endDate
            WITH USER_MODE
            ORDER BY Check_In_Date__c ASC, Name ASC
        ];
    }

    /**
     * Query 5 (parent-to-child): a room with its reservations in one query,
     * using the child relationship Reservations__r.
     * @return the room, or null if it does not exist or is not visible
     */
    public static Room__c getRoomWithReservations(Id roomId) {
        List<Room__c> rooms = [
            SELECT
                Id,
                Name,
                Room_Type__c,
                Room_Status__c,
                Room_Rate__c,
                Capacity__c,
                (
                    SELECT Id, Name, Guest_Name__c, Check_In_Date__c, Check_Out_Date__c, Reservation_Status__c
                    FROM Reservations__r
                    ORDER BY Check_In_Date__c DESC
                )
            FROM Room__c
            WHERE Id = :roomId
            WITH USER_MODE
        ];
        return rooms.isEmpty() ? null : rooms[0];
    }

    /**
     * Query 6 (child-to-parent): reservations with their room and guest details,
     * read through the lookups Room__r and Guest__r.
     * Expected: reservations checking in from fromDate onwards (at most 200).
     */
    public static List<Reservation__c> getReservationsWithRoomAndGuest(Date fromDate) {
        return [
            SELECT
                Id,
                Name,
                Check_In_Date__c,
                Check_Out_Date__c,
                Reservation_Status__c,
                Room__r.Name,
                Room__r.Room_Type__c,
                Room__r.Room_Rate__c,
                Guest__r.First_Name__c,
                Guest__r.Last_Name__c,
                Guest__r.Email__c,
                Guest__r.Mobile__c
            FROM Reservation__c
            WHERE Check_In_Date__c >= :fromDate
            WITH USER_MODE
            ORDER BY Check_In_Date__c ASC
            LIMIT 200
        ];
    }

    /**
     * Query 7 (parent-to-child from Guest): a guest with all their reservations.
     */
    public static Guest__c getGuestWithReservations(Id guestId) {
        List<Guest__c> guests = [
            SELECT
                Id,
                Name,
                Full_Name__c,
                Email__c,
                (
                    SELECT Id, Name, Room_Number__c, Check_In_Date__c, Check_Out_Date__c, Reservation_Status__c
                    FROM Reservations__r
                    ORDER BY Check_In_Date__c DESC
                )
            FROM Guest__c
            WHERE Id = :guestId
            WITH USER_MODE
        ];
        return guests.isEmpty() ? null : guests[0];
    }

    /**
     * Query 8 (aggregate, grouped by a parent field): non-cancelled reservations per room type.
     * @return room type -> number of reservations
     */
    public static Map<String, Integer> countReservationsByRoomType() {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (AggregateResult row : [
            SELECT Room__r.Room_Type__c roomType, COUNT(Id) total
            FROM Reservation__c
            WHERE Reservation_Status__c != :SmartStayConstants.STATUS_CANCELLED
            WITH USER_MODE
            GROUP BY Room__r.Room_Type__c
        ]) {
            counts.put((String) row.get('roomType'), (Integer) row.get('total'));
        }
        return counts;
    }
}
