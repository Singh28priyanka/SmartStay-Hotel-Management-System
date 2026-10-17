/**
 * Validation rules and formula fields on Room, Guest and Hotel Staff.
 * (Reservation validation rules are covered in ReservationBookingServiceTest and
 * ReservationStatusServiceTest because they interact with the booking logic.)
 */
@IsTest
private class SmartStayValidationRulesTest {
    private static Exception insertExpectingError(SObject record) {
        try {
            insert record;
        } catch (DmlException e) {
            return e;
        }
        return null;
    }

    @IsTest
    static void roomRateMustBePositive() {
        SmartStayTestDataFactory.assertDmlError(
            insertExpectingError(SmartStayTestDataFactory.buildRoom('Single', 1, 0)),
            'Room Rate is required and must be greater than zero'
        );
        SmartStayTestDataFactory.assertDmlError(
            insertExpectingError(SmartStayTestDataFactory.buildRoom('Single', 1, null)),
            'Room Rate is required'
        );
    }

    @IsTest
    static void roomCapacityMustBePositive() {
        SmartStayTestDataFactory.assertDmlError(
            insertExpectingError(SmartStayTestDataFactory.buildRoom('Single', 0, 2000)),
            'Capacity is required and must be at least 1'
        );
    }

    @IsTest
    static void roomFloorCannotBeNegative() {
        Room__c room = SmartStayTestDataFactory.buildRoom('Single', 1, 2000);
        room.Floor__c = -1;
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(room), 'Floor cannot be negative');
    }

    @IsTest
    static void newRoomDefaultsToAvailableWithUniqueNumber() {
        List<Room__c> rooms = new List<Room__c>{
            new Room__c(Room_Type__c = 'Single', Floor__c = 0, Capacity__c = 1, Room_Rate__c = 2000),
            new Room__c(Room_Type__c = 'Double', Floor__c = 0, Capacity__c = 2, Room_Rate__c = 3000)
        };
        insert rooms;

        List<Room__c> saved = [SELECT Name, Room_Status__c FROM Room__c WHERE Id IN :rooms];
        Assert.areEqual('Available', saved[0].Room_Status__c, 'Default status');
        Assert.areNotEqual(saved[0].Name, saved[1].Name, 'Auto Number gives each room a unique number');
        Assert.isTrue(saved[0].Name.startsWith('RM-'), 'Format RM-{0000}: ' + saved[0].Name);
    }

    @IsTest
    static void guestDateOfBirthCannotBeInFuture() {
        Guest__c guest = SmartStayTestDataFactory.buildGuest(1);
        guest.Date_of_Birth__c = Date.today().addDays(1);
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(guest), 'cannot be in the future');
    }

    @IsTest
    static void guestDateOfBirthMustBePlausible() {
        Guest__c guest = SmartStayTestDataFactory.buildGuest(1);
        guest.Date_of_Birth__c = Date.today().addYears(-121);
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(guest), 'more than 120 years ago');
    }

    @IsTest
    static void guestMobileMustBeValid() {
        Guest__c guest = SmartStayTestDataFactory.buildGuest(1);
        guest.Mobile__c = '12345';
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(guest), 'valid mobile number');
    }

    @IsTest
    static void guestRequiredFieldsAreEnforced() {
        Guest__c guest = SmartStayTestDataFactory.buildGuest(1);
        guest.Last_Name__c = null;
        guest.Email__c = null;
        Exception caught = insertExpectingError(guest);
        SmartStayTestDataFactory.assertDmlError(caught, 'REQUIRED_FIELD_MISSING');
    }

    @IsTest
    static void guestEmailFormatIsValidated() {
        Guest__c guest = SmartStayTestDataFactory.buildGuest(1);
        guest.Email__c = 'not-an-email';
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(guest), 'INVALID_EMAIL_ADDRESS');
    }

    @IsTest
    static void guestIdTypeAndNumberGoTogether() {
        Guest__c missingNumber = SmartStayTestDataFactory.buildGuest(1);
        missingNumber.ID_Number__c = null;
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(missingNumber), 'Enter the ID Number');

        Guest__c missingType = SmartStayTestDataFactory.buildGuest(2);
        missingType.ID_Type__c = null;
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(missingType), 'Select the ID Type');
    }

    @IsTest
    static void guestAgeIsCalculatedFromDateOfBirth() {
        Date today = Date.today();
        Guest__c birthdayToday = SmartStayTestDataFactory.buildGuest(1);
        birthdayToday.Date_of_Birth__c = today.addYears(-30);
        Guest__c birthdayTomorrow = SmartStayTestDataFactory.buildGuest(2);
        birthdayTomorrow.Date_of_Birth__c = today.addYears(-30).addDays(1);
        Guest__c noBirthDate = SmartStayTestDataFactory.buildGuest(3);
        noBirthDate.Date_of_Birth__c = null;
        insert new List<Guest__c>{ birthdayToday, birthdayTomorrow, noBirthDate };

        Map<Id, Guest__c> saved = new Map<Id, Guest__c>(
            [SELECT Id, Age__c, Full_Name__c FROM Guest__c]
        );
        Assert.areEqual(30, saved.get(birthdayToday.Id).Age__c, 'Birthday today counts');
        Assert.areEqual(29, saved.get(birthdayTomorrow.Id).Age__c, 'Birthday not reached yet');
        Assert.isNull(saved.get(noBirthDate.Id).Age__c, 'Blank Date of Birth gives blank Age');
        Assert.areEqual('Test Guest 0001', saved.get(birthdayToday.Id).Full_Name__c);
    }

    @IsTest
    static void staffMobileMustBeValid() {
        Hotel_Staff__c staff = SmartStayTestDataFactory.buildStaff('Kiran Rao', 'Reception', true);
        staff.Mobile__c = 'abc';
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(staff), 'valid mobile number');
    }

    @IsTest
    static void staffRequiredFieldsAreEnforced() {
        Hotel_Staff__c staff = SmartStayTestDataFactory.buildStaff('Kiran Rao', 'Reception', true);
        staff.Email__c = null;
        SmartStayTestDataFactory.assertDmlError(insertExpectingError(staff), 'REQUIRED_FIELD_MISSING');
    }

    @IsTest
    static void guestWithReservationsCannotBeDeleted() {
        Room__c room = SmartStayTestDataFactory.createRoom('Double', 2, 3000);
        Guest__c guest = SmartStayTestDataFactory.createGuest(1);
        SmartStayTestDataFactory.createReservation(guest.Id, room.Id, 3, 5);

        Exception guestError;
        try {
            delete guest;
        } catch (DmlException e) {
            guestError = e;
        }
        SmartStayTestDataFactory.assertDmlError(guestError, 'DELETE_FAILED');

        Exception roomError;
        try {
            delete room;
        } catch (DmlException e) {
            roomError = e;
        }
        SmartStayTestDataFactory.assertDmlError(roomError, 'DELETE_FAILED');
    }
}
