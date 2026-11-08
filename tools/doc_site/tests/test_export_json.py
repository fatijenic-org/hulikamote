"""
Tests for export_json.py - JSON block tree converter for doc site.
"""
import json
import pytest
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
DOC_SITE = HERE.parent
REPO_ROOT = DOC_SITE.parents[1]
sys.path.insert(0, str(DOC_SITE))

import export_json
import lib
import build_site
import content_start
import content_datasets
import content_models
import content_pipeline
import content_violations
import content_qa


def test_every_page_converts_with_zero_unknown_tags(tmp_path):
    """Every page converts with zero unknown tags and produces valid JSON."""
    for key, mod_name in build_site.PAGES.items():
        mod = sys.modules.get(mod_name) or __import__(mod_name)
        page = mod.build()
        html_text = page.render()

        out_file = export_json.export_page(page, html_text, tmp_path)
        assert out_file.exists()
        data = json.loads(out_file.read_text(encoding="utf-8"))

        assert data["slug"] == page.slug
        assert data["title"] == page.title
        assert len(data["blocks"]) > 0


def test_unknown_html_tag_fails_loudly():
    """Unknown HTML tags must raise ValueError, never be dropped silently."""
    page = lib.Page("test.html", "99", "Test", "Lede")
    page.add("<marquee>This is invalid tag</marquee>")
    html_text = page.render()

    with pytest.raises(ValueError, match="Unknown block HTML tag: <marquee>"):
        export_json.html_to_page_dict(page, html_text)


def test_unknown_inline_tag_fails_loudly():
    """Unknown inline HTML tags must raise ValueError."""
    page = lib.Page("test.html", "99", "Test", "Lede")
    page.add("<p><blink>blinking text</blink></p>")
    html_text = page.render()

    with pytest.raises(ValueError, match="Unknown inline HTML tag: <blink>"):
        export_json.html_to_page_dict(page, html_text)


def test_code_block_keeps_true_line_numbers(tmp_path):
    """A code block keeps its true line numbers and walks explanations."""
    page = content_violations.build()
    html_text = page.render()
    data = export_json.html_to_page_dict(page, html_text)

    # Find violation cards
    cards = [b for b in data["blocks"] if b.get("type") == "card"]
    assert len(cards) == 20

    # Counterflow card has code blocks
    cf = next(c for c in cards if c["key"] == "counterflow")
    code_blocks = [b for b in cf["bottom"] if b.get("type") == "code"]
    assert len(code_blocks) >= 1

    first_code = code_blocks[0]
    assert first_code["path"] == "hulikamote_backend/engine/violations/counterflow.py"
    assert first_code["first"] > 0
    assert first_code["last"] >= first_code["first"]

    # Verify line numbers in lines list
    numbered_lines = [line["n"] for line in first_code["lines"] if line["n"] is not None]
    assert numbered_lines[0] == first_code["first"]
    assert numbered_lines[-1] == first_code["last"]

    # Verify notes have marks and line numbers
    assert len(first_code["notes"]) > 0
    for note in first_code["notes"]:
        assert note["mark"] >= 1
        assert first_code["first"] <= note["line"] <= first_code["last"]
        assert len(note["text"]) > 0


def test_all_block_types_handled():
    """Verify converter produces all typed blocks: heading, paragraph, list, steps, kv, table, callout, cmd, refs, code, figure, card."""
    # Build all pages in memory
    all_blocks = []
    for mod_name in ("content_start", "content_datasets", "content_models", "content_pipeline", "content_violations", "content_qa"):
        mod = __import__(mod_name)
        page = mod.build()
        html_text = page.render()
        data = export_json.html_to_page_dict(page, html_text)
        all_blocks.extend(data["blocks"])

    block_types = {b["type"] for b in all_blocks}
    expected_types = {"heading", "paragraph", "list", "steps", "table", "callout", "cmd", "refs", "code", "figure", "card"}
    for exp in expected_types:
        assert exp in block_types, f"Missing expected block type: {exp}"


def test_figure_charts_and_scenes():
    """Verify figure blocks have kind hbar, line, or scene."""
    all_blocks = []
    for mod_name in ("content_start", "content_datasets", "content_models", "content_pipeline"):
        mod = __import__(mod_name)
        page = mod.build()
        html_text = page.render()
        data = export_json.html_to_page_dict(page, html_text)
        all_blocks.extend(data["blocks"])

    figures = [b for b in all_blocks if b.get("type") == "figure"]
    kinds = {f["kind"] for f in figures}
    assert "hbar" in kinds
    assert "line" in kinds
    assert "scene" in kinds

    # Verify hbar structure
    hbar_fig = next(f for f in figures if f["kind"] == "hbar")
    assert "groups" in hbar_fig and len(hbar_fig["groups"]) > 0
    assert "series" in hbar_fig and len(hbar_fig["series"]) > 0

    # Verify line structure
    line_fig = next(f for f in figures if f["kind"] == "line")
    assert "series" in line_fig and len(line_fig["series"]) > 0
    assert len(line_fig["series"][0]["points"]) > 0

    # Verify scene structure
    scene_fig = next(f for f in figures if f["kind"] == "scene")
    assert "primitives" in scene_fig["scene"] and len(scene_fig["scene"]["primitives"]) > 0


def test_glossary_export(tmp_path):
    """Verify glossary.json export contains terms and definitions."""
    out_file = export_json.export_glossary(tmp_path)
    assert out_file.exists()
    glossary = json.loads(out_file.read_text(encoding="utf-8"))
    assert "YOLO" in glossary
    assert "DeepSORT" in glossary
    assert len(glossary) >= 100
