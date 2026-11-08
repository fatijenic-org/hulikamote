# HULI-KAMOTE - MASTER HANDOVER (SESSION 003 ARCHIVE)
===================================================
ARCHIVED AT: Session 003 completion (2026-09-09)
BUILDER: Antigravity (Gemini)

PROJECT LOCATION
hulikamote_visualizer: C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_visualizer
hulikamote_backend:    C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_backend
hulikamote_dashboard:  C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_dashboard
hulikamote_app:        C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_app

STACK
Flutter desktop (Windows primary target)
Dependencies: flutter_math_fork, provider, shared_preferences
Backend: FastAPI, SQLite, YOLOv8, ONNX, DeepSORT, EasyOCR

CURRENT PHASE DEFAULT
home_screen.dart currentPhase = 4 (Temp Concept, for testing)
CHANGE THIS TO 3 before any presentation or handoff to non-developer

VIOLATION STATUS TABLE
Format: violation | cat | p0_old_way | p1_concept | p2_setup | p3_modern_ai | notes

Counterflow       | MC  | DONE       | DONE       | DONE     | DONE         | gold standard template
Illegal Parking   | MC  | missing    | missing    | missing  | DONE (basic) | zone timer working
No Plate Number   | Car | missing    | missing    | missing  | DONE (basic) | crop slider working
Swerving          | EXT | missing    | missing    | missing  | missing      | placeholder text only
Illegal Turn      | MC  | missing    | missing    | missing  | missing      | not in data file
Disregarding Signs| MC  | missing    | missing    | missing  | missing      | not in data file
No Helmet         | MC  | missing    | missing    | missing  | missing      | not in data file
Missing Side Mirror| MC | missing    | missing    | missing  | missing      | not in data file
Overloading       | MC  | missing    | missing    | missing  | missing      | not in data file
Signal Light      | EXT | missing    | missing    | missing  | missing      | not in data file
Red Light Running | EXT | missing    | missing    | missing  | missing      | not in data file
No Seatbelt       | EXT | missing    | missing    | missing  | missing      | not in data file
Pedestrian Lane   | EXT | missing    | missing    | missing  | missing      | not in data file

MC = Motorcycle, Car = Cars only, EXT = Extended

ACTIVE EXPERIMENTAL FILE
counterflow_temp.dart (Phase 4 tab) — 3-step centroid tracking tap interaction
Status: user reviewing whether to merge into Phase 1 (Core Concept) or Phase 2 (Real-World Setup)
Action needed: decide and merge or delete before handoff

BACKEND STATUS
All 3 tests passing: test_model_upload.py, test_stream.py, test_violations.py
Active endpoints: /auth/login, /upload-model, /violations, /ws/video-feed,
                  /notifications/register-token, /settings/violations, /settings/mock
Violation detection logic documented at: hulikamote_backend/violation_detection_logic.md

KNOWN ISSUES AND QUIRKS
- currentPhase defaults to 4 (temp tab). Must be set back to 3 for production.
- Counterflow wrap bounds: X=1500, Y=450. If screen differs, these need adjustment.
- dart:math must be imported in every CustomPainter file or it will not compile.
- Timers must be cancelled in dispose() to prevent leaks. All current ones do this.
- Emoji in tab buttons may render as garbage bytes on some systems. Known issue.
- StaticCropVisualizer: car scaled down and offset -20px vertically to prevent
  overlap with slider panel. Do not increase car size without adjusting offset.

DESIGN RULES LOCKED IN
- No jargon in any user-visible text. See banned word list in docs/ORCHESTRATION.md.
- Canvas is always left (flex 2), controls panel is always right (380px fixed).
- Visualizer container height: 550px. Road color: grey[700]. Car: blueGrey.
  Windshield: lightBlueAccent. Headlights: yellow.
- Legal flow direction for all violations is Left to Right.
- Math equations are shown at bottom, small, faded (opacity 0.4).
- Analogies locked: Old Way = cardboard stencil. Core Concept = compass needle.

FILE NAMING CONVENTION
[violation]_bf.dart         = Phase 0 (The Old Way)
[violation]_fp.dart         = Phase 1 (Core Concept)
[violation]_setup.dart      = Phase 2 (Real-World Setup)
[violation]_visualizer.dart = Phase 3 (Modern AI)
[violation]_temp.dart       = Experimental only. Delete when merged.

NEXT TASK FOR INCOMING BUILDER
1. Decide fate of counterflow_temp.dart: merge into fp or setup, then delete temp file.
2. Set currentPhase back to 3 in home_screen.dart after temp tab decision.
3. Build Illegal Parking Phase 0 (illegal_parking_bf.dart): show old fixed-coordinate
   grid approach failing when camera shifts.
4. Build Illegal Parking Phase 1 (illegal_parking_fp.dart): show Intersection over
   Union (IoU) concept. Two draggable rectangles. Show overlap area calculation.
5. Build Illegal Parking Phase 2 (illegal_parking_setup.dart): show how ROI polygon
   is drawn over the no-parking zone on a real camera feed.
6. Add remaining violations to violation_data.dart (at minimum: Illegal Turn,
   No Helmet, Overloading for motorcycle batch).

SESSION LOG HISTORY
See docs/SESSION_LOG.md
