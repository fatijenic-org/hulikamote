# helmet_specialist - dataset card

Generated 2026-11-09 by `python data.py report`. Do not edit by hand.

```
Helmet Specialist Dataset
Input: Cropped motorcycle box joined with its riders' person boxes (as engine/pipeline.py crops it,
so heads are not cut off). Harvest training crops the same way.
Task: Detect whether each rider has a valid helmet on their head

CRITICAL ANNOTATION RULE:
Use composite classes — annotate the WHOLE RIDER, not just the helmet.
This prevents the "helmet on lap" false negative described in AI_ENGINEERING_PLAN.md.
The rider's bounding box should span their full torso + head.
```

## Layout

`images/{train,val,test}/` + `labels/{train,val,test}/` (YOLO txt: `class cx cy w h`, normalised) + `data.yaml`. 2 classes: `0` rider_with_helmet, `1` rider_without_helmet.

## Contents

| split | pictures | rider_with_helmet | rider_without_helmet |
|---|---|---|---|
| train | 10,589 | 9,462 | 8,908 |
| val | 923 | 873 | 984 |
| test | 697 | 800 | 790 |

Longest side of a picture: min 36 / median 640 / max 1280 px. A box covers (10th pct / median / 90th pct of the picture): 0.0015 / 0.0125 / 0.0522.

## Where the pictures come from

| source | train | val | test | licence | country | Philippine | trust | link |
|---|---|---|---|---|---|---|---|---|
| edgevision_helmet | 1,885 | 265 | 230 | CC BY 4.0 | India | no | A (official / peer-reviewed host) | https://data.mendeley.com/datasets/j82bnw7gsr/1 |
| flashys_helmet | 4,837 | 303 | 101 | CC BY 4.0 (labels only: the pictures are stock photos) | ? | no | C (origin unclear or weak) | https://universe.roboflow.com/flashys-workspace/helmet-detection-fsrgu |
| martinez_helmet | 844 | 0 | 0 | CC BY 4.0 | Philippines | yes | B (community, open licence, named author) | https://universe.roboflow.com/css1823martinezmina-xyhl4/motorcycle-helmet-72c9g |
| naratip_helmet | 3,023 | 355 | 366 | MIT | Thailand | no | B (community, open licence, named author) | https://universe.roboflow.com/naratipws/motorcycle-helmet-w75eo |

Philippine pictures: **844 of 12,209 (7%)**. Everything else is foreign imagery: fine for learning what the object looks like, not proof of field accuracy.

## Known limits

- Less than a quarter of the pictures are Philippine: collect and review Zamboanga footage (`python harvest.py`).
- `flashys_helmet`: mostly Shutterstock / iStock stock photos (watermarks visible) of people on scooters, head-level boxes, augmented copies: weak evidence for real road accuracy
- `mapua_helmet`: one street camera in Manila (night + day, 2022), whole 640x640 frames with heads of only ~15 x 26 px, no motorcycle / rider boxes to cut crops from; the helmet model is fed rider crops. Use after cutting rider crops with the vehicle detector. Only ~230 'No-Helmet' heads in 2,184 train pictures. Same camera as martinez_helmet
- `martinez_helmet`: checked by eye 2026-10-25: Manila CCTV, 640x640 stretched frames; only ~105 'Not Wearing Helmet' boxes in train, so it mostly adds compliant riders from the target camera type
- `naratip_helmet`: checked by eye 2026-10-25: head-level boxes on close-up photos of riders (some stock-like); the train split holds rotated copies with black corners; some pictures have only 'person' boxes (skate park, bicycles) and are skipped

## Cleaning log

Checked 12,210 pictures, kept 12,209. Moved to `datasets/_quarantine/helmet_specialist/` (not deleted): duplicate 1. Label files fixed: 0. Pictures re-saved as upright RGB JPEG: 0.
A picture that sits in both train and val/test keeps its val/test copy; the train copy is the one quarantined.
**Before the first cleaning, about 15 val and about 8 test pictures had a near-identical twin in train (same scene or video frame), so scores measured on this data earlier were optimistic.**

## Rebuild

```
python scripts/fetch_datasets.py --model helmet_specialist
python data.py curate --model helmet_specialist --apply
python data.py report
```
