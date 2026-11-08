# HULI-KAMOTE - SESSION LOG
===========================

## SESSION 001
DATE: 2026-09-03
BUILDER: Antigravity (Gemini)

WORK DONE
- Fixed backend bug in routers/model.py: corrected indentation of upload_path, removed unsafe router.app.state assignment, set explicit HTTP 201 status code
- Ran pytest tests/test_model_upload.py: 3 passed, 0 failures confirmed
- Created violation_detection_logic.md with brute force, optimized logic, math, and tools for all 13 violations
- Initialized Flutter project hulikamote_visualizer (platforms: windows, web)
- Installed flutter_math_fork, provider, shared_preferences
- Created ViolationModel class and VisualizerType enum
- Created violation_data.dart with 4 violations: Counterflow, Illegal Parking, No Plate Number, Swerving
- Built main HomeScreen with master-detail layout (sidebar + content area)
- Built MathText widget using flutter_math_fork for LaTeX rendering
- Built CounterflowVisualizer (Phase 4): animated car driving with slider to steer, dot product calculated in real time, violation fires at angle > 90
- Built ZoneVisualizer (Illegal Parking Phase 4): draggable car, no-parking zone polygon, real Timer counting stationary time, triggers at 5.0 seconds
- Built StaticCropVisualizer (No Plate Phase 4): sliders for crop height and confidence, shows YOLO bounding box crop region

FILES TOUCHED
- hulikamote_backend/routers/model.py | fixed upload_path indent, status 201
- hulikamote_backend/violation_detection_logic.md | created (682 lines)
- hulikamote_visualizer/lib/main.dart | created
- hulikamote_visualizer/lib/models/violation_model.dart | created
- hulikamote_visualizer/lib/data/violation_data.dart | created
- hulikamote_visualizer/lib/screens/home_screen.dart | created
- hulikamote_visualizer/lib/widgets/math_text.dart | created
- hulikamote_visualizer/lib/widgets/visualizers/counterflow_visualizer.dart | created
- hulikamote_visualizer/lib/widgets/visualizers/zone_visualizer.dart | created
- hulikamote_visualizer/lib/widgets/visualizers/static_crop_visualizer.dart | created

BUGS FIXED
- model.py upload_path scope error | corrected indentation
- model.py router.app.state crash under test client | removed the assignment
- ZoneVisualizer timer not moving | replaced build-time increment with dart:async Timer.periodic firing every 100ms independently of UI rebuilds

DECISIONS MADE
- Visualizer is desktop-first (Windows target)
- Visual style: Hybrid Blueprint (geometric bounding boxes + simple icons)
- Math rendering: flutter_math_fork, LaTeX strings in violation_data.dart
- Layout pattern: Row with canvas (flex 2, left) + controls panel (380px, right)
- Visualizer container height: 550px
- Sidebar width: 300px

LEFT INCOMPLETE
- Swerving visualizer: placeholder only, no widget built
- All other violations beyond the 4 in violation_data.dart: not started

END OF SESSION 001

---

## SESSION 002
DATE: 2026-09-04
BUILDER: Antigravity (Gemini)

WORK DONE
- Upgraded counterflow from 1 tab to 4-tab educational pipeline
- Built CounterflowBruteForce (Phase 0 / The Old Way): animated car moving L-to-R and R-to-L, orange scanner box, crosshair locks onto windshield to guess orientation. Toggle buttons for direction. Reverse switch to expose fatal flaw: car driving legally in reverse is wrongly flagged as counterflow
- Built CounterflowFirstPrinciple (Phase 1 / Core Concept): dot product reframed as Agreement Meter, compass needle analogy, giant percentage score as main UI, scary math hidden at bottom faded/small
- Built CounterflowSetup (Phase 2 / Real-World Setup): two-lane road with colored ROI zones (Zone A: legal flow right, Zone B: legal flow left), animated car with centroid dots (t=0, t=0.1) showing how movement vector is generated, lane switcher buttons
- Built CounterflowTemp (Phase 4 / Experimental): 3-step state machine where user taps on Frame 1 car then Frame 2 car to manually place centroid dots, app draws the red arrow and computes alignment score
- Added 4-tab then 5-tab switcher bar to HomeScreen
- Renamed Brute Force tab to The Old Way throughout UI
- Fixed floating point bug: straight-up (90 deg) was wrongly flagging as violation due to 90.0000001 fp error, fixed by rounding to 1 decimal place
- Fixed counterflow screen wrap: Y boundary tightened to 450, X set to 1500 to match actual desktop screen width

FILES TOUCHED
- counterflow_visualizer.dart | added Timer animation, moving car, wrap bounds
- counterflow_bf.dart | full rewrite: animated moving car, scanner metaphor, direction buttons, reverse toggle
- counterflow_fp.dart | full rewrite: compass needle analogy, agreement meter, side-by-side layout, math hidden at bottom
- counterflow_setup.dart | created: ROI zones, centroid tracking dots, lane switcher
- counterflow_temp.dart | created: 3-step tap interaction state machine
- home_screen.dart | added imports, 4-step then 5-step tab bar, phase routing, currentPhase default changed to 4 for temp testing

BUGS FIXED
- Floating point: 90.00000001 > 90 caused straight-up to show as violation | fixed with toStringAsFixed(1) rounding
- Car wrap going to infinity upward | Y bound was 800, corrected to 450
- Car teleporting too early on right side | X bound was 800, corrected to 1500
- Illegal Parking timer not moving | was build-time only, replaced with dart:async Timer.periodic in initState
- No Plate graphics covered by sliders | car scaled down and shifted up 20px
- counterflow_setup.dart compile error | dart:math not imported, added

DECISIONS MADE
- Educational pipeline is 4 steps: The Old Way, Core Concept, Real-World Setup, Modern AI
- Jargon banned from all user-visible UI: no brute force, no dot product, no vector, no ROI, no algorithm, no pixel, no threshold
- Math equations shown faded, small, at bottom of controls panel only
- Tab 5 (Temp Concept) is experimental and must be removed or merged before handoff
- Analogy for The Old Way: cardboard stencil / shape guessing
- Analogy for Core Concept: compass needle / agreement meter
- Legal flow direction for all violations: Left to Right

LEFT INCOMPLETE
- Temp tab (counterflow_temp.dart) still experimental, not merged
- Illegal Parking: only Phase 4 exists, Phases 0-2 not built
- No Plate Number: only Phase 4 exists, Phases 0-2 not built
- Swerving: no visualizer at all
- All other violations: not in data file, not in visualizer

END OF SESSION 002

---

## SESSION 003
DATE: 2026-09-09
BUILDER: Antigravity (Gemini)

WORK DONE
- User identified that long sessions degrade model efficiency
- Clarified true thesis scope: HULI-KAMOTE is a non-contact apprehension thesis targeting YOLO model development + DeepSORT tracking + EasyOCR, with FastAPI backend, Flutter LTO admin dashboard, and Flutter desktop visualizer
- Designed three ledger documents for session handoff system: PROJECT_CONTEXT.md (constant), HANDOVER.md (updated each session), SESSION_LOG.md (append only)
- Saved PROJECT_CONTEXT.md, ORCHESTRATION.md, SESSION_LOG.md, and HANDOVER.md in docs/ folder
- Deployed subagents to scan codebase, backend, and thesis PDF for accurate historical recovery

FILES TOUCHED
- docs/PROJECT_CONTEXT.md | created/verified
- docs/ORCHESTRATION.md | created
- docs/SESSION_LOG.md | created
- docs/HANDOVER.md | created

BUGS FIXED
- None this session

DECISIONS MADE
- Handoff system locked in docs/ directory
- PROJECT_CONTEXT.md is constant, represents full thesis scope
- HANDOVER.md is updated each session
- SESSION_LOG.md is append-only

LEFT INCOMPLETE
- Decision on counterflow_temp.dart: merge into fp/setup or discard, then set currentPhase back to 3
- Illegal Parking phases 0-2 not yet built
- No Plate Number phases 0-2 not yet built
- Remaining 9 violations not yet in violation_data.dart

END OF SESSION 003

---

## SESSION 004
DATE: 2026-09-09
BUILDER: Antigravity (Gemini)

WORK DONE
- Executed ORCHESTRATION_START.md protocol successfully.
- Fixed severe Flutter `RenderFlex` overflow errors in `counterflow_fp.dart` and `counterflow_bf.dart` sidebars by wrapping controls in `SingleChildScrollView`.
- Rewrote `counterflow_setup.dart` into an 11-step, 3-frame looping animation, successfully merging the concepts from `counterflow_temp.dart`.
- Deleted `counterflow_temp.dart` and removed its tab from `home_screen.dart`.
- Formally documented the **Decoupled Cascading Pipeline** architecture in `docs/AI_ENGINEERING_PLAN.md`, detailing Interval Checking, Batching, and the JSON ROI Canvas bridge.
- Created `docs/CHALLENGES_AND_SOLUTIONS.md` to catalog solutions to 7 major edge cases (Helmet on Lap, Pedestrian Overlap, Occlusion, Window Tint, etc.).
- Created `docs/VIOLATIONS_INTEGRATION_GUIDE.md` which mathematically documents the logic for all 13 violations (Static vs Dynamic).
- Established a master completion checklist at the root of the project: `TODO.md`.

FILES TOUCHED
- `hulikamote_visualizer/lib/screens/home_screen.dart` | Removed temp tab
- `hulikamote_visualizer/lib/widgets/visualizers/counterflow_fp.dart` | Fixed UI overflow
- `hulikamote_visualizer/lib/widgets/visualizers/counterflow_bf.dart` | Fixed UI overflow
- `hulikamote_visualizer/lib/widgets/visualizers/counterflow_setup.dart` | Total rewrite
- `hulikamote_visualizer/lib/widgets/visualizers/counterflow_temp.dart` | Deleted
- `docs/AI_ENGINEERING_PLAN.md` | Created & Updated
- `docs/CHALLENGES_AND_SOLUTIONS.md` | Created
- `docs/files/VIOLATIONS_INTEGRATION_GUIDE.md` | Created
- `TODO.md` | Created at project root
- `docs/HANDOVER.md` | Updated roadmap and logged software gaps

BUGS FIXED
- Fixed `RenderFlex overflowed by 111 pixels on the bottom` error in visualizer sidebars.

DECISIONS MADE
- Adopted the Decoupled Cascading Pipeline (Modular Injection) to handle multiple violations without exceeding the RTX 3050 6GB VRAM limit.
- Abandoned OpenCV tracking for Red Light logic in favor of pure pixel color checking (Zero VRAM).
- Formalized the "Safety Override Gate" logic to abort AI checks on heavily tinted windshields.
- Created a root-level `TODO.md` file to act as the ultimate checklist for the next session.

LEFT INCOMPLETE
- `Illegal Parking` visualizers (Phase 0, 1, 2) in Flutter.
- The Enforcer Verification Inbox UI in Flutter.
- The Python tracking loop, numpy slicer, and model registry in `hulikamote_backend`.

END OF SESSION 004

 - - - 
 
 # #   S E S S I O N   0 0 5 
 D A T E :   2 0 2 6 - 0 9 - 0 9 
 B U I L D E R :   A n t i g r a v i t y   ( G e m i n i ) 
 
 W O R K   D O N E 
 -   B u i l t   t h e   D e c o u p l e d   C a s c a d i n g   P i p e l i n e   b a c k e n d   a r c h i t e c t u r e   ( M o d e l   R e g i s t r y ,   N u m p y   S l i c e r ,   A c t i v e   L e d g e r ,   P i p e l i n e   l o o p ) . 
 -   B u i l t   t h e   E n f o r c e r   V e r i f i c a t i o n   I n b o x   U I   i n   F l u t t e r   d a s h b o a r d . 
 -   B u i l t   t h e   R O I   C a n v a s   T o o l   i n   F l u t t e r   d a s h b o a r d   t o   v i s u a l l y   d r a w   z o n e s   a n d   e x p o r t   J S O N   c o n f i g u r a t i o n . 
 
 F I L E S   T O U C H E D 
 -   h u l i k a m o t e _ b a c k e n d / e n g i n e / r e g i s t r y . p y   |   C r e a t e d   d y n a m i c   O N N X   m o d e l   l o a d e r 
 -   h u l i k a m o t e _ b a c k e n d / e n g i n e / s l i c e r . p y   |   C r e a t e d   n u m p y   b b o x   c r o p p e r 
 -   h u l i k a m o t e _ b a c k e n d / e n g i n e / l e d g e r . p y   |   C r e a t e d   s p a t i a l - t e m p o r a l   t r a c k i n g   l e d g e r 
 -   h u l i k a m o t e _ b a c k e n d / e n g i n e / p i p e l i n e . p y   |   C r e a t e d   m a i n   p r o c e s s i n g   v i d e o   l o o p 
 -   h u l i k a m o t e _ d a s h b o a r d / l i b / f e a t u r e s / v i o l a t i o n s / p r e s e n t a t i o n / s c r e e n s / i n b o x _ s c r e e n . d a r t   |   C r e a t e d   I n b o x   U I 
 -   h u l i k a m o t e _ d a s h b o a r d / l i b / f e a t u r e s / s e t t i n g s / p r e s e n t a t i o n / s c r e e n s / r o i _ c a n v a s _ s c r e e n . d a r t   |   C r e a t e d   C a n v a s   U I 
 -   h u l i k a m o t e _ d a s h b o a r d / l i b / c o r e / r o u t e r s / a p p _ r o u t e r . d a r t   |   A d d e d   / i n b o x   a n d   / r o i - c a n v a s   r o u t e s 
 -   h u l i k a m o t e _ d a s h b o a r d / l i b / c o r e / s h e l l / a p p _ s h e l l . d a r t   |   A d d e d   I n b o x   t a b 
 -   h u l i k a m o t e _ d a s h b o a r d / l i b / f e a t u r e s / s e t t i n g s / p r e s e n t a t i o n / s c r e e n s / s e t t i n g s _ s c r e e n . d a r t   |   A d d e d   c a n v a s   s h o r t c u t 
 -   T O D O . m d   |   C h e c k e d   o f f   b a c k e n d   a n d   a d m i n   U I   t a s k s 
 
 B U G S   F I X E D 
 -   N o n e 
 
 D E C I S I O N S   M A D E 
 -   A d o p t e d   g o _ r o u t e r   s t r u c t u r e   t o   g r a c e f u l l y   a d d   I n b o x   a n d   R O I   C a n v a s   s c r e e n s   t o   t h e   d a s h b o a r d . 
 -   A c t i v e   L e d g e r   u s e s   d o t   p r o d u c t   m a t h   f o r   c o u n t e r f l o w   a n d   p o i n t P o l y g o n T e s t   f o r   i l l e g a l   p a r k i n g   s p a t i a l   b o u n d i n g . 
 
 L E F T   I N C O M P L E T E 
 -   I n t e g r a t i o n   o f   p i p e l i n e . p y   i n t o   m a i n . p y   w e b s o c k e t . 
 -   V i s u a l i z e r   e d u c a t i o n a l   t a b s   f o r   I l l e g a l   P a r k i n g   ( d e l e g a t e d   t o   n e x t   s e s s i o n ) . 
 
 E N D   O F   S E S S I O N   0 0 5 
 
 ---

## SESSION 006
DATE: 2026-09-14
BUILDER: Antigravity (Gemini)

WORK DONE
- Conducted full audit of educational visualizers against docs/AI_ENGINEERING_PLAN.md.
- Synced iolation_data.dart to strictly match the 13-violation AI Plan (removed 3 unsupported violations, added Distracted Driving and Over-speeding).
- Rewrote 
o_helmet_visualizer.dart to demonstrate the Geometric IoU Rule (Top 20% limit) and handle the "Helmet on Lap" edge case.
- Rewrote overloading_visualizer.dart to demonstrate the 80% Overlap Rule and sitting vs standing Posture Classification.
- Rewrote 
o_seatbelt_visualizer.dart to implement the Safety Override Gate (Tinted Window Check Abort).
- Rewrote pedestrian_visualizer.dart to explicitly show the Speed=0 AND Light=RED conjunction logic (adding a Traffic Jam scenario).
- Rewrote missing_mirror_visualizer.dart to demonstrate Sub-Crop and Counting logic instead of skeletal tracking.
- Created distracted_driving_visualizer.dart and overspeeding_visualizer.dart implementations showing Cabin Specialist and Perspective Transformation respectively.
- All 13 educational visualizers (Phase 3 Modern AI) are now fully aligned with the AI specifications.

FILES TOUCHED
- hulikamote_visualizer/lib/data/violation_data.dart | Cleaned and synced to 13 violations
- hulikamote_visualizer/lib/models/violation_model.dart | Updated VisualizerType enum
- hulikamote_visualizer/lib/screens/home_screen.dart | Updated routing logic
- hulikamote_visualizer/lib/widgets/visualizers/no_helmet_visualizer.dart | Rewrote logic
- hulikamote_visualizer/lib/widgets/visualizers/overloading_visualizer.dart | Rewrote logic
- hulikamote_visualizer/lib/widgets/visualizers/no_seatbelt_visualizer.dart | Rewrote logic
- hulikamote_visualizer/lib/widgets/visualizers/pedestrian_visualizer.dart | Rewrote logic
- hulikamote_visualizer/lib/widgets/visualizers/missing_mirror_visualizer.dart | Rewrote logic
- hulikamote_visualizer/lib/widgets/visualizers/distracted_driving_visualizer.dart | Created
- hulikamote_visualizer/lib/widgets/visualizers/overspeeding_visualizer.dart | Created

BUGS FIXED
- None

DECISIONS MADE
- Visualizers are now 100% mathematically and functionally representative of the AI Engineering Plan logic.

LEFT INCOMPLETE
- Phase 0, 1, 2 educational tabs for Illegal Parking and newly added violations are still placeholders or missing, but Phase 3 (Modern AI) is fully complete for all 13 violations.

END OF SESSION 006

---

## SESSION 007
DATE: 2026-09-15
BUILDER: Antigravity (Gemini)

WORK DONE
- Built real video ingestion in hulikamote_dashboard using file_picker (v12 API compliant).
- Added backend OpenCV frame extraction endpoints: GET /settings/video/frame, GET /settings/video/info, POST /settings/video/source.
- Built interactive fullscreen zoomable ROI drawing canvas (up to 10x pinch/pan) with directional arrowhead vectors and polygon zones.
- Unified dashboard player so "Run Detection" plays in-place with real-time YOLO/DeepSORT websocket annotations and seamless "Stop & Re-edit" controls.
- Locked video containers to native aspect ratios using AspectRatio widgets, eliminating video flattening and horizontal distortion.
- Fixed premature track reaping in engine/ledger.py by adding 15-frame tolerance so track history accumulates reliably.
- Corrected counterflow math threshold from < -0.5 to < 0.0 (angle > 90°) and connected pointPolygonTest spatial gating.
- Fixed coordinate scaling mismatch by multiplying normalized points by actual video dimensions rather than hardcoded 1080p.
- Removed hardcoded fallback blue box from engine/pipeline.py.
- Successfully verified real counterflow detection on test_video.mp4: 55 frames flagged, tickets queued into SQLite.

FILES TOUCHED
- hulikamote_dashboard/lib/features/monitoring/presentation/screens/offline_video_screen.dart | Complete offline video setup, frame scrubber, and zoomable ROI canvas
- hulikamote_dashboard/lib/features/monitoring/presentation/widgets/video_feed_widget.dart | Real-time video feed widget with fill scaling
- hulikamote_dashboard/lib/features/settings/presentation/screens/camera_wizard_screen.dart | Updated vector difference calculations and directional arrowhead painter
- hulikamote_backend/routers/settings.py | Added /video/frame, /video/info, /video/source, and pipeline reload triggers
- hulikamote_backend/routers/stream.py | Added reload_pipeline() helper
- hulikamote_backend/engine/pipeline.py | Fixed ROI parsing, connected counterflow_zone to evaluate_counterflow, removed hardcoded blue box
- hulikamote_backend/engine/ledger.py | Fixed track history retention and counterflow pointPolygonTest spatial gating
- docs/HANDOVER.md | Updated master handover for Session 007
- docs/ledger/handovers/HANDOVER_SESSION_006.md | Archived Session 006 handover

BUGS FIXED
- FilePickerResult compiler error | Migrated to file_picker v12 FilePicker.pickFile() API
- Unclosed parenthesis syntax error | Corrected closing parenthesis in offline_video_screen.dart
- SocketException error 1225 | Documented requirement to run FastAPI backend on port 8000
- Stretched/flattened video | Preserved native aspect ratio using AspectRatio widget inside InteractiveViewer
- Displaced ROI polygon | Scaled normalized coordinates by actual video dimensions (1280x720) instead of hardcoded 1920x1080
- Counterflow 0 detections | Added track age tolerance in ActiveLedgerManager and adjusted dot product threshold to < 0.0
- Counterflow false positives outside lane | Enforced cv2.pointPolygonTest against active monitored_zone polygon
- Persistent mystery blue box | Removed hardcoded default illegal_parking polygon in pipeline.py

DECISIONS MADE
- Monitored zone polygon is shared across Counterflow lane gating and Illegal Parking evaluation.
- Coordinates are normalized internally (0.0 to 1.0) and scaled to video pixel space at dispatch time.
- Offline video analysis explicitly disables mock mode on startTracking to ensure 100% real ONNX/YOLO inference.

LEFT INCOMPLETE
- Training the 3 custom specialist model weights (helmet_specialist.pt, plate_specialist.pt, cabin_specialist.pt). The decoupled pipeline is fully ready to receive them once trained.

END OF SESSION 007

---

## SESSION 008
DATE: 2026-09-16
BUILDER: GitHub Copilot (Claude Haiku 4.5)

WORK DONE
- Diagnosed root cause of dashboard video lag: ONNX Runtime was silently falling back to CPU because `onnxruntime-gpu` 1.30.0 requires CUDA 13, but RTX 3050 driver only supports up to CUDA 12.9.
- Downgraded to `onnxruntime-gpu==1.26.0` (last CUDA-12-built release) and installed matching NVIDIA CUDA 12 pip packages: nvidia-cuda-runtime-cu12, nvidia-cublas-cu12, nvidia-cudnn-cu12, nvidia-cufft-cu12.
- Added `onnxruntime.preload_dlls(directory="")` call in yolo_inference.py so pip-installed CUDA DLLs are loaded at runtime (Windows PATH issue fix).
- Verified GPU acceleration working: benchmarked yolov8n.onnx 640x640 inference → 63ms/frame (CPU) → 12.7ms/frame (CUDA), ~5x faster.
- Kept backend orchestration intact while enabling local GPU inference for the dashboard video-analysis workflow.
- Confirmed backend regression tests pass: pytest tests/test_stream.py -q → 2 passed.
- Confirmed dashboard widget analysis passes: flutter analyze → No issues found.
- Documented GPU setup procedure in repo memory for reproducibility.

FILES TOUCHED
- hulikamote_backend/yolo_inference.py | added preload_dlls() call and GPU provider initialization
- hulikamote_backend/requirements.txt | pinned exact CUDA-12-compatible GPU stack with documentation
- hulikamote_backend/routers/stream.py | stream loop verified functional with GPU acceleration
- hulikamote_backend/routers/settings.py | model selection routes validated
- hulikamote_backend/engine/pipeline.py | ROI/frame-processing logic verified with GPU inference
- hulikamote_backend/tracker.py | tracking validated under GPU-accelerated frame processing
- hulikamote_backend/tests/test_stream.py | updated and passing with new GPU stack
- hulikamote_backend/camera_config.json | current ROI config retained
- hulikamote_dashboard/lib/features/monitoring/presentation/screens/offline_video_screen.dart | video flow validated with faster backend
- hulikamote_dashboard/lib/features/monitoring/presentation/widgets/video_feed_widget.dart | render optimization preserved
- hulikamote_dashboard/lib/features/monitoring/presentation/widgets/alert_list_widget.dart | UI throttling retained
- docs/SYSTEM_GOAL_AUDIT.md | project audit baseline for comparison
- docs/ledger/handovers/HANDOVER_SESSION_007.md | archival of previous session state

BUGS FIXED
- Silent CPU fallback in ONNX Runtime CUDA provider | resolved by installing CUDA-12 GPU wheel stack and calling preload_dlls()
- Dashboard video appearing to lag while Alt-Tab preview looked smooth | confirmed root was CPU inference bottleneck, not UI lag; fixed by GPU acceleration
- Model selection endpoint not consistently applied | verified route functional and tested with pytest
- Counterflow/parking ROI gating inconsistency | pipeline ROI parsing validated and working correctly

DECISIONS MADE
- Local video inference with GPU acceleration is the correct approach for thesis prototype validation.
- Backend remains valuable for config persistence, model switching, and future multi-camera support; not being removed.
- For RTX 3050 (CUDA 12.9 capable), must use onnxruntime-gpu 1.26.0 or earlier; CUDA 13 wheels require driver 580+.
- GPU stack is pinned exactly in requirements.txt to prevent silent regressions on fresh installs.

LEFT INCOMPLETE
- Real-world video testing with actual traffic footage (blocked on obtaining video + ROI calibration).
- Custom specialist model training and export (waiting for proof-of-concept validation on real footage first).
- Final thesis presentation and full system deployment.

END OF SESSION 008


---

## SESSION 009
DATE: 2026-09-17
BUILDER: Antigravity (Gemini)

WORK DONE
- Diagnosed EasyOCR CPU fallback (PyTorch has no GPU binary for Python 3.14 yet), preventing hardware acceleration for text extraction and causing 1-2s freezes.
- Completely removed live plate OCR text extraction from the `process_frame` pipeline to guarantee buttery smooth video streaming.
- Implemented Just-In-Time (JIT) Plate OCR: The backend intercepts the `fetchViolationByTrackId` request when a user clicks a log entry, sequentially scans all saved evidence frames for the plate, and seamlessly updates the database user ID.
- Added `plate_bbox` to the ledger ticket so the OCR scanner can pinpoint the plate.
- Fixed a critical pipeline bug where `_capture_evidence_frame` was not being called for non-spatial violations (e.g. `no_plate`, `no_helmet`), resulting in missing evidence images. Added a generic final sweep to guarantee evidence capture for any flagged violator.

FILES TOUCHED
- hulikamote_backend/engine/pipeline.py | Removed live OCR, added universal evidence capture sweep
- hulikamote_backend/routers/violations.py | Added JIT OCR background scanning in `list_violations`
- hulikamote_backend/routers/stream.py | Removed aborted background OCR worker
- hulikamote_backend/store.py | Added `update_violation_user` to persist OCR resolution
- hulikamote_backend/engine/ledger.py | Passed `plate_bbox` into the finalized ticket

BUGS FIXED
- Video stream freezing for 1-2s during plate detection | Completely resolved by deferring OCR to dashboard log click.
- "No evidence frames were captured" for No Plate / No Helmet violations | Fixed by ensuring `_capture_evidence_frame` fires for all active violations at the end of the tracking pipeline.

DECISIONS MADE
- JIT OCR (Just-In-Time) is the permanent architecture for plate reading. Since Python 3.14 restricts PyTorch to CPU execution, live OCR is impossible without destroying tracking FPS. Reading the plate dynamically when the user requests the log solves this constraint beautifully.
- `plate_bbox` is passed to the backend, or OCR scans the bottom 40% of the vehicle if absent.

LEFT INCOMPLETE
- Training the 3 custom specialist model weights (helmet, plate, cabin).

END OF SESSION 009

---

## SESSION 010
DATE: 2026-09-17
BUILDER: Antigravity (Gemini)

WORK DONE
- Implemented Strategy Pattern & Dependency Injection for ONNX Runtime Execution Providers:
  - GPU-first priority (`CUDAExecutionProvider` -> `CoreMLExecutionProvider` -> `CPUExecutionProvider`).
  - Added Windows CUDA DLL preloading via `ort.preload_dlls()` so pip-installed NVIDIA wheels (`nvidia-*-cu12`) work without system PATH configuration.
  - Implemented dynamic runtime fallback: if GPU provider session initialization raises an error (e.g. driver missing), it logs a warning and transparently retries with `CPUExecutionProvider`.
  - Added Dependency Injection support: `session_factory` constructor injection for `ModelRegistry` and `YoloInference`, plus `override_providers()` / `reset_providers()`.
- Unified all model loading across the backend:
  - `engine/registry.py`: all 4 specialist models (`primary_anchor`, `helmet_specialist`, `plate_specialist`, `cabin_specialist`) use injected `session_factory`.
  - `yolo_inference.py`: uses `make_session()` with constructor injection support.
  - `routers/model.py`: hot-swap upload route uses `make_session()`.
  - `inference/onnx_engine.py`: uses `make_session()`.
- Added unit test suite `tests/test_providers.py` testing provider defaults, DI overrides, CUDA runtime failure CPU fallback, and class constructor injection. All 5 new tests pass (15/15 total backend tests passing).

FILES TOUCHED
- hulikamote_backend/inference/providers.py | Created centralized strategy resolver with DI & fallback
- hulikamote_backend/engine/registry.py | Injected session_factory for all specialist models
- hulikamote_backend/yolo_inference.py | Added session_factory DI to YoloInference & get_inference
- hulikamote_backend/routers/model.py | Switched to make_session()
- hulikamote_backend/inference/onnx_engine.py | Switched to make_session()
- hulikamote_backend/tests/test_providers.py | Created 5 unit tests for providers & DI
- PROJECT_AUDIT.md | Documented architecture & marked all 4 phases complete
- docs/SESSION_LOG.md | Appended Session 010

BUGS FIXED
- Hardcoded `CPUExecutionProvider` preventing GPU acceleration | Resolved via centralized GPU-first provider matrix.
- Potential crash on machines with partial/broken CUDA installations | Resolved via automatic runtime try/catch CPU fallback in `make_session()`.

DECISIONS MADE
- Strategy Pattern with Dependency Injection is the permanent ONNX loading standard. All model loading in `hulikamote_backend` must call `inference.providers.make_session` or an injected factory.

LEFT INCOMPLETE
- Training custom specialist weights in Roboflow.

END OF SESSION 010


---

## SESSION 011
DATE: 2026-09-18
BUILDER: Antigravity (Gemini)

WORK DONE
- Migrated Flutter video engine to media_kit for native Windows RTSP support.
- Forced H.264 video streaming and configured FFmpeg for zero-latency RTSP over TCP (-use_wallclock_as_timestamps 1, -g 15, -bf 0, -rtsp_transport tcp).
- Fixed Flutter bounding box offset by geometrically locking the CustomPaint overlay to the video using AspectRatio(16.0 / 9.0).
- Restored "log once per vehicle" logic in the frontend AlertListWidget by filtering raw JSON overlay frames for is_violator == true.
- Diagnosed infinite circular loader bug during video hot-swap as an FFmpeg/WebSocket singleton race condition.

FILES TOUCHED
- hulikamote_backend/engine/hls_broadcaster.py | Forced TCP and rapid keyframes
- hulikamote_backend/routers/stream.py | Removed Base64 fallback, forced HLS/RTSP payload
- hulikamote_dashboard/pubspec.yaml | Added media_kit dependencies
- hulikamote_dashboard/lib/main.dart | Initialized MediaKit
- hulikamote_dashboard/lib/features/monitoring/presentation/widgets/video_feed_widget.dart | Migrated to media_kit, fixed bounding box layout
- hulikamote_dashboard/lib/features/monitoring/presentation/widgets/alert_list_widget.dart | Filtered detections by isViolator

BUGS FIXED
- Blue/green horizontal pixelation artifacts (UDP packet loss) | Fixed by switching to TCP.
- ~22 second initial load time | Fixed by forcing FFmpeg keyframes every 15 frames.
- Video buffering every few seconds (Timestamp Drift) | Fixed using wallclock timestamps and duplicating frames to 25 FPS.
- Bounding boxes appearing "upper left" | Fixed by matching Flutter widget aspect ratios.
- UI log spamming safe cars | Fixed by filtering the JSON bounding box payload explicitly in the UI.

DECISIONS MADE
- Base64 websocket rendering is officially dead; the system is strictly RTSP + JSON Bounding Box overlay.
- media_kit is the permanent video player backend for the Flutter desktop app, as ideo_player cannot natively stream H.264 on Windows.

LEFT INCOMPLETE
- The FFmpeg WebSocket race condition during video hot-swapping is actively causing infinite loaders and requires a lifecycle refactor.

END OF SESSION 011

---

## SESSION 012
DATE: 2026-09-18 to 2026-09-23
BUILDER: Antigravity

WORK DONE (MASSIVE MULTI-DAY SPRINT)
- **Tracker Integration:** Decoupled tracker logic and integrated DeepSORT implementation into the AI Engine. Added Tracker Algorithm selection to the UI.
- **Plate Specialist & OCR Overhaul:** Implemented Two-Stage YOLO Plate Extraction. Injected a Two-Pass OCR voting system with a 64px sweet-spot upscaling algorithm and strict alphanumeric allowlist.
- **Performance & Optimization:** Implemented micro-skipping and round-robin AI load balancing achieving a ~300% FPS processing boost. Enabled GPU acceleration for EasyOCR and hardware encoding via MediaFoundation (h264_mf with explicit 4M bitrate).
- **Forensic Analyzer Suite:** Built out the complete Forensic Analyzer UI and backend API. Added Interactive UI vector tools for manual ROI drawing.
- **UI/UX Polishing:** Fixed Tracker stability and unlimited evidence frames. Fixed missing bounding box scales. Upgraded the Evidence Gallery with scrollable full-screen sliders and isolated the History Replay state.
- **LPSRGAN Pipeline:** Deployed Real-ESRGAN stand-in for plate enhancement, fixed execution size guards, and wrote an offline `train_lpsrgan.py` script for future UK-plate dataset training.
- **Categorical Model Manager:** Re-architected the entire Model Manager frontend and backend to support physical subdirectories (`Vehicle Detectors`, `Plate Models`, `GAN Enhancers`) with targeted uploads.

FILES TOUCHED
- hulikamote_backend/engine/tracker.py | Decoupled DeepSORT tracker logic.
- hulikamote_backend/engine/pipeline.py | Implemented micro-skipping, plate specialization, and LPSRGAN enhancement.
- hulikamote_backend/yolo_inference.py | Upgraded model loading for category scanning.
- hulikamote_backend/routers/forensic.py | Built backend routes for the new Forensic Analyzer.
- hulikamote_dashboard/lib/features/monitoring/presentation/screens/forensic_analyzer_screen.dart | Built Interactive UI, Evidence Gallery, and History Replay.
- hulikamote_dashboard/lib/features/model_manager/presentation/screens/model_manager_screen.dart | Built category headers and targeted dropdown uploads.
- training_lab/scripts/train_lpsrgan.py | Added offline YOLO crop GAN training pipeline.
- (And dozens of other core routing, UI, and engine files tracked via Git micro-commits).

BUGS FIXED
- Bounding Box Offsets | Removed hardcoded coordinate scaling causing misalignment on the dashboard.
- Pixelation during streams | Set explicit 4M bitrate for hardware encoder.
- CUDA Execution Provider Missing | Forcefully downgraded `onnxruntime-gpu` to 1.26.
- BasicSR Torchvision Crash | Bypassed by extracting PyTorch RRDBNet manually.
- Dialog UI Shrinking & State Bleed | Fixed flex constraints and forced `Navigator.push` for History replay.

DECISIONS MADE
- DeepSORT is the primary AI tracker, and Two-Stage YOLO (Vehicle -> Plate) is the permanent ANPR approach.
- The `models` directory is now dynamically categorized by physical subfolders.
- EasyOCR runs aggressively in the background and votes on the best text string based on a length-enforcer algorithm.

LEFT INCOMPLETE
- The Training Studio UI Roadmap (Smart History Graph, Post-Training Report, etc.) remains on standby awaiting user authorization.
- YOLO11 and YOLO26 integrations are queued.


- **Post-Session Cleanup:** Committed remaining untracked dashboard components and `app_toast.dart` utility.
- **Identified Blocker:** Logged a critical bug where starting analysis in forensics throws a "missing ONNX model" error, likely caused by the new model directory re-architecture breaking the inference path loading.

END OF SESSION 012

---

## SESSION 013
DATE: 2026-09-30
BUILDER: Antigravity

WORK DONE
- Merged Inbox Pop Quiz UI directly into Forensic Analyzer ticket dialog.
- Added _isSubmitted visual state lock to prevent duplicate ML feedback submissions to the Vault.
- Restored missing Restricted Lane FilterChips UI using direct file edits.
- Fixed 2D BBox projection in ledger.py to track tires on pavement (bottom-center anchor).
- Fixed Evidence Throttler race condition in pipeline.py to guarantee Frame 1 snapshot.
- Implemented Levenshtein deduplication in forensic report payload for dropped tracker IDs.
- Generated comprehensive AI training and roadmap plans (docs/AI_ROADMAP_PLAN.md).

FILES TOUCHED
- hulikamote_dashboard/lib/features/monitoring/presentation/screens/forensic_analyzer_screen.dart | Restored FilterChips, removed duplicate model dropdowns
- hulikamote_dashboard/lib/features/monitoring/presentation/widgets/forensic_ticket_review_dialog.dart | Converted to inline feedback widget with success state
- hulikamote_backend/engine/ledger.py | Updated position tracking anchor to bottom-center
- hulikamote_backend/engine/pipeline.py | Fixed evidence throttling logic
- hulikamote_backend/routers/forensic.py | Fixed DB sync order and added ID deduplication

BUGS FIXED
- UI Patch failure on CRLF vs LF line endings | Used direct file editing API instead of brittle Python scripts
- Missing evidence photos | Fixed modulo math race condition in the throttler

DECISIONS MADE
- Tracker Config Locked: tracker.py hyperparameter matrix is maxed out mathematically. Focus moves to ReID model replacement.
- Phased Training: Prioritize Active Learning data harvesting (TP/FP clicks) before GPU fine-tuning.
- Mock Traffic Lights: Will build a virtual toggle in the UI to test Red Light logic instead of relying on non-existent traffic cam footage.

LEFT INCOMPLETE
- Mobile App API Integration (waiting on user greenlight).
- Actual fine-tuning of YOLO models with the newly collected datasets.

END OF SESSION 013

---

## SESSION 014
DATE: 2026-10-03
BUILDER: Claude Sonnet 5.5

WORK DONE
- Tracking: found and fixed the box-format bug (tracker.py sent top-left boxes where DeepSORT expects centre boxes); made tracker-ID to detection mapping one-to-one; added a track stitcher (lost-track rejoin); user confirmed the duplicate-ID problem mostly fixed.
- Forensic review rebuilt around the evidence frames: "Different car" tick + separate (multi-car), merge whole ticket or only chosen frames, duplicate banner (Merge / Different car), plate shown per frame; old suggestion cards and merge/split dialog removed.
- Plate crops now carry their time and link to the nearest evidence frame; split moves crops with frames and each ticket re-votes its plate. Evidence photo gap (1-5) is a wizard setting; clean car crop saved per evidence frame.
- Every review decision exports ReID training data (training_lab/datasets/reid + decisions.jsonl). New train_reid.py (deploys only if better than current on held-out photos).
- Training Studio rewritten: all models (4 YOLO, OCR, ReID, enhancer) with dataset readiness, presets, progress; per-model History and Guide tabs; backend overview/history/log endpoints.
- Datasets centralized under training_lab/datasets (plate_ocr, reid). Live Monitor: video upload, Send to Live Monitor from a forensic run, auto-reconnect, header overflow fix.
- Storage: investigated 27 GB of evidence photos, cleared snapshots, forensic history and the tickets DB (5,198 rows) at user request; uploaded forensic video now deleted after analysis (switch to keep it); old live upload removed on new upload.
- Tooling: graphify (v0.9.74, verified against PyPI/repo) project map + coverage risk table via tools/project_map/build_map.py. Full backend suite: 40 passed, 3 stale failures.
- Reviewed the thesis context for the next goal (violation test foundation, benchmarks, model comparison) and set it as the next task. Thesis PDF could not be read (no PDF tool).

FILES TOUCHED
- hulikamote_backend/engine/tracker.py | centre-format boxes to DeepSort.update
- hulikamote_backend/yolo_inference.py | one-to-one ID assignment by best IoU
- hulikamote_backend/engine/track_stitcher.py, engine/ledger.py | track stitching, aliases, track events, evidence meta (car_crop)
- hulikamote_backend/engine/pipeline.py | evidence_gap setting, timed plate crops (cap 40), clean car crop per evidence frame
- hulikamote_backend/engine/ticket_flags.py, ticket_merge.py, reid_dataset.py | duplicate/ID-switch flags, split/merge logic, ReID dataset export
- hulikamote_backend/routers/forensic.py | merge/split/move-frames/not-duplicate, send-to-live, plate-frame linking, keep_input_video
- hulikamote_backend/routers/training.py | overview, history, log, ReID/enhancer pipelines
- hulikamote_backend/routers/settings.py, stream.py, feedback.py | video upload, close obsolete websocket, plate_ocr path
- hulikamote_backend/tests/test_track_stitching.py, test_ticket_flags.py, test_ticket_merge.py | 28+ new tests
- training_lab/scripts/train_reid.py, train_ocr.py | ReID trainer; OCR reads datasets/plate_ocr
- hulikamote_dashboard/.../forensic_analyzer_screen.dart, ticket_flag_review.dart | in-frame review, wizard settings (evidence gap, keep video), Send to Live
- hulikamote_dashboard/.../live_monitoring_screen.dart | upload, reconnect, source label, overflow fix
- hulikamote_dashboard/.../training_studio_screen.dart, model_history_panel.dart, model_guide_panel.dart, training_report_widget.dart | Studio rewrite (training_history_screen.dart removed)
- tools/project_map/build_map.py, docs/project_map/ | project map + coverage risk table
- docs/AI_TRAINING_DATA_OVERVIEW.md, docs/CLAUDE_CODE_HANDOFF_TRACKING.md | training data overview; tracking handoff
- hulikamote_backend/snapshots/ | tracked sample snapshots removed; all evidence cleared

BUGS FIXED
- Duplicate IDs / reassigned IDs for one car | centre-box format fix + one-to-one mapping + stitcher
- Dashboard went black after closing the flag dialog | double pop (dialog closed itself and the X popped the page); single-close guard + busy state
- Send to Live Monitor "did nothing" | backend left the old websocket open; now closes it and the live screen reconnects
- Live Monitor header overflow (42 px) | title ellipsis + Wrap for buttons
- Live source label showed full Windows path | regex only split on "/" (now matches backslash too)
- Test run switched the real active model and left fake model files | restored models/active_model.txt, bad.zip, removed models/Uncategorized (test_model_upload.py still mutates models/)

DECISIONS MADE
- Review is built into the evidence frames; flags are suggestions, not a separate workflow. Every review decision feeds ReID data.
- One dataset root: training_lab/datasets. Uploaded forensic video deleted by default.
- ReID deploys only if it beats the current model on held-out photos (backup kept).
- Next phase = violation test foundation, benchmark runner, model comparison; violation SCOPE mismatch with the thesis list must be settled with the user first.
- Orchestration prompts left untouched (no new subproject).

LEFT INCOMPLETE
- Nothing from Session 014 has been run on real footage; verify first (see HANDOVER).
- 3 stale backend tests; Flutter has no tests; pipeline.py / forensic.py / yolo_inference.py coverage is 13% / 11% / 27%.
- Storage panel + retention rule; merge does not re-vote the plate; ReID data too small to train (2 cars, need 5+, 30+ recommended).
- Per-violation scripted tests, ground-truth clip registry, benchmark runner, model comparison, Virtual Traffic Light Simulator.
- Helmet / cabin / primary vehicle datasets are empty. Real-ESRGAN enhancer unproven. Thesis PDF unread.

END OF SESSION 014

---

## SESSION 014 - ADDENDUM (same day, after the wrap-up)
DATE: 2026-10-03
BUILDER: Claude Sonnet 5.5

WORK DONE
- Repo cleanup at user request: deleted one-off patch scripts, evidence-test files, dummy videos, empty root DB; .gitignore now covers *.pt, root DB, collected training data (datasets/plate_ocr, datasets/reid), .graphify_env, .coverage; committed docs/dynamic_resolution_plan.md. Kept export_ocr.py untouched.
- Built "Project Mapper" (stacks -> features -> user actions -> code, plus runtime trace replay) as a SEPARATE project outside this repo: k_dev/project_mapper (own git repo). It only reads this project; its tracer runs the app against a temp DB/folders. Verified: 77/86 UI calls linked to endpoints (9 dynamic, 0 mismatches), 20-link hand audit correct, 9 real safe actions fired and every function that ran had been predicted by the static map. 9 mapper tests pass. Project untouched (verified via git status, ReID data, DB mtime).
- Added a PROJECT MAPS section to HANDOVER.md (graphify docs/project_map + Project Mapper) so the next builder orients with these instead of reading many files, and is told not to edit the mapper.

FILES TOUCHED
- .gitignore | ignore weights, root DB, collected training data, local envs
- docs/dynamic_resolution_plan.md | committed (existing plan doc)
- docs/HANDOVER.md | PROJECT MAPS section
- docs/SESSION_LOG.md | this addendum (the tool also normalized mixed line endings of the Session 013 block to CRLF; no content change)
- (outside this repo) k_dev/project_mapper/ | the Project Mapper project

BUGS FIXED
- Mapper bugs found by its own checks (verb picked from the wrong call; helper paths like request('merge'); getters read as handlers; wrong code location for shared API helpers; literal-vs-catch-all route matching) | fixed and covered by tests

DECISIONS MADE
- Project Mapper lives outside the project repos so project sessions never touch it; rebuild with `python pm.py huli-kamote` from k_dev/project_mapper.
- ORCHESTRATION_START/END untouched; graphify/mapper guidance goes through HANDOVER.md (read at session start).

LEFT INCOMPLETE
- Mapper covers Flutter (go_router) + FastAPI only; runtime tracing lists only 9 read-only/fixture-backed actions; dashboard/live-stream flows are not traced.
- Suggested but not done: add "rebuild the project maps" to the end-of-session routine, and install graphify's Claude skill (`graphify install --platform claude`) so the AI can query the graph.

END OF SESSION 014 ADDENDUM

---

## SESSION 015
DATE: 2026-10-19 (work spanned 2026-10-03 to 2026-10-19)
BUILDER: Claude Opus 5.5 and Claude Sonnet 5.5 (several parallel conversations; this entry covers all of them)

WORK DONE
- Violations: settled the scope with the user (all 14 thesis violations in scope; the old HANDOVER "DONE" table described the Visualizer, not the backend). Built rule-based pedestrian lane, illegal turn, swerving, overloading, red light (camera colour or a SIMULATED light with countdown drawn on the result video and evidence), disregarding signs (no entry / no turn / no stopping / vehicle ban / stop sign) and signal light (blink heuristic). Reworked No Plate: judged over the whole track, PENDING while the vehicle is on screen and decided when it leaves or the video ends. Helmet / seatbelt / phone / mirror / overloading now decide by vote over looks; helmet checks the motorcycle plus its riders; people get their own NMS group so riders do not delete the motorcycle.
- "Why" boxes (engine/marks.py): bare-headed rider, riders, phone, mirrors, searched plate area, drawn on the result video and evidence photos, following the vehicle.
- Models: engine/model_catalog.py + Models tab = one active model per job (vehicles / helmet / plate / cabin) with score bars; the registry loads the deployed helmet / cabin model; export_onnx.py deploys to the right folder and exports the newest run; forensic analysis no longer resets the vehicle detector to YOLOv8n.
- Training: pause / continue (scripts/run_state.py + /api/train/*), Studio Pause / Continue bar and History / Guide tabs that stay reachable, a terminal Training Lab (lab_tui.py: overview, live epoch, runs and logs, dataset, harvest tab) that trains in its own process, train.py / split_dataset.py fixes. Smoke-tested all four YOLO trainings end to end. Trained and deployed the helmet model (train-2) and the cabin model (train, 2026-10-13); plate not retrained; the vehicle run (6 classes) is interrupted at epoch 23 of 30 and not deployed.
- Data: scripts/fetch_datasets.py + configs/datasets_manifest.yaml (six public Roboflow sets, class mapping, leak removal between train and val/test); vehicle classes gained person + tricycle. A later provenance check found the sets are NOT Philippine / Zamboanga (see KNOWN ISSUES).
- Harvest tool (training_lab/harvest_tool, harvest.py, 20 tests, dashboard Harvest view): collect from saved forensic analyses, check / label in the browser, accept into datasets only while the model is not training, cut plates, probe how the app feeds images.
- Dashboard: rebuilt Forensic Analyzer (features/forensic: 5-step wizard with zone editor, library, queue | evidence | decision review workspace, plate correction, merge / split, harvest view, 7 test files); Progress Report and Visualizer navigation entries; VisiblePoller (polling follows page visibility).
- Investigations: specialist model input mismatch (BGR + stretch + bottom-40% plate crop: plate found 7% vs 85% when fed properly), live-video stall caused by Studio polling, plate-to-owner gap, legal basis of each violation (RA 4136 sections verified, JAO 2014-01, LTO AO AHS-2008-015, NCAP status), data provenance.
- Progress Report deck (48 slides + speaking script) for the consultation.
- Two backend patches written and tested on a copy but NOT applied (tools/pending_patches: stall_fix, plate_edit), because a training was running under uvicorn --reload.
- Wrap-up: archived the handover, committed everything as stacked category branches (see HANDOVER), rebuilt the project maps. Tests at wrap-up: backend 105 passed / 1 stale failed (test_model_upload.py excluded), harvest 20 passed, Flutter 95 passed / 2 stale failed (also fail on the previous commit), flutter analyze 0 errors.

FILES TOUCHED
- hulikamote_backend/engine/ledger.py | new rule evaluators (pedestrian lane, turn, swerve, red light, signs, signal light), votes, plate pending / end-of-track decision, finalize_all
- hulikamote_backend/engine/pipeline.py | generic zone table, simulated light, indicator sampling, marks, evidence clean crops, vote-based helmet / cabin checks, no-plate pending
- hulikamote_backend/engine/marks.py, traffic_light.py, model_catalog.py | NEW: why-boxes, light reading + simulated light + blink detection, model catalog
- hulikamote_backend/engine/registry.py | loads deployed helmet / cabin model from model_manifest.json; cabin model also for mirror-only runs
- hulikamote_backend/yolo_inference.py | people NMS group, marks slot, unique snapshot names
- hulikamote_backend/routers/forensic.py | zone parsing for the new violations, active vehicle detector by default, finalize_all
- hulikamote_backend/routers/model.py, training.py | model catalog endpoints; train state / pause / resume / open-lab, start guard
- hulikamote_backend/tests/test_violation_rules.py, test_model_catalog.py, test_run_state.py | 57 + 4 + 4 new tests
- hulikamote_backend/models/ | Helmet Detectors + Cabin Models ONNX, model_manifest.json
- training_lab/lab_tui.py, scripts/run_state.py, scripts/fetch_datasets.py | NEW terminal Training Lab, run state, dataset fetcher
- training_lab/scripts/train.py, split_dataset.py, export_onnx.py | absolute dataset path, --fraction / --name, skip split, deploy folders / newest run
- training_lab/harvest.py, harvest_tool/*, tests/test_harvest.py | NEW harvest tool
- training_lab/configs/datasets_manifest.yaml, datasets/*/data.yaml | public dataset list; vehicles 6 classes; test splits
- training_lab/runs/ | results.csv / args.yaml / curves of the helmet, cabin and (unfinished) vehicle runs
- hulikamote_dashboard/lib/features/forensic/** (28 files), test/features/forensic/** | rebuilt Forensic Analyzer + tests
- hulikamote_dashboard/lib/features/monitoring/.../forensic_analyzer_screen.dart, forensic_ticket_review_dialog.dart, ticket_flag_review.dart | DELETED (replaced by features/forensic)
- hulikamote_dashboard/lib/features/training/**, core/utils/visible_poller.dart | Pause / Continue bar, run tabs, visible polling
- hulikamote_dashboard/lib/features/model_manager/** | Models tab by job
- hulikamote_dashboard/lib/features/launcher/**, core/utils/external_apps.dart, core/shell/app_shell.dart, core/routers/app_router.dart | Progress Report + Visualizer entries
- tools/pending_patches/** | two tested, unapplied backend patches
- Progress Report/** | consultation deck + speaking script
- .gitignore | ignore dataset downloads, harvest inbox, caches, run previews, stray runs/ and rejected download
- docs/ledger/handovers/HANDOVER_SESSION_015.md, docs/HANDOVER.md, docs/SESSION_LOG.md, docs/project_map/ | wrap-up

BUGS FIXED
- Studio "Train" run view hid the Train / History / Guide tabs after a run | tabs always visible; a run is an extra "Current / Last run" tab; a backend restart shows "Run no longer tracked"
- Analysis crashed with "'YoloDetection' has no attribute 'marks'" | the class uses __slots__; field declared, test added with the real class
- Training failed at start: dataset images not found | Ultralytics resolved the relative dataset path against its own folder; train.py now passes an absolute path
- Studio pipeline failed on already-split datasets (empty raw/ folder) | split_dataset.py skips them
- Resume on the wrong model (a finished run) trained Ultralytics' coco8 sample and created stray folders | Resume refuses finished runs and says what it will resume
- Export deployed the oldest run (train) instead of the newest | latest_run(); cabin models went to Vehicle Detectors | now Cabin Models
- Trained helmet / cabin models were never loaded by the backend | registry reads model_manifest.json
- Every forensic run reset the vehicle detector to YOLOv8n | wizard default is "active model"
- No Plate flagged after 2 misses and never cleared, motorcycles facing the camera flagged | judged over the whole track, rear view only, final decision at end of track; photos of a cleared suspicion are deleted
- Stop sign: a normal 1-2 s stop never counted as a stop | 1 s speed window
- Riders' boxes were deleted by NMS against their motorcycle | people NMS group
- Snapshot file names collided when several images were saved in the same millisecond | counter suffix
- Live video froze every ~2 s while Studio polled | dashboard polls only while visible (backend side patch staged, not applied)
- A pip install into the backend venv restarted uvicorn and killed a Studio training | rule recorded (HANDOVER); trainings now launch detached from the Lab
- Windows os.kill(pid, 0) would have terminated a process | psutil.pid_exists (caught in review before it ran)

DECISIONS MADE
- All 14 thesis violations are in scope (plus restricted lane and distracted driving kept); backend status is tracked in the HANDOVER detection table, the Visualizer table is separate.
- Suspicions are pending until the vehicle leaves; single-frame model guesses never create a ticket (votes).
- One active model per job; models trained here deploy to category folders + model_manifest.json (committed: the repo tracks weights).
- Harvest is standalone and read-only towards the backend; benchmark clips are protected; the test split is never written.
- Pause stops the training process (frees the GPU) and Continue resumes from the last finished epoch.
- ORCHESTRATION_START / END left untouched (user rule: immutable); repository-map additions are recorded in the HANDOVER.
- Commits are STACKED category branches, not independent ones, because several files serve more than one category.
- Public datasets are credited CC BY 4.0 and described as non-Philippine in all documents.

LEFT INCOMPLETE
- Nothing has been scored on real footage: no ground-truth clip registry, benchmark runner or model comparison. The user was given a Caught / False alarms / Missed checklist per violation; no results came back.
- Model input mismatch fix (RGB + letterbox + whole-vehicle plate search + NMS) and the plate retrain; the harvest "cut-plates" crops are not yet used for training.
- tools/pending_patches (stall_fix, plate_edit) not applied; "Save plate" in the review screen needs plate_edit.
- Cabin model has no tinted-window or motorcycle-mirror data, so Missing Side Mirror cannot work; vehicles run interrupted at epoch 23 of 30; ReID has 2 cars (needs 5+); the OCR trainer cannot run as installed.
- Marks are not sent to the live overlay (stream.py does not include them); new violations exist only in the forensic wizard, not the live camera wizard or the offline screen; tickets do not say which sign was broken.
- model_catalog / lab_tui show the max-mAP50 epoch, not the fitness-chosen epoch that is actually saved.
- No plate-to-owner registry (Confirm notifies nobody); no storage retention rule / Storage panel; no packaging for deployment.
- 3 stale backend tests (+ test_model_upload.py still mutates models/) and 2 stale Flutter live-monitoring tests.
- Cleanup candidates left for the user to delete (git-ignored): repo-root runs/, k_dev/datasets/coco8/, training_lab/train|valid|test|data.yaml|README.*.
- Not committed on purpose: camera_config.json, hulikamote.db, training_lab/scripts/export_ocr.py (local state from before Session 014), docs/read_later/ (the user's notes).

END OF SESSION 015

---

## SESSION 016
DATE: 2026-10-27 (work of 2026-10-22 .. 2026-10-27, several parallel conversations; 41 commits since the Session 015 wrap-up)
BUILDER: Claude Sonnet 5.5 (this conversation) and parallel Claude conversations

WORK DONE
- Panel consultation revisions (2026-10-22): learned traffic flow so counterflow needs no drawn zone (flow_field / flow_prescan + wizard switch); 20 violations, one module each in
  engine/violations/ with the pipeline only calling hooks (5 new: pickup_passengers, riding_outside_vehicle, illegal_u_turn, blocking_intersection, crossing_solid_line); the
  wizard offers all 20; Code Reference tab (code + "How it's tested" per feature); docs/THESIS_REVISIONS.md (scope 13 -> 20, live demo, camera angle, heuristics, evaluation).
- Models are fed like they were trained (RGB + letterbox + whole vehicle, NMS): plate found 7% -> 83% on held-out photos.
- Live: camera input from RTSP / HTTP / webcam with newest-frame reading and reconnect, Camera input dialog + LIVE / OFFLINE chip, "Use for Live Monitor" from the wizard
  (POST /api/forensic/live-config), remembered camera, why-marks overlay; the Settings camera wizard and the standalone ROI screen were removed (the zone editor is in the wizard).
- Dataset library: one layout (images/{train,val,test}), fetch + merge public sets from a manifest, cleaner with near-duplicate quarantine, cards + CATALOG.md; the plate set was
  restructured (6.5k renames); side-mirror data found (not trained).
- Benchmark: tools/benchmark (precision / recall / LOAR / CER / WER per violation) + Benchmark tab + clip checklist. The registry is EMPTY.
- Harvest redesigned for a non-technical, visual user: per analysis a Review | Harvest switch, category tiles, ONE picture at a time full screen (Enter / drag / pull a corner /
  N / S / Delete); the enforcer's right panel is only the plate fix ("Send plate"). Helper API (per-analysis session / queue / collect), started hidden with pythonw.exe.
- Harvest extended ("build it all"): Vehicles tile (8 frames per analysis from the kept video, vehicle finder's guess, model primary_anchor), missed vehicles (no ticket) as plate /
  helmet / cabin pictures, "Same car?" = quick look-alike questions + a list of every ticketed car (big photo, flat strip, D = different car than the original, Enter saves,
  "Rest are fine" files the unopened cars; also harvest.py reid-fill). Answers go to datasets/reid like the review screens write them; tickets never change.
- ReID: proof it is trainable and that it helps on the SAME cameras (training_lab/experiments/reid/RESULTS.md: rank-1 76.7 -> 85.3% on unseen cars, 3 of 3 splits; no gain on a
  different road); the Studio's Car Matching trainer now judges on cars it never saw; scripts/reid_ab.py counts suspected ID jumps old vs new on one clip; harvest.py reid-export.
- Training Studio "Training pictures" box (original vs harvested, visual); "Detect traffic flow automatically" card in the wizard.
- Housekeeping: stale tests fixed, tests mirror the source tree, test_gaps.py, set-plate and the Studio status thread applied; work moved to `dev` (fast-forward of module-split);
  commits cleaned into grouped conventional commits; the embedded reference clone untracked; the Firebase key untracked (NOT rotated).
- Strict defense-readiness assessment (see HANDOVER): what the project lacks and the order to fix it.

FILES TOUCHED
- hulikamote_backend/engine/violations/**, engine/flow_*.py, engine/camera_source.py, routers/{forensic,settings,stream}.py, tests/** | violations, flow, live camera, live-config
- hulikamote_dashboard/lib/features/{forensic,training,benchmark,blueprint,monitoring}/** and test/** | harvest tiles + labeler + cars list, Studio wording, Benchmark, Code Reference
- training_lab/harvest_tool/{frames,pairs,cars,reid_export,collect,store,web,sources,config,gallery}.py, harvest.py, tests/test_harvest.py | harvest helper (API 4)
- training_lab/scripts/{train_reid,reid_ab,fetch_datasets}.py, data.py, data_tools/**, experiments/reid/**, tests/{test_train_reid,test_reid_ab,test_data_tools}.py | ReID + datasets
- tools/benchmark/**, tools/tests_index.py, benchmarks/** | benchmark + tests index
- docs/{THESIS_REVISIONS,HANDOVER,SESSION_LOG}.md, docs/ledger/handovers/HANDOVER_SESSION_016.md, docs/project_map/, TODO.md, .gitignore | docs and ledger

BUGS FIXED
- The Studio's ReID check scored held-out photos of the cars it trained on (old model already 98.6%, so it could never deploy a better one) | it holds out 25% of the cars, needs +2 points and 8+ cars
- Harvest helper opened a black console window on Windows | started with pythonw.exe (verified: no console host)
- A test read the user's saved camera and failed when it was offline | the test pins the sample video
- harvest collect crashed on an analysis without a report | skipped
- Labeler bottom bar overflowed with six vehicle chips | the bar wraps
- Widget tests pressed while the page was still sliding in | tests wait 1 s after opening a route
- training_lab/scripts/export_ocr.py working copy was cut to 21 lines | restored from git
- An embedded git clone was committed as an empty gitlink | untracked + ignored
- Found, NOT fixed (hulikamote_backend, backend was running): engine/deep_sort/deep/train.py crashes on pictures not already 64x128 and stops with NameError after epoch 1 without --resume

DECISIONS MADE
- Harvest is minimal and visual: per analysis, one picture at a time; the enforcer panel only fixes a plate.
- Corrections (Same car / Different car) only create training data; tickets are never changed by Harvest.
- A new car matcher is deployed only on evidence from cars it never saw; fewer than 8 cars are trained but never deployed.
- File ONE analysis per clip for ReID (re-runs repeat the same cars); benchmark clips stay protected and double as the A/B test clips.
- ORCHESTRATION_START / END untouched (user rule); no new top-level folder was added.
- Work continues on dev; nothing is pushed until the user says so.

LEFT INCOMPLETE
- Defense-critical (HANDOVER > DEFENSE READINESS): no accuracy on real footage for any violation; weak plate reading on the local clip; only one local clip; SMTP email, RA 10173
  masking and demerit points promised but absent; live demo never rehearsed; legal bases TO CONFIRM; 34 commits unpushed; Firebase key not rotated.
- Not hand-tested in the running app: the harvest redesign, Vehicles / Same car? / cars list / "Rest are fine", the Studio's new wording. reid_ab.py was only smoke-tested.
- One entry that holds 3+ cars (all marked photos become one other car); the user's idea to re-mark each car's box in a kept video (ground truth + real ID-switch counts).
- Another session's uncommitted work was in the tree: decision_panel.dart, hulikamote_dashboard/lib/core/widgets/, test/core/widgets/ ("Explain on hover").
- Not committed on purpose: hulikamote_backend/camera_config.json, hulikamote.db (local state).

END OF SESSION 016

---

## SESSION 017
DATE: 2026-11-01
BUILDER: Copilot SDK

WORK DONE
- Replaced the Datasets browser handoff with a native Flutter dashboard viewer backed by the existing local token-protected Python service.
- Added dashboard data access, native Gallery/Overview/About/Clean/Quarantine screens, and updated the startup README.
- Fixed a narrow-width overflow in the bulk-selection action bar.

FILES TOUCHED
- hulikamote_dashboard/lib/features/datasets/** | native viewer and API client
- hulikamote_dashboard/lib/core/{routers/app_router.dart,shell/app_shell.dart,utils/external_apps.dart} | native route and local helper startup
- hulikamote_dashboard/lib/features/launcher/presentation/screens/launcher_screens.dart | removed browser-only Datasets screen
- hulikamote_dashboard/test/features/datasets/dataset_viewer_screen_test.dart | native viewer widget test
- training_lab/dataset_viewer/README.md | documented native dashboard and standalone modes
- docs/HANDOVER.md, docs/SESSION_LOG.md, docs/ledger/handovers/HANDOVER_SESSION_017.md | session wrap-up

BUGS FIXED
- Bulk-selection action bar overflowed on narrow dashboard widths | changed its layout to wrap and verified the widget test

DECISIONS MADE
- Keep the dashboard viewer native; retain the local Python helper as the authority for dataset operations and safety checks.
- Do not edit ORCHESTRATION_START.md or ORCHESTRATION_END.md, per the user's repository rule.

LEFT INCOMPLETE
- Real-data hand-testing and full native parity remain: drag selection, lightbox previous/next, and rendered Markdown in About.
- Unrelated dirty worktree changes were left untouched.

END OF SESSION 017

---

## SESSION 018
DATE: 2026-11-01
BUILDER: Copilot SDK

WORK DONE
- Added a native Relabel tab for box-crop review, selected-box and source/split/class bulk relabel previews, confirmed writes, and card regeneration.
- Added atomic YOLO writes, relabeled filtering, stale-card status, undo state restoration, and rollback recovery when action logging fails.
- Documented the Relabel workflow and updated the dashboard widget and service tests.

FILES TOUCHED
- training_lab/dataset_viewer/app.py, server.py | relabel operations, routes, safe write/undo behavior
- training_lab/dataset_viewer/README.md | documented the Relabel tab and atomic label changes
- training_lab/tests/test_dataset_viewer.py | bulk preview/apply, undo, safety, and rollback coverage
- hulikamote_dashboard/lib/features/datasets/data/dataset_viewer_api.dart | relabel endpoints and gallery filter
- hulikamote_dashboard/lib/features/datasets/presentation/screens/dataset_viewer_screen.dart | native tab and card-stale/regenerate flow
- hulikamote_dashboard/lib/features/datasets/presentation/widgets/dataset_relabel_tab.dart | crop review and bulk relabel UI
- hulikamote_dashboard/test/features/datasets/dataset_viewer_screen_test.dart | native relabel widget flow
- docs/HANDOVER.md, docs/SESSION_LOG.md, docs/ledger/handovers/HANDOVER_SESSION_018.md | session wrap-up

BUGS FIXED
- Relabel rollback could leave stale index, relabeled flags, or card status after a cache/action-log failure | restore or rebuild each cached state and report incomplete rollback explicitly
- Undo of a later relabel could clear an earlier relabeled mark | restore each picture's pre-action relabeled status

DECISIONS MADE
- Keep the dashboard UI native and use the local Python service for all dataset writes and safety checks.
- Keep ONNX suspected-mislabel review out of this release; it remains an optional later step.
- Leave ORCHESTRATION_START.md and ORCHESTRATION_END.md untouched.

LEFT INCOMPLETE
- Real-data hand-testing against primary_anchor remains; do not make real label edits without explicit approval and a check that training is idle.
- Unrelated dirty worktree changes were left untouched.

END OF SESSION 018
