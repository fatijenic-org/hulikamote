# HANDOFF: Duplicate track IDs (same car, multiple tickets)
Written by Claude (chat session, 2026-09-30) for Claude Code. Read AFTER docs/ORCHESTRATION_START.md.
This is NOT part of the ledger. HANDOVER.md, SESSION_LOG.md and ORCHESTRATION_START.md were NOT modified.
Authorization rule still applies: the user said "proceed in order, no ambiguous tasks" only for the stitching work below. Ask before anything new (especially anything in "Open findings").

## 1. The user's problem
Same physical car gets several tracker IDs, so the Forensic Analyzer shows several tickets for one car.
User runs DeepSORT (backend/camera_config.json -> "tracker": "deepsort"; last forensic run also deepsort, model yolo11n, no SAHI).

## 2. Facts verified by reading code (all paths under hulikamote_backend/)
- yolo_inference.py:182 builds DeepSortStrategy(lost_track_buffer=60) -> DeepSORT max_age=60, n_init=3. The default 90 in engine/tracker.py is NOT used. Ledger death threshold is also 60 (engine/ledger.py), so they are aligned. (I first suspected a 60-vs-90 mismatch: that was wrong, dropped.)
- DeepSORT IDs are monotonic (sort/tracker.py `_next_id`), a raw ID can never come back after its track is deleted.
- ReID model engine/deep_sort/deep/checkpoint/ckpt.t7 is the stock deep_sort_pytorch Market-1501 (PEDESTRIAN) net, input resized to 64x128. Weak for cars.
- Detections are filtered to the ROI polygon in pipeline.py BEFORE ledger.update, so leaving the ROI counts as "missed".
- yolo_inference.py (~lines 346-369) maps tracker output boxes back to detections by IoU > 0.1, then sets det.track_id. Several tracked boxes can land on one detection (later overwrites earlier).
- Locked by user: DeepSORT hyperparameters in engine/tracker.py (do not tune).

## 3. What I implemented this session (only these files)
- NEW engine/track_stitcher.py: pure functions. Merges a newborn track into a LOST ledger if all gates pass: gap <= 3 s, same class, near the extrapolated position (gate = max(40 px, 1.2 * box size)), box area ratio 0.4-2.5, not moving backwards, HSV-histogram Bhattacharyya distance <= 0.5. Greedy one-to-one lowest cost. Tunables are constants at the top.
- EDIT engine/ledger.py: TrackLedger gets `appearance`, `update_appearance()`, `merged_ids`. ActiveLedgerManager gets `aliases` (raw id -> canonical ledger id), `track_events` deque, `_log_event()`; `update(detections, timestamp=None, frame=None)` rewritten: 3 passes (known ids, aliases, births->stitch), it REWRITES det.track_id to the canonical id so all downstream code sees one ID; death purges aliases; ticket dict now has `merged_track_ids`. Prints `[TrackEvent] birth|stitched|death|alias_dropped ...` to the backend console.
- EDIT engine/pipeline.py line ~694: `self.ledger_manager.update(detections, timestamp, frame)`.
- NEW tests/test_track_stitching.py: 13 tests, all pass. With stitching disabled 7 fail, so they are meaningful. Run: `python -m pytest tests/test_track_stitching.py --noconftest -q` (drop --noconftest if the app's test deps are installed).
- Files use CRLF. Preserve CRLF when editing (an earlier session hit CRLF patch failures).
- NOT run against real footage. Thresholds are untuned starting values.

## 4. Analysis of the latest forensic run (this is where I stopped)
Run dir: snapshots/evidence/forensic/55386dce-e9db-4ee4-92b9-89e5aee41330/ (input_video.mp4, output/report.json, output/evidence_replay.mp4; 602 frames, 30 fps, 1920x1080). Run finished ~10:55 local. ledger.py/track_stitcher.py were saved ~10:36 local. UNKNOWN whether the backend server had been restarted with the new code (no [TrackEvent] output was captured). First thing to check.
report.json has 27 tickets. Evidence file names are epoch-ms capture times (chronological). The user says #3, #7, #32 are the same car:

| ticket (report idx) | track_id | evidence first..last (epoch ms) | frames | plate | db id |
|---|---|---|---|---|---|
| 4 | 7  | ...562334 .. ...611235 | 24 | unidentified | f627c38b |
| 2 | 3  | ...583064 .. ...592563 | 6  | unidentified | d9f6c15e |
| 5 | 32 | ...596416 .. ...626798 | 15 | AP05JED | c8c77adc |
| 7 | 3 (again) | ...629978 .. ...652525 | 9 | AP05JEO | c8c77adc (same as 32) |
(all epoch values are 1790736xxxxxx)

Findings:
1. CONCURRENT duplicate tracks: #3 overlaps #7 in time, and #32 overlaps #7 in time. So two live tracks sat on one car at the same time. My stitcher only handles LOST ledgers (`missed_frames >= 1`), so it cannot merge these. This is a design gap in what I built.
2. Track ID 3 appears in TWO separate tickets (idx 2 and idx 7) with different evidence. Under normal DeepSORT behaviour that should be impossible (monotonic IDs). UNEXPLAINED. Investigate: was the new code running, how forensic.py assembles tickets (pending_tickets + still-alive ledgers, lines ~176-220), whether alias/canonical logic or the IoU back-mapping can re-emit an id. Suggest dumping `ledger_manager.track_events` into report.json to see births/deaths.
3. forensic.py "FORENSIC UI DEDUPLICATION" (lines ~226-256) runs BEFORE Pass 2 OCR, so it only sees the live-pass plate_text ("unidentified"). Plates read later in Pass 2 never trigger the merge. Proof: AP05JED (#32) and AP05JEO (#3) are Levenshtein 1 apart and store.add_violation merged them into one DB row (same db id) but the report/UI still shows two tickets. Fix idea: run the same merge after Pass 2. I have NOT read forensic.py past line ~270 (what Pass 2 and the DB write do exactly).
4. SUSPECTED ROOT-CAUSE BUG (found by reading, not yet proven by a run): engine/tracker.py DeepSortStrategy sends boxes as TOP-LEFT [x1, y1, w, h] ("tlwh"), but engine/deep_sort/deep_sort.py DeepSort.update expects CENTER [cx, cy, w, h] (original deep_sort_pytorch: `_xywh_to_tlwh` subtracts w/2,h/2; `_get_features` crops via `_xywh_to_xyxy` around the centre). Consequences: Kalman boxes AND the ReID crops are shifted up-left by half a box, so ReID features come from the wrong region; the returned box then maps back to its own detection with IoU only ~0.143 (threshold is 0.1), and a neighbouring car ahead can score much higher (~0.49 in my numeric example) -> IDs land on the wrong car or get dropped. This could explain concurrent duplicates and ID swaps far better than anything in the stitcher. Suggested fix: pass centre format (x1+w/2, y1+h/2, w, h) into DeepSort.update and keep output mapping consistent, then verify tracked-box vs detection IoU is high. This touches engine/tracker.py (bug fix, not a hyperparameter change) but that file is marked LOCKED, so ASK THE USER FIRST.

## 5. Not finished
- I staged 6 evidence frames from the device to view (first frames of the 4 tickets, last of #3-first and #7): snapshots/evidence/1790736562334.jpg, ...583064, ...596416, ...629978, ...592563, ...611235 (.jpg). NOT viewed yet, so visual confirmation that they are the same car is still pending.
- Step 4 of my plan (vehicle-trained ReID, e.g. OSNet/VeRi-776) was deliberately NOT done. Do it only if the box-format fix and stitching are not enough.

## 6. Suggested next steps (ask the user before each)
1. Confirm the backend was restarted with the new code; re-run the same video and capture `[TrackEvent]` console lines.
2. Look at the evidence frames / evidence_replay.mp4 to confirm the concurrent-duplicate picture.
3. Get permission, then fix the box-format mismatch (finding 4) and re-run.
4. If duplicates persist, extend stitching to concurrent duplicates (two live tracks with strongly overlapping boxes, same class, for N frames -> merge) and/or move the forensic dedup after Pass 2 (finding 3).
5. Investigate the twice-appearing track 3 (finding 2).

## 7. Environment notes (from my chat sandbox, Claude Code on Windows will not share these limits)
The chat sandbox reached the project only through a Linux VM mounting the folder at $HOME/mnt/huli-kamote, with python3.10, numpy, cv2, no torch/onnx. Recursive grep/find over venv/ or snapshots/evidence/ and `git status` hung there. Backups of ledger.py and pipeline.py from before my edits were saved only in that VM's /tmp (not reliable); use git.
