"""export_onnx.py: the deployed model gets its class-name file, which the app needs to label what it finds."""
import sys
import types
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import export_onnx  # noqa: E402


def test_the_class_file_lists_names_in_class_number_order(tmp_path):
    model = types.SimpleNamespace(names={6: "jeepney", 0: "motorcycle", 1: "car", 2: "bus", 3: "truck", 4: "person", 5: "tricycle"})
    dest = tmp_path / "primary_anchor_train-4_20261111.onnx"
    out = export_onnx.write_class_names(model, dest)
    assert out.name == "primary_anchor_train-4_20261111.onnx.classes.txt"          # the name the app looks for
    assert out.read_text(encoding="utf-8").splitlines() == ["motorcycle", "car", "bus", "truck", "person", "tricycle", "jeepney"]
