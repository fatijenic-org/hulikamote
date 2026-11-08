"""The public-clip downloader: the source list is sound and the selection / planning logic behaves (no network is used)."""
import pytest

from tools.benchmark import fetch_public_clips as fpc
from tools.benchmark.violations import NEEDS

DATA = fpc.load()
SOURCES = DATA["sources"]
KEYS = {n.key for n in NEEDS}
HOSTS = {"http", "hf", "osf", "mendeley", "zenodo", "kaggle", "roboflow", "manual"}


def test_every_source_has_what_the_script_needs():
    for s in SOURCES:
        for field in ("id", "title", "kind", "violations", "license", "page", "host", "tier"):
            assert s.get(field), f"{s.get('id')}: missing {field}"
        assert s["host"] in HOSTS and (s["tier"] in fpc.TIERS or s["tier"] == "manual")
        assert (s["host"] == "manual") == (s["tier"] == "manual")
        if s["host"] == "manual":
            assert s.get("how"), f"{s['id']}: a manual source must say what to do"
        if s["host"] == "http":
            assert all(f["url"].startswith("http") and f["name"] for f in s["files"])
        if s["host"] == "hf":
            assert "/" in s["repo"]
        if s["host"] == "osf":
            assert s["node"]


def test_ids_are_unique_and_violations_are_real_keys():
    ids = [s["id"] for s in SOURCES]
    assert len(ids) == len(set(ids))
    for s in SOURCES:
        assert set(s["violations"]) <= KEYS, f"{s['id']}: {set(s['violations']) - KEYS}"


def test_every_violation_has_a_coverage_note_and_no_note_is_stale():
    # follows the live list (tools/benchmark/violations.py), so a new violation fails here until it gets a note
    assert set(DATA["coverage"]) == KEYS


def test_coverage_rows_classify_every_violation():
    rows = {r["key"]: r for r in fpc.coverage_rows(DATA, NEEDS)}
    assert set(rows) == KEYS
    assert rows["no_helmet"]["status"] == "PUBLIC" and "ridesafe_400" in rows["no_helmet"]["core"]
    assert rows["red_light"]["status"] == "PUBLIC" and "runningredlight_vn" in rows["red_light"]["by_hand"]
    assert rows["no_seatbelt"]["status"] == "OPT-IN"                        # only a Roboflow set that needs your own key
    assert rows["signal_light"]["status"] == "BY HAND"                      # only a gated set exists
    assert rows["pickup_passengers"]["status"] == "FILM OWN"                # a frame check with no public set
    kinds = {n.key: n.kind for n in NEEDS}
    for key, r in rows.items():
        if r["status"] == "ANY FIXED CLIP":
            assert kinds[key] == "zone rule" and not r["downloadable"] and not r["by_hand"]
        if r["status"] == "FILM OWN":
            assert kinds[key] != "zone rule"


def test_plain_run_is_the_lean_core_and_never_manual():
    ids = {s["id"] for s in fpc.select(SOURCES)}
    assert {"idiap_traffic_junction", "dhaka_helmet_triple", "ridesafe_400", "medellin_pedestrian_cctv"} <= ids
    assert "meteor" not in ids and "seatbelt_rf" not in ids
    assert all(next(s for s in SOURCES if s["id"] == i)["host"] != "manual" for i in ids)


def test_plain_run_uses_sample_files_but_only_and_tier_do_not(monkeypatch):
    seen = []

    def fake_plan(src, sample=False):
        seen.append((src["id"], sample))
        return {"files": [], "license": None}
    monkeypatch.setattr(fpc, "plan", fake_plan)
    assert fpc.main(["--dry-run"]) == 0
    assert seen and all(sample for _, sample in seen)
    seen.clear()
    assert fpc.main(["--only", "ridesafe_400", "--dry-run"]) == 0
    assert seen == [("ridesafe_400", False)]
    seen.clear()
    assert fpc.main(["--tier", "small", "--dry-run"]) == 0
    assert seen and not any(sample for _, sample in seen)


def test_select_tier_widens_but_skips_manual():
    small = {s["id"] for s in fpc.select(SOURCES, tier="small")}
    large = {s["id"] for s in fpc.select(SOURCES, tier="large")}
    assert small < large and "ridesafe_400" in large and "meteor" not in large and "seatbelt_rf" in small
    assert "meteor" in {s["id"] for s in fpc.select(SOURCES, tier="huge")}
    assert not any(s["host"] == "manual" for s in fpc.select(SOURCES, tier="huge"))


def test_select_only_and_unknown_id():
    assert [s["id"] for s in fpc.select(SOURCES, only=["atg_pvd"])] == ["atg_pvd"]
    with pytest.raises(SystemExit):
        fpc.select(SOURCES, only=["nope"])


def test_pick_matches_globs_and_keeps_all_without_patterns():
    paths = ["README.md", "a/b.zip", "constructor_cvat_videoset1.txt", "videoset1_videos_part1.zip", "videoset1_videos_part2.zip"]
    assert fpc.pick(paths, None) == paths
    assert fpc.pick(paths, ["constructor_cvat_videoset*.txt", "videoset1_videos_part1.zip"]) == paths[2:4]


def test_hf_plan_uses_the_real_file_size_and_the_sample_list(monkeypatch):
    tree = [{"type": "file", "path": ".gitattributes", "size": 1},
            {"type": "file", "path": "README.md", "size": 2000},
            {"type": "file", "path": "videoset1_videos_part1.zip", "size": 135, "lfs": {"size": 4_822_000_000}},
            {"type": "file", "path": "videoset1_videos_part2.zip", "size": 135, "lfs": {"size": 4_502_000_000}},
            {"type": "file", "path": "videoset1_xml_annots_with_rider_motor_poly.zip", "size": 135, "lfs": {"size": 137_000_000}},
            {"type": "directory", "path": "x"}]

    def fake(url):
        return tree if "/tree/" in url else {"gated": False, "cardData": {"license": "cc-by-nc-sa-4.0"}}
    monkeypatch.setattr(fpc, "_get_json", fake)
    src = next(s for s in SOURCES if s["id"] == "ridesafe_400")
    whole = fpc.plan(src)
    assert [f["name"] for f in whole["files"]] == ["README.md", "videoset1_videos_part1.zip", "videoset1_videos_part2.zip",
                                                       "videoset1_xml_annots_with_rider_motor_poly.zip"]
    assert whole["files"][1]["size"] == 4_822_000_000 and whole["license"] == "cc-by-nc-sa-4.0"
    sample = fpc.plan(src, sample=True)
    assert [f["name"] for f in sample["files"]] == ["README.md", "videoset1_videos_part1.zip",
                                                         "videoset1_xml_annots_with_rider_motor_poly.zip"]   # the labels come along
    assert sample["files"][1]["url"].endswith("/resolve/main/videoset1_videos_part1.zip")


def test_a_gated_repo_is_not_planned(monkeypatch):
    monkeypatch.setattr(fpc, "_get_json", lambda url: {"gated": "auto"})
    with pytest.raises(PermissionError):
        fpc.hf_listing("ChaiJohn/TLD")


def test_manual_sources_only_print_instructions(capsys, tmp_path):
    src = next(s for s in SOURCES if s["host"] == "manual")
    assert fpc.fetch(src, [], tmp_path / "x") is False
    assert "by hand" in capsys.readouterr().out
    assert not (tmp_path / "x").exists()


def test_list_and_coverage_print_without_network(capsys):
    assert fpc.main(["--list"]) == 0
    assert "idiap_traffic_junction" in capsys.readouterr().out
    assert fpc.main(["--coverage"]) == 0
    assert "pickup_passengers" in capsys.readouterr().out


def test_refuses_to_write_inside_the_backend(tmp_path):
    with pytest.raises(SystemExit):
        fpc.main(["--out", str(fpc.REPO / "hulikamote_backend" / "public_clips_test")])


def test_the_download_folder_is_git_ignored():
    text = (fpc.REPO / ".gitignore").read_text(encoding="utf-8")
    assert "benchmarks/public_clips/" in text


def test_osf_plan_walks_folders_and_applies_the_sample_list(monkeypatch):
    base = "https://api.osf.io/v2/nodes/4pwj8"

    def file(name, size):
        return {"attributes": {"kind": "file", "materialized_path": f"/HELMET_DATASET/{name}", "size": size},
                "links": {"download": f"https://osf.io/download/{name.replace('/', '_')}/"}}

    def fake(url):
        if "embed=license" in url:
            return {"data": {"embeds": {"license": {"data": {"attributes": {"name": "CC-By Attribution 4.0 International"}}}}}}
        if url.endswith("/osfstorage/"):
            return {"data": [{"attributes": {"kind": "folder", "materialized_path": "/HELMET_DATASET/"},
                              "relationships": {"files": {"links": {"related": {"href": f"{base}/files/osfstorage/folder1/"}}}}}],
                    "links": {"next": None}}
        assert url.endswith("/folder1/")
        return {"data": [file("annotation.zip", 3_000_000), file("data_split.csv", 21_000), file("Readme.txt", 700),
                         file("image/part_7.zip", 1_093_000_000), file("image/part_1.zip", 4_694_000_000)], "links": {"next": None}}
    monkeypatch.setattr(fpc, "_get_json", fake)
    src = next(s for s in SOURCES if s["id"] == "helmet_myanmar")
    whole = fpc.plan(src)
    assert len(whole["files"]) == 5 and whole["license"] == "CC-By Attribution 4.0 International"
    sample = fpc.plan(src, sample=True)
    assert sorted(f["name"] for f in sample["files"]) == ["HELMET_DATASET/Readme.txt", "HELMET_DATASET/annotation.zip",
                                                          "HELMET_DATASET/data_split.csv", "HELMET_DATASET/image/part_7.zip"]
    assert sum(f["size"] for f in sample["files"]) < 1.2e9
