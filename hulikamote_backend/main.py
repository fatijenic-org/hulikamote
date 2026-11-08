from contextlib import asynccontextmanager
from pathlib import Path
import logging
import os
import sys

# Force discrete NVIDIA GPU (RTX 3050 = device 0).
# Must be set before any CUDA/ONNX import so Windows does not silently route
# inference to the integrated Intel iGPU under its power-saving policy.
os.environ.setdefault("CUDA_VISIBLE_DEVICES", "0")

# IMPORTANT: Import torch BEFORE any onnxruntime/inference modules 
# to prevent WinError 127 DLL conflicts with nvidia-cudnn-cu12.
try:
    import torch
except ImportError:
    pass

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from database import database, create_tables, run_migrations
from store import seed_users, seed_registry
from routers import stream, model, violations, notifications, auth, settings, forensic, training, feedback, demerit, registry, notify, mailbox, appeals, trimmer, dev

SNAPSHOTS_DIR = Path(__file__).parent / "snapshots"
SNAPSHOTS_DIR.mkdir(exist_ok=True)


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_tables()
    run_migrations()      # Safely add new columns to existing tables
    await database.connect()
    await seed_users()     # Seed 3 mock users only — no violation seed
    await seed_registry()  # ... and a made-up plate each, so the demo works out of the box
    yield
    await database.disconnect()


app = FastAPI(
    title="HULI-KAMOTE AI Backend",
    description="Inference server for traffic violation detection",
    version="0.2.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(stream.router)
app.include_router(model.router)
app.include_router(violations.router)
app.include_router(notifications.router)
app.include_router(settings.router)
app.include_router(forensic.router)
app.include_router(training.router)
app.include_router(feedback.router)
app.include_router(demerit.router)
app.include_router(registry.router)
app.include_router(notify.router)
app.include_router(mailbox.router)
app.include_router(appeals.router)
app.include_router(trimmer.router)
app.include_router(dev.router)      # temporary developer tools (HK_DEV=1 only)

# The dashboard's Benchmark tab. The scoring tool lives in tools/benchmark at the repo root; the backend must still
# start without it, so a failure to load it is logged, not fatal.
try:
    sys.path.append(str(Path(__file__).resolve().parent.parent))
    from tools.benchmark.api import router as benchmark_router
    app.include_router(benchmark_router)
except Exception as exc:
    logging.getLogger("uvicorn.error").warning("Benchmark service not loaded: %s", exc)

# Serve violation snapshot images at /snapshots/<filename>
app.mount("/snapshots", StaticFiles(directory=str(SNAPSHOTS_DIR)), name="snapshots")


@app.get("/")
def read_root():
    return {"message": "HULI-KAMOTE Backend Online"}


@app.get("/status")
def get_status():
    return {"status": "ok", "mode": "mock", "version": "0.2.0"}
