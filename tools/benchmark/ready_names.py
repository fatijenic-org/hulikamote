"""Folder names under benchmarks/public_clips/ready/: <origin>__<violations>, read from the `ready:` field of benchmarks/public_sources.yaml."""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

import yaml

MANIFEST = Path(__file__).resolve().parents[2] / "benchmarks" / "public_sources.yaml"


@lru_cache(maxsize=None)
def _names() -> dict[str, str]:
    data = yaml.safe_load(MANIFEST.read_text(encoding="utf-8"))
    return {s["id"]: s["ready"] for s in data["sources"] if s.get("ready")}


def ready(source_id: str) -> str:
    """The folder in ready/ for a source id (the id itself when the manifest gives no name)."""
    return _names().get(source_id, source_id)
