# Feature Plan: Dynamic Resolution Scaling & Hardware Profiling

## Overview
This plan outlines the architecture required to allow users to dynamically change the YOLO inference resolution (e.g., from 640p to 1280p) via the Flutter UI. This allows users to trade real-time speed for extreme forensic accuracy on a case-by-case basis.

## 1. The Resource Cost (The "Quadratic" Problem)
Increasing resolution does not scale linearly; it scales quadratically. 
- **640 x 640** = 409,600 pixels (8,400 grid guesses)
- **1280 x 1280** = 1,638,400 pixels (33,600 grid guesses)

**Hardware Implications:**
- **VRAM (GPU Memory):** Memory footprint increases 4x. A 1.5GB VRAM usage at 640p spikes to ~5-6GB at 1280p. Exceeding hardware limits will cause catastrophic Out-Of-Memory (OOM) crashes.
- **Compute Time:** Frame processing time increases ~4x, which can drop a live 30 FPS stream down to < 10 FPS.

## 2. Engineering Roadmap

### Phase A: Dynamic ONNX Export
Currently, `export_onnx.py` locks the model to a fixed tensor size (e.g., 640x640).
- **Task:** Modify the Ultralytics export script to include `dynamic=True`.
- **Result:** The ONNX model will accept variable input tensor shapes (e.g., `(1, 3, H, W)`).

### Phase B: Dynamic Backend Routing
Currently, `INPUT_SIZE = 640` and `SPECIALIST_INPUT_SIZE = 320` are hardcoded in `yolo_inference.py` and `pipeline.py`.
- **Task:** Remove these hardcoded constants. 
- **Task:** Update the backend to read these values dynamically from the `config_json` (for forensic) or `camera_config.json` (for live).
- **Task:** Ensure the preprocessing functions dynamically calculate `scale = min(NEW_SIZE / w, NEW_SIZE / h)`.

### Phase C: The Hardware Profiler ("Safe Mode")
To prevent users from crashing their system by maxing out the slider, we will build a benchmarking endpoint.
- **Task:** Create an API endpoint `/api/system/benchmark-resolution`.
- **Logic:** When a user sets a new resolution, the backend generates a dummy tensor of that size, runs it through the ONNX session 10 times, and measures:
  1. Average inference time (to estimate max FPS).
  2. Peak VRAM allocation.
- **UI Integration:** Before applying the setting, the Flutter dashboard displays a warning: *"Applying 1280p will drop performance to ~12 FPS and consume 4.8GB of VRAM. Proceed?"*

## 3. Use Cases
1. **Live Camera Mode:** Users keep the slider at `640` or `480` to maintain 30+ FPS across multiple camera streams.
2. **Forensic Video Mode:** Because forensic processing is offline and not latency-sensitive, users can crank the slider to `1920` (Full HD) to accurately crop tiny license plates in the distance, even if it takes the backend 1-2 seconds per frame to process.
