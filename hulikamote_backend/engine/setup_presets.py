"""
setup_presets.py - saved violation setups of the Live Monitor: which violations are on and how each one is set (zones, signs, settings), saved
under a name together with the fingerprint of the video they were made for (engine/video_fingerprint.py), so the setup can be offered again
when the same video is used and applied with one click.

Stored in hulikamote_backend/setup_presets.json (a person's own data: not committed). The road markings are NOT part of it: the road has its
own saved roads (engine/road_presets.py).
"""
import json
import threading
import time
import uuid
from pathlib import Path

PRESETS_PATH = Path(__file__).resolve().parent.parent / "setup_presets.json"
MAX_PRESETS = 200
MAX_NAME = 80
# What a saved setup keeps (the live setup's keys without the road markings).
KEYS = (
    "active_violations", "per_violation_configs", "tracker", "plate_model", "plate_method", "plate_format",
    "ocr_engine", "enhancement", "primary_model", "use_sahi", "flag_sensitivity", "evidence_gap", "blur_privacy",
)


class PresetError(ValueError):
    """What is wrong, in plain words (the dashboard shows it)."""


def _clean_name(name) -> str:
    text = " ".join(str(name or "").split())[:MAX_NAME]
    if not text:
        raise PresetError("Give the setup a name.")
    return text


def _clean_config(config) -> dict:
    if not isinstance(config, dict):
        raise PresetError("The setup is not valid.")
    kept = {k: config[k] for k in KEYS if k in config}
    violations = kept.get("active_violations")
    if not isinstance(violations, list) or not violations:
        raise PresetError("Pick at least one violation before saving a setup.")
    return json.loads(json.dumps(kept))


class SetupPresets:
    def __init__(self, path: Path | None = None):
        self.path = path or PRESETS_PATH
        self._lock = threading.Lock()

    def _read(self) -> list[dict]:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return []
        return [p for p in data if isinstance(p, dict) and p.get("id")] if isinstance(data, list) else []

    def _write(self, items: list[dict]) -> None:
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(items, ensure_ascii=False, indent=1), encoding="utf-8")
        tmp.replace(self.path)

    @staticmethod
    def _summary(p: dict, video_hash: str | None) -> dict:
        config = p.get("config") or {}
        return {"id": p["id"], "name": p.get("name", ""), "violations": list(config.get("active_violations") or []),
                "video_hash": p.get("video_hash") or "", "video_name": p.get("video_name") or "", "updated": p.get("updated", 0),
                "match": bool(video_hash) and p.get("video_hash") == video_hash}

    def list(self, video_hash: str | None = None) -> list[dict]:
        """No configs (just names and the violations), the ones made for this video first, then the newest."""
        with self._lock:
            rows = [self._summary(p, video_hash) for p in self._read()]
        return sorted(rows, key=lambda s: (not s["match"], -float(s["updated"] or 0)))

    def get(self, preset_id: str) -> dict | None:
        with self._lock:
            return next((p for p in self._read() if p["id"] == preset_id), None)

    def create(self, name, config, video_hash: str = "", video_name: str = "") -> dict:
        name, config = _clean_name(name), _clean_config(config)
        with self._lock:
            items = self._read()
            if len(items) >= MAX_PRESETS:
                raise PresetError("Too many saved setups. Delete one first.")
            preset = {"id": uuid.uuid4().hex[:12], "name": name, "config": config, "video_hash": str(video_hash or ""),
                      "video_name": str(video_name or "")[:200], "updated": time.time()}
            self._write(items + [preset])
            return preset

    def update(self, preset_id: str, name=None, config=None, video_hash=None, video_name=None) -> dict | None:
        with self._lock:
            items = self._read()
            preset = next((p for p in items if p["id"] == preset_id), None)
            if preset is None:
                return None
            if name is not None:
                preset["name"] = _clean_name(name)
            if config is not None:
                preset["config"] = _clean_config(config)
            if video_hash is not None:
                preset["video_hash"] = str(video_hash)
                preset["video_name"] = str(video_name or "")[:200]
            preset["updated"] = time.time()
            self._write(items)
            return preset

    def delete(self, preset_id: str) -> bool:
        with self._lock:
            items = self._read()
            kept = [p for p in items if p["id"] != preset_id]
            if len(kept) == len(items):
                return False
            self._write(kept)
            return True
