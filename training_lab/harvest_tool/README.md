# Harvest tool

Turns the system's own mistakes and confirmations into training data, in one place.

**What it never does:** write inside `hulikamote_backend/`, touch a dataset while that model is training,
upload anything, or add a picture to a dataset without a human having checked it.

## The loop

```
 1 Analyze clips   2 Collect          3 Check & label       4 Add to dataset     5 Train → Deploy
 Forensic Analyzer  harvest.py collect  page in your browser  harvest.py accept    Training Lab
        └──────────────────────────────── repeat: fewer mistakes each round ────────────────────────┘
```

| Step | What happens | Where |
|---|---|---|
| 2 Collect | Pictures the system was unsure about are copied into the inbox, with the model's suggested boxes | Training Lab → **5 Harvest** → Collect, or `python training_lab/harvest.py collect` |
| 3 Check & label | One picture at a time: **Enter** = the boxes are right, drag = draw one, **N** = nothing here, **S** = not sure | Training Lab → **5 Harvest** → Check & label, or `python training_lab/harvest.py serve` |
| 4 Add | Finished pictures go into the model's dataset (refused while that model trains) | page button, Training Lab, or `python training_lab/harvest.py accept <model>` |

Pictures come from every saved forensic analysis, **reviewed or not**. Review decisions in the forensic
screen only set the order (rejected tickets first: the model is most likely wrong there).

## What lands in the inbox

| Situation | Model | Question you are asked |
|---|---|---|
| Ticket says **no plate** | Plate | "Is a plate visible?" (the model's guess is drawn if it sees one) |
| Ticket for something else, plate was never read | Plate | same |
| Plate was read | Plate | "Is the box right?" |
| **No helmet** ticket | Helmet | "Box each rider: with / without helmet" |
| No seatbelt / phone / side mirror ticket | Cabin | "Box what you can see" |
| Counterflow, parking, turns, lanes, red light, signs, swerving, overloading | none | not a model problem; see the board's "how the rules are doing" |

Adding a violation = one row in `ROUTES` in `collect.py`.

### What tickets cannot show (needs no ticket, or the clip's video)

| Where it comes from | Model | Question you are asked |
|---|---|---|
| A frame sampled from the clip (8 per analysis; **only when the analysis kept its video**) | Vehicles (`primary_anchor`) | "Box every vehicle and rider": the vehicle finder's guess is drawn, add what it missed, delete what is wrong |
| A vehicle in those frames that nobody was ticketed for (up to 12 per model) | Plate / Helmet / Cabin | the same question as for tickets; the reason says "No ticket was issued". This is how vehicles the system **missed** reach you |
| Two cars of one analysis that may be one car (the tracker gave it a new number) or two look-alikes | Car matcher (ReID) | "Same car?": Same / Different / Not sure |

The "Same car?" tile has two parts, and neither needs the video; both use the clean photos every ticket already holds.

- **Cars** (`cars.py`): a card per ticketed car of the analysis, by number. Open one: the big photo on top, every
  photo of that car in a flat strip below, the first photo (the original) pinned in the corner. **D** marks the photo
  on screen as a *different car* and moves on; **Enter** saves. Photos you did not mark are filed as one car, marked
  ones as another car (`<car>_b`) in `datasets/reid/images/<analysis>/` (a photo filed under the wrong car earlier is
  moved, never duplicated; saving again changes your mind). Only training data: the ticket is not changed.
- **Quick questions** (`pairs.py`): A *Same* answer puts both cars' photos in one folder of `datasets/reid/images/<analysis>/`
(moving the other car's photos if it already had a folder), *Different* keeps two folders, *Not sure* writes
nothing. Each answer adds a line to `datasets/reid/decisions.jsonl` (`"source": "harvest"`), the same format the
review screens write. The tickets themselves never change.

## Folders

```
training_lab/
  harvest.py            command line (status, collect, serve, accept, cut-plates, probe-input, protect)
  harvest_tool/         the code (config, collect, detect, store, accept, web + page.html, tui_view, ...)
  harvest_inbox/        YOUR pictures (git-ignored, local only)
      harvest.db        index: what each picture is, why, what you decided
      gallery.json      snapshot for the Training Studio's Harvested tile (derived; safe to delete)
      server.json       url + token of the running helper (written by `serve`)
      <model>/images/   the pictures        <model>/labels/   your boxes (YOLO .txt)
      reid_pairs/images/  the two pictures of each "same car?" question
      protected.json    benchmark clips that must never be harvested
  tests/test_harvest.py
```

## Harvest inside the Forensic Analyzer (one picture at a time)

Every analysis has a **Review | Harvest** switch. **Harvest** shows only the kinds of picture that analysis can
teach (Plate, Helmet, Cabin) as big tiles with the number still waiting. Open a tile: one picture, full screen.

| Do | How |
|---|---|
| The boxes are right | **Enter** / *Looks right* |
| Draw a box | drag on the picture (several kinds of box: pick the colour first, or keys **1-9**) |
| Fix a box | pull a corner; drag inside to move; **Delete** removes the picked one |
| Nothing here / not sure | **N** / **S** |
| Back / close | **←** / **Esc** |

Two more tiles can appear: **Vehicles** (frames of the clip, when it was kept) and **Same car?** (one answer per pair:
**Enter** = same car, **N** = different cars, **S** = not sure). Without the kept video a one-line hint says so.

The forensic screen's own **Harvest** tab shows the same tiles for all analyses together.
The dashboard starts this tool's local helper by itself (`harvest.py serve --no-open --idle-exit <min>`, token in
`harvest_inbox/server.json`), collects the pictures of that analysis the first time you open the tab (again once after
an update that adds new kinds: `COLLECT_VERSION` in `collect.py`), and the helper stops when idle. A helper from before
an update is stopped and replaced (`/api/ping` reports `api`; 3 = cars one by one). Benchmark clips are never offered. Code: `hulikamote_dashboard/lib/features/forensic/**/harvest_*.dart`.

## The snapshot behind the Training Studio

```
python training_lab/harvest.py gallery        # rebuild harvest_inbox/gallery.json
```
The Training Studio's *Harvested* tile reads `gallery.json` and the pictures next to it straight from disk.
It is rebuilt after every collect, save, skip, accept and cut-plates.

## See the pictures in the Training Studio, per model

Each model's **Train** page has a **Training pictures** box under "1. Training data": two tiles side by side, **Original**
(the dataset in `training_lab/datasets/<model>/`) and **Harvested** (what this tool collected), each with its count and a
little mosaic. Pick one to see its pictures as a grid, with the boxes drawn. Colour chips narrow it down (Original: train /
val / test and the source it came from; Harvested: to check / ready / added ...). Click a picture to enlarge it (arrows or
keys move on, Esc closes); hover or open one to see where it came from. It only reads files: checking and adding to the dataset
stay in this tool. **Harvest tab** in the box jumps to the Forensic Analyzer's Harvest tab (the category tiles).

## Rules that keep the numbers honest

- **Benchmark clips are never harvested:** `python training_lab/harvest.py protect <task_id>`.
- **All pictures of one car stay on the same side of the train / validation split.**
- **The test split is never written to**, so old and new models stay comparable.
- A picture is added once; re-collecting never duplicates.
- Everything runs on the CPU at low priority, so it does not slow a training.

## Train the car matcher (ReID) on what you harvested

1. **File the cars.** In the dashboard: analysis > Harvest > Same car?: open the cars that look wrong (**D** marks a photo that
   shows a different car, **Enter** saves), then **Rest are fine** files all the others. Or from the command line:
   `python training_lab/harvest.py reid-fill` (every car nobody opened, in every analysis; slow: about 2 s per car).
   Several analyses of the SAME clip are fine: the trainer spots a car that was filed twice (average fingerprint above 0.95 and a
   closest photo pair above 0.98 against another analysis) and uses it once. Cars of one analysis are never merged this way.
   A ticket the Forensic Analyzer merged from two tracks ("412 & 5") opens like any other.
2. **Clean.** Datasets > Car matcher (ReID) (see `dataset_viewer/README.md`): scan, then merge the cars the tracker split in two, move
   photos that landed under the wrong car, remove bad photos. Undo and Removed keep it safe.
3. **Train.** Training Studio > Car Matching (ReID), or `python training_lab/scripts/train_reid.py --epochs 12 [--deploy]`. It reads
   `datasets/reid` directly and starts from the live `ckpt.t7`. Its check: a quarter of the CARS are never trained on; the old
   and the new model each try to find those cars again, and the new one is deployed only if it is clearly better there (+2 points)
   and there are 8+ cars to tell. Then it trains once more on all the cars and that file is the one deployed (the old one is kept
   as `ckpt_original.t7`). Restart the backend to load it.
4. **Count the jumps on one clip**, old matcher against new, same boxes, the app's own tracker settings:
   `python training_lab/scripts/reid_ab.py --task <analysis id> --new training_lab/runs/reid/train_<time>/ckpt.t7`
   (the analysis must have kept its video). It reports SUSPECTED jumps (one car, new number) and merges (two cars, one number),
   counted the same way for both; look at the worst by eye in Same car? before believing a small difference. There is no ground
   truth, and a clip whose cars were trained on says nothing: use a clip the matcher has not seen, from the same camera.

Evidence that this data trains a better matcher: `training_lab/experiments/reid/RESULTS.md`.

`harvest.py reid-export <a new folder>` (add `--public` for `datasets/reid_public`) writes a resized, split copy of `datasets/reid`
(`train/<car>/` + `val/<car>/`, every picture 64x128) for the OTHER trainer, the Market-1501 one in
`hulikamote_backend/engine/deep_sort/deep/train.py`. That script crashes on pictures that are not already 64x128, and without
`--resume` it stops with a `NameError` after epoch 1 (`torch.save(checkpoint, ...)` at the end of `main()`; `checkpoint` only exists
after a resume). Prefer the Studio trainer above.

## Make plate pictures from the plate photos you already have

```
python training_lab/harvest.py cut-plates --limit 20      # quick trial
python training_lab/harvest.py cut-plates                 # all (about 10 minutes on the CPU)
python training_lab/harvest.py accept plate_specialist    # when the plate model is not training
```
Cuts each vehicle out of a plate photo and moves the human-made plate box with it, so the plate model also
learns from "one vehicle, plate anywhere on it", which is what the app hands it.

## Measure instead of guess

`python training_lab/harvest.py probe-input` compares ways of feeding a picture to the plate model on held-out
photos and on your real "no plate" tickets. Re-run it after changing how the app prepares images.

## Tests

```
hulikamote_backend/venv/Scripts/python.exe -m pytest training_lab/tests -q -p no:cacheprovider
```
They run on temporary folders: no real data, database or model is touched.
