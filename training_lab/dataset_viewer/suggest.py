"""
suggest.py - "Suggested pickups": learn from the boxes a person already decided, then rank the boxes nobody looked at.

How: the person marked some boxes "this is a pickup" and others "not a pickup" (the journal, data_tools/decisions.py). Each box
is cut out and turned into 512 numbers by the car matcher's network (embed.py, already installed). A small logistic regression is
trained on the marked boxes and scores every box that was not looked at. The page shows them best-first.

A suggestion is NEVER applied by itself. It only orders the boxes; the person picks and confirms, like any other relabel.
"""
from __future__ import annotations

import json
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path

from data_tools import decisions

MIN_EACH = 100                 # marked pickups AND marked not-pickups needed before a suggestion is worth showing
HOLDOUT = 0.2                  # share of the marked boxes kept back to check the classifier on boxes it never trained on
LAB = Path(__file__).resolve().parents[1]
EMBED_SCRIPT = Path(__file__).with_name("embed.py")


def embed_in_subprocess(paths: list[str], progress, cache_dir: Path) -> "np.ndarray":
    """Default embedder: runs embed.py as its own process (torch stays out of the viewer) and follows its progress file."""
    import numpy as np
    cache_dir.mkdir(parents=True, exist_ok=True)
    token = uuid.uuid4().hex[:8]
    listing, out, prog = (cache_dir / f"_emb_{token}.json", cache_dir / f"_emb_{token}.npy", cache_dir / f"_emb_{token}.progress")
    listing.write_text(json.dumps(paths), encoding="utf-8")
    try:
        proc = subprocess.Popen([sys.executable, str(EMBED_SCRIPT), "--list", str(listing), "--out", str(out), "--progress", str(prog)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        while proc.poll() is None:
            time.sleep(0.8)
            try:
                p = json.loads(prog.read_text(encoding="utf-8"))
                progress(int(p["done"]), int(p["total"]))
            except (OSError, ValueError, KeyError):
                pass
        if proc.returncode != 0:
            raise RuntimeError((proc.stderr.read() or "the picture reader stopped")[-400:])
        return np.load(out)
    finally:
        for f in (listing, out, prog):
            f.unlink(missing_ok=True)


def fit_logistic(X, y, l2: float = 1.0):
    """Plain L2 logistic regression (scipy's L-BFGS). Classes are balanced, so many 'not pickup' boxes cannot drown the pickups."""
    import numpy as np
    from scipy.optimize import minimize
    n, d = X.shape
    pos = max(1, int(y.sum()))
    neg = max(1, n - pos)
    wt = np.where(y == 1, n / (2.0 * pos), n / (2.0 * neg))

    def loss(theta):
        w, b = theta[:-1], theta[-1]
        z = X @ w + b
        p = 1.0 / (1.0 + np.exp(-np.clip(z, -30, 30)))
        eps = 1e-9
        value = -np.sum(wt * (y * np.log(p + eps) + (1 - y) * np.log(1 - p + eps))) / n + 0.5 * l2 * np.dot(w, w) / n
        g = wt * (p - y)
        return value, np.concatenate([X.T @ g / n + l2 * w / n, [g.sum() / n]])

    res = minimize(loss, np.zeros(d + 1), jac=True, method="L-BFGS-B", options={"maxiter": 300})
    return res.x[:-1], res.x[-1]


def predict(X, w, b):
    import numpy as np
    return 1.0 / (1.0 + np.exp(-np.clip(X @ w + b, -30, 30)))


class Suggester:
    def __init__(self, app, embed_fn=None):
        self.app = app
        self._embed = embed_fn
        self._lock = threading.Lock()
        self._state: dict[str, dict] = {}
        self._scores: dict[str, dict] = {}

    # ----------------------------------------------------------------- state
    def _file(self, model: str) -> Path:
        return self.app.cache / f"suggest_{model}.json"

    def _set(self, model: str, **kw) -> None:
        with self._lock:
            self._state.setdefault(model, {}).update(kw)

    def status(self, model: str, from_name: str | None = None, to_name: str = decisions.DEFAULT_CLASS) -> dict:
        counts = self.app.journal(model).counts(from_name, to_name) if from_name else {}
        with self._lock:
            st = dict(self._state.get(model) or {})
        if not st:
            saved = self._load(model)
            st = {"state": "ready", "message": "", "accuracy": saved.get("accuracy"), "scored": len(saved.get("scores", {})),
                  "when": saved.get("when"), "from": saved.get("from"), "to": saved.get("to")} if saved else {"state": "idle"}
        st.pop("scores", None)
        st.update(min_each=MIN_EACH, marked_moved=counts.get("moved", 0), marked_kept=counts.get("kept", 0),
                  can_start=counts.get("moved", 0) >= MIN_EACH and counts.get("kept", 0) >= MIN_EACH)
        return st

    def _load(self, model: str) -> dict:
        try:
            return json.loads(self._file(model).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}

    def scores(self, model: str, from_name: str, to_name: str = decisions.DEFAULT_CLASS) -> dict[str, float]:
        """box signature -> chance it is [to_name]. Empty until a suggestion run has finished for these two classes."""
        with self._lock:
            hit = self._scores.get(model)
        if hit is None:
            hit = self._load(model)
            with self._lock:
                self._scores[model] = hit
        if hit.get("from") == from_name and hit.get("to") == to_name:
            return hit.get("scores", {})
        return {}

    # ----------------------------------------------------------------- run
    def start(self, model: str, from_name: str, to_name: str = decisions.DEFAULT_CLASS, wait: bool = False) -> dict:
        from .app import ViewerError
        model = self.app.model(model)
        names = self.app.class_names(model)
        if from_name not in names or to_name not in names:
            raise ViewerError(f"Both classes must exist first ({from_name}, {to_name}). Add the class, then mark some boxes.")
        counts = self.app.journal(model).counts(from_name, to_name)
        if counts["moved"] < MIN_EACH or counts["kept"] < MIN_EACH:
            raise ViewerError(f"Mark at least {MIN_EACH} {to_name}s and {MIN_EACH} boxes that are not {to_name}s first "
                              f"(now {counts['moved']} and {counts['kept']}).")
        with self._lock:
            if (self._state.get(model) or {}).get("state") in ("preparing", "embedding", "training"):
                return self.status(model, from_name, to_name)
            self._state[model] = {"state": "preparing", "done": 0, "total": 0, "message": "Cutting out the pictures...", "error": None}
        if wait:
            self._run(model, from_name, to_name)
        else:
            threading.Thread(target=self._run, args=(model, from_name, to_name), daemon=True).start()
        return self.status(model, from_name, to_name)

    def _boxes(self, model: str, from_name: str, to_name: str):
        """(labelled [(sig, index key, label)], candidates [(sig, index key)]). Index key = (split, name, box index)."""
        app = self.app
        idx = app.index(model)
        names = app.class_names(model)
        from_id, to_id = names.index(from_name), names.index(to_name)
        journal = app.journal(model).entries()
        by_name: dict[str, list[dict]] = {}
        for row in idx.rows:
            by_name.setdefault(row["n"], []).append(row)
        labelled = []
        for sig, e in journal.items():
            if e.get("from") != from_name or e.get("decision") not in ("move", "keep"):
                continue
            want = 1 if e["decision"] == "move" else 0
            expect_cls = to_id if want else from_id
            for row in by_name.get(e["name"], []):
                hit = next((i for i, b in enumerate(row["b"]) if b[0] == expect_cls and
                            max(abs(b[1] - e["box"][0]), abs(b[2] - e["box"][1]), abs(b[3] - e["box"][2]), abs(b[4] - e["box"][3])) < decisions.TOLERANCE), None)
                if hit is not None:
                    labelled.append((sig, (row["s"], row["n"], hit), want))
                    break
        candidates = []
        for row in idx.rows:
            for i, b in enumerate(row["b"]):
                if b[0] == from_id and decisions.box_sig(row["n"], b[1:]) not in journal:
                    candidates.append((decisions.box_sig(row["n"], b[1:]), (row["s"], row["n"], i)))
        return labelled, candidates

    def _vectors(self, model: str, keys: list[tuple]):
        """Embeddings for boxes, reusing what was computed before (the cache is keyed by the crop file and its time)."""
        import numpy as np
        app = self.app
        files = []
        for n, (split, name, i) in enumerate(keys):
            f = app.crop_of_item(model, split, name, i)
            files.append((str(f), f.stat().st_mtime_ns))
            if n % 200 == 0:
                self._set(model, state="preparing", done=n, total=len(keys), message="Cutting out the pictures...")
        cache_keys = self.app.cache / f"emb_{model}_keys.json"
        cache_vecs = self.app.cache / f"emb_{model}.npy"
        known: dict[str, int] = {}
        vecs = np.zeros((0, 512), dtype="float32")
        try:
            saved = json.loads(cache_keys.read_text(encoding="utf-8"))
            vecs = np.load(cache_vecs)
            if len(saved) == len(vecs):
                known = {k: i for i, k in enumerate(saved)}
            else:
                vecs = np.zeros((0, 512), dtype="float32")
        except (OSError, ValueError):
            pass
        tag = [f"{p}|{t}" for p, t in files]
        missing = [i for i, k in enumerate(tag) if k not in known]
        if missing:
            def progress(done, total):
                self._set(model, state="embedding", done=done, total=total, message="Reading the pictures...")
            self._set(model, state="embedding", done=0, total=len(missing), message="Reading the pictures...")
            embed = self._embed or (lambda paths, prog: embed_in_subprocess(paths, prog, self.app.cache))
            fresh = embed([files[i][0] for i in missing], progress)
            order = list(known)
            vecs = np.concatenate([vecs, fresh]) if len(vecs) else fresh
            for j, i in enumerate(missing):
                known[tag[i]] = len(order) + j
            keys_in_order = sorted(known, key=known.get)
            try:
                cache_keys.write_text(json.dumps(keys_in_order), encoding="utf-8")
                np.save(cache_vecs, vecs)
            except OSError:
                pass
        return vecs[[known[k] for k in tag]]

    def _run(self, model: str, from_name: str, to_name: str) -> None:
        import numpy as np
        try:
            labelled, candidates = self._boxes(model, from_name, to_name)
            if sum(1 for *_, w in labelled if w == 1) < MIN_EACH or sum(1 for *_, w in labelled if w == 0) < MIN_EACH:
                raise RuntimeError("Too few of the marked boxes could be found again: refresh the dataset and try again.")
            keys = [k for _, k, _ in labelled] + [k for _, k in candidates]
            X_all = self._vectors(model, keys)
            n_l = len(labelled)
            X, y = X_all[:n_l], np.array([w for *_, w in labelled], dtype="float64")
            Xc = X_all[n_l:]
            self._set(model, state="training", done=0, total=0, message="Learning from the boxes you marked...")
            rng = np.random.default_rng(0)
            order = rng.permutation(n_l)
            cut = int(n_l * (1 - HOLDOUT))
            tr, te = order[:cut], order[cut:]
            accuracy = None
            if len(te) >= 20 and 0 < y[tr].sum() < len(tr):
                w, b = fit_logistic(X[tr].astype("float64"), y[tr])
                accuracy = float(((predict(X[te].astype("float64"), w, b) >= 0.5) == (y[te] == 1)).mean())
            w, b = fit_logistic(X.astype("float64"), y)
            p = predict(Xc.astype("float64"), w, b) if len(Xc) else np.zeros(0)
            scores = {sig: round(float(s), 4) for (sig, _), s in zip(candidates, p)}
            self._file(model).write_text(json.dumps({"from": from_name, "to": to_name, "when": time.strftime("%Y-%m-%dT%H:%M:%S"),
                                                     "accuracy": accuracy, "scores": scores}), encoding="utf-8")
            with self._lock:
                self._scores[model] = {"from": from_name, "to": to_name, "scores": scores}
            self._set(model, state="ready", done=len(candidates), total=len(candidates), accuracy=accuracy, scored=len(scores),
                      when=time.strftime("%Y-%m-%dT%H:%M:%S"), message="", error=None, **{"from": from_name, "to": to_name})
        except Exception as e:                                                      # shown in words, never a crash
            self._set(model, state="error", message="", error=f"{type(e).__name__}: {e}")
