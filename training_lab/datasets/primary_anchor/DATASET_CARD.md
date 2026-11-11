# primary_anchor - dataset card

Generated 2026-11-09 by `python data.py report`. Do not edit by hand.

```
Primary Anchor Dataset
NOTE: In most cases you do NOT need to train this model from scratch.
The pretrained YOLOv8n COCO weights already detect cars and motorcycles well.
Only train this if you need to add Philippine-specific vehicle classes (e.g., tricycles, kalesas).
```

## Layout

`images/{train,val,test}/` + `labels/{train,val,test}/` (YOLO txt: `class cx cy w h`, normalised) + `data.yaml`. 7 classes: `0` motorcycle, `1` car, `2` bus, `3` truck, `4` person, `5` tricycle, `6` jeepney.

## Contents

| split | pictures | motorcycle | car | bus | truck | person | tricycle | jeepney |
|---|---|---|---|---|---|---|---|---|
| train | 28,445 | 7,873 | 17,088 | 5,783 | 6,818 | 28,235 | 6,279 | 6,447 |
| val | 1,587 | 892 | 1,461 | 443 | 498 | 1,854 | 238 | 184 |
| test | 822 | 493 | 834 | 242 | 301 | 1,115 | 124 | 92 |

Longest side of a picture: min 115 / median 640 / max 1280 px. A box covers (10th pct / median / 90th pct of the picture): 0.0015 / 0.0306 / 0.5828.

## Where the pictures come from

| source | train | val | test | licence | country | Philippine | trust | link |
|---|---|---|---|---|---|---|---|---|
| ph_plate_vehicle | 67 | 20 | 13 | CC BY 4.0 | Philippines | yes | B (community, open licence, named author) | https://universe.roboflow.com/research-3wj93/philippine-plate-and-vehicle |
| ph_traffic_detection | 1,345 | 60 | 40 | CC BY 4.0 | Philippines | yes | B (community, open licence, named author) | https://universe.roboflow.com/new-workspace-he7oi/philippine-traffic-detection |
| ph_vehicle_classification | 2,345 | 655 | 352 | CC BY 4.0 | Philippines | yes | B (community, open licence, named author) | https://universe.roboflow.com/thesis-vdkcz/vehicle-classification-philippines |
| ph_vehicles | 19,508 | 852 | 417 | CC BY 4.0 | Philippines | mixed | B (community, open licence, named author) | https://universe.roboflow.com/capstone-xgfsp/v4-best-philippine-vehicle-datasest-11ztu |
| ph_vehicles_selfdev | 5,180 | 0 | 0 | CC BY 4.0 | Philippines | yes | B (community, open licence, named author) | https://universe.roboflow.com/selfdev-l0ovg/ph-vehicles |

Philippine pictures: **10,077 of 30,854 (33%)**, plus 20,777 (67%) from a source that mixes real Philippine photos with generic web pictures. Everything else is foreign imagery: fine for learning what the object looks like, not proof of field accuracy.

## Known limits

- `ph_vehicles`: real Philippine jeepney / tricycle photos mixed with generic web, stock and Street View pictures; heavy augmentation (rotated, upside-down, noise)
- `ph_vehicles_selfdev`: checked by eye 2026-10-25: Philippine web photos of single vehicles (jeepney, van, bus, tricycle), large boxes
- `ph_traffic_detection`: Jeep and Tricycle have their own classes here. 'Vehicles' (775 boxes) is mapped to car; Bicycle is not one of ours, so it is dropped.

## Cleaning log

Checked 35,905 pictures, kept 30,854. Moved to `datasets/_quarantine/primary_anchor/` (not deleted): leak 3311, duplicate 1733, no_boxes 7. Label files fixed: 141. Pictures re-saved as upright RGB JPEG: 3241.
A picture that sits in both train and val/test keeps its val/test copy; the train copy is the one quarantined.
**Before the first cleaning, 81 val and 27 test pictures had a near-identical twin in train (same scene or video frame), so scores measured on this data earlier were optimistic.**

## Rebuild

```
python scripts/fetch_datasets.py --model primary_anchor
python data.py curate --model primary_anchor --apply
python data.py report
```
