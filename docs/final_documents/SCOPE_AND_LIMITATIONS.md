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

### VIOLATIONS (// = mandatory, / = included, x = excluded, ! = considered)
1. blocking_intersection /
2. counterflow //
3. crossing_solid_line /
4. disregarding_signs /
5. distracted_driving /
6. double_parking /
7. illegal_loading /
8. illegal_parking //
9. illegal_turn //
10. illegal_u_turn /
11. missing_side_mirror //
12. no_helmet //
13. no_plate //
14. no_seatbelt /
15. overloading //
16. pedestrian_lane /
17. pickup_passengers /
18. red_light /
19. restricted_lane /
20. riding_outside_vehicle /
21. sidewalk_driving !
22. signal_light /
23. swerving /
24. tricycle_on_highway !
25. truck_ban !
26. kuliglig passenger //


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
11. Illegal Parking: "stopped" means speed under 25 px/s; a shaking camera can hide a parked car
12. Illegal Turn: whole turn visible for 2 s or more; admin sets the forbidden direction
13. Illegal U-turn: elevated view of the road section; legal wording to confirm
14. Red Light: light is simulated (item 3); unknown light never gives a ticket; admin draws the stop line
15. Pedestrian Lane: flags a stop of more than 3 s on the crosswalk; a red-light queue looks the same
16. Blocking Intersection: elevated view of the whole box; flags a stop of more than 5 s; legal basis to confirm
17. Crossing Solid Line: admin draws the line; legal basis to confirm
18. Restricted Lane: admin sets the allowed vehicle types; no national legal basis found (local ordinance)
19. Truck Ban: a pickup or van may be detected as a car; no clock, so film the banned hours; legal basis to confirm
20. Sidewalk Driving: needs a moving vehicle in the zone for 1.5 s or more; legal basis to confirm
21. Illegal Loading: a jeepney is detected as a bus; needs 5 or more looks to settle the vehicle type; local rule to confirm
22. Double Parking: experimental; needs moving traffic in the zone; not tested on real footage
23. Swerving: front or rear view; vehicle visible 6 s or more; a shaking track can fake a swerve
24. Signal Light: experimental; can over-flag (hand signals are lawful, motorcycles are exempt); needs a close front or rear view
25. Pickup Passengers: a straight top-down view cannot tell the bed from the cab; pickups are detected as "truck"
26. Riding Outside Vehicle: a person on the rear step is hidden when seen from straight behind
27. Distracted Driving: front view through a clear windshield, daylight only; tinted windshield skipped
28. No Plate: vehicle at least 60 px wide; plate side faces the camera; motorcycle rear plate only; a plate found at any fair look cancels the case
