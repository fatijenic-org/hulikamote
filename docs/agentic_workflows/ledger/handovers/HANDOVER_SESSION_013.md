# HULI-KAMOTE - MASTER HANDOVER
================================
LAST UPDATED: 2026-09-23 by Antigravity (Gemini)

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
Red Light Running | Car | DONE       | DONE       | DONE     | DONE         | Dual-ROI spatial conjunction
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
- **[CRITICAL] Forensic Analyzer Model Error:** Starting analysis in forensics crashes/fails due to a missing ONNX model. The backend engine likely cannot find the model path after our categorical folder re-architecture, or the default model string from the UI doesn't match the new subdirectory format.
- **[CRITICAL] FFmpeg Race Condition:** Hot-swapping a video or starting a new detection run in the dashboard triggers an infinite circular loading indicator due to HLSBroadcaster termination conflict.
- **ONNXRuntime & CUDA Mapping:** `onnxruntime-gpu>=1.30.0` has dropped support for CUDA 12.x out-of-the-box on Windows. Peg to `onnxruntime-gpu==1.26.0` to maintain PyTorch `cu121` parity.
- **BasicSR vs Torchvision Failure:** Standard `basicsr` crashes on newer torchvision. Must instantiate `RRDBNet` PyTorch `nn.Module` manually inline to export ESRGAN `.pth` to `.onnx`.
- **Flutter UI Quirks:** Modifying a parent StatefulWidget's variables (like `_tickets` or `_controller`) from a secondary tab breaks tab-isolation. History playback must be handled via distinct routes (`Navigator.push`) with their own `State` classes to prevent wiping out the user's primary workspace.

DESIGN RULES LOCKED IN
- Video Analysis workflow:
  1. Open Video File (native file_picker)
  2. Frame scrubber (real OpenCV extraction via GET /settings/video/frame)
  3. Draw ROIs Fullscreen (InteractiveViewer zoom up to 10x, directional arrow with arrowhead, polygon)
  4. Run Detection (seamless in-place RTSP H.264 playback with real-time JSON bounding box annotations drawn via Flutter CustomPaint)

NEXT TASK FOR INCOMING BUILDER
1. **Implement Training Studio Roadmap Upgrades:**
   - Wait for explicit user authorization before starting.
   - Remaining tasks: Smart History Graph (reading `/report/{model_name}`), Post-Training Report, Syntax Highlighting, Interactive Tooltips, Pop Quiz Ledger, Auto-Verdict System, and Live AI Coach.
2. **Integrate YOLO11 and YOLO26:**
   - Research and inject YOLO26 (NMS-free edge king) and YOLO11. YOLO26 requires modifying the backend to bypass NMS.
3. **Train Custom UK-Specific Plate GAN (Option B):**
   - The user will run the offline training pipeline (`train_lpsrgan.py`) to overwrite the temporary Real-ESRGAN weights.

SESSION LOG HISTORY
See docs/SESSION_LOG.md
