# Project Progress Summary (Since August 25, 2026)

**Repository:** `huli-kamote`  
**Generated Date:** September 17, 2026  
**Reference Range:** `226dd8d` (2026-08-25) to Present  

---

## Executive Overview

Since August 25, 2026, the `huli-kamote` platform transitioned from a set of proof-of-concept prototypes into a cohesive, high-performance, multi-module intelligent traffic enforcement system. The work spans four primary subsystems:

1. **Backend Engine (`hulikamote_backend`):** Full Decoupled Cascading Pipeline architecture, GPU ONNX acceleration, dynamic multi-zone ROI enforcement, plate detection optimizations, and 1080p stream performance downscaling.
2. **Dashboard Application (`hulikamote_dashboard`):** Complete offline video ingestion workstation, multi-zone ROI drawing wizard, dynamic ONNX model switching, and real-time WebSocket alert ingestion.
3. **Educational Visualizer (`hulikamote_visualizer`):** Interactive 5-step learning suite spanning 13 traffic violations, comparing naive classical computer vision against the modern AI pipeline.
4. **Mobile Citizen Application (`hulikamote_mobile`):** Ticket appeals workflow, citizen violation notices, real-time push notifications, and authentication integration.

---

## 1. Timeline of Milestones & Major Commits

### Phase A: Mobile App Appeals & Core Integrations (Aug 25 – Sep 03, 2026)
* **API & Network Layer:** Refactored endpoint configurations to support unified local backend connections; replaced remote network image placeholders with resilient offline assets (`3b2f89f`).
* **Platform Support:** Configured multi-platform desktop (Windows x64) and Web targets for the visualizer framework (`7132017`).
* **Mobile Citizen Shell:** Implemented core citizen navigation shell, ticket appeal submissions, violation notice browsing, and profile management (`40b0a3c`, `83779a0`).

### Phase B: Architecture Transition — The Decoupled Cascading Pipeline (Sep 09 – Sep 11, 2026)
* **Backend Pipeline Core:** Introduced `DecoupledPipeline`, `ActiveLedgerManager`, and `NumpySlicer`. Decoupled primary vehicle anchor detection from specialist safety equipment inspection (`fa4e705`, `bd72c60`).
* **Enforcer Inbox & Review:** Implemented enforcer verification inbox with high-resolution violation proof timelines, status transitions (Pending $\rightarrow$ Verified $\rightarrow$ Dismissed), and snapshot archiving (`2aa6ee4`, `6ee7671`).
* **OCR & Specialist Integration:** Connected `plate_specialist.onnx` and `helmet_specialist.onnx` into the pipeline. Configured automatic plate text extraction using EasyOCR (`14e8635`, `ff3fe62`, `50ef24f`).
* **Specialist Training Lab:** Created an automation toolchain and desktop training GUI for fine-tuning secondary YOLO specialist models (`b48b288`, `21abc5c`).

### Phase C: Educational Visualizer Expansion (Sep 11 – Sep 14, 2026)
* **Modular Interactive Visualizers:** Created 4-phase and 5-phase interactive simulations for:
  * Motorcycle violations: *No Helmet*, *Missing Side Mirror*, *Overloading*, *Counterflow*.
  * Vehicle violations: *Illegal Parking*, *No Plate*, *Red Light Running*, *No Seatbelt*, *Crosswalk Obstruction*, *Distracted Driving*.
  * Extended highway violations: *Swerving*, *Overspeeding*, *Illegal Turn*.
* **Interactive Controls:** Integrated virtual vehicle steering, joystick controllers, dynamic road polygons, and real-time dot product math engines (`15559f5`, `518d2c0`, `213177f`).

### Phase D: Offline Video Analysis & Multi-Zone ROI (Sep 15 – Sep 16, 2026)
* **Offline Video Scrubber:** Built an inspection interface with frame-accurate video seeking (`/settings/video/frame`) and video metadata probes (`/settings/video/info`) (`59d886c`, `40f5aae`).
* **Zoomable ROI Canvas:** Implemented an interactive canvas tool for enforcers to draw custom polygon boundaries and legal flow directional arrows directly over video frames (`5ab20ea`, `b60ce0b`).
* **Multi-Zone ROI Backend Support:** Refactored `camera_config.json` and backend gating to support multiple concurrent counterflow and illegal parking zones with individual vector constraints (`71af313`, `f0bc7e3`).
* **Dynamic Model Switching:** Added runtime ONNX model switching (`/settings/model`), allowing enforcers to toggle between different YOLOv8 model variants without restarting the server (`b296852`, `ee20c89`).

### Phase E: Production Hardening, Lag Optimization & Code Visualizer (Sep 16 – Sep 17, 2026)
* **1080p Video Lag Elimination:** Resolved high-resolution video stutter by enforcing `MAX_PROCESSING_HEIGHT = 720` downscaling in `stream.py`, cutting CPU copy and JPEG encoding overhead by over 50% while preserving YOLO accuracy.
* **Tracker Race Condition & CUDA 700 Fix:** Enforced single-threaded execution (`_PIPELINE_EXECUTOR`) across all stream pipeline calls, eliminating race conditions in `SimpleIoUTracker.tracks` and preventing GPU CUDA illegal memory access crashes.
* **License Plate Specialist Tuning:**
  * Lowered specialist inference interval from 15 frames down to 5 frames.
  * Optimized crop geometry to isolate the bottom 40% bumper region rather than squashing the entire vehicle.
  * Adjusted detection confidence threshold to 0.35 and added a consecutive-miss safety counter to eliminate false positives.
* **Resolution-Agnostic ROI Coordinate Scaling:** Integrated `video_native_width`/`height` tracking with runtime coordinate normalization (`_get_scaled_rois`), ensuring polygon checks align accurately regardless of frame downscaling.
* **5-Step Code & Math Visualizer:** Fully populated Tab 1 (Raw Code & Math) with custom naive brute-force implementations, layman explanations, mathematical analogies, real-world failure modes, and modern AI optimization solutions across all 13 violations.

---

## 2. Comprehensive Module Changelog

| Subsystem | Area | Key Additions / Improvements |
| :--- | :--- | :--- |
| **Backend** | `engine/pipeline.py` | Added runtime ROI polygon scaling (`_get_scaled_rois`), consecutive-miss plate checking, bumper sub-cropping, and multi-model injection. |
| **Backend** | `routers/stream.py` | Implemented `MAX_PROCESSING_HEIGHT = 720`, dedicated single-threaded `ThreadPoolExecutor`, and WebSocket client management. |
| **Backend** | `engine/ledger.py` | Vector dot-product counterflow math ($\vec{V} \cdot \vec{R} < 0$), stationarity variance counter, evidence frame throttle, and ticket finalizer. |
| **Backend** | `tracker.py` | IoU greedy tracker with age-out thresholds and persistent track identity assignment. |
| **Dashboard** | `offline_video_screen.dart` | Integrated multi-zone ROI wizard, video frame scrubber, model selector dropdown, and independent plate detection toggle. |
| **Dashboard** | `violation_wizard_dialog.dart` | Multi-step dialog supporting step-by-step polygon drawing, arrow orientation, time limit thresholding, and zone reviews. |
| **Dashboard** | `inbox_screen.dart` | Enforcer verification table with proof carousel, driver details, plate numbers, and status review controls. |
| **Visualizer** | `code_math_visualizer.dart` | Step-by-step code walkthroughs for all 13 violations comparing naive classical logic with AI pipeline optimizations. |
| **Visualizer** | `screens/home_screen.dart` | 5-tab educational journey navigation (Raw Code, Naive Sim, Core Concept, Real-World Setup, Modern AI). |
| **Mobile** | `screens/appeals` | Citizen ticket appeal filing with image attachments and status tracking. |

---

## 3. Current Git State & Stability

* **Branch:** `nekolaiv/polishing-progress`
* **Safe Rollback Checkpoint:** `backup/pre-optimization-stable` (`838cac2`)
* **Verification Status:**
  * Backend: Clean startup on Python 3.10+ with CUDA Execution Provider active.
  * Dashboard: Flutter analysis verified clean.
  * Visualizer: Flutter analysis verified clean with all 13 violation cases compiled.
