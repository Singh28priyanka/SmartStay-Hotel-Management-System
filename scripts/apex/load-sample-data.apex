// SmartStay fictional sample data. All names, phone numbers, emails (@example.com)
// and ID numbers are invented.
//
// Prerequisite (past-dated stays need it):
//   sf org assign permset --name SmartStay_Data_Migration
// Run:
//   sf apex run --file scripts/apex/load-sample-data.apex
// Afterwards:
//   sf apex run --file scripts/apex/remove-data-migration-access.apex
//
// Dates are relative to today, so "today's check-ins", "current month" and the room
// statuses are meaningful whenever the script is run. Every step goes through the real
// trigger, validation rules and Flows; nothing is written around the automation.
// Confirmation emails are suppressed for sample bookings (Confirmation_Email_Status__c).

Assert.areEqual(0, [SELECT COUNT() FROM Room__c], 'Rooms already exist: sample data was loaded before.');
Assert.isTrue(
    FeatureManagement.checkPermission('SmartStay_Historical_Data_Load'),
    'Assign the SmartStay_Data_Migration permission set first (see the header of this script).'
);
Date today = Date.today();

// ---------------------------------------------------------------- staff (6)
Hotel_Staff__c housekeeperActive = new Hotel_Staff__c(Name = 'Sunil Yadav', Department__c = 'Housekeeping',
    Mobile__c = '+91 90000 20001', Email__c = 'sunil.yadav@example.com', Shift__c = 'Morning', Active__c = true);
Hotel_Staff__c housekeeperInactive = new Hotel_Staff__c(Name = 'Ramesh Pillai', Department__c = 'Housekeeping',
    Mobile__c = '+91 90000 20002', Email__c = 'ramesh.pillai@example.com', Shift__c = 'Night', Active__c = false);
insert new List<Hotel_Staff__c>{
    new Hotel_Staff__c(Name = 'Meera Kapoor', Department__c = 'Manager', Mobile__c = '+91 90000 20000',
        Email__c = 'meera.kapoor@example.com', Shift__c = 'Morning', Active__c = true),
    new Hotel_Staff__c(Name = 'Arjun Mehta', Department__c = 'Reception', Mobile__c = '+91 90000 20003',
        Email__c = 'arjun.mehta@example.com', Shift__c = 'Morning', Active__c = true),
    new Hotel_Staff__c(Name = 'Priya Nair', Department__c = 'Reception', Mobile__c = '+91 90000 20004',
        Email__c = 'priya.nair@example.com', Shift__c = 'Evening', Active__c = true),
    new Hotel_Staff__c(Name = 'Kavita Joshi', Department__c = 'Accounts', Mobile__c = '+91 90000 20005',
        Email__c = 'kavita.joshi@example.com', Shift__c = 'Morning', Active__c = true),
    housekeeperActive,
    housekeeperInactive
};

// ---------------------------------------------------------------- rooms (12): type, capacity, rate, floor
List<List<Object>> roomSpecs = new List<List<Object>>{
    new List<Object>{ 'Single', 1, 2500, 1, 'Wi-Fi;TV;AC' },
    new List<Object>{ 'Single', 1, 2500, 1, 'Wi-Fi;TV' },
    new List<Object>{ 'Double', 2, 3800, 1, 'Wi-Fi;TV;AC' },
    new List<Object>{ 'Double', 2, 3800, 2, 'Wi-Fi;TV;AC;Breakfast' },
    new List<Object>{ 'Double', 2, 3800, 2, 'Wi-Fi;TV;AC' },
    new List<Object>{ 'Deluxe', 3, 5500, 2, 'Wi-Fi;TV;AC;Breakfast' },
    new List<Object>{ 'Deluxe', 3, 5500, 3, 'Wi-Fi;TV;AC;Breakfast;Parking' },
    new List<Object>{ 'Suite', 4, 9000, 3, 'Wi-Fi;TV;AC;Breakfast;Parking' },
    new List<Object>{ 'Single', 1, 2500, 1, 'Wi-Fi;AC' },
    new List<Object>{ 'Double', 2, 3800, 2, 'Wi-Fi;TV;AC' },
    new List<Object>{ 'Deluxe', 3, 5800, 3, 'Wi-Fi;TV;AC;Breakfast' },
    new List<Object>{ 'Suite', 4, 9500, 3, 'Wi-Fi;TV;AC;Breakfast;Parking' }
};
List<Room__c> rooms = new List<Room__c>();
for (List<Object> spec : roomSpecs) {
    rooms.add(new Room__c(Room_Type__c = (String) spec[0], Capacity__c = (Integer) spec[1],
        Room_Rate__c = (Integer) spec[2], Floor__c = (Integer) spec[3], Amenities__c = (String) spec[4]));
}
insert rooms; // RM-0001 .. RM-0012, all Available

// ---------------------------------------------------------------- guests (12)
List<List<String>> guestSpecs = new List<List<String>>{
    new List<String>{ 'Aarav', 'Sharma', '1988-04-12', 'Aadhaar' },
    new List<String>{ 'Diya', 'Patel', '1992-09-30', 'Passport' },
    new List<String>{ 'Rohan', 'Verma', '1979-01-05', 'Driving License' },
    new List<String>{ 'Ananya', 'Iyer', '1995-12-18', 'Aadhaar' },
    new List<String>{ 'Vikram', 'Singh', '1983-07-22', 'Passport' },
    new List<String>{ 'Sneha', 'Reddy', '1990-03-14', 'Aadhaar' },
    new List<String>{ 'Kabir', 'Malhotra', '1975-11-02', 'Other' },
    new List<String>{ 'Isha', 'Banerjee', '2000-06-09', 'Driving License' },
    new List<String>{ 'Farhan', 'Qureshi', '1986-08-27', 'Passport' },
    new List<String>{ 'Lakshmi', 'Menon', '1969-02-11', 'Aadhaar' },
    new List<String>{ 'Nikhil', 'Desai', '1998-10-01', 'Aadhaar' },
    new List<String>{ 'Zoya', 'Khan', '1993-05-25', 'Passport' }
};
List<Guest__c> guests = new List<Guest__c>();
for (Integer i = 0; i < guestSpecs.size(); i++) {
    List<String> spec = guestSpecs[i];
    String n = String.valueOf(i + 1).leftPad(2, '0');
    guests.add(new Guest__c(
        First_Name__c = spec[0],
        Last_Name__c = spec[1],
        Mobile__c = '+91 90000 100' + n,
        Email__c = spec[0].toLowerCase() + '.' + spec[1].toLowerCase() + '@example.com',
        Date_of_Birth__c = Date.valueOf(spec[2]),
        ID_Type__c = spec[3],
        ID_Number__c = 'DEMO-' + spec[3].left(3).toUpperCase() + '-00' + n,
        Address__c = n + ' Demo Street, Bhopal, Madhya Pradesh (fictional)'
    ));
}
insert guests;

// ---------------------------------------------------------------- reservations
// r(guestIndex, roomIndex, checkInOffset, checkOutOffset, guests, request) - indexes are 1-based
Map<String, Reservation__c> booking = new Map<String, Reservation__c>();
List<List<Object>> bookingSpecs = new List<List<Object>>{
    // key, guest, room, in, out, guests, special request
    new List<Object>{ 'HIST_1', 1, 1, -20, -17, 1, null },             // past stay, checked out
    new List<Object>{ 'HIST_2', 2, 3, -15, -12, 2, 'Extra towels' },   // past stay, checked out
    new List<Object>{ 'HIST_3', 3, 6, -10, -8, 3, null },              // past stay, checked out
    new List<Object>{ 'HIST_4', 4, 8, -25, -22, 4, 'Anniversary cake' }, // past stay, checked out
    new List<Object>{ 'HIST_CANCEL', 5, 1, -12, -10, 1, null },        // cancelled
    new List<Object>{ 'INHOUSE_1', 6, 4, -2, 1, 2, null },             // checked in, leaves tomorrow
    new List<Object>{ 'INHOUSE_2', 7, 7, -1, 2, 2, 'Late checkout if possible' }, // checked in
    new List<Object>{ 'DUE_OUT', 8, 5, -3, 0, 1, null },               // checked in, due out today
    new List<Object>{ 'LEFT_TODAY', 9, 2, -2, 0, 1, null },            // checked out today
    new List<Object>{ 'ARRIVE_1', 10, 3, 0, 3, 2, 'Ground floor preferred' }, // arriving today
    new List<Object>{ 'ARRIVE_2', 11, 9, 0, 2, 1, null },              // arriving today
    new List<Object>{ 'FUTURE_1', 12, 1, 5, 8, 1, null },
    new List<Object>{ 'FUTURE_2', 1, 1, 8, 10, 1, 'Same-day turnover after FUTURE_1' },
    new List<Object>{ 'FUTURE_3', 2, 6, 3, 6, 3, null },
    new List<Object>{ 'FUTURE_4', 3, 8, 10, 14, 4, 'Airport pickup' },
    new List<Object>{ 'TO_CANCEL', 4, 10, 2, 4, 2, null },             // cancelled, then rebooked
    new List<Object>{ 'FUTURE_5', 5, 11, 15, 18, 2, null },
    new List<Object>{ 'FUTURE_6', 6, 4, 1, 3, 2, 'Arrives as INHOUSE_1 leaves' }
};
for (List<Object> spec : bookingSpecs) {
    booking.put((String) spec[0], new Reservation__c(
        Guest__c = guests[(Integer) spec[1] - 1].Id,
        Room__c = rooms[(Integer) spec[2] - 1].Id,
        Check_In_Date__c = today.addDays((Integer) spec[3]),
        Check_Out_Date__c = today.addDays((Integer) spec[4]),
        Number_of_Guests__c = (Integer) spec[5],
        Special_Request__c = (String) spec[6],
        Confirmation_Email_Status__c = 'Suppressed'
    ));
}
insert booking.values();

// Past stays: check in, then check out (rooms go Occupied -> Cleaning via Flows 2 and 3).
List<Reservation__c> pastStays = new List<Reservation__c>{
    booking.get('HIST_1'), booking.get('HIST_2'), booking.get('HIST_3'), booking.get('HIST_4')
};
for (Reservation__c r : pastStays) { r.Reservation_Status__c = 'Checked-In'; }
update pastStays;
for (Reservation__c r : pastStays) { r.Reservation_Status__c = 'Checked-Out'; }
update pastStays;

// Cancellations (Flow 5 notifies the manager role and recalculates the room).
List<Reservation__c> cancellations = new List<Reservation__c>{ booking.get('HIST_CANCEL'), booking.get('TO_CANCEL') };
for (Reservation__c r : cancellations) { r.Reservation_Status__c = 'Cancelled'; }
update cancellations;

// Housekeeping finishes the rooms of past stays (Flow 4 keeps RM-0003 Reserved: arrival today).
update new List<Room__c>{
    new Room__c(Id = rooms[0].Id, Room_Status__c = 'Available', Assigned_Housekeeper__c = housekeeperActive.Id),
    new Room__c(Id = rooms[2].Id, Room_Status__c = 'Available'),
    new Room__c(Id = rooms[5].Id, Room_Status__c = 'Available', Assigned_Housekeeper__c = housekeeperActive.Id),
    new Room__c(Id = rooms[7].Id, Room_Status__c = 'Available')
};

// Current guests check in; one already left this morning.
List<Reservation__c> currentStays = new List<Reservation__c>{
    booking.get('INHOUSE_1'), booking.get('INHOUSE_2'), booking.get('DUE_OUT'), booking.get('LEFT_TODAY')
};
for (Reservation__c r : currentStays) { r.Reservation_Status__c = 'Checked-In'; }
update currentStays;
booking.get('LEFT_TODAY').Reservation_Status__c = 'Checked-Out';
update booking.get('LEFT_TODAY'); // RM-0002 -> Cleaning

// Cancelled dates are free again: rebook RM-0010 for exactly the cancelled stay.
Reservation__c rebooking = new Reservation__c(
    Guest__c = guests[6].Id, Room__c = rooms[9].Id,
    Check_In_Date__c = today.addDays(2), Check_Out_Date__c = today.addDays(4),
    Number_of_Guests__c = 2, Special_Request__c = 'Booked into dates freed by a cancellation',
    Confirmation_Email_Status__c = 'Suppressed'
);
insert rebooking;

// RM-0012 goes into maintenance.
update new Room__c(Id = rooms[11].Id, Room_Status__c = 'Maintenance');

// ---------------------------------------------------------------- rejected on purpose
List<Reservation__c> invalid = new List<Reservation__c>{
    // overlaps FUTURE_1 on RM-0001
    new Reservation__c(Guest__c = guests[7].Id, Room__c = rooms[0].Id, Check_In_Date__c = today.addDays(6),
        Check_Out_Date__c = today.addDays(9), Number_of_Guests__c = 1, Confirmation_Email_Status__c = 'Suppressed'),
    // 3 guests in a Single room
    new Reservation__c(Guest__c = guests[8].Id, Room__c = rooms[8].Id, Check_In_Date__c = today.addDays(20),
        Check_Out_Date__c = today.addDays(22), Number_of_Guests__c = 3, Confirmation_Email_Status__c = 'Suppressed'),
    // check-out before check-in
    new Reservation__c(Guest__c = guests[9].Id, Room__c = rooms[10].Id, Check_In_Date__c = today.addDays(25),
        Check_Out_Date__c = today.addDays(23), Number_of_Guests__c = 1, Confirmation_Email_Status__c = 'Suppressed'),
    // room under maintenance
    new Reservation__c(Guest__c = guests[10].Id, Room__c = rooms[11].Id, Check_In_Date__c = today.addDays(5),
        Check_Out_Date__c = today.addDays(7), Number_of_Guests__c = 2, Confirmation_Email_Status__c = 'Suppressed')
};
List<String> labels = new List<String>{ 'Overlapping booking', 'Guests above capacity', 'Invalid check-out date', 'Maintenance room' };
List<Database.SaveResult> results = Database.insert(invalid, false);
for (Integer i = 0; i < results.size(); i++) {
    System.debug('REJECTED AS EXPECTED [' + labels[i] + ']: '
        + (results[i].isSuccess() ? 'NOT REJECTED - check configuration!' : results[i].getErrors()[0].getMessage()));
}
Database.SaveResult staffResult = Database.update(
    new Room__c(Id = rooms[9].Id, Assigned_Housekeeper__c = housekeeperInactive.Id), false);
System.debug('REJECTED AS EXPECTED [Inactive staff assignment]: '
    + (staffResult.isSuccess() ? 'NOT REJECTED - check configuration!' : staffResult.getErrors()[0].getMessage()));

// ---------------------------------------------------------------- summary
for (Room__c room : [SELECT Name, Room_Type__c, Room_Status__c FROM Room__c ORDER BY Name]) {
    System.debug(room.Name + ' ' + room.Room_Type__c + ' -> ' + room.Room_Status__c);
}
for (AggregateResult row : [SELECT Reservation_Status__c status, COUNT(Id) total FROM Reservation__c GROUP BY Reservation_Status__c]) {
    System.debug('Reservations ' + row.get('status') + ': ' + row.get('total'));
}
