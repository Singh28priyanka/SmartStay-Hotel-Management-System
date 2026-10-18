// Replays the SmartStay business rules against the loaded sample data, prints PASS/FAIL
// for each check, then ROLLS BACK everything (no data is changed, no email is sent,
// because Salesforce sends email only when a transaction commits).
//
// sf apex run --file scripts/apex/verify-business-rules.apex
// Run as an administrator WITHOUT the SmartStay_Data_Migration permission set.

Savepoint before = Database.setSavepoint();
Integer passed = 0;
Integer failed = 0;
List<String> report = new List<String>();
Date today = Date.today();

Map<String, Room__c> rooms = new Map<String, Room__c>();
for (Room__c r : [SELECT Id, Name, Room_Status__c, Room_Rate__c FROM Room__c]) { rooms.put(r.Name, r); }
Map<String, Reservation__c> res = new Map<String, Reservation__c>();
for (Reservation__c r : [SELECT Id, Name, Room__c, Reservation_Status__c, Check_In_Date__c, Check_Out_Date__c FROM Reservation__c]) { res.put(r.Name, r); }
Id guestId = [SELECT Id FROM Guest__c ORDER BY Name LIMIT 1].Id;

// helpers implemented inline: expectSuccess / expectError
// ---------------------------------------------------------------------------------------
// 1. Valid booking: booked rate, nights, amount, confirmation flow
Reservation__c booking = new Reservation__c(Guest__c = guestId, Room__c = rooms.get('RM-0010').Id,
    Check_In_Date__c = today.addDays(30), Check_Out_Date__c = today.addDays(32), Number_of_Guests__c = 2);
Database.SaveResult sr = Database.insert(booking, false);
Reservation__c saved = sr.isSuccess() ? [SELECT Booked_Rate__c, Number_of_Nights__c, Estimated_Amount__c,
    Reservation_Status__c, Confirmation_Email_Status__c FROM Reservation__c WHERE Id = :booking.Id] : null;
Boolean ok = saved != null && saved.Booked_Rate__c == 3800 && saved.Number_of_Nights__c == 2
    && saved.Estimated_Amount__c == 7600 && saved.Reservation_Status__c == 'Confirmed'
    && saved.Confirmation_Email_Status__c == 'Sent';
report.add((ok ? 'PASS' : 'FAIL') + ' 01 valid booking saved; rate 3800 x 2 nights = 7600; Flow 1 status=' + (saved == null ? sr.getErrors()[0].getMessage() : saved.Confirmation_Email_Status__c));
if (ok) passed++; else failed++;

// 2-7. Rejections
List<List<Object>> rejections = new List<List<Object>>{
    new List<Object>{ '02 overlapping booking rejected', 'RM-0010', 31, 33, 1, 'already booked' },
    new List<Object>{ '03 check-out before check-in rejected', 'RM-0010', 40, 38, 1, 'later than Check-In' },
    new List<Object>{ '04 same-day check-out rejected', 'RM-0010', 40, 40, 1, 'later than Check-In' },
    new List<Object>{ '05 guests above capacity rejected', 'RM-0001', 40, 41, 2, 'exceeds the capacity' },
    new List<Object>{ '06 maintenance room rejected', 'RM-0012', 40, 41, 1, 'under Maintenance' },
    new List<Object>{ '07 past check-in rejected', 'RM-0010', -5, -3, 1, 'cannot be in the past' },
    new List<Object>{ '08 zero guests rejected', 'RM-0010', 40, 41, 0, 'at least 1' }
};
for (List<Object> t : rejections) {
    Reservation__c r = new Reservation__c(Guest__c = guestId, Room__c = rooms.get((String) t[1]).Id,
        Check_In_Date__c = today.addDays((Integer) t[2]), Check_Out_Date__c = today.addDays((Integer) t[3]),
        Number_of_Guests__c = (Integer) t[4]);
    Database.SaveResult result = Database.insert(r, false);
    String msg = result.isSuccess() ? 'SAVED (should have failed)' : result.getErrors()[0].getMessage();
    ok = !result.isSuccess() && msg.contains((String) t[5]);
    report.add((ok ? 'PASS' : 'FAIL') + ' ' + t[0] + ': ' + msg);
    if (ok) passed++; else failed++;
}

// 9. Same-day turnover allowed
Reservation__c turnover = new Reservation__c(Guest__c = guestId, Room__c = rooms.get('RM-0010').Id,
    Check_In_Date__c = today.addDays(32), Check_Out_Date__c = today.addDays(34), Number_of_Guests__c = 1);
sr = Database.insert(turnover, false);
report.add((sr.isSuccess() ? 'PASS' : 'FAIL') + ' 09 arrival on previous guest\'s check-out date allowed');
if (sr.isSuccess()) passed++; else failed++;

// 10. Moving dates into a conflict rejected
turnover.Check_In_Date__c = today.addDays(31);
sr = Database.update(turnover, false);
ok = !sr.isSuccess() && sr.getErrors()[0].getMessage().contains('already booked');
report.add((ok ? 'PASS' : 'FAIL') + ' 10 date change into an existing stay rejected');
if (ok) passed++; else failed++;

// 11. Cancelled booking frees its dates
booking.Reservation_Status__c = 'Cancelled';
update booking;
Reservation__c rebook = new Reservation__c(Guest__c = guestId, Room__c = rooms.get('RM-0010').Id,
    Check_In_Date__c = today.addDays(30), Check_Out_Date__c = today.addDays(32), Number_of_Guests__c = 1,
    Confirmation_Email_Status__c = 'Suppressed');
sr = Database.insert(rebook, false);
report.add((sr.isSuccess() ? 'PASS' : 'FAIL') + ' 11 cancelled dates can be booked again');
if (sr.isSuccess()) passed++; else failed++;

// 12. Invalid status transition and early check-in rejected
Reservation__c future = res.get('RES-0012');
future.Reservation_Status__c = 'Checked-Out';
sr = Database.update(future, false);
ok = !sr.isSuccess() && sr.getErrors()[0].getMessage().contains('cannot move from Confirmed to Checked-Out');
report.add((ok ? 'PASS' : 'FAIL') + ' 12 Confirmed -> Checked-Out rejected');
if (ok) passed++; else failed++;
future.Reservation_Status__c = 'Checked-In';
sr = Database.update(future, false);
ok = !sr.isSuccess() && sr.getErrors()[0].getMessage().contains('Check-in is only possible');
report.add((ok ? 'PASS' : 'FAIL') + ' 13 check-in before arrival date rejected');
if (ok) passed++; else failed++;

// 14-16. Room status through a stay (Flows 2, 3, 4) on today's arrival RES-0010 / RM-0003
Reservation__c arrival = res.get('RES-0010');
Id arrivalRoom = arrival.Room__c;
String before14 = [SELECT Room_Status__c FROM Room__c WHERE Id = :arrivalRoom].Room_Status__c;
arrival.Reservation_Status__c = 'Checked-In';
update arrival;
String afterIn = [SELECT Room_Status__c FROM Room__c WHERE Id = :arrivalRoom].Room_Status__c;
ok = before14 == 'Reserved' && afterIn == 'Occupied';
report.add((ok ? 'PASS' : 'FAIL') + ' 14 check-in: room ' + before14 + ' -> ' + afterIn + ' (Flow 2)');
if (ok) passed++; else failed++;
Database.SaveResult blocked = Database.update(new Room__c(Id = arrivalRoom, Room_Status__c = 'Available'), false);
ok = !blocked.isSuccess() && blocked.getErrors()[0].getMessage().contains('is still checked in');
report.add((ok ? 'PASS' : 'FAIL') + ' 15 occupied room cannot be marked Available (Flow 4)');
if (ok) passed++; else failed++;
arrival.Reservation_Status__c = 'Checked-Out';
update arrival;
String afterOut = [SELECT Room_Status__c FROM Room__c WHERE Id = :arrivalRoom].Room_Status__c;
update new Room__c(Id = arrivalRoom, Room_Status__c = 'Available');
String afterReady = [SELECT Room_Status__c FROM Room__c WHERE Id = :arrivalRoom].Room_Status__c;
ok = afterOut == 'Cleaning' && afterReady == 'Available';
report.add((ok ? 'PASS' : 'FAIL') + ' 16 check-out: room -> ' + afterOut + ' (Flow 3); housekeeping ready -> ' + afterReady);
if (ok) passed++; else failed++;

// 17. Cancelling today's arrival frees the room (Flow 5 + RoomStatusService)
Reservation__c arrival2 = res.get('RES-0011');
String before17 = [SELECT Room_Status__c FROM Room__c WHERE Id = :arrival2.Room__c].Room_Status__c;
arrival2.Reservation_Status__c = 'Cancelled';
update arrival2;
String after17 = [SELECT Room_Status__c FROM Room__c WHERE Id = :arrival2.Room__c].Room_Status__c;
ok = before17 == 'Reserved' && after17 == 'Available';
report.add((ok ? 'PASS' : 'FAIL') + ' 17 cancellation: room ' + before17 + ' -> ' + after17 + ' (Flow 5)');
if (ok) passed++; else failed++;

// 18. Inactive staff cannot be assigned (Flow 6)
Hotel_Staff__c inactive = [SELECT Id FROM Hotel_Staff__c WHERE Active__c = false LIMIT 1];
blocked = Database.update(new Room__c(Id = rooms.get('RM-0011').Id, Assigned_Housekeeper__c = inactive.Id), false);
ok = !blocked.isSuccess() && blocked.getErrors()[0].getMessage().contains('inactive');
report.add((ok ? 'PASS' : 'FAIL') + ' 18 inactive staff assignment rejected (Flow 6)');
if (ok) passed++; else failed++;

// 19. Bulk: 100 bookings in one DML (10 rooms x 10 stays) plus 1 in-batch conflict
List<Room__c> bulkRooms = new List<Room__c>();
for (Integer i = 0; i < 10; i++) {
    bulkRooms.add(new Room__c(Room_Type__c = 'Double', Floor__c = 4, Capacity__c = 2, Room_Rate__c = 3000));
}
insert bulkRooms;
List<Reservation__c> bulkBookings = new List<Reservation__c>();
for (Room__c br : bulkRooms) {
    for (Integer s = 0; s < 10; s++) {
        bulkBookings.add(new Reservation__c(Guest__c = guestId, Room__c = br.Id, Check_In_Date__c = today.addDays(60 + s * 2),
            Check_Out_Date__c = today.addDays(62 + s * 2), Number_of_Guests__c = 1, Confirmation_Email_Status__c = 'Suppressed'));
    }
}
bulkBookings.add(new Reservation__c(Guest__c = guestId, Room__c = bulkRooms[0].Id, Check_In_Date__c = today.addDays(61),
    Check_Out_Date__c = today.addDays(63), Number_of_Guests__c = 1, Confirmation_Email_Status__c = 'Suppressed'));
Integer queriesBefore = Limits.getQueries();
List<Database.SaveResult> bulkResults = Database.insert(bulkBookings, false);
Integer queriesUsed = Limits.getQueries() - queriesBefore;
Integer bulkSaved = 0;
for (Integer i = 0; i < 100; i++) { if (bulkResults[i].isSuccess()) bulkSaved++; }
ok = bulkSaved == 100 && !bulkResults[100].isSuccess() && queriesUsed <= 10;
report.add((ok ? 'PASS' : 'FAIL') + ' 19 bulk: ' + bulkSaved + '/100 saved, in-batch conflict rejected=' + !bulkResults[100].isSuccess() + ', SOQL used=' + queriesUsed);
if (ok) passed++; else failed++;

Database.rollback(before);

for (String line : report) { System.debug(line); }
System.debug('RESULT: ' + passed + ' passed, ' + failed + ' failed. All changes rolled back.');
System.debug('Rooms after rollback: RM-0003=' + [SELECT Room_Status__c FROM Room__c WHERE Name = 'RM-0003'].Room_Status__c
    + ', reservations=' + [SELECT COUNT() FROM Reservation__c]);
