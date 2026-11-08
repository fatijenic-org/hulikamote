"""
reid.py - The Car matcher (ReID) manager of the Dataset Viewer: clean datasets/reid before the matcher is trained on it.

datasets/reid/images/<analysis>/<car>/*.jpg is one folder per car, and the folder IS the label. When the tracker jumps (one car gets a
new number) the car is filed as two folders; when it swaps (two cars share a number) one folder holds two cars. This lets a person fix both:
move photos between the cars of one analysis, merge cars, take bad photos out.

Same rules as the rest of the viewer:
  * nothing is deleted: removed photos go to datasets/_quarantine/reid/<reason>/<analysis>/<car>/ and can be restored;
  * every change is written to dataset_viewer_cache/reid_actions.json with what is needed to undo it (in order);
  * no write while train_reid.py runs;
  * names that reach the disk are validated; nothing is written inside hulikamote_backend/.
Every move / merge is also noted in datasets/reid/decisions.jsonl ("source": "manager") like the review screens do, and "not the same"
answers there keep the Harvest > Same car? questions from asking about that pair again.

Suspects (repeats, jumps, mixed folders) come from `train_reid.py --scan`: the matcher's own fingerprints, one scan of about a minute.
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
from pathlib import Path

from .app import LAB, NotFound, TrainingBusy, ViewerError, safe_image_name, safe_name, safe_reason

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
DEFAULT_REASON = "removed_in_manager"
KEEP_ACTIONS = 500
FILTERS = ("all", "flagged", "jumps", "repeats", "mixed", "small", "used")
SCAN_SCRIPT = LAB / "scripts" / "train_reid.py"


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
        raise ViewerError(f"not a car: {key!r}")
    analysis, car = key.split("/")
    return safe_name(analysis), safe_name(car)


def _atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.{threading.get_ident()}.tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


class ReidManager:
    def __init__(self, datasets: Path, cache: Path, training_check=None, thumb=None, scan_runner=None):
        self.datasets = Path(datasets)
        self.root = self.datasets / "reid"
        self.images = self.root / "images"
        self.qroot = self.datasets / "_quarantine" / "reid"
        self.decisions = self.root / "decisions.jsonl"
        self.cache = Path(cache)
        self.log_path = self.cache / "reid_actions.json"
        self.scan_path = self.cache / "reid_scan.json"
        self.dismiss_path = self.cache / "reid_dismissed.json"
        self.is_training = training_check or default_training_check
        self._thumb = thumb
        self._scan_runner = scan_runner or self._run_scan_process
        self._lock = threading.RLock()
        self._jobs: dict[str, dict] = {}
        self._actions: list[dict] = self._read(self.log_path, [])
        self._dismissed: set[str] = set(self._read(self.dismiss_path, []))

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
        """datasets/-relative -> datasets/reid-relative, the paths decisions.jsonl holds (images/<analysis>/<car>/<file>)."""
        return rel[len("reid/"):] if rel.startswith("reid/") else rel

    def _abs(self, rel: str) -> Path:
        path = (self.datasets / rel).resolve()
        path.relative_to(self.datasets.resolve())                       # a path from the log can never leave the datasets folder
        return path

    def _car_dir(self, key: str) -> Path:
        analysis, car = _split(key)
        return self.images / analysis / car

    @staticmethod
    def _photos_in(folder: Path) -> list[str]:
        try:
            return sorted(f.name for f in folder.iterdir() if f.is_file() and f.suffix.lower() in IMAGE_EXT)
        except OSError:
            return []

    def _all_cars(self) -> list[tuple[str, Path]]:
        out = []
        if not self.images.is_dir():
            return out
        for a in sorted(p for p in self.images.iterdir() if p.is_dir()):
            for c in sorted(p for p in a.iterdir() if p.is_dir()):
                out.append((f"{a.name}/{c.name}", c))
        return out

    def _decide(self, kind: str, identities: dict[str, list[str]]) -> None:
        """One line in decisions.jsonl, the format the review screens and the harvest tool write."""
        analysis = next((k.split("/")[0] for k in identities if "/" in k), "")
        lines = {}
        for key, rels in identities.items():
            lines[key.split("/")[-1]] = rels
        with open(self.decisions, "a", encoding="utf-8") as f:
            f.write(json.dumps({"ts": time.time(), "kind": kind, "task_id": analysis, "identities": lines,
                                "source": "manager"}) + "\n")

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
        """What the last scan said about each car (only about folders that still exist)."""
        flags = {"repeat_of": {}, "kept_by": {}, "jump": {}, "mixed": {}, "used": set()}
        if not scan:
            return flags
        for r in scan.get("repeats", []):
            if r["dropped"] in present and r["kept"] in present:
                flags["repeat_of"][r["dropped"]] = r["kept"]
                flags["kept_by"].setdefault(r["kept"], []).append(r["dropped"])
        for j in scan.get("jumps", []):
            a, b = j["a"], j["b"]
            if a in present and b in present and "|".join(sorted((a, b))) not in self._dismissed:
                flags["jump"].setdefault(a, []).append({"key": b, "alike": j["alike"]})
                flags["jump"].setdefault(b, []).append({"key": a, "alike": j["alike"]})
        for m in scan.get("mixed", []):
            if m["car"] in present:
                flags["mixed"][m["car"]] = m["share"]
        repeats = set(flags["repeat_of"])
        flags["used"] = {k for k in present if k not in repeats}
        return flags

    def summary(self) -> dict:
        cars = self._all_cars()
        counts = {k: len(self._photos_in(p)) for k, p in cars}
        scan = self._scan()
        present = set(counts)
        flags = self._flags(scan, present)
        edits = self._edits_since_scan(scan)
        scan_info = None
        if scan:
            scan_info = {"ts": scan.get("ts"), "cars": scan.get("cars"), "used": scan.get("used"), "photos_used": scan.get("photos_used"),
                         "repeats": len(flags["repeat_of"]), "jumps": len({"|".join(sorted((k, j["key"]))) for k, v in flags["jump"].items() for j in v}),
                         "mixed": len(flags["mixed"]), "stale": edits > 0, "edits": edits}
        try:
            busy = bool(self.is_training())
        except Exception:
            busy = True
        return {"analyses": len({k.split("/")[0] for k in counts}), "cars": len(counts), "photos": sum(counts.values()),
                "small": sum(1 for n in counts.values() if n < 2), "scan": scan_info, "can_undo": bool(self._live_actions()),
                "training": busy, "job": self._running_job(), "removed": self._removed_count()}

    def cars(self, analysis: str | None = None, flt: str = "all", q: str = "") -> dict:
        if flt not in FILTERS:
            raise ViewerError(f"unknown filter: {flt!r}")
        if analysis:
            safe_name(analysis)
        listing = [(k, p, self._photos_in(p)) for k, p in self._all_cars()]
        present = {k for k, _, _ in listing}
        flags = self._flags(self._scan(), present)
        per_analysis: dict[str, dict] = {}
        for key, _, names in listing:
            a = key.split("/")[0]
            row = per_analysis.setdefault(a, {"id": a, "short": a[:8], "cars": 0, "photos": 0, "flagged": 0})
            row["cars"] += 1
            row["photos"] += len(names)
            if key in flags["jump"] or key in flags["mixed"]:
                row["flagged"] += 1
        needle = (q or "").strip().lower()
        out = []
        for key, _, names in listing:
            a, c = key.split("/")
            if analysis and a != analysis:
                continue
            if needle and needle not in key.lower():
                continue
            jump, mixed, repeat = flags["jump"].get(key), flags["mixed"].get(key), flags["repeat_of"].get(key)
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
                        "small": len(names) < 2})
        return {"analyses": sorted(per_analysis.values(), key=lambda r: r["id"]), "cars": out}

    def car(self, key: str) -> dict:
        folder = self._car_dir(key)
        if not folder.is_dir():
            raise NotFound(key)
        analysis = key.split("/")[0]
        listing = [(k, self._photos_in(p)) for k, p in self._all_cars()]
        present = {k for k, _ in listing}
        flags = self._flags(self._scan(), present)
        names = self._photos_in(folder)
        siblings = [{"key": k, "photos": len(n), "thumb": n[len(n) // 2] if n else None} for k, n in listing
                    if k.split("/")[0] == analysis and k != key]
        partners = {j["key"]: j["alike"] for j in flags["jump"].get(key, [])}
        siblings.sort(key=lambda s: (-partners.get(s["key"], 0), s["key"]))
        for s in siblings:
            s["alike"] = partners.get(s["key"])
        repeat = flags["repeat_of"].get(key)
        return {"key": key, "analysis": analysis, "car": key.split("/")[1], "photos": names,
                "jump": flags["jump"].get(key, []), "mixed": flags["mixed"].get(key), "repeat_of": repeat,
                "repeats": flags["kept_by"].get(key, []), "siblings": siblings}

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
        """Folders left with nothing in them are not cars."""
        gone = []
        for f in folders:
            try:
                if f.is_dir() and not any(f.iterdir()):
                    f.rmdir()
                    gone.append(self._rel(f))
            except OSError:
                pass
        return gone

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
        while (self.images / analysis / f"{analysis[:8]}_manual{n}").exists():
            n += 1
        return f"{analysis[:8]}_manual{n}"

    def move(self, photos, to: str | None = None) -> dict:
        """Move photos to another car of the SAME analysis, or (to=None) into a new car. A tracker jump happens inside one analysis."""
        with self._lock:
            self._guard()
            refs = self._refs(photos)
            analyses = {c.split("/")[0] for c, _ in refs}
            if len(analyses) != 1:
                raise ViewerError("photos can only be moved inside one analysis")
            analysis = analyses.pop()
            if to is None:
                dest_key = f"{analysis}/{self._new_car_label(analysis)}"
            else:
                dest_key = to
                if _split(to)[0] != analysis:
                    raise ViewerError("a photo can only move to a car of the same analysis")
                if not self._car_dir(to).is_dir():
                    raise NotFound(to)
            moves, sources = [], set()
            for car, name in refs:
                if car == dest_key:
                    continue
                src = self._car_dir(car) / name
                moves.append({"from": self._rel(src), "to": self._rel(self._car_dir(dest_key) / name)})
                sources.add(self._car_dir(car))
            if not moves:
                raise ViewerError("those photos are already in that car")
            self._do_moves(moves)
            gone = self._tidy(sources)
            entry = self._record("move", moves=moves, rmdirs=gone, dest=dest_key, created=to is None)
            self._decide("moved", {dest_key: [self._in_reid(m["to"]) for m in moves]})
            return {"ok": True, "moved": len(moves), "to": dest_key, "created": to is None, "id": entry["id"], "can_undo": True}

    def merge(self, keys, into: str) -> dict:
        """Everything of the other cars goes into `into` (same analysis); their folders go away."""
        with self._lock:
            self._guard()
            if not isinstance(keys, list) or not keys:
                raise ViewerError("choose the cars to merge")
            analysis, _ = _split(into)
            if not self._car_dir(into).is_dir():
                raise NotFound(into)
            moves, sources = [], set()
            for key in dict.fromkeys(keys):
                if key == into:
                    continue
                if _split(key)[0] != analysis:
                    raise ViewerError("cars can only be merged inside one analysis")
                folder = self._car_dir(key)
                if not folder.is_dir():
                    raise NotFound(key)
                for name in self._photos_in(folder):
                    moves.append({"from": self._rel(folder / name), "to": self._rel(self._car_dir(into) / name)})
                sources.add(folder)
            if not moves:
                raise ViewerError("there is nothing to merge")
            self._do_moves(moves)
            gone = self._tidy(sources)
            entry = self._record("merge", moves=moves, rmdirs=gone, dest=into)
            self._decide("merge", {into: [self._in_reid(self._rel(self._car_dir(into) / n)) for n in self._photos_in(self._car_dir(into))]})
            return {"ok": True, "moved": len(moves), "to": into, "id": entry["id"], "can_undo": True}

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
            entry = self._record("remove", moves=moves, rmdirs=gone, reason=reason)
            return {"ok": True, "moved": len(moves), "id": entry["id"], "can_undo": True}

    def remove_cars(self, keys, reason: str = DEFAULT_REASON) -> dict:
        """A whole folder that is not a car (or not worth keeping)."""
        with self._lock:
            if not isinstance(keys, list) or not keys:
                raise ViewerError("choose the cars to remove")
            photos = []
            for key in dict.fromkeys(keys):
                folder = self._car_dir(key)
                if not folder.is_dir():
                    raise NotFound(key)
                photos += [{"car": key, "name": n} for n in self._photos_in(folder)]
            return self.remove(photos, reason) if photos else {"ok": True, "moved": 0, "can_undo": bool(self._live_actions())}

    def restore(self, items) -> dict:
        """Put removed photos back into the car they came from."""
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
                moves.append({"from": self._rel(src), "to": self._rel(self.images / analysis / car / name)})
            self._do_moves(moves)
            self._tidy({self._abs(m["from"]).parent for m in moves})
            entry = self._record("restore", moves=moves, rmdirs=[])
            return {"ok": True, "moved": len(moves), "id": entry["id"], "can_undo": True}

    def dismiss(self, a: str, b: str) -> dict:
        """'These two are NOT the same car': the suspect goes away and Harvest > Same car? will not ask about the pair."""
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
            else:
                back = [{"from": m["to"], "to": m["from"]} for m in reversed(entry["moves"])]
                self._do_moves(back)
                for rel in entry.get("rmdirs", []):                      # folders that were emptied come back with their photos
                    self._abs(rel).mkdir(parents=True, exist_ok=True)
                self._tidy({self._abs(m["from"]).parent for m in back})
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

    def start_scan(self) -> dict:
        with self._lock:
            running = self._running_job()
            if running:
                return running
            job = {"id": uuid.uuid4().hex[:12], "kind": "scan", "state": "running", "text": "Looking at every car with the matcher "
                   "(about a minute)...", "started": time.time()}
            self._jobs[job["id"]] = job
            try:
                training = bool(self.is_training())
            except Exception:
                training = True

            def work():
                out = self.cache / f"reid_scan_{job['id']}.tmp"
                try:
                    self.cache.mkdir(parents=True, exist_ok=True)
                    text = self._scan_runner(out, training)
                    data = json.loads(out.read_text(encoding="utf-8"))
                    _atomic(self.scan_path, json.dumps(data))
                    job.update(state="done", text=text or "done")
                except Exception as e:
                    job.update(state="error", text=f"{type(e).__name__}: {e}")
                finally:
                    try:
                        out.unlink()
                    except OSError:
                        pass

            threading.Thread(target=work, daemon=True).start()
            return dict(job)

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
                "cars": s["cars"], "ph_share": None, "warnings": [], "card_stale": False}
