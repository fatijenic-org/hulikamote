"""
engine/specialists.py - the way the helmet / plate / cabin models are fed (RGB, letterbox) and read (box mapping, NMS),
checked with a fake ONNX session so no model file is needed.
"""
import numpy as np

from engine import specialists as sp


class FakeSession:
    """Looks like an onnxruntime session: records the tensor it was given, returns canned YOLO output."""

    def __init__(self, rows, size=320):
        self.rows, self.size, self.last_blob = rows, size, None

    def get_inputs(self):
        class Input:
            name = "images"
            shape = [1, 3, self.size, self.size]
        return [Input()]

    def run(self, _outputs, feed):
        self.last_blob = feed["images"]
        rows = np.array(self.rows, dtype=np.float32).reshape(len(self.rows), -1) if self.rows else np.zeros((0, 5), np.float32)
        padded = np.zeros((100, rows.shape[1]), dtype=np.float32)       # real exports have thousands of rows (N > channels)
        padded[:len(rows)] = rows
        return [padded.T[np.newaxis]]                                   # (1, 4 + classes, N) like a YOLOv8 export


def test_letterbox_keeps_the_aspect_ratio_and_pads_with_grey():
    wide = np.zeros((50, 200, 3), dtype=np.uint8)                      # 4:1 crop
    blob, scale, pad_x, pad_y = sp.letterbox(wide, 320)
    assert blob.shape == (1, 3, 320, 320) and blob.dtype == np.float32
    assert scale == 1.6 and pad_x == 0 and pad_y == 120                # 320 x 80 picture, 120 px grey above and below
    assert np.allclose(blob[0, :, 10, :], sp.PAD_VALUE / 255.0)        # a padding row
    assert np.allclose(blob[0, :, 160, :], 0.0)                        # a picture row (black crop)


def test_letterbox_converts_bgr_to_rgb():
    crop = np.zeros((40, 40, 3), dtype=np.uint8)
    crop[..., 0] = 255                                                  # pure blue in BGR
    blob, *_ = sp.letterbox(crop, 320)
    assert blob[0, 2, 160, 160] == 1.0                                  # ...is the LAST channel in RGB
    assert blob[0, 0, 160, 160] == 0.0


def test_detect_maps_boxes_back_to_crop_pixels():
    # a 200 x 100 crop sits in the 320 input at scale 1.6, pad_y 80. A box centred in the input, 160 x 80 wide:
    session = FakeSession([[160, 160, 160, 80, 0.9]])
    dets = sp.detect(session, np.zeros((100, 200, 3), dtype=np.uint8), conf=0.1)
    assert len(dets) == 1
    assert dets[0]["class_id"] == 0 and abs(dets[0]["confidence"] - 0.9) < 1e-6
    x, y, w, h = dets[0]["box"]
    assert (x, y, w, h) == (50, 25, 100, 50)                            # centre of the crop, half its size


def test_detect_drops_weak_detections():
    session = FakeSession([[100, 100, 20, 20, 0.05], [200, 200, 20, 20, 0.7]])
    dets = sp.detect(session, np.zeros((64, 64, 3), dtype=np.uint8), conf=0.4)
    assert [round(d["confidence"], 2) for d in dets] == [0.7]


def test_detect_removes_duplicates_of_the_same_class_but_not_other_classes():
    session = FakeSession([
        [100, 100, 40, 40, 0.9, 0.0],     # class 0
        [102, 101, 40, 40, 0.8, 0.0],     # same object, class 0 again: duplicate
        [100, 100, 40, 40, 0.0, 0.7],     # same place, class 1: a different thing (clear window + seatbelt, say)
    ])
    dets = sp.detect(session, np.zeros((320, 320, 3), dtype=np.uint8), conf=0.1)
    assert sorted(d["class_id"] for d in dets) == [0, 1]
    assert [d["class_id"] for d in dets] == [0, 1]                      # best first


def test_detect_counts_two_separate_objects_of_one_class_twice():
    session = FakeSession([[60, 100, 40, 40, 0.9], [260, 100, 40, 40, 0.8]])    # two mirrors, far apart
    dets = sp.detect(session, np.zeros((320, 320, 3), dtype=np.uint8), conf=0.1)
    assert len(dets) == 2


def test_detect_ignores_a_degenerate_crop():
    assert sp.detect(FakeSession([[1, 1, 1, 1, 1.0]]), np.zeros((1, 1, 3), dtype=np.uint8)) == []


def test_input_size_is_read_from_the_model():
    assert sp.input_size(FakeSession([], size=640)) == 640
    assert sp.input_size(object()) == sp.INPUT_SIZE                     # no shape info: the default


def test_nms_keeps_the_best_of_overlapping_boxes():
    boxes = np.array([[0, 0, 10, 10], [1, 1, 11, 11], [50, 50, 60, 60]], dtype=float)
    assert sp.nms(boxes, np.array([0.5, 0.9, 0.7])) == [1, 2]
