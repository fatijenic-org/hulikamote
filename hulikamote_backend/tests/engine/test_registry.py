"""engine/registry.py - the model registry takes an injected session factory."""
from unittest.mock import MagicMock, patch

from engine.registry import ModelRegistry


def test_model_registry_dependency_injection(tmp_path):
    """Verify that ModelRegistry accepts and invokes an injected session_factory."""
    mock_factory = MagicMock()
    mock_session = MagicMock()
    mock_factory.return_value = mock_session

    config_file = tmp_path / "camera_config.json"
    config_file.write_text('{"active_violations": []}')

    dummy_model = tmp_path / "yolov8n.onnx"
    dummy_model.write_bytes(b"dummy")

    with patch("pathlib.Path.parent") as mock_parent:
        registry = ModelRegistry(str(config_file), session_factory=mock_factory)
        # Directly test loading with injected factory
        registry._load_model("test_model", dummy_model)
        mock_factory.assert_called_with(str(dummy_model))
        assert registry.models["test_model"] == mock_session
