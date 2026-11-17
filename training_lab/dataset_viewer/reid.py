"""
reid.py - The Car matcher (ReID) manager of the Dataset Viewer: clean datasets/reid before the matcher is trained on it.

datasets/reid/images/<analysis>/<vehicle>/*.jpg is one folder per vehicle (car, motorcycle, tricycle, jeepney, bus, truck ...), and the
folder IS the label. When the tracker jumps (one vehicle gets a new number) it is filed as two folders; when it swaps (two vehicles
share a number) one folder holds two. This lets a person fix both:
  * move photos between the vehicles of one analysis, merge vehicles, take bad photos out;
  * set a vehicle's class (the tickets' class is the starting guess), so a bike is not mistaken for a truck;
  * set photos aside in the TEMPORARY area (datasets/reid/temporary/<analysis>/<vehicle>/): they are not trained on until you
    "keep" them as their own vehicle or merge them into a known one. The trainer only reads images/, so this is safe by construction.

Same rules as the rest of the viewer:
  * nothing is deleted: removed photos go to datasets/_quarantine/reid/<reason>/<analysis>/<vehicle>/ and can be restored;
  * every change is written to dataset_viewer_cache/reid_actions.json with what is needed to undo it (in order);
  * no write while train_reid.py runs;
  * names that reach the disk are validated; nothing is written inside hulikamote_backend/.
Every move / merge is also noted in datasets/reid/decisions.jsonl ("source": "manager") like the review screens do, and "not the same"
answers there keep the Harvest > Same car? questions from asking about that pair again.

Suspects (repeats, jumps, mixed folders) come from `train_reid.py --scan`: the matcher's own fingerprints, one scan of about a minute.
"Most alike" suggestions (similar) are quick and model-free: the colour layout of the photos (harvest_tool.pairs.look).
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import threading
import time
import uuid
from collections import Counter
from pathlib import Path

from .app import LAB, NotFound, TrainingBusy, ViewerError, safe_image_name, safe_name, safe_reason

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
DEFAULT_REASON = "removed_in_manager"
KEEP_ACTIONS = 500
CLASSES = ("car", "motorcycle", "tricycle", "jeepney", "bus", "truck", "other")
FILTERS = ("all", "flagged", "jumps", "repeats", "mixed", "small", "used", "temporary")
SCAN_SCRIPT = LAB / "scripts" / "train_reid.py"
SUGGEST_SCRIPT = LAB / "scripts" / "reid_suggest_class.py"


def default_training_check() -> bool:
    """Is the car matcher being trained right now (train_reid.py, but not its read-only --scan)?"""
    import psutil
    for proc in psutil.process_iter(["cmdline"]):
        try:
            cmd = proc.info["cmdline"] or []
        except Exception:
            continue
        text = " ".join(cmd)
        if "train_reid.py" in text and "--scan" not in cmd:
            return True
    return False


def _split(key) -> tuple[str, str]:
    if not isinstance(key, str) or key.count("/") != 1:
        raise ViewerError(f"not a vehicle: {key!r}")
    analysis, car = key.split("/")
    return safe_name(analysis), safe_name(car)


def _atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.{threading.get_ident()}.tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def _spread(items: list, n: int) -> list:
    if len(items) <= n:
        return list(items)
    return [items[round(i * (len(items) - 1) / (n - 1))] for i in range(n)] if n > 1 else [items[0]]


class ReidManager:
    def __init__(self, datasets: Path, cache: Path, training_check=None, thumb=None, scan_runner=None, forensic_root=None,
                 suggest_runner=None):
        self.datasets = Path(datasets)
        self.root = self.datasets / "reid"
        self.images = self.root / "images"
        self.temp = self.root / "temporary"
        self.qroot = self.datasets / "_quarantine" / "reid"
        self.decisions = self.root / "decisions.jsonl"
        self.classes_path = self.root / "classes.json"
        self.cache = Path(cache)
        self.log_path = self.cache / "reid_actions.json"
        self.scan_path = self.cache / "reid_scan.json"
        self.suggest_path = self.cache / "reid_class_suggest.json"
        self.dismiss_path = self.cache / "reid_dismissed.json"
        self.is_training = training_check or default_training_check
        self._thumb = thumb
        self._scan_runner = scan_runner or self._run_scan_process
        self._suggest_runner = suggest_runner or self._run_suggest_process
        self._suggested_cache: tuple[float, dict] = (0.0, {})
        self._forensic_root = Path(forensic_root) if forensic_root else None
        self._lock = threading.RLock()
        self._jobs: dict[str, dict] = {}
        self._tickets: dict[str, tuple[float, dict]] = {}
        self._looks: dict[str, tuple[float, tuple]] = {}
        self._actions: list[dict] = self._read(self.log_path, [])
        self._dismissed: set[str] = set(self._read(self.dismiss_path, []))
        self._classes: dict[str, str] = {k: v for k, v in self._read(self.classes_path, {}).items() if v in CLASSES}

    # ----------------------------------------------------------------- small helpers

    @staticmethod
    def _read(path: Path, default):
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return default

    def _save(self) -> None:
        _atomic(self.log_path, json.dumps(self._actions[-KEEP_ACTIONS:], ensure_ascii=False))
        _atomic(self.dismiss_path, json.dumps(sorted(self._dismissed)))

    def _save_classes(self) -> None:
        present = {k for k, _, _ in self._all_cars()}
        self._classes = {k: v for k, v in self._classes.items() if k in present}
        if self._classes or self.classes_path.exists():
            _atomic(self.classes_path, json.dumps(self._classes, ensure_ascii=False, indent=1, sort_keys=True))

    def _guard(self) -> None:
        try:
            busy = self.is_training()
        except Exception as e:                                           # cannot tell: do not risk the training
            raise TrainingBusy(f"Could not check whether the car matcher is training ({type(e).__name__}); nothing was changed.")
        if busy:
            raise TrainingBusy("The car matcher is training right now. Wait for it to finish; nothing was changed.")

    def _rel(self, path: Path) -> str:
        return path.resolve().relative_to(self.datasets.resolve()).as_posix()

    @staticmethod
    def _in_reid(rel: str) -> str:
        """datasets/-relative -> datasets/reid-relative, the paths decisions.jsonl holds (images/<analysis>/<vehicle>/<file>)."""
        return rel[len("reid/"):] if rel.startswith("reid/") else rel

    def _abs(self, rel: str) -> Path:
        path = (self.datasets / rel).resolve()
        path.relative_to(self.datasets.resolve())                       # a path from the log can never leave the datasets folder
        return path

    def _dirs(self, key: str) -> tuple[Path, Path]:
        analysis, car = _split(key)
        return self.images / analysis / car, self.temp / analysis / car

    def _car_dir(self, key: str) -> Path:
        """Where the vehicle is: images/ (trained on) or temporary/ (set aside)."""
        perm, tmp = self._dirs(key)
        if perm.is_dir():
            return perm
        if tmp.is_dir():
            return tmp
        return perm

    def _is_temp(self, key: str) -> bool:
        perm, tmp = self._dirs(key)
        return tmp.is_dir() and not perm.is_dir()

    @staticmethod
    def _photos_in(folder: Path) -> list[str]:
        try:
            return sorted(f.name for f in folder.iterdir() if f.is_file() and f.suffix.lower() in IMAGE_EXT)
        except OSError:
            return []

    def _all_cars(self) -> list[tuple[str, Path, bool]]:
        """(key, folder, set aside?) of every vehicle: the trained-on ones first, then the temporary ones."""
        out = []
        for base, temporary in ((self.images, False), (self.temp, True)):
            if not base.is_dir():
                continue
            for a in sorted(p for p in base.iterdir() if p.is_dir()):
                for c in sorted(p for p in a.iterdir() if p.is_dir()):
                    if temporary and (self.images / a.name / c.name).is_dir():
                        continue
                    out.append((f"{a.name}/{c.name}", c, temporary))
        return out

    def _decide(self, kind: str, identities: dict[str, list[str]]) -> None:
        """One line in decisions.jsonl, the format the review screens and the harvest tool write."""
        analysis = next((k.split("/")[0] for k in identities if "/" in k), "")
        lines = {key.split("/")[-1]: rels for key, rels in identities.items()}
        self.root.mkdir(parents=True, exist_ok=True)
        with open(self.decisions, "a", encoding="utf-8") as f:
            f.write(json.dumps({"ts": time.time(), "kind": kind, "task_id": analysis, "identities": lines,
                                "source": "manager"}) + "\n")

    # ----------------------------------------------------------------- classes

    def _forensic(self) -> Path | None:
        if self._forensic_root:
            return self._forensic_root
        try:
            from harvest_tool.config import Paths
            return Paths().forensic
        except Exception:
            return None

    def _ticket_classes(self, analysis: str) -> dict[str, str]:
        """vehicle label -> the class the analysis gave it (its photos' most common class), the starting guess."""
        root = self._forensic()
        report = root / analysis / "output" / "report.json" if root else None
        if report is None or not report.is_file():
            return {}
        mtime = report.stat().st_mtime
        cached = self._tickets.get(analysis)
        if cached and cached[0] == mtime:
            return cached[1]
        out: dict[str, str] = {}
        try:
            for t in json.loads(report.read_text(encoding="utf-8")):
                counts = Counter(m.get("vclass") for m in (t.get("evidence_meta") or []) if m.get("vclass") in CLASSES)
                if t.get("ticket_uid") and counts:
                    out[f"{analysis[:8]}_{t['ticket_uid']}"] = counts.most_common(1)[0][0]
        except (OSError, ValueError, AttributeError):
            out = {}
        self._tickets[analysis] = (mtime, out)
        return out

    def _suggested(self) -> dict[str, str]:
        """vehicle key -> the class the vehicle model suggested (Suggest classes), read again when the file changes."""
        try:
            mtime = self.suggest_path.stat().st_mtime
        except OSError:
            return {}
        if self._suggested_cache[0] != mtime:
            data = self._read(self.suggest_path, {})
            classes = data.get("classes", {}) if isinstance(data, dict) else {}
            self._suggested_cache = (mtime, {k: v["class"] for k, v in classes.items()
                                             if isinstance(v, dict) and v.get("class") in CLASSES})
        return self._suggested_cache[1]

    def _class_of(self, key: str, include_model: bool = True) -> tuple[str | None, str | None]:
        """(class, where it comes from: 'you' | 'ticket' | 'model' | None). What you set wins, then the ticket's class, then the model's."""
        mine = self._classes.get(key)
        if mine:
            return mine, "you"
        analysis, car = _split(key)
        guesses = self._ticket_classes(analysis)
        guess = guesses.get(car) or (guesses.get(car[:-2]) if car.endswith("_b") else None)
        if guess:
            return guess, "ticket"
        if include_model:
            suggestion = self._suggested().get(key)
            if suggestion:
                return suggestion, "model"
        return None, None

    # ----------------------------------------------------------------- reading

    def _scan(self) -> dict | None:
        scan = self._read(self.scan_path, None)
        return scan if isinstance(scan, dict) else None

    def _edits_since_scan(self, scan: dict | None) -> int:
        if scan is None:
            return len(self._live_actions())
        return sum(1 for a in self._live_actions() if a["ts"] > scan.get("ts", 0))

    def _live_actions(self) -> list[dict]:
        return [a for a in self._actions if not a.get("undone")]

    def _flags(self, scan: dict | None, present: set[str]) -> dict:
        """What the last scan said about each vehicle (only about folders that still exist; a bike and a truck are never one vehicle)."""
        flags = {"repeat_of": {}, "kept_by": {}, "jump": {}, "mixed": {}, "used": set()}
        if not scan:
            return flags
        for r in scan.get("repeats", []):
            if r["dropped"] in present and r["kept"] in present:
                flags["repeat_of"][r["dropped"]] = r["kept"]
                flags["kept_by"].setdefault(r["kept"], []).append(r["dropped"])
        for j in scan.get("jumps", []):
            a, b = j["a"], j["b"]
            if a not in present or b not in present or "|".join(sorted((a, b))) in self._dismissed:
                continue
            ca, cb = self._class_of(a, False)[0], self._class_of(b, False)[0]
            if ca and cb and ca != cb:
                continue
            flags["jump"].setdefault(a, []).append({"key": b, "alike": j["alike"]})
            flags["jump"].setdefault(b, []).append({"key": a, "alike": j["alike"]})
        for m in scan.get("mixed", []):
            if m["car"] in present:
                flags["mixed"][m["car"]] = m["share"]
        repeats = set(flags["repeat_of"])
        flags["used"] = {k for k in present if k not in repeats}
        return flags

    def summary(self) -> dict:
        listing = self._all_cars()
        counts = {k: len(self._photos_in(p)) for k, p, t in listing if not t}
        temp = {k: len(self._photos_in(p)) for k, p, t in listing if t}
        scan = self._scan()
        flags = self._flags(scan, set(counts))
        edits = self._edits_since_scan(scan)
        scan_info = None
        if scan:
            scan_info = {"ts": scan.get("ts"), "cars": scan.get("cars"), "used": scan.get("used"), "photos_used": scan.get("photos_used"),
                         "repeats": len(flags["repeat_of"]), "jumps": len({"|".join(sorted((k, j["key"]))) for k, v in flags["jump"].items() for j in v}),
                         "mixed": len(flags["mixed"]), "stale": edits > 0, "edits": edits}
        by_class = Counter((self._class_of(k)[0] or "unset") for k in counts)
        suggest = self._read(self.suggest_path, None)
        suggest_info = ({"ts": suggest.get("ts"), "weights": suggest.get("weights"), "count": len(self._suggested())}
                        if isinstance(suggest, dict) else None)
        try:
            busy = bool(self.is_training())
        except Exception:
            busy = True
        return {"analyses": len({k.split("/")[0] for k in counts}), "cars": len(counts), "photos": sum(counts.values()),
                "small": sum(1 for n in counts.values() if n < 2), "temporary": len(temp), "temporary_photos": sum(temp.values()),
                "classes": dict(by_class), "class_list": list(CLASSES), "suggest": suggest_info, "scan": scan_info, "can_undo": bool(self._live_actions()),
                "training": busy, "job": self._running_job(), "removed": self._removed_count()}

    def cars(self, analysis: str | None = None, flt: str = "all", q: str = "", cls: str | None = None) -> dict:
        if flt not in FILTERS:
            raise ViewerError(f"unknown filter: {flt!r}")
        if analysis:
            safe_name(analysis)
        if cls and cls != "unset" and cls not in CLASSES:
            raise ViewerError(f"unknown class: {cls!r}")
        listing = [(k, p, t, self._photos_in(p)) for k, p, t in self._all_cars()]
        flags = self._flags(self._scan(), {k for k, _, t, _ in listing if not t})
        per_analysis: dict[str, dict] = {}
        for key, _, temporary, names in listing:
            a = key.split("/")[0]
            row = per_analysis.setdefault(a, {"id": a, "short": a[:8], "cars": 0, "photos": 0, "flagged": 0, "temporary": 0})
            if temporary:
                row["temporary"] += 1
                continue
            row["cars"] += 1
            row["photos"] += len(names)
            if key in flags["jump"] or key in flags["mixed"]:
                row["flagged"] += 1
        needle = (q or "").strip().lower()
        out = []
        for key, _, temporary, names in listing:
            a, c = key.split("/")
            if analysis and a != analysis:
                continue
            if needle and needle not in key.lower():
                continue
            klass, source = self._class_of(key)
            if cls == "unset" and klass:
                continue
            if cls and cls != "unset" and klass != cls:
                continue
            jump, mixed, repeat = flags["jump"].get(key), flags["mixed"].get(key), flags["repeat_of"].get(key)
            if flt == "temporary" and not temporary:
                continue
            if flt != "temporary" and flt != "all" and temporary:
                continue
            if flt == "flagged" and not (jump or mixed):
                continue
            if flt == "jumps" and not jump:
                continue
            if flt == "mixed" and mixed is None:
                continue
            if flt == "repeats" and not repeat:
                continue
            if flt == "small" and len(names) >= 2:
                continue
            if flt == "used" and (repeat or len(names) < 2):
                continue
            out.append({"key": key, "analysis": a, "car": c, "photos": len(names), "thumb": names[len(names) // 2] if names else None,
                        "jump": jump or [], "mixed": mixed, "repeat_of": repeat, "repeats": flags["kept_by"].get(key, []),
                        "small": len(names) < 2, "temporary": temporary, "class": klass, "class_source": source})
        return {"analyses": sorted(per_analysis.values(), key=lambda r: r["id"]), "cars": out}

    def car(self, key: str) -> dict:
        folder = self._car_dir(key)
        if not folder.is_dir():
            raise NotFound(key)
        analysis = key.split("/")[0]
        listing = [(k, self._photos_in(p), t) for k, p, t in self._all_cars()]
        flags = self._flags(self._scan(), {k for k, _, t in listing if not t})
        names = self._photos_in(folder)
        siblings = []
        for k, n, t in listing:
            if k.split("/")[0] == analysis and k != key:
                klass, _ = self._class_of(k)
                siblings.append({"key": k, "photos": len(n), "thumb": n[len(n) // 2] if n else None, "temporary": t, "class": klass})
        partners = {j["key"]: j["alike"] for j in flags["jump"].get(key, [])}
        siblings.sort(key=lambda s: (-partners.get(s["key"], 0), s["key"]))
        for s in siblings:
            s["alike"] = partners.get(s["key"])
        repeat = flags["repeat_of"].get(key)
        klass, source = self._class_of(key)
        return {"key": key, "analysis": analysis, "car": key.split("/")[1], "photos": names, "temporary": self._is_temp(key),
                "class": klass, "class_source": source, "jump": flags["jump"].get(key, []), "mixed": flags["mixed"].get(key),
                "repeat_of": repeat, "repeats": flags["kept_by"].get(key, []), "siblings": siblings}

    def photo_file(self, key: str, name: str, thumbnail: bool = False) -> Path:
        path = self._car_dir(key) / safe_image_name(name)
        if not path.is_file():
            raise NotFound(f"{key}/{name}")
        return self._thumbnail(path, f"reid/{key}/{name}") if thumbnail else path

    def removed_file(self, reason: str, analysis: str, car: str, name: str, thumbnail: bool = False) -> Path:
        path = self.qroot / safe_reason(reason) / safe_name(analysis) / safe_name(car) / safe_image_name(name)
        if not path.is_file():
            raise NotFound(f"{reason}/{analysis}/{car}/{name}")
        return self._thumbnail(path, f"reid_q/{reason}/{analysis}/{car}/{name}") if thumbnail else path

    def _thumbnail(self, source: Path, key: str) -> Path:
        if self._thumb is None:
            return source
        return self._thumb(source, key.replace("/", "__"))

    def removed(self) -> dict:
        items = []
        if self.qroot.is_dir():
            for reason in sorted(p for p in self.qroot.iterdir() if p.is_dir()):
                for a in sorted(p for p in reason.iterdir() if p.is_dir()):
                    for c in sorted(p for p in a.iterdir() if p.is_dir()):
                        for name in self._photos_in(c):
                            items.append({"reason": reason.name, "analysis": a.name, "car": c.name, "name": name})
        return {"items": items}

    def _removed_count(self) -> int:
        return len(self.removed()["items"]) if self.qroot.is_dir() else 0

    # ----------------------------------------------------------------- "most alike" suggestions (quick, no model)

    def _look(self, path: Path):
        try:
            mtime = path.stat().st_mtime
        except OSError:
            return None
        cached = self._looks.get(str(path))
        if cached and cached[0] == mtime:
            return cached[1]
        import cv2
        from harvest_tool.pairs import look
        image = cv2.imread(str(path))
        value = look(image) if image is not None else None
        self._looks[str(path)] = (mtime, value)
        return value

    def similar(self, key: str, photos=None) -> dict:
        """The other vehicles of the same analysis, most alike first: for each selected photo (or the whole vehicle) its best match among
        the other vehicle's photos, averaged. Colour layout only: a hint to look at, never a decision."""
        folder = self._car_dir(key)
        if not folder.is_dir():
            raise NotFound(key)
        analysis = key.split("/")[0]
        names = self._photos_in(folder)
        if photos is not None:
            if not isinstance(photos, list) or not photos:
                raise ViewerError("choose at least one photo")
            chosen = [safe_image_name(n) for n in photos]
            if any(n not in names for n in chosen):
                raise NotFound("a photo that is not in this vehicle")
            names = chosen
        from harvest_tool.pairs import how_alike
        mine = [v for v in (self._look(folder / n) for n in _spread(names, 6)) if v is not None]
        out = []
        for k, path, temporary in self._all_cars():
            if k == key or k.split("/")[0] != analysis:
                continue
            theirs_names = self._photos_in(path)
            theirs = [v for v in (self._look(path / n) for n in _spread(theirs_names, 4)) if v is not None]
            score = (sum(max(how_alike(a, b) for b in theirs) for a in mine) / len(mine)) if mine and theirs else 0.0
            klass, _ = self._class_of(k)
            out.append({"key": k, "alike": round(float(score), 3), "photos": len(theirs_names), "temporary": temporary, "class": klass,
                        "thumb": theirs_names[len(theirs_names) // 2] if theirs_names else None})
        out.sort(key=lambda r: (-r["alike"], r["key"]))
        return {"key": key, "vehicles": out}

    # ----------------------------------------------------------------- writing

    def _record(self, op: str, **data) -> dict:
        entry = {"id": uuid.uuid4().hex[:12], "ts": time.time(), "op": op, **data}
        self._actions.append(entry)
        self._save()
        return entry

    def _do_moves(self, moves: list[dict]) -> None:
        """Move files (each {"from": rel, "to": rel}); if one fails, every move already made is taken back."""
        done = []
        try:
            for m in moves:
                src, dst = self._abs(m["from"]), self._abs(m["to"])
                if not src.is_file():
                    raise NotFound(m["from"])
                if dst.exists():
                    raise ViewerError(f"{dst.name} is already in {dst.parent.name}: nothing was changed")
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(src), str(dst))
                done.append(m)
        except Exception:
            for m in reversed(done):
                try:
                    shutil.move(str(self._abs(m["to"])), str(self._abs(m["from"])))
                except OSError:
                    pass
            raise

    def _tidy(self, folders: set[Path]) -> list[str]:
        """Folders left with nothing in them are not vehicles."""
        gone = []
        for f in folders:
            try:
                if f.is_dir() and not any(f.iterdir()):
                    f.rmdir()
                    gone.append(self._rel(f))
            except OSError:
                pass
        return gone

    def _vanished_classes(self, folders: set[Path]) -> dict[str, str]:
        """Classes YOU set on vehicles whose folder is gone now (emptied by a move / merge / remove): undo gives them back."""
        out = {}
        for f in folders:
            key = f"{f.parent.name}/{f.name}"
            if key in self._classes and not f.is_dir() and not self._car_dir(key).is_dir():
                out[key] = self._classes[key]
        return out

    def _refs(self, photos) -> list[tuple[str, str]]:
        if not isinstance(photos, list) or not photos:
            raise ViewerError("choose at least one photo")
        refs = []
        for p in photos:
            if not isinstance(p, dict):
                raise ViewerError("a photo is {car, name}")
            _split(p.get("car"))
            refs.append((p["car"], safe_image_name(p.get("name"))))
        return list(dict.fromkeys(refs))

    def _new_car_label(self, analysis: str) -> str:
        n = 1
        while any((base / analysis / f"{analysis[:8]}_manual{n}").exists() for base in (self.images, self.temp)):
            n += 1
        return f"{analysis[:8]}_manual{n}"

    def move(self, photos, to: str | None = None, temporary: bool = False) -> dict:
        """Move photos to another vehicle of the SAME analysis, or (to=None) into a NEW vehicle: its own, or (temporary=True) one that is set
        aside in the temporary area (not trained on) until it is kept or merged. A tracker jump happens inside one analysis."""
        with self._lock:
            self._guard()
            refs = self._refs(photos)
            analyses = {c.split("/")[0] for c, _ in refs}
            if len(analyses) != 1:
                raise ViewerError("photos can only be moved inside one analysis")
            analysis = analyses.pop()
            if to is None:
                label = self._new_car_label(analysis)
                dest_key = f"{analysis}/{label}"
                dest_dir = (self.temp if temporary else self.images) / analysis / label
            else:
                dest_key = to
                if _split(to)[0] != analysis:
                    raise ViewerError("a photo can only move to a vehicle of the same analysis")
                dest_dir = self._car_dir(to)
                if not dest_dir.is_dir():
                    raise NotFound(to)
            moves, sources = [], set()
            for car, name in refs:
                if car == dest_key:
                    continue
                src = self._car_dir(car) / name
                moves.append({"from": self._rel(src), "to": self._rel(dest_dir / name)})
                sources.add(self._car_dir(car))
            if not moves:
                raise ViewerError("those photos are already in that vehicle")
            inherit = self._class_of(refs[0][0])[0] if to is None else None
            self._do_moves(moves)
            gone = self._tidy(sources)
            class_restore = self._vanished_classes(sources)
            class_set = {}
            if inherit:                                                    # a split-off vehicle starts with the class of the one it came from
                self._classes[dest_key] = inherit
                class_set[dest_key] = inherit
                self._save_classes()
            self._save_classes()
            entry = self._record("move", moves=moves, rmdirs=gone, dest=dest_key, created=to is None, class_set=class_set,
                                 class_restore=class_restore)
            self._decide("moved", {dest_key: [self._in_reid(m["to"]) for m in moves]})
            return {"ok": True, "moved": len(moves), "to": dest_key, "created": to is None, "temporary": dest_dir.is_relative_to(self.temp),
                    "id": entry["id"], "can_undo": True}

    def merge(self, keys, into: str) -> dict:
        """Everything of the other vehicles goes into `into` (same analysis, trained-on or temporary); their folders go away."""
        with self._lock:
            self._guard()
            if not isinstance(keys, list) or not keys:
                raise ViewerError("choose the vehicles to merge")
            analysis, _ = _split(into)
            into_dir = self._car_dir(into)
            if not into_dir.is_dir():
                raise NotFound(into)
            moves, sources = [], set()
            for key in dict.fromkeys(keys):
                if key == into:
                    continue
                if _split(key)[0] != analysis:
                    raise ViewerError("vehicles can only be merged inside one analysis")
                folder = self._car_dir(key)
                if not folder.is_dir():
                    raise NotFound(key)
                for name in self._photos_in(folder):
                    moves.append({"from": self._rel(folder / name), "to": self._rel(into_dir / name)})
                sources.add(folder)
            if not moves:
                raise ViewerError("there is nothing to merge")
            self._do_moves(moves)
            gone = self._tidy(sources)
            class_restore = self._vanished_classes(sources)
            entry = self._record("merge", moves=moves, rmdirs=gone, dest=into, class_restore=class_restore)
            self._decide("merge", {into: [self._in_reid(self._rel(into_dir / n)) for n in self._photos_in(into_dir)]})
            self._save_classes()
            return {"ok": True, "moved": len(moves), "to": into, "id": entry["id"], "can_undo": True}

    def _relocate(self, keys, to_temp: bool) -> dict:
        with self._lock:
            self._guard()
            if not isinstance(keys, list) or not keys:
                raise ViewerError("choose the vehicles")
            moves, sources = [], set()
            for key in dict.fromkeys(keys):
                perm, tmp = self._dirs(key)
                src, dest = (perm, tmp) if to_temp else (tmp, perm)
                if not src.is_dir():
                    raise ViewerError(f"{key.split('/')[1]} is not " + ("a trained-on vehicle" if to_temp else "set aside"))
                if dest.exists():
                    raise ViewerError(f"{key.split('/')[1]} already exists there: nothing was changed")
                for name in self._photos_in(src):
                    moves.append({"from": self._rel(src / name), "to": self._rel(dest / name)})
                sources.add(src)
            if not moves:
                raise ViewerError("there is nothing to move")
            self._do_moves(moves)
            gone = self._tidy(sources)
            entry = self._record("hold" if to_temp else "keep", moves=moves, rmdirs=gone)
            return {"ok": True, "moved": len(moves), "vehicles": len(sources), "id": entry["id"], "can_undo": True}

    def hold(self, keys) -> dict:
        """Set whole vehicles aside (temporary): not trained on, nothing lost."""
        return self._relocate(keys, True)

    def keep(self, keys) -> dict:
        """A set-aside vehicle becomes a vehicle of its own that is trained on."""
        return self._relocate(keys, False)

    def set_class(self, keys, cls) -> dict:
        """Set the class of one or more vehicles (cls None / "" / "auto" goes back to the tickets' class)."""
        with self._lock:
            self._guard()
            if not isinstance(keys, list) or not keys:
                raise ViewerError("choose the vehicles")
            if cls in (None, "", "auto"):
                cls = None
            elif cls not in CLASSES:
                raise ViewerError(f"unknown class: {cls!r}")
            keys = list(dict.fromkeys(keys))
            for key in keys:
                if not self._car_dir(key).is_dir():
                    raise NotFound(key)
            before = {k: self._classes.get(k) for k in keys}
            for k in keys:
                if cls is None:
                    self._classes.pop(k, None)
                else:
                    self._classes[k] = cls
            self._save_classes()
            entry = self._record("class", before=before, after=cls)
            return {"ok": True, "changed": len(keys), "id": entry["id"], "can_undo": True}

    def remove(self, photos, reason: str = DEFAULT_REASON) -> dict:
        """Take photos out of the data (quarantine, reversible)."""
        with self._lock:
            self._guard()
            reason = safe_reason(reason)
            refs = self._refs(photos)
            moves, sources = [], set()
            for car, name in refs:
                src = self._car_dir(car) / name
                analysis, label = _split(car)
                moves.append({"from": self._rel(src), "to": self._rel(self.qroot / reason / analysis / label / name)})
                sources.add(self._car_dir(car))
            self._do_moves(moves)
            gone = self._tidy(sources)
            class_restore = self._vanished_classes(sources)
            entry = self._record("remove", moves=moves, rmdirs=gone, reason=reason, class_restore=class_restore)
            self._save_classes()
            return {"ok": True, "moved": len(moves), "id": entry["id"], "can_undo": True}

    def remove_cars(self, keys, reason: str = DEFAULT_REASON) -> dict:
        """A whole folder that is not a vehicle (or not worth keeping)."""
        with self._lock:
            if not isinstance(keys, list) or not keys:
                raise ViewerError("choose the vehicles to remove")
            photos = []
            for key in dict.fromkeys(keys):
                folder = self._car_dir(key)
                if not folder.is_dir():
                    raise NotFound(key)
                photos += [{"car": key, "name": n} for n in self._photos_in(folder)]
            return self.remove(photos, reason) if photos else {"ok": True, "moved": 0, "can_undo": bool(self._live_actions())}

    def restore(self, items) -> dict:
        """Put removed photos back into the vehicle they came from (where it is now: trained-on or set aside)."""
        with self._lock:
            self._guard()
            if not isinstance(items, list) or not items:
                raise ViewerError("choose at least one removed photo")
            moves = []
            for it in items:
                if not isinstance(it, dict):
                    raise ViewerError("a removed photo is {reason, analysis, car, name}")
                reason, analysis, car, name = (safe_reason(it.get("reason")), safe_name(it.get("analysis")), safe_name(it.get("car")),
                                               safe_image_name(it.get("name")))
                src = self.qroot / reason / analysis / car / name
                moves.append({"from": self._rel(src), "to": self._rel(self._car_dir(f"{analysis}/{car}") / name)})
            self._do_moves(moves)
            self._tidy({self._abs(m["from"]).parent for m in moves})
            entry = self._record("restore", moves=moves, rmdirs=[])
            return {"ok": True, "moved": len(moves), "id": entry["id"], "can_undo": True}

    def dismiss(self, a: str, b: str) -> dict:
        """'These two are NOT the same vehicle': the suspect goes away and Harvest > Same car? will not ask about the pair."""
        with self._lock:
            _split(a), _split(b)
            pair = "|".join(sorted((a, b)))
            if pair in self._dismissed:
                return {"ok": True, "can_undo": bool(self._live_actions())}
            self._dismissed.add(pair)
            entry = self._record("dismiss", pair=pair)
            self._decide("not_same", {a: [], b: []})
            return {"ok": True, "id": entry["id"], "can_undo": True}

    def undo(self) -> dict:
        with self._lock:
            self._guard()
            live = self._live_actions()
            if not live:
                raise ViewerError("there is nothing to undo")
            entry = live[-1]
            if entry["op"] == "dismiss":
                self._dismissed.discard(entry["pair"])
            elif entry["op"] == "class":
                for key, old in entry["before"].items():
                    if old:
                        self._classes[key] = old
                    else:
                        self._classes.pop(key, None)
                self._save_classes()
            else:
                back = [{"from": m["to"], "to": m["from"]} for m in reversed(entry["moves"])]
                self._do_moves(back)
                for rel in entry.get("rmdirs", []):                      # folders that were emptied come back with their photos
                    self._abs(rel).mkdir(parents=True, exist_ok=True)
                self._tidy({self._abs(m["from"]).parent for m in back})
                for key in entry.get("class_set", {}):                   # the class a split-off vehicle was given goes with it
                    self._classes.pop(key, None)
                for key, klass in entry.get("class_restore", {}).items():  # the class of a vehicle that came back
                    self._classes[key] = klass
                if entry.get("class_set") or entry.get("class_restore"):
                    self._save_classes()
            entry["undone"] = True
            self._save()
            return {"ok": True, "undid": entry["op"], "can_undo": bool(self._live_actions())}

    # ----------------------------------------------------------------- the scan (what to look at)

    def _running_job(self) -> dict | None:
        for job in self._jobs.values():
            if job["state"] == "running":
                return dict(job)
        return None

    def _run_scan_process(self, out: Path, training: bool) -> str:
        cmd = [sys.executable, str(SCAN_SCRIPT), "--scan", str(out)] + (["--cpu"] if training else [])
        flags = getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0)
        proc = subprocess.run(cmd, cwd=str(LAB), capture_output=True, text=True, creationflags=flags)
        if proc.returncode != 0:
            raise RuntimeError((proc.stderr or proc.stdout or "the scan failed").strip().splitlines()[-1][:300])
        return (proc.stdout or "").strip().splitlines()[-1] if proc.stdout.strip() else "done"

    def _run_suggest_process(self, out: Path, training: bool) -> str:
        cmd = [sys.executable, str(SUGGEST_SCRIPT), "--out", str(out)] + (["--cpu"] if training else [])
        flags = getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0)
        proc = subprocess.run(cmd, cwd=str(LAB), capture_output=True, text=True, creationflags=flags)
        if proc.returncode != 0:
            raise RuntimeError((proc.stderr or proc.stdout or "the suggestion failed").strip().splitlines()[-1][:300])
        return (proc.stdout or "").strip().splitlines()[-1] if proc.stdout.strip() else "done"

    def _start_job(self, kind: str, text: str, runner, target: Path) -> dict:
        with self._lock:
            running = self._running_job()
            if running:
                return running
            job = {"id": uuid.uuid4().hex[:12], "kind": kind, "state": "running", "text": text, "started": time.time()}
            self._jobs[job["id"]] = job
            try:
                training = bool(self.is_training())
            except Exception:
                training = True

            def work():
                out = self.cache / f"reid_{kind}_{job['id']}.tmp"
                try:
                    self.cache.mkdir(parents=True, exist_ok=True)
                    said = runner(out, training)
                    data = json.loads(out.read_text(encoding="utf-8"))
                    _atomic(target, json.dumps(data))
                    job.update(state="done", text=said or "done")
                except Exception as e:
                    job.update(state="error", text=f"{type(e).__name__}: {e}")
                finally:
                    try:
                        out.unlink()
                    except OSError:
                        pass

            threading.Thread(target=work, daemon=True).start()
            return dict(job)

    def start_scan(self) -> dict:
        return self._start_job("scan", "Looking at every vehicle with the matcher (about a minute)...", self._scan_runner, self.scan_path)

    def start_suggest(self) -> dict:
        """Ask the vehicle model for a class for the vehicles (about a minute). A class you set always wins over its suggestion."""
        return self._start_job("suggest", "Asking the vehicle model what each vehicle is (about a minute)...", self._suggest_runner,
                               self.suggest_path)

    def job(self, job_id: str) -> dict:
        job = self._jobs.get(job_id)
        if not job:
            raise NotFound(f"no such job: {job_id!r}")
        return dict(job)

    # ----------------------------------------------------------------- the entry in the Datasets list

    def entry(self) -> dict:
        s = self.summary()
        return {"name": "reid", "kind": "reid", "title": "Car matcher (ReID)", "classes": [], "training": s["training"],
                "index": {"state": "ready", "progress": {"done": 1, "total": 1}}, "images": None, "total": s["photos"],
                "cars": s["cars"], "temporary": s["temporary"], "ph_share": None, "warnings": [], "card_stale": False}
