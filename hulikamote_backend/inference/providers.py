"""
inference/providers.py
─────────────────────
Centralized ONNX Runtime execution provider resolver (Strategy Pattern).

All InferenceSession creation in this codebase goes through `make_session()`.
Providers are probed once at import time and reused — GPU-first, CPU fallback.
"""

import os
import logging
from typing import Sequence, Optional

import onnxruntime as ort

log = logging.getLogger(__name__)

# Preload CUDA DLLs (pip-installed nvidia-*-cu12 packages on Windows aren't on PATH)
try:
    ort.preload_dlls(directory="")
except Exception as e:
    log.debug("[ORT] CUDA DLL preload skipped: %s", e)

# Pin CUDA to the discrete NVIDIA GPU (device_id=0 = RTX 3050).
# Without this, Windows power-saving policy silently routes ONNX Runtime
# to the integrated Intel iGPU even when CUDAExecutionProvider is listed.
_CUDA_PROVIDER_OPTIONS = {
    "device_id": 0,
    "gpu_mem_limit": 4 * 1024 * 1024 * 1024,  # 4 GB — safe cap for RTX 3050 6 GB
    "arena_extend_strategy": "kNextPowerOfTwo",
    "cudnn_conv_algo_search": "EXHAUSTIVE",
    "do_copy_in_default_stream": True,
}

# ── Provider probe (runs once at import) ─────────────────────────────────────
def _resolve_providers() -> list:
    """Return the best available provider list, GPU-first.

    CUDAExecutionProvider is passed as a (name, options) tuple to explicitly
    pin device_id=0, preventing the Intel iGPU from being selected.
    """
    available = ort.get_available_providers()

    if "CUDAExecutionProvider" in available:
        # Set env var so any torch/CUDA code also stays on the discrete GPU
        os.environ.setdefault("CUDA_VISIBLE_DEVICES", "0")
        log.info("[ORT] Pinned to discrete GPU (CUDAExecutionProvider device_id=0 — RTX 3050)")
        return [("CUDAExecutionProvider", _CUDA_PROVIDER_OPTIONS), "CPUExecutionProvider"]

    if "CoreMLExecutionProvider" in available:
        log.info("[ORT] Apple Silicon detected — using CoreMLExecutionProvider")
        return ["CoreMLExecutionProvider", "CPUExecutionProvider"]

    log.info("[ORT] No discrete GPU — falling back to CPUExecutionProvider")
    return ["CPUExecutionProvider"]


_DEFAULT_PROVIDERS: list = _resolve_providers()
_CURRENT_PROVIDERS: list = list(_DEFAULT_PROVIDERS)


def get_providers() -> list:
    """Return the currently configured provider list (read-only copy)."""
    return list(_CURRENT_PROVIDERS)


def override_providers(providers: Sequence) -> None:
    """Dependency injection hook: override providers globally (e.g. for testing or config)."""
    global _CURRENT_PROVIDERS
    _CURRENT_PROVIDERS = list(providers)
    log.info("[ORT] Provider override active: %s", _CURRENT_PROVIDERS)


def reset_providers() -> None:
    """Reset providers back to the auto-detected system default."""
    global _CURRENT_PROVIDERS
    _CURRENT_PROVIDERS = list(_DEFAULT_PROVIDERS)
    log.info("[ORT] Providers reset to auto-detected default: %s", _CURRENT_PROVIDERS)


def make_session(
    model_path: str,
    providers: Optional[Sequence] = None,
    **session_options
) -> ort.InferenceSession:
    """
    Create an InferenceSession with GPU-first priority and automatic CPU fallback.

    Args:
        model_path: Absolute or relative path to the .onnx model file.
        providers: Optional explicit provider list. If omitted, uses global DI strategy.
        **session_options: Extra kwargs forwarded to InferenceSession.

    Returns:
        A ready-to-use ort.InferenceSession.
    """
    target_providers = list(providers) if providers is not None else list(_CURRENT_PROVIDERS)
    log.debug("[ORT] Loading %s with providers=%s", model_path, target_providers)

    try:
        return ort.InferenceSession(model_path, providers=target_providers, **session_options)
    except Exception as exc:
        # If GPU provider failed at runtime (e.g., missing CUDA driver/runtime), fall back to CPU
        if target_providers != ["CPUExecutionProvider"]:
            log.warning(
                "[ORT] Failed to initialize session with providers %s (%s). Falling back to CPUExecutionProvider.",
                target_providers,
                exc,
            )
            return ort.InferenceSession(model_path, providers=["CPUExecutionProvider"], **session_options)
        raise exc


def active_provider() -> str:
    """Return the name of the currently active (highest-priority) provider."""
    p = _CURRENT_PROVIDERS[0]
    # Handle tuple form: ("CUDAExecutionProvider", {...})
    return p[0] if isinstance(p, tuple) else p
