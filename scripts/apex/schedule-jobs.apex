// Schedules the nightly room status refresh (00:05 daily). Safe to run again.
// sf apex run --file scripts/apex/schedule-jobs.apex
List<CronTrigger> existing = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :RoomStatusRefreshJob.JOB_NAME];
if (existing.isEmpty()) {
    System.debug('Scheduled job Id: ' + RoomStatusRefreshJob.scheduleDaily());
} else {
    System.debug('Already scheduled: ' + existing[0].Id);
}
