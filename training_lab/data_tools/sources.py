"""
sources.py - Download public datasets from trustworthy hosts into the staging folders (see stage.py).

Hosts handled without any account or key:
    mendeley     data.mendeley.com public API (peer-reviewed data repository, DOI per dataset)
    zenodo       zenodo.org records (CERN, DOI per record)
    huggingface  public dataset repos on huggingface.co
    openimages   Google's Open Images V7 (CC BY), only the classes / images we ask for
    url          any direct file URL (use only for an official project page)

Roboflow needs your own key and stays in fetch_datasets.py. Every download is cached under
datasets/_downloads/ (delete a folder to fetch again) and records where it came from in SOURCE.json.
"""
from __future__ import annotations

import csv
import hashlib
import io
import json
import shutil
import time
import zipfile
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path

from .common import DATASETS, DOWNLOADS, ROBOFLOW_SPLIT, sha256_file, xyxy_to_yolo
from .stage import Stage, import_coco, import_yolo_tree

ARCHIVES = DOWNLOADS / "_archives"          # downloaded zips (deleted after a successful import unless keep_archive)
CACHE = DOWNLOADS / "_cache"                # small reusable files (e.g. filtered Open Images rows)
TMP = DOWNLOADS / "_tmp"
UA = {"User-Agent": "huli-kamote-dataset-fetch/1.0 (thesis project)"}


# --------------------------------------------------------------------------- download helpers

def download_file(url: str, dest: Path, expected_size: int | None = None, retries: int = 4, quiet: bool = False) -> Path:
    """Stream a file to `dest`, resuming a half-finished '.part' file and retrying on network errors."""
    import requests
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and (expected_size is None or dest.stat().st_size == expected_size):
        return dest
    part = dest.with_suffix(dest.suffix + ".part")
    for attempt in range(1, retries + 1):
        try:
            have = part.stat().st_size if part.exists() else 0
            headers = dict(UA, **({"Range": f"bytes={have}-"} if have else {}))
            with requests.get(url, headers=headers, stream=True, timeout=60, allow_redirects=True) as r:
                if r.status_code == 416:                       # asked past the end: the file is complete
                    break
                r.raise_for_status()
                if have and r.status_code != 206:              # server ignored Range: start over
                    have = 0
                total = int(r.headers.get("Content-Length", 0)) + have
                mode = "ab" if have else "wb"
                done, next_mark = have, 0.1
                with open(part, mode) as f:
                    for chunk in r.iter_content(1 << 20):
                        f.write(chunk)
                        done += len(chunk)
                        if not quiet and total and done / total >= next_mark:
                            print(f"    {dest.name}: {done / 1e6:,.0f} / {total / 1e6:,.0f} MB", flush=True)
                            next_mark += 0.1
            break
        except Exception as e:                                  # network hiccup: wait and resume
            print(f"    ! download attempt {attempt}/{retries} failed: {e}", flush=True)
            if attempt == retries:
                raise
            time.sleep(3 * attempt)
    part.replace(dest)
    if expected_size is not None and dest.stat().st_size != expected_size:
        raise RuntimeError(f"{dest.name}: got {dest.stat().st_size} bytes, expected {expected_size}")
    return dest


def extract_zip(archive: Path, dest: Path) -> Path:
    """Unzip without trusting member paths (no '../' escapes)."""
    dest.mkdir(parents=True, exist_ok=True)
    root = dest.resolve()
    with zipfile.ZipFile(archive) as z:
        for member in z.infolist():
            target = (dest / member.filename).resolve()
            if root != target and root not in target.parents:
                raise RuntimeError(f"unsafe path in {archive.name}: {member.filename}")
        z.extractall(dest)
    return dest


def _json(url: str, retries: int = 6):
    """GET a JSON document; retries because a DNS or connection hiccup should not abort a long fetch."""
    import requests
    for attempt in range(retries):
        try:
            r = requests.get(url, headers=UA, timeout=60)
            r.raise_for_status()
            return r.json()
        except requests.RequestException:
            if attempt == retries - 1:
                raise
            time.sleep(4 * (attempt + 1))


def _meta(src: dict, **extra) -> dict:
    return {"id": src["id"], "retrieved": date.today().isoformat(), "license": src.get("license", "unknown"),
            "country": src.get("country"), "ph": bool(src.get("ph", False)), "trust": src.get("trust"),
            "citation": src.get("citation"), "notes": src.get("notes"), **extra}


def _finish_archive(archive: Path, src: dict, tmp: Path) -> None:
    shutil.rmtree(tmp, ignore_errors=True)
    if not src.get("keep_archive", False):
        archive.unlink(missing_ok=True)


def _import_opts(src: dict) -> dict:
    """Manifest options that steer import_yolo_tree: ratios, image_dirs, label_format."""
    return {"ratios": tuple(src.get("ratios", (0.8, 0.1, 0.1))), "image_dirs": src.get("image_dirs"),
            "label_format": src.get("label_format", "yolo")}


def _names_from_tree(root: Path, src: dict) -> list[str]:
    """Class names: the manifest's `names`, else a classes.txt / data.yaml found in the download."""
    if src.get("names"):
        return [str(n) for n in src["names"]]
    for f in root.rglob("classes.txt"):
        return [l.strip() for l in f.read_text(encoding="utf-8").splitlines() if l.strip()]
    for f in root.rglob("data.yaml"):
        import yaml
        names = (yaml.safe_load(f.read_text(encoding="utf-8")) or {}).get("names")
        if names:
            return [str(names[k]) for k in sorted(names)] if isinstance(names, dict) else [str(n) for n in names]
    raise RuntimeError(f"[{src['id']}] no class names found: add `names: [...]` to the manifest entry")


# --------------------------------------------------------------------------- Mendeley Data

def fetch_mendeley(src: dict, out: Path) -> Path:
    """Whole dataset zip from the public API. Needs: dataset (id). Optional: version, names, ratios."""
    meta = _json(f"https://data.mendeley.com/public-api/datasets/{src['dataset']}")
    version = src.get("version", meta.get("version", 1))
    archive = download_file(f"https://data.mendeley.com/public-api/zip/{src['dataset']}/download/{version}",
                            ARCHIVES / f"mendeley_{src['dataset']}_v{version}.zip")
    tmp = extract_zip(archive, TMP / src["id"])
    stage = Stage(src["id"], _names_from_tree(tmp, src), out)
    seen = import_yolo_tree(tmp, stage, **_import_opts(src))
    stage.finish(_meta(src, host="mendeley", url=f"https://data.mendeley.com/datasets/{src['dataset']}/{version}",
                       doi=(meta.get("doi") or {}).get("id") if isinstance(meta.get("doi"), dict) else meta.get("doi"),
                       title=meta.get("name"), archive_sha256=sha256_file(archive), import_stats=dict(seen)))
    _finish_archive(archive, src, tmp)
    return out


# --------------------------------------------------------------------------- Zenodo

def fetch_zenodo(src: dict, out: Path) -> Path:
    """Files of a Zenodo record. Needs: record (id), files (list of file names). Optional: names, ratios."""
    rec = _json(f"https://zenodo.org/api/records/{src['record']}")
    wanted = set(src["files"])
    tmp = TMP / src["id"]
    archives, shas = [], {}
    for f in rec["files"]:
        if f["key"] not in wanted:
            continue
        arc = download_file(f["links"]["self"], ARCHIVES / f"zenodo_{src['record']}_{f['key']}", f.get("size"))
        algo, _, want = f.get("checksum", "md5:").partition(":")
        if algo == "md5" and want:
            md5 = hashlib.md5()
            with open(arc, "rb") as fh:
                while block := fh.read(1 << 20):
                    md5.update(block)
            if md5.hexdigest() != want:
                raise RuntimeError(f"{arc.name}: checksum mismatch (Zenodo says {want}, got {md5.hexdigest()})")
        shas[f["key"]] = sha256_file(arc)
        if arc.suffix.lower() != ".zip":
            raise RuntimeError(f"{arc.name}: only .zip archives are supported (unrar/7z are not installed)")
        extract_zip(arc, tmp)
        archives.append(arc)
    stage = Stage(src["id"], _names_from_tree(tmp, src), out)
    seen = import_yolo_tree(tmp, stage, **_import_opts(src))
    md = rec["metadata"]
    stage.finish(_meta(src, host="zenodo", url=f"https://zenodo.org/records/{src['record']}", doi=rec.get("doi"),
                       title=md.get("title"), creators=[c["name"] for c in md.get("creators", [])],
                       archive_sha256=shas, import_stats=dict(seen)))
    for arc in archives:
        _finish_archive(arc, src, tmp)
    return out


# --------------------------------------------------------------------------- Hugging Face

def fetch_huggingface(src: dict, out: Path) -> Path:
    """A public dataset repo. Needs: repo. Optional: patterns, layout ('coco_zips' | 'yolo_tree'), names."""
    from huggingface_hub import snapshot_download
    tmp = TMP / src["id"]
    snapshot_download(repo_id=src["repo"], repo_type="dataset", local_dir=str(tmp),
                      allow_patterns=src.get("patterns"))
    for z in sorted(tmp.rglob("*.zip")):
        extract_zip(z, z.with_suffix(""))
        z.unlink()
    layout = src.get("layout", "yolo_tree")
    if layout == "coco_zips":                                   # data/<split>/_annotations.coco.json + images
        cats = None
        for jf in sorted(tmp.rglob("_annotations.coco.json")):
            data = json.loads(jf.read_text(encoding="utf-8"))
            cats = [c["name"] for c in sorted(data["categories"], key=lambda c: c["id"]) if c["name"] not in src.get("skip_categories", [])]
            break
        stage = Stage(src["id"], src.get("names") or cats, out)
        seen = Counter()
        from .common import SPLIT_ALIASES
        for jf in sorted(tmp.rglob("_annotations.coco.json")):
            split = SPLIT_ALIASES.get(jf.parent.name.lower())
            if split is None:
                raise RuntimeError(f"{jf}: cannot tell train / val / test from the folder name")
            seen.update(import_coco(jf, jf.parent, stage, split))
    else:
        stage = Stage(src["id"], _names_from_tree(tmp, src), out)
        seen = import_yolo_tree(tmp, stage, **_import_opts(src))
    info = _json(f"https://huggingface.co/api/datasets/{src['repo']}")
    stage.finish(_meta(src, host="huggingface", url=f"https://huggingface.co/datasets/{src['repo']}",
                       revision=info.get("sha"), import_stats=dict(seen)))
    shutil.rmtree(tmp, ignore_errors=True)
    return out


# --------------------------------------------------------------------------- Open Images V7

OI_BBOX = {
    "train": "https://storage.googleapis.com/openimages/v6/oidv6-train-annotations-bbox.csv",
    "validation": "https://storage.googleapis.com/openimages/v5/validation-annotations-bbox.csv",
    "test": "https://storage.googleapis.com/openimages/v5/test-annotations-bbox.csv",
}
OI_CLASSES_URL = "https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions-boxable.csv"
OI_IMAGE_URL = "https://open-images-dataset.s3.amazonaws.com/{split}/{image_id}.jpg"
OI_SPLIT_OURS = {"train": "train", "validation": "val", "test": "test"}


def _oi_class_ids(display_names: list[str]) -> dict[str, str]:
    """Open Images display name -> machine id ('/m/01jfm_')."""
    import requests
    r = requests.get(OI_CLASSES_URL, headers=UA, timeout=60)
    r.raise_for_status()
    wanted = set(display_names)
    ids = {row[1]: row[0] for row in csv.reader(io.StringIO(r.text)) if len(row) == 2 and row[1] in wanted}
    missing = wanted - set(ids)
    if missing:
        raise RuntimeError(f"Open Images has no boxable class named {sorted(missing)}")
    return ids


def _oi_rows(split: str, mids: set[str]) -> list[dict]:
    """Annotation rows of the wanted classes for one split, cached (the train csv alone is ~1 GB)."""
    import requests
    CACHE.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha1(("|".join(sorted(mids))).encode()).hexdigest()[:10]
    cache = CACHE / f"oi_{split}_{key}.csv"
    if not cache.exists():
        print(f"    reading the Open Images {split} annotation file (streamed, nothing else is stored)...", flush=True)
        part = cache.with_suffix(".part")
        with requests.get(OI_BBOX[split], headers=UA, stream=True, timeout=120) as r, \
                open(part, "w", newline="", encoding="utf-8") as f:
            r.raise_for_status()
            rd = csv.reader(l.decode("utf-8") for l in r.iter_lines())
            header = next(rd)
            w = csv.writer(f)
            w.writerow(header)
            li = header.index("LabelName")
            for row in rd:
                if row and row[li] in mids:
                    w.writerow(row)
        part.replace(cache)
    with open(cache, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _oi_download_image(split: str, image_id: str, dest: Path) -> bool:
    import requests
    if dest.exists():
        return True
    for attempt in range(3):
        try:
            r = requests.get(OI_IMAGE_URL.format(split=split, image_id=image_id), headers=UA, timeout=40)
            if r.status_code == 404:
                return False
            r.raise_for_status()
            dest.write_bytes(r.content)
            return True
        except Exception:
            time.sleep(1 + attempt)
    return False


def fetch_openimages(src: dict, out: Path) -> Path:
    """
    Needs: classes {Open Images class name: our staging class name}. Optional: max_images {train, validation, test}.
    Group-of boxes ('a crowd of plates') and depictions (drawings) are skipped. Images are picked by a fixed hash,
    so a re-run gets the same ones.
    """
    mapping: dict[str, str] = src["classes"]
    names = list(dict.fromkeys(mapping.values()))
    ids = _oi_class_ids(list(mapping))
    mid_to_idx = {ids[k]: names.index(v) for k, v in mapping.items()}
    caps = {"train": 2000, "validation": 400, "test": 400, **src.get("max_images", {})}
    stage = Stage(src["id"], names, out)
    raw = TMP / src["id"]
    seen = Counter()
    for split in ("train", "validation", "test"):
        by_image: dict[str, list] = defaultdict(list)
        for row in _oi_rows(split, set(mid_to_idx)):
            if row["IsGroupOf"] == "1" or row["IsDepiction"] == "1":
                continue
            x1, x2, y1, y2 = (float(row[k]) for k in ("XMin", "XMax", "YMin", "YMax"))
            if x2 - x1 <= 0 or y2 - y1 <= 0:
                continue
            by_image[row["ImageID"]].append((mid_to_idx[row["LabelName"]], *xyxy_to_yolo(x1, y1, x2, y2, 1.0, 1.0)))
        chosen = sorted(by_image, key=lambda i: hashlib.sha1(f"oi:{i}".encode()).hexdigest())[:caps[split]]
        print(f"    {split}: {len(by_image):,} images have the classes, taking {len(chosen):,}", flush=True)
        raw.mkdir(parents=True, exist_ok=True)

        staged_dir = out / ROBOFLOW_SPLIT[OI_SPLIT_OURS[split]] / "images"

        def job(image_id: str) -> tuple[str, str]:
            if (staged_dir / f"{image_id}.jpg").exists():                  # a resumed run: this one is already here
                return image_id, "have"
            return image_id, "ok" if _oi_download_image(split, image_id, raw / f"{image_id}.jpg") else "missing"

        with ThreadPoolExecutor(max_workers=src.get("workers", 12)) as pool:
            for n, (image_id, state) in enumerate(pool.map(job, chosen), 1):
                if state == "missing":
                    seen["missing_image"] += 1
                elif state == "ok":
                    stage.add(raw / f"{image_id}.jpg", by_image[image_id], OI_SPLIT_OURS[split], move=True)
                seen[OI_SPLIT_OURS[split]] += 1 if state != "missing" else 0
                if n % 500 == 0:
                    print(f"      {n:,} / {len(chosen):,}", flush=True)
    stage.finish(_meta(src, host="openimages", url="https://storage.googleapis.com/openimages/web/index.html",
                       class_ids=ids, import_stats=dict(seen),
                       license="Annotations CC BY 4.0 (Google); images CC BY 2.0 (original Flickr authors)"))
    shutil.rmtree(raw, ignore_errors=True)
    return out


# --------------------------------------------------------------------------- plain URL

def fetch_url(src: dict, out: Path) -> Path:
    """A direct .zip link (official project page only). Needs: url. Optional: names, ratios."""
    archive = download_file(src["url"], ARCHIVES / f"{src['id']}.zip")
    tmp = extract_zip(archive, TMP / src["id"])
    stage = Stage(src["id"], _names_from_tree(tmp, src), out)
    seen = import_yolo_tree(tmp, stage, **_import_opts(src))
    stage.finish(_meta(src, host="url", url=src["url"], archive_sha256=sha256_file(archive), import_stats=dict(seen)))
    _finish_archive(archive, src, tmp)
    return out


HANDLERS = {"mendeley": fetch_mendeley, "zenodo": fetch_zenodo, "huggingface": fetch_huggingface,
            "openimages": fetch_openimages, "url": fetch_url}


def fetch(src: dict) -> Path:
    """Staging folder for a manifest entry (cached: a folder with data.yaml is never fetched twice)."""
    out = DOWNLOADS / src.get("stage_as", src["id"])
    if (out / "data.yaml").exists():
        return out
    kind = src.get("source")
    if kind not in HANDLERS:
        raise SystemExit(f"[{src['id']}] unknown source '{kind}' (use one of {sorted(HANDLERS)} or roboflow)")
    print(f"  fetching {src['id']} from {kind}...", flush=True)
    return HANDLERS[kind](src, out)
