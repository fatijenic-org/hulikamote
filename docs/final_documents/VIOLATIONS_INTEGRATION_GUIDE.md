# HULI-KAMOTE: VIOLATIONS INTEGRATION GUIDE
Updated 2026-11-09. This guide covers all **25 violations built** in `hulikamote_backend/engine/violations/`, what each one flags, what the operator sets in the wizard, and its known limits. The text of Part A is generated from `tools/benchmark/violations.py` (a test keeps its keys in sync with the code), so it matches the running system. Legal basis and difficulty grades are in [VIOLATIONS_AND_SOURCES.md](VIOLATIONS_AND_SOURCES.md). The original September design notes for the first 13 violations are kept in Part C, with a list of what changed since.

---

## PART A: BUILT VIOLATIONS (25)

### Judged inside a drawn zone (17)

#### `counterflow`: Counterflow
- **Flags:** A vehicle drives against the legal direction for 2 s or more.
- **Does not flag:** Normal traffic on the same road; a vehicle crossing the road sideways.
- **Camera view:** Any fixed view where the road direction is clear.
- **Operator setup:** Zones mode: draw the zone and the legal-flow arrow. Auto mode (flow_mode auto): no drawing, but the clip needs about 60 s of normal traffic first, because the legal direction is learned from it.
- **Known limit:** Two-way roads are never judged in auto mode (both directions are normal there). Needs a fixed camera.

#### `illegal_parking`: Illegal parking
- **Flags:** A vehicle stands in the no-parking zone longer than the zone's time limit.
- **Does not flag:** A vehicle that stops in the zone for less than the limit; moving traffic.
- **Camera view:** Any fixed view where the zone and the whole vehicle are visible.
- **Operator setup:** Draw the zone. Set a short time limit (for example 10 s) so test clips stay short; the default is 180 s.
- **Known limit:** Judged on speed below 25 px/s, so a camera that shakes can hide a parked car.

#### `restricted_lane`: Restricted lane
- **Flags:** A vehicle type that is not allowed (for example a car in a motorcycle lane) is inside the lane zone.
- **Does not flag:** An allowed vehicle type in the same lane.
- **Camera view:** Any fixed view where the lane and the vehicle type are clear.
- **Operator setup:** Draw the lane zone and tick the allowed vehicle classes.
- **Known limit:** Not in the thesis list; kept as an extra.

#### `pedestrian_lane`: Pedestrian lane obstruction
- **Flags:** A vehicle stands still on the crosswalk for more than 3 s.
- **Does not flag:** A vehicle that drives across the crosswalk without stopping.
- **Camera view:** Any fixed view where the crosswalk and the whole vehicle are visible.
- **Operator setup:** Draw the crosswalk zone.

#### `illegal_turn`: Illegal turn
- **Flags:** A vehicle turns into the forbidden direction (heading swings 45 degrees or more).
- **Does not flag:** Vehicles going straight or turning the allowed way in the same zone.
- **Camera view:** Elevated view of the junction (the whole turn visible for 2 s or more).
- **Operator setup:** Draw the zone and an arrow for the forbidden direction (an arrow pointing left = no left turn).

#### `illegal_u_turn`: Illegal U-turn
- **Flags:** A vehicle turns back the way it came (150 degrees or more) and moves sideways at least 0.75 box widths.
- **Does not flag:** A vehicle reversing in a straight line; ordinary turns.
- **Camera view:** Elevated view of the road section.
- **Operator setup:** Draw the area where U-turns are not allowed.
- **Known limit:** The legal wording (local no-U-turn rules) still has to be confirmed before it is quoted on a ticket.

#### `swerving`: Swerving
- **Flags:** A vehicle weaves left-right-left within 6 s (swings of at least half its width).
- **Does not flag:** A single lane change; a steady straight path.
- **Camera view:** Rear or front view along the road; the vehicle visible for 6 s or more and travelling at least 2 box widths.
- **Operator setup:** Draw the monitored zone (auto flow mode gives it the whole frame).

#### `red_light`: Red light running
- **Flags:** A vehicle crosses the stop line while the light is red.
- **Does not flag:** A vehicle crossing on green; a vehicle still in the junction when the light turns red.
- **Camera view:** View of the stop line and of the vehicles' wheels; the light itself visible if the real light is used.
- **Operator setup:** Draw the zone, the stop line and either the light box or the simulated light (red start, red / green / yellow seconds).
- **Known limit:** An unknown light never produces a ticket.

#### `disregarding_signs`: Disregarding traffic signs
- **Flags:** Breaking a sign: no entry, no turn, no stopping, vehicle ban or stop sign (one clip per sign type).
- **Does not flag:** Obeying the same sign.
- **Camera view:** Fixed view of the sign's zone.
- **Operator setup:** One zone per sign with its type (and an arrow or stop line where the type needs one).

#### `signal_light`: Signal light violation (experimental)
- **Flags:** A turn of 45 degrees or more without a blinking indicator.
- **Does not flag:** Turns with a blinking indicator.
- **Camera view:** Close front or rear view where the indicators at the left and right edges are visible.
- **Operator setup:** Draw the zone.
- **Known limit:** EXPERIMENTAL: it can over-flag (hand signals are lawful, motorcycles are exempt), so it is not a headline result.

#### `blocking_intersection`: Blocking the intersection
- **Flags:** A vehicle stands still inside the junction box for more than 5 s.
- **Does not flag:** A vehicle passing through, or waiting before the box.
- **Camera view:** Elevated view of the whole junction box.
- **Operator setup:** Draw the junction box.
- **Known limit:** The legal basis (local anti-obstruction rules) still has to be confirmed.

#### `crossing_solid_line`: Crossing a solid line
- **Flags:** A vehicle crosses the drawn solid line (it ends up clearly past it).
- **Does not flag:** A vehicle wobbling on its own side of the line.
- **Camera view:** Fixed view where the line and the wheels are visible.
- **Operator setup:** Draw the road section and the line.
- **Known limit:** The legal basis (no-overtaking rules) still has to be confirmed.

#### `illegal_loading`: Illegal loading / unloading
- **Flags:** A bus, jeepney, tricycle or truck stands still in the no-loading zone for more than 8 s.
- **Does not flag:** A bus passing through, a short stop, a car left standing (that is illegal parking), a vehicle outside the zone.
- **Camera view:** Fixed view where the zone and the whole vehicle are visible.
- **Operator setup:** Draw the no-loading area; set the time limit and the vehicle types that may not load there.
- **Known limit:** Needs the vehicle class to settle (5+ looks). A jeepney is detected as a bus. The legal basis (MMDA / LGU loading rules) still has to be confirmed for Zamboanga City.

#### `truck_ban`: Truck ban / truck lane
- **Flags:** A truck stays inside the banned road or lane zone for 1 s or more.
- **Does not flag:** Cars, buses and motorcycles in the same zone; a truck outside the zone.
- **Camera view:** Fixed view where the zone and the vehicle type can be told apart.
- **Operator setup:** Draw the banned road or lane; the banned types default to truck.
- **Known limit:** No clock: for a ban that applies only at certain hours, film those hours. The stock detector may call a pickup or van a car. The legal basis still has to be confirmed.

#### `tricycle_on_highway`: Tricycle on a national highway
- **Flags:** A tricycle stays inside the highway zone for 1 s or more.
- **Does not flag:** Motorcycles, cars and buses on the same highway; a tricycle on a street outside the zone.
- **Camera view:** Fixed view of a road where tricycles are banned (a national highway the city has not exempted).
- **Operator setup:** Nothing has to be drawn: ticking the rule says the whole view is a road where tricycles are banned. Draw a zone only to limit the rule to the banned part (for example when the view also shows a side street or an exempted section). The banned type defaults to tricycle.
- **Known limit:** Needs a detector that knows "tricycle" (the stock COCO model does not). Based on DILG MC 2020-036 / 2023-195. The video cannot show that a road is a national highway, or that the city exempts a section of it, so the operator states it for each camera (DPWH national road list, the city's Tricycle Route Plan and ordinance). Confirm the local rule for Zamboanga City.

#### `sidewalk_driving`: Driving on the sidewalk
- **Flags:** A moving vehicle stays inside the sidewalk or bike-lane zone for 1.5 s or more.
- **Does not flag:** A parked vehicle in the zone (that is illegal parking); a vehicle crossing to a driveway in under 1.5 s.
- **Camera view:** Fixed view where the sidewalk edge is clear.
- **Operator setup:** Draw the sidewalk or bike lane.
- **Known limit:** No legal source was found yet: confirm the local ordinance before quoting it.

#### `double_parking`: Double parking
- **Flags:** A vehicle stands in the travel lane beside another stopped vehicle (there first) for more than 8 s while a third vehicle drives through the zone.
- **Does not flag:** A queue at a red light (nothing moves past); a vehicle stopped alone; a vehicle queued behind another.
- **Camera view:** Elevated or side view where the lane, the kerb vehicle and the passing traffic are all visible.
- **Operator setup:** Draw the one travel lane next to the kerb, not the whole road.
- **Known limit:** Needs moving traffic inside the zone; the direction of that traffic decides what "beside" means. Experimental until it has run on real footage.

### People on or in the vehicle (frame checks) (3)

#### `overloading`: Overloading (too many riders)
- **Flags:** A motorcycle carries more riders than allowed (default 2) in most looks.
- **Does not flag:** Motorcycles with one or two riders; pedestrians walking past a motorcycle.
- **Camera view:** Front, rear or side view with every rider's body visible and the motorcycle large enough to count heads.
- **Operator setup:** Set the maximum riders (default 2).
- **Known limit:** Riders are counted from person boxes; heavy overlap hides riders.

#### `pickup_passengers`: Passengers in the back of a pickup / truck
- **Flags:** A moving pickup or truck has people in its open back (bed).
- **Does not flag:** A pickup with an empty bed; a pedestrian walking beside it; a parked pickup being loaded.
- **Camera view:** Front, rear or side view at a moderate height, so the bed and the cab are apart in the picture.
- **Operator setup:** Set how many people are tolerated (default 0).
- **Known limit:** A straight top-down view cannot tell the bed from the cab. Pickups are usually detected as 'truck'. Legal basis: RA 4136 Sections 32 and 51 (the fine amounts are unconfirmed).

#### `riding_outside_vehicle`: Riding on the roof or hanging off a vehicle
- **Flags:** People on the roof of, or hanging off, a moving bus, jeepney or truck.
- **Does not flag:** People boarding a stopped bus; pedestrians beside a moving one.
- **Camera view:** The whole side or the rear of the vehicle at a moderate height.
- **Operator setup:** None.
- **Known limit:** Someone on the rear step seen from straight behind is hidden by the vehicle.

### Specialist model on the vehicle crop (5)

#### `no_plate`: No plate number
- **Flags:** A vehicle with no plate on it (rear view for motorcycles, which carry a rear plate only).
- **Does not flag:** Vehicles with a plate; a motorcycle seen from the front.
- **Camera view:** Vehicles at least 60 px wide in the picture, plate side facing the camera.
- **Operator setup:** None. Decided when the vehicle leaves the picture or the video ends.
- **Known limit:** A plate found at any fair look cancels the suspicion.

#### `no_helmet`: No helmet
- **Flags:** A motorcycle rider without a helmet (or a helmet hung on the arm).
- **Does not flag:** Riders with helmets; pedestrians.
- **Camera view:** Front or rear view of the motorcycle with the riders' heads visible.
- **Operator setup:** None.
- **Known limit:** Needs the helmet model; the training data is not from Zamboanga.

#### `no_seatbelt`: No seatbelt
- **Flags:** A car driver without a seatbelt, seen through a clear windshield.
- **Does not flag:** Belted drivers; cars with tinted windshields (judged as 'no look' by design).
- **Camera view:** Front view of the car, close enough to see through the windshield, daylight.
- **Operator setup:** None.
- **Known limit:** Tinted windows are skipped on purpose (safety gate); there is no tinted-window training data yet.

#### `distracted_driving`: Phone use while driving
- **Flags:** A driver holding a phone to the ear or at the wheel.
- **Does not flag:** Drivers with empty hands.
- **Camera view:** Front view through a clear windshield, daylight.
- **Operator setup:** None.
- **Known limit:** Not in the thesis list; kept as an extra.

#### `missing_side_mirror`: Missing side mirror
- **Flags:** A motorcycle with fewer than two side mirrors, seen from the front or the rear.
- **Does not flag:** Motorcycles with both mirrors; any motorcycle seen from the side (one mirror is always hidden).
- **Camera view:** Front or rear view of the motorcycle with the mirrors large enough to see.
- **Operator setup:** None.
- **Known limit:** Cannot work yet: the cabin model has no motorcycle-mirror training data (see datasets/CATALOG.md).

Camera and clip rules that apply to every violation:

- Fixed camera: no panning, zooming or hand-held footage (the zones and the learned flow assume one fixed view).
- Mounted above the road (about 3 to 8 m) looking down at 15 to 45 degrees, not straight down.
- Vehicles at least 120 px wide in the picture for plate, helmet and seatbelt checks (the plate check ignores vehicles under 60 px).
- At least 720p and 15 fps; 25-30 fps is better. Daylight for the first test set; evening and night as a separate set.
- Each vehicle visible for at least 3 s (the rules need several position updates; swerving needs 6 s).
- No heavy rain, lens dirt or strong backlight in the main test set.

---

## PART B: PROPOSED, NOT BUILT (12)

Ten were proposed on 2026-11-05 and two were added on 2026-11-09. Each has a legal basis, difficulty grade and reason in [VIOLATIONS_AND_SOURCES.md](VIOLATIONS_AND_SOURCES.md).

| Proposed violation | Would work like | What it needs first |
|---|---|---|
| illegal_overtaking | path rule (A passes B) | order change in a lane plus a centre-line crossing or a drawn no-passing zone |
| overtaking_on_right (added 2026-11-09) | path rule (A passes B, ends on B's right) | lane geometry; legal on multi-lane one-way sections and beside a left-turning vehicle, so draw it only on single-lane roads |
| kuliglig_with_passengers (added 2026-11-09) | frame check (person box inside the vehicle box, like pickup_passengers) | a kuliglig detector class (none exists) and own footage; driver assumed excepted, to confirm |
| failure_to_yield_pedestrian | zone rule | person tracks, a crosswalk zone and a car that does not slow down |
| child_on_motorcycle | model check | tell a child from a small adult and see the feet |
| phone_while_riding | model check | a phone model for riders (none) |
| unreadable_or_improvised_plate | model check | plate box found but OCR confidence low |
| tricycle_rest_day | plate rule | tricycle detector and a readable plate |
| no_lights_at_night | model check | night clips and a lit/unlit lamp detector |
| high_beam_not_dimmed | model check | glare handling and scene reasoning |
| overspeeding | path rule with calibration | pixel-to-metre calibration per camera and a limit per zone |
| smoke_belching | model check | a smoke classifier (suspicion only, never a confirmed violation) |

---

## PART C: ORIGINAL DESIGN NOTES (September 2026, first 13 violations)

These notes were written before the 25 violations were built. Where they disagree with Part A, Part A is right. What changed:

- 13 violations became 25 (see Part A).
- "Crosswalk Obstruction" is now `pedestrian_lane`: a vehicle standing still on the crosswalk for more than 3 s. It does not read the light.
- "Over-speeding" is not built; it is proposed (Part B).
- "Illegal Turn" is no longer a tripwire: the zone has an arrow for the forbidden direction and a heading swing of 45 degrees or more flags it. `illegal_u_turn` is separate (150 degrees or more).
- "Illegal Parking" judges a vehicle as stopped when its speed is below 25 px/s (not 5 px per frame), and the zone's time limit defaults to 180 s.
- "Swerving" flags a left-right-left weave within 6 s (swings of at least half the vehicle's width), not a jerk threshold.
- "Overloading" counts person boxes whose feet are inside the motorcycle's width and that overlap it by at least 30%, and flags when more than the maximum (default 2) are seen in at least 60% of the last 10 looks (minimum 5 looks). It does not use the 80% overlap rule below.
- "No Helmet" lets the helmet model read the motorcycle together with its riders (whole rider, not just the helmet) and decides by a vote (60% of the last 10 looks, at least 3).
- "Red Light" is judged at the moment of crossing (30% of the box width and at least 10 px past the stop line) while the light is red; the light is read from a box on the real light or a simulated timer for recorded footage. An unknown light never tickets.
- "Missing Side Mirror" cannot work yet: the cabin model has no motorcycle-mirror training data.

## PART 1: STATIC VIOLATIONS (SHAPE-BASED)
These violations do not rely on movement over time. They are solved by injecting a cropped vehicle image into a Specialist YOLO model during an Interval Check (e.g., every 15 frames).

### 1. No Helmet
* **Required Models:** Primary YOLO (Vehicle), Specialist YOLO (Helmet/Rider).
* **JSON Requirement:** Simple `boolean` toggle (ON/OFF).
* **Integration Logic:** 
  1. Crop the motorcycle bounding box.
  2. Inject crop into Helmet Specialist.
  3. Calculate: `Count(rider_class) - Count(rider_with_helmet)`. 
  4. If `> 0`, flag violation.
* **Edge Case Guard:** The helmet box must overlap the top 20% of the rider box to ensure it is worn, not carried.

### 2. Overloading
* **Required Models:** Primary YOLO (Vehicle), Specialist YOLO (Helmet/Rider).
* **JSON Requirement:** Simple `boolean` toggle (ON/OFF).
* **Integration Logic:** 
  1. Crop the motorcycle bounding box.
  2. Inject crop into Helmet/Rider Specialist.
  3. Tally total instances of the `rider` class.
  4. If `Count(rider) > 2`, flag violation.
* **Edge Case Guard:** Uses an 80% IoU Overlap Rule to ensure pedestrians in the background are not counted as riders.

### 3. No Plate Number
* **Required Models:** Primary YOLO (Vehicle), Specialist YOLO (License Plate).
* **JSON Requirement:** Simple `boolean` toggle (ON/OFF).
* **Integration Logic:**
  1. Crop the vehicle bounding box.
  2. Inject crop into Plate Specialist.
  3. If no plate bounding box is found with high confidence (>0.6), flag violation.
  4. *Note: EasyOCR is skipped for this ticket since there is no text to read.*

### 4. Missing Side Mirror
* **Required Models:** Primary YOLO (Vehicle), Specialist YOLO (Motorcycle Parts).
* **JSON Requirement:** Simple `boolean` toggle (ON/OFF).
* **Integration Logic:**
  1. Crop the motorcycle bounding box.
  2. Inject crop into Parts Specialist.
  3. If `Count(side_mirror) < 2`, flag violation.

### 5. No Seatbelt
* **Required Models:** Primary YOLO (Vehicle), Specialist YOLO (Cabin/Driver).
* **JSON Requirement:** Simple `boolean` toggle (ON/OFF).
* **Integration Logic:**
  1. Crop the top 50% of the car (Windshield area).
  2. Inject crop into Cabin Specialist to find the `seatbelt` diagonal strap class.
  3. If no seatbelt is detected on the driver, flag violation.
* **Edge Case Guard (Tint Override):** If the model classifies the windshield as `tinted_window`, the system explicitly aborts the check to prevent false positives.

### 6. Distracted Driving (Mobile Phone)
* **Required Models:** Primary YOLO (Vehicle), Specialist YOLO (Cabin/Driver).
* **JSON Requirement:** Simple `boolean` toggle (ON/OFF).
* **Integration Logic:**
  1. Crop the windshield area.
  2. Inject crop into Cabin Specialist.
  3. If `driver_phone` class is detected near the head/hand region, flag violation.
* **Edge Case Guard:** Also protected by the Tint Override logic.

---

## PART 2: DYNAMIC VIOLATIONS (MOVEMENT-BASED)
These violations require tracking over time. They are solved by the DeepSORT memory tracker and the Python Ledger, interacting directly with the Admin's JSON ROI Canvas.

### 7. Counterflow
* **Required Models:** Primary YOLO (Vehicle), DeepSORT (Tracker).
* **JSON Requirement:** A defined `Legal Vector` (directional arrow) drawn by the admin on the canvas.
* **Integration Logic:**
  1. DeepSORT logs the centroid of the vehicle at Frame 1 and Frame 15.
  2. Python calculates the movement vector (angle).
  3. Python compares the movement vector against the JSON's `Legal Vector`.
  4. If the angle opposes the legal flow (e.g., > 90° difference) and sustains for N frames, flag violation.

### 8. Illegal Parking
* **Required Models:** Primary YOLO (Vehicle), DeepSORT (Tracker).
* **JSON Requirement:** A defined `Polygon` (No Parking Zone) and an integer `Time Limit` (e.g., 180s) drawn by the admin.
* **Integration Logic:**
  1. Check if the vehicle's centroid is inside the Polygon coordinates.
  2. If inside, check Jitter Filter: is inter-frame movement < 5 pixels?
  3. If Yes, start the Temporal Stopwatch for that `Track_ID`.
  4. If Stopwatch >= JSON `Time Limit`, flag violation. Reset stopwatch if car moves.

### 9. Illegal Turn (e.g., No U-Turn)
* **Required Models:** Primary YOLO (Vehicle), DeepSORT (Tracker).
* **JSON Requirement:** A defined `Tripwire Line` (Prohibited Turn boundary) drawn by the admin.
* **Integration Logic:**
  1. DeepSORT traces the movement history of the vehicle.
  2. If the vehicle's sustained trajectory vector intersects the restricted `Tripwire Line`, flag violation.

### 10. Swerving (Reckless Driving)
* **Required Models:** Primary YOLO (Vehicle), DeepSORT (Tracker).
* **JSON Requirement:** Simple `boolean` toggle (ON/OFF). Optional Lane lines defining boundary width.
* **Integration Logic:**
  1. Calculate the lateral (side-to-side) velocity vector between frames.
  2. Calculate the rate of change of lateral velocity (Jerk).
  3. If lateral jerk exceeds a designated high threshold repeatedly within a 2-second window (indicating erratic weaving), flag violation.

### 11. Red Light Running
* **Required Models:** Primary YOLO (Vehicle), DeepSORT (Tracker), OpenCV (Pixel Color Check).
* **JSON Requirement:** A small visual `ROI Box` placed specifically over the physical red light bulb, and a `Stop Line Tripwire` drawn across the road.
* **Integration Logic:**
  1. OpenCV constantly checks the raw pixels inside the Traffic Light ROI. If they glow bright red, `state = RED` and the system arms the tripwire.
  2. While armed, monitor the Stop Line Tripwire.
  3. If a vehicle's DeepSORT tracking centroid completely crosses the Stop Line, flag violation.
* **Edge Case Guard (Grace Period):** If the vehicle's starting bounding box coordinate was already touching or past the line at the exact millisecond the light flipped to `RED`, the system forgives it and ignores the trigger.

### 12. Crosswalk Obstruction
* **Required Models:** Primary YOLO (Vehicle), DeepSORT (Tracker), Simple YOLO (Traffic Light State).
* **JSON Requirement:** A defined `Polygon` over the pedestrian crosswalk.
* **Integration Logic:**
  1. Monitor Traffic Light State.
  2. If state == `RED`, check if any vehicle centroid is stationary (Speed < 5px) inside the Crosswalk Polygon.
  3. If stationary inside the box while light is Red, flag violation.

### 13. Over-speeding
* **Required Models:** Primary YOLO (Vehicle), DeepSORT (Tracker).
* **JSON Requirement:** 4 points clicked on the road by the admin to create a `Perspective Transform Matrix`, and an integer `Speed Limit`.
* **Integration Logic:**
  1. DeepSORT measures how many raw 2D pixels the car's centroid travels in 1 second.
  2. The Python backend applies OpenCV's `warpPerspective()` function using the JSON matrix to mathematically flatten the 2D image into a Top-Down 3D Bird's-Eye View.
  3. Convert Bird's-Eye pixels into Real-World Meters.
  4. Calculate Kilometers Per Hour (KPH). If `KPH > Speed Limit`, flag violation.
