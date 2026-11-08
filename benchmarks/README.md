# Benchmark

Scores each of the 20 violations on clips whose answers are known, and writes one report you can compare over time.

**Words:** *Caught* = a ticket matched a real event. *False alarm* = a ticket with no real event. *Missed* = a real event with no ticket.

## Easiest: the Benchmark tab in the dashboard
Run the clip in the Forensic Analyzer (turn on "Keep the uploaded video" in Settings if you can). Then **Benchmark → Add clip**: pick that
run, add what really happens (the run's flags are offered as a start), **Save**. Repeat for every clip, then **Run benchmark**. The tab
shows coverage per violation, the clips, progress and the report. It edits the same `registry.yaml` as the command line below, so you
can mix both. (The backend must be running; an older backend without the service shows a message in the tab.)

## The same from the command line (from the repo root, with the backend's python)

1. **Film or collect clips.** What to show for each violation, and the camera rules: `CLIP_CHECKLIST.md`.
2. **Run the clip once in the Forensic Analyzer** (set the zones and switch the violations on). Note the run's id.
3. **Adopt it:**
   ```
   hulikamote_backend/venv/Scripts/python.exe -m tools.benchmark adopt <task id> <clip id>
   ```
   It copies the video and the wizard's settings here and lists what the run flagged. The run's id is the newest folder name in
   `hulikamote_backend/snapshots/evidence/forensic/`. If the run did not keep its video (the wizard's "Keep the uploaded video" is
   off by default), add the original clip: `... adopt <task id> <clip id> --video "C:/path/to/clip.mp4"`.
4. **Watch the clip and write down the truth** in `registry.yaml` under `events:` (replace the `[]`; violation, start, end in seconds). Anything the run
   flagged that did not really happen is simply left out (it will show as a False alarm); anything it missed you add (it will show as Missed).
   For a clip where nothing happens, use `clean: true`.
5. **Score:**
   ```
   hulikamote_backend/venv/Scripts/python.exe -m tools.benchmark run --label baseline
   ```
   The backend must be running. Nothing is written to the Inbox. Expect it to be slow: the analysis takes about 10 times the clip's length on this PC. The report goes to `reports/` (markdown + json).
6. **Compare two runs** (for example a baseline model and a fine-tuned one on the same clips):
   `python -m tools.benchmark run --label finetuned --set primary_model=yolo11_primary.onnx`, then
   `python -m tools.benchmark compare reports/<baseline>.json reports/<finetuned>.json`.

`status` shows which violations still lack events; `validate` finds mistakes in the registry.

## What the report says
- Per violation: real events, Caught, False alarms, Missed, precision, recall, F1, false alarms per minute of footage, and a verdict
  (PASS / FAIL once there are enough events, otherwise "too few events").
- **LOAR** (the thesis' main system metric, chapter 3): of the Caught events, how many were recorded with the right violation type,
  the right vehicle and the exact plate string. It needs the true plate written on the event (`plate:`), and ideally the vehicle's
  place in the picture (`box: [x1, y1, x2, y2]` as fractions) so the right car can be checked. Events without `plate:` are Caught but
  not counted in LOAR. The report also gives plate **CER** and **WER** (the thesis' OCR metrics) on the same events.
- Violations without any real event are listed as *not benchmarked*: they have no score yet, which is different from a good score.
- mAP@50 of the detectors is separate: `training_lab/scripts/validate.py`.

Keep benchmark clips out of training (`python training_lab/harvest.py protect <task id>`). The videos in `clips/` are not committed.

## Clips other studies used (public sources)
`public_sources.yaml` lists the public clips and datasets that similar studies tested on, with licences and caveats, and
`python tools/benchmark/fetch_public_clips.py --coverage` shows which violations have any public test material (about half; for the rest see ANY FIXED CLIP and FILM OWN in that report).
`python tools/benchmark/fetch_public_clips.py --list` / `--dry-run` / run it with no options to download the lean core set, sample files only (it shows sizes and asks first).
Downloads go to `public_clips/` (git-ignored). They are evaluation material only: never train on them, and write the truth for each clip in `registry.yaml`
before scoring it, because their own labels are not our violation definitions.
