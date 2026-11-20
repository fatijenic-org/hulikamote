"""
plate_ocr.py - read the text of one plate crop: OCR (EasyOCR / PaddleOCR) and the picture enhancers (GAN, LapSRN, Lanczos).

This is the HEAVY part of plate reading (neural nets, a lot of Python around them). It does NOT run inside the live feed's process:
engine/plate_service.py starts engine/plate_worker.py as a process of its own and sends the work there, so the live pipeline never
shares its interpreter (GIL) or its CPU threads with the plate reading. The functions are the same ones the
live backend used to call itself; engine/pipeline.py keeps the old names as thin forwards to the service.

Two switches, set by the worker process (nothing changes for a caller that sets neither):
  HK_OCR_GPU=0       EasyOCR and the GAN run on the CPU (the service sets this when HK_PLATE_GPU=0, or =auto while the live feed runs)
  HK_PLATE_THREADS=n CPU threads of the GAN session (and, set by the worker, of torch / OpenCV)
"""
import logging
import os
from pathlib import Path

import cv2
import numpy as np

from engine import plate_vote

log = logging.getLogger(__name__)

# On the CPU the GAN (a 67 MB network) takes seconds for a crop of ordinary size and much longer for a big one; a big crop is
# readable without it, so above this many pixels the CPU path enlarges it with Lanczos instead.
CPU_GAN_MAX_PIXELS = int(os.environ.get("HK_PLATE_CPU_GAN_MAX_PX", "20000"))


def _use_gpu() -> bool:
    return os.environ.get("HK_OCR_GPU", "1") != "0"


def _threads() -> int:
    try:
        return max(0, int(os.environ.get("HK_PLATE_THREADS", "0")))
    except ValueError:
        return 0


# ─── EasyOCR (lazy singleton) ─────────────────────────────────────────────────

_ocr_reader = None
_paddle_reader = None


def _get_ocr_reader(engine="easyocr"):
    global _ocr_reader, _paddle_reader

    if engine == "paddleocr":
        if _paddle_reader is None:
            try:
                from paddleocr import PaddleOCR
                logging.getLogger("ppocr").setLevel(logging.ERROR)
                _paddle_reader = PaddleOCR(use_angle_cls=False, lang='en')
            except ImportError:
                log.warning("[OCR] paddleocr not installed.")
                return None
        return _paddle_reader

    # Default to easyocr
    if _ocr_reader is None:
        try:
            import easyocr
            _ocr_reader = easyocr.Reader(['en'], gpu=_use_gpu(), verbose=False)
        except ImportError:
            log.warning("[OCR] easyocr not installed.")
    return _ocr_reader


_sr_model = None


def _apply_super_resolution(image: np.ndarray) -> np.ndarray:
    """
    Applies LapSRN (Laplacian Pyramid Super-Resolution Network) to upscale
    blurry dashcam crops by 8x using deep learning instead of mathematical interpolation.
    """
    global _sr_model

    if _sr_model is None:
        try:
            model_path = Path(__file__).parent.parent / "models" / "LapSRN_x8.pb"
            if model_path.exists():
                _sr_model = cv2.dnn_superres.DnnSuperResImpl_create()
                _sr_model.readModel(str(model_path))
                _sr_model.setModel("lapsrn", 8)
            else:
                _sr_model = "failed"
        except Exception as e:
            print(f"[Warning] SuperResolution disabled: {e}")
            _sr_model = "failed"

    if _sr_model and _sr_model != "failed":
        try:
            return _sr_model.upsample(image)
        except Exception:
            pass

    # Fallback to normal resize if model fails
    h, w = image.shape[:2]
    return cv2.resize(image, (w * 4, h * 4), interpolation=cv2.INTER_CUBIC)


_realesrgan_session = None


def _gpu_gan_session(model_path):
    """The GAN on the GPU. Plate crops come in many sizes, and the live pipeline's session options search the fastest cuDNN algorithm for
    EVERY new input size (seconds each); here the default heuristic is used, so a crop of a new size costs nothing extra. The pool is capped
    (HK_ORT_GPU_MEM_MB, default 1024) like every other session."""
    import onnxruntime as ort
    from inference.providers import make_session

    if "CUDAExecutionProvider" not in ort.get_available_providers():
        return make_session(str(model_path))
    options = {
        "device_id": 0,
        "gpu_mem_limit": int(os.environ.get("HK_ORT_GPU_MEM_MB", "1024")) * 1024 * 1024,
        "arena_extend_strategy": "kSameAsRequested",
        "cudnn_conv_algo_search": "HEURISTIC",
        "do_copy_in_default_stream": True,
    }
    return make_session(str(model_path), providers=[("CUDAExecutionProvider", options), "CPUExecutionProvider"])


def _apply_realesrgan(image: np.ndarray) -> np.ndarray:
    global _realesrgan_session

    if not _use_gpu():
        h, w = image.shape[:2]
        if h * w > CPU_GAN_MAX_PIXELS:
            return cv2.resize(image, (w * 4, h * 4), interpolation=cv2.INTER_LANCZOS4)

    if _realesrgan_session is None:
        try:
            base_dir = Path(__file__).resolve().parent.parent / "models"
            model_path = base_dir / "realesrgan.onnx"
            if not model_path.exists():
                for p in base_dir.rglob("*.onnx"):
                    if p.name == "realesrgan.onnx":
                        model_path = p
                        break

            if model_path.exists():
                if _use_gpu():
                    _realesrgan_session = _gpu_gan_session(model_path)
                else:
                    import onnxruntime as ort
                    options = ort.SessionOptions()
                    if _threads():
                        options.intra_op_num_threads = _threads()
                    options.inter_op_num_threads = 1
                    _realesrgan_session = ort.InferenceSession(str(model_path), options, providers=["CPUExecutionProvider"])
            else:
                _realesrgan_session = "failed"
        except Exception as e:
            _realesrgan_session = "failed"
            print(f"[Enhancement] Failed to load realesrgan: {e}")

    if _realesrgan_session == "failed" or _realesrgan_session is None:
        # Graceful fallback to Lanczos
        h, w = image.shape[:2]
        return cv2.resize(image, (w * 4, h * 4), interpolation=cv2.INTER_LANCZOS4)

    try:
        input_name = _realesrgan_session.get_inputs()[0].name

        # Preprocess: BGR to RGB, normalize, NCHW format
        rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        input_tensor = rgb.astype(np.float32) / 255.0
        input_tensor = np.transpose(input_tensor, (2, 0, 1))
        input_tensor = np.expand_dims(input_tensor, axis=0)

        # Run GAN
        outputs = _realesrgan_session.run(None, {input_name: input_tensor})

        # Postprocess
        output_tensor = np.squeeze(outputs[0])
        output_tensor = np.clip(output_tensor, 0, 1)
        output_tensor = np.transpose(output_tensor, (1, 2, 0))
        output_bgr = cv2.cvtColor((output_tensor * 255.0).astype(np.uint8), cv2.COLOR_RGB2BGR)
        return output_bgr
    except Exception as e:
        print(f"[Enhancement] realesrgan Error during inference: {e}")
        h, w = image.shape[:2]
        return cv2.resize(image, (w * 4, h * 4), interpolation=cv2.INTER_LANCZOS4)


def _ocr_plate_image(plate_crop: np.ndarray, plate_format: str = "raw", ocr_engine: str = "easyocr", enhancement: str = "none") -> tuple[str, str, np.ndarray, np.ndarray, float]:
    """
    Run EasyOCR or PaddleOCR on a plate crop.
    Returns (raw_text, corrected_text, raw_crop, enhanced_crop).
    raw_crop is the original unmodified image.
    enhanced_crop is after GAN/SR/Lanczos upscaling (may be identical to raw_crop if no enhancement ran).
    """
    reader = _get_ocr_reader(ocr_engine)
    if reader is None:
        return "unidentified", "unidentified", plate_crop, plate_crop, 0.0

    h, w = plate_crop.shape[:2]
    if h == 0 or w == 0:
        return "unidentified", "unidentified", plate_crop, plate_crop, 0.0

    # Save original before enhancement so we can return both
    raw_crop = plate_crop.copy()

    # All enhancers are unconditional — always upscale for better OCR readability
    if enhancement == "realesrgan":
        plate_crop = _apply_realesrgan(plate_crop)
    elif enhancement == "lapsrn":
        plate_crop = _apply_super_resolution(plate_crop)
    elif enhancement == "lanczos":
        plate_crop = cv2.resize(plate_crop, (w * 4, h * 4), interpolation=cv2.INTER_LANCZOS4)

    sr_crop = plate_crop  # enhanced copy (always different from raw_crop now)

    # PaddleOCR performs best on color images (BGR). EasyOCR can use grayscale.
    gray = cv2.cvtColor(plate_crop, cv2.COLOR_BGR2GRAY)

    try:
        raw = ""
        confidence = 0.0

        if ocr_engine == "paddleocr":
            # PaddleOCR returns a nested list structure. Pass the color BGR image!
            try:
                results = reader.ocr(plate_crop)
            except TypeError:
                results = reader.ocr(plate_crop, cls=False)

            if results and results[0]:
                raw = "".join([res[1][0] for res in results[0]]).strip().upper().replace(" ", "")
                # Average the confidences
                confidences = [res[1][1] for res in results[0]]
                if confidences:
                    confidence = sum(confidences) / len(confidences)
                import re
                raw = re.sub(r'[^0-9A-Z]', '', raw)
        else:
            # EasyOCR detail=1 returns [(bbox, text, prob)]
            results = reader.readtext(gray, detail=1, paragraph=False, allowlist='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ')
            if results:
                raw = "".join([res[1] for res in results]).strip().upper().replace(" ", "")
                confidences = [res[2] for res in results]
                if confidences:
                    confidence = sum(confidences) / len(confidences)

        if raw:

            if plate_format == "raw":
                return raw, raw, raw_crop, sr_crop, confidence

            dict_char_to_int = {'O': '0', 'I': '1', 'J': '3', 'A': '4', 'G': '6', 'S': '5', 'B': '8', 'Z': '2', 'Q': '0', 'D': '0', 'T': '7', 'U': '0', 'Y': '7', 'P': '0', 'F': '5', 'L': '4'}
            dict_int_to_char = {'0': 'O', '1': 'I', '3': 'J', '4': 'A', '6': 'G', '5': 'S', '8': 'B', '2': 'Z', '7': 'T', '9': 'P'}

            cleaned = ""
            mapping = {}
            if plate_format == "ph_standard":
                mapping = {0: dict_int_to_char, 1: dict_int_to_char, 2: dict_int_to_char,
                           3: dict_char_to_int, 4: dict_char_to_int, 5: dict_char_to_int, 6: dict_char_to_int}
            elif plate_format == "uk_standard":
                mapping = {0: dict_int_to_char, 1: dict_int_to_char,
                           2: dict_char_to_int, 3: dict_char_to_int,
                           4: dict_int_to_char, 5: dict_int_to_char, 6: dict_int_to_char}

            if mapping:
                for i in range(len(raw)):
                    if i in mapping:
                        if raw[i] in mapping[i]:
                            cleaned += mapping[i][raw[i]]
                        else:
                            cleaned += raw[i]
                    else:
                        cleaned += raw[i]
                return raw, cleaned, raw_crop, sr_crop, confidence

            return raw, raw, raw_crop, sr_crop, confidence

    except Exception as e:
        print(f"OCR Error: {e}")

    return "unidentified", "unidentified", raw_crop, sr_crop, 0.0


def _enlarge_for_ocr(image: np.ndarray) -> np.ndarray:
    """A plain enlargement (no enhancement model) for a plate that is only a few pixels tall, so the OCR can read the "as seen" crop at all."""
    h, w = image.shape[:2]
    if h == 0 or w == 0 or h >= 48:
        return image
    k = max(2, int(round(64 / h)))
    return cv2.resize(image, (w * k, h * k), interpolation=cv2.INTER_CUBIC)


def extract_plate_reads(plate_crop: np.ndarray, plate_format: str = "raw", ocr_engine: str = "easyocr", enhancement: str = "lanczos") -> dict:
    """
    Read a plate crop TWICE: as it was seen (only enlarged, never enhanced) and enhanced (realesrgan = the GAN, lapsrn, lanczos).
    Returns {"raw_crop", "enhanced_crop", "reads": [{"source": "raw" | "enhanced", "raw", "cleaned", "confidence"}, ...]}.
    With enhancement "none" there is nothing to compare: one read, "raw". engine/plate_vote.py grades the reads.
    """
    raw_crop = plate_crop.copy()
    seen = _ocr_plate_image(_enlarge_for_ocr(raw_crop), plate_format, ocr_engine, "none")
    reads = [{"source": "raw", "raw": seen[0], "cleaned": seen[1], "confidence": float(seen[4])}]
    enhanced_crop = raw_crop
    if enhancement not in ("none", "", None):
        enhanced = _ocr_plate_image(raw_crop, plate_format, ocr_engine, enhancement)
        enhanced_crop = enhanced[3]
        reads.append({"source": "enhanced", "raw": enhanced[0], "cleaned": enhanced[1], "confidence": float(enhanced[4])})
    return {"raw_crop": raw_crop, "enhanced_crop": enhanced_crop, "reads": reads}


def extract_plate_text(plate_crop: np.ndarray, plate_format: str = "raw", ocr_engine: str = "easyocr", enhancement: str = "lanczos"):
    """The best of the two reads of extract_plate_reads, as (raw_text, cleaned_text, raw_crop, enhanced_crop, confidence)."""
    got = extract_plate_reads(plate_crop, plate_format, ocr_engine, enhancement)
    top = plate_vote.best_read(got["reads"], plate_format)
    return top["raw"], top["cleaned"], got["raw_crop"], got["enhanced_crop"], top["confidence"]
