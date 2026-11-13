# TABLE 3 UPDATE: violations list, challenges, sources

Paste-ready section for the thesis. The PDF itself cannot be edited from here, so this is a draft to copy in.
Source of the old table: `FINAL-PROPOSAL.pdf`, Table 3, printed pages 39-43 (PDF 48-52).
Law text marked "read" was read on lawphil.net. Full source notes: `VIOLATIONS_AND_SOURCES.md`.

---

## A. WHAT TO UPDATE IN THE VIOLATIONS LIST

1. Vehicle scope. Printed p. 5, line 239: "Two vehicle types are covered, specifically motorcycles and cars."
   Change to: vehicles common in Zamboanga City (motorcycle, car, tricycle, jeepney, bus, truck, pickup, kuliglig).
2. Mandatory violations grow from 13 to 20 (see section B).
   Added: kuliglig passenger, pickup bed passengers, riding outside the vehicle, illegal U-turn, crossing solid line, restricted lane, overtaking on the right.
3. Some violations apply to one vehicle type only:
   - motorcycle only: no helmet, missing side mirror, overloading
   - car only: no seatbelt
   - kuliglig only: kuliglig passenger
   - all other violations: all vehicles
4. Table 3 gets a new column: "Applies to". Table 3 no longer has separate motorcycle and car rows for shared violations.
5. Fix the wrong law sections (see `REVISION_LOG.md`, R7).
6. Disregarding traffic signs = stop sign only (R1-R3).
7. Data sources: barangay CCTV, then public datasets and own recordings (R11-R16).
8. Optional (built, not promised): blocking intersection, sidewalk driving, illegal loading, truck ban, tricycle on highway, double parking, distracted driving.

---

## B. NEW TABLE 3 (20 mandatory violations)

| # | Violation | Applies to | Legal basis | How the system detects it | Challenge | Mitigation |
|---|---|---|---|---|---|---|
| 1 | Counterflow | all | RA 4136 §37 (read) | Track moves against the legal direction for 2 s or more | Vehicle hidden by another vehicle; two-way roads | Sustained-time rule; admin sets the legal direction |
| 2 | Illegal parking | all | RA 4136 §46 (read) | Track stands in the no-parking zone longer than the time limit | A queued car looks parked; shaking camera hides a parked car | Traffic-flow guard; stopped = under 25 px/s |
| 3 | Illegal turn | all | RA 4136 §45 (read); banned turns by sign | Heading swings 45° or more into the forbidden direction | Turn must be visible for 2 s or more | Elevated view; admin draws the forbidden arrow |
| 4 | Disregarding signs (stop sign) | all | JAO 2014-01 (not opened) | Crosses the stop line without a full stop | Creeping vehicles; large vehicles roll past the line | Track the vehicle center; count a stop below a speed threshold |
| 5 | No plate | all | RA 4136 §18 (read); motorcycles: RA 11235 §5 as amended by RA 12209 (read); LTO AO AHS-2008-015 §III (read, copy) | Plate model finds no plate; decided when the vehicle leaves the picture | Plate model trained on foreign plates; small or dirty plates | Vehicle at least 60 px wide; a plate found at any fair look cancels the case |
| 6 | No helmet | motorcycle | RA 10054 §3 (read); LTO AO AHS-2008-015 §VII, §XI(a) (read, copy) | Helmet model reads the rider; vote over recent looks | Model fires on few rear and top-down crops | Front or rear view only; vote of 60% of last 10 looks |
| 7 | Missing side mirror | motorcycle | LTO AO AHS-2008-015 §VIII (read, copy) | Cabin model counts mirrors; fewer than 2 is a bad look | Mirrors are small; arms hide them; one is hidden from the side | Front or rear view only; 80% of at least 5 looks |
| 8 | Overloading | motorcycle | RA 4136 §32 (read); LTO AO AHS-2008-015 §VI (read, copy) | More than 2 riders in most looks | Riders overlap and hide the count | Vote over 10 looks; person boxes over the motorcycle |
| 9 | No seatbelt | car | RA 8750 §4 (read) | Cabin model finds no belt on the driver | Tinted windows; glare | Tinted windshield skipped on purpose; daylight only |
| 10 | Kuliglig passenger | kuliglig | None found (see section C) | Person box inside the kuliglig box | No kuliglig class in the detector | Train a kuliglig class from own clips |
| 11 | Pickup bed passengers | pickup, truck | RA 4136 §32(b), §51 (read) | People inside a moving pickup or truck bed | Pickups detected as "truck"; bed hidden from some views | Side or rear view at moderate height |
| 12 | Riding outside the vehicle | all except motorcycle | RA 4136 §32(b), (c), §51 (read) | People on the roof or hanging off a moving vehicle | A person on the rear step is hidden from straight behind | Side or rear view; ignore people boarding a stopped vehicle |
| 13 | Signal light | all | RA 4136 §44 (read) | Turn of 45° or more without a blinking indicator | Blinkers are tiny; hand signals are lawful | Experimental; close front or rear view only |
| 14 | Red light | all | JAO 2014-01 (not opened) | Crosses the stop line while the light is red | Vehicle already inside the junction on red | Judged at the moment of crossing; unknown light never gives a ticket |
| 15 | Swerving | all | RA 4136 §48 (read) | Left-right-left weave within 6 s | "Reckless" has no number; tracker jitter | Thresholds are ours; vehicle visible 6 s or more |
| 16 | Pedestrian lane | all | RA 4136 §46(b) (read) | Track stands still on the crosswalk for more than 3 s | A red-light queue looks the same | Admin draws the crosswalk; signal state helps |
| 17 | Illegal U-turn | all | No U-turn rule in RA 4136 (read); by sign (JAO 2014-01) | Heading turns back 150° or more and moves sideways | Reversing and wide turns look similar | Elevated view; sideways-move check |
| 18 | Crossing solid line | all | RA 4136 §41(a) (read) | Track ends clearly past the drawn line | "Clearly past" is our threshold | Admin draws the line; wobble on own side ignored |
| 19 | Restricted lane | all | None found (see section C) | A banned vehicle type is inside the lane zone | Class errors (pickup as car; jeepney as bus) | Admin ticks the allowed classes |
| 20 | Overtaking on the right | all | RA 4136 §39 (read) | Vehicle A passes B and ends on B's right | Legal on multi-lane one-way roads and beside a left-turning vehicle | Use only on single-lane roads; draw the zone |

Two violations in this table are not built yet: #10 and #20.

---

## C. SOURCES: HOW STRONG, AND WHAT TO SAY IF ASKED

Strong (law text read):
- #1 counterflow, #2 illegal parking, #3 illegal turn, #5 no plate, #8 overloading, #11 pickup, #12 riding outside, #13 signal light, #15 swerving, #16 pedestrian lane, #18 solid line, #20 overtaking on the right.
- Say: "The rule comes from the section named in the table."

Medium (read, but not from the official site):
- #6 no helmet, #7 missing side mirror, and the plate and overloading parts of #5 and #8 use LTO Administrative Order AHS-2008-015 (15 May 2008).
- Read on a legal-text copy: https://dev.lawyerly.ph/laws/55941. Not read on lto.gov.ph.
- What it says: side mirror is a standard accessory (§VIII); one back rider with a seat and footrest (§VI); riders must wear standard helmets (§VII); plates visible and legible (§III).
- Weak point: the order does not say "two mirrors." Our rule counts fewer than 2. Say: "The order requires side mirrors. Two is our reading for one on each side."

Medium (not opened):
- #4 disregarding signs and #14 red light rely on JAO 2014-01. The LTO site blocked the request. Secondary sources list "disregarding traffic signs" under it.
- Links: https://lto.gov.ph/wp-content/uploads/2024/06/JAO-2014-01.pdf and https://www.scribd.com/document/507959581/JAO-2014-01
- To do: open the PDF in a browser and add the item numbers.
- RA 4136 has no rule to obey traffic signals or the stop sign. Do not cite §42(a).

No national source found:
- #10 kuliglig passenger. No national rule names the kuliglig. Nearest laws: RA 4136 §32(b) (passengers on top) and §51 (riding outside or at the rear). Cities regulate kuliglig by permit and ordinance.
- #19 restricted lane. Local ordinance only.
- #17 illegal U-turn. Charged by sign or marking, not by its own section.
- Say: "No national law names this. We apply the nearest law and the local ordinance. This study tests detection, not the legal case."

Not verified at all: MMDA Regulation No. 96-009, Local Ordinance SP-1160, the Zamboanga ordinances, and the 2019 LTO memo on pickup passengers.

---
