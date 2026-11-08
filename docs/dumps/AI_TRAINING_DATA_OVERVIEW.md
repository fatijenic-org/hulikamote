# AI Training Data Overview (plain language)
Not part of the ledger. Written alongside docs/AI_ROADMAP_PLAN.md.

## Rule
Harvest first, train later. Do not run training without explicit user instruction.

## Models and their data

| # | Model | Job | Data to harvest | Training in plain words |
|---|---|---|---|---|
| 1 | Plate detector (YOLO plate specialist) | Find the plate on a car | True/False Positive clicks in the Forensic Analyzer. False Positives are "hard negatives" (e.g. a bumper is not a plate) | Show photos with plate boxes marked; it learns to draw the box. Wrong boxes are shown as "not this" |
| 2 | Plate reader (OCR) | Read the characters | Plate crops that were confirmed or corrected | Show crop + correct text; it learns local plate font/spacing and stops confusing O/0 etc. |
| 3 | Car-matching model (ReID, inside DeepSORT) | Tell if two photos are the same car | "Different car" marks, merges, and splits made during review (NOT YET SAVED - to be built) | Show pairs labeled same/different; same-car photos should look alike, different cars should look different. Reduces ID mix-ups |
| 4 | Helmet / phone detectors (rider specialists) | Spot no-helmet / phone use | No manual harvesting: download labeled datasets from Kaggle / Roboflow | Same as the plate detector |
| 5 | Main vehicle detector (YOLO) | Detect vehicles | None from the review work | Leave alone |

## Suggested order
1. Keep harvesting (plate detector + OCR data already flows in).
2. Add saving of the review decisions as ReID data (model 3).
3. Train only when enough data exists and the user says so.
