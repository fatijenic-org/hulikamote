# DEFEND AND COUNTER DEFEND
Questions that may Arise to target the thesis and the defend and counter defend statements
for each and every decision in line with the true goal of the study
and honest limitations and scope set by the researchers along with the consultation agreements.

> Facts checked up to 2026-11-12. Anything marked **[CHECK]** was true when last seen, or is not known to the writer. Re-read the latest number or status before the defense.
> Sources: `FINAL-PROPOSAL.pdf`, `SCOPE_AND_LIMITATIONS.md`, `dumps/REVISION_LOG.md`, `dumps/TABLE3_UPDATE.md`, and the project notes of the build sessions.

## THE CORE CLAIM (say this first, every time)

- HULI-KAMOTE is a **prototype**. It watches recorded or simulated-live video, flags possible violations, reads the plate, and puts the case in front of a human for review.
- It does **not** make final enforcement decisions. Its tickets, emails, appeals and demerit points carry no legal weight (Scope and Limitations, FINAL-PROPOSAL).
- The question this study answers is the proposal's own: *"How accurately does our system log and organize the violations it detects, and where are its limits under simulation?"* Finding the limits is part of the answer, not a failure.
- Our edge is not one clever model. It is the **whole chain**: detect, track, apply the traffic rule, read the plate, keep the evidence, let a human check it, and measure honestly.

**Four rules for answering any question**
1. Say what we measured, and with what clips.
2. Say what we did **not** measure.
3. Never say a violation "works" unless the benchmark scored it on real footage.
4. When pushed on a weakness, name it first, then show the evidence and the plan. A panel trusts a team that finds its own faults.

---

## ABOUT THE DATA SOURCE

**Q: Why did you use barangay CCTV as the main source?**
- **We decided:** Barangay CCTV (Baliwasan first, then other barangays) is the first choice.
- **Defense:** It is the real thing: real Zamboanga streets, real camera heights, real traffic. It matches what the system would see if a barangay used it. The proposal said so from the start (Phase 1).
- **If they push ("did you get it?"):** Say plainly how much footage arrived and when. **[CHECK: hours received, from which barangay, date of the signed agreement.]**
- **Say honestly:** Barangay footage is often low quality and may break our camera rules (angle, 720p, 15 fps). That is why we wrote a backup plan into the scope.

**Q: Why public datasets and your own recordings as the backup?**
- **We decided:** If barangay footage is poor or outside the camera limits, we use open-licence public datasets (COCO, Kaggle, Roboflow Universe) and footage we record ourselves, for both training and evaluating the pipeline (Revision Log #3, #9).
- **Defense:** This is how nearly all detection work is done: start from public data, then adapt to the local scene. A violation such as "three riders on a motorcycle" is rare on one street, so public data gives us enough examples to teach the model what a helmet or plate looks like at all.
- **If they push ("then it will fail in Zamboanga"):** That is the exact risk, so we **tested it** instead of hiding it. We found the helmet model barely fires on rear and top-down CCTV crops (only about 8% of crops reached our 0.4 confidence line), and a vehicle model that won on its own test photos lost on our real clips. We measure on local clips, report both numbers side by side, and collect local frames to close the gap (the Harvest tool).
- **Say honestly:** Public sets are mostly foreign. Plates 0% Philippine, helmets about 7%, cabin about 19%, vehicles about 20% (dataset catalog, as of 2026-10). Results may not fully reflect Zamboanga traffic. The proposal already says this in its limitations.

**Q: Why did you drop MMDA footage, GTA V and CARLA?**
- **We decided:** Removed by team decision (Revision Log #3, #8, #9, #12).
- **Defense:**
  - MMDA footage must come through eFOI, takes long, and is Manila traffic, not Zamboanga.
  - Game and simulator footage is not real traffic. It adds a second gap (cartoon-like pictures) on top of the first one, and it does not capture Philippine roads.
  - Fewer, more honest sources are better than more sources we cannot defend.
- **If they push ("the proposal promised them"):** The revision is written down in the Revision Log. **[CHECK: adviser agreement on the revision.]** Removing a source that was too slow to obtain is a scope reduction, not a lowering of the goal.
- **Say honestly:** The first proposal listed them. We changed it on purpose and recorded the change.

**Q: Why not test on a live road?**
- **We decided:** All testing is on recorded footage, controlled video and simulated live input (Scope and Limitations).
- **Defense:**
  - Live public surveillance raises privacy and legal issues (Data Privacy Act, RA 10173) that a student prototype should not take on.
  - The system reads its camera as an **address** (RTSP). A phone, a laptop playing a clip, and a real DVR look the same to it. So the live path is exercised without a public road.
- **If they push ("so live was never tested"):** True for a real CCTV. We say it. What we show is the same input path, with newest-frame-only reading, live lag display and automatic reconnect.
- **Say honestly:** Real CCTV was not available. Live use on a real road is future work.

---

## ABOUT THE DETECTION PIPELINE

**Q: Why not one trained model per violation? Isn't your "heuristic" just if-else?** *(Panel remark; the panel said the system would be "heuristic programming".)*
- **We decided:** A **hybrid**. Models do the *seeing* (vehicles, riders, helmets, plates, cabin). Explicit rules do the *deciding* (zone, direction, time, count).
- **Defense:**
  - Traffic law is a rule, not a pattern. "Stopped longer than 3 minutes in a no-parking zone" is a measurement, not something to guess.
  - A ticket must be **explainable**: we can show *why* it was flagged (path, time, count, picture). A single black-box model cannot.
  - A model per violation would need thousands of labelled violation clips for each of 20+ types. Nobody has that, least of all for Zamboanga.
  - Each violation is still its **own module** (own file, own settings, own tests). It is not one long if-else.
- **If they push ("then the AI is only detecting cars"):** Detecting and tracking correctly is the hard part. The rules sit on top of it and are fed by it. Mistakes in the rules are easy to see and fix; mistakes inside a black box are not.
- **Say honestly:** Rules need the right camera view. That is why the scope sets camera limits.

**Q: Why YOLO?**
- **We decided:** A YOLO detector, run through ONNX.
- **Defense:** One pass per frame, fast on modest hardware, no special GPU needed, widely tested. Our goal is a **light** system that a barangay could run on an ordinary laptop (consultation goal).
- **If they push ("newer or bigger models are more accurate"):** Yes, and they are slower and heavier. We chose the speed and size our goal needs, and the pipeline is modular so the detector can be swapped (Phase 2 of the proposal).
- **Say honestly:** The stock COCO model has **no tricycle or jeepney class**, and it scores motorcycles low from a CCTV angle. We had to adjust (below).

**Q: You trained your own vehicle model. Is it better than the stock one?**
- **We decided:** Train a vehicle model with Zamboanga classes (motorcycle, car, bus, truck, person, tricycle, then jeepney), but activate it **only if it wins on real clips**.
- **Defense:** An earlier version (train-3) beat stock on its own test photos (for example truck .71 vs .23, tricycle .92 vs none) but **lost on our real clips**: fewer people and riders found, a taxi called a truck. So we did **not** activate it. We judge on real footage, not on the easy score.
- **If they push ("so which model do you run?"):** A newer version that also knows jeepney (train-4) is now the active one. **[CHECK: its comparison on a held-out real clip.]**
- **Say honestly:** Dataset test scores flatter the model. Real-clip scores are the ones that count. Every dataset score we quote is a validation-split score unless we say otherwise.

**Q: Why DeepSORT as the tracker?**
- **We decided:** DeepSORT (the proposal's choice), with a car-matching network (ReID).
- **Defense:** It remembers *how a car looks*, not only where it was. That helps when cars overlap or hide behind a jeepney, which is common in Zamboanga's dense traffic (Phase 2 of the proposal). Every rule that needs a car's *path* (counterflow, turns, parking time) depends on stable IDs.
- **If they push ("ByteTrack is popular"):** We compared. In our wizard setting ByteTrack left about 58% of detections untracked, DeepSORT about 2%. **[CHECK: the wizard default is now DeepSORT.]** A tuned ByteTrack may do better; our test was not exhaustive.
- **ReID facts:** Making the matcher look at 96x192 pictures instead of 64x128 raised the "right car on top" score from 70.6 to 74.6 with no retraining. Fine-tuning it on our data did **not** beat the stock weights on a road it had not seen. So we kept stock weights. We only had 5 roads, so we do not claim it generalizes.
- **Say honestly:** Identity switches still happen in heavy occlusion. The review tools (merge, split and move frames between tickets) exist because of that.

**Q: Why do the helmet, plate and cabin models run only every 5th frame, at a small size?**
- **We decided:** Specialist models run on every 5th frame, on a small picture of each vehicle (320 px), and the result is **voted** across several looks.
- **Defense:** It keeps the system light enough for a laptop. One frame is never trusted alone: a violation needs several looks (for example 60% of the last 10, at least 5 looks).
- **If they push ("small pictures hurt accuracy"):** Yes, especially for small plates. The vehicle must be at least 120 px wide for plate, helmet and seatbelt checks (plate check: 60 px). Smaller is "not judged", not guessed.
- **Honest fix we found and made:** The app was feeding the models the wrong way (colour order, stretched, wrong part of the picture). Plate finding was only **7%**. After the fix on 2026-10-24 it was **83%** on our check pictures. We found this by measuring, which is the point of measuring.

**Q: Why EasyOCR for plates, and how good is it?**
- **We decided:** EasyOCR with plate-format rules and voting over several crops. Plate text is never guessed: unclear means "unidentified".
- **Defense:** It runs offline, needs no training, and the format rules plus voting remove many wrong reads. LOAR and WER are strict **on purpose**: the proposal says a wrong plate is worse than none, because it tickets an innocent driver.
- **If they push ("your plate reading is weak"):** Correct, it is our weakest part. On a Zamboanga 4K rainy clip only 4 of 61 tickets had a plate read (2026-10-27). The plate model was trained on Vietnamese grayscale plates. The review screen lets a human **fix or redraw the plate** before confirming. **[CHECK: latest plate results and whether a Philippine plate format is set.]**
- **Say honestly:** Plate quality is the main limit on LOAR. Retraining on local plates is the next step.

**Q: Why does the system work without drawing zones (no ROI)?**
- **We decided:** Panel request: flow detection works **automatically**, and drawing zones stays as an option (flow mode "auto").
- **Defense:** The system learns the road's normal direction from traffic and runs 10 rules with no drawing (counterflow, swerving, U-turn, illegal turn, parking, loading, double parking, truck ban, tricycle ban, signal light). It also learns crosswalks and road lines from the live camera.
- **If they push ("so no drawing at all?"):** Seven rules still need a drawing: pedestrian lane, blocking intersection, restricted lane, red light, sidewalk driving, disregarding signs, crossing solid line (some now have overlay tools).
- **Say honestly:** Auto mode needs about 60 s of normal traffic first, and two-way roads are not judged in auto mode.

**Q: Why a human review step? Why not automatic tickets?**
- **We decided:** The system flags, the human confirms, rejects or edits.
- **Defense:** The proposal says the system makes no final decisions. Precision matters more than speed here: a false flag costs an enforcer's time, a false ticket costs an innocent driver. Every ticket carries evidence photos, close-ups of what the helmet and cabin checks looked at, and "why" marks.
- **If they push ("then it is not automatic"):** It automates the watching, which is the part enforcers cannot do all day. The decision stays human, by design.

**Q: Is the system light? How fast is it?**
- **We decided:** Light, offline, local computing, as the proposal says.
- **Defense:** It runs on a laptop with no internet. Live reading keeps only the newest frame, so lag cannot build up.
- **Say honestly:** On our development PC, analysing a recorded clip takes about 10 times the clip's length. **[CHECK: timing on the demo laptop.]** The system also needs a decent CPU or GPU; we did not test a barangay computer.

---

## ABOUT THE DATASET

**Q: Your datasets are public and mostly foreign. How can the models be valid for Zamboanga?**
- **We decided:** Treat public data as the **starting point**, then test and improve on local footage.
- **Defense:** Public data teaches *what a helmet, plate or truck looks like*. Local footage tells us *how well it holds up here*. We keep those two apart and report both.
- **If they push:** We have the evidence that the gap is real (helmet and vehicle findings above). Reporting it is more honest than a high score on photos that do not match the camera.
- **Say honestly:** No plate set is known to be Zamboanga. A Philippine-format check and local harvesting are the planned fix.

**Q: The proposal said 3,000 images with an 80/10/10 split. Did you reach it?**
- **We decided:** Keep the target as a plan, and report the **real counts** by dataset.
- **Defense:** The 3,000 is a minimum target for annotated images (Revision Log #3 note). We trained several small specialist models from many public sets, so the real totals are much larger than 3,000 for most of them. 80/10/10 is the standard train/validation/test split, and our benchmark clips are held out completely.
- **Say honestly:** The split and counts are per dataset, not one single 3,000-image set. **[CHECK: real counts in the dataset catalog.]**

**Q: Did your scores contain leakage?**
- **We decided:** Clean the datasets and say so.
- **Defense:** On 2026-10-25 our cleaning tool found train/validation overlap in some sets. The models were trained **before** that cleaning, so their old scores (helmet about .98, plate about .77, cabin about .79 mAP50, all on each dataset's own validation split) are probably optimistic. We found this ourselves.
- **If they push ("so your numbers are wrong"):** They are validation-split numbers and we label them so. The numbers we lean on are the real-clip benchmark numbers, not these. **[CHECK: retrained scores after cleaning.]**

**Q: How do you keep test clips out of training?**
- **We decided:** Benchmark clips are **evaluation only**. A "protect" command marks clips that came from an analysis so the Harvest tool never uses them for training.
- **Defense:** This is the basic rule of honest testing: never grade on what the model studied.
- **Say honestly:** Public evaluation clips (HELMET Myanmar and others) have their own labels, which are not our violation definitions. We re-label events ourselves before scoring.

**Q: The proposal promised Grounding DINO for auto-annotation. Where is it?**
- **We decided:** Replace it with the **Harvest tool**: our own detector proposes boxes on local clips and **a human checks every picture**.
- **Defense:** Same goal (cut the hundreds of hours of manual boxing, with a human review as the proposal says). It uses a model we already run, which keeps the system light, and each label is verified by a person.
- **Say honestly:** Grounding DINO was not built. **[CHECK: the proposal text still says it; add it to the Revision Log.]**

**Q: How do you handle the helmet and rider-count weakness?**
- **We decided:** Fix with data, not by lowering thresholds.
- **Defense:** The cause is the domain gap, not the code. Lowering the confidence line does not help (it moved 8% to 10%). The fix is more local rider pictures, labelled by people, then a retrain, judged on a held-out part of the clip.
- **Say honestly:** On 150 HELMET Myanmar clips our overloading rule caught only about 2% of bikes with 3 or more riders (14% with a lower person cutoff; precision about 40%). The cause is detection: overlapping riders merge into one box. We report this number, we do not hide it.

---

## ABOUT VIOLATIONS

### General (all violations)

**Q: Why these violations, and why did the vehicle scope change from motorcycles and cars?**
- **We decided:** 20 **mandatory** violations for the vehicles common in Zamboanga: motorcycles, cars, tricycles, jeepneys, buses, trucks, pickups and kuliglig (Revision Log #1, #2).
  - 13 apply to all vehicles: counterflow, illegal parking, illegal turn, disregarding signs (stop sign), no plate, illegal U-turn, crossing solid line, restricted lane, overtaking on the right, signal light, red light, swerving, pedestrian lane.
  - Motorcycle only: no helmet, missing side mirror, overloading. Car only: no seatbelt. Kuliglig: passengers. Pickup and other vehicles (not motorcycles): passengers on the pickup bed, riding outside.
  - Extras that are built: blocking intersection, sidewalk driving, illegal loading, truck ban, tricycle on a national highway, double parking, distracted driving.
- **Defense:** The panel asked for at least 20 and for the pickup-bed passenger case in particular. Zamboanga roads are full of tricycles, jeepneys and pickups. Some violations (loading, tricycle ban, truck ban) cannot even be defined without those vehicles. We chose violations by whether they are visible in one frame or inferred from a short path over frames (proposal), and added easier ones to reach 20.
- **Say honestly:** Two mandatory items are **not built**: kuliglig passengers (needs a kuliglig class in the detector) and overtaking on the right. That makes 18 of the 20 built, plus 7 extras (25 rules in total).

**Q: Which of your violations really work?**
- **We decided:** Claim only what the benchmark scored.
- **Defense:** The benchmark gives, per violation, real events, Caught, False alarm and Missed, with precision, recall and false alarms per minute. It gives a verdict only with at least 10 real events; below that it says "too few events", and it lists unscored violations as "not benchmarked", which is different from a good score.
- **Our answer script:** "Here are the ones scored, with counts. Here are the ones built but not yet scored. Here are the experimental ones. Here are the ones that cannot work yet." Never skip a group.
- **Say honestly:** Most violations were not scored on real footage when last checked; the first real number was overloading (weak, see above). **[CHECK: the latest benchmark report before the defense.]**

**Q: Are your rules just guesses about the law?**
- **We decided:** Every violation gets a legal source, and unconfirmed ones are marked.
- **Defense:** We corrected our own Table 3 (Revision Log #10): for example RA 8750 (Seat Belts Act) was cited for plates, and RA 4136 has no stop-sign rule, so disregarding signs now points to JAO 2014-01. Section numbers were read on lawphil.net. **Fine amounts are left out** because none was confirmed from a primary source.
- **If they push:** Several items are still marked "to confirm" (JAO 2014-01 not opened, local ordinances such as Zamboanga's loading and restricted-lane rules, the Zamboanga tricycle route plan).
- **Say honestly:** The system detects behaviours that *resemble* these violations. The human and the law decide whether it is one.

**Q: How do you avoid flagging innocent drivers?**
- **We decided:** Add "not judged" gates rather than guess.
- **Defense:** Unknown light: no ticket. Tinted windshield: seatbelt skipped on purpose. Vehicle too small: plate, helmet and seatbelt not judged. A plate found at any fair look cancels the "no plate" suspicion. The truck-ban rule records the *time source* on the ticket ("time not confirmed" if unknown).
- **Say honestly:** The cost is recall: some real violations will be skipped when the picture is poor. For an assistant that feeds a human, skipping is safer than a false ticket.

**Q: Your system relies on a human to decide. Is that not an escape?**
- **We decided:** The study states it plainly. The system does not make final enforcement decisions. Nothing it logs is used in official enforcement. The dashboard is for LTO staff and enforcers to review flagged violations. Operators view the evidence frame and verify the record before a notice is issued. The paper also says false alarms create more manual review work for enforcers. LTO officers are the evaluators.
- **Defense:** Human review is a design choice of the proposal. It is the right answer to approximate distances, borderline cases and rule ambiguity.
- **Say honestly (three limits):**
  1. It does **not** excuse errors. The paper commits to Precision and Recall. The panel can still ask for the numbers. Review is the safety net, not an excuse.
  2. The paper says flags are "reliable and legally credible" and also "no legal weight". Pick one. Say "decision support".
  3. Show the human step in the demo: someone presses Confirm or Dismiss before any notice goes out.

### Illegal parking

**Q: What exactly counts as illegal parking? Is it one rule or many?**
- **We decided:** Follow RA 4136 Section 46, items (a) to (h). Section 46 says no driver shall park a vehicle, or permit it to stand, upon a highway in these places: (a) within an intersection, (b) on a crosswalk, (c) within 6 m of the corner (intersection of curb lines), (d) within 4 m of a fire station driveway, (e) within 4 m of a fire hydrant, (f) in front of a private driveway, (g) on the roadway side of a vehicle parked at the curb (double parking), (h) where official signs ban parking (read on lawphil.net, 2026-11-11).
- **Defense:** Section 46 is a **list**, so we split it by how each item is detected. (c), (d), (e), (f) and (h) are boxes the operator places on the picture, and each box says why parking is banned there (the reason is printed on the evidence photo). (a), (b) and (g) keep their own rules: Blocking the intersection, Pedestrian lane blocked and Double parking. They have different time limits (junction 5 s, crosswalk 3 s, double parking 8 s, parking 180 s by default) and different zones, so one merged rule would force one limit on all of them. Each rule maps to one Section 46 letter.
- **If they push ("the 5 m or 6 m in some sources"):** The text of Section 46(c) says **6 meters**. The 4 m for a hydrant is in RA 4136 Section 46(e) only. The Fire Code (RA 9514) Section 8(d) bans obstructing fire lanes and hydrant access, but gives no distance and does not mention parking.
- **If they push ("two tickets for one stop?"):** Both tickets land in the review queue, each with its own reason on the evidence photo, and the reviewer sees they are the same car and the same moment. The operator can join them with the "Same car" merge, and an officer confirms or dismisses each one. Nothing is sent to the driver without that step. The planned rule makes it one ticket: the specific rule (crosswalk, junction, double parking) wins over plain parking.
- **Say honestly:** One stop can trigger two rules (for example parking and crosswalk) and give two tickets. **Not handled yet.** The plan: one stop gives one ticket, and the specific rule wins over plain illegal parking. These boxes and reasons were built and merged but **not scored on real footage**.

**Q: How do you measure "4 meters from a hydrant"?**
- **We decided:** The system does **not** measure meters. The operator draws the no-parking area on the picture (an annotated ROI, which is how the proposal defines illegal parking: "stationary persistence within annotated no-parking ROI"). The distances in the law are guidance for drawing the box. A car is about 4.5 m long, so 4 m is about one car length.
- **Defense:** The study checks whether a stopped vehicle is **inside the area the operator marked**. It makes no claim of metric accuracy. The ticket goes to an officer for review, and the evidence photo shows the box and the reason. The law text we read gives the distances but no measuring method.
- **If they push ("then it is not accurate"):** Correct, and we say so. Perspective makes the same pixels mean different meters near and far. The most accurate method is to calibrate the road plane once per camera (the operator clicks 4 corners of something with known size, then 4 m becomes a true 4 m circle). We name it as future work, together with an uncertain band: a car clearly inside is flagged, a car near the edge goes to review and gets no automatic ticket. Then we would tape-measure a few spots on a test clip and report the measured error.
- **Say honestly:** **Not built:** the calibration, the uncertain band and the error test. Today the distance is as good as the box the operator draws. Stating "the system measures 4 m" would be wrong.

**Q: Are the violations detected automatically? Do you need to draw anything?**
- **We decided:** Vehicles are always detected and tracked automatically. Illegal parking has an **automatic mode**: with nothing drawn, the whole picture is the zone, and a vehicle that stays stopped while other traffic keeps driving past is flagged (a red-light queue is not parking). The special places (hydrant, corner, driveway, fire station, no-parking sign) are marked once per camera.
- **Defense:** A fixed CCTV camera needs the marking only once. The crosswalk can be found by the road finder in the Live Monitor. A hydrant could be found automatically, because the standard COCO detector has a fire hydrant class.
- **Say honestly:** **Not built:** automatic hydrant detection (untested on Zamboanga footage). Corners, driveways, fire stations and no-parking signs have no model and no training data. The automatic crosswalk finder was tested on few clips, and it refuses a crosswalk cut by the picture edge.

**Q: A car waiting at a red light inside the no-parking area: is it flagged?**
- **We decided:** Illegal parking needs the vehicle to stay stopped longer than a time limit (180 s by default, set per rule). In automatic mode it must also be stopped **while other traffic keeps driving past it**, so a queue where everything is stopped is not parking.
- **Defense:** A red light is usually shorter than the limit, and in automatic mode a stopped queue has no traffic flowing past it. For a drawn area or a placed box, the operator puts it where no queue forms. This is the same guard the study uses for stops in a zone.
- **If they push ("and if the road direction is not learned yet?"):** Automatic mode then flags nothing. We prefer a missed case to a wrong ticket. A drawn box or sign works without learning the road.
- **Say honestly:** A very long red light or a jam in a drawn area can still look like parking. A drawn zone has no flow check. The reviewer is the last guard, and none of this is scored on real footage.

**Q: Why is a vehicle with its hazard lights on not flagged?**
- **We decided:** If an indicator or hazard light blinks on a stopped vehicle, the parking stopwatch is held and starts again when the lights stop.
- **Defense:** A vehicle that signals is pulling in or out, or waiting for a gap. It has not parked yet. We use the same blink test as the Signal Light rule (a steady on and off rhythm of 0.5 to 3 times a second), so a constant amber light does not count.
- **Say honestly:** A driver who leaves hazards on is never flagged while they blink, so this can be abused. A lamp that is far, tinted or hidden is not seen. **Not scored on real footage.**

### Red light and disregarding signs

**Q: Why are the traffic light and the signs simulated?**
- **We decided:** Light and signs are **overlays** the admin places on the picture. The system does not recognise signs or light colours from the image.
- **Defense:** We had no sign or light detector or data. So we test the *rule* (does the system judge correctly given the light state?), which is what the proposal's Boolean logic is about.
- **If they push ("then it is not real"):** The rule and the vehicle tracking are real. Recognising the light is a separate, solved computer vision task we scoped out. An unknown light never gives a ticket.
- **Say honestly:** Disregarding signs covers the **stop sign** only (stop line crossed without a full stop). Other signs are covered by their own violations (no entry = counterflow, no turn = illegal turn, no stopping = illegal parking, vehicle ban = truck ban).

**Q: Aren't "stop sign" and "red light" the same thing?**
- **We decided:** They are kept apart in the text (Revision Log #11).
- **Defense:** A stop-sign violation is crossing the stop line **without a full stop**. A red-light violation is crossing **while the light is red**. Different trigger, same stop-line geometry.

### Signal light (and double parking)

**Q: Why is Signal Light "experimental"?**
- **Defense:** Hand signals are lawful and motorcycles are exempt, so the rule can over-flag. We scored it as experimental on purpose and it is **not** a headline result. Same for Double Parking (needs moving traffic in the zone, not tested on real footage).

### Truck ban

**Q: Truck ban and time?**
- **We decided:** The ban only holds inside the hours the admin sets. Each frame is judged by the time of the *video*, found in this order: typed by the admin, then the clock printed in the picture, then the file tag, then the file name. The ticket shows the time and where it came from.
- **Defense:** Time is an input, not something the AI invents. Real enforcement systems stamp time at recording from a synced clock (NTP or GPS), keep the source of the time, and give no automatic ticket when the time is unknown. We follow the same rules: every source is named on the ticket, and the printed clock is believed only when two readings agree with the time that really passed (a misread digit cannot agree twice).
- **If they push ("what if there is no time in the video?"):** The truck is still flagged, but the ticket says **"Time not confirmed"** and carries a review flag, so an officer checks the time before confirming. Nothing is ticketed silently on a guess. This fits the study's rule that a person confirms every ticket.
- **If they push ("why not estimate the hour from shadows or brightness?"):** Shadows give about plus or minus 30 minutes on a clear day and fail under cloud; brightness cannot tell 8 AM from 10 AM. A wrong ticket is worse than a ticket marked for review, so brightness is only used to say day, dusk or night, never as a time.
- **If they push ("what if the camera clock is wrong?"):** The reviewer sees the time source on the ticket. A camera that drifts is fixed by its owner syncing it, as real systems require. When the printed clock and the file tag disagree by more than 5 minutes, the printed clock is used and the note says so.
- **Say honestly:** The real Zamboanga ban hours are **not known**; no national legal source was found, so the hours are a setting, not hard-coded (the "example hours" button is only an example). The clock reading was tested on real clips with a painted clock, **not** on a real Zamboanga camera. The live monitor uses this computer's clock; reading the camera stream's own time is future work. **[CHECK: get the ordinance hours from the City Traffic or City Legal office, and test one real Zamboanga clip with a clock, before the defense.]**

### Tricycle on a national highway

**Q: Why Tricycle on a National Highway, if you cannot tell a national highway?**
- **We decided:** The admin states it per camera. No zone drawn = the whole view counts as a banned road. A drawn zone limits the ban to part of the view.
- **Defense:** The system cannot know a road's legal class, so we do not pretend. The ban comes from DILG MC 2020-036 and 2023-195, and each city's Tricycle Route Plan sets the allowed parts.
- **Say honestly:** The Zamboanga plan is **not confirmed**. A wrong choice flags tricycles on a road where they are allowed. A "tricycle" class is needed in the detector.

### Pickup passengers and overloading

**Q: Pickup passengers and overloading?**
- **Defense:** Pickup passengers (RA 4136 Sec 32(b) and Sec 51) was asked for by the panel. Overloading counts riders from the person boxes (default max 2).
- **Say honestly:** A straight top-down view cannot tell the pickup bed from the cab. Pickups are detected as "truck". For overloading, hidden or overlapping riders reduce the count (recall about 2% to 14% in our test).

### Missing side mirror

**Q: Why keep Missing Side Mirror if it cannot work?**
- **We decided:** Keep it, marked as limited.
- **Defense:** It is in the proposal and the panel expects it. The proposal already says mirrors are small and the rider's arms hide them.
- **Say honestly:** **It cannot work yet.** The cabin model has no mirror training data. It is judged from the front or rear only (from the side one mirror is always hidden). We do not claim a result for it.

---

## ABOUT CAMERA RULES AND SCOPE LIMITS

**Q: Your camera rules are strict. Isn't real CCTV messy?**
- **We decided:** The system is evaluated on a fixed camera 3 to 8 m up, looking down 15 to 45 degrees, in daylight, 720p or better, at least 15 fps, vehicles at least 120 px wide, each visible at least 3 s (swerving 6 s) (Revision Log #5).
- **Defense:** Rules depend on a **stable picture** (zones, learned flow, paths). A moving camera or straight top-down view breaks that. Stating the working conditions is normal engineering: we say where it works, we do not claim it works everywhere.
- **If they push ("then barangay cameras may not qualify"):** Correct. That is why the study says so, and why it relies on public data and our own recordings if barangay footage does not meet the limits.
- **Say honestly:** Night, heavy rain, strong backlight, moving cameras and top-down views are **out of scope**.

---

## ABOUT THE LIVE DEMO AND CLOUD GPU

**Q: The scope says you do not test live. Why do you demo "live"?**
- **We decided:** Show a live demonstration with **simulated** camera input: a phone, or a second laptop that plays a clip as an RTSP camera. The teachers asked for it.
- **Defense:** The general objective is a prototype "designed with an architecture to support live camera implementation" (FINAL-PROPOSAL). A live demo proves that architecture works. The scope only says we do not test a camera **on a real road**. It does not forbid a live-style demo from simulated input. The system reads a camera as an **address**, so a real CCTV, a phone and a laptop look the same to it. Only the address changes.
- **If they push ("so it is not a real live test"):** Correct. We call it **simulated live**. Real CCTV is future work.
- **Say honestly:** The live screen shows the lag and the frames per second. **[CHECK: measured live fps on the demo laptop.]**

**Q: Is "live" a different system from your forensic analysis?**
- **We decided:** No. The final output is the **forensic pipeline running on a live feed**: the same detector, tracker, rules, plate reading, evidence and human review.
- **Defense:** One pipeline with two inputs (a file, a camera). We defend one system, not two. What we score offline on clips is the same code the live demo runs. **[CHECK: tickets appear while the feed runs.]**
- **Say honestly:** Live reading keeps only the newest frame, so it may see fewer frames than an offline run. Offline scores are therefore the better case for live accuracy.

**Q: If the live demo is too slow, can you rent a cloud GPU? Isn't that a privacy risk?**
- **We decided:** Local first. A cloud GPU is **plan B**, for the demo only, with demo data only.
- **Defense:**
  - Order of steps: (1) measure fps on the demo laptop. (2) Try cheap fixes: a smaller picture, skip more frames, use a GPU run option, borrow a laptop with a GPU. (3) Use a cloud GPU only if it is still too slow.
  - If we use the cloud: only demo footage goes up (public clips and our own staged clips, **never barangay footage**), and only the demo database with made-up plates (`demo.db`). No real motorist, plate-owner or email data goes up.
  - The machine is created for the session and deleted after. The link is an encrypted tunnel, with no open ports and an encrypted disk. No footage is kept.
  - So the risk is limited by **what we send**, not by trusting the provider.
- **If they push ("encrypted data is still read in plain by the GPU"):** Correct. A GPU must see frames in plain form. Encryption protects the link and the stored files. It does not protect data while it is being processed. That is why nothing sensitive goes up. (Special "confidential" cloud machines exist. They cost too much for this study and we do not use them.)
- **Say honestly:** The blur cannot run before the upload, because the blur needs the detections made on the GPU. So the cloud sees **unblurred** frames. Real barangay footage and real people never go to the cloud.

**Q: Doesn't the cloud break "tested offline using local computing resources"?**
- **We decided:** Yes, it does if you read the sentence literally. We change the text. We do not hide it.
- **Proposed wording for the scope:** "The system runs offline on local computing resources. For the live demonstration only, the researchers may use a temporary cloud GPU that processes demonstration footage only (no barangay footage and no real motorist data). The cloud machine is deleted after the session."
- **Also change:** The consent form says the demonstration is "strictly within a controlled, offline simulation setting". If the demo uses the cloud, edit that sentence and tell the evaluator. Ask the Research Ethics Office first.
- **Defense:** The offline promise exists to protect real people and to keep the system away from government databases. Both stay true: the cloud holds only demo data, and there is no link to any government system.
- **Say honestly:** If we cannot get the approval in time, we run local at lower fps and say so. A slower honest demo is better than an unapproved cloud demo.

**Q: Your goal is a light system a barangay can run. Why show a cloud GPU?**
- **We decided:** Report the speed for **local and cloud separately**, each labelled.
- **Defense:** A barangay will not have a cloud GPU. The cloud run only shows what extra hardware would give. The claim about the barangay stays tied to the local laptop number.
- **Say honestly:** Never present the cloud fps as the barangay laptop's fps. **[CHECK: fps on the demo laptop, and on the rented GPU if used.]**

---

## ABOUT EVALUATION

**Q: Why LOAR and not only mAP?**
- **Defense:** mAP tells us if boxes are right. LOAR asks the question that matters to enforcement: did the **record** come out right, meaning the right violation type, the right vehicle track and the exact plate string together? A system with perfect boxes and a wrong plate is worse than useless (proposal).
- **If they push ("your plate is weak, so LOAR will be low"):** Likely, and that is the honest finding. LOAR exposes integration failures that single-part scores hide.
- **Say honestly:** LOAR is only as reliable as our own labelled clips. **[CHECK: LOAR, CER and WER once the benchmark has run.]**

**Q: You tested only on simulation and recorded video. Is that enough?**
- **Defense:** The proposal frames the study as applied, simulation-based research. It avoids exposing real people to live surveillance. The second layer is a live demo judged by LTO personnel.
- **Say honestly:** Results show what happens under controlled footage, not on the road.

**Q: How many LTO evaluators, and what do the scores mean?**
- **Defense:** Evaluators fill the FURPS and SUS form after a live demo. Scores are averaged with a weighted mean and read against the Table 4 bands (3.50 to 4.00 Highly Acceptable, down to Not Acceptable).
- **Say honestly:** **[CHECK: number of evaluators.]** With only **one** evaluator, the result is expert feedback, **not** a statistic and not something we can generalise. Say that before the panel does. The form's rating words ("Acceptable", "Needs Revision") also differ slightly from Table 4's bands.

**Q: What if your accuracy results are low?**
- **Defense:** Research question 4 asks for the **limits** of performance under simulation. A clear, measured limit with a plan to fix it is a valid result. We already show how: the helmet and vehicle findings led to harvesting local data.

---

## ABOUT THE DASHBOARD, NOTICES AND PRIVACY

**Q: How do demerit points work? What are the values?**
- **We decided:** One confirmed (approved) ticket = one point per plate, counted when read. No weights or thresholds.
- **Defense:** The proposal defines the counter only as "accumulated violations per plate number". We did not invent legal point values. Rejecting a ticket undoes the point.
- **Say honestly:** The points carry no legal weight. Real LTO demerit rules were not applied.

**Q: How do email and notices work?**
- **We decided:** Confirming a ticket sends a notice with the evidence photos. Two routes: **online** (Gmail, plus an optional Supabase cloud for the phone app with push) or **offline** (a mailbox page on the laptop's local network).
- **Defense:** The offline route keeps the demo working with no internet and matches the "offline, local computing" scope. A demo plate registry links plates to made-up owners.
- **Say honestly:** The online Supabase route was tested only against faked responses, **not** a real project. **[CHECK: real Supabase test, push to a closed app, phone APK build.]** Motorist accounts use the plate as the login in the prototype.

**Q: Appeals?**
- **Defense:** The Violator Portal (phone app) lets a registered motorist see approved tickets and file an appeal.
- **Say honestly:** **[CHECK: officer-side appeal review screen. It did not exist when last seen.]**

**Q: How do you protect privacy (RA 10173)?**
- **We decided:** A **mandatory blur** step. Saved evidence blurs people's heads and other vehicles' plates and keeps only the violator's plate. If blur fails, nothing is saved ("fail closed"). It costs about 69 ms per 1080p frame.
- **Defense:** Only what is needed to log the violation is stored (proposal). Footage is evaluated offline, with no access to government databases.
- **If they push ("why not face detection?"):** We tested the classic OpenCV face detector on real evidence photos: 9 hits, **all false** (cars, grass, road), 1.2 s per photo. So we blur heads found from the person boxes instead.
- **Say honestly:** Not covered: photos saved before the blur existed, the forensic replay video, uploaded source videos, the mock-mode live snapshot, and people the detector misses. Blurred heads also weaken helmet evidence. The proposal also promises that footage is discarded within 30 days of the final evaluation (barangay data-sharing terms). **[CHECK: signed agreement.]**

---

## BIG PICTURE

**Q: Why is this study worth doing? Public models already exist.**
- **Defense:** The models are not the contribution. The contribution is the **end-to-end, locally tested, explainable workflow** for Zamboanga: from camera input to a reviewed, documented case with evidence, notice, appeal and an honest measure. Plus the tools that make it repeatable (Harvest tool, Benchmark, documentation site).

**Q: Does this replace traffic enforcers?**
- **Defense:** No. It covers the gaps they physically cannot: weather, manpower and roads they cannot watch all at once. People still decide.

**Q: What would you do next with more time?**
- Collect and label more local footage (helmets, plates, riders), retrain, then rescore on a held-out local clip.
- Score every violation with at least 10 real events.
- Confirm the legal items and local ordinances.
- Test on a real CCTV and a barangay computer.

---

## OPEN POINTS FOR THE TEAM (not for the panel)

1. **Two lists of the "official 20" disagree.** The Revision Log (#2) counts pickup passengers and riding outside as mandatory and blocking intersection and illegal loading as extras. `SCOPE_AND_LIMITATIONS.md` ranks blocking intersection and illegal loading in the top 20 and puts pickup passengers and riding outside under "other". Pick one and make both files match.
2. **Grounding DINO** is still in the proposal text. It is not in the Revision Log.
3. **Form vs Chapter 3.** The evaluation form (Appendix C) groups items by FURPS with the words Acceptable and Needs Revision. Chapter 3 uses criteria A to F and Table 4 words. Decide whether to align them or explain the mapping.
4. **Evaluator count.** One evaluator cannot support a statistical claim.
5. **Two mandatory violations are not built:** kuliglig passengers and overtaking on the right.
6. **Barangay footage status and the signed agreement** must be stated plainly.
7. **Benchmark results.** The defense depends on the latest benchmark report. Rerun and replace every number marked [CHECK].
8. **Plate quality** (the biggest factor in LOAR) needs local training data.
9. **Cloud GPU decision.** Measure fps on the demo laptop first. Use the cloud only if it is still too slow.
10. **If the cloud is used,** change two texts: the scope sentence "tested offline using local computing resources" and the consent sentence "strictly within a controlled, offline simulation setting". Add the change to the Revision Log, and ask the adviser and the Research Ethics Office.
9. **Fix the paper's illegal parking citation.** The proposal cites RA 4136 **Sec. 51** (hitching to a vehicle) and "Local Ordinance SP-1160" (not verified) for illegal parking. The correct source is **Sec. 46, items (a) to (h)**. The same Chapter 3 passage calls flags "reliable and legally credible"; change it to "decision support".
10. **One stop, two tickets.** Illegal parking (automatic mode) and Pedestrian lane, Blocking the intersection or Double parking can fire for the same stop. No automatic merge exists; only the operator's manual "Same car" merge. Decide the rule: the specific rule wins.
11. **Distance in meters is approximate.** Decide whether to build ground calibration and the uncertain band before the defense, or to state it as future work.
