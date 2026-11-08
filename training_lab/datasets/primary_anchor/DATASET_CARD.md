# primary_anchor - dataset card

Generated 2026-10-25 by `python data.py report`. Do not edit by hand.

```
Primary Anchor Dataset
NOTE: In most cases you do NOT need to train this model from scratch.
The pretrained YOLOv8n COCO weights already detect cars and motorcycles well.
Only train this if you need to add Philippine-specific vehicle classes (e.g., tricycles, kalesas).
```

## Layout

`images/{train,val,test}/` + `labels/{train,val,test}/` (YOLO txt: `class cx cy w h`, normalised) + `data.yaml`. 6 classes: `0` motorcycle, `1` car, `2` bus, `3` truck, `4` person, `5` tricycle.

## Contents

| split | pictures | motorcycle | car | bus | truck | person | tricycle |
|---|---|---|---|---|---|---|---|
| train | 24,763 | 5,724 | 14,503 | 10,824 | 6,401 | 27,109 | 4,908 |
| val | 876 | 488 | 1,005 | 481 | 344 | 1,815 | 27 |
| test | 430 | 217 | 552 | 252 | 238 | 1,082 | 8 |

Longest side of a picture: min 640 / median 640 / max 640 px. A box covers (10th pct / median / 90th pct of the picture): 0.0014 / 0.0353 / 0.6136.

## Where the pictures come from

| source | train | val | test | licence | country | Philippine | trust | link |
|---|---|---|---|---|---|---|---|---|
| ph_plate_vehicle | 67 | 20 | 13 | CC BY 4.0 | Philippines | yes | B (community, open licence, named author) | https://universe.roboflow.com/research-3wj93/philippine-plate-and-vehicle |
| ph_vehicles | 19,490 | 856 | 417 | CC BY 4.0 | Philippines | mixed | B (community, open licence, named author) | https://universe.roboflow.com/capstone-xgfsp/v4-best-philippine-vehicle-datasest-11ztu |
| ph_vehicles_selfdev | 5,206 | 0 | 0 | CC BY 4.0 | Philippines | yes | B (community, open licence, named author) | https://universe.roboflow.com/selfdev-l0ovg/ph-vehicles |

Philippine pictures: **5,306 of 26,069 (20%)**, plus 20,763 (80%) from a source that mixes real Philippine photos with generic web pictures. Everything else is foreign imagery: fine for learning what the object looks like, not proof of field accuracy.

## Known limits

- Class `tricycle` has only 27 boxes in `val`: its score is unreliable (below 50).
- Class `tricycle` has only 8 boxes in `test`: its score is unreliable (below 50).
- `ph_vehicles`: real Philippine jeepney / tricycle photos mixed with generic web, stock and Street View pictures; heavy augmentation (rotated, upside-down, noise)
- `ph_vehicles_selfdev`: checked by eye 2026-10-25: Philippine web photos of single vehicles (jeepney, van, bus, tricycle), large boxes

## Cleaning log

Checked 26,069 pictures, kept 26,069. Moved to `datasets/_quarantine/primary_anchor/` (not deleted): nothing. Label files fixed: 0. Pictures re-saved as upright RGB JPEG: 0.
A picture that sits in both train and val/test keeps its val/test copy; the train copy is the one quarantined.
**Before the first cleaning, 81 val and 27 test pictures had a near-identical twin in train (same scene or video frame), so scores measured on this data earlier were optimistic.**

## Rebuild

```
python scripts/fetch_datasets.py --model primary_anchor
python data.py curate --model primary_anchor --apply
python data.py report
```
