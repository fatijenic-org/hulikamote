# Dataset catalog

Generated 2026-11-09 by `python data.py report`.

One standard layout everywhere (`images/<split>`, `labels/<split>`, `data.yaml`). Per-model details are in `datasets/<model>/DATASET_CARD.md`; sources and licences in `configs/datasets_manifest.yaml`.

| dataset | train | val | test | classes | Philippine share | sources |
|---|---|---|---|---|---|---|
| primary_anchor | 28,445 | 1,587 | 822 | 7 | 33% (+67% mixed) | ph_plate_vehicle, ph_traffic_detection, ph_vehicle_classification, ph_vehicles, ph_vehicles_selfdev |
| helmet_specialist | 10,589 | 923 | 697 | 2 | 7% | edgevision_helmet, flashys_helmet, martinez_helmet, naratip_helmet |
| plate_specialist | 12,968 | 1,790 | 1,003 | 1 | 0% | colorum_plates, govviolation_plates, indonesia_plates, legacy, my_plates, oi_plates, ph_plates, tr_plates250 |
| cabin_specialist | 15,685 | 300 | 402 | 5 | 19% | govviolation_cabin, mc_helmet_overload, menna_cabin, tint_windows, tpnew_seatbelt |
| plate_ocr | 296 pictures in total | | | plate crops + text | | |
| reid | 15,272 pictures in total | | | own review decisions (real Zamboanga cars) | | |
| reid_public | 3,900 pictures in total | | | public vehicle identities (synthetic pre-training) | | |
| sr_plates | 3,578 pictures in total | | | sharp plate crops for the enhancer | | |

## Waiting for your action

- **ph_vehicle_classification**: The 2026-10-25 download was cut off (1.6 GB roboflow.zip that is not a complete zip). In your own terminal, with ROBOFLOW_API_KEY set: python scripts/fetch_datasets.py --only ph_vehicle_classification   (then python data.py curate --apply and python data.py report).
- **mapua_helmet**: Downloaded and checked, held back (merge: false): whole 640x640 frames of one Manila street camera with ~15 x 26 px heads. Turn it on after cutting rider crops with the vehicle detector.
- **rodosol_alpr**: 20,000 plate photos with text, 5,000 are motorcycles (Brazilian LLL-NNNN plates, same shape as PH plates). Academic licence: e-mail the signed form from a university address to the authors, link arrives in 1-5 days. https://github.com/raysonlaroca/rodosol-alpr-dataset
- **ufpr_alpr**: 4,500 frames with plate text, cars and motorcycles. Same request process. https://web.inf.ufpr.br/vri/databases/ufpr-alpr/
- **veri_776**: Real multi-camera vehicle ReID (776 cars). Request form on the authors' page; non-commercial research.
- **ufpr_sr_plates**: 100,000 paired low / high resolution plate photos for the enhancer. Project page: valfride.github.io/nascimento2025toward (check the licence there).
- **seatbelt_phone_kaggle**: Kaggle sets need a Kaggle token (kaggle.json); State Farm Distracted Driver is competition data with its own rules, check them before use.
- **side_mirror**: FIRST DATA FOUND 2026-10-25: mc_helmet_overload (a Philippine street camera, about 3,100 small motorcycle crops, train only, merged under cabin_specialist). Pictures are 640x360, so each crop is only about 40 x 90 px: harvest crops from our own footage (harvest tool) to get a sharp validation set. Other Roboflow projects (mximos-workspace/side-mirror, mohammed-hoodh-valiyaveedu-paramba-ghqjk/side-mirror-bounding-box) were never checked for motorcycles.
- **window_tint_seg**: slzz-hwlpm/car-window-tint-jw8l0 (4,589 imgs, Public Domain, segmentation, class 'window'): check what 'window' means before mapping to tinted_window. A clear-window set from the same kind of pictures is what tint_windows lacks.
- **ph_plate_t1lqw**: colorumscan/philiipine_license_plate-t1lqw (480 imgs, CC BY 4.0) has classes '0' and 'n': look at them before mapping to license_plate. (colorum_plates, from the same workspace, turned out to be Indian / UK / US plates, so check by eye first.)
- **ridesafe_400**: Dashcam clips of riders with helmet / no-helmet / plate / triple riding (arXiv 2503.00428, IIIT Hyderabad). The page says 'Coming Soon': nothing to download yet. Watch https://dash-cop.github.io/ or ask the authors.
- **not_used**: Excluded on purpose: DeBoniz/helmet-detection-dataset (18k images, origin not stated), dataph Cebu CCTV (30 GB, no licence, shows people), mabo7237/license-plates-700k and sonnetechnology OCR (labels made by a model), seatbelt sets on Hugging Face (whole-photo classification, no boxes), Medellin motorcyclists (riders are not labelled as persons).
