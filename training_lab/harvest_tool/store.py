"""
store.py - The inbox: every picture waiting for a human, and what happened to it.

One SQLite file (harvest_inbox/harvest.db) is the index; pictures live in
harvest_inbox/<model>/images/<id>.jpg and, once a human has decided, labels in
harvest_inbox/<model>/labels/<id>.txt (YOLO format). Nothing here touches the datasets.

An item is always in exactly one state:
    check     the model suggested boxes (possibly none = "no object") - a human confirms or fixes
    label     the model found nothing - a human draws the boxes (or says "nothing here")
    ready     a human decided; waiting to be added to the dataset
    skipped   a human was not sure; kept out of training
    accepted  added to the dataset
"""
import hashlib
import json
import sqlite3
import time
from contextlib import closing
from dataclasses import dataclass, field
from pathlib import Path

from .config import Paths

NEEDS_EYES = ("check", "label")

SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
    id TEXT PRIMARY KEY,
    model TEXT NOT NULL,
    state TEXT NOT NULL,
    source TEXT NOT NULL,
    reason TEXT NOT NULL DEFAULT '',
    boxes TEXT NOT NULL DEFAULT '[]',
    suggested INTEGER NOT NULL DEFAULT 0,
    group_id TEXT NOT NULL,
    split_hint TEXT,
    task_id TEXT,
    ticket_uid TEXT,
    violation TEXT,
    decision TEXT,
    priority INTEGER NOT NULL DEFAULT 5,
    width INTEGER,
    height INTEGER,
    created REAL NOT NULL,
    decided REAL,
    accepted REAL,
    dataset_name TEXT
);
CREATE INDEX IF NOT EXISTS idx_items_model_state ON items(model, state);

CREATE TABLE IF NOT EXISTS pairs (
    id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    a_label TEXT NOT NULL,
    b_label TEXT NOT NULL,
    a_files TEXT NOT NULL DEFAULT '[]',
    b_files TEXT NOT NULL DEFAULT '[]',
    kind TEXT NOT NULL DEFAULT 'gap',
    reason TEXT NOT NULL DEFAULT '',
    score REAL NOT NULL DEFAULT 0,
    state TEXT NOT NULL DEFAULT 'open',
    created REAL NOT NULL,
    decided REAL
);
CREATE INDEX IF NOT EXISTS idx_pairs_task_state ON pairs(task_id, state);

CREATE TABLE IF NOT EXISTS car_checks (
    task_id TEXT NOT NULL,
    uid TEXT NOT NULL,
    state TEXT NOT NULL,
    marked TEXT NOT NULL DEFAULT '[]',
    decided REAL NOT NULL,
    PRIMARY KEY (task_id, uid)
);

CREATE TABLE IF NOT EXISTS collected (
    task_id TEXT PRIMARY KEY,
    version INTEGER NOT NULL,
    at REAL NOT NULL
);
"""

README = """HARVEST INBOX  (your pictures, local only - never uploaded, git-ignored)

What is here
  <model>/images/   pictures waiting for you, or already decided
  <model>/labels/   the boxes you confirmed or drew (YOLO text files)
  harvest.db        the index: what each picture is, why it is here, what you decided
  protected.json    benchmark clips: never harvested, so the test stays honest

How it works (the loop)
  1. Analyze clips in the Forensic Analyzer.
  2. Collect:  python training_lab/harvest.py collect      (or the Harvest tab in the Training Lab)
  3. Check & label: python training_lab/harvest.py serve    (opens a page in your browser)
       - a green box the model drew: press Enter if it is right, fix it if not
       - no box: draw one, or press N = nothing here
  4. Add to dataset (page button, or: python training_lab/harvest.py accept <model>)
  5. Train the model in the Training Lab, deploy, and test again.
"""


@dataclass
class Item:
    id: str
    model: str
    state: str
    source: str
    reason: str = ""
    boxes: list = field(default_factory=list)      # [[cls, cx, cy, w, h], ...] normalised YOLO
    suggested: bool = False
    group_id: str = ""
    split_hint: str | None = None
    task_id: str | None = None
    ticket_uid: str | None = None
    violation: str | None = None
    decision: str | None = None
    priority: int = 5
    width: int = 0
    height: int = 0
    created: float = 0.0
    decided: float | None = None
    accepted: float | None = None
    dataset_name: str | None = None

    def to_dict(self) -> dict:
        return {k: getattr(self, k) for k in self.__dataclass_fields__}


@dataclass
class Pair:
    """Two cars from one analysis: a person says whether they are the same car (the tracker may have split one car in two)."""
    id: str
    task_id: str
    a_label: str                                      # identity folder in datasets/reid: <task8>_<ticket>
    b_label: str
    a_files: list = field(default_factory=list)       # crop names in the evidence folder, one per photo of that car
    b_files: list = field(default_factory=list)
    kind: str = "gap"                                 # gap: one starts as the other ends (same car?); twin: seen together
    reason: str = ""
    score: float = 0.0
    state: str = "open"                               # open | same | different | skipped
    created: float = 0.0
    decided: float | None = None

    def to_dict(self) -> dict:
        return {k: getattr(self, k) for k in self.__dataclass_fields__}


def make_id(*parts: str) -> str:
    return hashlib.sha1("|".join(parts).encode("utf-8")).hexdigest()[:16]


def yolo_text(boxes: list) -> str:
    return "\n".join(f"{int(c)} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}" for c, cx, cy, w, h in boxes)


def clean_boxes(boxes: list, n_classes: int) -> list:
    """Validate boxes from a client: class in range, centre/size inside the picture, not degenerate."""
    out = []
    for b in boxes:
        c, cx, cy, w, h = int(b[0]), float(b[1]), float(b[2]), float(b[3]), float(b[4])
        if not (0 <= c < n_classes) or w <= 0.002 or h <= 0.002:
            continue
        x1, y1 = max(0.0, cx - w / 2), max(0.0, cy - h / 2)
        x2, y2 = min(1.0, cx + w / 2), min(1.0, cy + h / 2)
        if x2 - x1 <= 0.002 or y2 - y1 <= 0.002:
            continue
        out.append([c, (x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1])
    return out


class Store:
    def __init__(self, paths: Paths | None = None):
        self.paths = paths or Paths()
        self.root = self.paths.inbox
        self.root.mkdir(parents=True, exist_ok=True)
        self.db_path = self.root / "harvest.db"
        readme = self.root / "README.txt"
        if not readme.exists():
            readme.write_text(README, encoding="utf-8")
        with self._connect() as con:
            con.executescript(SCHEMA)

    def _connect(self) -> sqlite3.Connection:
        con = sqlite3.connect(self.db_path, timeout=10)
        con.row_factory = sqlite3.Row
        return con

    # ── files ──
    def image_path(self, model: str, item_id: str) -> Path:
        return self.root / model / "images" / f"{item_id}.jpg"

    def label_path(self, model: str, item_id: str) -> Path:
        return self.root / model / "labels" / f"{item_id}.txt"

    def pair_image_path(self, pair_id: str, side: str) -> Path:
        """The one picture shown for each car of a pair: side is 'a' or 'b'."""
        return self.root / "reid_pairs" / "images" / f"{pair_id}_{side}.jpg"

    # ── writing ──
    def add(self, item: Item) -> bool:
        """Insert unless this id is already known. Returns True when it was new."""
        item.created = item.created or time.time()
        with closing(self._connect()) as con, con:
            cur = con.execute(
                """INSERT OR IGNORE INTO items (id, model, state, source, reason, boxes, suggested, group_id,
                   split_hint, task_id, ticket_uid, violation, decision, priority, width, height, created)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (item.id, item.model, item.state, item.source, item.reason, json.dumps(item.boxes),
                 int(item.suggested), item.group_id, item.split_hint, item.task_id, item.ticket_uid,
                 item.violation, item.decision, item.priority, item.width, item.height, item.created))
            return cur.rowcount == 1

    def save_boxes(self, item_id: str, boxes: list) -> Item:
        """A human decided: these boxes (empty list = 'nothing here'). The item becomes ready."""
        item = self.get(item_id)
        if item is None:
            raise KeyError(item_id)
        if item.state == "accepted":
            raise ValueError("Already added to the dataset")
        label = self.label_path(item.model, item_id)
        label.parent.mkdir(parents=True, exist_ok=True)
        label.write_text(yolo_text(boxes), encoding="utf-8")
        with closing(self._connect()) as con, con:
            con.execute("UPDATE items SET state='ready', boxes=?, decided=? WHERE id=?",
                        (json.dumps(boxes), time.time(), item_id))
        return self.get(item_id)

    def skip(self, item_id: str) -> None:
        with closing(self._connect()) as con, con:
            con.execute("UPDATE items SET state='skipped', decided=? WHERE id=? AND state!='accepted'",
                        (time.time(), item_id))

    def set_suggestion(self, item_id: str, boxes: list) -> None:
        """A model proposal for an item that had none: label -> check."""
        with closing(self._connect()) as con, con:
            con.execute("UPDATE items SET boxes=?, suggested=1, state='check' WHERE id=? AND state='label'",
                        (json.dumps(boxes), item_id))

    def forget(self, model: str, source: str) -> int:
        """Remove the not-yet-added items of one source (and their files), e.g. to re-cut with new rules.
        Items already added to a dataset are never touched."""
        with closing(self._connect()) as con:
            ids = [r["id"] for r in con.execute(
                "SELECT id FROM items WHERE model=? AND source=? AND state!='accepted'", (model, source))]
        for item_id in ids:
            self.image_path(model, item_id).unlink(missing_ok=True)
            self.label_path(model, item_id).unlink(missing_ok=True)
        with closing(self._connect()) as con, con:
            con.executemany("DELETE FROM items WHERE id=?", [(i,) for i in ids])
        return len(ids)

    def mark_accepted(self, item_id: str, dataset_name: str) -> None:
        with closing(self._connect()) as con, con:
            con.execute("UPDATE items SET state='accepted', accepted=?, dataset_name=? WHERE id=?",
                        (time.time(), dataset_name, item_id))

    # ── reading ──
    @staticmethod
    def _row(row: sqlite3.Row) -> Item:
        d = dict(row)
        d["boxes"] = json.loads(d["boxes"] or "[]")
        d["suggested"] = bool(d["suggested"])
        return Item(**d)

    def get(self, item_id: str) -> Item | None:
        with closing(self._connect()) as con:
            row = con.execute("SELECT * FROM items WHERE id=?", (item_id,)).fetchone()
        return self._row(row) if row else None

    def items(self, model: str, states: tuple, limit: int | None = None, task: str | None = None) -> list[Item]:
        """Items of one model in the given states, most likely wrong first. `task` = only that analysis."""
        marks = ",".join("?" for _ in states)
        sql = (f"SELECT * FROM items WHERE model=? AND state IN ({marks})" + (" AND task_id=?" if task else "") +
               " ORDER BY priority, created, id" + (f" LIMIT {int(limit)}" if limit else ""))
        with closing(self._connect()) as con:
            rows = con.execute(sql, (model, *states, *([task] if task else []))).fetchall()
        return [self._row(r) for r in rows]

    def queue(self, model: str, limit: int = 200, task: str | None = None) -> list[Item]:
        return self.items(model, NEEDS_EYES, limit, task)

    def ready(self, model: str) -> list[Item]:
        return self.items(model, ("ready",))

    def counts(self, model: str, task: str | None = None) -> dict:
        with closing(self._connect()) as con:
            rows = con.execute("SELECT state, COUNT(*) n FROM items WHERE model=?" + (" AND task_id=?" if task else "")
                               + " GROUP BY state", (model, *([task] if task else []))).fetchall()
        c = {r["state"]: r["n"] for r in rows}
        return {"check": c.get("check", 0), "label": c.get("label", 0), "ready": c.get("ready", 0),
                "skipped": c.get("skipped", 0), "accepted": c.get("accepted", 0),
                "needs_eyes": c.get("check", 0) + c.get("label", 0)}

    def has_task(self, task: str) -> bool:
        """True once anything of that analysis was collected (even if every picture was decided since)."""
        with closing(self._connect()) as con:
            return con.execute("SELECT 1 FROM items WHERE task_id=? LIMIT 1", (task,)).fetchone() is not None

    def has_group(self, model: str, group_id: str) -> bool:
        with closing(self._connect()) as con:
            return con.execute("SELECT 1 FROM items WHERE model=? AND group_id=? LIMIT 1",
                               (model, group_id)).fetchone() is not None

    def unsuggested_labels(self, model: str) -> list[Item]:
        with closing(self._connect()) as con:
            rows = con.execute("SELECT * FROM items WHERE model=? AND state='label' AND suggested=0",
                               (model,)).fetchall()
        return [self._row(r) for r in rows]

    # ── pairs: "are these the same car?" ──
    @staticmethod
    def _pair_row(row: sqlite3.Row) -> Pair:
        d = dict(row)
        d["a_files"] = json.loads(d["a_files"] or "[]")
        d["b_files"] = json.loads(d["b_files"] or "[]")
        return Pair(**d)

    def add_pair(self, pair: Pair) -> bool:
        pair.created = pair.created or time.time()
        with closing(self._connect()) as con, con:
            cur = con.execute(
                """INSERT OR IGNORE INTO pairs (id, task_id, a_label, b_label, a_files, b_files, kind, reason, score,
                   state, created) VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
                (pair.id, pair.task_id, pair.a_label, pair.b_label, json.dumps(pair.a_files), json.dumps(pair.b_files),
                 pair.kind, pair.reason, pair.score, pair.state, pair.created))
            return cur.rowcount == 1

    def get_pair(self, pair_id: str) -> Pair | None:
        with closing(self._connect()) as con:
            row = con.execute("SELECT * FROM pairs WHERE id=?", (pair_id,)).fetchone()
        return self._pair_row(row) if row else None

    def open_pairs(self, task: str | None = None, limit: int | None = None) -> list[Pair]:
        """Pairs still waiting for an answer: the likeliest split cars first, look-alikes after."""
        sql = ("SELECT * FROM pairs WHERE state='open'" + (" AND task_id=?" if task else "") +
               " ORDER BY CASE kind WHEN 'gap' THEN 0 ELSE 1 END, score DESC, created, id" +
               (f" LIMIT {int(limit)}" if limit else ""))
        with closing(self._connect()) as con:
            rows = con.execute(sql, ((task,) if task else ())).fetchall()
        return [self._pair_row(r) for r in rows]

    def decide_pair(self, pair_id: str, state: str) -> Pair:
        if state not in ("same", "different", "skipped"):
            raise ValueError(f"not an answer: {state!r}")
        if self.get_pair(pair_id) is None:
            raise KeyError(pair_id)
        with closing(self._connect()) as con, con:
            con.execute("UPDATE pairs SET state=?, decided=? WHERE id=?", (state, time.time(), pair_id))
        return self.get_pair(pair_id)

    def pair_counts(self, task: str | None = None) -> dict:
        with closing(self._connect()) as con:
            rows = con.execute("SELECT state, COUNT(*) n FROM pairs" + (" WHERE task_id=?" if task else "")
                               + " GROUP BY state", ((task,) if task else ())).fetchall()
        c = {r["state"]: r["n"] for r in rows}
        return {"open": c.get("open", 0), "same": c.get("same", 0), "different": c.get("different", 0),
                "skipped": c.get("skipped", 0)}

    # ── which analyses were gathered, and by which version of the gatherer ──
    def mark_collected(self, task: str, version: int) -> None:
        with closing(self._connect()) as con, con:
            con.execute("INSERT OR REPLACE INTO collected (task_id, version, at) VALUES (?,?,?)",
                        (task, version, time.time()))

    def is_collected(self, task: str, version: int) -> bool:
        with closing(self._connect()) as con:
            row = con.execute("SELECT version FROM collected WHERE task_id=?", (task,)).fetchone()
        return bool(row) and row["version"] >= version

    # ── cars: "are all the photos under this number one car?" ──
    def save_car_check(self, task: str, uid: str, state: str, marked: list) -> None:
        """state: checked (all one car) or split (the marked photos are another car)."""
        with closing(self._connect()) as con, con:
            con.execute("INSERT OR REPLACE INTO car_checks (task_id, uid, state, marked, decided) VALUES (?,?,?,?,?)",
                        (task, uid, state, json.dumps(marked), time.time()))

    def car_checks(self, task: str) -> dict:
        """{uid: (state, [marked photo names])} of the cars a person already went through."""
        with closing(self._connect()) as con:
            rows = con.execute("SELECT uid, state, marked FROM car_checks WHERE task_id=?", (task,)).fetchall()
        return {r["uid"]: (r["state"], json.loads(r["marked"] or "[]")) for r in rows}
