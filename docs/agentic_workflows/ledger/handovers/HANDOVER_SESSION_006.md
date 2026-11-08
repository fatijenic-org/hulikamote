# HULI-KAMOTE - MASTER HANDOVER
================================
LAST UPDATED: 2026-09-15 by Antigravity (Gemini)

PROJECT LOCATION
hulikamote_visualizer: C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_visualizer
hulikamote_backend:    C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_backend
hulikamote_dashboard:  C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_dashboard
hulikamote_app:        C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_app

STACK
Flutter desktop (Windows primary target)
Dependencies: flutter_math_fork, provider, shared_preferences, go_router, file_picker, web_socket_channel, http
Backend: FastAPI, SQLite, YOLOv8, ONNX, DeepSORT, EasyOCR, OpenCV

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
Red Light Running | Car | DONE       | DONE       | DONE     | DONE         | Dual-ROI spatial conjunction
No Seatbelt       | Car | DONE       | DONE       | DONE     | DONE         | Tinted Window Override Gate (needs trained cabin_specialist.pt)
Crosswalk Obstruct| Car | DONE       | DONE       | DONE     | DONE         | Speed=0 AND Light=RED
Distracted Driving| Car | DONE       | DONE       | DONE     | DONE         | Cabin Specialist (phone detection)
Over-speeding     | EXT | DONE       | DONE       | DONE     | DONE         | Perspective Transform, KPH

MC = Motorcycle/Car, Car = Cars only, EXT = Extended

ACTIVE CHECKLIST
See TODO.md at the root of the project for the master completion checklist covering the Python Backend, Admin Tools, and Flutter Frontend.

BACKEND STATUS
All 3 unit tests passing: test_model_upload.py, test_stream.py, test_violations.py
Active endpoints:
- /auth/login, /upload-model, /violations, /ws/video-feed, /status
- /notifications/register-token, /settings/violations, /settings/mock
- /settings/camera-config, /settings/video/frame, /settings/video/source, /settings/video/info
Decoupled Engine (slicer, registry, ledger, pipeline) fully integrated in: hulikamote_backend/engine
Verified real counterflow detection on test_video.mp4: 55 frames flagged, tickets queued into ledger.

KNOWN ISSUES AND QUIRKS
- Track stability: TrackLedger now allows up to 15 missed frames tolerance before reaping, ensuring track history survives single-frame YOLO occlusions.
- Counterflow dot product threshold: set to < 0.0 (angle > 90° opposing reference vector).
- ROI coordinates: Normalized internally [0.0..1.0], scaled dynamically by actual video resolution (_videoWidth, _videoHeight) when sent to backend.
- Video aspect ratio: Enforced via AspectRatio containers to prevent stretching/flattening.

DESIGN RULES LOCKED IN
- Video Analysis workflow:
  1. Open Video File (native file_picker)
  2. Frame scrubber (real OpenCV extraction via GET /settings/video/frame)
  3. Draw ROIs Fullscreen (InteractiveViewer zoom up to 10x, directional arrow with arrowhead, polygon)
  4. Run Detection (seamless in-place playback with real-time bounding box annotations burned in)
- Monitored zone ROI: When a polygon is drawn, evaluate_counterflow gates strictly via cv2.pointPolygonTest; vehicles outside the polygon are ignored.

NEXT TASK FOR INCOMING BUILDER
1. **Model Training & Specialist Weights Injection:**
   - The decoupled cascading architecture (`pipeline.py`) is complete and tested.
   - Proceed to train the 3 specialist models as specified in `docs/files/AI_ENGINEERING_PLAN.md`:
     1. `helmet_specialist.pt` (Motorcycle rider crops -> with_helmet vs without_helmet)
     2. `plate_specialist.pt` (Vehicle rear/front crops -> license plate bbox for EasyOCR)
     3. `cabin_specialist.pt` (Windshield crops -> seatbelt, phone distraction, tinted window)
   - Export trained weights to ONNX format and place in `hulikamote_backend/models/`.

SESSION LOG HISTORY
See docs/SESSION_LOG.md
