# HULI-KAMOTE Training Lab

This directory contains everything needed to train, validate, and export the specialist ONNX models used by the Decoupled Cascading Pipeline.

## Train from a plain menu

```
hulikamote_backend/venv/Scripts/python.exe training_lab/lab.py
```

Numbered choices, one step at a time, the screen is cleared at every step: pick a model, see its pictures and past runs,
start a training (test run / quick / balanced / thorough), watch it live, stop or resume it, export or deploy the result,
and run the data tools (report, clean). The training runs in its own background process, so closing the window, the dashboard
or a backend restart never stops it. `lab_tui.py` is the full-screen version of the same thing (both share `lab_core.py`).

## Architecture Recap

The system uses **4 models**, each trained independently and loaded only when needed:

| Model | File | Detects | Used For |
|-------|------|---------|----------|
| `primary_anchor` | `yolov8n.onnx` | motorcycle, car, bus, truck | Runs every frame |
| `helmet_specialist` | `helmet_specialist.onnx` | rider_with_helmet, rider_without_helmet | Motorcycle crops only |
| `plate_specialist` | `plate_specialist.onnx` | license_plate | All vehicle crops |
| `cabin_specialist` | `cabin_specialist.onnx` | clear_window, tinted_window, seatbelt, driver_phone, side_mirror | Car crops only |

## Directory Structure

```
training_lab/
├── datasets/
│   ├── primary_anchor/         # Usually use pretrained COCO weights, skip training
│   │   ├── images/train/       # Raw frames (jpg/png)
│   │   ├── images/val/
│   │   ├── labels/train/       # YOLO .txt annotations
│   │   ├── labels/val/
│   │   └── data.yaml
│   ├── helmet_specialist/
│   │   ├── images/train/
│   │   ├── images/val/
│   │   ├── labels/train/
│   │   ├── labels/val/
│   │   └── data.yaml
│   ├── plate_specialist/
│   │   └── ...
│   └── cabin_specialist/
│       └── ...
├── scripts/
│   ├── train.py                # Run YOLOv8 training for any specialist
│   ├── export_onnx.py          # Convert best.pt → .onnx → deploy to backend
│   ├── validate.py             # Run mAP validation on a trained model
│   ├── split_dataset.py        # Auto-split raw images into train/val sets
│   └── augment.py              # Albumentations-based offline augmentation
└── configs/
    └── training_config.yaml    # Master config (epochs, imgsz, batch, etc.)
```

## Quickstart

### 1. Set up the environment
```bash
cd training_lab
pip install ultralytics albumentations scikit-learn opencv-python
```

### 2. Collect and annotate data
- Use **Roboflow** or **CVAT** to annotate raw footage
- Export in **YOLOv8 format** directly into the correct `datasets/<model>/` folder

### 3. Split your dataset
```bash
python scripts/split_dataset.py --model helmet_specialist --ratio 0.8
```

### 4. (Optional) Augment for small datasets
```bash
python scripts/augment.py --model helmet_specialist --count 500
```

### 5. Train
```bash
python scripts/train.py --model helmet_specialist
# or override config:
python scripts/train.py --model helmet_specialist --epochs 100 --imgsz 320
```

### 6. Validate
```bash
python scripts/validate.py --model helmet_specialist
```

### 7. Export to ONNX and deploy
```bash
python scripts/export_onnx.py --model helmet_specialist
# Automatically copies the .onnx to hulikamote_backend/models/
```

## Datasets: fetch, look, clean, document

Every dataset uses ONE layout: `datasets/<model>/images/{train,val,test}` + `labels/{train,val,test}` + `data.yaml`
(plate text: `datasets/plate_ocr`, public vehicle identities: `datasets/reid_public`, your reviewed cars: `datasets/reid`).
What is in each one, where it came from, its licence and its known gaps: **`datasets/CATALOG.md`** and each
`datasets/<model>/DATASET_CARD.md` (generated; sources are listed in `configs/datasets_manifest.yaml`).

```bash
python scripts/fetch_datasets.py                    # download + merge every source in the manifest (Roboflow ones need a key)
python scripts/fetch_datasets.py --only oi_plates --stage-only   # download one source, merge nothing
python data.py sheet --staged oi_plates             # picture grid with the boxes drawn: LOOK before you trust a source
python data.py curate                               # dry run: what the cleaner would fix / move (nothing changes)
python data.py curate --apply                       # clean: bad pictures and train copies of val/test photos -> datasets/_quarantine/
python data.py report                               # rewrite the dataset cards and the catalog
python data.py sr-build                             # sharp plate crops for the enhancer (datasets/sr_plates/clean)
```

- **Roboflow sets** need your own free key: set `ROBOFLOW_API_KEY` (PowerShell: `$env:ROBOFLOW_API_KEY="<key>"`), then run
  `fetch_datasets.py`. Without it those entries are skipped; nothing else breaks. The tools have their own environment:
  `C:\Users\<you>\.dataset_env\Scripts\python.exe` (requests, pillow, opencv, roboflow, remotezip).
- **Never curate a model while it is training.** Nothing is deleted: moved files can be restored from `datasets/_quarantine/`.
- Your own `harvest__*` pictures are never changed by the cleaner. Tests: `python -m pytest training_lab/tests -q`.

## Annotation Guidelines

### helmet_specialist classes
| Class | Label | Description |
|-------|-------|-------------|
| `rider_with_helmet` | 0 | Rider whose head is covered by a helmet in the top 20% of their box |
| `rider_without_helmet` | 1 | Rider with no helmet, or helmet held on lap |

> **Key Rule:** Use **composite classes** — annotate the whole rider, not just the helmet. This avoids the "helmet on lap" false negative.

### plate_specialist classes
| Class | Label | Description |
|-------|-------|-------------|
| `license_plate` | 0 | Any visible license plate (front or rear) |

### cabin_specialist classes
| Class | Label | Description |
|-------|-------|-------------|
| `clear_window` | 0 | Untinted, visible windshield |
| `tinted_window` | 1 | Tinted windshield (triggers seatbelt/phone check skip) |
| `seatbelt` | 2 | Seatbelt strap crossing the driver's torso |
| `driver_phone` | 3 | Phone held near driver's head or hands |
| `side_mirror` | 4 | Visible side mirror on the motorcycle frame |

## Target mAP Benchmarks (before deployment)
| Model | Min mAP@0.5 | Notes |
|-------|-------------|-------|
| helmet_specialist | 0.85 | Critical — false negatives issue tickets |
| plate_specialist | 0.90 | Feeds EasyOCR; must be tight crops |
| cabin_specialist | 0.80 | tinted_window gate must be reliable |
