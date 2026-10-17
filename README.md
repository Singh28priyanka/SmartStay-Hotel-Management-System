# SmartStay — Salesforce Hotel Management System

LNCT Salesforce Admin & Development Capstone (Wipro Salesforce COE Skilling Program).

A native Salesforce application for rooms, guests, reservations and hotel staff: custom objects, validation rules,
formula fields, record-triggered Flows, an Apex trigger with handler and service classes, SOQL, role-based security,
reports and dashboards. No LWC, Aura, Visualforce or external systems. All sample data is fictional.

## Project structure

```
force-app/main/default/
  objects/            Room__c, Guest__c, Reservation__c, Hotel_Staff__c (fields, validation rules, list views, compact layouts)
  layouts/            Page layouts with related lists and quick actions
  quickActions/       Check In, Check Out, Cancel Reservation, Mark Room Ready, Mark Under Maintenance
  applications/       SmartStay Hotel Management System (Lightning app)
  contentassets/      App logo
  tabs/               Object tabs
  triggers/           ReservationTrigger (logic-free)
  classes/            Handler, services, nightly job, SOQL class, test classes
  flows/              6 record-triggered Flows
  email/, workflows/  Cancellation email template and email alert
  roles/, profiles/, permissionsets/, sharingRules/, customPermissions/
  reportTypes/, reports/, dashboards/
scripts/apex/         Demo users, sample data, SOQL demo, job scheduling
docs/                 Project documentation
```

## Setup and deployment

Prerequisites: a Salesforce Developer Edition org, Salesforce CLI (`sf`), Git. VS Code with the Salesforce Extension Pack
is optional.

1. Authorize the org (sign in through the browser window):

   ```bash
   sf org login web --alias smartstay --set-default
   ```

2. Deploy all metadata:

   ```bash
   sf project deploy start --source-dir force-app --wait 30
   ```

3. Make the admin the Hotel CEO and create the demo users (as many as free Salesforce Platform licenses allow):

   ```bash
   sf apex run --file scripts/apex/setup-demo-users.apex
   ```

4. Load the fictional sample data (needs a temporary permission to create past-dated stays), then remove that permission:

   ```bash
   sf org assign permset --name SmartStay_Data_Migration
   ```

   ```bash
   sf apex run --file scripts/apex/load-sample-data.apex
   ```

   ```bash
   sf apex run --file scripts/apex/remove-data-migration-access.apex
   ```

5. Schedule the nightly room-status refresh:

   ```bash
   sf apex run --file scripts/apex/schedule-jobs.apex
   ```

6. Run all Apex tests with coverage:

   ```bash
   sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 30
   ```

7. See the SOQL queries' output:

   ```bash
   sf apex run --file scripts/apex/soql-demo.apex
   ```

8. Open the org, then App Launcher → **SmartStay Hotel Management System**:

   ```bash
   sf org open
   ```

To receive the guest confirmation email in a demo, create a guest whose Email is an address you can read, then book a
room for them. Email deliverability (Setup → Deliverability) must be **All email**.

See [docs/SmartStay_Project_Documentation.md](docs/SmartStay_Project_Documentation.md) for the full design, test
results and interview notes.
