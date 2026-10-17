/**
 * Nightly refresh of Room Status. Needed because "Reserved" means "a confirmed
 * guest is due today", and today changes at midnight without any record changing.
 *
 * Schedule once (Execute Anonymous):  RoomStatusRefreshJob.scheduleDaily();
 */
public without sharing class RoomStatusRefreshJob implements Database.Batchable<SObject>, Schedulable {
    public static final String JOB_NAME = 'SmartStay Daily Room Status Refresh';
    // 00:05 every day, in the scheduling user's time zone.
    public static final String DAILY_CRON = '0 5 0 * * ?';

    public static Id scheduleDaily() {
        return scheduleDaily(JOB_NAME);
    }

    /** Job names must be unique, so tests schedule under their own name. */
    @TestVisible
    private static Id scheduleDaily(String jobName) {
        return System.schedule(jobName, DAILY_CRON, new RoomStatusRefreshJob());
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(new RoomStatusRefreshJob(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            [SELECT Id FROM Room__c WHERE Room_Status__c != :SmartStayConstants.ROOM_MAINTENANCE]
        );
    }

    public void execute(Database.BatchableContext context, List<Room__c> scope) {
        RoomStatusService.recalculate(new Map<Id, Room__c>(scope).keySet());
    }

    public void finish(Database.BatchableContext context) {
        // Nothing to do: each chunk updates its own rooms.
    }
}
