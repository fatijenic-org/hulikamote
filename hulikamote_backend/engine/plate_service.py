"""
plate_service.py - the live backend's door to the plate reading PROCESS (engine/plate_worker.py).

Plate reading (finding the plate in the evidence photos, the OCR, the GAN) is heavy and mostly Python. Run inside the backend, it
shared the live feed's interpreter lock, CPU threads and GPU, and the live picture stuttered. So it runs in a process of its own:

  - started on the first job (never at start-up), with a small number of CPU threads. It runs in Windows' background mode (lowest CPU,
    disk and memory priority, and below-normal GPU scheduling priority): the live feed always goes first;
  - it uses the GPU (HK_PLATE_GPU=1, default): the GAN and the OCR run there, with a memory cap, so the CPU stays free for the feed.
    HK_PLATE_GPU=0 reads on the CPU only; HK_PLATE_GPU=auto uses the GPU only while the live feed is NOT running;
  - jobs go one at a time (the review's own "Read the plate" jumps ahead of the live queue's background reads);
  - it stops by itself after HK_PLATE_IDLE_S seconds without work (default 900; frees its memory) and starts again on the next job;
  - if it dies or hangs, the job fails with PlateServiceError and the next job starts a fresh one.

HK_PLATE_PROCESS=0 runs the reading inside the backend again (the old way; for a machine where a second process is not possible).
Other switches: HK_PLATE_THREADS (default 3), HK_PLATE_JOB_TIMEOUT_S (default 900), HK_PLATE_GPU_MEM_MB (GPU memory cap, default 768),
HK_PLATE_BACKGROUND=0 (no background mode).
"""
import atexit
import base64
import json
import logging
import os
import queue
import subprocess
import sys
import threading
import time
from pathlib import Path

import cv2
import numpy as np

log = logging.getLogger(__name__)

BACKEND_DIR = Path(__file__).resolve().parent.parent
LOG_PATH = BACKEND_DIR / "plate_worker.log"
EVIDENCE_DIR = BACKEND_DIR / "snapshots" / "evidence"


class PlateServiceError(RuntimeError):
    """The plate process failed on a job (it crashed, hung, or the reading raised)."""


class PlateServiceDown(PlateServiceError):
    """The plate process could not be started at all (the job was not tried)."""


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


class PlateService:
    def __init__(self) -> None:
        self.live_probe = lambda: False                  # set by routers/stream.py: True while the live feed runs
        self._lock = threading.Lock()                    # one job at a time
        self._state = threading.Lock()                   # guards the fields below
        self._proc: subprocess.Popen | None = None
        self._answers: "queue.Queue | None" = None
        self._gpu = False                                # the running process's mode
        self._next_id = 0
        self._interactive = 0                            # review jobs waiting for their turn
        self._busy_since: float | None = None
        self._last_used = time.time()
        self._watchdog: threading.Thread | None = None
        self.jobs_done = 0
        self.failures = 0
        self.last_job_s: float | None = None

    # ── settings ──────────────────────────────────────────────────────────────

    @staticmethod
    def own_process() -> bool:
        return os.environ.get("HK_PLATE_PROCESS", "1") != "0"

    def _want_gpu(self) -> bool:
        mode = os.environ.get("HK_PLATE_GPU", "1").strip().lower()
        if mode in ("0", "false", "no", "cpu"):
            return False
        if mode == "auto":
            try:
                return not self.live_probe()
            except Exception:
                return False
        return True

    # ── the process ───────────────────────────────────────────────────────────

    def _spawn(self, gpu: bool) -> None:
        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"
        env["HK_PLATE_THREADS"] = str(max(1, _env_int("HK_PLATE_THREADS", 3)))
        env["HK_OCR_GPU"] = "1" if gpu else "0"
        if gpu:
            env["HK_ORT_GPU_MEM_MB"] = str(_env_int("HK_PLATE_GPU_MEM_MB", 768))
        else:
            env["CUDA_VISIBLE_DEVICES"] = "-1"            # the CPU worker cannot touch the GPU at all
        flags = 0
        if os.name == "nt":
            flags = subprocess.BELOW_NORMAL_PRIORITY_CLASS | subprocess.CREATE_NO_WINDOW
        try:
            log_file = open(LOG_PATH, "ab")
            proc = subprocess.Popen(
                [sys.executable, "-u", "-m", "engine.plate_worker"], cwd=str(BACKEND_DIR), env=env,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log_file, creationflags=flags,
                preexec_fn=(lambda: os.nice(10)) if os.name != "nt" else None)
        except Exception as e:
            raise PlateServiceDown(f"The plate process could not be started: {e}") from e
        finally:
            try:
                log_file.close()                          # the child keeps its own handle
            except Exception:
                pass
        answers: queue.Queue = queue.Queue()
        threading.Thread(target=self._read_answers, args=(proc, answers), daemon=True, name="plate-answers").start()
        try:
            first = answers.get(timeout=120)
        except queue.Empty:
            self._kill(proc)
            raise PlateServiceDown("The plate process did not start in time") from None
        if not first or not first.get("ready"):
            self._kill(proc)
            raise PlateServiceDown("The plate process stopped while it started (see plate_worker.log)")
        self._proc, self._answers, self._gpu = proc, answers, gpu
        self._last_used = time.time()                     # the quiet spell is counted from now, not from the last job of an older process
        log.info("[Plate] worker process %s started (%s)", proc.pid, "GPU" if gpu else "CPU")
        self._start_watchdog()

    @staticmethod
    def _read_answers(proc: subprocess.Popen, answers: "queue.Queue") -> None:
        try:
            for line in iter(proc.stdout.readline, b""):
                try:
                    answers.put(json.loads(line))
                except ValueError:
                    continue
        except Exception:
            pass
        answers.put(None)                                 # the process ended

    @staticmethod
    def _kill(proc: subprocess.Popen | None) -> None:
        if proc is None:
            return
        try:
            proc.kill()
        except Exception:
            pass
        try:
            proc.wait(timeout=5)
        except Exception:
            pass

    def _stop_process(self) -> None:
        with self._state:
            proc, self._proc, self._answers = self._proc, None, None
        if proc is None:
            return
        try:
            proc.stdin.close()                            # it leaves by itself when its stdin closes
            proc.wait(timeout=3)
        except Exception:
            self._kill(proc)

    def stop(self) -> None:
        """Stop the plate process (backend shutdown). A job that waits for it fails."""
        self._stop_process()

    def _alive(self) -> bool:
        return self._proc is not None and self._proc.poll() is None

    def _start_watchdog(self) -> None:
        if self._watchdog is not None and self._watchdog.is_alive():
            return
        self._watchdog = threading.Thread(target=self._watch, daemon=True, name="plate-watchdog")
        self._watchdog.start()

    def _watch(self) -> None:
        """Between jobs: end the process after a quiet spell (its memory is freed) and when it holds the GPU while the live feed runs."""
        idle_s = _env_int("HK_PLATE_IDLE_S", 900)
        while True:
            time.sleep(3)
            if not self._alive():
                continue
            if not self._lock.acquire(blocking=False):
                continue                                   # a job is running
            try:
                if not self._alive():
                    continue
                quiet = time.time() - self._last_used > idle_s
                holds_gpu = self._gpu and not self._want_gpu()                 # the live feed started while it holds the GPU
                if quiet or holds_gpu:
                    log.info("[Plate] worker process ended (%s)", "quiet" if quiet else "the live feed needs the GPU")
                    self._stop_process()
            finally:
                self._lock.release()

    # ── jobs ──────────────────────────────────────────────────────────────────

    _background = threading.local()

    @classmethod
    def run_in_background(cls, fn, *args):
        """Call fn(*args) as a background job: its plate reads wait for the review's own ones (live queue worker)."""
        cls._background.flag = True
        try:
            return fn(*args)
        finally:
            cls._background.flag = False

    def _call(self, payload: dict, timeout: float | None = None) -> dict:
        background = getattr(self._background, "flag", False)
        if not background:
            with self._state:
                self._interactive += 1
        else:
            while self._interactive:
                time.sleep(0.25)                           # the reviewer asked for something: they go first
        with self._lock:
            if not background:
                with self._state:
                    self._interactive -= 1
            want = self._want_gpu()
            if self._alive() and self._gpu != want:
                self._stop_process()                       # the live feed started or stopped: the other mode
            if not self._alive():
                self._stop_process()
                self._spawn(want)
            with self._state:
                self._next_id += 1
                request_id = self._next_id
                proc, answers = self._proc, self._answers
            self._busy_since = time.time()
            started = self._busy_since
            limit = timeout or _env_int("HK_PLATE_JOB_TIMEOUT_S", 900)
            try:
                proc.stdin.write((json.dumps({**payload, "id": request_id}) + "\n").encode("utf-8"))
                proc.stdin.flush()
                while True:
                    try:
                        answer = answers.get(timeout=limit)
                    except queue.Empty:
                        self._stop_process()
                        self._kill(proc)
                        self.failures += 1
                        raise PlateServiceError("The plate process took too long and was stopped") from None
                    if answer is None:
                        self._stop_process()
                        self.failures += 1
                        raise PlateServiceError("The plate process stopped while it was reading (see plate_worker.log)")
                    if answer.get("id") == request_id:
                        break
            except (BrokenPipeError, OSError) as e:
                self._stop_process()
                self.failures += 1
                raise PlateServiceError(f"The plate process is not answering: {e}") from e
            finally:
                self._busy_since = None
                self._last_used = time.time()
            self.last_job_s = round(time.time() - started, 2)
            if not answer.get("ok"):
                if answer.get("kind") == "ValueError":
                    raise ValueError(answer.get("error") or "")
                self.failures += 1
                raise PlateServiceError(f"{answer.get('kind')}: {answer.get('error')}")
            self.jobs_done += 1
            return answer

    # ── what the backend calls ────────────────────────────────────────────────

    def reread(self, ticket: dict, frames: list, config: dict, plate_format: str, written: list | None = None):
        """Read a ticket's plate from its evidence photos (engine/plate_reader.reread_ticket). Returns (new ticket, summary).
        ValueError when there is nothing to read; PlateServiceError when the process failed."""
        if not self.own_process():
            from engine import plate_reader
            names: list = []
            result = plate_reader.reread_ticket(ticket, frames, config, plate_format, names)
            if written is not None:
                written.extend(EVIDENCE_DIR / n for n in names)
            return result
        answer = self._call({"op": "reread", "ticket": ticket, "frames": list(frames or []), "config": config, "plate_format": plate_format})
        if written is not None:
            written.extend(EVIDENCE_DIR / Path(n).name for n in answer.get("written", []))
        return answer["new"], answer["summary"]

    def read_crop(self, plate_crop: np.ndarray, plate_format: str = "raw", ocr_engine: str = "easyocr", enhancement: str = "lanczos") -> dict:
        """Read one plate crop twice, as seen and enhanced (plate_ocr.extract_plate_reads), the same answer shape."""
        if not self.own_process():
            from engine import plate_ocr
            return plate_ocr.extract_plate_reads(plate_crop, plate_format, ocr_engine, enhancement)
        ok, buffer = cv2.imencode(".png", plate_crop)
        if not ok:
            raise ValueError("The crop could not be encoded")
        answer = self._call({
            "op": "read_crop", "image": base64.b64encode(buffer.tobytes()).decode("ascii"), "plate_format": plate_format,
            "ocr_engine": ocr_engine, "enhancement": enhancement})
        enhanced = cv2.imdecode(np.frombuffer(base64.b64decode(answer["enhanced_crop"]), dtype=np.uint8), cv2.IMREAD_COLOR)
        return {"raw_crop": plate_crop.copy(), "enhanced_crop": enhanced if enhanced is not None else plate_crop, "reads": answer["reads"]}

    def status(self) -> dict:
        """For the Live Monitor and the Performance window: is the plate process on, in which mode, busy."""
        alive = self._alive()
        return {
            "own_process": self.own_process(),
            "running": alive,
            "pid": self._proc.pid if alive else None,
            "mode": ("gpu" if self._gpu else "cpu") if alive else None,
            "busy": self._busy_since is not None,
            "jobs_done": self.jobs_done,
            "failures": self.failures,
            "last_job_s": self.last_job_s,
        }


SERVICE = PlateService()
atexit.register(SERVICE.stop)
