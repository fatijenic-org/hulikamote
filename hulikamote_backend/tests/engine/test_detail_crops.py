"""
Close-ups of what a specialist model looked at (the helmet crop, the cabin crop ...), kept as extra evidence:
engine/pipeline.py keep_detail, the four model checks that ask for them, the ledger that ties them to evidence photos,
and engine/ticket_photos.py that lists them in the ticket's database row. Fake models and synthetic pictures only.
"""
import json
from pathlib import Path
from types import SimpleNamespace

import cv2
import numpy as np

import engine.pipeline as pipeline_mod
from engine import marks
from engine import specialists as sp
from engine.ledger import ActiveLedgerManager, TrackLedger
from engine.pipeline import DecoupledPipeline
from engine.specialist_jobs import JOBS, Look
from engine.ticket_photos import detail_files, photo_names
from engine.violations import REGISTRY
from tests.engine.test_pipeline import WITHOUT, fake_pipe, look_n
from tests.helpers import FPS, H, W, Det

NOISE = np.random.RandomState(0).randint(0, 255, (600, 800, 3)).astype(np.uint8)   # busy, so a blur is easy to see


def entry(conf, t, violation="no_helmet", kind="helmet", path=None):
    return {"kind": kind, "violation": violation, "label": "NO HELMET", "confidence": conf, "t": t,
            "path": path or f"p{conf}", "file": f"f{conf}.jpg"}


def scene(monkeypatch):
    """A pipeline with one motorcycle (track 4) and its rider on a noisy frame, ready for keep_detail()."""
    pipe = object.__new__(DecoupledPipeline)
    pipe.ledger_manager = ActiveLedgerManager()
    bike = Det(4, [300, 300, 100, 150], "motorcycle")
    rider = Det(10, [310, 250, 60, 140], "person")
    for i in range(3):
        pipe.ledger_manager.update([bike, rider], i / FPS)
    pipe._look_frame, pipe._look_dets = NOISE, [bike, rider]
    look = Look(dets=[], crop=NOISE[250:450, 300:400], origin=(300, 250))
    return pipe, bike, look


# ─── keep_detail: the picture, blurred like every evidence photo, with the model's boxes on it ─────────────

def test_a_closeup_is_saved_blurred_with_the_models_boxes_and_remembered(monkeypatch):
    pipe, bike, look = scene(monkeypatch)
    pipe.keep_detail(bike, look, "helmet", "no_helmet", "NO HELMET", 0.8, [([310, 250, 60, 140], "NO HELMET", marks.RED)])
    ledger = pipe.ledger_manager.ledgers[4]
    assert len(ledger.detail_crops) == 1
    d = ledger.detail_crops[0]
    assert d["kind"] == "helmet" and d["violation"] == "no_helmet" and d["confidence"] == 0.8
    assert d["file"].startswith("detail_helmet_") and d["file"].endswith(".jpg")      # the apps recognise close-ups by this
    saved = cv2.imread(d["path"])
    assert saved.shape == (200, 100, 3)                                             # exactly what the model was given
    assert saved[10:36, 20:60].std() < 25 < saved[150:190, 10:90].std()              # the rider's head is blurred, the rest is not
    red = (saved[..., 2] > 200) & (saved[..., 0] < 60) & (saved[..., 1] < 60)
    assert red.any()                                                                # the NO HELMET box is drawn on it


def test_a_closeup_never_breaks_the_analysis(monkeypatch):
    pipe, bike, look = scene(monkeypatch)
    pipe._look_frame = None                                    # no frame (or any other failure): nothing happens
    pipe.keep_detail(bike, look, "helmet", "no_helmet", "NO HELMET", 0.8, [])
    pipe._look_frame = NOISE
    pipe.keep_detail(bike, Look(dets=[]), "helmet", "no_helmet", "NO HELMET", 0.8, [])      # a look without a crop
    pipe.keep_detail(Det(99, [0, 0, 5, 5]), look, "helmet", "no_helmet", "NO HELMET", 0.8, [])   # a vehicle with no ledger
    assert pipe.ledger_manager.ledgers[4].detail_crops == []


def test_only_the_most_confident_few_closeups_per_kind_are_kept(tmp_path):
    ledger = TrackLedger(1)
    assert ledger.accepts_detail("helmet", "no_helmet", 0.5, 0.0)
    assert ledger.add_detail(entry(0.5, 0.0)) == []
    assert not ledger.accepts_detail("helmet", "no_helmet", 0.9, 0.5)          # too soon after the last one
    for conf, t in ((0.6, 2.0), (0.7, 4.0)):
        assert ledger.add_detail(entry(conf, t)) == []
    assert not ledger.accepts_detail("helmet", "no_helmet", 0.4, 6.0)          # full, and weaker than every one kept
    assert ledger.accepts_detail("helmet", "no_helmet", 0.8, 6.0)
    pushed = ledger.add_detail(entry(0.8, 6.0))
    assert [p["confidence"] for p in pushed] == [0.5] and len(ledger.detail_crops) == 3
    assert ledger.accepts_detail("seatbelt", "no_seatbelt", 0.1, 6.0)          # another kind has its own room


def test_keep_detail_replaces_the_weakest_closeup_and_deletes_its_file(monkeypatch):
    pipe, bike, look = scene(monkeypatch)
    ledger = pipe.ledger_manager.ledgers[4]
    kept = []
    for i, conf in enumerate((0.5, 0.6, 0.7, 0.9)):
        ledger.path.append((10.0 * (i + 1), 350, 450, 100))                  # each look 10 s apart
        pipe.keep_detail(bike, look, "helmet", "no_helmet", "NO HELMET", conf, [])
        kept.append(ledger.detail_crops[-1]["path"] if ledger.detail_crops else None)
    assert sorted(d["confidence"] for d in ledger.detail_crops) == [0.6, 0.7, 0.9]
    assert not Path(kept[0]).exists()                    # the 0.5 close-up was pushed out and deleted
    assert all(Path(d["path"]).exists() for d in ledger.detail_crops)


# ─── when the vehicle leaves: tied to the nearest evidence photo, or deleted ───────────────────────────────

def test_closeups_of_a_violation_that_held_join_the_nearest_evidence_photo(tmp_path):
    keep, wrong = tmp_path / "keep.jpg", tmp_path / "wrong.jpg"
    keep.write_bytes(b"x"); wrong.write_bytes(b"x")
    ledger = TrackLedger(1)
    ledger.violations = {"no_helmet"}
    ledger.evidence_paths = ["a.jpg", "b.jpg"]
    ledger.evidence_meta = [{"file": "a.jpg", "t": 1.0}, {"file": "b.jpg", "t": 5.0}]
    ledger.detail_crops = [entry(0.8, 4.6, path=str(keep)),
                           entry(0.7, 4.7, violation="no_seatbelt", kind="seatbelt", path=str(wrong))]   # did not hold
    ActiveLedgerManager().decide_end_of_track(ledger)
    assert [m.get("details") for m in ledger.evidence_meta] == [None, [
        {"kind": "helmet", "violation": "no_helmet", "label": "NO HELMET", "confidence": 0.8, "file": "f0.8.jpg"}]]
    assert keep.exists() and not wrong.exists() and ledger.detail_crops == []


def test_closeups_of_a_vehicle_with_no_violation_are_all_deleted(tmp_path):
    f = tmp_path / "x.jpg"
    f.write_bytes(b"x")
    ledger = TrackLedger(1)
    ledger.detail_crops = [entry(0.8, 1.0, path=str(f))]
    ActiveLedgerManager().decide_end_of_track(ledger)
    assert not f.exists() and ledger.detail_crops == []


def test_closeups_with_no_evidence_photo_to_belong_to_are_deleted(tmp_path):
    f = tmp_path / "x.jpg"
    f.write_bytes(b"x")
    ledger = TrackLedger(1)
    ledger.violations = {"no_helmet"}
    ledger.detail_crops = [entry(0.8, 1.0, path=str(f))]
    ActiveLedgerManager().decide_end_of_track(ledger)
    assert not f.exists()


def test_a_whole_run_from_looks_to_a_ticket_with_its_closeup(monkeypatch):
    """Three bad helmet looks make the ticket (real pipeline code, fake model); its photo carries the helmet close-up."""
    pipe = fake_pipe(monkeypatch, ["no_helmet"], [[WITHOUT]] * 3, model="helmet_specialist")
    assert "no_helmet" in look_n(pipe, 3, "motorcycle")
    ledger = pipe.ledger_manager.ledgers[4]
    assert ledger.detail_crops and all(d["file"].startswith("detail_helmet_") for d in ledger.detail_crops)
    photo = pipeline_mod.EVIDENCE_DIR / "photo.jpg"
    photo.parent.mkdir(parents=True, exist_ok=True)
    photo.write_bytes(b"x")
    ledger.add_evidence_frame(str(photo), bbox=[1000, 1400, W, H], t=ledger.path[-1][0])
    pipe.ledger_manager.finalize_all()
    ticket = pipe.ledger_manager.pending_tickets[0]
    details = ticket["evidence_meta"][0]["details"]
    assert details[0]["kind"] == "helmet" and details[0]["violation"] == "no_helmet"
    assert (pipeline_mod.EVIDENCE_DIR / details[0]["file"]).is_file()
    assert photo_names(ticket)[1] == details[0]["file"]                            # the database row lists it after the first photo


# ─── the four model checks ask for a close-up only on a look that voted FOR the violation ──────────────────

class Recorder:
    def __init__(self):
        self.ledger_manager = ActiveLedgerManager()
        self.calls = []

    def keep_detail(self, det, look, kind, violation, label, confidence, boxes, note=None):
        self.calls.append((kind, violation, label, round(confidence, 2), note))


def judged(violation_key, cls, dets, drive=False):
    pipe, det = Recorder(), Det(4, [1000, 1500, W, H], cls)
    for i in range(6 if drive else 1):
        det = Det(4, [1000, int(1500 - 9 * i), W, H], cls)           # drives up the image: front / rear view for the mirror check
        pipe.ledger_manager.update([det], i / FPS)
    REGISTRY[violation_key].judge(pipe, det, Look(dets=[{"class_id": c, "confidence": p, "box": [0, 0, 5, 5]} for c, p in dets]))
    return pipe.calls


def test_no_helmet_keeps_the_closeup_only_for_a_bare_head():
    assert judged("no_helmet", "motorcycle", [(sp.IDX_RIDER_WITHOUT_HELMET, 0.8), (sp.IDX_RIDER_WITH_HELMET, 0.9)]) == [
        ("helmet", "no_helmet", "NO HELMET", 0.8, None)]
    assert judged("no_helmet", "motorcycle", [(sp.IDX_RIDER_WITH_HELMET, 0.9)]) == []


def test_no_seatbelt_keeps_the_closeup_only_when_no_belt_is_seen_through_a_clear_window():
    assert judged("no_seatbelt", "car", [(sp.IDX_CLEAR_WINDOW, 0.7)]) == [("seatbelt", "no_seatbelt", "NO SEATBELT", 0.7, None)]
    assert judged("no_seatbelt", "car", [(sp.IDX_CLEAR_WINDOW, 0.7), (sp.IDX_SEATBELT, 0.8)]) == []
    assert judged("no_seatbelt", "car", [(sp.IDX_TINTED_WINDOW, 0.9), (sp.IDX_CLEAR_WINDOW, 0.7)]) == []     # tinted: no judgement


def test_distracted_driving_keeps_the_closeup_only_when_a_phone_is_seen():
    assert judged("distracted_driving", "car", [(sp.IDX_CLEAR_WINDOW, 0.7), (sp.IDX_DRIVER_PHONE, 0.6)]) == [
        ("phone", "distracted_driving", "PHONE", 0.6, None)]
    assert judged("distracted_driving", "car", [(sp.IDX_CLEAR_WINDOW, 0.7)]) == []


def test_missing_side_mirror_keeps_the_closeup_when_fewer_than_two_mirrors_are_seen():
    assert judged("missing_side_mirror", "motorcycle", [(sp.IDX_SIDE_MIRROR, 0.5)], drive=True) == [
        ("mirror", "missing_side_mirror", "1/2 MIRRORS", 0.5, "1/2 MIRRORS")]
    assert judged("missing_side_mirror", "motorcycle", [], drive=True) == [
        ("mirror", "missing_side_mirror", "0/2 MIRRORS", 0.5, "0/2 MIRRORS")]
    assert judged("missing_side_mirror", "motorcycle", [(sp.IDX_SIDE_MIRROR, 0.5), (sp.IDX_SIDE_MIRROR, 0.6)], drive=True) == []


def test_the_helmet_and_cabin_looks_carry_the_crop_the_model_was_given(monkeypatch):
    monkeypatch.setattr(sp, "detect", lambda session, crop, conf=0.1: [])
    pipe = SimpleNamespace(registry=SimpleNamespace(get_model=lambda name: object()))
    det = Det(4, [300, 300, 100, 150], "motorcycle")
    jobs = {j.name: j for j in JOBS}
    for name in ("helmet", "cabin"):
        look = jobs[name].look(pipe, np.zeros((600, 800, 3), np.uint8), det, [det])
        assert look.crop.shape[:2] == (150, 100) and look.origin == (300, 300), name


# ─── what the ticket's database row lists, and so what the Inbox and the phone get ─────────────────────────

def test_a_ticket_row_lists_the_closeups_after_the_first_photo(tmp_path, monkeypatch):
    import evidence_files
    monkeypatch.setattr(evidence_files, "EVIDENCE_DIR", tmp_path)
    for name in ("a.jpg", "b.jpg", "detail_helmet_1.jpg"):
        (tmp_path / name).write_bytes(b"x")
    ticket = {"evidence_paths": ["a.jpg", "b.jpg"],
              "evidence_meta": [{"file": "a.jpg", "details": [{"file": "detail_helmet_1.jpg", "kind": "helmet"}]},
                                {"file": "b.jpg", "details": [{"file": "detail_helmet_1.jpg", "kind": "helmet"}]}]}
    assert detail_files(ticket) == ["detail_helmet_1.jpg"]                        # listed once
    assert photo_names(ticket) == ["a.jpg", "detail_helmet_1.jpg", "b.jpg"]
    assert evidence_files.frames_of({"evidence_paths": json.dumps(photo_names(ticket))}) == ["a.jpg", "detail_helmet_1.jpg", "b.jpg"]


def test_a_ticket_without_closeups_lists_exactly_its_photos():
    assert photo_names({"evidence_paths": ["a.jpg", "b.jpg"], "evidence_meta": [{"file": "a.jpg"}]}) == ["a.jpg", "b.jpg"]
    assert photo_names({"evidence_paths": [], "evidence_meta": []}) == []


def test_a_removed_photo_takes_its_closeups_out_of_the_row():
    from engine.ticket_merge import remove_frames
    ticket = {"evidence_paths": ["a.jpg", "b.jpg"],
              "evidence_meta": [{"file": "a.jpg"}, {"file": "b.jpg", "details": [{"file": "detail_helmet_2.jpg"}]}]}
    assert photo_names(ticket) == ["a.jpg", "detail_helmet_2.jpg", "b.jpg"]
    assert photo_names(remove_frames(ticket, ["b.jpg"])) == ["a.jpg"]


def test_cancel_deletes_the_closeups_of_released_tickets_and_of_cars_still_on_screen(tmp_path):
    from routers.forensic import _discard_run
    photo, tied, waiting = tmp_path / "p.jpg", tmp_path / "detail_helmet_1.jpg", tmp_path / "detail_helmet_2.jpg"
    for f in (photo, tied, waiting):
        f.write_bytes(b"x")
    on_screen = TrackLedger(7)
    on_screen.detail_crops = [entry(0.8, 1.0, path=str(waiting))]                    # not tied to a photo yet
    released = {"evidence_paths": [str(photo)], "evidence_meta": [{"file": "p.jpg", "details": [{"file": tied.name}]}]}
    pipeline = SimpleNamespace(ledger_manager=SimpleNamespace(ledgers={7: on_screen}, pending_tickets=[]))
    _discard_run(pipeline, [], tmp_path / "not_a_run", released=[released])
    assert not photo.exists() and not tied.exists() and not waiting.exists()


def test_a_label_is_shrunk_to_fit_a_narrow_crop():
    narrow = np.zeros((200, 60, 3), np.uint8)
    marks.draw_boxes(narrow, [([5, 20, 50, 100], "NO HELMET", marks.RED)])
    red = (narrow[..., 2] > 200) & (narrow[..., 0] < 60) & (narrow[..., 1] < 60)
    ys, xs = np.nonzero(red)
    assert len(xs) and xs.max() <= 59                                              # nothing is drawn outside the picture
    label_rows = red[:, 5:55][: 20].any(axis=1)                                    # the label background sits above the box
    assert label_rows.any()
    wide = np.zeros((200, 400, 3), np.uint8)                                         # a wide crop is unchanged and still works
    marks.draw_boxes(wide, [([5, 20, 300, 100], "NO HELMET", marks.RED)], note="1/2 MIRRORS")
    assert (wide[..., 2] > 200).any()
