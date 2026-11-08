# HULI-KAMOTE - MASTER HANDOVER
================================
LAST UPDATED: 2026-09-30 by Antigravity

PROJECT LOCATION
hulikamote_visualizer: C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_visualizer
hulikamote_backend:    C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_backend
hulikamote_dashboard:  C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_dashboard
hulikamote_app:        C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_app
training_lab:          C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\training_lab

STACK
Flutter desktop (Windows primary target)
Dependencies: flutter_math_fork, provider, shared_preferences, go_router, file_picker, web_socket_channel, http, media_kit (VLC-based video player)
Backend: FastAPI, SQLite, YOLOv8/11/26, ONNX, DeepSORT, EasyOCR, OpenCV, FFmpeg, MediaMTX
Custom AI Models: Real-ESRGAN / LPSRGAN (Image Enhancement), YOLOv8 Plate Specialist

CURRENT PHASE DEFAULT
home_screen.dart currentPhase = 3 (Modern AI is the default focus)

VIOLATION STATUS TABLE (13 Violations from AI Plan)
Format: violation | cat | p0_old_way | p1_concept | p2_setup | p3_modern_ai | notes

Counterflow       | MC  | DONE       | DONE       | DONE     | DONE         | Ray-casting, flow vector dot product, pointPolygonTest ROI gating
Illegal Parking   | MC  | DONE       | DONE       | DONE     | DONE         | Polygon ROI, Stationary frame accum (5.0s threshold)
No Plate Number   | Car | DONE       | DONE       | DONE     | DONE         | End-to-End ANPR Pipeline (needs trained plate_specialist.pt)
Swerving          | EXT | DONE       | DONE       | DONE     | DONE         | Lateral jerk calculation
Illegal Turn      | MC  | DONE       | DONE       | DONE     | DONE         | Trig angle gating
No Helmet         | MC  | DONE       | DONE       | DONE     | DONE         | Geometric IoU, temporal voting (needs trained helmet_specialist.pt)
Missing Side Mirror| MC | DONE       | DONE       | DONE     | DONE         | Sub-crop, Count < 2 (needs trained cabin_specialist.pt)
Overloading       | MC  | DONE       | DONE       | DONE     | DONE         | 80% overlap, Posture classification
Red Light Running | Car | DONE       | DONE       | DONE     | DONE         | Dual-ROI spatial conjunction (Needs Virtual UI Traffic Simulator)
No Seatbelt       | Car | DONE       | DONE       | DONE     | DONE         | Tinted Window Override Gate (needs trained cabin_specialist.pt)
Crosswalk Obstruct| Car | DONE       | DONE       | DONE     | DONE         | Speed=0 AND Light=RED
Distracted Driving| Car | DONE       | DONE       | DONE     | DONE         | Cabin Specialist (phone detection)
Over-speeding     | EXT | DONE       | DONE       | DONE     | DONE         | Perspective Transform, KPH

MC = Motorcycle/Car, Car = Cars only, EXT = Extended

ACTIVE CHECKLIST
See TODO.md at the root of the project for the master completion checklist covering the Python Backend, Admin Tools, and Flutter Frontend.

BACKEND STATUS
All 4 unit test suites passing (15/15 tests).
Active endpoints:
- /auth/login, /upload-model, /violations, /ws/video-feed, /status
- /notifications/register-token, /settings/violations, /settings/mock
- /settings/camera-config, /settings/video/frame, /settings/video/source, /settings/video/info
Decoupled Engine (slicer, registry, ledger, pipeline) fully integrated in: hulikamote_backend/engine
Model Organization: Physical category folders (Vehicle Detectors, Plate Models, GAN Enhancers).

KNOWN ISSUES AND QUIRKS
- **[CRITICAL] Memory Rule:** Never implement new modules or execute training runs without explicit instruction from the user. (Wait for commands after fixes).
- **ONNXRuntime & CUDA Mapping:** `onnxruntime-gpu>=1.30.0` has dropped support for CUDA 12.x out-of-the-box on Windows. Peg to `onnxruntime-gpu==1.26.0` to maintain PyTorch `cu121` parity.
- **BasicSR vs Torchvision Failure:** Standard `basicsr` crashes on newer torchvision. Must instantiate `RRDBNet` PyTorch `nn.Module` manually inline to export ESRGAN `.pth` to `.onnx`.
- **Flutter UI Quirks:** Modifying a parent StatefulWidget's variables (like `_tickets` or `_controller`) from a secondary tab breaks tab-isolation. History playback must be handled via distinct routes (`Navigator.push`) with their own `State` classes to prevent wiping out the user's primary workspace.

DESIGN RULES LOCKED IN
- **Tracker Config Locked:** `tracker.py` DeepSORT hyperparameter matrix is maxed out mathematically. Do not attempt to tune. Focus moves to ReID model replacement if tracking needs improvement.
- **2D BBox Spatial Projection:** Vehicle mapping is strictly anchored at the bottom-center of the bounding box (`cy = y + h`) to perfectly map the tires to the 2D pavement polygons drawn in the UI.
- **Evidence Throttler Safety:** `pipeline.py` evidence capture is throttled, but it MUST guarantee a snapshot on Frame 1 (`_evidence_counter == 1`) to prevent race conditions on fast-moving violators dropping frames before OCR can extract the plate.
- **Dataset Synchronization:** Inline Pop Quiz buttons in the Forensic Analyzer (True/False Positive) automatically push the image context and corrected strings back to the SQLite Vault for dataset accumulation.

NEXT TASK FOR INCOMING BUILDER
1. **Execute the Phased AI Roadmap (docs/AI_ROADMAP_PLAN.md):**
   - Phase 1: Support user in Active Data Harvesting (do not train yet, collect TP/FP data first).
   - Phase 2: Fine-tune YOLO plate_specialist and OCR.
   - Phase 3: Build the Virtual Traffic Light Simulator Widget in the UI to test Red Light violations.
   - Phase 4: Download Open-Source datasets to bootstrap Helmet/Phone specialist training.
   - Phase 5: Expose FastAPI REST endpoints (`GET /api/citizen/tickets`) to link the existing Flutter Mobile App.
   - **WAIT FOR EXPLICIT INSTRUCTION BEFORE STARTING ANY OF THESE PHASES.**

SESSION LOG HISTORY
See docs/SESSION_LOG.md
