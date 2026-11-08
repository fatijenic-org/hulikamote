from fastapi import APIRouter, Query
from pydantic import BaseModel, Field
from store import get_violations, add_violation

router = APIRouter(prefix="/violations", tags=["violations"])


class ViolationCreate(BaseModel):
    user_id: str
    cls: str = Field(..., description="Violation class name")
    confidence: float = Field(..., ge=0.0, le=1.0)
    image_path: str = ""


class ViolationStatusUpdate(BaseModel):
    status: str = Field(..., description="New status (e.g., approved, rejected)")



@router.get("/sessions")
async def list_sessions():
    """Groups pending violations by source and session_id (max 25 per source)."""
    from store import db
    import sqlalchemy
    
    grouped = {
        "live": {},
        "forensic": {},
        "video_analysis": {}
    }
    
    for src in grouped.keys():
        query = (
            db.violations_table.select()
            .add_columns(db.users_table.c.name.label("user_name"))
            .select_from(
                db.violations_table.outerjoin(
                    db.users_table, db.violations_table.c.user_id == db.users_table.c.id
                )
            )
            .where(sqlalchemy.and_(
                db.violations_table.c.status == "pending",
                db.violations_table.c.source == src
            ))
            .order_by(db.violations_table.c.timestamp.desc())
        )
        
        rows = await db.database.fetch_all(query)
        
        for r in rows:
            d = dict(r)
            
            # --- Injects Missing Forensic Metadata (crop_results) ---
            if src == "forensic":
                import os
                import json
                sess_id = d.get("session_id", "default")
                from engine.pipeline import EVIDENCE_DIR
                rep_path = EVIDENCE_DIR / 'forensic' / sess_id / 'output' / 'report.json'
                if rep_path.exists():
                    try:
                        with open(rep_path, "r") as r_file:
                            rep_data = json.load(r_file)
                            for t_json in rep_data:
                                if t_json.get("track_id", -1) == d.get("track_id", -1) and d.get("cls") in t_json.get("violations", []):
                                    if "crop_results" in t_json:
                                        import json
                                        d["crop_results_json"] = json.dumps(t_json["crop_results"])
                                        break
                    except Exception as e:
                        pass
            
            if d.get("plate_text") and d.get("plate_text") not in ("unidentified", ""):
                d["user_name"] = d["plate_text"]
            elif d.get("user_id") == "scanning":
                d["user_name"] = "SCANNING..."
            elif d.get("user_id") == "no_plate_found":
                d["user_name"] = "NO PLATE FOUND"
            elif str(d.get("user_id", "")).startswith("RAW:"):
                d["user_name"] = str(d.get("user_id", "")).replace("RAW:", "")
            elif not d.get("user_name") and d.get("user_id") != "unregistered":
                d["user_name"] = "UNIDENTIFIED"
                
            sess_id = d.get("session_id", "default")
            if sess_id not in grouped[src]:
                grouped[src][sess_id] = []
            grouped[src][sess_id].append(d)
            
    return grouped


@router.get("")
async def list_violations(
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    user_id: str | None = Query(None, description="Filter by user ID"),
    status: str | None = Query(None, description="Filter by status (pending, approved, rejected)"),
    track_id: int | None = Query(None, description="Filter by tracker-assigned vehicle ID"),
):
    from store import get_violations, update_violation_user, get_user_by_license
    import json
    import os
    import cv2
    import asyncio
    
    results = await get_violations(page, size, user_id, status, track_id)

    return results
    
async def run_plate_extraction(violation_id: str) -> dict:
    from store import db, update_violation_user, get_user_by_plate
    import json
    import os
    import cv2
    import asyncio
    from yolo_inference import _extract_plate_text
    
    query = db.violations_table.select().where(db.violations_table.c.id == violation_id)
    row = await db.database.fetch_one(query)
    if not row:
        return {"user_id": "not_found", "user_name": "TICKET NOT FOUND"}
        
    item = dict(row)
    if not item.get("evidence_paths") or item.get("evidence_paths") == "[]":
        await update_violation_user(violation_id, "no_evidence")
        return {"user_id": "no_evidence", "user_name": "NO EVIDENCE FRAMES"}
        
    paths = item["evidence_paths"]
    if isinstance(paths, str):
        try:
            paths = json.loads(paths)
        except:
            paths = []
            
    if not paths:
        await update_violation_user(violation_id, "no_evidence")
        return {"user_id": "no_evidence", "user_name": "NO EVIDENCE FRAMES"}
        
    def _scan_frames():
        from yolo_inference import get_inference, _extract_plate_text
        from engine import specialists
        import onnxruntime as ort
        
        yolo = get_inference()
        
        # Load the dedicated plate specialist YOLO model (Two-stage approach)
        plate_model_path = os.path.join(os.path.dirname(__file__), "..", "models", "plate_specialist.onnx")
        plate_session = None
        if os.path.exists(plate_model_path):
            plate_session = ort.InferenceSession(plate_model_path, providers=['CPUExecutionProvider'])
            
        step = max(1, len(paths) // 3)
        for path in paths[::step][:3]:
            abs_path = os.path.join(os.path.dirname(__file__), "..", path)
            if not os.path.exists(abs_path): continue
            frame = cv2.imread(abs_path)
            if frame is None: continue
            
            detections = yolo.infer(frame)
            
            for det in detections:
                x, y, w, h = det.bbox
                if w < 30 or h < 30:
                    continue
                
                # Bumper crop
                plate_y = y + int(h * 0.6)
                plate_h = h - int(h * 0.6)
                
                fh, fw = frame.shape[:2]
                py1 = max(0, plate_y)
                py2 = min(fh, plate_y + plate_h)
                px1 = max(0, x)
                px2 = min(fw, x + w)
                
                if py2 <= py1 or px2 <= px1:
                    continue
                    
                bumper_crop = frame[py1:py2, px1:px2]
                if bumper_crop.size == 0:
                    continue
                
                # TWO-STAGE PIPELINE: Use Plate Specialist YOLO to find the exact plate boundary
                final_crop = bumper_crop
                if plate_session is not None:
                    # Search the WHOLE vehicle (the model was trained on whole-vehicle crops), then crop tight to the plate
                    vehicle_crop = frame[max(0, y):min(fh, y + h), px1:px2]
                    plates = [d for d in specialists.detect(plate_session, vehicle_crop)
                              if d["class_id"] == specialists.IDX_LICENSE_PLATE]
                    if plates:
                        lx, ly, lw, lh = plates[0]["box"]
                        tight = vehicle_crop[ly:ly + lh, lx:lx + lw]
                        if tight.size:
                            final_crop = tight
                
                text = _extract_plate_text(final_crop)
                if text not in ("unidentified", "OCR_NOT_INSTALLED"):
                    return text
                    
        return "unidentified"
        
    best_plate = await asyncio.get_event_loop().run_in_executor(None, _scan_frames)
    
    if best_plate != "unidentified":
        resolved = await get_user_by_plate(best_plate)
        if resolved:
            await update_violation_user(violation_id, resolved["id"])
            return {"user_id": resolved["id"], "user_name": resolved["name"]}
        else:
            await update_violation_user(violation_id, "unregistered")
            return {"user_id": "unregistered", "user_name": best_plate}
    else:
        await update_violation_user(violation_id, "no_plate_found")
        return {"user_id": "no_plate_found", "user_name": "NO PLATE DETECTED"}


@router.post("/{violation_id}/extract-plate")
async def extract_plate(violation_id: str):
    from fastapi import HTTPException
    result = await run_plate_extraction(violation_id)
    if result["user_id"] == "not_found":
        raise HTTPException(status_code=404, detail="Violation not found")
    return result


@router.post("", status_code=201)
async def create_violation(body: ViolationCreate):
    from store import add_violation
    return await add_violation(body.cls, body.confidence, body.user_id, body.image_path)


@router.patch("/{violation_id}")
async def update_violation(violation_id: str, body: ViolationStatusUpdate):
    from store import update_violation_status
    from fastapi import HTTPException
    
    updated = await update_violation_status(violation_id, body.status)
    if not updated:
        raise HTTPException(status_code=404, detail="Violation not found")
    return updated
