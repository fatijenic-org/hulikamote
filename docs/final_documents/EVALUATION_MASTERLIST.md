# EVALUATION MASTERLIST (Sunday)

Do the steps in order. Do one step at a time. Tick each box when done.
Fill in: Date/time ______  Place ______  Number of evaluators ______

Paper = `docs/final_documents/FINAL-PROPOSAL.pdf`. Printed page = PDF page - 9.
Repo = `C:\Users\nekol\Desktop\istqm_framework\k_dev\huli-kamote`.

---

## PHASE A. FRIDAY: PAPERS

- [ ] A1. Open the paper. Go to "Testing and Evaluation" (printed p. 51, PDF 60) and "Evaluation Criteria for Expert Validation" (printed pp. 52-53, PDF 61-62).
  - Write criteria A to F on one sheet. The evaluators score these six.
- [ ] A2. Open Appendix C "Evaluation Tool" (printed pp. 68-71, PDF 77-80).
  - If you see the FURPS and SUS questions: print them. Print one copy per evaluator and 2 spare.
  - If the pages are blank: tell me. I will write the forms.
- [ ] A3. Print the informed consent: Appendix I (starts printed p. 80, PDF 89, and runs to the end of the PDF). One copy per evaluator and 2 spare.
- [ ] A4. Print Table 4 (printed p. 54, PDF 63). It gives the scoring ranges for the 4-point Likert scale. Keep it for after the session.
- [ ] A5. Print `docs/final_documents/SCOPE_AND_LIMITATIONS.md`. This is the scope sheet. Keep 3 copies.
- [ ] A6. Open `docs/final_documents/REVISION_LOG.md`. Apply every entry marked "agreed" to your paper (entries 1, 2, 3, 4, 5, 8, 9, 10, 12).
  - Evaluators may read the paper. Wrong law sections must be fixed.

## PHASE B. FRIDAY: COMPUTER

- [ ] B1. Choose the demo laptop. Plug it in. Close all other programs.
- [ ] B2. Open PowerShell. Type: `cd C:\Users\nekol\Desktop\istqm_framework\k_dev\huli-kamote\hulikamote_backend`
- [ ] B3. Start the backend: `venv\Scripts\uvicorn.exe main:app --port 8000`
  - Do NOT add `--reload`. A saved file would restart the server in the middle of the demo.
  - Wait for the line "Application startup complete."
  - If the port is busy, a backend already runs. Use it.
- [ ] B4. Open http://localhost:8000/docs in a browser. The page must load.
- [ ] B5. Build a new dashboard. The old program in the Release folder is from 23 September. Do not use it.
  - Open a second PowerShell. Type: `cd C:\Users\nekol\Desktop\istqm_framework\k_dev\huli-kamote\hulikamote_dashboard`
  - Type: `flutter build windows`. Wait until the build ends (about 5 to 10 minutes).
  - If the build fails, use `flutter run -d windows` instead and tell me.
- [ ] B6. Start the dashboard: double-click `hulikamote_dashboard\build\windows\x64\runner\Release\hulikamote_dashboard.exe`
- [ ] B7. Log in. The accounts are made by `seed_users()` in `hulikamote_backend\store.py` (line 618). Read the account there. Write it on your demo sheet.
- [ ] B8. Open each menu once: Forensic Analyzer, Violations, Inbox, Benchmark, Demerit Points, Motorists, Settings, Wiki. Write down any menu that fails. Tell me.
- [ ] B9. Open Wiki > Technical Docs > Violations. The "Scope of the study" table must be at the top. Use it as the panel table.

## PHASE C. FRIDAY: CLIPS

- [ ] C1. Plug in the Seagate drive. Wait until drive `A:` appears.
  - If it does not appear, stop. Tell me. (The drive dropped three times last week.)
- [ ] C2. Open `A:\huli-kamote\evaluation-testing-videos\`. There is one folder per violation. Clip counts today:
  - Enough (10 or more): restricted_lane 46, no_helmet 41, counterflow 41, illegal_parking 33, missing_side_mirror 32, no_plate 31, illegal_turn 20, pedestrian_lane 19, overloading 14, swerving 13, illegal_u_turn 10.
  - Few: red_light 5, pickup_passengers 5, disregarding_signs 5, overtaking_on_right 3, kuliglig_with_passengers 3, crossing_solid_line 2, signal_light 1, riding_outside_vehicle 1.
  - None: no_seatbelt 0.
- [ ] C3. Make the folder `C:\HK_DEMO\` on the laptop.
- [ ] C4. For each of the 20 mandatory violations, copy 2 clips into `C:\HK_DEMO\<violation name>\`:
  - 1 clip where the violation happens.
  - 1 clean clip (no violation).
  - Each clip must be shorter than 1 minute. The analysis takes about 10 times the clip length on this PC.
  - To cut a long clip: `ffmpeg -ss 0 -t 30 -i input.mp4 -c copy output.mp4` (30 seconds from the start).
- [ ] C5. For each violation with few clips or none, choose one:
  - Film it (step C6).
  - Or write "not demonstrated" on your sheet and say it in the session.
- [ ] C6. To film: open `benchmarks\CLIP_CHECKLIST.md`. It says what each clip must show.
  - Camera: fixed, 3 to 8 m high, looking down 15 to 45 degrees.
  - Light: daylight. Quality: 720p, 15 fps or more.
  - No seatbelt: a car, seen from the front, close, through a clear windshield.
  - Do not film a person's face without permission.
- [ ] C7. Write your decision for the two violations that are not built (kuliglig passenger, overtaking on the right): "show as not built" or "ask for a build". Decision: ______
- [ ] C8. Play every clip in `C:\HK_DEMO\` once. Delete any that does not play.
- [ ] C9. Copy `C:\HK_DEMO\` to a USB stick. Never demo from drive A: alone.

## PHASE D. SATURDAY: RUN THE ANALYSES

- [ ] D1. Start the backend and the dashboard (steps B2 to B7).
- [ ] D2. For each clip, open Forensic Analyzer. Do the 5 steps: Video, Violations, Rules and zones, Settings, Run.
  - In Settings, choose tracker "DeepSORT". Turn ON "Keep the uploaded video".
  - Where it is explained step by step: Wiki > Technical Docs > Violations > "How to set up an analysis".
  - For a zone rule, draw the zone, line or arrow that the editor asks for.
- [ ] D3. Wait until a run ends before you start the next one. A run takes about 10 times the clip length.
- [ ] D4. Open the tickets of each run (menu Violations or Inbox). Look at the photos. Confirm the correct tickets. Reject the wrong ones.
- [ ] D5. Fill a results sheet: Clip | Violation | Real event? | Caught | False alarm | Missed.
- [ ] D6. Check privacy. Open one ticket's photos. You must see:
  - faces blurred,
  - other vehicles' plates blurred,
  - the violator's plate readable (this is on purpose).
  - Take a screenshot. You need it for Criterion E.

## PHASE E. SATURDAY: NUMBERS

- [ ] E1. Open the Benchmark tab. Click "Add clip". Pick the run. Write what really happens: violation, start second, end second. Add the true plate text if you know it. For a clip with no violation, mark it clean. Click Save. Repeat for every clip.
- [ ] E2. Click "Run benchmark". It is slow (about 10 times the clip length). Start it Saturday evening.
- [ ] E3. Open the report in `benchmarks\reports\` (a markdown file). Print it. It shows, for each violation: precision, recall, false alarms per minute, and a verdict. It also shows LOAR, CER and WER.
  - A violation with no real event is "not benchmarked". Do not hide this. Say it.
- [ ] E4. Get the model scores (mAP@50). Run this once for each model name:
  - `cd C:\Users\nekol\Desktop\istqm_framework\k_dev\huli-kamote`
  - `hulikamote_backend\venv\Scripts\python.exe training_lab\scripts\validate.py --model helmet_specialist`
  - Repeat with `plate_specialist`, `cabin_specialist`, `primary_anchor`.
  - Run it when no analysis is running.
  - Write on the sheet: "validation split of public data" next to each score. These are not field results.
- [ ] E5. Make a one-page numbers sheet: precision and recall per violation, LOAR, CER, WER, mAP@50. Print 3 copies.

## PHASE F. SATURDAY: DEMO PLAN AND PRACTICE

- [ ] F1. Write the demo order. One part for each criterion:
  - A (Functionality): show tickets for helmet, overloading, no plate, counterflow, parking, turn.
  - B (Reliability and performance): show a busy clip and the benchmark numbers.
  - C (Usability): open the Violations list and one ticket. Show the evidence photos and the time.
  - D (Evidence value): show a ticket with photos and the plate text.
  - E (Data privacy): show the blurred photo (step D6).
  - F (Overall): ask the evaluators to fill the form.
- [ ] F2. Give a role to each person: presenter, operator, scribe (writes the comments).
- [ ] F3. Practice the full session with a timer. The session must last 30 to 60 minutes. Practice it two times.
- [ ] F4. Learn two-sentence answers for these five questions:
  1. Why public data? "We trained the models on openly licensed public datasets. We test on our own footage and report the gap."
  2. What is "disregarding signs"? "The stop sign. The operator marks the sign on the picture. The system does not read signs."
  3. Why is the side mirror weak? "Mirrors are small and arms hide them. We judge only front and rear views."
  4. How is the stop sign different from red light? "Stop sign: crossing the line without a full stop. Red light: crossing while the light is red."
  5. Where are the real-footage scores? "Here is the benchmark report. These violations have no score yet: (read the list)."
- [ ] F5. Put in one folder: the scope sheet, the numbers sheet, the results sheet, the benchmark report.

## PHASE G. SUNDAY

- [ ] G1. Pack: laptop, charger, projector cable or adapter, mouse, power strip, USB stick with `C:\HK_DEMO\`, printed consent forms, printed evaluation forms, printed scope sheet, numbers sheet, pens.
- [ ] G2. Arrive 60 minutes early. Connect the laptop to the projector.
- [ ] G3. Start the backend and the dashboard (steps B2 to B7). Log in. Open the Wiki scope table (step B9).
- [ ] G4. Open one saved run. It must show tickets and photos.
- [ ] G5. Give each evaluator the consent form. Collect them signed before you start.
- [ ] G6. Run the demo in the order from step F1.
- [ ] G7. At the end, give each evaluator the evaluation form (FURPS and SUS). Collect it.
- [ ] G8. The scribe writes every verbal comment.
- [ ] G9. Later, compute the weighted mean for each criterion. Use Table 4 (step A4) to read the result.

---

## DO NOT

- Do not demo from drive A: alone.
- Do not start the backend with `--reload`.
- Do not change code after Saturday evening.
- Do not run a long clip live. Use the saved runs.
- Do not show an mAP score as field accuracy.
