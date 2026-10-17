/**
 * Orchestrates everything that happens when Reservation__c records are saved.
 *
 * Before save (validation and field defaults, no DML):
 *   1. ReservationStatusService  - default status, allowed status moves, check-in rules
 *   2. ReservationBookingService - maintenance check, booked rate, overlap prevention
 *
 * After save (DML on other objects):
 *   3. RoomStatusService - recalculates Room Status when a booking's room or dates change.
 *
 * Room updates caused by status changes are owned by record-triggered Flows
 * (Check-In -> Occupied, Check-Out -> Cleaning, Cancelled -> recalculate), so
 * this handler deliberately ignores status-only changes to avoid two automations
 * writing the same field.
 *
 * Recursion: every step compares new and old values and does nothing when the
 * relevant fields did not change, so re-entry (for example when the confirmation
 * Flow stamps Confirmation_Email_Status__c) costs no extra queries or DML.
 */
public with sharing class ReservationTriggerHandler {
    private final System.TriggerOperation operation;
    private final List<Reservation__c> newRecords;
    private final Map<Id, Reservation__c> oldMap;

    public ReservationTriggerHandler() {
        this(Trigger.operationType, Trigger.new, (Map<Id, Reservation__c>) Trigger.oldMap);
    }

    @TestVisible
    private ReservationTriggerHandler(
        System.TriggerOperation operation,
        List<Reservation__c> newRecords,
        Map<Id, Reservation__c> oldMap
    ) {
        this.operation = operation;
        this.newRecords = newRecords;
        this.oldMap = oldMap;
    }

    public void run() {
        switch on operation {
            when BEFORE_INSERT {
                ReservationStatusService.prepareNewReservations(newRecords);
                ReservationBookingService.validateBookings(newRecords, null);
            }
            when BEFORE_UPDATE {
                ReservationStatusService.validateStatusChanges(newRecords, oldMap);
                ReservationBookingService.validateBookings(newRecords, oldMap);
            }
            when AFTER_INSERT {
                RoomStatusService.recalculate(roomsOf(newRecords));
            }
            when AFTER_UPDATE {
                RoomStatusService.recalculate(roomsWithChangedBookings());
            }
        }
    }

    private static Set<Id> roomsOf(List<Reservation__c> reservations) {
        Set<Id> roomIds = new Set<Id>();
        for (Reservation__c reservation : reservations) {
            roomIds.add(reservation.Room__c);
        }
        return roomIds;
    }

    /** Old and new rooms of reservations whose room or dates changed. */
    private Set<Id> roomsWithChangedBookings() {
        Set<Id> roomIds = new Set<Id>();
        for (Reservation__c reservation : newRecords) {
            Reservation__c oldReservation = oldMap.get(reservation.Id);
            if (
                reservation.Room__c != oldReservation.Room__c ||
                reservation.Check_In_Date__c != oldReservation.Check_In_Date__c ||
                reservation.Check_Out_Date__c != oldReservation.Check_Out_Date__c
            ) {
                roomIds.add(reservation.Room__c);
                roomIds.add(oldReservation.Room__c);
            }
        }
        return roomIds;
    }
}
