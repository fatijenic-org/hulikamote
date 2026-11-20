"""
plate_worker.py - the plate reading PROCESS.

Started by engine/plate_service.py (`python -m engine.plate_worker`), never imported by the live backend. It owns the plate model,
the OCR and the GAN, so none of that shares the live feed's interpreter (GIL) or CPU threads; it runs in Windows' background mode, so
the live feed also goes first for disk, memory and (best effort) the GPU.

Talk: one JSON object per line. The service writes requests on this process's stdin, this process answers on the real stdout.
Everything else that prints (libraries, warnings) is moved to stderr, which the service writes to plate_worker.log.

  request   {"id": n, "op": "reread" | "read_crop" | "ping", ...}
  answer    {"id": n, "ok": true, ...}  or  {"id": n, "ok": false, "kind": "ValueError", "error": "...", "trace": "..."}

It stops by itself when its stdin closes (the backend ended).
"""
import base64
import json
import os
import sys
import traceback

# Set the thread limits before numpy / torch / onnxruntime are imported.
_THREADS = os.environ.get("HK_PLATE_THREADS", "").strip()
if _THREADS.isdigit() and int(_THREADS) > 0:
    for _name in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
        os.environ.setdefault(_name, _THREADS)


def _plain(value):
    """json.dumps fallback: numpy numbers and arrays become plain Python."""
    if hasattr(value, "item") and getattr(value, "ndim", 1) == 0:
        return value.item()
    if hasattr(value, "tolist"):
        return value.tolist()
    return str(value)


def _png(image) -> str:
    import cv2
    ok, buffer = cv2.imencode(".png", image)
    if not ok:
        raise ValueError("The picture could not be encoded")
    return base64.b64encode(buffer.tobytes()).decode("ascii")


def _decode(text: str):
    import cv2
    import numpy as np
    image = cv2.imdecode(np.frombuffer(base64.b64decode(text), dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("The picture could not be decoded")
    return image


def _handle(request: dict) -> dict:
    op = request.get("op")
    if op == "ping":
        return {"pid": os.getpid(), "gpu": os.environ.get("HK_OCR_GPU", "1") != "0"}
    _limit_libraries()
    if request.get("focus"):
        _set_threads(os.cpu_count() or 4)                  # the first job too: torch is loaded by now
    if op == "warm":
        # load everything once (plate model, EasyOCR, the GAN) with a tiny blank crop, so the first real read is fast
        import numpy as np
        from engine import plate_ocr, plate_reader
        plate_reader.plate_finder({})
        plate_ocr.extract_plate_reads(np.full((24, 72, 3), 127, np.uint8), "ph_standard", "easyocr", "realesrgan")
        return {"warm": True}
    if op == "reread":
        from engine import plate_reader
        written: list = []
        new, summary = plate_reader.reread_ticket(
            request["ticket"], request.get("frames") or [], request.get("config") or {}, request.get("plate_format") or "ph_standard", written)
        return {"new": new, "summary": summary, "written": written}
    if op == "read_crop":
        from engine import plate_ocr
        got = plate_ocr.extract_plate_reads(
            _decode(request["image"]), request.get("plate_format") or "raw", request.get("ocr_engine") or "easyocr",
            request.get("enhancement") or "lanczos")
        return {"reads": got["reads"], "enhanced_crop": _png(got["enhanced_crop"])}
    raise ValueError(f"Unknown request: {op}")


_limited = False


def _configured_threads() -> int:
    return int(_THREADS) if _THREADS.isdigit() else 0


def _set_threads(n: int) -> None:
    """CPU threads of OpenCV and torch (whatever is loaded; nothing is imported here)."""
    if n <= 0:
        return
    cv2 = sys.modules.get("cv2")
    if cv2 is not None:
        try:
            cv2.setNumThreads(n)
        except Exception:
            pass
    torch = sys.modules.get("torch")
    if torch is not None:
        try:
            torch.set_num_threads(n)
        except Exception:
            pass


def _focus_mode(on: bool) -> None:
    """A job the reviewer waits for: leave Windows' background mode, run above normal priority (CPU, disk, memory, GPU scheduling) and use
    every CPU thread; afterwards go back to the quiet mode. Best effort."""
    if on:
        _set_threads(os.cpu_count() or 4)
    else:
        _set_threads(_configured_threads())
    if os.name != "nt" or os.environ.get("HK_PLATE_BACKGROUND", "1") == "0":
        return
    try:
        import ctypes
        kernel = ctypes.windll.kernel32
        kernel.GetCurrentProcess.restype = ctypes.c_void_p
        kernel.SetPriorityClass.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        me = kernel.GetCurrentProcess()
        if on:
            kernel.SetPriorityClass(me, 0x00200000)        # PROCESS_MODE_BACKGROUND_END
            kernel.SetPriorityClass(me, 0x00008000)        # ABOVE_NORMAL_PRIORITY_CLASS
        else:
            kernel.SetPriorityClass(me, 0x00004000)        # BELOW_NORMAL_PRIORITY_CLASS
            kernel.SetPriorityClass(me, 0x00100000)        # PROCESS_MODE_BACKGROUND_BEGIN
    except Exception:
        pass
    try:
        import ctypes
        gdi = ctypes.windll.gdi32
        gdi.D3DKMTSetProcessSchedulingPriorityClass.argtypes = [ctypes.c_void_p, ctypes.c_int]
        ctypes.windll.kernel32.GetCurrentProcess.restype = ctypes.c_void_p
        gdi.D3DKMTSetProcessSchedulingPriorityClass(ctypes.windll.kernel32.GetCurrentProcess(), 3 if on else 1)   # above normal / below normal
    except Exception:
        pass


def _limit_libraries() -> None:
    """Fewer threads for torch and OpenCV (onnxruntime sessions get theirs in plate_ocr / plate_reader). Done once, at the first real
    job: importing torch takes a long time on a busy machine, and the service must hear "ready" long before that."""
    global _limited
    if _limited:
        return
    _limited = True
    threads = int(_THREADS) if _THREADS.isdigit() else 0
    if threads <= 0:
        return
    try:
        import cv2
        cv2.setNumThreads(threads)
    except Exception:
        pass
    try:
        import torch
        torch.set_num_threads(threads)
    except Exception:
        pass


def _background_mode() -> None:
    """Windows background mode for this process: the lowest CPU, DISK and MEMORY priority (its pages are the first to be taken back when
    RAM is short), so the live feed's models and pictures always come first - also while this process loads torch and its models. The GPU
    scheduler is asked to serve this process after the others. All best effort: a failure changes nothing. HK_PLATE_BACKGROUND=0 skips it."""
    if os.name != "nt" or os.environ.get("HK_PLATE_BACKGROUND", "1") == "0":
        return
    try:
        import ctypes
        kernel = ctypes.windll.kernel32
        kernel.GetCurrentProcess.restype = ctypes.c_void_p
        kernel.SetPriorityClass.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        kernel.SetPriorityClass(kernel.GetCurrentProcess(), 0x00100000)        # PROCESS_MODE_BACKGROUND_BEGIN
    except Exception:
        pass
    try:
        import ctypes
        gdi = ctypes.windll.gdi32
        gdi.D3DKMTSetProcessSchedulingPriorityClass.argtypes = [ctypes.c_void_p, ctypes.c_int]
        ctypes.windll.kernel32.GetCurrentProcess.restype = ctypes.c_void_p
        gdi.D3DKMTSetProcessSchedulingPriorityClass(ctypes.windll.kernel32.GetCurrentProcess(), 1)   # D3DKMT_SCHEDULINGPRIORITYCLASS_BELOW_NORMAL
    except Exception:
        pass


def main() -> None:
    _background_mode()
    # The real stdout is kept for the talk; anything else that prints goes to stderr.
    talk = os.fdopen(os.dup(1), "wb")
    os.dup2(2, 1)
    sys.stdout = sys.stderr

    def say(message: dict) -> None:
        talk.write((json.dumps(message, default=_plain) + "\n").encode("utf-8"))
        talk.flush()

    say({"ready": True, "pid": os.getpid(), "gpu": os.environ.get("HK_OCR_GPU", "1") != "0"})   # first: nothing heavy is loaded yet
    for line in iter(sys.stdin.buffer.readline, b""):
        line = line.strip()
        if not line:
            continue
        request_id = None
        try:
            request = json.loads(line)
            request_id = request.get("id")
            focus = bool(request.get("focus"))
            if focus:
                _focus_mode(True)
            try:
                result = _handle(request)
            finally:
                if focus:
                    _focus_mode(False)
            say({"id": request_id, "ok": True, **result})
        except Exception as e:
            sys.stderr.write(traceback.format_exc() + "\n")
            sys.stderr.flush()
            say({"id": request_id, "ok": False, "kind": type(e).__name__, "error": str(e), "trace": traceback.format_exc()[-2000:]})


if __name__ == "__main__":
    main()
