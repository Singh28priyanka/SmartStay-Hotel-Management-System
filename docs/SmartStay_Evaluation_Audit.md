# SmartStay — Requirement Audit (strict evaluator view)

Audit date: 17/10/2026. Org: Developer Edition `00Dg800000OcyW7EAJ`. Source: `main` branch.

**Rule applied:** a requirement is PASS only when there is direct evidence from the org (metadata describe/query,
REST API output, Apex test result, or a live verification run). Existing code or metadata alone is not evidence of
behaviour. Anything that could not be observed is NOT VERIFIED.

## Evidence used

| ID | Evidence | How it was produced |
|---|---|---|
| E1 | Object, field and relationship describe | `sf sobject describe` on the 4 objects |
| E2 | OWD values | `EntityDefinition.InternalSharingModel` query |
| E3 | 16 active validation rules | Tooling API `ValidationRule` query |
| E4 | 6 Flows, each with active version 1 | Tooling API `FlowDefinition` query |
| E5 | Trigger active on 4 events | Tooling API `ApexTrigger` query |
| E6 | Deployed layouts (quick actions, related lists) and layout assignment | Metadata retrieve + `ProfileLayout` query |
| E7 | 15 list views | `ListView` query |
| E8 | Roles, users, profiles, permission-set assignments, object permissions, FLS | SOQL on `UserRole`, `User`, `PermissionSetAssignment`, `ObjectPermissions`, `FieldPermissions` |
| E9 | 5 sharing rules | Metadata retrieve of `SharingRules` |
| E10 | Apex test run `707g800000pUcPh`: **76 test methods, 76 passed** | `sf apex run test --test-level RunLocalTests` |
| E11 | Live rule replay: **19/19 checks passed**, rolled back | `scripts/apex/verify-business-rules.apex` |
| E12 | All 10 reports executed with expected totals | Analytics REST API `/analytics/reports/{id}` |
| E13 | All 9 dashboard components return data after refresh | Analytics REST API `/analytics/dashboards/{id}` |
| E14 | SOQL demo output | `scripts/apex/soql-demo.apex` |
| E15 | Check-only full deployment `0Afg800000HpRpBCAV`: 155/155 components, 76/76 tests | `sf project deploy validate --test-level RunLocalTests` |
| E16 | User's own screenshots of the app (navigation bar, Rooms list-view menu, Dashboards home) | Provided in chat |
| E17 | GitHub repository | https://github.com/Singh28priyanka/SmartStay-Hotel-Management-System |

## Summary

| Status | Count |
|---|---|
| PASS | 67 |
| FAIL | 1 |
| NOT VERIFIED | 7 |

Update 18/10/2026: three of the four original FAIL items were fixed (logo setting, test count, debug-log e-mail).
Remaining FAIL: no screenshots in the documentation. The logo fix is NOT VERIFIED until seen in the browser.

---

## 1. Application and interface

| # | Requirement | Expected implementation | Actual implementation | Evidence | Test performed | Actual result | Missing / incorrect | Corrective steps | Status |
|---|---|---|---|---|---|---|---|---|---|
| 1.1 | Lightning app "SmartStay Hotel Management System" | CustomApplication, Lightning UI | `SmartStay_Hotel_Management_System`, uiType Lightning | AppMenuItem query; E16 | Opened app in browser (user) | App opens with SmartStay label | — | — | PASS |
| 1.2 | Navigation: Rooms, Guests, Reservations, Hotel Staff, Reports, Dashboards | 6 nav items | Exactly these 6 tabs | Retrieved app XML; E16 | Visual (user screenshot) | All 6 visible in order | — | — | PASS |
| 1.3 | Application logo | Logo visible for the app | ContentAsset `SmartStay_Logo` set as app brand logo, but `shouldOverrideOrgTheme=false` | Retrieved app XML; E16 | Visual (user screenshot) | Header shows the Salesforce cloud logo, not SmartStay | Fixed 18/10/2026: `shouldOverrideOrgTheme` set to true and deployed; not yet seen in the browser | Reload the app and screenshot the header | NOT VERIFIED |
| 1.4 | List views: Available, Occupied, Maintenance, Today's Check-Ins/Outs, Confirmed, Cancelled | 7 list views with filters | All 7 present + Reserved, Being Cleaned, In-House, All views | E7; E16 (menu shows room views) | Query | 15 list views exist | Data inside each view not visually checked | Open each view and screenshot | PASS |
| 1.5 | Record pages, related lists, page and compact layouts | Layouts with related lists; compact layouts | Layouts with Reservations related list, field history list, quick actions; compact layout per object | E6 | Retrieve + assignment query | Layouts assigned to System Administrator and SmartStay Hotel Staff profiles | — | — | PASS |
| 1.6 | Functional actions (not hard-coded) | Actions update real records | Quick actions Check In, Check Out, Cancel Reservation, Mark Room Ready, Mark Under Maintenance | E6; E11 (status changes through the same automation) | Live replay of status changes | Room status changes correctly | Buttons not clicked in the UI | Click Check In on a today arrival during demo | PASS |

## 2. Data model

| # | Requirement | Expected | Actual | Evidence | Test | Result | Gap | Fix | Status |
|---|---|---|---|---|---|---|---|---|---|
| 2.1 | Room fields (7) incl. RM-{0000} auto number | Auto Number, picklists, number, currency, multi-select | All 7 fields with specified types; numbering starts RM-0001 | E1 | Describe; `newRoomDefaultsToAvailableWithUniqueNumber` | Pass | — | — | PASS |
| 2.2 | Room number unique | Unique identifier | Auto Number record name | E1; test 2.1 | Two inserts compared | Different numbers | Not a DB unique constraint (documented) | — | PASS |
| 2.3 | Room default status Available | Picklist default | Default Available | E1; E10 | Insert without status | Available | — | — | PASS |
| 2.4 | Guest fields (9) incl. Age formula | Text, phone, email, date, formula, picklist, long text | All 9 + Full Name formula | E1 | Describe | Types match | — | — | PASS |
| 2.5 | Reservation fields (10) incl. RES-{0000}, Nights, Estimated Amount | Lookups, dates, picklist, formulas | All 10 + Booked Rate, Guest Name, Room Number, Room Type, Confirmation Email Status | E1 | Describe; E10; E11 #01 | 3,800 × 2 = 7,600 | — | — | PASS |
| 2.6 | Hotel Staff fields (6) | Text, picklists, phone, email, checkbox | All 6 | E1 | Describe | Types match | — | — | PASS |
| 2.7 | Guest → Reservation and Room → Reservation lookups | Lookup relationships | Required lookups, Restrict delete, `Reservations__r` | E1 (restrictedDelete=true) | `guestWithReservationsCannotBeDeleted` | DELETE_FAILED for guest and room | — | — | PASS |
| 2.8 | Related lists on Guest and Room; guest/room details on Reservation | Related lists + lookup fields | Reservations related list on both; formula fields on Reservation | E6 | Retrieve | Present | — | — | PASS |
| 2.9 | Rate-change behaviour documented | Explain effect | Booked Rate frozen at booking | Docs §8; E10 | `roomRateChangeDoesNotAlterExistingBooking` | Pass | — | — | PASS |

## 3. Validation rules and formulas

| # | Requirement | Expected | Actual | Evidence | Test | Result | Gap | Fix | Status |
|---|---|---|---|---|---|---|---|---|---|
| 3.1 | Room: rate > 0, capacity > 0 | Validation rules | Room_Rate_Must_Be_Positive, Capacity_Must_Be_Positive (+ floor, status) | E3 | `roomRateMustBePositive`, `roomCapacityMustBePositive` | Pass | — | — | PASS |
| 3.2 | Guest: names, email format, DOB, no negative age | Required fields + rules | Required fields; Email type; DOB rules; mobile and ID rules | E1, E3 | 7 tests in `SmartStayValidationRulesTest` | Pass (incl. `INVALID_EMAIL_ADDRESS`) | — | — | PASS |
| 3.3 | Reservation: dates, guests > 0, capacity, maintenance, room & guest selected | Rules + Apex | 6 rules; required lookups; maintenance in Apex | E3; E10; E11 #03–#08 | Live inserts | All rejected with clear messages | — | — | PASS |
| 3.4 | Hotel Staff: name, email, mobile required | Required fields | Required + mobile format rule | E1, E3 | `staffRequiredFieldsAreEnforced`, `staffMobileMustBeValid` | Pass | — | — | PASS |
| 3.5 | Cross-record overlap not faked with a formula | Apex | Implemented in Apex; limitation explained | Docs §9, §13 | E11 #02 | Rejected | — | — | PASS |
| 3.6 | Age, Nights, Estimated Amount formulas handle blanks | Null-safe formulas | `IF(ISBLANK(...), NULL, ...)`; BlankAsBlank | E1; E10 | `guestAgeIsCalculatedFromDateOfBirth` (30 / 29 / blank) | Pass | — | — | PASS |

## 4. Flows and email

| # | Requirement | Expected | Actual | Evidence | Test | Result | Gap | Fix | Status |
|---|---|---|---|---|---|---|---|---|---|
| 4.1 | Flow 1 confirmation email: content, no duplicates | After-save create flow + email | Send Email action, HTML body with number, room, type, dates, amount; status Sent/Failed; create-only + blank-status entry | E4; E10 `confirmationFlowEmailsGuestOnce`; E11 #01 (status = Sent) | Flow executed in test and live (rolled back) | Flow runs, records Sent, no resend on edit | **No real email has ever been delivered**: all 19 org bookings are Suppressed, live check was rolled back, tests never send email | Create a guest with your own email, book a room, confirm the email arrives, screenshot it | NOT VERIFIED (delivery) |
| 4.2 | Flow 2 check-in → Occupied | After-save update flow | Implemented with prior-value entry and fault path | E4; E10; E11 #14 | Live check-in | Reserved → Occupied | — | — | PASS |
| 4.3 | Flow 3 check-out → Cleaning, history kept | After-save flow | Implemented; history lock rule | E4; E10; E11 #16 | Live check-out | Occupied → Cleaning; reservation unchanged | — | — | PASS |
| 4.4 | Flow 4 room Available only when eligible | Guard | Before-save: blocks if guest in house; Reserved if arrival today | E4; E11 #15, #16 | Live | Blocked / allowed correctly | — | — | PASS |
| 4.5 | Flow 5 cancellation: notify manager, free dates, recalc room | Email alert + recalculation | Email alert to Hotel Manager role (deployed, template active) + invocable Apex | E4; WorkflowAlert/EmailTemplate queries; E11 #11, #17 | Live cancel | Room Reserved → Available; dates rebookable | Manager email **delivery not observed** | Cancel a test booking; check the manager user's (admin's) inbox | NOT VERIFIED (email) |
| 4.6 | Flow 6 inactive staff blocked | Guard on assignment | Before-save flow on Room.Assigned_Housekeeper__c | E4; E11 #18; sample-data log | Live | "Ramesh Pillai is inactive…" | — | — | PASS |
| 4.7 | Fault paths handle failures safely | Fault connectors | Email faults recorded / skipped; room-update faults roll back via Custom Error | Flow XML | Not executable on demand (needs a forced failure) | — | Fault paths not exercised | Optional: temporarily add a blocking validation rule on Room and check in a guest | NOT VERIFIED |
| 4.8 | No Flow/Apex conflict on the same field | Single owner per event | Apex: room/date changes; Flows: status changes; shared rules via invocable Apex | Handler code; E10; E11 #14–#17 | Full stay replayed | Each step produced exactly one expected status, no errors | — | — | PASS |

## 5. Apex

| # | Requirement | Expected | Actual | Evidence | Test | Result | Gap | Fix | Status |
|---|---|---|---|---|---|---|---|---|---|
| 5.1 | Trigger + handler, logic not in trigger | One-line trigger, handler class | `ReservationTrigger` → `ReservationTriggerHandler` → 3 services | E5 | Coverage 100% trigger/handler | Pass | — | — | PASS |
| 5.2 | Overlap rule (strict <, >, not cancelled, not self) | Apex in before trigger | `ReservationBookingService` | E10 (5 overlap shapes); E11 #02, #09, #10 | Live + tests | Overlaps rejected; same-day turnover allowed | — | — | PASS |
| 5.3 | Insert, update, room change, date change, cancelled ignored | All paths | Implemented | E10; E11 #10, #11 | Tests + live | Pass | — | — | PASS |
| 5.4 | Bulk-safe, no SOQL/DML in loops | Set-based | 1 lock + 1 overlap query per batch | E10 (200 records ≤ 10 SOQL); E11 #19 (100 records, 3 SOQL, in-batch conflict rejected) | Live + tests | Pass | — | — | PASS |
| 5.5 | Concurrency safeguard | Locking where feasible, honest limits | `FOR UPDATE` on rooms; limits documented | Code; Docs §13 | Cannot be simulated in one transaction | — | Behaviour under two simultaneous users not observed | Optional manual test: two browsers, save the same booking at the same time | NOT VERIFIED |
| 5.6 | Room status consistency | Recalculate, never free a needed room | `RoomStatusService` + nightly job (scheduled, WAITING) | E10 (15 tests); E11 #14–#17; CronTrigger query | Live + tests | Pass | — | — | PASS |
| 5.7 | Clear error messages, no swallowed exceptions | addError with text | Messages name room, dates, reservation | E11 outputs | Live | Messages clear | — | — | PASS |
| 5.8 | No sensitive data in debug logs | Avoid PII in logs | Load/verify scripts print numbers and statuses only; **`soql-demo.apex` prints guest names and e-mail addresses** | Script source; E14 | Inspection | PII (fictional) printed | Fixed 18/10/2026: debug line no longer prints e-mail; re-run shows names only | — | PASS |
| 5.9 | No hard-coded record IDs | Query by name/developer name | None found | Source inspection | — | — | — | — | PASS |

## 6. SOQL

| # | Requirement | Expected | Actual | Evidence | Test | Result | Gap | Fix | Status |
|---|---|---|---|---|---|---|---|---|---|
| 6.1 | Q1 reservations of a room | Query + explanation | `getReservationsForRoom` | E14; E10 | `query1…` | 4 rows for RM-0001 | — | — | PASS |
| 6.2 | Q2 reservations of a guest | | `getReservationsForGuest` | E14; E10 | `query2…` | 2 rows | — | — | PASS |
| 6.3 | Q3 active reservations of a room | | `getActiveReservationsForRoom` | E14; E10 | `query3…` | 2 rows, cancelled excluded | — | — | PASS |
| 6.4 | Q4 date range | | `getReservationsInDateRange` | E14; E10 | `query4…` | 9 rows; invalid range rejected | — | — | PASS |
| 6.5 | Parent-to-child | Room with Reservations__r | `getRoomWithReservations`, `getGuestWithReservations` | E14; E10 | `query5…`, `query7…` | Pass | — | — | PASS |
| 6.6 | Child-to-parent | Room__r / Guest__r fields | `getReservationsWithRoomAndGuest` | E14; E10 | `query6…` | Pass | — | — | PASS |

## 7. Security

| # | Requirement | Expected | Actual | Evidence | Test | Result | Gap | Fix | Status |
|---|---|---|---|---|---|---|---|---|---|
| 7.1 | 6 users | CEO, Manager, 2 Receptionists, Housekeeping, Accounts | All 6 active; admin is CEO | E8 | Query | Present | — | — | PASS |
| 7.2 | Role hierarchy | CEO → Manager → departments | Exactly this | E8 | Query | Parent roles correct | — | — | PASS |
| 7.3 | Profiles and permission sets | Least privilege | 1 staff profile + 5 role permission sets | E8 | Query | Matches design | — | — | PASS |
| 7.4 | Receptionist CRE, no delete | | Reservation C/R/E, Delete false | E8; `receptionistCreatesAndEditsButCannotDeleteReservations` | runAs, user-mode delete | Delete refused | — | — | PASS |
| 7.5 | Manager view all | | View All + Modify All | E8; `managerSeesAndManagesEverything` | runAs | Pass | — | — | PASS |
| 7.6 | Housekeeping: room status only, no guest/reservation data | | Room R/E, FLS edit on status only; no Guest/Reservation | E8; `housekeepingUpdatesRoomStatusOnly` | runAs | Pass | — | — | PASS |
| 7.7 | Accounts: amounts yes, room status no | | Read-only; Room_Status read-only; ID fields hidden | E8; `accountsReadsAmountsButNotIdentityOrRoomStatus` | runAs + stripInaccessible | Pass | — | — | PASS |
| 7.8 | OWD + sharing rules | Record-level access | Room/Staff Read; Guest/Reservation Private; 5 owner rules | E2; E9; `receptionistsShareReservationsThroughSharingRule` | runAs + UserRecordAccess | Receptionist 2 can edit Receptionist 1's booking | — | — | PASS |
| 7.9 | Guest ID protected | FLS | ID Number readable only by Receptionist, Manager, Admin | E8 FLS rows | runAs | Pass | Not encrypted (documented limitation) | — | PASS |
| 7.10 | Permissions tested with suitable users | Real users | Apex runAs with real profile/role/permission sets | E10 | 6 tests | Pass | Not checked by logging in as the demo users | Enable "Administrators Can Log in as Any User", log in as Accounts, screenshot a guest record without ID fields | NOT VERIFIED (interactive) |
| 7.11 | Licensing restrictions documented | | Platform licenses used; CRM Content license disabled; documented | Docs §15; E8 (license column) | — | — | — | — | PASS |

## 8. Reports and dashboards

| # | Requirement | Expected | Actual | Evidence | Test | Result | Gap | Fix | Status |
|---|---|---|---|---|---|---|---|---|---|
| 8.1 | Report 1 current month | | Summary by status, This Month | E12 | REST run | 16 rows, ₹1,75,900 | — | — | PASS |
| 8.2 | Report 2 cancelled | | Tabular filter Cancelled | E12 | REST run | 2 rows | — | — | PASS |
| 8.3 | Report 3 room-wise history | | Rooms with Reservations, by room | E12 | REST run | 12 groups, ₹2,27,800 | — | — | PASS |
| 8.4 | Report 4 guest-wise history | | Guests with Reservations, by guest | E12 | REST run | 12 groups, ₹2,27,800 | — | — | PASS |
| 8.5 | Report 5 monthly revenue | | By check-in month, excl. cancelled, chart | E12 | REST run | Sep 34,500 / Oct 1,63,300 / Nov 17,400 | — | — | PASS |
| 8.6 | Dashboard 1 today's check-ins/outs | | 3 metrics + 2 charts | E13 | REST refresh + read | 2 in, 2 out, 3 in house | — | — | PASS |
| 8.7 | Dashboard 2 rooms by status (5 statuses) | | Donut + column | E13 | REST refresh + read | 5/2/3/1/1 | — | — | PASS |
| 8.8 | Dashboard 3 reservations by room type | | Bar + revenue column | E13 | REST refresh + read | Double 6, Single 5, Deluxe 4, Suite 2 | Charts not seen visually | Screenshot after Refresh | PASS |
| 8.9 | Refresh and interpretation explained | | Docs §16 | Docs | — | — | Note: before this audit the dashboards had never been refreshed (NO_DATA); an earlier claim that they refreshed was wrong | Click Refresh before demo | PASS |

## 9. Sample data

| # | Requirement | Expected | Actual | Evidence | Test | Result | Gap | Fix | Status |
|---|---|---|---|---|---|---|---|---|---|
| 9.1 | ≥10 rooms, ≥10 guests, ≥15 reservations, ≥5 staff | | 12 / 12 / 19 / 6 | Queries; E12 | Count | Met | — | — | PASS |
| 9.2 | All scenarios (booking, non-overlap, overlap rejection, cancel, check-in/out, maintenance, capacity, invalid dates) | | All present; rejections printed by load script | Load log; E11 | Live | All present | — | — | PASS |
| 9.3 | Fictional, consistent data | | `@example.com`, `DEMO-` IDs; statuses consistent with reservations | E12 room status report | — | Consistent | — | — | PASS |

## 10. Testing, deployment, documentation, source control

| # | Requirement | Expected | Actual | Evidence | Test | Result | Gap | Fix | Status |
|---|---|---|---|---|---|---|---|---|---|
| 10.1 | 12 required Apex test cases | Meaningful assertions | All 12 mapped (Docs §18) | E10 | Full run | 76/76 pass | — | — | PASS |
| 10.2 | Flows, VRs, email actions, security tested | | Covered | E10 | Full run | Pass | Email delivery cannot be tested in Apex (see 4.1) | — | PASS |
| 10.3 | No SeeAllData, own test data | | Data factory, no SeeAllData | Source | — | — | — | — | PASS |
| 10.4 | Deployment readiness | Deploys cleanly with tests | Check-only deploy succeeded (155/155, 76/76) **after** unscheduling the nightly job; with the job scheduled, validation fails ("schedulable class has jobs pending") | E15 + failed validation `0Afg800000HpRUDCA3` | Validate twice | Fresh org: deployable. This org: needs the documented abort → deploy → reschedule step | Redeploy needs a manual step | Either keep the documented procedure, or enable Setup → Deployment Settings → "Allow deployments of components when corresponding Apex jobs are pending or in progress" | PASS (with documented step) |
| 10.5 | Documentation accurate | Uses actual results | 23 sections present, but states **"81 tests"**: the run executed **76 test methods** (the CLI count of 81 includes 5 `@TestSetup` methods) | Test JSON | Compared | Fixed 18/10/2026: documentation corrected to 76 and live verification added (the first Git commit message still says 81; corrected in the follow-up commit) | — | PASS |
| 10.6 | Screenshots of the working application | Real screenshots | None in the repository | Repo contents | — | — | Missing | Capture the 10 screenshots listed in Docs §19 and add to `docs/screenshots/` | **FAIL** |
| 10.7 | Source control | Git repository | Public GitHub repo, 1 commit | E17 | Repo view | Present | Brief section 16 text not available (truncated) | Provide section 16 to check its exact requirements | NOT VERIFIED |
| 10.8 | Record types only if needed | Justify | Not used; justified in Docs §4 | Docs | — | — | — | — | PASS |

---

## Prioritised remaining tasks

| Priority | Task | Requirement | Who |
|---|---|---|---|
| 1 | Capture the 10 screenshots (Docs §19) and add them to the repo and documentation | 10.6 | You (or me via Claude in Chrome) |
| ~~1~~ | ~~Correct the test count to 76; add this audit and the live verification results~~ — done 18/10/2026 | 10.5 | Me |
| 1 | Provide the missing brief section 16 (and anything after it) | 10.7 | You |
| 2 | Prove real email delivery: create a guest with your own email, book (Flow 1), then cancel (Flow 5, manager alert to the admin's inbox); screenshot both emails. Check Setup → Deliverability = All email first | 4.1, 4.5 | You, with my steps |
| 2 | Reload the app and confirm the SmartStay logo now shows in the header (deployed 18/10/2026) | 1.3 | You (look) |
| ~~3~~ | ~~Stop printing guest e-mail addresses in `soql-demo.apex`~~ — done 18/10/2026 | 5.8 | Me |
| 3 | Log in as the Accounts and Housekeeping demo users and screenshot what they cannot see | 7.10 | You (requires Login Access Policies setting) |
| 4 | Decide on redeploy handling with the scheduled job (keep documented procedure or enable the Deployment Setting) | 10.4 | You decide |
| 4 | Optional: manual two-browser concurrency test; forced fault-path test | 5.5, 4.7 | Optional |
