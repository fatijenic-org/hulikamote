# Dataset Viewer

A local, offline dataset service for the YOLO training datasets
(`primary_anchor`, `helmet_specialist`, `plate_specialist`, `cabin_specialist`).
The dashboard renders its viewer natively in Flutter; a standalone browser UI is also available.
Python stdlib + Pillow only; no CDN. Binds to `127.0.0.1` with a random token.

## Start

In the dashboard, choose side-nav **Datasets** to open the native viewer and start the local service.
For the standalone browser UI, run this from the repo root:

```
hulikamote_backend\venv\Scripts\python.exe training_lab\dataset_viewer.py
```

Flags: `--port 8766`, `--no-open` (do not open the browser), `--idle-exit MINUTES` (quit when unused).
The URL with the token is printed and written to `training_lab/dataset_viewer_cache/server.json`.

The first start reads every label once (about 2 minutes for primary_anchor); the result is cached as JSON
and later starts take a few seconds. Changes made outside the viewer are noticed through folder timestamps.

## Tabs

- **Gallery**: virtual grid, boxes on thumbnails (`B`), filters (split, class, source, no/many/tiny boxes,
  flagged, harvested), sorts, zoom, multi-select (click, Shift-click, drag, Ctrl+A). Click opens the
  lightbox: arrows = previous/next, click a box then `1-9` = class, `Del` = remove box (or quarantine the
  picture), `F` flag, `O` open in Explorer, `Ctrl+Z` undo.
- **Overview**: charts from the labels at once; picture sizes are read in the background.
- **Relabel**: review individual box crops or preview a source/split/class rule before changing labels.
  Selection and rule changes are confirmed before writing; edited pictures can be filtered in Gallery.
- **About**: `DATASET_CARD.md`, sources from `configs/datasets_manifest.yaml`, the CATALOG row, and your notes
  (`datasets/<model>/NOTES.md`, never overwritten by `report.py`). Relabeling marks the card stale; regenerate it
  from the dashboard banner after reviewing the edits.
- **Clean**: runs `data_tools.curate.curate_model` as a dry run, shows findings with samples, then an explicit
  "Apply cleaning" (confirmation required).
- **Quarantine**: browse by reason, restore. Items removed in the viewer remember their split; items moved by
  the curator ask for the split.

## Safety

- Nothing is deleted; "remove" moves files to `datasets/_quarantine/<model>/<reason>/`.
- Every change is logged in `training_lab/dataset_viewer_cache/actions.jsonl` (moved paths, previous label text).
  Label rewrites are atomic; undo is per dataset and in order.
- All writes are refused while a training of that model is running (flags and notes are still allowed).
- `harvest__*` pictures need an extra confirmation. Restoring something that could leak between splits warns.
  There is no "move to another split" and no permanent delete.
- Names are validated; no path traversal. Nothing is written inside `hulikamote_backend/`.

## Car matcher (ReID): clean the vehicles before training

`datasets/reid` is not a box dataset (folders of vehicle photos, one folder = one vehicle: car, motorcycle, tricycle, jeepney, bus,
truck ...), so it has its own entry at the bottom of the Datasets list, **Car matcher (ReID)**, and its own screen (`reid.py`). Use it
when the tracker jumped (one vehicle filed as two), swapped (two vehicles in one folder), or when a vehicle has the wrong class.

**The list** (left): every vehicle, with its class, filters (Suspects, Trained on, Temporary, Repeats, Few photos), a class filter, an
analysis picker and a name search. Click opens a vehicle. **Shift+click** or **Ctrl+click** selects several; a bar at the bottom of the
list then offers *Merge into one*, *Set class*, *Set aside*, *Keep* and *Remove* for all of them.

**The photos** (right): click a photo to pick it, **Shift+click** to pick a range. Then:
- **Move to...**: another vehicle of the same analysis, listed *most alike first* (quick colour-layout match), or a new vehicle, or a
  temporary one;
- **New vehicle**: the picked photos become a vehicle of their own;
- **Set aside (temporary)**: they become a *temporary* vehicle (`datasets/reid/temporary/<analysis>/<vehicle>/`). Temporary photos are
  **not trained on** (the trainer reads `images/` only). Later: **Keep as its own vehicle**, or **Merge this into...** a known vehicle;
- **Remove photos** (reason asked). Other buttons: **Merge another vehicle into this**, **Merge this into...**, **Set this vehicle
  aside**, **Remove whole vehicle**. The zoom icon enlarges a photo.
- Open another vehicle and do the same: nothing is lost between vehicles, and temporary vehicles can take photos from several vehicles
  (open each, pick, *Move to...* the same temporary vehicle).

**Class**: each vehicle has a class (dropdown in its header). The starting class is the tickets' class when the analysis report is still
there; otherwise **Suggest classes** (about a minute) asks the 6-class vehicle model (`scripts/reid_suggest_class.py`, newest
`primary_anchor` run). It only suggests **car** and **motorcycle**, and only when at least 2 photos voted and 3 of 4 agree: on the real
photos it was right for those but mixed up trucks, tricycles and buses, so the rest stay "no class" for you to set (filter *Not set*,
Shift+click the tricycles, *Set class...*). A class you set always wins, then the ticket's, then the model's
(marked *suggested*). "Use the ticket's class" in the menu clears yours. A bike and a truck are never shown as one vehicle: suspects
between two vehicles whose class **you** set (or the ticket gave) differ are hidden. Classes are kept in `datasets/reid/classes.json`.

**Scan** (about a minute): runs `train_reid.py --scan` with the live matcher and marks *maybe the same vehicle* (two vehicles of one
analysis that look alike: probably a jump; shown side by side with **Same vehicle - merge** / **Not the same vehicle**), *maybe two
vehicles* (a folder whose photos do not look alike) and *repeats* (the same vehicle filed by another analysis of the same clip: the
trainer uses it once, so there is nothing to clean there). It also says how many different vehicles training would use. Edits after a
scan mark it stale.

**Undo** goes back one change at a time (moves, merges, class changes, set-asides; kept across restarts). **Removed (n)** lists the
quarantined photos so any can be restored.

Rules are the same as above: nothing is deleted (removed photos go to `datasets/_quarantine/reid/<reason>/<analysis>/<vehicle>/`),
every change is in `dataset_viewer_cache/reid_actions.json`, writes are refused while `train_reid.py` runs, names are validated. Each
move / merge / "not the same" is also noted in `datasets/reid/decisions.jsonl` (`"source": "manager"`), so Harvest > Same car? does not
ask about a pair you already answered. After cleaning here, do not edit the same vehicles in Harvest > Same car? (it files photos from
the tickets again and could duplicate what you moved).
Tests: `hulikamote_backend\venv\Scripts\python.exe -m pytest training_lab/tests/test_reid_manager.py -q`, and
`flutter test test/features/datasets` in `hulikamote_dashboard`.

Cache (thumbnails, index, flags) lives in `training_lab/dataset_viewer_cache/` (git-ignored).
Tests: `hulikamote_backend\venv\Scripts\python.exe -m pytest training_lab/tests/test_dataset_viewer.py -q`
