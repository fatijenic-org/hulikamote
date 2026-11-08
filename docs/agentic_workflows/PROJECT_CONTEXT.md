HULI-KAMOTE PROJECT CONTEXT
============================
VERSION: 1.0
MAINTAINED BY: Project Team
DO NOT MODIFY THIS DOCUMENT WITHOUT TEAM APPROVAL.
This is the constant reference document. It does not change session to session.


WHAT THIS PROJECT IS

HULI-KAMOTE is an undergraduate thesis system developed at the College of
Computing Studies in Zamboanga City. It is a computer vision-based traffic
violation detection system designed for non-contact apprehension of road
violators. The name is a play on the Filipino slang "kamote" referring to
reckless or inconsiderate drivers who disregard traffic rules.

The primary focus is model development: training and validating object
detection models that can automatically identify traffic violations from
video footage. Software components (dashboard, backend, visualizer) are
required deliverables but secondary to the detection pipeline.

The end goal is a prototype demonstrating that automated, contactless traffic
violation detection is technically feasible using available local tools,
specifically for Zamboanda City roads and traffic conditions.


TARGET USERS OF THE SYSTEM

1. LTO / Traffic Enforcement Officers: Primary operators. They use the Admin
    Dashboard to review flagged violations, verify evidence, and issue apprehension
    notices without physically being present at the violation site.

2. Motorists and Commuters: Direct beneficiaries. Safer roads and more consistent
    enforcement of traffic rules.

3. College of Computing Studies community: Future researchers who will use this
    thesis as a reference starting point for Philippine traffic detection research.


VIOLATIONS IN SCOPE

Motorcycle violations:
- Counterflow
- Illegal parking
- Illegal turn
- Disregarding signs
- No plate number
- No helmet
- Missing side mirror
- Overloading (too many passengers)

Car violations:
- Counterflow
- Illegal parking
- Illegal turn
- Disregarding signs
- No plate number

Extended violations (stretch goals, lower priority):
- Signal light violation
- Red light running
- Swerving
- No seatbelt
- Pedestrian lane obstruction


THE DETECTION PIPELINE (3 stages)

Stage 1: Single-Frame Object Detection
Tool: YOLO (object detection model)
What it does: Detects and classifies objects in each video frame. Draws
bounding boxes around vehicles, riders, helmets, plates, and signs.
Key logic: Plate detection runs inside the vehicle bounding box. If no plate
is found inside, it flags No Plate Number. Head count inside vehicle bounding
box flags Overloading. Non-Maximum Suppression (NMS) removes duplicate
detections of the same vehicle before passing to Stage 2.

Stage 2: Spatiotemporal Multi-Object Tracking
Tool: DeepSORT algorithm
What it does: Tracks the same vehicle across multiple frames. Assigns a
persistent Track ID to each vehicle even if it briefly disappears. Enables
movement-based violation detection.
Key logic for each violation:
- Counterflow: Compares vehicle movement vector against the legal flow
    direction of the lane. Flags only if sustained over a defined time period
    to avoid false positives from minor swerves.
- Illegal Parking: Detects vehicle remaining stationary inside a restricted
    zone for longer than the defined time threshold.
- Illegal Turn: Detects vehicle trajectory crossing into a prohibited path
    at a defined intersection zone.
- Red Light Running: Detects vehicle crossing the stop line while red light
    timer is active.

Stage 3: License Plate Recognition
Tools: EasyOCR for character recognition, image preprocessing before OCR
What it does: Crops the detected plate zone, applies preprocessing to reduce
motion blur and compression artifacts, then extracts alphanumeric plate
characters. Merges plate string with violation class and DeepSORT Track ID
to produce a complete legal log entry.
If OCR fails to read the plate, it logs "NO PLATE" explicitly rather than
leaving blank, confirming the optical check was performed.


SYSTEM COMPONENTS AND THEIR PURPOSE

hulikamote_backend (FastAPI, Python)
The detection and processing server. Runs on localhost. Hosts the YOLO
inference pipeline, DeepSORT tracking, OCR engine, and database logging.
Connects to the Flutter dashboard via API.

hulikamote_dashboard (Flutter)
The Admin Dashboard used by LTO operators. Three functional areas:
1. Violation Detection Subsystem: Real-time monitoring view with live video
    overlay, bounding boxes color-coded by severity, confidence scores, FPS
    counter, and active vehicle count.
2. Vehicle Identification and Recording Subsystem: Automatically writes
    confirmed violations to database with violation class, timestamp,
    plate string, and Track ID.
3. Results Review Subsystem: Searchable, filterable archive of all logged
    violations. Operators can view evidence frames, metadata, and issue
    apprehension notices. PII masking is applied to comply with RA10173
    (Data Privacy Act).
Additional: Violator Portal where registered motorists can check their
violation records and file appeals. Demerit Point System accumulates per
plate number.

hulikamote_visualizer (Flutter desktop)
NOT part of the main system. This is a supplemental educational tool built
to support thesis defense presentations and explain the AI detection logic to
non-technical audiences such as panel members, teachers, and the general
public. It uses interactive simulations and analogies instead of code or
math. Think of it as an interactive textbook companion to the thesis document.


TECH STACK SUMMARY

Detection model: YOLO (version to be confirmed by team)
Tracking: DeepSORT
OCR: EasyOCR with image preprocessing
Backend: FastAPI (Python)
Frontend dashboard: Flutter
Visualizer: Flutter desktop (Windows)
Database: to be confirmed
Notification: SMTP email server for automated violation notices


EVALUATION METRICS

mAP@50: Primary detection accuracy metric. A detection counts as correct
only if the predicted bounding box overlaps the ground truth by at least 50%.
Logging and Organization Accuracy Rate: Checks whether violation type,
plate result, vehicle identity, and evidence frame are correctly recorded
for a ground-truth event.
False Positive and False Negative rates are tracked separately.
All testing in this study uses pre-recorded footage and controlled video.
Live camera deployment is architecturally supported but not tested in scope.


KEY DEFINITIONS (shorthand for builders)

Kamote: Filipino slang for a reckless driver who ignores traffic rules.
Bounding Box: Rectangle drawn by YOLO around a detected object.
Track ID: Temporary ID DeepSORT assigns to one vehicle for its duration on screen.
Ground Truth: The manually verified correct answer used to measure model accuracy.
NMS: Non-Maximum Suppression. Removes duplicate bounding boxes on the same object.
mAP@50: How well the model finds objects overall, at 50% overlap threshold.
HULI: Filipino word meaning "caught."


SCOPE BOUNDARIES (what this project is NOT)

This is not a live deployed traffic enforcement system.
It is not integrated with LTO databases in production.
It does not use live road cameras during this study.
It does not make autonomous legal decisions. Human operators review all flags.
The visualizer is not part of the main system. It is a presentation aid only.


RESEARCH LOCATION CONTEXT

Zamboanda City, Philippines. Traffic patterns, road markings, and vehicle
types are specific to Philippine road conditions. This affects dataset
collection, model training choices, and the relevance of detected violations.