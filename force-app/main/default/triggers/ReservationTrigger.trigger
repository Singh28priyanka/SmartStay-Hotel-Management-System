/**
 * Single trigger for Reservation__c. All logic lives in ReservationTriggerHandler
 * and the services it calls, so the trigger stays logic-free and the order of
 * operations is explicit in one place.
 */
trigger ReservationTrigger on Reservation__c(before insert, before update, after insert, after update) {
    new ReservationTriggerHandler().run();
}
