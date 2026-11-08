"""
inference/providers.py - unit tests for ONNX Runtime Execution Provider Strategy, Dependency Injection,
and automatic GPU -> CPU graceful fallback.
"""
from unittest.mock import patch, MagicMock
import pytest
from inference.providers import (
    get_providers,
    override_providers,
    reset_providers,
    make_session,
    active_provider,
)


def test_provider_resolution_defaults():
    providers = get_providers()
    assert isinstance(providers, list)
    assert len(providers) > 0
    assert "CPUExecutionProvider" in providers
    # The first entry may be a plain name or a (name, options) pair; active_provider() returns the name.
    first = providers[0]
    assert active_provider() == (first[0] if isinstance(first, tuple) else first)


def test_override_and_reset_providers():
    original = get_providers()
    try:
        override_providers(["CPUExecutionProvider"])
        assert get_providers() == ["CPUExecutionProvider"]
        assert active_provider() == "CPUExecutionProvider"
    finally:
        reset_providers()
        assert get_providers() == original


def test_make_session_gpu_fallback_to_cpu():
    """Verify that if CUDA initialization fails, make_session transparently falls back to CPU."""
    with patch("onnxruntime.InferenceSession") as mock_session:
        # First call with CUDA raises an exception (e.g. driver missing)
        # Second call with CPU succeeds
        def side_effect(model_path, providers, **kwargs):
            if "CUDAExecutionProvider" in providers:
                raise RuntimeError("CUDA driver library not found")
            mock = MagicMock()
            mock.providers = providers
            return mock

        mock_session.side_effect = side_effect

        session = make_session("dummy.onnx", providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
        assert session is not None
        assert mock_session.call_count == 2
        # Verify second call used CPUExecutionProvider exclusively
        assert mock_session.call_args_list[1][1]["providers"] == ["CPUExecutionProvider"]


