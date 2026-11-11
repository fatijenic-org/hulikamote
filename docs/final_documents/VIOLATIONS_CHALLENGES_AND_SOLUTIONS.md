# HULI-KAMOTE: COMPUTER VISION CHALLENGES & SOLUTIONS LOG

This document catalogs the critical edge cases, software conflicts, and real-world physics problems encountered during the design of the HULI-KAMOTE architecture, and the precise software logic used to solve them.

---

## 1. The "Helmet on Lap" Problem (False Negatives)
**Challenge:** YOLO counts objects inside the motorcycle bounding box. If a rider is holding a helmet on their lap, YOLO counts `1 Person` and `1 Helmet` and clears the check, even though the helmet is not worn.
**Solution:** 
- *Geometric Constraints (IoU):* The Python backend enforces a rule that the center of the Helmet bounding box must physically intersect with the top 20% of the Person's bounding box.
- *Composite Classes:* YOLO is trained on contextual classes (`rider_with_helmet` vs `rider_without_helmet`) rather than separating the items, allowing the neural network to learn the posture of a worn helmet.

## 2. The "Background Pedestrian" Problem (False Overloading)
**Challenge:** When a motorcycle drives closely past a pedestrian on a sidewalk, the pedestrian accidentally gets caught inside the motorcycle's bounding box crop. The system counts 3 people in the crop and falsely flags an Overloading violation.
**Solution:**
- *Strict Overlap Filter:* The system only counts a person as a passenger if at least 80% of their bounding box area is inside the motorcycle's box.
- *Posture Differentiation:* YOLO is trained to distinguish between a `rider` (knees bent, sitting) and a `pedestrian` (standing). The counter only tallies `rider` classes.

## 3. The "Occlusion" Problem (Dense Traffic Chaos)
**Challenge:** In heavy Philippine traffic, motorcycles frequently drive side-by-side, causing their bounding boxes to overlap heavily. This causes YOLO to delete one of the boxes (via Non-Maximum Suppression), or causes DeepSORT to swap their Track IDs when they cross paths.
**Solution:**
- *NMS Tuning:* The IoU threshold for NMS is strictly configured to allow high bounding box overlap without triggering deletion.
- *ReID (Visual Memory):* DeepSORT is configured to heavily weigh appearance feature extraction (colors/textures) rather than just physics, so it re-assigns the correct ID to the correct bike after they separate.
- *Fallback Architecture:* If rectangular boxes cause too much cross-contamination, the Primary Anchor model is upgraded to YOLO-Segmentation to use pixel-perfect shrink-wrapped masks instead of squares.

## 4. The "Window Tint" Problem (Visibility Blocking)
**Challenge:** Most vehicles in Zamboanga have heavily tinted windows. The AI cannot see through 5% VLT tint, causing it to blindly guess if a seatbelt is worn or a phone is used, generating massive false positives.
**Solution:** 
- *The Safety Override Gate:* The secondary cabin model is trained to classify the windshield itself (`clear_window`, `open_window`, `tinted_window`). If it detects `tinted_window`, the Python ledger instantly aborts the seatbelt/phone checks to protect system integrity.

## 5. The "Red Light Synchronization" Problem
**Challenge:** Determining exactly when a car runs a red light without unfairly ticketing cars that were already caught inside the intersection during a yellow-to-red transition.
**Solution:**
- *Dual-Tracking Logic:* The system tracks the physical traffic light (using a fixed visual ROI) and the vehicle simultaneously.
- *The Stop Line Tripwire:* An invisible polygon is drawn at the pedestrian lane. A violation is ONLY triggered if the vehicle's DeepSORT vector crosses completely *through* the line while the light status is `RED`. 
- *Grace Period:* If the vehicle's starting bounding box coordinate was already past the line before the light turned red, the system ignores it.

## 6. The "Quick Stop vs. Illegal Park" Problem
**Challenge:** YOLO cannot distinguish between a car stopping for 10 seconds to drop off a passenger and a car illegally parked for 10 minutes, as frozen images look identical.
**Solution:**
- *Spatial-Temporal Stopwatch:* The system relies strictly on DeepSORT. If a car enters the No Parking ROI, it checks for micro-movements. If frame-to-frame displacement is < 5 pixels (to account for camera jitter), speed is registered as 0.
- A Python timer starts for that specific `Track ID`. The violation is only flagged if the timer hits the legally defined threshold (e.g., 180 seconds). The moment the car moves, the timer deletes itself.

## 7. The "Hardware Meltdown" Problem (Computational Overload)
**Challenge:** A Decoupled Pipeline running a Primary YOLO model and 3 Specialist Sub-Models (Helmet, Plate, Cabin) on 10 vehicles in a 30 FPS video requires processing 1,200 crops per second. This will crash any standard GPU.
**Solution:**
- *Interval Checking (Frame Skipping):* Sub-models are explicitly barred from running every frame. Because DeepSORT remembers the vehicle across time, the sub-models are only "injected" once every 15 frames (twice a second).
- *GPU Batching:* When the interval check occurs, all 10 vehicle crops are stacked into a single tensor array and processed simultaneously by the GPU in one pass.
- *Optimal Zone Triggering:* Heavy models (like EasyOCR) only trigger once per vehicle, precisely when the DeepSORT centroid crosses a predefined "optimal clarity line" near the bottom of the camera frame.
