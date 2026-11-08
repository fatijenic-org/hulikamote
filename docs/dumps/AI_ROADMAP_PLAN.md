# HULI-KAMOTE: STRATEGIC AI ROADMAP & HANDOFF
================================================

This document serves as the high-level roadmap and architectural guideline for the next phases of development for the HULI-KAMOTE traffic apprehension system. 

## CURRENT SYSTEM STATE (As of Session 013)
- **Object Tracking**: DeepSORT (Config is STRICTLY LOCKED. Do not modify hyperparameter matrices in `tracker.py`. To improve tracking, replace the ReID embedding model instead).
- **Spatial Awareness**: The AI uses the bottom-center of the bounding box (`cy = y + h`) to track vehicles, perfectly anchoring them to the 2D pavement polygons drawn in the UI.
- **Evidence Capturing**: Throttled in `pipeline.py`, but guaranteed to capture a snapshot on Frame 1 of the violation to prevent empty `evidence_paths` due to race conditions.
- **MLOps Feedback Loop**: The Forensic Analyzer UI allows operators to manually review tickets. Clicking "True Positive", "False Positive", or "Corrected" immediately syncs the exact evidence crop (`image_raw` or `image_sr`) to the SQLite Database/Vault for future retraining.

---

## FUTURE PHASES & EXECUTION STRATEGY

### PHASE 1: Active Learning (Data Harvesting)
*Do not immediately run heavy GPU training scripts.*
1. Instruct the user to run standard video footage through the Forensic Analyzer.
2. The user will use the newly built inline feedback buttons to classify at least 500-1000 edge cases (night time, blur, obscured plates).
3. We must collect both **True Positives** (to reinforce edge-case confidence) and **False Positives** (for Hard Negative Mining, e.g., teaching the AI that a bumper is not a plate).

### PHASE 2: Train the YOLO Plate Specialist & OCR
1. Execute `train.py --model plate_specialist` on the collected YOLO dataset.
2. Execute `train_ocr.py` on the Corrected/True Positive plate crops to tune the engine to local LTO-issued font spacing and thickness.

### PHASE 3: Virtual Traffic Light Simulator (For Red Light Violations)
*Constraint: We lack free footage of actual intersections with visible traffic lights.*
1. Do not build an AI model to detect traffic light colors yet.
2. Instead, build a **Virtual Traffic Light Controller Widget** directly into the Dashboard UI.
3. This widget will simulate a traffic light cycle (or allow manual toggling). When the simulated state is "Red", the backend will instantly flag any vehicle entering the intersection ROI. This allows us to test the logical pipeline on normal highway footage.

### PHASE 4: Train Visual Attribute Specialists (Helmet / Phone)
1. Do not collect this data manually.
2. Bootstrap the training using massive open-source datasets from Kaggle or Roboflow Universe containing pre-labeled motorcycles and helmets.
3. Train a specific "Rider Specialist" YOLO model to crop riders and detect the `helmet` class.

### PHASE 5: Mobile App API Integration
1. The user already has a Flutter Mobile App for citizens.
2. Do not build a new web portal. 
3. Build secure REST API endpoints in the FastAPI backend (e.g., `GET /api/citizen/tickets/{plate_number}`) so the existing mobile app can seamlessly query the SQLite database and display the JSON ticket and photographic evidence to the violator.
