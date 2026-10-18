// Runs every query in SmartStayQueries against the sample data and prints the results.
// sf apex run --file scripts/apex/soql-demo.apex
// Output contains fictional sample data only. Guest contact and identification fields are queried
// but never written to the debug log.

Room__c sampleRoom = [SELECT Id, Name FROM Room__c WHERE Name = 'RM-0001' LIMIT 1];
Guest__c sampleGuest = [SELECT Id, Full_Name__c FROM Guest__c WHERE Last_Name__c = 'Sharma' LIMIT 1];
Date today = Date.today();

System.debug('=== Query 1: reservations for room ' + sampleRoom.Name);
for (Reservation__c r : SmartStayQueries.getReservationsForRoom(sampleRoom.Id)) {
    System.debug(r.Name + ' / ' + r.Guest_Name__c + ' / ' + r.Check_In_Date__c.format() + ' -> ' + r.Check_Out_Date__c.format() + ' / ' + r.Reservation_Status__c + ' / ' + r.Estimated_Amount__c);
}

System.debug('=== Query 2: reservations for guest ' + sampleGuest.Full_Name__c);
for (Reservation__c r : SmartStayQueries.getReservationsForGuest(sampleGuest.Id)) {
    System.debug(r.Name + ' / ' + r.Room_Number__c + ' (' + r.Room_Type__c + ') / ' + r.Check_In_Date__c.format() + ' -> ' + r.Check_Out_Date__c.format() + ' / ' + r.Reservation_Status__c);
}

System.debug('=== Query 3: active reservations for room ' + sampleRoom.Name);
for (Reservation__c r : SmartStayQueries.getActiveReservationsForRoom(sampleRoom.Id)) {
    System.debug(r.Name + ' / ' + r.Check_In_Date__c.format() + ' -> ' + r.Check_Out_Date__c.format() + ' / ' + r.Reservation_Status__c);
}

System.debug('=== Query 4: stays fully inside ' + today.format() + ' .. ' + today.addDays(14).format());
for (Reservation__c r : SmartStayQueries.getReservationsInDateRange(today, today.addDays(14))) {
    System.debug(r.Name + ' / ' + r.Room_Number__c + ' / ' + r.Check_In_Date__c.format() + ' -> ' + r.Check_Out_Date__c.format() + ' / ' + r.Reservation_Status__c);
}

System.debug('=== Query 5 (parent-to-child): room with its reservations');
Room__c roomWithChildren = SmartStayQueries.getRoomWithReservations(sampleRoom.Id);
System.debug(roomWithChildren.Name + ' ' + roomWithChildren.Room_Type__c + ' ' + roomWithChildren.Room_Status__c + ' rate ' + roomWithChildren.Room_Rate__c + ' -> ' + roomWithChildren.Reservations__r.size() + ' reservations');
for (Reservation__c r : roomWithChildren.Reservations__r) {
    System.debug('   ' + r.Name + ' / ' + r.Guest_Name__c + ' / ' + r.Reservation_Status__c);
}

System.debug('=== Query 6 (child-to-parent): reservations from today with room and guest fields');
for (Reservation__c r : SmartStayQueries.getReservationsWithRoomAndGuest(today)) {
    System.debug(r.Name + ' / ' + r.Room__r.Name + ' ' + r.Room__r.Room_Type__c + ' @ ' + r.Room__r.Room_Rate__c + ' / ' + r.Guest__r.First_Name__c + ' ' + r.Guest__r.Last_Name__c);
}

System.debug('=== Query 7 (parent-to-child): guest with reservations');
Guest__c guestWithChildren = SmartStayQueries.getGuestWithReservations(sampleGuest.Id);
System.debug(guestWithChildren.Name + ' ' + guestWithChildren.Full_Name__c + ' -> ' + guestWithChildren.Reservations__r.size() + ' reservations');

System.debug('=== Query 8 (aggregate): non-cancelled reservations by room type');
System.debug(SmartStayQueries.countReservationsByRoomType());
