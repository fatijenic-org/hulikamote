# HULI-KAMOTE: AI ENGINEERING & ARCHITECTURE PLAN
**Version:** 1.1
**Target Environment:** Zamboanga City Traffic (Dense, high-occlusion, chaotic)
**Goal:** Establish the blueprint for handling multiple simultaneous violations and resolving critical computer vision edge cases in real-world deployments.

---

## 1. THE CORE ARCHITECTURE: DECOUPLED CASCADING PIPELINE
To ensure high FPS, low VRAM usage, and easy maintenance, the system abandons the "monolithic model" approach (one giant AI trying to detect everything). Instead, it uses a **Modular Injection Pipeline** relying on tracking-by-detection.

1. **The Primary Anchor (YOLO Generalist):** An ultra-fast, lightweight model (`vehicle_tracker.pt`) runs on the full 4K frame. Its ONLY job is to find and draw boxes around `Motorcycles` and `Cars`. It has no memory.
2. **The Tracker (DeepSORT):** Takes the Primary Anchor's boxes and uses physics (Kalman Filters) and visual appearance (ReID) to track the vehicles across frames, assigning a unique `Track ID`.
3. **The Injected Specialists (Modular AI):** Once the Anchor crops a vehicle, the Python backend *injects* that tiny crop into highly specialized secondary models, but ONLY if the JSON configuration requires it. 
   - `helmet_specialist.pt` (Analyzes motorcycle crops for helmets)
   - `plate_specialist.pt` (Analyzes vehicle crops for plates)
   - `cabin_specialist.pt` (Analyzes car windshields for seatbelts/phones)
   *Benefit: If a camera does not need to check for seatbelts, the `cabin_specialist` is never loaded into VRAM, drastically improving system speed. Retraining the helmet model will never break the vehicle tracker.*
4. **The Ticketing (EasyOCR):** Extracts text from the plate crop only after a violation is definitively confirmed.

---

## 2. MANAGING CHAOS: THE PARENT-CHILD LEDGER SYSTEM
To prevent the AI from cross-contaminating objects (e.g., assigning a pedestrian's hat to a motorcycle rider), we use a strictly hierarchical approach.

* **Step 1: The Vehicle Anchor:** DeepSORT only tracks the Vehicle (Motorcycle or Car). This is the "Parent".
* **Step 2: Cropped Child Search:** Once YOLO finds the vehicle, the system crops that exact rectangle out of the image. A secondary YOLO scan looks *strictly inside that crop* for "Children" (Riders, Helmets, Plates).
* **Step 3: The Active Ledger:** Every `Track ID` gets a temporary digital ledger. The system constantly checks for both static shape violations and dynamic movement violations simultaneously.
* **Step 4: Aggregation:** Violations are NOT ticketed instantly. The system aggregates all broken rules into the ledger. Once the vehicle leaves the camera view, it generates ONE ticket containing all offenses (e.g., "Counterflow + No Helmet + Overloading").

---

## 3. SOLVING CRITICAL REAL-WORLD EDGE CASES

### A. The "Helmet on Lap" Problem
**The Danger:** The AI sees 1 person and 1 helmet in the box and assumes it's legal, even if the helmet is held in the hand.
**The Solution:**
1. **Geometric IoU:** Python math enforces that the center of the Helmet box must reside in the top 20% of the Rider box.
2. **Composite Classes:** We train YOLO with specific contextual classes (`rider_with_helmet` vs `rider_without_helmet`) rather than separating the objects.

### B. The "Background Pedestrian" Problem (False Overloading)
**The Danger:** A motorcycle drives past a pedestrian. The pedestrian accidentally falls inside the motorcycle's bounding box and is counted as a 3rd passenger.
**The Solution:**
1. **Strict 80% Overlap Rule:** A human is only counted as a passenger if at least 80% of their bounding box is physically inside the motorcycle's box.
2. **Posture Training:** YOLO is trained to differentiate between a `rider` (sitting posture) and a `pedestrian` (standing posture). Only `rider` classes are counted inside the crop.

### C. The "Occlusion" Problem (Overlapping Motorcycles)
**The Danger:** Two bikes drive side-by-side. Their boxes overlap. YOLO deletes one, or DeepSORT swaps their IDs.
**The Solution:**
1. **NMS Tuning:** Set a strict Non-Maximum Suppression (NMS) threshold so YOLO allows heavy overlaps without deleting them.
2. **DeepSORT ReID:** DeepSORT remembers the color and texture of each bike so it can re-assign the correct ID when they separate.

### D. The "Window Tint" Problem (Invisible Cabins)
**The Danger:** The Philippines has heavily tinted cars. The AI might randomly guess if a seatbelt is worn through black glass, generating false tickets.
**The Solution:** We implement a **Safety Override Gate**. YOLO is trained to classify the windshield as `clear_window`, `open_window`, or `tinted_window`. If `tinted_window` is detected, the Python ledger explicitly aborts the seatbelt and phone checks, logging *"Check Skipped - Visibility Blocked by Tint."*

---

## 4. EVIDENCE CAPTURE & PACKAGING (Human-in-the-Loop)
Because AI can make mistakes, every generated ticket must be verifiable by a human enforcer and undeniable to the violator. 

When the Ledger aggregates a ticket, it compiles an **Evidence Package** consisting of three parts:
1. **The Context Proof:** A wide-angle photo (Static) or a 3-Frame Collage / 3-second GIF showing the DeepSORT vector (Dynamic) proving the physical movement.
2. **The Violation Crop:** A tight crop of the vehicle with the AI's bounding boxes physically drawn on it (e.g., pointing to the missing helmet).
3. **The OCR Plate Crop:** The clearest crop of the license plate placed next to the EasyOCR text result.

This package is sent to the human enforcer's dashboard. If `Approved`, it becomes the final mailed ticket.

---

## 5. MASTER GLOSSARY: 13 VIOLATIONS LOGIC

### STATIC VIOLATIONS (Solved entirely by YOLO within the Cropped Box)
1. **No Plate Number:** If `Count(Plate) == 0` inside the vehicle box. OCR is skipped.
2. **No Helmet:** If `Count(Rider)` != `Count(Valid Helmets)`. Uses IoU geometry or composite classes.
3. **Overloading:** If `Count(Rider class) > 2` inside the motorcycle box.
4. **Missing Side Mirror:** If `Count(Mirror) < 2` on the motorcycle frame.
5. **No Seatbelt:** Requires `clear_window` class. If `seatbelt` strap class not found crossing the driver box.
6. **Distracted Driving (Mobile Phone):** Requires `clear_window`. Looks for `driver_phone` class near the head/hand region.

### DYNAMIC VIOLATIONS (Solved by DeepSORT + Python Ledger)
7. **Counterflow:** DeepSORT generates a movement vector over `N` frames. If the vector opposes the legal flow arrow of the active ROI, it flags.
8. **Illegal Parking:** 
   - *Spatial:* Car enters No Parking ROI. 
   - *Jitter Filter:* Movement between frames is < 5 pixels (Speed = 0). 
   - *Temporal Stopwatch:* A timer starts. If the timer hits the defined threshold (e.g., 180s), it flags.
9. **Illegal Turn:** The sustained movement vector crosses through an invisible prohibited ROI line at an intersection.
10. **Swerving:** The lateral (side-to-side) velocity vector exceeds a designated threshold (jerk calculation) multiple times over a short frame window.
11. **Red Light Running:** 
    - *Light State:* Vision-based ROI reads the physical traffic light as `RED`.
    - *Stop Line Laser:* DeepSORT vector crosses entirely through the "Stop Line ROI". 
    - *Grace Period:* If the vehicle's bounding box was already past the line before it turned Red, it is ignored.
12. **Crosswalk Obstruction:** 
    - Vehicle speed hits 0 inside the "Pedestrian Crosswalk ROI".
    - Occurs while the vehicle traffic light is Red.
13. **Over-speeding:** Uses Perspective Transformation math. Calculates pixels traveled per second by the DeepSORT centroid, mapped to real-world meters, converted to KPH. If `KPH > Speed Limit`, it flags.

---

## 6. SYSTEM SCALABILITY: DYNAMIC ADMIN CONFIGURATION
Hardcoding coordinates and rules into a Python backend is a brittle approach that breaks the moment a camera is bumped by the wind or relocated. To make HULI-KAMOTE an enterprise-grade platform, the system architecture separates the **AI Engine** from the **Spatial Rules** using a Dynamic Configuration Dashboard.

### 1. The ROI Canvas (Enforcer Dashboard)
Admins access a web interface displaying a freeze-frame of the connected camera. They are given drawing tools:
* **Polygons:** Click to draw restricted zones (e.g., No Parking, Box Junctions).
* **Tripwires:** Draw lines for Stop Lines or Illegal Turn boundaries.
* **Vectors:** Drag an arrow to define the "Legal Flow Direction."

### 2. The Rule Assigner & Toggles
After drawing a shape, the admin assigns it a behavior (e.g., `If Speed == 0 for 180s inside Polygon A -> Flag Illegal Parking`). 
Furthermore, the admin is provided a checklist of the 13 violations. They can toggle them `ON` or `OFF` per camera. A highway camera does not need to waste processing power checking for Red Light violations.

### 3. The JSON Bridge
When the admin clicks "Save," the dashboard generates a `camera_config.json` file.
```json
{
  "camera_id": "Intersection_01",
  "active_violations": ["counterflow", "no_helmet", "illegal_parking"],
  "regions_of_interest": {
    "parking_zone_1": {"coordinates": [[100, 200], [400, 200], [400, 300], [100, 300]], "time_limit": 180},
    "legal_flow_vector": {"x_dir": 1, "y_dir": 0}
  }
}
```
The Python AI engine simply loads this file on startup. It mathematically applies the JSON coordinates to the DeepSORT tracking logic. If a camera angle shifts, a programmer is not required—an enforcer simply redraws the polygon in the UI, generating a new JSON file, and the AI instantly adapts.

---

## 7. SYSTEM OPTIMIZATION (MAINTAINING 30 FPS)
Running multiple specialist YOLO models simultaneously on a crowded video feed is computationally impossible if executed on every frame. To prevent hardware meltdowns and maintain real-time 30 FPS processing, the system employs three crucial software optimizations:

1. **Interval Checking (Frame Skipping):** Because DeepSORT tracks vehicles consistently across frames, the sub-models do not need to check for static violations 30 times a second. The Python ledger is instructed to "wake up" the Specialist Models (e.g., helmet checker) only once every 15 frames (twice a second). DeepSORT bridges the gap in between, cutting processing load by 90%.
2. **GPU Batch Processing:** When the interval check triggers, the system does not process vehicles sequentially. It slices all motorcycle crops from the frame simultaneously, stacks them into a single tensor batch, and fires them into the Specialist Model. The GPU processes 10 tiny images in parallel at the same speed it takes to process 1.
3. **Optimal Zone Triggering:** For heavy operations like EasyOCR plate reading, the system defines an invisible line (the optimal clarity zone). The crop is injected into the OCR model exactly once per vehicle, triggered only when the vehicle's vector intersects the optimal zone.

---

## 8. MODEL TRAINING PIPELINE
To ensure the system works in the Philippine context, relying on generic pre-trained weights (which are US/EU-centric) is insufficient. The Specialist Models must be trained locally using the following 5-step pipeline:

1. **Data Collection (Scraping & Recording):** Gather thousands of raw frames containing Philippine traffic. Sources include local dashcams, stationary smartphone recordings mimicking CCTV angles, and LTO-standard license plate datasets.
2. **Annotation & Labeling (The Ground Truth):** Use platforms like Roboflow or CVAT to manually draw bounding boxes on the raw images. This step defines the custom classes required by the architecture (e.g., `rider_with_helmet`, `tinted_window`, `driver_phone`).
3. **Data Augmentation (Weather/Time Simulation):** To prevent overfitting and prepare the AI for real-world conditions, the dataset is mathematically multiplied. Augmentations include altering brightness (simulating nighttime), adding noise/blur (simulating rain/fog), and flipping images.
4. **Training (Ultralytics YOLOv8):** The dataset is formatted into YAML and fed into the Ultralytics framework. Training is executed on a dedicated GPU (e.g., RTX 3050+) using Nano (`yolov8n`) or Small (`yolov8s`) base weights to ensure the final models remain lightweight enough for VRAM sharing.
5. **Export & Injection:** The training outputs a `best.pt` weights file. This file is renamed (e.g., `plate_specialist.pt`) and injected directly into the backend Model Registry.

---

## 9. SIMULATION & TESTING METHODOLOGY
Before live deployment, the software architecture is rigorously tested without requiring live RTSP camera feeds or fully trained custom models.

1. **Mock Video Ingestion:** The system is fed pre-recorded `.mp4` video files of local traffic, including staged violations (e.g., a motorcycle intentionally counterflowing).
2. **Dummy Model Anchoring:** The standard, free `yolov8n.pt` model (which already recognizes generic cars/motorcycles) is used as the Primary Anchor. This allows immediate testing of DeepSORT and the Python Ledger without waiting for custom training.
3. **JSON Canvas Mocking:** A `test_config.json` file is manually written for the specific camera angle of the `.mp4` video, containing hardcoded Polygon and Tripwire coordinates.
4. **Output Rendering & Validation:** The Python test-bench executes the video frame-by-frame and outputs a final rendered `.mp4`. Engineers review the video to visually verify that bounding boxes track smoothly, vectors calculate correctly, and text overlays (e.g., `VIOLATION: COUNTERFLOW`) trigger at the exact expected timestamps.

---
**END OF ENGINEERING PLAN**
