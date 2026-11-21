"""
road_presets.py - saved road configurations of the Live Monitor setup: the road markings (crosswalks, lines, lanes, roads, sidewalks with
their direction arrows), saved under a name so they can be used again, duplicated and edited later.

The markings are kept as the dashboard sends them (1920x1080 reference space), so a preset fits any picture of the same camera view.
Stored in hulikamote_backend/road_presets.json (a person's own data: not committed).
"""
import json
import threading
import time
import uuid
from pathlib import Path

PRESETS_PATH = Path(__file__).resolve().parent.parent / "road_presets.json"
MAX_PRESETS = 200
MAX_MARKINGS = 200
MAX_NAME = 80


class PresetError(ValueError):
    """What is wrong, in plain words (the dashboard shows it)."""


def _clean_name(name) -> str:
    text = " ".join(str(name or "").split())[:MAX_NAME]
    if not text:
        raise PresetError("Give the road a name.")
    return text


def _clean_markings(markings) -> list[dict]:
    if not isinstance(markings, list) or len(markings) > MAX_MARKINGS:
        raise PresetError(f"A road has at most {MAX_MARKINGS} markings.")
    out = []
    for item in markings:
        if not isinstance(item, dict) or not isinstance(item.get("kind"), str):
            raise PresetError("A marking is not valid.")
        out.append(item)
    return out


class RoadPresets:
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
    def _summary(p: dict, video_hash: str | None = None) -> dict:
        return {"id": p["id"], "name": p.get("name", ""), "count": len(p.get("markings") or []), "updated": p.get("updated", 0),
                "video_hash": p.get("video_hash") or "", "video_name": p.get("video_name") or "",
                "match": bool(video_hash) and p.get("video_hash") == video_hash}

    def list(self, video_hash: str | None = None) -> list[dict]:
        """Names only (no markings): the roads saved for this video first, then the newest change."""
        with self._lock:
            rows = [self._summary(p, video_hash) for p in self._read()]
        return sorted(rows, key=lambda s: (not s["match"], -float(s["updated"] or 0)))

    def get(self, preset_id: str) -> dict | None:
        with self._lock:
            return next((p for p in self._read() if p["id"] == preset_id), None)

    def create(self, name, markings, video_hash: str = "", video_name: str = "") -> dict:
        name, markings = _clean_name(name), _clean_markings(markings)
        with self._lock:
            items = self._read()
            if len(items) >= MAX_PRESETS:
                raise PresetError("Too many saved roads. Delete one first.")
            preset = {"id": uuid.uuid4().hex[:12], "name": name, "markings": markings, "updated": time.time(),
                      "video_hash": str(video_hash or ""), "video_name": str(video_name or "")[:200]}
            self._write(items + [preset])
            return preset

    def update(self, preset_id: str, name=None, markings=None, video_hash=None, video_name=None) -> dict | None:
        """Change the name and/or the markings of a saved road. None: there is no such road."""
        with self._lock:
            items = self._read()
            preset = next((p for p in items if p["id"] == preset_id), None)
            if preset is None:
                return None
            if name is not None:
                preset["name"] = _clean_name(name)
            if markings is not None:
                preset["markings"] = _clean_markings(markings)
            if video_hash is not None:
                preset["video_hash"] = str(video_hash)
                preset["video_name"] = str(video_name or "")[:200]
            preset["updated"] = time.time()
            self._write(items)
            return preset

    def duplicate(self, preset_id: str) -> dict | None:
        with self._lock:
            items = self._read()
            source = next((p for p in items if p["id"] == preset_id), None)
            if source is None:
                return None
            if len(items) >= MAX_PRESETS:
                raise PresetError("Too many saved roads. Delete one first.")
            copy = {"id": uuid.uuid4().hex[:12], "name": f"{source.get('name', 'Road')} (copy)"[:MAX_NAME],
                    "markings": json.loads(json.dumps(source.get("markings") or [])), "updated": time.time(),
                    "video_hash": source.get("video_hash") or "", "video_name": source.get("video_name") or ""}
            self._write(items + [copy])
            return copy

    def delete(self, preset_id: str) -> bool:
        with self._lock:
            items = self._read()
            kept = [p for p in items if p["id"] != preset_id]
            if len(kept) == len(items):
                return False
            self._write(kept)
            return True
