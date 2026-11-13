# KNOWN SCOPE AND LIMITATIONS FOR THIS STUDY:

## SCOPES

### CAMERA SETUPS DEFINED AND ACCEPTED
1. angle of camera:
- fixed camera (no pan, no zoom, no hand-held)
- mounted 3 to 8 m above the road
- looks down 15° to 45° (not straight down)
- vehicles move toward or away from the camera
2. lighting environment:
- daylight
- no strong backlight or glare
- no heavy rain, no dirty lens
3. video quality:
- 720p or higher
- 15 fps or higher (25-30 fps is better)
- vehicle at least 120 px wide (plate check: at least 60 px)
- each vehicle visible at least 3 s (swerving: 6 s)

### DATA SOURCES
1. Barangay CCTV footage (Baliwasan first, then other barangays)
2. If barangay footage is low quality or outside the camera limits above:
- public datasets (COCO, Kaggle, Roboflow Universe, and others with open licences)
- footage the researchers record themselves
- both are used for training and for evaluating the violation detection pipeline
3. Not used: GTA V, CARLA, MMDA (too slow to obtain)

### VIOLATIONS (top 20 first, grouped by category)

TOP 20

| Violation | Source |
|---|---|
| **Stopped in a zone** | |
| 1. illegal_parking | RA 4136 Sec 46 (a to h) |
| 2. pedestrian_lane | RA 4136 Sec 46(b) (stopping on a crosswalk) |
| 3. blocking_intersection | RA 4136 Sec 54 (obstruction of traffic), Sec 46(a) (stopping within an intersection); local anti-obstruction rules to confirm |
| 4. illegal_loading | RA 4136 Sec 54 (loading or unloading that obstructs traffic); local loading rules for Zamboanga City to confirm |
| **Direction and path** | |
| 5. counterflow | RA 4136 Sec 37 (pass to the right when meeting vehicles) |
| 6. illegal_turn | RA 4136 Sec 45 (lane to turn from); banned turns come from signs |
| 7. illegal_u_turn | no U-turn rule in RA 4136; charged by sign, or under Sec 48 or Sec 54; to confirm |
| 8. swerving | RA 4136 Sec 48 (reckless driving) |
| 9. overtaking_on_right | RA 4136 Sec 39 (pass on the left; passing on the right only on a multi-lane one-way road in a business or residential district, or beside a left-turning vehicle), Sec 41(b) and (c) |
| **Line, lane and sign** | |
| 10. restricted_lane | no national source found; local ordinance, to confirm |
| 11. crossing_solid_line | RA 4136 Sec 41(a) (centre line when overtaking); to confirm |
| 12. disregarding_signs | LTO JAO 2014-01 (not opened) and local codes; RA 4136 has no general rule on obeying signals |
| 13. red_light | LTO JAO 2014-01 (not opened); RA 4136 has no general rule on obeying signals |
| **People on the vehicle** | |
| 14. overloading | RA 4136 Sec 32 (registered capacity); motorcycle back rider: LTO AO AHS-2008-015 (not read) |
| 15. kuliglig_with_passengers | no national rule found that names the kuliglig; local ordinance to confirm; related: RA 4136 Sec 32(b) and Sec 51 (not confirmed for this vehicle) |
| **Rider and driver gear** | |
| 16. no_helmet | RA 10054 Sec 3 (driver and back rider, standard helmet) |
| 17. missing_side_mirror | LTO AO AHS-2008-015 (not read; mirror wording not confirmed) |
| 18. no_seatbelt | RA 8750 Sec 4 (driver and front-seat passengers) |
| **Plate and lights** | |
| 19. no_plate | RA 4136 Sec 18; motorcycles: RA 11235 Sec 5 as amended by RA 12209 (rear plate) |
| 20. signal_light | RA 4136 Sec 44 (signal before starting, stopping or turning) |

OTHER VIOLATIONS (after the top 20)

| Violation | Source |
|---|---|
| **Stopped in a zone** | |
| 21. double_parking | RA 4136 Sec 46(g) (roadside of a vehicle already parked) |
| **Banned zone or road** | |
| 22. sidewalk_driving | RA 4136 Sec 52 (drive or park on a sidewalk) |
| 23. tricycle_on_highway | DILG MC 2020-036 and DILG MC 2023-195; each city's Tricycle Route Plan decides the allowed parts (Zamboanga City plan not confirmed) |
| 24. truck_ban | no source found; local ordinance, to confirm |
| **People on the vehicle** | |
| 25. pickup_passengers | RA 4136 Sec 32(b) (passengers on top or cover), Sec 51 (riding outside or at the rear); the 2019 LTO memo was not found |
| 26. riding_outside_vehicle | RA 4136 Sec 32(b) and (c) (top, running board), Sec 51 |
| **Rider and driver gear** | |
| 27. distracted_driving | RA 10913 Sec 4 |
| **Not built yet** | |
| 28. child_on_motorcycle | RA 10666 Sec 4 (child must reach the foot pegs, hold the rider's waist, wear a helmet) |
| 29. failure_to_yield_pedestrian | RA 4136 Sec 42(c) (yield to a pedestrian in a crosswalk) |
| 30. high_beam_not_dimmed | RA 4136 Sec 34(c) (dim the lights when meeting another vehicle or on lit streets) |
| 31. illegal_overtaking | RA 4136 Sec 41 (a to d: centre line, crest or curve, railway or intersection, road works) |
| 32. no_lights_at_night | RA 4136 Sec 34(c) and (d) (headlights, red tail light) |
| 33. overspeeding | RA 4136 Sec 35(b) (limit by road type and vehicle) |
| 34. phone_while_riding | RA 10913 Sec 4 (its meaning of motor vehicle includes motorcycles and tricycles) |
| 35. smoke_belching | RA 8749 Sec 46 (visible smoke only makes a vehicle suspected; an emission test follows) |
| 36. tricycle_rest_day | Zamboanga City Ordinance 185, Art 6 Sec 3, per Manila Bulletin 8 Aug 2025 (not opened; enforcement not verified) |
| 37. unreadable_or_improvised_plate | RA 4136 Sec 18; RA 12209; LTO notice on improvised plates (not opened) |

DESCRIPTIONS (the same violations, with what each one means in this system)

TOP 20

| Violation | Description |
|---|---|
| **Stopped in a zone** | |
| 1. illegal_parking | A vehicle stays still, longer than the time limit, where parking is banned. RA 4136 Sec 46 lists the places: (a) within an intersection, (b) on a crosswalk, (c) within 6 m of the corner (intersection of curb lines), (d) within 4 m of a fire station driveway, (e) within 4 m of a fire hydrant, (f) in front of a private driveway, (g) beside a vehicle parked at the curb (double parking), (h) where an official sign bans parking. Items c, d, e, f and h are marked as boxes on the picture; a, b and g are judged by blocking_intersection, pedestrian_lane and double_parking. |
| 2. pedestrian_lane | A vehicle stops on a crosswalk and blocks people crossing. |
| 3. blocking_intersection | A vehicle stops inside the junction box and blocks the cross traffic. |
| 4. illegal_loading | A bus, jeepney, tricycle or truck stops to load or unload where it is not allowed. |
| **Direction and path** | |
| 5. counterflow | A vehicle drives against the legal direction of its lane. |
| 6. illegal_turn | A vehicle turns where turning is prohibited. |
| 7. illegal_u_turn | A vehicle turns right round where a U-turn is prohibited. |
| 8. swerving | A vehicle weaves from side to side. |
| 9. overtaking_on_right | A vehicle passes another on the right where the law allows passing on the left only. |
| **Line, lane and sign** | |
| 10. restricted_lane | A vehicle type that is not allowed in a reserved lane, such as a car in a bus lane. |
| 11. crossing_solid_line | A vehicle drives over a solid line that must not be crossed. |
| 12. disregarding_signs | A vehicle breaks a traffic sign: no entry, no turn, no stopping, banned vehicle or stop sign. |
| 13. red_light | A vehicle crosses the stop line while the light is red. |
| **People on the vehicle** | |
| 14. overloading | More people ride a motorcycle than allowed. |
| 15. kuliglig_with_passengers | A kuliglig carries passengers where this is not allowed. |
| **Rider and driver gear** | |
| 16. no_helmet | A rider or back rider has no helmet. |
| 17. missing_side_mirror | A motorcycle is missing a mirror. |
| 18. no_seatbelt | A driver or front-seat passenger has no seatbelt. |
| **Plate and lights** | |
| 19. no_plate | A vehicle has no license plate at all. |
| 20. signal_light | A vehicle turns without a blinking indicator. |

OTHER VIOLATIONS (after the top 20)

| Violation | Description |
|---|---|
| **Stopped in a zone** | |
| 21. double_parking | A vehicle stands in the travel lane beside a parked vehicle while traffic passes. |
| **Banned zone or road** | |
| 22. sidewalk_driving | A moving vehicle is on the sidewalk or in a bike lane. |
| 23. tricycle_on_highway | A tricycle is on a highway where tricycles are not allowed. |
| 24. truck_ban | A truck is on a road or lane that is closed to trucks (at the banned hours). |
| **People on the vehicle** | |
| 25. pickup_passengers | People ride in the open back of a moving pickup or truck. |
| 26. riding_outside_vehicle | People ride on the roof of, or hang off, a moving bus, jeepney or truck. |
| **Rider and driver gear** | |
| 27. distracted_driving | A driver uses a phone. |
| **Not built yet** | |
| 28. child_on_motorcycle | A child rides a motorcycle in an unsafe way (cannot reach the foot pegs, no helmet). |
| 29. failure_to_yield_pedestrian | A vehicle does not give way to a person on a crosswalk. |
| 30. high_beam_not_dimmed | A driver keeps the high beam on when meeting another vehicle. |
| 31. illegal_overtaking | A vehicle overtakes where this is banned: on the centre line, a crest or curve, a railway crossing or an intersection, or road works. |
| 32. no_lights_at_night | A vehicle drives at night without headlights or a red tail light. |
| 33. overspeeding | A vehicle drives faster than the limit for that road and vehicle. |
| 34. phone_while_riding | A motorcycle or tricycle rider uses a phone. |
| 35. smoke_belching | A vehicle gives out visible smoke (only a suspicion; an emission test follows). |
| 36. tricycle_rest_day | A tricycle runs on its rest day (Zamboanga City). |
| 37. unreadable_or_improvised_plate | A plate is unreadable or home-made. |

SOURCES KEY

| Source | Link |
|---|---|
| RA 4136 (Land Transportation and Traffic Code) | https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html |
| RA 10054 (Motorcycle Helmet Act) | https://lawphil.net/statutes/repacts/ra2010/ra_10054_2010.html |
| RA 8750 (Seat Belts Use Act) | https://lawphil.net/statutes/repacts/ra1999/ra_8750_1999.html |
| RA 10913 (Anti-Distracted Driving Act) | https://lawphil.net/statutes/repacts/ra2016/ra_10913_2016.html |
| RA 11235 (Motorcycle Crime Prevention Act) | https://lawphil.net/statutes/repacts/ra2019/ra_11235_2019.html |
| RA 12209 (amends RA 11235) | https://lawphil.net/statutes/repacts/ra2025/ra_12209_2025.html |
| RA 10666 (Children's Safety on Motorcycles Act) | https://lawphil.net/statutes/repacts/ra2015/ra_10666_2015.html |
| RA 8749 (Philippine Clean Air Act) | https://lawphil.net/statutes/repacts/ra1999/ra_8749_1999.html |
| LTO JAO 2014-01 (not opened) | https://lto.gov.ph/wp-content/uploads/2024/06/JAO-2014-01.pdf |
| LTO AO AHS-2008-015 (copy on a legal-text site, not read) | https://dev.lawyerly.ph/laws/55941 |
| DILG MC 2023-195 (copy on a legal-text site) | https://batasnatin.com/laws/mc-2023-195 |
| LTO notice on improvised plates (not opened) | https://lto.gov.ph/news/lto-advises-motorists-vs-use-of-temporary-improvised-plates-warns-of-p5000-fine/ |
| Zamboanga City tricycle rest day, Manila Bulletin 8 Aug 2025 (not opened) | https://mb.com.ph/2025/08/08/tricycle-rest-day-slated-in-zamboanga-city |

Section numbers were read on lawphil.net unless marked not opened or not read. Fine amounts are left out: none was confirmed from a primary source.

## LIMITATIONS

### DATA
1. Barangay CCTV is often low quality and may not match the camera limits of this study
2. Public datasets and own recordings come from outside the barangay cameras
- results may not fully reflect traffic at the barangay cameras
3. No synthetic (game or simulator) footage is used

### CCTV SETUP
1. Camera Quality
- below 720p or 15 fps: not judged
- vehicle under 120 px wide: plate, helmet, seatbelt not judged
2. Lighting Conditions
- night, heavy rain, strong backlight: not judged
- seatbelt and phone: daylight only
3. Camera Angle
- moving camera or straight top-down view: not judged
- side view: one mirror always hidden

### VIOLATIONS:
1. Missing Sidemirror:
- front or rear view only
- mirror is small, rider's arms can hide it
2. No Seatbelt:
- front view through clear windshield only
- tinted windshield: skipped on purpose
3. Traffic Light
- Simulated only with overlay
4. Disregarding Signs
- Signs are simulated only with overlay
- Sign type in scope: stop sign (stop line, no full stop)
- Other signs: covered by their own violations (no entry = counterflow, no turn = illegal turn, no stopping = illegal parking, vehicle ban = truck ban)
- No sign recognition from the image
5. Motorcycles:
- Motorcycles can be detected when plate number is visible at the back at minimum of 15° angle and maximum of 45° angle
6. Zone rules (counterflow, parking, turns, lanes):
- admin draws the zone for each camera view (tricycle on highway: zone optional, see 9)
- two-way road: admin draws the legal direction
7. No Helmet and Overloading:
- heads and bodies of all riders visible
- riders that overlap can hide the count
8. Kuliglig Passenger:
- needs a kuliglig class in the detector
- driver is allowed (to confirm)
9. Tricycle on a National Highway:
- the system cannot tell if a road is a national highway, or if the city allows tricycles on part of it
- admin states it for each camera: no zone drawn = the whole view is a banned road; a drawn zone limits the rule to the banned part
- the ban comes from DILG MC 2020-036 and 2023-195; each city lists its national highways and the parts tricycles may use (Tricycle Route Plan, ordinance)
- Zamboanga City's current route plan is not confirmed: a wrong choice flags tricycles on a road where they are allowed
- needs a detector with a "tricycle" class (the stock model has none)

### PER VIOLATION (one line each)
10. Counterflow: two-way roads are not judged in auto mode; auto mode needs about 60 s of normal traffic first
11. Illegal Parking: "stopped" means speed under 25 px/s; a shaking camera can hide a parked car, and a stop at a red light inside the area looks the same (draw the area where no queue forms). Banned places (RA 4136 Sec 46):
- the banned places are set by the operator: a box placed on the picture for a no-parking sign, a fire hydrant (4 m), a fire station driveway (4 m), a corner (6 m) or a private driveway, or a drawn zone; nothing finds hydrants, driveways, corners or signs by itself
- the distances are NOT measured in meters: the box is sized by eye (4 m is about one car length), so the distance is only as exact as the box; perspective makes the same pixels mean different meters near and far
- items (a) within an intersection, (b) on a crosswalk and (g) double parking are judged by the rules Blocking Intersection, Pedestrian Lane and Double Parking; one stop can trigger two rules and give two tickets (no automatic merge yet)
- a vehicle with a blinking indicator or hazard light is not flagged while the lights blink; a driver who leaves hazards on is never flagged, and a far, tinted or hidden lamp is not seen
- automatic mode (nothing drawn) watches the whole picture and needs traffic that keeps driving past a stopped vehicle; where the road direction is not learned yet, it flags nothing
- not scored on real footage; the officer who reviews the ticket makes the final decision
12. Illegal Turn: whole turn visible for 2 s or more; admin sets the forbidden direction
13. Illegal U-turn: elevated view of the road section; legal wording to confirm
14. Red Light: light is simulated (item 3); unknown light never gives a ticket; admin draws the stop line
15. Pedestrian Lane: flags a stop of more than 3 s on the crosswalk; a red-light queue looks the same
16. Blocking Intersection: elevated view of the whole box; flags a stop of more than 5 s; legal basis to confirm
17. Crossing Solid Line: admin draws the line; legal basis to confirm
18. Restricted Lane: admin sets the allowed vehicle types; no national legal basis found (local ordinance)
19. Truck Ban: a pickup or van may be detected as a car; legal basis to confirm. Ban hours (see below):
- the ban hours are a setting the admin types from the city ordinance; the real Zamboanga hours are not confirmed (the wizard button "example hours" is only an example)
- the ban depends on the hour, so the system needs the time of the video. It takes it, in this order, from: the time typed by the admin, the clock printed in the picture (read with OCR, believed only when two readings agree with the time that passed), the video's own creation tag, the file name
- the system does NOT work out the hour from the picture. Brightness only says day, dusk or night, so it is never used as a time
- footage with no recorded time (no clock, no tag, no time in the name): the truck is still flagged, but the ticket says "Time not confirmed" and a person must check the time before confirming
- a wrong camera clock gives a wrong hour; the source of the time is shown on every ticket so the reviewer can see it
- a printed clock that is small, blurred or low contrast may not be read; the search then takes about 15 to 20 s and falls to the next source
- the clock reading was tested on real clips with a painted clock, not yet on a real Zamboanga camera
- live monitor: uses this computer's clock; the camera's own stream time is not read yet (future work)
20. Sidewalk Driving: needs a moving vehicle in the zone for 1.5 s or more; legal basis to confirm
21. Illegal Loading: a jeepney is detected as a bus; needs 5 or more looks to settle the vehicle type; local rule to confirm
22. Double Parking: experimental; needs moving traffic in the zone; not tested on real footage
23. Swerving: front or rear view; vehicle visible 6 s or more; a shaking track can fake a swerve
24. Signal Light: experimental; can over-flag (hand signals are lawful, motorcycles are exempt); needs a close front or rear view
25. Pickup Passengers: a straight top-down view cannot tell the bed from the cab; pickups are detected as "truck"
26. Riding Outside Vehicle: a person on the rear step is hidden when seen from straight behind
27. Distracted Driving: front view through a clear windshield, daylight only; tinted windshield skipped
28. No Plate: vehicle at least 60 px wide; plate side faces the camera; motorcycle rear plate only; a plate found at any fair look cancels the case
29. Overtaking on Right: not built; passing on the right is legal on a multi-lane one-way road and next to a left-turning vehicle (RA 4136 Sec 39), so it needs the lane layout; no test footage yet
30. Not built yet: child_on_motorcycle, failure_to_yield_pedestrian, high_beam_not_dimmed, illegal_overtaking, no_lights_at_night, overspeeding, phone_while_riding, smoke_belching, tricycle_rest_day, unreadable_or_improvised_plate; no rule, no model, no test footage


# DUMPS

motorcycle:
• counterflow
• illegal parking
• Illegal turn 
• Disregarding signs
• No plate number
• no helmet
• missing side mirror
• Overloading


Cars:
•counterflow
•illegal parking
•Illegal turn 
•Disregarding signs
•No plate number


EXTENDED
• Signal light violation
• red light running
• Swerving
• no seatbelt
• pedestrian lane obstruction