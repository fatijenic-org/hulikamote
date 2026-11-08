# plate_specialist - dataset card

Generated 2026-10-25 by `python data.py report`. Do not edit by hand.

```
Plate Specialist Dataset
Input: a vehicle picture (the plate sits somewhere on it). Task: find the licence plate.
Annotation rule: a tight rectangle around the plate itself; EasyOCR accuracy depends on tight crops.
```

## Layout

`images/{train,val,test}/` + `labels/{train,val,test}/` (YOLO txt: `class cx cy w h`, normalised) + `data.yaml`. 1 classes: `0` license_plate.

## Contents

| split | pictures | license_plate |
|---|---|---|
| train | 12,968 | 20,517 |
| val | 1,790 | 2,561 |
| test | 1,003 | 1,483 |

Longest side of a picture: min 220 / median 640 / max 1280 px. A box covers (10th pct / median / 90th pct of the picture): 0.0002 / 0.0031 / 0.0384.

## Where the pictures come from

| source | train | val | test | licence | country | Philippine | trust | link |
|---|---|---|---|---|---|---|---|---|
| colorum_plates | 196 | 61 | 25 | CC BY 4.0 | mixed (India, UK, USA) | no | B (community, open licence, named author) | https://universe.roboflow.com/colorumscan/colorumscan-ox9vj |
| govviolation_plates | 1,701 | 329 | 118 | CC BY 4.0 | Egypt | no | B (community, open licence, named author) | https://universe.roboflow.com/firstproject-7iwwi/governmentviolation |
| indonesia_plates | 675 | 188 | 94 | CC BY 4.0 on Zenodo; the original Roboflow project named none, so research use only | Indonesia | no | B (community, open licence, named author) | https://zenodo.org/records/15605718 |
| legacy | 2,526 | 297 | 134 | as committed in git (Roboflow exports) | mixed | no | B (community, open licence, named author) |  |
| my_plates | 414 | 89 | 0 | CC BY 4.0 | Malaysia | no | A (official / peer-reviewed host) | https://data.mendeley.com/datasets/9795rjwxnd/1 |
| oi_plates | 2,995 | 400 | 400 | Annotations CC BY 4.0 (Google); images CC BY 2.0 (Flickr authors) | ? | no | A (official / peer-reviewed host) | https://storage.googleapis.com/openimages/web/index.html |
| ph_plates | 4,261 | 404 | 205 | CC BY 4.0 | Vietnam | no | B (community, open licence, named author) | https://universe.roboflow.com/thesis-dzclp/license-plate-detection-jy62w |
| tr_plates250 | 200 | 22 | 27 | CC BY 4.0 | Turkey | no | A (official / peer-reviewed host) | https://zenodo.org/records/23369685 |

Philippine pictures: **0 of 15,761 (0%)**. Everything else is foreign imagery: fine for learning what the object looks like, not proof of field accuracy.

## Known limits

- Less than a quarter of the pictures are Philippine: collect and review Zamboanga footage (`python harvest.py`).
- `ph_plates`: named ph_plates but the pictures are greyscale Vietnamese barrier-camera photos with heavy augmentation (checked by eye 2026-10-24)
- `augmented_plates`: same Vietnamese parking-barrier pictures as ph_plates (8,823 more of one camera view): it would drown the varied plate sets. Checked by eye 2026-10-24
- `colorum_plates`: named like a Philippine colorum project, but checked by eye 2026-10-25: Indian, UK and US plates from car-sale photos. A few boxes sit on the wrong spot (a headlight)
- `govviolation_plates`: Egyptian enforcement cameras, Arabic plates (checked by eye 2026-10-25)

## Cleaning log

Checked 15,761 pictures, kept 15,761. Moved to `datasets/_quarantine/plate_specialist/` (not deleted): nothing. Label files fixed: 0. Pictures re-saved as upright RGB JPEG: 0.
A picture that sits in both train and val/test keeps its val/test copy; the train copy is the one quarantined.
**Before the first cleaning, about 88 val and about 43 test pictures had a near-identical twin in train (same scene or video frame), so scores measured on this data earlier were optimistic.**

## Rebuild

```
python scripts/fetch_datasets.py --model plate_specialist
python data.py curate --model plate_specialist --apply
python data.py report
```
