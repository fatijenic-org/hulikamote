# HULI-KAMOTE - MASTER HANDOVER
================================
LAST UPDATED: 2026-11-01 by Copilot SDK (Session 018)

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

New in Session 016 (the ORCHESTRATION_* repo maps were again NOT edited: immutable by the user's rule; they list top-level folders and none was added):
  hulikamote_backend/engine/violations/   one module per violation (20), the pipeline only calls their hooks; engine/flow_field.py + flow_prescan.py (learned traffic
                                          direction), engine/camera_source.py (RTSP / HTTP / webcam, newest frame, reconnect)
  hulikamote_dashboard/lib/features/{benchmark,blueprint}/   Benchmark tab, Code Reference (code + "How it's tested" per feature)
  tools/benchmark/, benchmarks/           benchmark runner + clip registry (EMPTY) + clip checklist;  tools/tests_index.py  (which test ran which function)
  training_lab/data.py, data_tools/, datasets/CATALOG.md + DATASET_CARD.md   dataset library (fetch, merge, clean, document)
  training_lab/harvest_tool/{frames,pairs,cars,reid_export}.py   Vehicles + missed vehicles, "Same car?", cars one by one, ReID export
  training_lab/scripts/reid_ab.py         suspected ID jumps, old vs new car matcher on one clip (writes only training_lab/runs/reid_ab/)
  training_lab/experiments/reid/          ReID evidence: RESULTS.md, two reproducible scripts, run logs
  docs/THESIS_REVISIONS.md                thesis wording: scope 13 -> 20, live demo, camera angle, heuristics, evaluation protocol

New in Session 017 (ORCHESTRATION_* files remain untouched per the user's rule):
  hulikamote_dashboard/lib/features/datasets/  native Flutter Dataset Viewer; the Python helper remains its local, token-protected data service
  training_lab/dataset_viewer/README.md       distinguishes the dashboard UI from the standalone browser UI
  Commit: 7e91831 feat(dashboard): open dataset viewer natively

New in Session 018 (ORCHESTRATION_* files remain untouched per the user's rule):
  Dataset Viewer Relabel tab: box-crop review, selection/rule previews, atomic label writes, undo, relabeled filter, and card regeneration
  Python rollback coverage for action-log failures; dashboard widget flow and training-lab suite pass

STACK
Flutter desktop (Windows primary target)
Dependencies: flutter_math_fork, provider, shared_preferences, go_router, file_picker, web_socket_channel, http, media_kit (VLC-based video player)
Backend: FastAPI, SQLite, YOLOv8/11/26, ONNX, DeepSORT, EasyOCR, OpenCV, FFmpeg, MediaMTX
Training Lab: Ultralytics, textual + textual-plotext (terminal UI), roboflow (dataset download, user's own key), psutil
Custom AI Models: Real-ESRGAN / LPSRGAN (Image Enhancement), YOLO plate / helmet / cabin specialists

CURRENT PHASE DEFAULT
home_screen.dart currentPhase = 3 (Modern AI is the default focus)  [visualizer]

DETECTION STATUS - BACKEND (Session 016; 20 violations registered in engine/violations/, one module each, with a test guard)
zone rules (12)   counterflow (drawn zone or LEARNED flow), illegal_parking, restricted_lane, pedestrian_lane, illegal_turn, swerving, red_light (camera colour
                  or SIMULATED light), disregarding_signs (per-sign zones), signal_light (heuristic, EXPERIMENTAL: may over-flag), illegal_u_turn,
                  blocking_intersection, crossing_solid_line                                                  -> rule + unit tests
frame checks (3)  overloading (riders per motorcycle, vote), pickup_passengers, riding_outside_vehicle         -> rule + unit tests
model checks (5)  no_plate (plate model, decided when the vehicle leaves), no_helmet (helmet model), no_seatbelt + distracted_driving + missing_side_mirror (cabin model;
                  mirror still has NO verified mirror data: first data found 2026-10-25, not trained)           -> rule + fake-model tests
New in Session 016 and NEVER seen on real footage: pickup_passengers, riding_outside_vehicle, illegal_u_turn, blocking_intersection, crossing_solid_line (legal wording TO CONFIRM).
NO violation has been SCORED on real footage: the benchmark registry (benchmarks/registry.yaml) is EMPTY (`clips: []`); of 428 forensic tickets in the database only 4
(all counterflow) were ever reviewed by a person. See DEFENSE READINESS below.
"Why" boxes (engine/marks.py) show the exact part; the live overlay now draws them too ("Use for Live Monitor" work).

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
Tests at the end of Session 016 (all green): backend 284 passed (hulikamote_backend/tests, mirrors the source tree; the 3 stale tests were fixed and the tests that wrote
into real folders were isolated, commit 0402c4e); training_lab 91 passed; dashboard `flutter test` 217 passed (2 skipped); `flutter analyze` on the changed folders: only
old notes. Coverage / risk: docs/project_map/RISK_TABLE.md and docs/project_map/tests_index.json (rebuilt at wrap-up).
Models (unchanged): vehicles yolo11_primary.onnx (stock COCO: NO tricycle / jeepney class), helmet_specialist_train-2_20261005, plate_specialist_train2_20260924 (v1, Vietnamese
data, still not retrained), cabin_specialist_train_20261013. Best validation mAP50 from the run folders (each dataset's OWN validation split, not field accuracy): plate 0.77,
helmet 0.99, cabin 0.80, 6-class vehicle set 0.68 (stopped at epoch 23, not deployed). Models are fed RGB + letterbox now (the Session 015 "input mismatch" is FIXED,
commit 2ae2d04: plate found 7% -> 83% on held-out photos).
New endpoints: POST /api/forensic/live-config, /settings/video/test, /video/status, /camera-profiles, /api/benchmark/* (tools/benchmark/api.py), set-plate, /ws status messages.
Harvest helper (training_lab/harvest.py serve, started by the dashboard with pythonw.exe, stops after 30 idle minutes) speaks API 4: /api/session, /api/queue, /api/save,
/api/skip, /api/collect, /api/pairs, /api/pair, /api/cars, /api/car, /api/cars/fill; the dashboard replaces an older helper by itself (/api/ping reports `api`).

DEFENSE READINESS (strict assessment, 2026-10-27; verified in the repo, not guessed)
1. No accuracy numbers on real footage for ANY violation (registry empty; 4 of 428 tickets reviewed). The model scores above are validation-split numbers.
2. Plate reading on the user's local clip is weak: crossing clip 9db131ee (Zamboanga, 4K, wide angle, rain): 4 of 61 tickets had a plate read at all. Plate model = Vietnamese v1.
   The live config (camera_config.json) has plate_format uk_standard: set ph_standard for a local demo.
3. Local evidence is thin: only ONE local clip is confirmed (9db131ee, same clip as 0c0363de); the analyses with readable plates (0a51c09e, 1b4be534, 39cda55b, 6ca9224e,
   7ce549fd, e8f42772) are UK footage (the same clip re-run). The project's own clip rules say no heavy rain in the main test set.
4. Promised in docs/PROJECT_CONTEXT.md but NOT in the code (searched backend, app, dashboard): SMTP email notices, privacy masking (RA 10173), demerit points.
   Push notifications (Firebase) and the appeals screen exist. Decide: implement small versions or reword the scope WITH team approval.
5. 20 violations coded, none scored; the two no_helmet analyses (09879f31, 29d417a9) produced 0 tickets (unknown whether the clips had violations).
6. Live demo never rehearsed: "Use for Live Monitor" not tried by hand, no phone / RTSP rehearsal, no 30-minute stability run.
7. Traps: the wizard defaults to ByteTrack (leaves 58% of detections untracked): always choose DeepSORT (live config is DeepSORT). COCO detector has no tricycle / jeepney class.
8. Legal bases TO CONFIRM (4 violations, penalty figures unverified); 34 commits exist only on this laptop (dev is 34 ahead of origin/dev); Firebase key NOT rotated and still
   in remote history; this handover, the deck and the project maps were stale before this wrap-up.

KNOWN ISSUES AND QUIRKS
- **[CRITICAL] Memory Rule:** Never implement new modules or execute training runs without explicit instruction from the user. (Wait for commands after fixes).
- **Do not edit anything under hulikamote_backend/ (or pip install into its venv) while a training started from Training Studio is running.**
  The backend runs uvicorn --reload: any write there restarts it and kills Studio-started trainings (Session 015 lost a training this way).
  Trainings started from the terminal Training Lab (lab_tui.py) or with Continue run detached and survive. Check first:
  Get-CimInstance Win32_Process for train.py / uvicorn.
- **Model input mismatch: FIXED 2026-10-24 (commit 2ae2d04).** The specialists are fed RGB + letterbox + the whole vehicle box, with NMS (plate found 7% -> 83%). The plate
  model itself is still the old Vietnamese-data v1: retrain it (harvest the plate pictures first); re-run `harvest.py probe-input` to compare.
- **Backend patches stall_fix and plate_edit are APPLIED** (711737f, a025da8, 2026-10-24); tools/pending_patches is history. Review "Save plate" works (set-plate).
- **Training data is NOT Zamboanga and mostly not Philippine (checked 2026-10-13; the 2026-10-25 dataset library merged more Roboflow sets, see datasets/CATALOG.md):** plate sets are
  grayscale parking-barrier photos with Vietnamese plates; helmet / cabin sets are mostly foreign stock-like photos. Never call them Philippine or Zamboanga without
  qualification. Real accuracy needs the user's own footage (harvest loop). The only local clip so far is 9db131ee.
- **No plate-to-owner registry:** users are keyed by driver's licence number; a plate never matches, so Confirm notifies nobody. The review
  screen says so. Needs a plate_no on users + demo plates. User: "we'll handle the sending later".
- **Studio's Start button trains inside the backend** (dies on a backend reload): use the terminal Training Lab or Continue.
- **Forensic Analyzer was rebuilt by a parallel session** (12k lines, widget-tested only). The old monitoring/forensic_* files are deleted.
  Re-verify all 14 violations through the new wizard on real clips (zones, arrows, stop lines, light box, sign type).
- **Signal-light rule can over-flag:** RA 4136 s44 accepts hand signals and s34(f) exempts motorcycles from signal lights. Legal basis for red light /
  disregarding signs is JAO 2014-01 + MMDA/LGU codes (RA 4136 has no general "obey signals" rule); side mirror is LTO AO AHS-2008-015.
  Fines quoted from news are unverified. NCAP: Supreme Court TRO Aug 2022, partly lifted May 2025, petitions dismissed as moot mid-2026
  without ruling on validity. Details are in the Progress Report deck (Appendix E).
- **ReID (2026-10-27):** the Studio's Car Matching trainer (scripts/train_reid.py) now judges on CARS IT NEVER SAW (its old check scored held-out photos of the trained cars, where
  the old model already gets 98.6%, so it could never deploy a better model). It AUTO-DEPLOYS when it passes (+2 points rank-1, mAP not lower, 8+ cars): keeps ckpt_original.t7 and a
  timestamped backup next to ckpt.t7; restart the backend after. Evidence: training_lab/experiments/reid/RESULTS.md (same cameras, new cars: rank-1 76.7 -> 85.3%; a different road: no gain).
  File ONE analysis per clip (re-runs of a clip repeat the same cars and would teach "one car = several cars"). Harvest > Same car? > "Rest are fine" files the unopened cars.
  The Market-1501 script hulikamote_backend/engine/deep_sort/deep/train.py is broken (crashes on non-64x128 pictures; NameError after epoch 1 without --resume): NOT fixed, it sits under
  hulikamote_backend. `harvest.py reid-export` makes its input if ever needed. scripts/reid_ab.py (jump counter) was only smoke-tested: the one kept clip's cars were trained on.
- **Keep the uploaded video** (wizard switch) is needed for the Vehicles tile, missed-vehicle pictures and reid_ab.py; only 2 analyses kept theirs. Cars only get photos when ticketed.
- **GPU:** the laptop RTX 3050 runs at 337 of 2100 MHz under load (SW power cap), so trainings are slow (a ReID epoch of 800 photos ~30 s). Windows "Best performance" should help.
- **Another session's work was in the tree at wrap-up (NOT committed, not mine):** decision_panel.dart (CodeInspectorTooltip), hulikamote_dashboard/lib/core/widgets/, test/core/widgets/
  ("Explain on hover", TODO step 3). Never commit them from a harvest / ReID session.
- **Windows: os.kill(pid, 0) TERMINATES the process.** Use psutil.pid_exists(pid).
- **Disk:** evidence photos reached ~27 GB in Session 014 (cleared). Each evidence frame now also saves a clean wider crop (for the harvest tool),
  so disk use per flagged car went up. Still no retention rule / Storage panel.
- **Launcher entries (Progress Report, Visualizer) only work from a repository checkout**, not from a packaged install. The built visualizer
  exe was dated Sep 11 (the app warns when it is older than the source).
- **Dataset Viewer (Sessions 017-018):** Datasets opens natively in the dashboard, About renders the card as Markdown, and Relabel provides crop review, confirmed bulk changes, undo, and a card-stale/regenerate flow. Python and Flutter tests pass. Hand-test the full workflow against real `primary_anchor` data only when training is idle; suspected-mislabel ONNX review remains a possible later step.
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
- ReID training needs >=5 cars with 2+ photos (8+ to be allowed to deploy, 30+ recommended); datasets/reid has about 20 filed cars (2026-10-27). plate_ocr has 42 corrections. The OCR trainer cannot run as installed
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
- **Harvest (Session 016):** per analysis (Review | Harvest), one picture at a time, full screen; tiles = Plates / Helmets / Cabin / Vehicles (primary_anchor frames from the kept video) /
  Same car? (cars one by one + quick look-alike questions). Missed vehicles (no ticket) come from the same frames. `COLLECT_VERSION` (collect.py) makes older analyses gather once more.
  The enforcer's right panel is only the plate fix ("Send plate"). Corrections go to datasets/reid exactly like the review screens write them; tickets never change.
- **Simulated traffic light:** red-light zones in "Virtual light" mode follow a timer cycle (red start, red/green/yellow seconds); the light and a countdown
  are drawn on every result-video frame and evidence photo; the stop line is drawn in the light's colour.
- **Dataset Viewer:** the dashboard owns the native browsing UI; the Python helper remains the single authority for indexing, safe writes, quarantine, and undo. Do not open the system browser from the Datasets side-nav entry.

PROJECT MAPS (use these to orient FAST instead of reading many files)
- docs/project_map/ (in this repo, graphify + coverage): GRAPH_REPORT.md = hubs/groups, RISK_TABLE.md = files that are connected but under-tested,
  graph.html = interactive map, graph.json = the data behind it. ASK IT: python tools/project_map/ask.py explain|path|query "<exact name>"
  (see CLAUDE.md at the repo root; explain/path are precise, query only works with exact names; it cannot link Flutter to Python).
  The wrap-up (ORCHESTRATION_END step 6) rebuilds it automatically: python tools/project_map/build_map.py (graphify lives in ~/.graphify_env).
- Project Mapper (feature -> action -> code, with a replay of what really runs): lives OUTSIDE this repo at ../project_mapper
  (k_dev/project_mapper, its own git repo). Open ../project_mapper/outputs/huli-kamote/index.html. Rebuild: cd ../project_mapper && python pm.py huli-kamote.
  DO NOT edit ../project_mapper during HULI-KAMOTE work; it only reads this project.

BRANCHES (Session 017)
Work continues on local `dev` (fast-forwarded to nekolaiv/module-split on 2026-10-27; module-split is kept as is). `main` is only the initial commit. 41 commits since the Session 015
wrap-up plus the native Dataset Viewer commit 7e91831, in small conventional commits. NOTHING is pushed: dev is 34 commits ahead of origin/dev (last push base 3fe1e4f, 2026-10-24). Push (or copy the
repo to a second drive) before the defense. The Session 015 stacked branches are merged history.

NEXT TASK FOR INCOMING BUILDER
USER GOAL (Session 018): add a Relabel tab inside the native Dataset Viewer for correcting wrong YOLO classes. The feature and automated tests are complete; validate it on real local data only with explicit care.
1. **Dataset Viewer validation:** start the native dashboard service and hand-test crop review, previews, confirmed relabel, undo, card regeneration, and Gallery filtering against `primary_anchor`. Check training status first; do not make real label edits without the user's explicit approval.
2. **Optional later step:** ask before implementing ONNX-based suspected-mislabel review; it was described as a possible second release, not part of this implementation.
3. **Defense readiness:** ask how many days remain, then prioritize the existing list below to fit. WAIT FOR EXPLICIT INSTRUCTION before starting unrelated features (user rule).
4. **Today:** back up (push dev or copy the repo + datasets to another drive); rotate the Firebase key (Google Cloud console, project hulikamote-001: new JSON key over
   hulikamote_backend/firebase-service-account.json, then delete the old key); set plate_format ph_standard in the live config; always choose DeepSORT.
5. **Real numbers (the long pole):** 3 local clips (the rainy crossing 9db131ee + 2 new dry-daytime fixed-camera clips, 30-60 s, 3-8 m high), each analyzed with DeepSORT and
   "Keep the uploaded video"; in the Benchmark tab add each clip, write what really happens, protect it, run. Claim only violations with ~10+ real events; say
   "implemented, not scored" for the rest. Tune thresholds from the Caught / False alarms / Missed results.
6. **Plates:** Harvest > Plates on the local clip (draw the boxes), retrain the plate model in the Studio (Quick), report read rate by vehicle size, consider a closer camera for the demo.
7. **Decide the promised-but-missing features** (SMTP email, RA 10173 masking, demerit points): build small versions (masking = blur plates in violator-facing views; a demerit
   counter per plate; email can be a stub next to push) or reword PROJECT_CONTEXT scope with the team's approval. Do not leave it silent.
8. **Live rehearsal twice** (follow the exact-steps list given to the user), a 30+ minute stability run, phone / RTSP rehearsal, recorded fallback. Remember the live config.
9. **ReID:** file the cars (Harvest > Same car? > Rest are fine, one analysis per clip), train in the Studio (Quick), then run scripts/reid_ab.py on a NEW clip from the same camera.
   Optional idea the user liked: re-mark each car's box in a kept video (ground truth for ReID training AND real ID-switch counts) and let one entry hold 3+ cars (today all
   marked photos become ONE other car).
10. **Paper work:** paste docs/THESIS_REVISIONS.md, confirm the TO-CONFIRM legal items with the adviser, update the deck with the real numbers and limitations.
11. **Housekeeping:** refresh docs/HANDOVER.md + SESSION_LOG.md + project maps at the end; the Explain-on-hover work of the other session; tricycle / jeepney detection (deploy the
   6-class vehicle model only after testing it on the local clip); cleanup candidates listed above.

SESSION LOG HISTORY
See docs/SESSION_LOG.md
