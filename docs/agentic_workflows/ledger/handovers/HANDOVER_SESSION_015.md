# HULI-KAMOTE - MASTER HANDOVER
================================
LAST UPDATED: 2026-10-03 by Claude Sonnet 5.5 (Session 014)

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

READ THIS TABLE HONESTLY (added Session 014): "DONE" means the logic is implemented. It does NOT mean benchmarked.
No violation has a ground-truth clip, a scripted logic test, or a precision/recall/FP/FN score yet.
SCOPE MISMATCH to resolve with the user (do not invent or drop classes without direction):
- PROJECT_CONTEXT.md lists "Disregarding signs" and "Signal light violation": NOT in the table above.
- The table has Swerving, Crosswalk Obstruction, Distracted Driving, Over-speeding (stretch / not in the thesis list).
- "Restricted lane" is implemented in the pipeline but is in neither list.

ACTIVE CHECKLIST
See TODO.md at the root of the project for the master completion checklist covering the Python Backend, Admin Tools, and Flutter Frontend.

BACKEND STATUS
Tests (Session 014 run, backend venv, pytest-asyncio + coverage now installed there): 40 passed, 3 FAILED.
The 3 failures are NOT from Session 014 work and need updating: tests/test_model_upload.py (2: stale message text /
status code) and tests/test_providers.py::test_provider_resolution_defaults (provider is a string, test expects a tuple).
WARNING: tests/test_model_upload.py MUTATES the real models/ folder (switched models/active_model.txt, deleted
models/uploads/bad.zip, created models/Uncategorized/). Session 014 restored these by hand. Isolate that test (tmp dir).
Coverage (tools/project_map): pipeline.py 13%, forensic.py 11%, yolo_inference.py 27%, store.py 34%, ledger.py 55%, stream.py 49%.
Flutter dashboard has no tests at all.
New in Session 014: /api/forensic/tickets/{merge,split,move-frames,not-duplicate}, /api/forensic/send-to-live/{task_id},
/settings/video/upload, /api/train/{overview,history/{model},log/{task_id}}.
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

- **Tests that touch real files:** tests/test_model_upload.py rewrites the real models/ folder, and tests/test_stream.py rewrites
  models/active_model.txt; the app tests also rewrite the tracked test_hulikamote.db. build_map.py skips test_model_upload.py and restores
  the others from git. If you run the tests by hand, run `git checkout -- hulikamote_backend/models hulikamote_backend/test_hulikamote.db` after. Fix them to use temp dirs.
- **Windows import-order quirk:** importing onnxruntime before torch breaks torch's cuDNN DLL (WinError 127). tests/conftest.py now imports torch first.
- **[UNVERIFIED] Session 014 work has never run on real footage.** Tracker box fix, one-to-one ID mapping, track stitcher,
  evidence gap, plate-to-frame links, in-frame review UI, Send to Live Monitor, Training Studio. Only unit tests + analyzer.
  FIRST ACTION next session: restart backend, run one analysis, tick the checklist in the "NEXT TASK" section.
- **Backslashes get eaten in Bash heredocs** run through this tool (regex/escape bugs happened twice). Use the Write/Edit
  tools or chr(92) for anything with backslashes. PowerShell blocks `rd /s /q` style commands and misreads robocopy /E next to Remove-Item.
- **Slow Windows filesystem:** recursive ls/find/du over backend/snapshots or venv hangs. Use targeted paths or .NET EnumerateFiles.
- **Disk:** evidence photos reached ~27 GB (139k files) with no cleanup. Cleared in Session 014. Still no retention rule / Storage panel.
- Live Monitor config (camera_config.json) is local state rewritten by "Send to Live Monitor"; it pointed at a deleted video at wrap-up.
- hulikamote.db was wiped (5,198 tickets) at user request; a backup copy was only in the Session 014 scratchpad (temporary).
- export_ocr.py has uncommitted changes from before Session 014 (not touched). Scratch files at repo root (fix_forensic_import.py,
  safe_append.py, revert_ocr_labels.py, test_evidence_rendering.py, dummy*.mp4, *.pt, debug_test_evidence.jpg) are untracked leftovers.
- ReID training needs >=5 cars with 2+ photos (30+ recommended); datasets/reid currently has 2. Helmet/cabin/primary datasets are empty.
- Real-ESRGAN enhancer training is experimental (basicsr vs torchvision crash noted earlier); listed in Studio but unproven.
- The thesis PDF (docs/files/CH1-3-REVISED-new-2.pdf) could not be read in Session 014 (no PDF tool). Read it for metrics/scope.

DESIGN RULES LOCKED IN
- **Tracker box format (Session 014):** engine/tracker.py now sends CENTER [cx,cy,w,h] boxes to DeepSort.update (it expects centre,
  not top-left). Hyperparameters remain locked. yolo_inference.py maps tracker IDs to detections one-to-one by descending IoU.
- **One dataset root:** every training dataset lives under training_lab/datasets/ (plate_specialist, helmet_specialist, cabin_specialist,
  primary_anchor, plate_ocr = Pop Quiz corrections, reid = review decisions). The old training_lab/dataset/ folder no longer exists.
- **ReID data = review decisions:** every merge / separate / "different car" answer saves clean car crops to datasets/reid
  (images/<task>/<identity>/ + decisions.jsonl). train_reid.py deploys a new ckpt.t7 ONLY if it beats the current one on held-out photos.
- **Review lives inside the evidence frames** (TicketEvidenceReview): Different-car tick + separate, merge whole ticket or chosen frames,
  duplicate banner (Merge / Different car). Merge/split is not a separate dialog any more.
- **Uploaded forensic video is deleted after analysis** unless "Keep uploaded video" is on (Send to Live Monitor needs it).
- **Plate crops carry their time** and are linked to the nearest evidence frame (<=1 s) in evidence_meta (crop, plate); split moves crops with frames.
- **Evidence gap** (1-5) is a wizard setting (evidence_gap in the forensic config; live defaults to 5).
- **Project map / coverage:** python tools/project_map/build_map.py (needs graphify in its own env + coverage in the backend venv).
  Output: docs/project_map/ (index.html, RISK_TABLE.md). coverage_html is git-ignored.
- **Tracker Config Locked:** `tracker.py` DeepSORT hyperparameter matrix is maxed out mathematically. Do not attempt to tune. Focus moves to ReID model replacement if tracking needs improvement.
- **2D BBox Spatial Projection:** Vehicle mapping is strictly anchored at the bottom-center of the bounding box (`cy = y + h`) to perfectly map the tires to the 2D pavement polygons drawn in the UI.
- **Evidence Throttler Safety:** `pipeline.py` evidence capture is throttled, but it MUST guarantee a snapshot on Frame 1 (`_evidence_counter == 1`) to prevent race conditions on fast-moving violators dropping frames before OCR can extract the plate.
- **Dataset Synchronization:** Inline Pop Quiz buttons in the Forensic Analyzer (True/False Positive) automatically push the image context and corrected strings back to the SQLite Vault for dataset accumulation.

PROJECT MAPS (use these to orient FAST instead of reading many files)
- docs/project_map/ (in this repo, graphify + coverage): GRAPH_REPORT.md = hubs/groups, RISK_TABLE.md = files that are connected but under-tested,
  graph.html = interactive map, graph.json = the data behind it. ASK IT: python tools/project_map/ask.py explain|path|query "<exact name>"
  (see CLAUDE.md at the repo root; explain/path are precise, query only works with exact names; it cannot link Flutter to Python).
  The wrap-up (ORCHESTRATION_END step 6) rebuilds it automatically: python tools/project_map/build_map.py (graphify lives in ~/.graphify_env).
- Project Mapper (feature -> action -> code, with a replay of what really runs): lives OUTSIDE this repo at ../project_mapper
  (k_dev/project_mapper, its own git repo). Open ../project_mapper/outputs/huli-kamote/index.html. Rebuild: cd ../project_mapper && python pm.py huli-kamote.
  DO NOT edit ../project_mapper during HULI-KAMOTE work; it only reads this project (the tracer runs the app against a temp DB/folders).
  If a new endpoint/screen/button was added, rebuilding is enough; the user owns changes to the mapper itself.

NEXT TASK FOR INCOMING BUILDER
USER GOAL (Session 014): make the system ready so that only data gathering, harvesting, training and benchmarking remain.
Thesis metrics (PROJECT_CONTEXT.md): mAP@50, logging/organization accuracy rate, FP and FN rates tracked separately; all tests on pre-recorded footage.
0. **Verify Session 014 first** (restart backend + hot-restart dashboard, run one analysis with "Keep uploaded video" on):
   fewer duplicate tickets / no repeated track ID vs the old run (29 tickets, track 19 twice); [TrackEvent] lines in console;
   "Plate: XXXX" labels on evidence frames; Different-car tick + separate; merge chosen frames; duplicate banner; datasets/reid fills;
   Send to Live Monitor + Live Monitor plays; Training Studio lists all models with Guide/History tabs. Fix what fails BEFORE anything new.
   Then fix the 3 stale tests and isolate test_model_upload.py from the real models/ folder.
1. **Violation test foundation:** scripted-track logic tests for EVERY violation (no models needed), plus a ground-truth clip registry
   (clip + ROIs + expected events + pass criteria). Ask the user to settle the violation SCOPE mismatch first (see table notes).
2. **Benchmark runner:** run a clip through the pipeline, score precision / recall / FP / FN / logging accuracy per violation, write one comparable report.
3. **Model comparison:** baseline vs fine-tuned on the same held-out clips (mAP from validate.py + system-level scores), shown side by side.
4. **Readiness checklist per violation:** models needed, data needed, data present, testable today? Build the Virtual Traffic Light Simulator for Red Light.
5. **Then data:** helmet / cabin / primary datasets, harvest via review, train in Training Studio, benchmark.
6. Also pending: Storage panel + retention rule, raise tests on pipeline.py / forensic.py / yolo_inference.py (RISK_TABLE.md), Flutter tests.

Previous roadmap (still valid, WAIT FOR USER INSTRUCTION before starting any phase):
1. **Execute the Phased AI Roadmap (docs/AI_ROADMAP_PLAN.md):**
   - Phase 1: Support user in Active Data Harvesting (do not train yet, collect TP/FP data first).
   - Phase 2: Fine-tune YOLO plate_specialist and OCR.
   - Phase 3: Build the Virtual Traffic Light Simulator Widget in the UI to test Red Light violations.
   - Phase 4: Download Open-Source datasets to bootstrap Helmet/Phone specialist training.
   - Phase 5: Expose FastAPI REST endpoints (`GET /api/citizen/tickets`) to link the existing Flutter Mobile App.
   - **WAIT FOR EXPLICIT INSTRUCTION BEFORE STARTING ANY OF THESE PHASES.**

SESSION LOG HISTORY
See docs/SESSION_LOG.md
