# REVISION LOG

Document: `FINAL-PROPOSAL.pdf` (92 pages).
Printed page = PDF page - 9. Line numbers are the numbers in the left margin of the PDF.
Each entry has: where, DELETE (exact old text), WRITE (new text). The metadata is below the line.
Add new entries at the bottom.

| # | Where | What |
|---|---|---|
| 1 | printed p. 4, line 213 | Objective: vehicle scope |
| 2 | printed p. 5, lines 239-247 | Scope paragraph: vehicles and violations |
| 3 | printed pp. 5-6, lines 255-260 | Data sources |
| 4 | printed p. 6, lines 276-277 | Limitation: side mirror |
| 5 | printed p. 7, lines 280-282 | Limitation: footage and camera |
| 6 | printed p. 9 | Glossary: Bounding Box |
| 7 | printed pp. 10-11 | Glossary: eFOI Portal, MMDA |
| 8 | printed p. 32, lines 610-611 | Phase 1: data gathering |
| 9 | printed pp. 34-35, lines 644-672 | Data Collection |
| 10 | printed pp. 39-43 | Table 3 |
| 11 | printed p. 45, lines 769-770 | Stop line and red light |
| 12 | printed p. 63, lines 1077-1079 | Appendix: footage request note |

---

## 1. Objective: vehicle scope
**Page:** printed 4 (PDF 13) | **Lines:** 213

**DELETE:**
> violations for motorcycles and cars;

**WRITE:**
> violations for vehicles common in Zamboanga City;

*Metadata*
- Why: the study now covers all common Zamboanga vehicles.
- Status: agreed

---

## 2. Scope paragraph: vehicles and violations
**Page:** printed 5 (PDF 14) | **Lines:** 239 to the word "development." in line 247

**DELETE:**
> Two vehicle types are covered, specifically motorcycles and cars. The violations selected between motorcycles and cars are almost the same: counterflow driving, illegal parking, illegal turn, disregarding traffic signs, and no visible plate number. Additional violations for motorcycles are no helmet, missing side mirror, and overloading. The panel also requested the inclusion of signal light violations, red light running, Swerving, No seatbelt, and pedestrian lane obstruction. These are being considered as extended targets, but whether they make it into the final prototype depends on what the hardware can handle during development.

**WRITE:**
> The vehicles covered are those common in Zamboanga City: motorcycles, cars, tricycles, jeepneys, buses, trucks, pickups, and kuliglig. The mandatory violations are: counterflow driving, illegal parking, illegal turn, disregarding traffic signs (stop sign), no visible plate number, illegal U-turn, crossing a solid line, restricted lane, overtaking on the right, signal light violation, red light running, swerving, and pedestrian lane obstruction. These apply to all vehicles. These apply to one vehicle type only: no helmet, missing side mirror, and overloading (motorcycles); no seatbelt (cars); passengers in a kuliglig (kuliglig). Passengers on a pickup bed or riding outside a vehicle apply to all vehicles except motorcycles. Other violations that the prototype implements, such as blocking the intersection, sidewalk driving, illegal loading, truck ban, tricycle on a national highway, double parking, and distracted driving, are optional extras.

**Keep:** the sentence that starts "In selecting the primary categories..." (line 247) and everything after it.

*Metadata*
- Why: team decision. 20 mandatory violations. The old "extended targets" sentence no longer applies.
- Count check: 13 (all vehicles) + 3 (motorcycle) + 1 (car) + 1 (kuliglig) + 2 (pickup, riding outside) = 20.
- Not built yet: kuliglig passenger, overtaking on the right.
- Status: agreed

---

## 3. Data sources
**Page:** printed 5-6 (PDF 14-15) | **Lines:** 255 to the word "themselves." in line 260

**DELETE:**
> Traffic footage from the Metropolitan Manila Development Authority (MMDA) will also be requested through the electronic Freedom of Information (eFOI) Portal. GTA V gameplay recordings will be used as a synthetic source since they produce controlled road scenarios without capturing real people. Public datasets from COCO, Kaggle, and Roboflow Universe will supplement these. If none of the above becomes available, the researchers will record the footage themselves.

**WRITE:**
> If the barangay footage is of low quality or does not meet the camera limits of this study, the researchers will rely on publicly available datasets (COCO, Kaggle, Roboflow Universe) and on footage they record themselves, for training the models and for evaluating the violation detection pipeline.

**Keep:** lines 251-254 (barangay request) and the sentence "The target is at least 3,000 images, annotated through Roboflow with an 80/10/10 training split." (lines 260-262).

*Metadata*
- Why: MMDA takes too long. GTA V and CARLA are removed by team decision.
- Note: the 3,000 target is a plan, not a claim. Report the real counts in the data section (optional).
- Status: agreed

---

## 4. Limitation: side mirror
**Page:** printed 6 (PDF 15) | **Lines:** 276-277

**KEEP:**
> Side mirror detection is also harder than the others because mirrors are small objects and the rider's arms often block them in the frame.

**ADD AFTER IT:**
> Missing side mirror is judged only from the front or rear of a motorcycle. From the side, one mirror is always hidden.

*Metadata*
- Why: states a physical limit. It is not a data limit.
- Status: agreed

---

## 5. Limitation: footage and camera
**Page:** printed 7 (PDF 16) | **Lines:** 280-282

**DELETE:**
> Because some footage may come from outside Zamboanga City, including GTA V scenes and MMDA recordings, the results may not fully reflect traffic patterns specific to the city.

**WRITE:**
> Because some footage may come from outside Zamboanga City, such as public datasets, the results may not fully reflect traffic patterns specific to the city. Barangay CCTV may also be of low quality or outside the camera limits of this study. In that case, the study relies on public datasets and on footage the researchers record themselves. The system is evaluated on footage from a fixed camera mounted about 3 to 8 m above the road, looking down at 15 to 45 degrees, in daylight, at 720p or higher and at least 15 frames per second. Night footage, heavy rain, strong backlight, moving cameras, and straight top-down views are outside the scope of this study.

*Metadata*
- Why: GTA V and MMDA removed. The proposal had no camera angle or lighting limit.
- Full list of limits: `SCOPE_AND_LIMITATIONS.md`.
- Status: agreed

---

## 6. Glossary: Bounding Box
**Page:** printed 9 (PDF 18)

**DELETE:**
> A rectangular marker drawn by the detection model around a detected object, such as a vehicle, rider, helmet, plate, or traffic sign.

**WRITE:**
> A rectangular marker drawn by the detection model around a detected object, such as a vehicle, rider, helmet, or plate.

*Metadata*
- Why: the system does not detect signs. The old text suggests it does.
- Status: proposed

---

## 7. Glossary: eFOI Portal and MMDA
**Page:** printed 10 (PDF 19) and printed 11 (PDF 20)

**DELETE (printed 10, entry 10):**
> eFOI Portal: A Philippine government website where anyone can file formal requests for public documents online, where MMDA footage request is submitted.

**DELETE (printed 11, entry 22):**
> MMDA: The Metropolitan Manila Development Authority manages traffic and urban development in Metro Manila. Traffic footage from MMDA was one of the sources requested for use in this study.

**THEN:** renumber the glossary entries after each deleted entry.

*Metadata*
- Why: MMDA is no longer a data source.
- Note: "MMDA Regulation No. 96-009" appears in Table 3 as a law reference. Table 3 (entry 10) removes it. If you keep it, keep a short MMDA entry without the footage sentence.
- Status: proposed

---

## 8. Phase 1: data gathering
**Page:** printed 32 (PDF 41) | **Lines:** 610-611

**DELETE:**
> in the area, and the existing CCTV footages taken from MMDA to ensure

**WRITE:**
> in the area to ensure

*Metadata*
- Why: MMDA removed.
- Status: agreed

---

## 9. Data Collection
**Page:** printed 34-35 (PDF 43-44) | **Lines:** 644-672

**9a. Lines 644-646**

DELETE:
> instead of generic datasets because

WRITE:
> from Barangay Baliwasan, and use public datasets and our own recordings where that footage cannot be used, because

**9b. Lines 647-649**

DELETE:
> motorcycles, jeepneys, tricycles whilst making it focus on motorcycles and car vehicles specifically. Hence, our data is being taken from three sources:

WRITE:
> motorcycles, cars, tricycles, jeepneys, buses, trucks, pickups, and kuliglig. Hence, our data is being taken from two sources:

**9c. Lines 659-666**

DELETE the whole item:
> 2. MMDA Historical Video Traces
> This is our secondary source by which, we aim to acquire with our utmost capacity to acquire from the Metropolitan Manila Development Authority. Acquiring such data might take longer which could compromise our target deadline for this project, which explains why it is our second option for this study. But, acquiring such extremely high-density intersection scenes, it will train our models to be exposed with more demanding vehicle occlusion and much more higher vehicle counts than what our standard local footage from the barangay will provide.

**9d. Lines 667-669**

DELETE:
> 3. Contingency Field Recording
> If neither of our first two sources would every be available in worst case scenarios, we will resort to manual field recording; which serves as our insurance

WRITE:
> 2. Public Datasets and Field Recording
> If the barangay footage is of low quality or does not meet the camera limits of this study, we will use openly licensed public datasets and manual field recording, which serves as our insurance

**Keep:** lines 670-672 and the rest of that paragraph.

*Metadata*
- Why: MMDA removed. The text must match how the models were really trained (public datasets).
- Status: agreed

---

## 10. Table 3
**Page:** printed 39-43 (PDF 48-52)

**DELETE:** the whole of Table 3 (all motorcycle and car rows).

**WRITE:** the table in `TABLE3_UPDATE.md`, section B (20 violations, with an "Applies to" column).

**If you keep the old table instead, fix these cells:**

| Row | Page | DELETE | WRITE |
|---|---|---|---|
| Motorcycle counterflow | 40 | "R.A. 4136, Sec. 45(b)" | "R.A. 4136, Sec. 37" |
| Car counterflow | 43 | "R.A. 4136, Sec. 45(b)" | "R.A. 4136, Sec. 37" |
| Motorcycle illegal turns | 40 | "R.A. 4136, Sec. 42(d); MMDA Regulation No. 96-009" | "R.A. 4136, Sec. 45" |
| Motorcycle illegal parking | 41 | "R.A. 4136, Sec. 51; Local Ordinance No. SP-1160" | "R.A. 4136, Sec. 46" |
| Motorcycle overloading | 39 | "R.A. 4136, Sec. 54(f)" | "R.A. 4136, Sec. 32" |
| Motorcycle no plate | 41 | "R.A. 11235 (Motorcycle Crime Prevention Act); R.A. 8750 (Seat Belts Use Act of 1999 analog for plates)" | "R.A. 11235 as amended by R.A. 12209" |
| Car no plate | 43 | "R.A. 8750; R.A. 4136, Sec. 18" | "R.A. 4136, Sec. 18" |
| Motorcycle disregarding signs | 41 | "R.A. 4136, Sec. 42(a): Trajectory crossing a stop-line or signal-state zone during a restricted signal phase" | "Joint Administrative Order No. 2014-01 (LTO, MMDA), violation of disregarding traffic signs: Trajectory crossing the stop line of a stop sign without a full stop" |
| Car disregarding signs | 42 | "R.A. 4136, Sec. 42(a): Centroid crossing stop-line during restricted signal phase" | "Joint Administrative Order No. 2014-01 (LTO, MMDA), violation of disregarding traffic signs: Centroid crossing the stop line of a stop sign without a full stop" |

*Metadata*
- Why: R.A. 8750 is the Seat Belts Use Act. The other sections cover different rules. RA 4136 has no stop-sign rule.
- Checked against: lawphil.net text. Notes in `VIOLATIONS_AND_SOURCES.md`, section 9, and `TABLE3_UPDATE.md`, section C.
- Not checked: the car rows for illegal turn and illegal parking (printed 42-43).
- Not verified: MMDA Regulation No. 96-009, Local Ordinance No. SP-1160.
- JAO 2014-01: not opened (LTO site blocks the request). Add the item number after you read it.
- Status: agreed on the wording above. Table replacement: proposed.

---

## 11. Stop line and red light
**Page:** printed 45 (PDF 54) | **Lines:** 769-770

**KEEP:**
> This stage also tracks the vehicles path upon crossing the stop-line during red-light timer and flags it as red-light violation.

**ADD AFTER IT:**
> A stop-sign violation is a crossing of the stop line without a full stop. A red-light violation is a crossing while the light is red.

*Metadata*
- Why: the old Table 3 sign rows and this sentence described the same behavior. A panelist could call them duplicates.
- Status: proposed

---

## 12. Appendix: footage request note
**Page:** printed 63 (PDF 72) | **Lines:** 1077-1079

**DELETE:**
> The researchers are also pursuing the MMDA request through the eFOI Portal and CARLA-generated footage as additional sources in case institutional footage becomes unavailable.

**WRITE:**
> If institutional footage becomes unavailable or does not meet the camera limits of this study, the researchers will use public datasets and their own recordings.

*Metadata*
- Why: MMDA, eFOI and CARLA removed.
- Status: agreed

---
