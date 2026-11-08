# cabin_specialist - dataset card

Generated 2026-10-25 by `python data.py report`. Do not edit by hand.

```
Cabin Specialist Dataset
Input: Cropped car bounding boxes (from primary anchor)
Task: Assess cabin interior for seatbelt, phone use, and window tint

ANNOTATION RULES:
- clear_window / tinted_window: Annotate the windshield region only.
The tinted_window class GATES all seatbelt and phone checks — it must be reliable.
- seatbelt: Annotate the diagonal strap crossing the driver's chest, not the clip.
- driver_phone: Annotate the phone itself if held near the head or at the steering wheel.
- side_mirror: Annotate visible side mirrors on MOTORCYCLE crops only.
If a mirror is missing from a motorcycle, Count(side_mirror) < 2 triggers the violation.
```

## Layout

`images/{train,val,test}/` + `labels/{train,val,test}/` (YOLO txt: `class cx cy w h`, normalised) + `data.yaml`. 5 classes: `0` clear_window, `1` tinted_window, `2` seatbelt, `3` driver_phone, `4` side_mirror.

## Contents

| split | pictures | clear_window | tinted_window | seatbelt | driver_phone | side_mirror |
|---|---|---|---|---|---|---|
| train | 15,689 | 9,860 | 11,142 | 6,685 | 3,430 | 3,138 |
| val | 300 | 306 | 0 | 215 | 69 | 0 |
| test | 402 | 407 | 0 | 255 | 104 | 0 |

Longest side of a picture: min 33 / median 640 / max 1280 px. A box covers (10th pct / median / 90th pct of the picture): 0.0016 / 0.0138 / 0.1854.

## Where the pictures come from

| source | train | val | test | licence | country | Philippine | trust | link |
|---|---|---|---|---|---|---|---|---|
| govviolation_cabin | 1,251 | 112 | 69 | CC BY 4.0 | Egypt | no | B (community, open licence, named author) | https://universe.roboflow.com/firstproject-7iwwi/governmentviolation |
| mc_helmet_overload | 3,072 | 0 | 0 | CC BY 4.0 | Philippines | yes | B (community, open licence, named author) | https://universe.roboflow.com/peds-workspace-1618a/mc-side-mirror-violation |
| menna_cabin | 7,967 | 188 | 333 | CC BY 4.0 | Egypt | no | B (community, open licence, named author) | https://universe.roboflow.com/mennaworkspace/ds-5cu4e |
| tint_windows | 2,994 | 0 | 0 | CC BY 4.0 | ? | no | B (community, open licence, named author) | https://universe.roboflow.com/workspace-4fyp5/window-tint-tint-insq3 |
| tpnew_seatbelt | 405 | 0 | 0 | CC BY 4.0 | ? | no | B (community, open licence, named author) | https://universe.roboflow.com/skripsinew/tpnew |

Philippine pictures: **3,072 of 16,391 (19%)**. Everything else is foreign imagery: fine for learning what the object looks like, not proof of field accuracy.

## Known limits

- Class `tinted_window` has only 0 boxes in `val`: its score is unreliable (below 50).
- Class `side_mirror` has only 0 boxes in `val`: its score is unreliable (below 50).
- Class `tinted_window` has only 0 boxes in `test`: its score is unreliable (below 50).
- Class `side_mirror` has only 0 boxes in `test`: its score is unreliable (below 50).
- Less than a quarter of the pictures are Philippine: collect and review Zamboanga footage (`python harvest.py`).
- `menna_cabin`: enforcement-camera views through the windshield (Arabic plates). The same cars repeat across train / val / test (video frames + augmented copies): see the cleaning log. 'un seat-belt' is not mapped, absence = no seatbelt
- `govviolation_cabin`: checked by eye 2026-10-25: Egyptian enforcement cameras (Arabic plates), the same kind of picture as menna_cabin
- `tint_windows`: checked by eye 2026-10-25: the boxes are windows (not whole cars), but the pictures are general car-sale photos, many from INSIDE the car, and the set has no clear windows. A model trained on it can learn the picture style instead of the tint: do not trust the tint gate until it is tested on Zamboanga footage
- `mc_helmet_overload`: checked by eye 2026-10-25: a street camera in the Philippines, one box per motorcycle, one per mirror seen ('sidemirror') and one where a mirror is missing ('no_sidemirror'). Only the mirrors that exist are trained: the rule 'fewer than two mirrors' counts them. Pictures are 640x360 so the crops are small

## Cleaning log

Checked 16,391 pictures, kept 16,391. Moved to `datasets/_quarantine/cabin_specialist/` (not deleted): nothing. Label files fixed: 28. Pictures re-saved as upright RGB JPEG: 0.
A picture that sits in both train and val/test keeps its val/test copy; the train copy is the one quarantined.
**Before the first cleaning, 196 val and 283 test pictures had a near-identical twin in train (same scene or video frame), so scores measured on this data earlier were optimistic.**

## Rebuild

```
python scripts/fetch_datasets.py --model cabin_specialist
python data.py curate --model cabin_specialist --apply
python data.py report
```
