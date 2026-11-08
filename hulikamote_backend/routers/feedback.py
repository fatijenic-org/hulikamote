from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import base64
from pathlib import Path
import time
import os

router = APIRouter(prefix="/api/feedback", tags=["Pop Quiz Ledger"])

# Locate the training lab datasets directory
BACKEND_DIR = Path(__file__).parent.parent
TRAINING_LAB_DIR = BACKEND_DIR.parent / "training_lab"
DATASET_DIR = TRAINING_LAB_DIR / "datasets" / "plate_ocr"

# Ensure the yolo dataset structure exists
IMAGES_DIR = DATASET_DIR / "images" / "train"
LABELS_DIR = DATASET_DIR / "labels" / "train"

IMAGES_DIR.mkdir(parents=True, exist_ok=True)
LABELS_DIR.mkdir(parents=True, exist_ok=True)

class PopQuizCorrection(BaseModel):
    image_base64: str
    corrected_label: str
    class_id: int = 0  # Default to class 0 (e.g. 'plate')

@router.post("/pop-quiz")
async def submit_pop_quiz_correction(req: PopQuizCorrection):
    """
    Receives a corrected image and label from the Pop Quiz UI,
    and directly saves it into the YOLO training dataset.
    """
    try:
        # Generate a unique timestamp ID for this specific image
        timestamp = int(time.time() * 1000)
        
        # Sanitize the corrected label for filesystem safety
        import re
        safe_label = re.sub(r'[^A-Za-z0-9]', '', req.corrected_label).upper()
        
        if safe_label:
            filename_base = f"{safe_label}_{timestamp}"
        else:
            filename_base = f"background_{timestamp}"

        
        # 1. Decode and save the image
        img_data = base64.b64decode(req.image_base64)
        image_path = IMAGES_DIR / f"{filename_base}.jpg"
        with open(image_path, "wb") as f:
            f.write(img_data)
            
        # 2. Save the corrected YOLO format label
        # (Assuming the corrected_label is passed as standard YOLO bbox format
        #  or just the raw text if you are training OCR in the future)
        label_path = LABELS_DIR / f"{filename_base}.txt"
        with open(label_path, "w", encoding="utf-8") as f:
            f.write(f"{req.class_id} {req.corrected_label}\n")
            
        return {
            "status": "success", 
            "message": "Correction routed successfully to the Training Lab!",
            "image_saved": str(image_path.name),
            "label_saved": str(label_path.name)
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save correction: {str(e)}")

@router.get("/stats")
async def get_feedback_stats():
    """Returns the total number of accumulated images in the feedback loop vault."""
    try:
        count = len(list(IMAGES_DIR.glob("*.jpg")))
        return {"accumulated_images": count}
    except Exception:
        return {"accumulated_images": 0}
