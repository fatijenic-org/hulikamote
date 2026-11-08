"""
engine/plate_reread.py and ticket_merge.remove_frames - the review tools that change which photos a ticket has, what
its plate is, and the box a reviewer draws by hand. Models and image files are replaced by tiny fakes.
"""
import numpy as np
import pytest

from engine.plate_reread import UNREAD, crop_box, reread
from engine.ticket_merge import remove_frames


def crop_result(file, text, conf=0.9):
    return {"image_raw": file, "image_sr": None, "image_context": None, "t": 1.0, "raw": text, "cleaned": text, "confidence": conf}


def ticket(manual=False):
    """Three photos. Photos 1 and 2 were read as ABC1234 (crops c1, c2); photo 3 as XYZ9999 (c3)."""
    meta = [
        {"file": "p1.jpg", "t": 1.0, "bbox": [0, 0, 10, 10], "clean": "clean1.jpg", "crop": "c1.jpg", "plate": "ABC1234"},
        {"file": "p2.jpg", "t": 2.0, "bbox": [0, 0, 10, 10], "clean": "clean2.jpg", "crop": "c2.jpg", "plate": "ABC1234"},
        {"file": "p3.jpg", "t": 3.0, "bbox": [0, 0, 10, 10], "clean": None, "car_crop": None, "crop": "c3.jpg", "plate": "XYZ9999"},
    ]
    t = {
        "ticket_uid": "u1", "track_id": 1, "violations": ["no_helmet"], "plate_text": "ABC1234", "db_ids": ["r1"],
        "evidence_meta": meta, "evidence_paths": [m["file"] for m in meta], "flags": [], "metadata": {"plate_format": "ph_standard"},
        "crop_results": [crop_result("c1.jpg", "ABC1234"), crop_result("c2.jpg", "ABC1234"), crop_result("c3.jpg", "XYZ9999")],
        "plate_crop_paths": ["c1.jpg", "c2.jpg", "c3.jpg"],
    }
    if manual:
        t.update(plate_manual=True, plate_ocr="ABC1234", plate_text="TYPED77")
    return t


# ─── remove photos ───────────────────────────────────────────────────────────

def test_removing_photos_drops_them_and_the_plate_reads_taken_from_them():
    out = remove_frames(ticket(), ["p3.jpg"])
    assert out["evidence_paths"] == ["p1.jpg", "p2.jpg"]
    assert [m["file"] for m in out["evidence_meta"]] == ["p1.jpg", "p2.jpg"]
    assert out["plate_crop_paths"] == ["c1.jpg", "c2.jpg"] and len(out["crop_results"]) == 2
    assert [m["file"] for m in out["removed_frames"]] == ["p3.jpg"]                 # kept for the record


def test_the_plate_is_voted_again_without_the_removed_photos():
    t = ticket()
    t["plate_text"] = "ABC1234"
    out = remove_frames(t, ["p1.jpg", "p2.jpg"])                                    # only the XYZ9999 read is left
    assert out["plate_text"] == "XYZ9999"


def test_removing_every_photo_that_read_the_plate_leaves_it_unidentified():
    t = ticket()
    t["evidence_meta"][2]["crop"] = None                                           # photo 3 never read a plate
    t["crop_results"] = t["crop_results"][:2]
    t["plate_crop_paths"] = ["c1.jpg", "c2.jpg"]
    assert remove_frames(t, ["p1.jpg", "p2.jpg"])["plate_text"] == "unidentified"


def test_a_plate_the_reviewer_typed_is_not_voted_again():
    out = remove_frames(ticket(manual=True), ["p1.jpg", "p2.jpg"])
    assert out["plate_text"] == "TYPED77" and out["plate_manual"] is True


@pytest.mark.parametrize("files", [[], ["nope.jpg"], ["p1.jpg", "p2.jpg", "p3.jpg"]])
def test_at_least_one_photo_must_stay_and_the_photos_must_exist(files):
    with pytest.raises(ValueError):
        remove_frames(ticket(), files)


def test_removing_does_not_change_the_original_ticket():
    t = ticket()
    remove_frames(t, ["p3.jpg"])
    assert len(t["evidence_paths"]) == 3 and len(t["crop_results"]) == 3


# ─── read the plate again ────────────────────────────────────────────────────

def fake_io(plates_by_image, reads):
    """find_plates / read_plate / load_image / save_image stand-ins. `reads` = what the OCR returns per call, in order."""
    saved = []
    queue = list(reads)

    def load(name):
        return None if name is None or name.startswith("missing") else np.full((100, 200, 3), 7, np.uint8)

    def find(image):
        return plates_by_image

    def read(crop):
        text, conf = queue.pop(0)
        return text, text, crop, crop, conf

    def save(image):
        saved.append(image.shape)
        return f"new{len(saved)}.jpg"
    return dict(find_plates=find, read_plate=read, load_image=load, save_image=save), saved


def test_reading_again_adds_a_crop_for_each_photo_with_a_clean_picture_and_votes():
    io, saved = fake_io([{"box": [50, 40, 60, 20], "confidence": 0.9}], [("NEW1234", 0.95), ("NEW1234", 0.9)])
    out, summary = reread(ticket(), [], plate_format="ph_standard", **io)
    assert summary["checked"] == 3 and summary["found"] == 2 and summary["no_picture"] == 1      # photo 3 has no clean picture
    assert [c["cleaned"] for c in out["crop_results"] if c.get("reread_of")] == ["NEW1234", "NEW1234"]
    assert out["plate_text"] == "NEW1234" and summary["suggested"] == "NEW1234" and summary["kept_manual"] is False
    p1 = out["evidence_meta"][0]
    assert p1["crop"] == "new1.jpg" and p1["plate"] == "NEW1234"                                # the photo shows what it read


def test_the_crop_has_a_margin_around_the_plate_box():
    io, saved = fake_io([{"box": [50, 40, 60, 20], "confidence": 0.9}], [("ABC1234", 0.9)])
    reread(ticket(), ["p1.jpg"], plate_format="ph_standard", **io)
    assert saved[0] == (20 + 2 * 2, 60 + 2 * 6, 3)                                              # 10% more on each side


def test_only_the_chosen_photos_are_read_again():
    io, _ = fake_io([{"box": [0, 0, 40, 20], "confidence": 0.9}], [("ABC1234", 0.9)])
    _, summary = reread(ticket(), ["p2.jpg"], plate_format="ph_standard", **io)
    assert summary["checked"] == 1 and summary["found"] == 1


def test_reading_the_same_photo_twice_does_not_count_it_twice():
    io, _ = fake_io([{"box": [0, 0, 40, 20], "confidence": 0.9}], [("AAA1111", 0.9), ("BBB2222", 0.9)])
    once, _ = reread(ticket(), ["p1.jpg"], plate_format="ph_standard", **io)
    twice, _ = reread(once, ["p1.jpg"], plate_format="ph_standard", **io)
    assert [c["cleaned"] for c in twice["crop_results"] if c.get("reread_of") == "p1.jpg"] == ["BBB2222"]
    assert "new1.jpg" not in twice["plate_crop_paths"]                                          # the stale crop is gone


def test_when_no_plate_is_found_nothing_changes():
    io, _ = fake_io([], [])
    out, summary = reread(ticket(), [], plate_format="ph_standard", **io)
    assert summary["found"] == 0 and summary["no_plate"] == 2
    assert out["plate_text"] == "ABC1234" and len(out["crop_results"]) == 3


def test_a_typed_plate_is_kept_and_the_new_read_is_only_a_suggestion():
    io, _ = fake_io([{"box": [0, 0, 40, 20], "confidence": 0.9}], [("NEW1234", 0.99), ("NEW1234", 0.99)])
    out, summary = reread(ticket(manual=True), [], plate_format="ph_standard", **io)
    assert out["plate_text"] == "TYPED77" and out["plate_manual"] is True
    assert summary["kept_manual"] is True and summary["suggested"] == "NEW1234"


def test_reading_again_does_not_change_the_original_ticket():
    t = ticket()
    io, _ = fake_io([{"box": [0, 0, 40, 20], "confidence": 0.9}], [("NEW1234", 0.9), ("NEW1234", 0.9)])
    reread(t, [], plate_format="ph_standard", **io)
    assert len(t["crop_results"]) == 3 and t["evidence_meta"][0]["crop"] == "c1.jpg"


def test_there_must_be_a_photo_to_read():
    io, _ = fake_io([], [])
    with pytest.raises(ValueError):
        reread(ticket(), ["nope.jpg"], plate_format="ph_standard", **io)


# ─── a box drawn by hand ─────────────────────────────────────────────────────

def test_a_drawn_box_gives_the_pixels_inside_it_whichever_corner_it_started_from():
    image = np.arange(100 * 200, dtype=np.uint8).reshape(100, 200)
    crop = crop_box(image, [0.25, 0.5, 0.75, 0.9])
    assert crop.shape == (40, 100) and crop[0, 0] == image[50, 50]
    assert crop_box(image, [0.75, 0.9, 0.25, 0.5]).shape == (40, 100)             # dragged from the bottom right


def test_a_box_that_sticks_out_a_little_is_trimmed_to_the_picture():
    assert crop_box(np.zeros((100, 200), np.uint8), [-0.005, 0.2, 1.005, 0.6]).shape == (40, 200)


@pytest.mark.parametrize("box", [[0.1, 0.1, 0.101, 0.9], [0.1, 0.1, 0.9, 0.102], [0.3, 0.3, 0.3, 0.3]])
def test_a_slip_of_the_mouse_is_not_a_plate(box):
    with pytest.raises(ValueError, match="bigger"):
        crop_box(np.zeros((100, 200), np.uint8), box)


@pytest.mark.parametrize("box", [[0, 0, 1], [0, 0, 1, 2], [-1, 0, 1, 1]])
def test_a_box_outside_the_picture_is_refused(box):
    with pytest.raises(ValueError):
        crop_box(np.zeros((100, 200), np.uint8), box)


def test_the_unread_words_are_the_ones_the_rest_of_the_system_uses():
    assert {"unidentified", "no_plate_found", ""} <= set(UNREAD)
