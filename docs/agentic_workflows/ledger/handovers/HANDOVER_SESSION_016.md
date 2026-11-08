# HULI-KAMOTE - MASTER HANDOVER
================================
LAST UPDATED: 2026-10-19 by Claude Opus 5.5 / Sonnet 5.5 (Session 015, several parallel conversations)

PROJECT LOCATION
hulikamote_visualizer: C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_visualizer
hulikamote_backend:    C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_backend
hulikamote_dashboard:  C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_dashboard
hulikamote_app:        C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_app
training_lab:          C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\training_lab
New in Session 015 (the ORCHESTRATION_* repo maps were NOT edited: those files are immutable by the user's rule):
  Progress Report/                      presenter deck for the consultation (index.html + speaking_script.txt)
  tools/pending_patches/                two tested backend patches, not applied yet (see KNOWN ISSUES)
  training_lab/harvest_tool/, harvest.py   one-place training-data harvest (README inside)
  training_lab/lab_tui.py               terminal Training Lab (trains outside the backend)
  hulikamote_dashboard/lib/features/forensic/   rebuilt Forensic Analyzer (replaces features/monitoring/.../forensic_*)
  hulikamote_dashboard/lib/features/launcher/   side-nav entries: Progress Report, Visualizer
  hulikamote_backend/engine/marks.py, engine/model_catalog.py

STACK
Flutter desktop (Windows primary target)
Dependencies: flutter_math_fork, provider, shared_preferences, go_router, file_picker, web_socket_channel, http, media_kit (VLC-based video player)
Backend: FastAPI, SQLite, YOLOv8/11/26, ONNX, DeepSORT, EasyOCR, OpenCV, FFmpeg, MediaMTX
Training Lab: Ultralytics, textual + textual-plotext (terminal UI), roboflow (dataset download, user's own key), psutil
Custom AI Models: Real-ESRGAN / LPSRGAN (Image Enhancement), YOLO plate / helmet / cabin specialists

CURRENT PHASE DEFAULT
home_screen.dart currentPhase = 3 (Modern AI is the default focus)  [visualizer]

DETECTION STATUS - BACKEND (Session 015; all 14 thesis violations are now in scope, user decision)
violation | how it is detected | model needed | state
Counterflow            | movement against a zone's legal-flow arrow, sustained                         | none                 | rule + unit tests
Illegal parking        | stopped inside a zone longer than the time limit                              | none                 | rule + unit tests
Restricted lane        | vehicle class not allowed in the lane zone (not in the thesis list; kept)     | none                 | rule
Pedestrian lane        | stopped on a crosswalk zone > limit (default 3 s)                             | none                 | rule + unit tests
Illegal turn           | heading swings >= 45 deg into the drawn forbidden direction inside a zone     | none                 | rule + unit tests
Swerving               | left-right-left swings >= 0.5 box width within 6 s                            | none                 | rule + unit tests
Overloading            | riders counted per motorcycle (feet inside the bike), vote over looks, max 2  | person class         | rule + unit tests
Red light              | crosses the stop line while the light is red; light = camera colour or a     | none                 | rule + unit tests
                       | SIMULATED light (timer cycle, drawn on every frame + evidence)                |                      |
Disregarding signs     | per-sign zones: no entry, no turn, no stopping, vehicle ban, stop sign        | none                 | rule + unit tests
Signal light           | turn without a blinking indicator (amber on/off on the box edges)            | none (heuristic)     | rule + unit tests; may over-flag (see ISSUES)
No plate               | no plate in any fair look; PENDING while on screen, decided when it leaves   | plate (exists)       | rule + unit tests
No helmet              | helmet model on motorcycle + riders crop, vote                                | helmet (TRAINED)     | rule + fake-model tests
No seatbelt            | cabin model on cars (tinted window = no judgement), vote                      | cabin (TRAINED)      | rule + fake-model tests
Missing side mirror    | cabin model, only judged when the bike faces toward/away from the camera      | cabin (NO mirror data)| code only: cannot work yet
Distracted driving     | cabin model phone class (not in the thesis list)                              | cabin (TRAINED)      | rule + fake-model tests
Not implemented: over-speeding, crosswalk-vs-light combos, anything else from the visualizer table below.
No violation has been SCORED on real footage: there is no ground-truth clip registry or benchmark runner yet.
"Why" boxes (engine/marks.py) show the exact part for no helmet / overloading / seatbelt / phone / mirror / no plate.

VIOLATION STATUS TABLE (VISUALIZER teaching phases - this is the educational app, NOT the backend)
Format: violation | cat | p0_old_way | p1_concept | p2_setup | p3_modern_ai | notes
Counterflow       | MC  | DONE       | DONE       | DONE     | DONE         | Ray-casting, flow vector dot product, pointPolygonTest ROI gating
Illegal Parking   | MC  | DONE       | DONE       | DONE     | DONE         | Polygon ROI, Stationary frame accum (5.0s threshold)
No Plate Number   | Car | DONE       | DONE       | DONE     | DONE         | End-to-End ANPR Pipeline
Swerving          | EXT | DONE       | DONE       | DONE     | DONE         | Lateral jerk calculation
Illegal Turn      | MC  | DONE       | DONE       | DONE     | DONE         | Trig angle gating
No Helmet         | MC  | DONE       | DONE       | DONE     | DONE         | Geometric IoU, temporal voting
Missing Side Mirror| MC | DONE       | DONE       | DONE     | DONE         | Sub-crop, Count < 2
Overloading       | MC  | DONE       | DONE       | DONE     | DONE         | 80% overlap, Posture classification
Red Light Running | Car | DONE       | DONE       | DONE     | DONE         | Dual-ROI spatial conjunction
No Seatbelt       | Car | DONE       | DONE       | DONE     | DONE         | Tinted Window Override Gate
Crosswalk Obstruct| Car | DONE       | DONE       | DONE     | DONE         | Speed=0 AND Light=RED
Distracted Driving| Car | DONE       | DONE       | DONE     | DONE         | Cabin Specialist (phone detection)
Over-speeding     | EXT | DONE       | DONE       | DONE     | DONE         | Perspective Transform, KPH
MC = Motorcycle/Car, Car = Cars only, EXT = Extended. No visualizer work was done in Session 015.

ACTIVE CHECKLIST
See TODO.md at the root of the project for the master completion checklist covering the Python Backend, Admin Tools, and Flutter Frontend.

MODELS (Session 015) - one ACTIVE model per job, shown in the dashboard Models tab (GET /models/catalog)
vehicles: yolo11_primary.onnx (stock COCO-trained, active)   helmet: helmet_specialist_train-2_20261005.onnx
plate:    plate_specialist_train2_20260924.onnx (OLD data, not retrained)   cabin: cabin_specialist_train_20261013.onnx
Scores below are Ultralytics VALIDATION-split numbers at imgsz 640 (the app feeds 320); the test split was never evaluated; NOT field accuracy.
Saved best.pt is chosen by fitness = 0.1*mAP50 + 0.9*mAP50-95, not by max mAP50:
  helmet  epoch 32/62   mAP50 0.978  mAP50-95 0.762  P 0.958  R 0.949
  cabin   epoch 70/100  mAP50 0.788  mAP50-95 0.628  P 0.957  R 0.775  (just under the 0.80 target; no tinted-window / mirror data)
  plate   epoch 82/100  mAP50 0.765  mAP50-95 0.333  P 0.778  R 0.741   (v1, trained on the old plate set)
  vehicles: a run on the 6-class vehicle set is INTERRUPTED at epoch 23 of 30 (Continue resumes it); not deployed, the stock model is in use.
  helmet run "train" (19/100) was killed by a backend reload and abandoned; "train-2" (finished, early stop at 62) is the real one.
engine/model_catalog.py and lab_tui.py still show the max-mAP50 epoch (e.g. helmet 0.987): fix to use fitness.

BACKEND STATUS
Tests (backend venv, test_model_upload.py excluded because it rewrites the real models/ folder): 105 passed, 1 failed.
  The failure is tests/test_providers.py::test_provider_resolution_defaults (stale: provider is a string, test expects a tuple).
  tests/test_model_upload.py has 2 more stale failures (message text / status code) and still mutates models/ (not run this session).
Harvest tests (training_lab/tests/test_harvest.py): 20 passed. Dashboard: flutter test 95 passed, 2 failed; flutter analyze 0 errors, 37 notes.
  The 2 Flutter failures (live_monitoring_screen_test "renders VideoFeedWidget and AlertListWidget", video_feed_widget_test "Shows MOCK badge
  and detection on frame arrival") ALSO fail on the previous commit (checked on a clean copy): stale tests, not caused by Session 015.
Coverage / risk: docs/project_map/RISK_TABLE.md (rebuilt at wrap-up). pipeline.py, forensic.py, yolo_inference.py are still the least tested hubs.
New endpoints: /models/catalog, /models/catalog/activate, /api/train/state/{model}, /api/train/pause/{model}, /api/train/resume/{model},
  /api/train/open-lab. Earlier endpoints (Session 014) unchanged.
Decoupled Engine (slicer, registry, ledger, pipeline) in hulikamote_backend/engine. Model organization: Vehicle Detectors, Helmet Detectors,
  Plate Models, Cabin Models, GAN Enhancers folders + model_manifest.json (the registry loads the deployed helmet / cabin model from it).

KNOWN ISSUES AND QUIRKS
- **[CRITICAL] Memory Rule:** Never implement new modules or execute training runs without explicit instruction from the user. (Wait for commands after fixes).
- **Do not edit anything under hulikamote_backend/ (or pip install into its venv) while a training started from Training Studio is running.**
  The backend runs uvicorn --reload: any write there restarts it and kills Studio-started trainings (Session 015 lost a training this way).
  Trainings started from the terminal Training Lab (lab_tui.py) or with Continue run detached and survive. Check first:
  Get-CimInstance Win32_Process for train.py / uvicorn.
- **Model input mismatch (measured 2026-10-13 with `python training_lab/harvest.py probe-input`; re-run to confirm):** the app feeds the
  specialist models BGR (models were trained on RGB), plain-stretched to 320x320 (no letterbox), and the plate model only sees the bottom 40%
  of the vehicle box. On held-out labelled photos the plate was found 7% of the time as the app feeds it, 85% with RGB + letterbox + whole
  vehicle. Only 51% of plates sit in the bottom 40% (diagonal CCTV). 18% of 28 real "no plate" tickets had a plate the model finds when fed
  properly. _run_specialist_onnx also has no NMS (mirror counts are inflated). FIX NOT APPLIED: engine/pipeline.py _preprocess_crop,
  yolo_inference.preprocess, _run_plate_check, _run_specialist_onnx. Do this BEFORE retraining the plate model, then re-run probe-input.
- **Pending backend patches (written + tested on a copy, NOT applied):** tools/pending_patches/README.md. stall_fix: Studio status/state endpoints
  blocked the event loop 150-600 ms every 2-4 s, so live video froze on that rhythm while a training ran (dashboard side is fixed with
  VisiblePoller). plate_edit: POST /api/forensic/tickets/set-plate (the review screen's "Save plate" shows "needs a backend update" until applied).
  Apply when nothing trains, then run the backend tests.
- **Training data is NOT Zamboanga and mostly not Philippine (checked 2026-10-13):** plate sets are grayscale parking-barrier photos with Vietnamese
  plates; helmet set is mostly stock photos of people on scooters; cabin sets are front/top-down car photos with Arabic-script plates; the vehicle set is
  mixed countries (tricycle only 76 val / 25 test). `ph_plates` in datasets_manifest.yaml is a misnomer. Never call these datasets Philippine
  or Zamboanga without qualification. Real accuracy needs the user's own footage (harvest loop).
- **No plate-to-owner registry:** users are keyed by driver's licence number; a plate never matches, so Confirm notifies nobody. The review
  screen says so. Needs a plate_no on users + demo plates. User: "we'll handle the sending later".
- **Studio's Start button trains inside the backend** (dies on a backend reload): use the terminal Training Lab or Continue.
- **Forensic Analyzer was rebuilt by a parallel session** (12k lines, widget-tested only). The old monitoring/forensic_* files are deleted.
  Re-verify all 14 violations through the new wizard on real clips (zones, arrows, stop lines, light box, sign type).
- **Signal-light rule can over-flag:** RA 4136 s44 accepts hand signals and s34(f) exempts motorcycles from signal lights. Legal basis for red light /
  disregarding signs is JAO 2014-01 + MMDA/LGU codes (RA 4136 has no general "obey signals" rule); side mirror is LTO AO AHS-2008-015.
  Fines quoted from news are unverified. NCAP: Supreme Court TRO Aug 2022, partly lifted May 2025, petitions dismissed as moot mid-2026
  without ruling on validity. Details are in the Progress Report deck (Appendix E).
- **Windows: os.kill(pid, 0) TERMINATES the process.** Use psutil.pid_exists(pid).
- **Disk:** evidence photos reached ~27 GB in Session 014 (cleared). Each evidence frame now also saves a clean wider crop (for the harvest tool),
  so disk use per flagged car went up. Still no retention rule / Storage panel.
- **Launcher entries (Progress Report, Visualizer) only work from a repository checkout**, not from a packaged install. The built visualizer
  exe was dated Sep 11 (the app warns when it is older than the source).
- **Cleanup candidates (safe to delete; the permission guard blocked my delete, so left for the user):** repo-root `runs/` (17 MB, created when
  a plate resume was started from the wrong folder), `k_dev/datasets/coco8/` (same cause, outside the repo), `training_lab/train|valid|test|data.yaml|
  README.dataset.txt|README.roboflow.txt` (a rejected Roboflow download: 21 "no helmet" labels). All are git-ignored now.
- **Local state deliberately NOT committed:** hulikamote_backend/camera_config.json, hulikamote.db, training_lab/scripts/export_ocr.py (uncommitted
  changes from before Session 014), docs/read_later/ (the user's notes).
- **ONNXRuntime & CUDA Mapping:** `onnxruntime-gpu>=1.30.0` has dropped support for CUDA 12.x out-of-the-box on Windows. Peg to `onnxruntime-gpu==1.26.0` to maintain PyTorch `cu121` parity.
- **BasicSR vs Torchvision Failure:** Standard `basicsr` crashes on newer torchvision. Must instantiate `RRDBNet` PyTorch `nn.Module` manually inline to export ESRGAN `.pth` to `.onnx`.
- **Flutter UI Quirks:** Modifying a parent StatefulWidget's variables (like `_tickets` or `_controller`) from a secondary tab breaks tab-isolation. History playback must be handled via distinct routes (`Navigator.push`) with their own `State` classes to prevent wiping out the user's primary workspace.
- **Tests that touch real files:** tests/test_model_upload.py rewrites the real models/ folder, and tests/test_stream.py rewrites models/active_model.txt;
  the app tests also rewrite the tracked test_hulikamote.db. After a manual run: `git checkout -- hulikamote_backend/models/active_model.txt hulikamote_backend/test_hulikamote.db`
  (NOT the whole models/ folder: model_manifest.json is the deployed-model pointer). build_map.py restores `hulikamote_backend/models` from git, so commit
  model_manifest.json before a map rebuild. Fix the tests to use temp dirs.
- **Windows import-order quirk:** importing onnxruntime before torch breaks torch's cuDNN DLL (WinError 127). tests/conftest.py imports torch first.
- **Backslashes get eaten in Bash heredocs** run through this tool (regex/escape bugs happened again in Session 015). Use the Write/Edit tools or a script
  file for anything with backslashes. PowerShell blocks `rd /s /q` style commands.
- **Slow Windows filesystem:** recursive ls/find/du over backend/snapshots or venv hangs. Use targeted paths or .NET EnumerateFiles. Counting ~30k dataset files takes minutes.
- Live Monitor config (camera_config.json) is local state rewritten by "Send to Live Monitor".
- ReID training needs >=5 cars with 2+ photos (30+ recommended); datasets/reid has 2 cars. plate_ocr has 42 corrections. The OCR trainer cannot run as installed
  (EasyOCR's pip package has no trainer; PaddleOCR training tools missing).
- The thesis PDF (docs/files/CH1-3-REVISED-new-2.pdf) could not be read in Session 014/015 (no PDF tool). Read it for metrics/scope when possible.

DESIGN RULES LOCKED IN
- **Tracker box format (Session 014):** engine/tracker.py sends CENTER [cx,cy,w,h] boxes to DeepSort.update. Hyperparameters locked: do not tune. If tracking
  must improve, replace the ReID model.
- **One dataset root:** every training dataset lives under training_lab/datasets/. Public sets are merged in by scripts/fetch_datasets.py from
  configs/datasets_manifest.yaml (files named <id>__*, git-ignored). A photo that is in train AND val/test is moved into train automatically.
- **ReID data = review decisions; plate_ocr = Pop Quiz corrections; harvest_inbox = harvested pictures** (all git-ignored, local).
- **Review lives inside the evidence frames.** Confirm records the violation but notifies nobody yet (no plate registry).
- **Pending vs final decisions (Session 015):** a suspicion is only PENDING while the vehicle is on screen (ledger.pending); it becomes a ticket in
  decide_end_of_track / finalize_all when the vehicle leaves or the video ends. No Plate works this way (a plate found later clears it and deletes the
  photos taken for the suspicion). Model-based checks (helmet, seatbelt, phone, mirror, overloading) use ledger.vote over recent looks, never a single frame.
- **Marks follow the vehicle:** engine/marks.py stores boxes relative to the vehicle box, shows them only while the violation is flagged/pending and fresh
  (3 s); red (violation) boxes are drawn last. Live monitoring does not draw them: det.marks is set on the detection, but routers/stream.py
  builds the live JSON field by field and does not include it (add it there, then draw it in the Flutter overlay). While a No Plate suspicion is pending
  the live overlay label reads "no_plate?" (display only; live tickets still come only from the end-of-track queue).
- **One active model per job** (vehicles / helmet / plate / cabin), switched in the Models tab. Deployed models go to their category folder and
  model_manifest.json. Forensic analysis uses the active vehicle detector unless the wizard names one. Plate model: chosen per analysis, default = active.
- **Pause = stop the training process, Continue = Ultralytics resume from weights/last.pt** (the unfinished epoch restarts). A finished run
  (last.pt epoch = -1, including early-stopped) cannot be resumed. State is read from runs/<model>/<run>/results.csv + last.pt (scripts/run_state.py).
- **Harvest tool rules (training_lab/harvest_tool/README.md):** never writes inside hulikamote_backend; never touches a dataset while that model
  trains; never uploads; a human checks every picture; benchmark clips are protected with `harvest.py protect <task_id>`; frames of one car stay on one
  side of the train/val split; the test split is never written. Add a violation = one row in ROUTES (collect.py). Rule-only violations are not harvested.
- **Polling:** dashboard timers use VisiblePoller (follows page visibility). Backend endpoints that are polled must be plain `def` or run in a thread and must
  never return a whole training log.
- **2D BBox Spatial Projection:** Vehicle mapping is strictly anchored at the bottom-center of the bounding box (`cy = y + h`) to map the tires to the 2D pavement polygons drawn in the UI.
- **Evidence Throttler Safety:** `pipeline.py` evidence capture is throttled, but it MUST guarantee a snapshot on Frame 1 (`_evidence_counter == 1`).
- **Simulated traffic light:** red-light zones in "Virtual light" mode follow a timer cycle (red start, red/green/yellow seconds); the light and a countdown
  are drawn on every result-video frame and evidence photo; the stop line is drawn in the light's colour.

PROJECT MAPS (use these to orient FAST instead of reading many files)
- docs/project_map/ (in this repo, graphify + coverage): GRAPH_REPORT.md = hubs/groups, RISK_TABLE.md = files that are connected but under-tested,
  graph.html = interactive map, graph.json = the data behind it. ASK IT: python tools/project_map/ask.py explain|path|query "<exact name>"
  (see CLAUDE.md at the repo root; explain/path are precise, query only works with exact names; it cannot link Flutter to Python).
  The wrap-up (ORCHESTRATION_END step 6) rebuilds it automatically: python tools/project_map/build_map.py (graphify lives in ~/.graphify_env).
- Project Mapper (feature -> action -> code, with a replay of what really runs): lives OUTSIDE this repo at ../project_mapper
  (k_dev/project_mapper, its own git repo). Open ../project_mapper/outputs/huli-kamote/index.html. Rebuild: cd ../project_mapper && python pm.py huli-kamote.
  DO NOT edit ../project_mapper during HULI-KAMOTE work; it only reads this project.

BRANCHES (Session 015 micro-commits; STACKED: each branch contains the one before it, in this order)
nekolaiv/chore-repo-hygiene > backend-violation-evidence > model-catalog > trained-models > training-data-harvest > training-run-control >
dashboard-forensic-workspace > dashboard-launchers > tools-pending-patches > docs-progress-report > docs-session-015 (ledger + maps).
nekolaiv/polishing-progress was fast-forwarded to the last one. Merge the tip (or the branches in this order); do not merge them independently.

NEXT TASK FOR INCOMING BUILDER
USER GOAL (end of Session 015): additional features, solidifying tests, revisions from the thesis consultation, and deploying to potential users.
WAIT FOR EXPLICIT INSTRUCTION before starting a feature. Suggested order (ask the user to confirm):
0. **Housekeeping (nothing may train):** apply tools/pending_patches (stall_fix, then plate_edit) and run the backend tests; delete the cleanup candidates above
   if the user agrees; restart backend + hot-restart dashboard.
1. **Consultation revisions:** ask the user for the panel's comments and turn each into a checklist item in TODO.md before anything else.
2. **Fix the model input mismatch** (RGB + letterbox + whole-vehicle plate search + NMS), re-run `harvest.py probe-input` to show the gain, then retrain the plate
   model on the plate set + `harvest.py cut-plates` crops, deploy, compare on the same photos. Biggest free accuracy gain.
3. **Solidify tests:** the 3 stale backend tests + isolate test_model_upload.py (temp dirs); fix or replace the 2 stale Flutter live-monitoring tests; raise coverage
   on engine/pipeline.py, routers/forensic.py, yolo_inference.py (RISK_TABLE.md); an end-to-end test of one forensic run on a short clip; run the backend tests in CI.
4. **Benchmark + real-footage check:** ground-truth clip registry (protect those clips from harvesting), runner scoring precision / recall / FP / FN per
   violation, mAP on the test split (validate.py), model comparison v8 / 11 / 26 on the same clips. First have the user run each violation on a clip and report
   Caught / False alarms / Missed; tune thresholds (45 deg turn, swerve width, vote shares) from that.
5. **Deployment readiness:** plate -> owner registry + notification (RA 10173 review of what is stored and shown), packaging (backend + dashboard installers or a
   single start script), configuration + secrets handling, authentication for operators, storage retention rule + Storage panel, backup of the SQLite DB,
   logging, a pilot checklist with potential users (LTO / LGU). Decide the camera path (recorded clips vs live) first.
6. **Feature backlog:** new violations in the live camera wizard and offline screen (only the forensic wizard has them), marks in the live overlay, the ticket should
   say which sign was broken, model_catalog / lab_tui pick the best epoch by fitness, Studio Start button should train detached, stop line without an arrowhead.
7. **Data:** collect Zamboanga footage, run the harvest loop (collect -> check -> accept -> train -> deploy -> benchmark), label tinted windows and motorcycle mirrors
   (no public data exists), retrain cabin and plate.

SESSION LOG HISTORY
See docs/SESSION_LOG.md
