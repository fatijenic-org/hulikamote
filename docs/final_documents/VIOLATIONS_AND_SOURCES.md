# Violations, legal sources and difficulty (updated 2026-11-09)

37 violations: the 25 built in `hulikamote_backend/engine/violations/` plus 12 proposed ones (marked NEW). Grouped by how they would be implemented.
Added 2026-11-09: `overtaking_on_right` and `kuliglig_with_passengers` (both proposed, not built; folders for test clips exist under `evaluation-testing-videos/`).

**Grade** = how hard it is to build AND make reliable on Zamboanga-style CCTV: 1 easy, 2 moderate, 3 hard, 4 very hard, 5 close to unrealistic with today's data.

**How the sources were checked**
- **Read** = I downloaded and read the actual law text on lawphil.net (Arellano Law Foundation). Section numbers below are from that text.
- **Not opened** = the link came from a search result; the site blocked me (HTTP 403) or I could not confirm the content. All lto.gov.ph pages and the Manila Bulletin page were blocked. Open them yourself before quoting.
- Fine amounts are left out on purpose: none was confirmed from a primary source.
- Added 2026-11-09: RA 4136 §39 to §41 were re-read on lawphil.net for `overtaking_on_right` (note: the title "Overtaking a vehicle" is §39; §40 is "Driver to give way to overtaking vehicle"; §41 is the restrictions). A search for a national kuliglig rule found nothing current; only local permits and older news (2010), so that row has no confirmed legal basis.

## 1. Stopped inside a drawn zone

| Violation | Basis | Grade | Why |
|---|---|---|---|
| illegal_parking | [RA 4136 §46](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (a to h) | 2 | Rule is simple (stopped in zone longer than the limit). Telling a parked car from a queued one needs the traffic-flow guard (built). |
| pedestrian_lane | [RA 4136 §46(b)](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (on a crosswalk) | 2 | Same rule with a 3 s limit. A red-light queue looks the same, so the signal state matters. |
| blocking_intersection | [RA 4136 §54](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (obstruction), §46(a) (within an intersection) | 3 | Waiting before the box is legal, so only "stopped inside" counts. The box is drawn by hand. |
| illegal_loading | [RA 4136 §54](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (loading or unloading that obstructs traffic) | 3 | Video cannot tell loading from plain stopping; only a vehicle-class filter. |
| double_parking | [RA 4136 §46(g)](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (roadside of a vehicle already parked) | 4 | Experimental. Needs a stopped neighbour that was there first and traffic flowing past. |

## 2. Direction and path shape

| Violation | Basis | Grade | Why |
|---|---|---|---|
| counterflow | [RA 4136 §37](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (pass to the right when meeting vehicles) | 2 | Heading against the flow. The learned flow handles one-way roads; two-way roads are never judged. |
| illegal_turn | [RA 4136 §45](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (lane to turn from) | 3 | The law only says which lane to turn from. Banned turns come from signs, which are drawn by hand. |
| illegal_u_turn | No U-turn provision in RA 4136 (read). Only by sign, or under §48 or §54. | 3 | Nothing exact to test against; reversing and wide turns look similar. |
| swerving | [RA 4136 §48](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (reckless driving) | 3 | "Reckless" has no number, so the thresholds are ours. Tracker jitter can fake a swerve. |
| illegal_overtaking (NEW) | [RA 4136 §41](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (a to d: centre line, crest or curve, railway or intersection, road works) | 3 | Needs "A passes B" (order change in a lane) plus a centre-line crossing or a drawn no-passing zone. Reuses path logic; no test footage. |
| overtaking_on_right (NEW, added 2026-11-09) | [RA 4136 §39](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (read: the overtaking driver passes at a safe distance to the left). The law allows passing on the right on a highway in a business or residential district with two or more lanes in one direction, and when the other vehicle is making or about to make a left turn; §41(b), (c) repeat these exceptions. | 3 | Needs "A passes B" with the side: A ends up on B's right. Legal only on multi-lane one-way sections and beside a left-turning vehicle, so the rule must be drawn only on single-lane-per-direction roads. A lane change by a slower vehicle can look the same. No test footage; film it (`evaluation-testing-videos/overtaking_on_right`). |

## 3. Crossing a line or entering a banned zone

| Violation | Basis | Grade | Why |
|---|---|---|---|
| red_light | [JAO 2014-01](https://lto.gov.ph/wp-content/uploads/2024/06/JAO-2014-01.pdf) (LTO-hosted, not opened). RA 4136 has no general signal-obedience section (read). | 3 | Needs the signal state (light box or timer) and a stop line. |
| disregarding_signs | [JAO 2014-01](https://lto.gov.ph/wp-content/uploads/2024/06/JAO-2014-01.pdf) (not opened) | 4 | Built as hand-drawn zones per sign. Reading real signs would need a sign detector. |
| crossing_solid_line | [RA 4136 §41(a)](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (centre line when overtaking) | 3 | The line is drawn by hand; "clearly past the line" is a threshold of ours. |
| restricted_lane | No national source found; local ordinance, to confirm | 2 | Easy rule (class not allowed in the lane). The open part is the legal basis. |
| truck_ban | No source found; local ordinance, to confirm | 3 | Pickups usually come out as "truck". |
| tricycle_on_highway | DILG MC 2020-036, 17 Feb 2020 ([news](https://mb.com.ph/2020/02/19/dilg-to-strictly-enforce-ban-on-tricycles-plying-highways-major-roads/), circular text not opened); [DILG MC 2023-195](https://batasnatin.com/laws/mc-2023-195) (copy on a legal-text site, not the DILG page); [news](https://philstar.com/cebu-news/2023/12/10/2317820/lgus-told-ban-tricycles-national-highways); Zamboanga City's own position in 2020 ([news](https://www.sunstar.com.ph/article/1847679/Zamboanga/Local-News/Zamboanga-City-Government-to-allow-trikes-on-national-highways), not opened) | 4 | The stock detector has no tricycle class; the 6-class model is trained but not active. The ban is on national highways, but each LGU lists its national highways and the portions tricycles may use where there is no alternative route (Tricycle Route Plan), and may allow them by ordinance; Zamboanga City said in 2020 it could allow them. The video cannot tell a national highway from another road, so the operator states for each camera that the ban applies there (no zone drawn = the whole view; a zone limits it). The DPWH national road list (route numbers N1-N99 primary, N100-N999 secondary; tertiary roads have no number) and the city's current route plan decide it. Confirm with the City Council or DILG Region IX. |
| sidewalk_driving | [RA 4136 §52](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (drive or park on a sidewalk) | 3 | The sidewalk zone is drawn; pedestrians share the zone. |
| failure_to_yield_pedestrian (NEW) | [RA 4136 §42(c)](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (yield to a pedestrian in a crosswalk) | 3 | Needs person tracks, a crosswalk zone, and a car that does not slow down. The law excludes junctions run by a signal or enforcer. |

## 4. People on or in the vehicle (frame checks)

| Violation | Basis | Grade | Why |
|---|---|---|---|
| overloading | [RA 4136 §32](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (registered capacity); motorcycle back-rider rule: [LTO AO AHS-2008-015](https://dev.lawyerly.ph/laws/55941) (copy on a legal-text site, not read) | 3 | Counts person boxes; riders overlap and blur. |
| pickup_passengers | [RA 4136 §32(b)](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (passengers on top or cover), §51 (hanging on or riding the outside or rear). The 2019 LTO memo was not found. | 4 | Pickups are detected as "truck"; people in the bed are hidden behind the sides. |
| riding_outside_vehicle | [RA 4136 §32(b), (c)](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (top, running board), §51 | 4 | Roof riders versus people hanging on; someone on a rear step is hidden from behind. |
| kuliglig_with_passengers (NEW, added 2026-11-09) | No national rule found that names the kuliglig (an open-cab motor cart); regulated locally, ordinance to confirm. Related: [RA 4136 §32(b)](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (passengers on top or cover) and §51 (riding outside or at the rear) may apply, not confirmed for this vehicle. | 4 | Rule as stated by the team: an open kuliglig must carry no person (assumption: the driver is excepted; confirm). The rule is easy once the vehicle is found (a person box inside the kuliglig box), but no detector has a kuliglig class and no public footage exists: train the class from your own clips. Tricycle and truck labels will leak into it. |
| child_on_motorcycle (NEW) | [RA 10666 §4](https://lawphil.net/statutes/repacts/ra2015/ra_10666_2015.html) (child must reach the foot pegs, hold the rider's waist, wear a helmet) | 4 | Must tell a child from a small adult and see the feet. The law only applies on busy roads or where the limit is above 60 km/h. |

## 5. Specialist model on the vehicle crop

| Violation | Basis | Grade | Why |
|---|---|---|---|
| no_helmet | [RA 10054 §3](https://lawphil.net/statutes/repacts/ra2010/ra_10054_2010.html) (driver and back rider, standard helmet) | 4 | Rule is easy (vote). The model fires on only about 8% of rear or top-down CCTV crops, so it needs your own labelled data. |
| no_seatbelt | [RA 8750 §4](https://lawphil.net/statutes/repacts/ra1999/ra_8750_1999.html) (driver and front-seat passengers) | 4 | Needs a front view through clear glass. Tinted windows are skipped on purpose. |
| distracted_driving | [RA 10913 §4](https://lawphil.net/statutes/repacts/ra2016/ra_10913_2016.html) | 4 | Windshield glare; a phone is small. |
| missing_side_mirror | [LTO AO AHS-2008-015](https://dev.lawyerly.ph/laws/55941) (not read; mirror wording unconfirmed) | 5 | Mirrors are tiny and often hidden; no mirror training data yet. |
| phone_while_riding (NEW) | [RA 10913 §4](https://lawphil.net/statutes/repacts/ra2016/ra_10913_2016.html); its definition of "motor vehicle" includes motorcycles and tricycles (read) | 5 | A phone in a rider's hand at CCTV size, with gloves and a helmet. No model, no data. |

## 6. Plates and registration

| Violation | Basis | Grade | Why |
|---|---|---|---|
| no_plate | [RA 4136 §18](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (front and rear, always legible); motorcycles: [RA 11235 §5](https://lawphil.net/statutes/repacts/ra2019/ra_11235_2019.html) as amended by [RA 12209](https://lawphil.net/statutes/repacts/ra2025/ra_12209_2025.html) (rear plate, readable from 15 m) | 4 | The plate model is weak (old Vietnamese data); "no plate" cannot yet be told apart from "plate we failed to read". |
| unreadable_or_improvised_plate (NEW) | [RA 4136 §18](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html); [RA 12209](https://lawphil.net/statutes/repacts/ra2025/ra_12209_2025.html); [LTO notice on improvised plates](https://lto.gov.ph/news/lto-advises-motorists-vs-use-of-temporary-improvised-plates-warns-of-p5000-fine/) (not opened) | 3 | A plate box exists but the OCR confidence is low. The thesis already says the two cases need different records. |
| tricycle_rest_day (NEW) | Zamboanga Ordinance 185, Art. 6 Sec. 3 per [Manila Bulletin, 8 Aug 2025](https://mb.com.ph/2025/08/08/tricycle-rest-day-slated-in-zamboanga-city) (not opened; whether enforcement started is unverified) | 4 | The rule is trivial (last digit of the plate against the day), but it needs a tricycle detector and a readable plate, and both are weak. |

## 7. Lights and signals

| Violation | Basis | Grade | Why |
|---|---|---|---|
| signal_light | [RA 4136 §44](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (signal before starting, stopping or turning, by hand or device) | 5 | Blinkers are tiny at CCTV size, and hand signals are lawful. Experimental. |
| no_lights_at_night (NEW) | [RA 4136 §34(c), (d)](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (headlights, red tail light) | 3 | Needs night clips; detect a lit or unlit pair; camera exposure changes the picture. |
| high_beam_not_dimmed (NEW) | [RA 4136 §34(c)](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (dim when meeting another vehicle or on lit streets) | 4 | Glare saturates the image, auto-exposure fights it, and "meeting another vehicle" needs scene reasoning. |

## 8. Needs a measurement beyond boxes

| Violation | Basis | Grade | Why |
|---|---|---|---|
| overspeeding (NEW) | [RA 4136 §35(b)](https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html) (20, 30, 40, 50 or 80 km/h by road type and vehicle) | 3 | Needs pixel-to-metre calibration per camera and the limit per zone. The Visualizer already teaches the idea. |
| smoke_belching (NEW) | [RA 8749 §46](https://lawphil.net/statutes/repacts/ra1999/ra_8749_1999.html): visible smoke only makes a vehicle "suspected" and sends it to an emission test | 4 | Needs a smoke classifier. Video can raise suspicion only, never confirm a violation. |

## 9. Wrong citations found in the thesis (Table 3 of CH1-3-REVISED-new-2.pdf), checked against the lawphil text

| Thesis cites | What the law says | Use instead |
|---|---|---|
| Counterflow: RA 4136 Sec. 45(b) | §45 is turning at intersections | §37 |
| Illegal turn: RA 4136 Sec. 42(d) | §42(d) is a full stop before a through highway or railroad crossing | §45 |
| Disregarding traffic signs: RA 4136 Sec. 42(a) | §42(a) is right of way at intersections; RA 4136 has no signal-obedience rule | JAO 2014-01 and local codes |
| Illegal parking: RA 4136 Sec. 51 | §51 is hitching to a vehicle | §46 |
| Overloading: RA 4136 Sec. 54(f) | §54 is obstruction of traffic and has no (f) | §32 (and the AO for motorcycles) |
| Car no plate: "RA 8750" | RA 8750 is the Seat Belts Use Act | §18 |
| "R.A. 8750 analog for plates" (motorcycle no plate) | Same | RA 11235 as amended by RA 12209 |

Could not verify at all: MMDA Regulation No. 96-009, Local Ordinance No. SP-1160, Zamboanga Ordinances 248 and 185 (no official page found), and the LTO memo of September 2019 on pickup passengers.

The Progress Report's "JAO 2014-01" link points to LTO Memorandum Circular AVT-2014-1900, which only refers to the JAO and has no fine schedule. The JAO itself is the LTO-hosted PDF linked in section 3, which I could not open.

## 10. Other links

- [LTO LETAS page (fines by offense)](https://lto.gov.ph/httpswww.lto.gov.ph/law-enforcement-and-adjudication-of-cases/536-new-letas.html): LTO-hosted, not opened.
- [RA 11229 Child Safety in Motor Vehicles Act](https://lawphil.net/statutes/repacts/ra2019/ra_11229_2019.html): read; §5 bars children 12 and under from the front seat unless they meet the height rule and use the seat belt. Possible later addition (child in the front seat); not in the 10 above.
- [RA 10586 Anti-Drunk and Drugged Driving Act](https://lawphil.net/statutes/repacts/ra2013/ra_10586_2013.html): not camera-detectable, listed only so it is not forgotten.
