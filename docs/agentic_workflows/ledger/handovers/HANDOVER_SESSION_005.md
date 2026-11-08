# HULI-KAMOTE - MASTER HANDOVER
================================
LAST UPDATED: 2026-09-09 by Antigravity (Gemini)

PROJECT LOCATION
hulikamote_visualizer: C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_visualizer
hulikamote_backend:    C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_backend
hulikamote_dashboard:  C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_dashboard
hulikamote_app:        C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_app

STACK
Flutter desktop (Windows primary target)
Dependencies: flutter_math_fork, provider, shared_preferences, go_router
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

ACTIVE CHECKLIST
See TODO.md at the root of the project for the master completion checklist covering the Python Backend, Admin Tools, and Flutter Frontend.

BACKEND STATUS
All 3 tests passing: test_model_upload.py, test_stream.py, test_violations.py
Active endpoints: /auth/login, /upload-model, /violations, /ws/video-feed,
                  /notifications/register-token, /settings/violations, /settings/mock
Violation detection logic documented at: hulikamote_backend/violation_detection_logic.md
Decoupled Engine (slicer, registry, ledger, pipeline) built in: hulikamote_backend/engine

KNOWN ISSUES AND QUIRKS
- Counterflow wrap bounds: X=1500, Y=450. If screen differs, these need adjustment.
- dart:math must be imported in every CustomPainter file or it will not compile.
- Timers must be cancelled in dispose() to prevent leaks. All current ones do this.
- Emoji in tab buttons may render as garbage bytes on some systems. Known issue.
- StaticCropVisualizer: car scaled down and offset -20px vertically to prevent overlap with slider panel.

DESIGN RULES LOCKED IN
- No jargon in any user-visible text. (Allowed replacements: the old way, compass needle, agreement meter, cardboard stencil, zone).
- Canvas is always left (flex 2), controls panel is always right (380px fixed).
- Visualizer container height: 550px. Road color: grey[700]. Car: blueGrey.
- Legal flow direction for all violations is Left to Right.
- Analogies locked: Old Way = cardboard stencil. Core Concept = compass needle.

FILE NAMING CONVENTION
[violation]_bf.dart         = Phase 0 (The Old Way)
[violation]_fp.dart         = Phase 1 (Core Concept)
[violation]_setup.dart      = Phase 2 (Real-World Setup)
[violation]_visualizer.dart = Phase 3 (Modern AI)

NEXT TASK FOR INCOMING BUILDER
1. **Flutter Visualizer:** Build Illegal Parking Phase 0, Phase 1, and Phase 2 visualizers (`illegal_parking_bf.dart`, `illegal_parking_fp.dart`, `illegal_parking_setup.dart`).
2. **Flutter Visualizer:** Add the remaining violations to `violation_data.dart` to reach the full 13-violation glossary.

CRITICAL GAPS IDENTIFIED (For Next Session)
- **The Visualizer Gap:** Illegal Parking lacks the educational step-by-step visualizers.

SESSION LOG HISTORY
See docs/SESSION_LOG.md
