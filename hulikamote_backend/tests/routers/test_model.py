"""
routers/model.py - POST /upload-model: a .zip with exactly one .onnx goes to models/<category>/.
config.json / classes.txt are optional and only give the class names.

The route works on the relative folder "models/", so every test runs inside a temp
working directory and never touches the real models/ folder.
"""
import io
import json
import zipfile

import pytest
from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


@pytest.fixture(autouse=True)
def temp_cwd(tmp_path, monkeypatch):
    """The route resolves 'models/…' against the current directory: make that a temp dir."""
    monkeypatch.chdir(tmp_path)
    return tmp_path


def _zip(files: dict) -> io.BytesIO:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, content in files.items():
            z.writestr(name, content)
    buf.seek(0)
    return buf


def _upload(buf, filename="model.zip", **data):
    return client.post("/upload-model", data=data, files={"file": (filename, buf, "application/zip")})


def test_upload_model_success(temp_cwd):
    cfg = json.dumps({"classes": ["no_helmet", "helmet"]})
    response = _upload(_zip({"traffic.onnx": b"dummy onnx content", "config.json": cfg}))

    assert response.status_code == 201
    assert "traffic.onnx" in response.json()["detail"]
    assert (temp_cwd / "models" / "Uncategorized" / "traffic.onnx").read_bytes() == b"dummy onnx content"
    classes = temp_cwd / "models" / "Uncategorized" / "traffic.onnx.classes.txt"
    assert classes.read_text().splitlines() == ["no_helmet", "helmet"]
    assert not (temp_cwd / "models" / "uploads" / "model.zip").exists()   # the zip is removed afterwards


def test_upload_goes_to_the_chosen_category(temp_cwd):
    response = _upload(_zip({"helmet.onnx": b"x"}), category="Helmet Detectors")

    assert response.status_code == 201
    assert (temp_cwd / "models" / "Helmet Detectors" / "helmet.onnx").exists()


def test_upload_config_is_optional(temp_cwd):
    response = _upload(_zip({"traffic.onnx": b"dummy"}))

    assert response.status_code == 201
    assert not (temp_cwd / "models" / "Uncategorized" / "traffic.onnx.classes.txt").exists()


def test_upload_without_an_onnx_file_is_rejected(temp_cwd):
    response = _upload(_zip({"config.json": "{}"}), filename="bad.zip")

    assert response.status_code == 400
    assert "No .onnx file found" in response.json()["detail"]
    assert not (temp_cwd / "models" / "uploads" / "bad.zip").exists()   # cleaned up even on error


def test_upload_with_two_onnx_files_is_rejected():
    response = _upload(_zip({"a.onnx": b"1", "b.onnx": b"2"}))

    assert response.status_code == 400
    assert "Multiple .onnx files" in response.json()["detail"]


def test_upload_only_accepts_zip_files():
    response = client.post("/upload-model", files={"file": ("model.onnx", io.BytesIO(b"x"), "application/octet-stream")})

    assert response.status_code == 400
    assert "Only .zip files" in response.json()["detail"]
