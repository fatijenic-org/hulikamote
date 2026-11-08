# Traffic Violation Detection — Logic Documentation

> **Scope:** Motorcycle & Car violations (core + extended)
> **Approach:** Brute Force → Optimized Logic → Math → Tools

---

## Legend

| Symbol | Meaning |
|--------|---------|
| 🔴 BF | Brute Force approach |
| 🟢 OL | Optimized Logic |
| 📐 | Math / Formula |
| 🛠️ | Tools |

---

## Shared Concepts (Used Across All Violations)

### Object Detection Baseline
Every violation starts by detecting the **vehicle or rider** in a frame.

**🔴 BF:** Scan every pixel of every frame. Compare pixel clusters to known vehicle templates.

**🟢 OL:** Use a pretrained YOLO model. Pass the frame → get bounding boxes with class labels (`motorcycle`, `car`, `person`, `helmet`, etc.) + confidence scores.

**📐 Math:**
```
IoU (Intersection over Union) = Area(A ∩ B) / Area(A ∪ B)
Confidence threshold τ = 0.5 (typical)
NMS (Non-Max Suppression): keep box with highest score when IoU > τ
```

**🛠️ Tools:**

| Tool | Type | Cost |
|------|------|------|
| YOLOv8 (Ultralytics) | Object Detection | Free |
| YOLOv9 / YOLOv10 | Object Detection | Free |
| OpenCV | Frame processing | Free |
| Roboflow | Dataset annotation | Free tier |
| CVAT | Dataset annotation | Free (self-hosted) |
| LabelImg | Dataset annotation | Free |

---

---

# MOTORCYCLE VIOLATIONS

---

## 1. Counterflow

### Definition
A motorcycle traveling **against the legal direction of traffic** on a one-way road or against the designated lane flow.

### 🔴 Brute Force
- Detect motorcycle in every frame.
- Manually compare its position in frame T and frame T+N.
- If it moves from right-to-left on a road marked left-to-right, flag it.
- Problem: requires hardcoded road direction per camera; no scalability.

### 🟢 Optimized Logic
1. **Detect** motorcycle bounding box per frame (YOLO).
2. **Track** the vehicle across frames (assign persistent ID).
3. **Compute velocity vector** from centroid displacement.
4. **Compare** velocity vector against the road's **reference flow vector** (pre-configured per camera angle).
5. If angle between vehicle vector and reference vector > 90°, flag as counterflow.

### 📐 Math
```
Centroid at frame t:  C_t = (x_t, y_t)  [center of bounding box]
Centroid at frame t+n: C_{t+n} = (x_{t+n}, y_{t+n})

Velocity vector:
  V = C_{t+n} - C_t = (Δx, Δy)

Reference flow vector (configured per camera):
  R = (r_x, r_y)  [e.g., (1, 0) means traffic flows left to right]

Dot product:
  D = V · R = Δx·r_x + Δy·r_y

Angle between vectors:
  θ = arccos( D / (|V| × |R|) )

Counterflow condition:
  θ > 90°  →  D < 0  →  VIOLATION
```

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| YOLOv8 | Detect motorcycle | Free |
| ByteTrack / DeepSORT | Multi-object tracking | Free |
| OpenCV | Vector math, frame ops | Free |
| NumPy | Math computations | Free |

---

## 2. Illegal Parking

### Definition
Vehicle stopped/parked in a **no-parking zone** (yellow lines, intersections, bus stops, etc.).

### 🔴 Brute Force
- Check every frame if a vehicle is present.
- If it's stationary for X seconds → flag it.
- Problem: requires manual zone definition per camera; false positives from traffic stops.

### 🟢 Optimized Logic
1. **Detect** motorcycle using YOLO.
2. **Track** across frames with ByteTrack.
3. **Measure stationarity**: if centroid displacement < threshold pixels for N consecutive seconds → vehicle is stationary.
4. **Check zone**: Does the vehicle's bounding box overlap a **pre-defined no-parking polygon** (mapped to the scene)?
5. If stationary in no-parking zone for ≥ T_min → VIOLATION.

### 📐 Math
```
Displacement between frames:
  d = |C_{t+n} - C_t| = sqrt(Δx² + Δy²)

Stationary condition:
  d < ε  (e.g., ε = 5 pixels) for N consecutive frames

Time stationary:
  t_stationary = N_frames / FPS

No-parking zone check (Point-in-Polygon):
  Use Ray Casting Algorithm:
  Count intersections of a ray from C to infinity with polygon edges.
  If count is odd → point is inside polygon → IN ZONE

Violation condition:
  d < ε  AND  C inside no-parking polygon  AND  t_stationary > T_min (e.g., 5s)
```

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| YOLOv8 | Detection | Free |
| ByteTrack | Tracking | Free |
| OpenCV `pointPolygonTest()` | Zone containment | Free |
| Shapely | Polygon geometry | Free |

---

## 3. Illegal Turn

### Definition
Turning at a location where a **"No Turn"** sign applies or turning from the **wrong lane**.

### 🔴 Brute Force
- Track position across all frames.
- Manually define intersection zones.
- Check if heading before intersection ≠ heading after intersection at a no-turn zone.

### 🟢 Optimized Logic
1. **Detect** motorcycle and entry direction before an intersection zone.
2. **Track** through the intersection.
3. **Detect exit direction** after the intersection.
4. **Compare** turn (left/right/U) against the rules for that zone.
5. Optionally detect **"No Turn" signs** using a sign classifier.

### 📐 Math
```
Entry vector:  V_entry = C_{t_entry} - C_{t_entry - n}
Exit vector:   V_exit  = C_{t_exit + n} - C_{t_exit}

Turn angle:
  θ_turn = arctan2(V_exit_y, V_exit_x) - arctan2(V_entry_y, V_entry_x)
  Normalize to [-180, 180]

Turn classification:
  |θ_turn| < 30°      → Straight
  30° ≤ θ_turn < 120° → Left Turn
  -120° < θ_turn ≤ -30° → Right Turn
  |θ_turn| ≥ 150°    → U-Turn

Intersection zone: pre-defined polygon
  If C_t enters polygon AND turn type matches prohibited turn → VIOLATION
```

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| YOLOv8 | Detection | Free |
| ByteTrack | Tracking | Free |
| OpenCV | Vector math | Free |
| Tesseract OCR / YOLO classifier | Sign detection | Free |

---

## 4. Disregarding Signs

### Definition
Vehicle passes through a **Stop sign**, **No Entry**, or other regulatory sign without obeying.

### 🔴 Brute Force
- Detect sign in frame.
- Detect vehicle in same frame.
- If vehicle is near sign and still moving → flag.

### 🟢 Optimized Logic
1. **Detect signs** in the scene (YOLO classifier trained on PH road signs).
2. **Define a compliance zone** in front of each sign (polygon/line).
3. **Detect vehicle** entering the compliance zone.
4. **Measure speed** or **check if vehicle stopped** (for Stop sign).
5. If the vehicle passes through without satisfying the sign condition → VIOLATION.

### 📐 Math
```
Stop sign compliance:
  Speed at compliance zone:
  v = d / Δt = |C_{t+1} - C_t| / (1/FPS)

  Condition: v < v_stop_threshold (e.g., 2 px/frame) for at least T_stop frames

No Entry violation:
  If vehicle enters zone AND direction matches restricted flow → VIOLATION

Sign detection confidence:
  Keep detection if confidence > 0.7
  Use IoU > 0.45 for NMS
```

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| YOLOv8 (custom trained) | Sign detection | Free |
| GTSRB / PH Sign Dataset | Training data | Free |
| OpenCV | Zone logic | Free |
| Roboflow | Annotate sign dataset | Free tier |

---

## 5. No Plate Number

### Definition
Motorcycle has **no visible license plate** or the plate is obscured.

### 🔴 Brute Force
- Crop vehicle bounding box.
- Apply edge detection to find rectangular regions.
- Check if any rectangle matches plate aspect ratio.

### 🟢 Optimized Logic
1. **Detect motorcycle** bounding box (YOLO).
2. **Crop** the lower/rear region of the motorcycle.
3. **Run plate detector** (another YOLO model trained on plates) on the crop.
4. If no plate bounding box found with sufficient confidence → VIOLATION.
5. Optionally run **OCR** to validate the plate text.

### 📐 Math
```
Plate aspect ratio (PH standard):
  Width / Height ≈ 3.5 (motorcycle plate)

Plate detection:
  confidence_plate > τ (e.g., 0.5) → plate present
  else → no plate → VIOLATION

Plate region crop (heuristic):
  crop_y_start = bbox_y + (0.6 × bbox_height)   [lower 40% of motorcycle]
  crop_x_start = bbox_x
  crop_width   = bbox_width
  crop_height  = 0.4 × bbox_height
```

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| YOLOv8 | Plate detection | Free |
| EasyOCR / Tesseract | Plate reading | Free |
| OpenALPR (community) | ALPR | Free (limited) |
| OpenCV | Image crop/transform | Free |

---

## 6. No Helmet

### Definition
Motorcycle rider (driver or passenger) not wearing a **helmet**.

### 🔴 Brute Force
- Crop rider's head region.
- Compare pixel color/texture to known helmet colors.

### 🟢 Optimized Logic
1. **Detect motorcycle and rider(s)** with YOLO (pose or bounding box).
2. **Crop head region** of each detected rider.
3. **Classify** head region: `helmet` vs `no_helmet` using a trained classifier.
4. If any rider → `no_helmet` → VIOLATION.

### 📐 Math
```
Head region estimation:
  Rider bbox height H_r
  Head crop: top 25% of rider bbox
  head_y_end = rider_y + 0.25 × H_r

Binary classification:
  P(helmet | crop) = sigmoid(model output)
  P > 0.5 → helmet present
  P ≤ 0.5 → no helmet → VIOLATION

Passenger detection:
  If second person detected behind driver on same motorcycle
  → apply same head crop + classification logic
```

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| YOLOv8-pose | Rider keypoint detection | Free |
| YOLOv8 classifier | Helmet / no-helmet | Free |
| Roboflow Universe | Pre-labeled helmet datasets | Free |
| OpenCV | Crop operations | Free |

---

## 7. Missing Side Mirror

### Definition
Motorcycle is missing **one or both side mirrors**.

### 🔴 Brute Force
- Use edge detection on motorcycle.
- Compare resulting shape to template motorcycles with mirrors.

### 🟢 Optimized Logic
1. **Detect motorcycle** with YOLO.
2. **Run a part segmentation / keypoint model** that identifies mirror positions.
3. Check presence of mirrors at expected positions (left-wing, right-wing of handlebar area).
4. If mirror keypoint/region is absent or confidence is below threshold → VIOLATION.

### 📐 Math
```
Mirror expected location (relative to motorcycle bbox):
  Left mirror:  (bbox_x + 0.1 × bbox_w, bbox_y + 0.15 × bbox_h)
  Right mirror: (bbox_x + 0.9 × bbox_w, bbox_y + 0.15 × bbox_h)

Keypoint detection confidence:
  kp_confidence > 0.5 → mirror detected
  kp_confidence ≤ 0.5 → mirror possibly absent

Decision:
  Both mirrors detected → OK
  One or both absent → VIOLATION
```

> ⚠️ **Note:** This is one of the harder violations. A side-view camera angle significantly improves accuracy. Front-facing cameras may have limited detection capability.

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| YOLOv8-seg | Motorcycle part segmentation | Free |
| Custom YOLO keypoints | Mirror localization | Free |
| OpenCV | Region analysis | Free |

---

## 8. Overloading

### Definition
More than the **legally allowed number of passengers** on a motorcycle (typically 2 total: driver + 1 passenger).

### 🔴 Brute Force
- Count number of heads in motorcycle bounding box.

### 🟢 Optimized Logic
1. **Detect motorcycle** bounding box.
2. **Detect persons** inside or overlapping the motorcycle bbox.
3. **Count riders** (persons whose centroid falls within or very close to the motorcycle bbox).
4. If count > 2 → VIOLATION.

### 📐 Math
```
Person-motorcycle association:
  For each person bbox P and motorcycle bbox M:
  IoU(P, M) > 0.1  OR  centroid(P) inside M → person is a rider

Rider count: R = count of associated persons

Overload condition:
  R > 2 → VIOLATION
  (or R > 1 if local ordinance applies stricter rules)
```

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| YOLOv8 | Detect persons + motorcycle | Free |
| ByteTrack | Consistent ID across frames | Free |
| OpenCV | Overlap/IoU computation | Free |

---

---

# CAR VIOLATIONS

*(Counterflow, Illegal Parking, Illegal Turn, Disregarding Signs, No Plate Number — same core logic as Motorcycle. Differences noted below.)*

---

## Cars — Key Differences from Motorcycle

| Violation | Difference |
|-----------|-----------|
| **Counterflow** | Car is larger; tracking more stable. Same vector angle logic. |
| **Illegal Parking** | Same zone logic. Cars have distinct size ratio (wider bbox). |
| **Illegal Turn** | Same angle logic. Cars have stricter lane-change rules. |
| **Disregarding Signs** | Same sign-detection pipeline. |
| **No Plate Number** | PH car plate aspect ratio ≈ 2.5. Rear plate more reliably visible. |

---

---

# EXTENDED VIOLATIONS

---

## E1. Signal Light Violation

### Definition
Vehicle changes lane or turns **without activating a turn signal** (indicator).

### 🔴 Brute Force
- Track vehicle heading changes.
- If heading changes without signal light blink detected → flag.

### 🟢 Optimized Logic
1. **Detect vehicle turn signal light** region (YOLO or template on rear of car).
2. **Detect blink pattern**: alternating bright/dark at ~1–2 Hz frequency.
3. **Track vehicle trajectory** to detect a lane change or turn.
4. If trajectory changes (turn/swerve) but **no blink detected** → VIOLATION.

### 📐 Math
```
Blink detection (brightness analysis):
  Sample ROI of signal light per frame
  Brightness B_t = mean pixel intensity in ROI

  Blink frequency f = (# transitions from high to low in T seconds) / T
  Expected: 1 Hz ≤ f ≤ 2 Hz

Lane change detection:
  |Δx_centroid| > threshold over N frames → lateral movement
  If lateral movement AND f < 0.5 Hz (no blink) → VIOLATION
```

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| YOLOv8 | Vehicle detection | Free |
| OpenCV | ROI brightness sampling | Free |
| NumPy | Frequency analysis | Free |
| ByteTrack | Track lateral movement | Free |

---

## E2. Red Light Running

### Definition
Vehicle **crosses a stop line** while the traffic light is red.

### 🔴 Brute Force
- Check if light is red.
- Check if vehicle is moving past the stop line.

### 🟢 Optimized Logic
1. **Detect traffic light** state (YOLO or HSV color detection → red/green/yellow).
2. **Define stop line** as a horizontal polygon/line in the scene.
3. **Track vehicle**: detect if it crosses the stop line while light state = RED.
4. VIOLATION if vehicle crosses stop line during red phase.

### 📐 Math
```
Traffic light color detection (HSV):
  Red: H ∈ [0,10] ∪ [160,180], S > 100, V > 100

Stop line crossing:
  Define stop line as y = y_stop
  If vehicle centroid y_t > y_stop  AND  y_{t-1} ≤ y_stop  → line crossed
  If light_state = RED at crossing time → VIOLATION

Confidence:
  Light detection confidence > 0.8 recommended
```

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| YOLOv8 (traffic light class) | Light detection | Free |
| OpenCV HSV | Color verification | Free |
| ByteTrack | Vehicle tracking | Free |
| Shapely | Line crossing detection | Free |

---

## E3. Swerving

### Definition
Sudden, **erratic lateral movement** across lanes without signaling.

### 🔴 Brute Force
- Compare centroid x-position per frame.
- If it changes suddenly → flag.

### 🟢 Optimized Logic
1. **Track vehicle** centroid over time using ByteTrack.
2. Compute **lateral displacement** (Δx) between consecutive frames.
3. Compute **rate of change of Δx** (second derivative = lateral jerk).
4. If lateral jerk exceeds threshold → swerving.
5. Cross-check: no valid turn signal active.

### 📐 Math
```
Lateral position: x_t = centroid_x at frame t

Lateral velocity:  v_x(t) = x_{t+1} - x_t
Lateral jerk:      j_x(t) = v_x(t+1) - v_x(t)  [= second derivative]

Swerve condition:
  |j_x(t)| > J_threshold  (e.g., 15 px/frame²)
  AND  no blink detected
  → VIOLATION

Kalman filter recommended to smooth noise before computing derivatives.
```

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| ByteTrack / DeepSORT | Smooth trajectory | Free |
| OpenCV / NumPy | Derivative computation | Free |
| FilterPy | Kalman filter | Free |

---

## E4. No Seatbelt

### Definition
Car occupant (driver or front passenger) **not wearing a seatbelt**.

### 🔴 Brute Force
- Crop driver area.
- Check for diagonal line across torso.

### 🟢 Optimized Logic
1. **Detect car** and **crop the cabin area** (upper portion of vehicle bbox).
2. **Detect persons** inside cabin using YOLO-pose.
3. **Classify seatbelt presence** on each front occupant using a fine-tuned binary classifier.
4. If any front occupant → `no_seatbelt` → VIOLATION.

### 📐 Math
```
Seatbelt region of interest:
  Upper-body region of driver/passenger
  ROI: keypoint[shoulder] → keypoint[hip] (from pose model)

Diagonal line check (edge-based):
  Apply Canny edge detection in ROI
  Run Hough Line Transform
  Check for diagonal line: 30° < θ < 60° (relative to vertical)

  If no diagonal line of minimum length L detected → no seatbelt → VIOLATION

Deep learning alternative:
  Binary classifier: seatbelt / no-seatbelt
  P(seatbelt | crop) > 0.5 → OK
```

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| YOLOv8-pose | Keypoint detection (shoulder, hip) | Free |
| OpenCV Canny + Hough | Edge/line detection | Free |
| YOLOv8 classifier | Binary seatbelt classifier | Free |
| Kaggle Seatbelt Dataset | Training data | Free |

---

## E5. Pedestrian Lane Obstruction

### Definition
Vehicle **blocking a pedestrian crosswalk**, preventing pedestrians from crossing.

### 🔴 Brute Force
- Detect pedestrian crossing marking in image.
- Check if vehicle bounding box overlaps crossing area.

### 🟢 Optimized Logic
1. **Define pedestrian lane zone** as a polygon in the scene (pre-configured per camera).
2. **Detect vehicles** using YOLO.
3. Check if any vehicle bbox **overlaps** the pedestrian zone polygon.
4. Check if vehicle is **stationary** (parked/stopped in zone).
5. Optionally: detect **pedestrians** present → escalate severity.

### 📐 Math
```
Polygon overlap:
  Vehicle bbox rectangle R = (x1, y1, x2, y2)
  Pedestrian zone polygon P

  Overlap area = area of intersection(R, P)
  Overlap ratio = Overlap area / area(R)

  If Overlap ratio > 0.3  AND  vehicle is stationary → VIOLATION

Pedestrian presence amplifier:
  If pedestrian detected in zone AND vehicle obstructing → HIGH PRIORITY
```

### 🛠️ Tools

| Tool | Purpose | Cost |
|------|---------|------|
| YOLOv8 | Detect vehicles + pedestrians | Free |
| Shapely | Polygon intersection | Free |
| OpenCV `pointPolygonTest()` | Fast zone check | Free |
| ByteTrack | Verify stationarity | Free |

---

---

# Recommended Free Tech Stack (Summary)

| Layer | Tool | Alternative |
|-------|------|-------------|
| Object Detection | **YOLOv8** (Ultralytics) | YOLOv9, RT-DETR |
| Multi-Object Tracking | **ByteTrack** | DeepSORT, StrongSORT |
| Pose Estimation | **YOLOv8-pose** | MediaPipe Pose |
| OCR (Plate Reading) | **EasyOCR** | Tesseract |
| Geometry / Zones | **Shapely + OpenCV** | custom NumPy |
| Kalman Filtering | **FilterPy** | OpenCV KalmanFilter |
| Annotation | **Roboflow** / CVAT | LabelImg |
| Training Platform | **Google Colab (free)** | Kaggle Notebooks |
| Video I/O | **OpenCV** | FFmpeg |
| Language | **Python 3.10+** | — |

---

# Detection Priority Matrix

| Violation | Complexity | Camera Angle Needed | Confidence |
|-----------|-----------|---------------------|-----------|
| No Helmet | Low | Front/rear | High |
| No Plate | Low | Rear | High |
| Red Light Running | Medium | Fixed overhead | High |
| Illegal Parking | Medium | Any | High |
| Counterflow | Medium | Side/overhead | Medium |
| Overloading | Medium | Side | Medium |
| Illegal Turn | High | Overhead | Medium |
| Swerving | Medium | Overhead | Medium |
| No Seatbelt | High | Side/front | Medium |
| Signal Light Violation | High | Rear | Medium |
| Disregarding Signs | High | Front | Medium |
| Missing Side Mirror | Very High | Side | Low–Medium |
| Pedestrian Obstruction | Medium | Fixed overhead | High |

---

> **Note:** All polygon/zone definitions (no-parking areas, stop lines, pedestrian crossings) must be configured **per camera installation**. This is a one-time setup step using a calibration tool (e.g., drawing zones on the first frame using OpenCV or Roboflow).
