# Thesis revisions: paste-ready text

Written 2026-10-25 for the panel's consultation requests. Page numbers refer to `docs/files/CH1-3-REVISED-new-2.pdf`
(the page printed on the sheet, not the PDF page). Everything here describes what the system really does today; the numbers come from the code.
Items marked **TO CONFIRM** need your adviser or the LTO before they are quoted.

## 0. Where each block goes

| Block | Goes in | Replaces / adds |
|---|---|---|
| A. Scope of violations | Chapter 1, Scope and Limitations (p. 5) | replaces "Two vehicle types are covered ... pedestrian lane obstruction ... depends on what the hardware can handle" |
| B. Live demonstration | Chapter 1, Scope (p. 5) | replaces "built to support a live camera connection in the future, but that is not what this study tests" |
| C. Camera-angle limitation (+ Table 1) | Chapter 1, Limitations (p. 6-7) | adds to "Video quality also affects detection accuracy ... angled" |
| D. Heuristic decision logic (+ Table 2) | Chapter 3, Algorithmic Framework (p. 44-46) | new paragraph after the three-stage description |
| E. Modular design | Chapter 3, System Architecture (p. 47) | one paragraph; matches Figure 2 "Modular" |
| F. Automatic flow detection | Chapter 3, Stage 2 (p. 46) | new paragraph after the counterflow sentence |
| G. Table 3 additions | Chapter 3, Table 3 (p. 39-43) | new rows (below) |
| H. Evaluation protocol | Chapter 3, Evaluation Metrics (p. 50-52) | how LOAR, CER, WER, precision and recall are measured |
| I. Data section | Chapter 1, footage and dataset paragraph (p. 6) | what the data actually is now |

## A. Scope of violations

Four vehicle groups are covered: motorcycles (and tricycles), cars, pickup trucks and trucks, and buses and jeepneys. The system checks 20 violations.
*Movement and position:* counterflow driving, illegal parking, restricted lane use, pedestrian lane obstruction, illegal turn, illegal U-turn,
swerving, blocking the intersection, and crossing a solid line. *Signals and signs:* red light running, disregarding traffic signs, and signal
light violation (experimental). *Vehicle and riders:* no visible plate number, no helmet, missing side mirror, overloading of motorcycles,
passengers in the open back of a pickup or truck, people riding on the roof of or hanging off a bus, jeepney or truck, no seatbelt, and phone use
while driving. Restricted lane use and phone use while driving are extras that were not in the original list. The signal light violation is marked
experimental because hand signals are lawful and motorcycles are exempt from signal lights under R.A. 4136, so it can over-flag.

## B. Live demonstration

The system reads its video through one camera-input setting that accepts a recorded file, a webcam or an RTSP stream, which is the protocol IP
cameras and CCTV recorders use. For the live demonstration, a second laptop or a phone publishes the test footage as an RTSP stream, so the system
receives it exactly as it would a CCTV feed; when a CCTV recorder is available only the address changes. The live view shows the stream status,
its frame rate and its delay. All accuracy results are measured on recorded footage; connecting the system to a camera on a public road remains outside this study.

## C. Camera-angle limitation

The system works only when the camera is fixed and sees each vehicle from a suitable angle. The drawn zones, the learned traffic flow and the
tracker assume the camera does not pan, zoom or shake. Each violation also needs a particular view, listed in Table 1: for example, the plate,
helmet, seatbelt and mirror checks need the front or rear of the vehicle at a usable size; passengers in a pickup's bed or on a bus roof need a side
or rear view at a moderate height, because a straight top-down view cannot tell the bed from the cab; turns, U-turns and blocking the intersection
need an elevated view of the whole junction; and a side mirror cannot be judged from the side because one mirror is always hidden. Footage from a
very low or very high angle, hand-held footage, and footage in which vehicles are small, blocked or blurred lowers accuracy. The evaluation clips are
chosen to meet these requirements; the numbers are working values for this study and are tightened or relaxed by the benchmark results.

Working camera specification for the evaluation clips:

- Fixed camera: no panning, zooming or hand-held footage (the zones and the learned flow assume one fixed view).
- Mounted above the road (about 3 to 8 m) looking down at 15 to 45 degrees, not straight down.
- Vehicles at least 120 px wide in the picture for plate, helmet and seatbelt checks (the plate check ignores vehicles under 60 px).
- At least 720p and 15 fps; 25-30 fps is better. Daylight for the first test set; evening and night as a separate set.
- Each vehicle visible for at least 3 s (the rules need several position updates; swerving needs 6 s).
- No heavy rain, lens dirt or strong backlight in the main test set.

**Table 1. View each violation needs**

| Violation | Camera view that works | Known limit |
|---|---|---|
| Counterflow | Any fixed view where the road direction is clear. | Two-way roads are never judged in auto mode (both directions are normal there). Needs a fixed camera. |
| Illegal parking | Any fixed view where the zone and the whole vehicle are visible. | Judged on speed below 25 px/s, so a camera that shakes can hide a parked car. |
| Restricted lane | Any fixed view where the lane and the vehicle type are clear. | Not in the thesis list; kept as an extra. |
| Pedestrian lane obstruction | Any fixed view where the crosswalk and the whole vehicle are visible. | - |
| Illegal turn | Elevated view of the junction (the whole turn visible for 2 s or more). | - |
| Illegal U-turn | Elevated view of the road section. | The legal wording (local no-U-turn rules) still has to be confirmed before it is quoted on a ticket. |
| Swerving | Rear or front view along the road; the vehicle visible for 6 s or more and travelling at least 2 box widths. | - |
| Red light running | View of the stop line and of the vehicles' wheels; the light itself visible if the real light is used. | An unknown light never produces a ticket. |
| Disregarding traffic signs | Fixed view of the sign's zone. | - |
| Signal light violation (experimental) | Close front or rear view where the indicators at the left and right edges are visible. | EXPERIMENTAL: it can over-flag (hand signals are lawful, motorcycles are exempt), so it is not a headline result. |
| Blocking the intersection | Elevated view of the whole junction box. | The legal basis (local anti-obstruction rules) still has to be confirmed. |
| Crossing a solid line | Fixed view where the line and the wheels are visible. | The legal basis (no-overtaking rules) still has to be confirmed. |
| Overloading (too many riders) | Front, rear or side view with every rider's body visible and the motorcycle large enough to count heads. | Riders are counted from person boxes; heavy overlap hides riders. |
| Passengers in the back of a pickup / truck | Front, rear or side view at a moderate height, so the bed and the cab are apart in the picture. | A straight top-down view cannot tell the bed from the cab. Pickups are usually detected as 'truck'. Legal basis: RA 4136 Sections 32 and 51 (the fine amounts are unconfirmed). |
| Riding on the roof or hanging off a vehicle | The whole side or the rear of the vehicle at a moderate height. | Someone on the rear step seen from straight behind is hidden by the vehicle. |
| No plate number | Vehicles at least 60 px wide in the picture, plate side facing the camera. | A plate found at any fair look cancels the suspicion. |
| No helmet | Front or rear view of the motorcycle with the riders' heads visible. | Needs the helmet model; the training data is not from Zamboanga. |
| No seatbelt | Front view of the car, close enough to see through the windshield, daylight. | Tinted windows are skipped on purpose (safety gate); the only tinted-window data is general car photos (train only), so the gate is not trustworthy until tested on Zamboanga footage. |
| Phone use while driving | Front view through a clear windshield, daylight. | Not in the thesis list; kept as an extra. |
| Missing side mirror | Front or rear view of the motorcycle with the mirrors large enough to see. | Training data exists now (about 3,100 small motorcycle crops from one Philippine street camera, see datasets/CATALOG.md) but the cabin model has not been retrained on it; expect weak results until crops from our own footage are added. |

## D. Heuristic decision logic

Every violation is decided by explicit, documented heuristic rules rather than by one end-to-end learned model. A heuristic is a rule of thumb with
measurable thresholds: for example, a vehicle is parked illegally when it stays inside a no-parking zone, slower than 25 pixels per second, for
longer than the zone's time limit. The learned models (YOLO detectors for vehicles, riders, plates and cabins; DeepSORT for tracking; OCR for plate
text) supply what is on the screen and how it moves; the rules decide whether that is a violation. Table 2 lists each rule with its thresholds.
This makes every ticket explainable, because the evidence record shows which rule fired and which part of the vehicle caused it, and each
threshold can be changed and re-measured with the benchmark without retraining a model. Where a single frame is unreliable (helmet, seatbelt,
phone, mirror, overloading, passengers, plate), the decision is a vote over recent looks (usually at least 60% of the last 10), so one wrong frame
cannot create a ticket.

**Table 2. The decision rules and their thresholds** (distances in pixels of the processed frame; the thresholds are defaults and can be set per camera)

| Violation | Rule (heuristic) | Model needed |
|---|---|---|
| counterflow | Zone mode: movement over the last ~3 s points more than 90 deg against the zone's legal-flow arrow (at least 4 position updates and 6 px of travel). Auto mode: more than 135 deg against the learned direction of its grid cell for 1.5 s in a row. Two-way and not-yet-learned cells are never judged. | none |
| illegal_parking | Inside the zone and slower than 25 px/s for longer than the zone's time limit (default 180 s); at least 5 position updates. | none |
| restricted_lane | Ground point inside the lane zone and the vehicle's class (most common class over its whole track) is not in the zone's allowed list. | vehicle detector |
| pedestrian_lane | Stopped (below 25 px/s) inside the crosswalk zone for more than 3 s. | none |
| illegal_turn | Inside the zone the heading swings 45 deg or more, now points along the forbidden-direction arrow (within 45 deg) and did not on entry; headings need half a box width (at least 15 px) of travel. | none |
| illegal_u_turn | Inside the zone the heading swings 150 deg or more AND the vehicle moves sideways at least 0.75 box widths from its entry line. | none |
| swerving | Over 6 s the smoothed path swings sideways at least 0.5 median box widths, two or more reversals (left-right-left); the vehicle must travel at least 2 box widths. | none |
| red_light | The ground point crosses the stop line clearly (30% of the box width, at least 10 px) from the side it was first seen on while the light is red. Light = colour in a box drawn around the real light, or a simulated timer cycle. An unknown light never tickets. | none |
| disregarding_signs | One zone per sign. No entry: moving along the prohibited arrow (within 45 deg). No turn: turning into the prohibited direction. No stopping: stopped longer than 5 s. Vehicle ban: banned class inside. Stop sign: crosses the stop line without a full stop (below 25 px/s for 1 s). | none |
| signal_light (experimental) | Inside the zone, a turn of 45 deg or more and no blinking amber on the left or right 30% edge of the box in the last 5 s (blinking = steady on/off at 0.5-3 Hz). | none (colour analysis) |
| blocking_intersection | Stopped (below 25 px/s) inside the junction box for more than 5 s. | none |
| crossing_solid_line | The ground point ends clearly past the drawn line (30% of the box width, at least 10 px), coming from the side it was first seen on. | none |
| overloading | Riders = person boxes whose feet are inside the motorcycle's width, with at least 30% of the person over the motorcycle. More than the maximum (default 2) in at least 60% of the last 10 looks (minimum 5 looks). | vehicle detector (person class) |
| pickup_passengers | For a moving truck or pickup: a person in the trailing 40% of the vehicle along its travel, feet on its body, moving with it; at least 60% of the last 10 looks (minimum 5). | vehicle detector (person, truck) |
| riding_outside_vehicle | For a moving bus, jeepney or truck: a person on the roof (feet in the top 30%, head at or above the roof line) or hanging off the side or back, moving with the vehicle; vote of 60% of 10 looks (minimum 5). | vehicle detector (person, bus, truck) |
| no_plate | No plate in any fair look over the whole track (at least 6 fair looks; vehicle at least 60 px wide; a motorcycle seen from the rear). Pending while the vehicle is on screen, decided when it leaves or the video ends; a plate found later cancels it. | plate model |
| no_helmet | The helmet model, looking at the motorcycle together with its riders, finds a rider without a helmet in at least 60% of the last 10 looks (minimum 3). | helmet model |
| no_seatbelt | Cabin model: a clear window and no seatbelt seen in at least 80% of at least 4 looks. A tinted window or no clear window means no look (safety gate). | cabin model |
| distracted_driving | Cabin model finds a phone held by the driver in at least 60% of the last 10 looks (minimum 3). Not in the thesis list. | cabin model |
| missing_side_mirror | Cabin model counts fewer than 2 mirrors in at least 80% of at least 5 looks, judged only when the motorcycle is seen from the front or the rear. | cabin model (needs mirror data) |

## E. Modular design

Each violation is its own module with the same interface: what it needs (a zone, a specialist model, or nothing), when it fires, and how it
explains itself. The 20 modules share one detector, one tracker and one ledger of each vehicle's history. Visual checks (helmet, plate,
seatbelt and phone, side mirror) use specialist models; movement checks need no extra model. A new violation is added as one module with its own
tests, and a violation that is switched off is not run and its model is not loaded.

## F. Automatic flow detection

The legal direction of traffic can be given in two ways. In zone mode the operator draws the lane zone and an arrow (kept as the reference and for
testing). In automatic mode the system learns it from the traffic itself: the picture is divided into a 16 x 9 grid, every tracked moving vehicle
votes for its heading in the cell it occupies (eight directions of 45 degrees), and a cell is judged only when at least 3 different vehicles and 15
votes have been collected and one direction holds 70% of them. A vehicle that heads more than 135 degrees against its cell's dominant direction for 1.5 s
is flagged. Two-way cells are never judged, because the system cannot tell which side is legal there. For a recorded clip the first 60 s are scanned
before the analysis starts. The learned flow is checked against hand-drawn zones on the same clips. Limit: it needs a fixed camera and some normal
traffic, and a clip whose first vehicles are the wrong-way ones learns the wrong flow.

## G. Table 3 additions (new rows)

| Class to be detected | Legal basis | Implementation / challenges |
|---|---|---|
| Pickup / truck, passengers in the open back | R.A. 4136, Secs. 32 and 51 (persons riding outside or at the rear of a vehicle); LTO memorandum of Sept. 2019 applying them to the cargo area of trucks including pickups; MMDA Regulation No. 04-005 (Metro Manila). Fine amounts differ between reports: do not quote them until confirmed. | Person and truck boxes plus position and co-motion rules. A top-down camera cannot separate the bed from the cab; pickups are detected as 'truck'. |
| Bus / jeepney / truck, riding on the roof or hanging off | Same R.A. 4136 Secs. 32 and 51. | Someone on the rear step seen from straight behind is hidden by the vehicle. |
| Illegal U-turn | TO CONFIRM: there is no single 'U-turn' offence. It is charged under the sign or marking that prohibits it (disregarding traffic signs / illegal turn, R.A. 4136 Sec. 42 as in the existing table), or as reckless driving (Sec. 48) or obstruction of traffic (Sec. 54). | Needs an elevated view of the whole turn; a vehicle reversing in a straight line must not count. |
| Blocking the intersection | TO CONFIRM: obstruction of traffic (R.A. 4136 Sec. 54) and local anti-obstruction rules (MMDA obstruction fine reported as P1,000 under Regulation No. 18-008). | Waiting before the junction box is legal; only stopping inside it counts. |
| Crossing a solid line | TO CONFIRM: R.A. 4136 Sec. 41 (restrictions on overtaking and passing); the double-solid-line no-passing rule is usually quoted from road-marking guides, not from the statute text. | A vehicle wobbling on its own side must not count: it has to end up clearly past the line. |
| Restricted lane (extra) | TO CONFIRM: local ordinances on bus / motorcycle lanes. | Needs the lane zone and the allowed vehicle types. |
| Phone use while driving (extra) | R.A. 10913 (Anti-Distracted Driving Act). | Windshield glare and tint hide the phone; skipped when the window is tinted. |

## H. Evaluation protocol (Technical Simulation Benchmarking)

The evaluation set is a registry of clips whose real violations were written down by the team: for each event the violation, the start and end
time, and where possible the true plate string and the vehicle's place in the picture. Each clip is analysed by the same code the dashboard uses.
A ticket **catches** a real event when it is the same violation and its evidence time is within 3 s of the event; each ticket and each event is used
once. A ticket with no real event is a **false alarm**; a real event with no ticket is **missed**. Per violation: precision = caught / (caught + false
alarms), recall = caught / (caught + missed), plus false alarms per minute of footage. **LOAR** counts a caught event as correctly logged only when the
violation type, the vehicle and the plate string all match, as defined in this chapter; plate **CER** is the character edits divided by the characters
of the true plates and **WER** is the share of plates that are not exactly right. A violation is only given a verdict (pass or fail against the targets)
when the registry holds at least 10 real events of it; violations with no real events are reported as not yet benchmarked. mAP@50 of the detectors is
measured separately on the held-out test split of each training set. Tool: `python -m tools.benchmark` (see `benchmarks/README.md`).

## I. Data section (what the data is now)

The detector training sets are built from public sources with documented licences instead of the original plan of 3,000 annotated images:
about 20,900 vehicle pictures (Philippine vehicle sets with jeepneys and tricycles), 7,600 helmet pictures (real road photos from India plus stock
photos), 13,300 plate pictures (Open Images, Indonesia, Malaysia, Turkey and older sets) and 8,900 windshield pictures (enforcement-camera views).
Every set was checked for broken files and for pictures that appear in both training and testing; the cabin set had such overlaps in about 70% of its
validation and test pictures, which were removed. None of this footage is from Zamboanga, so the limitation that results may not reflect the city's
traffic still applies until the barangay or MMDA footage arrives. Sources and licences: `training_lab/datasets/CATALOG.md`.

## J. Things in the current text that no longer match

- p. 5: "Two vehicle types are covered" (now four groups) and "extended targets ... depends on what the hardware can handle" (all built).
- p. 5: the live camera is "not what this study tests": now a simulated CCTV stream is shown live (block B).
- p. 6: footage sources (GTA V, MMDA, barangay) and "at least 3,000 images ... Roboflow ... 80/10/10": see block I.
- p. 45: "counting the number of heads" for overloading: the system counts person boxes on the motorcycle.
- p. 51: LOAR uses "track ID": the benchmark checks the vehicle by its place in the picture, because the tracker's ID numbers are not known in advance.
