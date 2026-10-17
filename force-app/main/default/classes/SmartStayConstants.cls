/**
 * Picklist values and names shared by the SmartStay Apex classes, so a value is
 * spelled in exactly one place.
 */
public with sharing class SmartStayConstants {
    // Reservation_Status__c
    public static final String STATUS_CONFIRMED = 'Confirmed';
    public static final String STATUS_CHECKED_IN = 'Checked-In';
    public static final String STATUS_CHECKED_OUT = 'Checked-Out';
    public static final String STATUS_CANCELLED = 'Cancelled';

    // Room_Status__c
    public static final String ROOM_AVAILABLE = 'Available';
    public static final String ROOM_RESERVED = 'Reserved';
    public static final String ROOM_OCCUPIED = 'Occupied';
    public static final String ROOM_CLEANING = 'Cleaning';
    public static final String ROOM_MAINTENANCE = 'Maintenance';

    // Custom permission that allows loading past-dated (historical) reservations.
    public static final String HISTORICAL_LOAD_PERMISSION = 'SmartStay_Historical_Data_Load';
}
