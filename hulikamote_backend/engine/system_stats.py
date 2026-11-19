"""
system_stats.py - CPU, RAM and GPU load of this machine and of the backend itself, for the Live Monitor's Performance popup.

A small thread samples once a second (started the first time someone asks, never otherwise) and keeps the last HISTORY seconds, so the
popup can draw a line. The GPU is read with pynvml (the NVIDIA library the driver ships); with no NVIDIA GPU, or no pynvml, `gpu` is None.
Reading is cheap: psutil and pynvml calls take microseconds.
"""
import threading
import time
from collections import deque

import psutil

HISTORY = 90                  # seconds of history kept
INTERVAL_S = 1.0

try:                          # the GPU part is optional
    import pynvml
    pynvml.nvmlInit()
    _GPU = pynvml.nvmlDeviceGetHandleByIndex(0)
except Exception:             # no NVIDIA GPU, no driver library
    pynvml, _GPU = None, None


def _gpu_sample() -> dict | None:
    if _GPU is None:
        return None
    try:
        rates = pynvml.nvmlDeviceGetUtilizationRates(_GPU)
        mem = pynvml.nvmlDeviceGetMemoryInfo(_GPU)
        out = {"util": rates.gpu, "mem_util": rates.memory, "vram_used_mb": round(mem.used / 2**20), "vram_total_mb": round(mem.total / 2**20)}
    except Exception:
        return None
    for key, call in (("temp_c", lambda: pynvml.nvmlDeviceGetTemperature(_GPU, pynvml.NVML_TEMPERATURE_GPU)),
                      ("power_w", lambda: round(pynvml.nvmlDeviceGetPowerUsage(_GPU) / 1000, 1)),
                      ("power_limit_w", lambda: round(pynvml.nvmlDeviceGetEnforcedPowerLimit(_GPU) / 1000)),
                      ("clock_mhz", lambda: pynvml.nvmlDeviceGetClockInfo(_GPU, pynvml.NVML_CLOCK_SM)),
                      ("clock_max_mhz", lambda: pynvml.nvmlDeviceGetMaxClockInfo(_GPU, pynvml.NVML_CLOCK_SM)),
                      ("pstate", lambda: f"P{pynvml.nvmlDeviceGetPerformanceState(_GPU)}")):
        try:
            out[key] = call()
        except Exception:     # not every card reports every value
            out[key] = None
    try:
        out["name"] = pynvml.nvmlDeviceGetName(_GPU)
        if isinstance(out["name"], bytes):
            out["name"] = out["name"].decode()
    except Exception:
        out["name"] = "GPU"
    return out


class SystemStats:
    def __init__(self):
        self._lock = threading.Lock()
        self._thread: threading.Thread | None = None
        self._proc = psutil.Process()
        self._history: deque = deque(maxlen=HISTORY)       # (cpu %, gpu %, process cores busy, vram used MB)
        self._latest: dict = {}
        self._last_ask = 0.0

    def _run(self) -> None:
        psutil.cpu_percent(None, percpu=True)
        self._proc.cpu_percent(None)
        while time.monotonic() - self._last_ask < 30.0:      # stops by itself when nobody looks for 30 s
            time.sleep(INTERVAL_S)
            try:
                self._sample()
            except Exception:
                pass
        self._thread = None

    def _sample(self) -> None:
        cores = psutil.cpu_percent(None, percpu=True)
        vm, sw = psutil.virtual_memory(), psutil.swap_memory()
        with self._proc.oneshot():
            proc_cores = self._proc.cpu_percent(None) / 100.0
            rss, threads = self._proc.memory_info().rss, self._proc.num_threads()
        gpu = _gpu_sample()
        latest = {
            "cpu": {"percent": round(sum(cores) / max(len(cores), 1), 1), "cores": [round(c) for c in cores], "count": len(cores)},
            "ram": {"percent": vm.percent, "used_gb": round((vm.total - vm.available) / 2**30, 1), "total_gb": round(vm.total / 2**30, 1)},
            "swap": {"percent": sw.percent, "used_gb": round(sw.used / 2**30, 1), "total_gb": round(sw.total / 2**30, 1)},
            "backend": {"cpu_cores": round(proc_cores, 2), "rss_gb": round(rss / 2**30, 2), "threads": threads},
            "gpu": gpu,
        }
        with self._lock:
            self._latest = latest
            self._history.append((latest["cpu"]["percent"], gpu["util"] if gpu else None, round(proc_cores, 2), gpu["vram_used_mb"] if gpu else None))

    def snapshot(self) -> dict:
        """{"now": {...}, "history": [[cpu %, gpu %, backend cores, vram MB], ...] oldest first}. Starts the sampler on first use."""
        self._last_ask = time.monotonic()
        if self._thread is None:
            self._thread = threading.Thread(target=self._run, name="system-stats", daemon=True)
            self._thread.start()
            try:
                self._sample()                               # something to show at once
            except Exception:
                pass
        with self._lock:
            return {"now": dict(self._latest), "history": [list(h) for h in self._history]}


STATS = SystemStats()
