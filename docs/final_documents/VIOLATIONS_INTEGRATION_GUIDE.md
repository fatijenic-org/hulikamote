# HULI-KAMOTE: VIOLATIONS INTEGRATION GUIDE
This document serves as the technical integration manual for all 13 target violations. It details exactly how each violation is mathematically solved, which AI models are engaged, and how it connects to the system's dynamic JSON configuration.

---

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
