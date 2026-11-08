import os
import zipfile
import json
from fastapi import APIRouter, UploadFile, File, HTTPException, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel

import yolo_inference

router = APIRouter()

class SetActiveModelRequest(BaseModel):
    model_name: str

@router.get("/models")
async def get_models():
    """List all available models and the currently active one."""
    available = yolo_inference.list_available_models()
    active = yolo_inference.MODEL_PATH.name if yolo_inference.MODEL_PATH.exists() else None
    return {
        "active_model": active,
        "available_models": available
    }

@router.post("/models/active")
async def set_active_model(req: SetActiveModelRequest):
    """Switch the live AI engine to a specific model."""
    try:
        yolo_inference.set_model_path(req.model_name)
        return JSONResponse(content={"detail": f"Switched to {req.model_name} successfully."})
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))

class ActivateRequest(BaseModel):
    type: str   # vehicles | helmet | plate | cabin
    name: str   # file name inside that type's models/ folder


@router.get("/models/catalog")
async def get_model_catalog():
    """Every model grouped by job (vehicles / helmet / plate / cabin), the active one, and training scores."""
    from engine import model_catalog
    return model_catalog.catalog()


@router.post("/models/catalog/activate")
async def activate_catalog_model(req: ActivateRequest):
    """Make one model the active one for its job."""
    from engine import model_catalog
    try:
        return {"detail": model_catalog.activate(req.type, req.name)}
    except (ValueError, FileNotFoundError) as e:
        raise HTTPException(status_code=404, detail=str(e))


class HubVersionRequest(BaseModel):
    job: str    # vehicles | plate | helmet | cabin | matcher (the others cannot switch yet)
    id: str     # a version id from GET /models/hub


@router.get("/models/hub")
def get_model_hub():
    """Every job with its live model and all its versions (training runs and model files), with their numbers.
    A plain def (worker thread): it reads result files and hashes the car-matcher files."""
    from engine import model_hub
    return model_hub.hub()


@router.post("/models/hub/use")
def use_hub_version(req: HubVersionRequest):
    """Make one version the live one. A trained run that was never exported is exported to ONNX first (about half a minute)."""
    from engine import model_hub
    try:
        return {"detail": model_hub.use(req.job, req.id)}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/models/hub/check")
def check_hub_version(req: HubVersionRequest):
    """Score a finished detector run per vehicle / object type on its test photos. Runs in the background; the hub shows the result."""
    from engine import model_hub
    try:
        return {"state": model_hub.start_check(req.job, req.id)}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))


from fastapi import Form
@router.post("/upload-model", status_code=status.HTTP_201_CREATED)
async def upload_model(category: str = Form("Uncategorized"), file: UploadFile = File(...)):

    """
    Upload a new model via ZIP.
    The ZIP must contain exactly one .onnx file (the model itself).
    Optionally, it can contain a classes.txt or config.json.
    """
    if not file.filename.endswith(".zip"):
        raise HTTPException(status_code=400, detail="Only .zip files are accepted.")

    upload_path = os.path.join("models", "uploads", file.filename)
    os.makedirs(os.path.dirname(upload_path), exist_ok=True)
    
    with open(upload_path, "wb") as f:
        content = await file.read()
        f.write(content)

    try:
        with zipfile.ZipFile(upload_path, "r") as z:
            # Find the .onnx file
            onnx_files = [f for f in z.namelist() if f.endswith(".onnx")]
            if not onnx_files:
                raise HTTPException(status_code=400, detail="No .onnx file found in the zip.")
            if len(onnx_files) > 1:
                raise HTTPException(status_code=400, detail="Multiple .onnx files found. Provide exactly one.")
            
            onnx_name = onnx_files[0]
            extract_dir = os.path.abspath(os.path.join("models", category))
            os.makedirs(extract_dir, exist_ok=True)
            
            # Extract the ONNX file
            z.extract(onnx_name, path=extract_dir)
            
            # Check for classes
            classes_out_path = os.path.join(extract_dir, f"{onnx_name}.classes.txt")
            
            if "classes.txt" in z.namelist():
                # Extract and rename
                extracted = z.extract("classes.txt", path=extract_dir)
                os.replace(extracted, classes_out_path)
            elif "config.json" in z.namelist():
                # Try to parse Roboflow config.json if they uploaded that
                with z.open("config.json") as f:
                    try:
                        cfg = json.load(f)
                        # Typical roboflow config has a "classes" mapping
                        if "classes" in cfg:
                            # dict like {"0": "no_helmet"} or list
                            if isinstance(cfg["classes"], dict):
                                class_list = [cfg["classes"][str(i)] for i in range(len(cfg["classes"]))]
                            else:
                                class_list = cfg["classes"]
                            with open(classes_out_path, "w") as out:
                                out.write("\n".join(class_list))
                    except Exception:
                        pass # Ignore malformed config.json
                        
    finally:
        os.remove(upload_path)

    return JSONResponse(
        content={"detail": f"Model '{onnx_name}' uploaded successfully. It is now available in the Model Manager."},
        status_code=status.HTTP_201_CREATED
    )
