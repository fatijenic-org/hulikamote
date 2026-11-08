# Does harvested car data train a better car matcher (ReID)? Evidence of 2026-10-27

**Question.** The tracker's ReID network (`ckpt.t7`, the stock people-trained one) gives every car a fingerprint. If it is
fine-tuned on car photos from our own tickets (what the Harvest tab files into `datasets/reid`), does it find a car again
more often among other cars?

**Data.** 67 ticketed cars from two real clips (24 + 43), each car = its saved photos (tight crops), stretched to 64x128 RGB the
way the tracker feeds the network. One analysis per clip, so the same physical car is never counted twice.

**Test.** Only on cars the model never trained on. For each test car its photos in time order: the first half are queries,
the second halves of all test cars are the gallery. rank-1 = the nearest gallery photo is the same car; mAP and AUC
(same-car vs different-car similarity) say how well the whole ranking is ordered. Guessing gives rank-1 of 2-5 %.

## Results

**Same cameras, new cars** (`reid_same_camera.py`: both clips pooled, 46 cars train, 21 unseen cars test, 3 random splits)

| | rank-1 | mAP | AUC |
|---|---|---|---|
| stock `ckpt.t7` (what the app uses now) | 76.7 ± 6.3 % | 69.5 ± 5.2 % | 91.3 ± 2.1 % |
| fine-tuned on harvested cars, careful (backbone lr 0.01, 10 epochs) | **85.3 ± 4.2 %** | **74.8 ± 5.5 %** | 91.9 ± 1.8 % |
| fine-tuned with `train.py`'s own defaults (lr 0.1, 12 epochs) | **84.0 ± 4.1 %** | **74.5 ± 4.5 %** | 92.6 ± 1.6 % |

rank-1 per split, stock -> careful: 73.4 -> 85.5, 71.2 -> 80.0, 85.6 -> 90.4: better in all three.

**A different road** (`reid_cross_clip.py`: train on one clip, test on the other)

| | stock | fine-tuned (2 runs) |
|---|---|---|
| train on clip B (43 cars), test on clip A (24 cars): rank-1 / mAP / AUC | 62.4 / 56.7 / 82.2 | 65.3 / 57.1 / 82.9 and 62.4 / 56.7 / 82.2 |
| train on clip A (24 cars), test on clip B (43 cars): rank-1 / mAP / AUC | 72.2 / 59.5 / 89.3 | 74.7 / 58.4 / 87.8 and 73.8 / 58.9 / 88.1 |

No gain that is bigger than the noise. Wrongly splitting 30 % of the training cars in two (what tracker jumps do) changed nothing
measurable at this size either (rank-1 65.7 and 75.2), so these numbers do **not** show that fixing labels helps.

**Is it trainable with the repo's own trainer?** `hulikamote_backend/engine/deep_sort/deep/train.py` on the real harvested cars
(`harvest.py reid-export`: 19 cars, 424 training + 98 checking pictures), 40 epochs: accuracy on training pictures 18 -> 89 %,
on held-out pictures of the same cars 14 -> 90 % (chance about 5 %). It needed two things first:

1. The pictures must be 64x128 already (its random crop has no resize step) and laid out as `train/<car>/` + `val/<car>/` with the
   same cars in both: that is what `harvest.py reid-export` writes.
2. A one-line bug: `main()` ends each epoch with `torch.save(checkpoint, ...)`, but `checkpoint` only exists after `--resume`
   loaded a file, so without it the script stops with a `NameError` after epoch 1 (the default `--resume` path also has a stray
   quote). The run above used a scratch copy with that line removed. The repo file was not changed: it lives under
   `hulikamote_backend`, where an edit restarts a running backend.

## What this shows, and what it does not

- Shows: harvested ticket photos are a valid, trainable ReID dataset, and on the cameras they came from, fine-tuning on them
  finds new cars again about 8 points more often (rank-1) in each of 3 splits.
- Does not show: that tracking improves (that needs the benchmark's ID switches before / after on the same clip), that it
  carries over to a different road (it did not here), or that your Same car / Different car corrections help (not testable yet).
- Small: 67 cars, 2 clips, 21 unseen test cars per split. More analyses of different clips, and public pre-training
  (`datasets/reid_public`, VeRi-776), would make it much firmer. Re-run these scripts when there is more data.

Run them with the backend venv from the repo root; they only read the repo. `REID_CLIP_A` / `REID_CLIP_B` pick the two
analyses (first 8 characters of their ids). The `.txt` files next to this one are the output of the runs above.

## Addendum: the Studio's own trainer, and how it decided

`training_lab/scripts/train_reid.py` (Training Studio > Car Matching) already fine-tunes the matcher on `datasets/reid`, so no new
trainer is needed. Run as it was (Adam 1e-4 / 1e-3, colour jitter, random erasing, 12 epochs) on 46 cars, it lifted the same
unseen-car test (21 cars, split 1 of `reid_same_camera.py`) from rank-1 **73.4 % to 83.9 %** (mAP 68.3 -> 75.5, AUC 92.8 -> 93.5).

But its own pass / fail check judged held-out PHOTOS OF THE CARS IT TRAINED ON. There the old model already scored **98.6 %**, so nothing
could beat it, and the Studio would have answered "Not deployed: not better" for a model that is clearly better on new cars.

The check now holds out 25 % of the CARS (never trained on), asks old and new "find this car again" on them, and deploys only if rank-1
is up by 2 points, mAP is not lower and there are 8+ cars; then it trains on all the cars and that file is deployed. The same 46 cars, run
through it end to end: **80.6 % -> 85.0 %** on the 12 cars it kept out (passed, trained on all 46, ckpt written, not deployed because
`--deploy` was not given). 12 test cars is a small test: treat a pass as "not worse, probably better", like the 3-split table above.

## Addendum 2026-10-29: input shape and size (same 67 cars, same 3 splits, `reid_same_camera.py`)

Switches in `reid_cross_clip.py`: `REID_INPUT=pad` (default `stretch`) and `REID_SIZE=WxH` (default `64x128`). Bigger sizes swap the stock 8x4 pooling window
(a global average at 64x128) for an adaptive global average, so all stock weights still load. Saved car photos are large (median 346x261 px; 98 % >= 64x128, 80 % >= 96x192, 52 % >= 128x256).

| rank-1 (mean of 3 splits) | stock | fine-tuned careful | fine-tuned train.py defaults |
|---|---|---|---|
| 64x128 stretch (what the tracker does) | 76.7 % | 85.6 % | 83.7 % |
| 64x128 **pad** (shape kept, gray bars) | 73.0 % | 76.5 % | 80.5 % |
| **96x192** stretch | 81.0 % | **89.6 %** | 86.4 % |

- **Padding is worse** than stretching in every column (mAP and AUC too): a padded car fills about half of the small frame.
- **96x192 is better** than 64x128 in every column and in all 3 splits (careful: +7.2, +1.6, +3.2 points; mAP 76.1 vs 74.7). It also lifts the untrained stock network (+4.3), so the gain is
  mostly the extra detail, not the fine-tuning. Cost: about 2.25x the pixels per car.
- Same limits as above: 67 cars, 2 clips, 21 test cars per split. This tests photo matching, not tracking: the tracker is unchanged.
- 128x256: not run (the first attempt died after 30 s, then it was dropped). 96x192 is what the tracker uses now.

## Addendum 2026-11-03: five clips, can fine-tuning beat the stock matcher on a NEW road?

**Data.** The 23 saved analyses are repeats of a few clips: comparing each car's mean fingerprint, cars of repeated analyses match an A/B car at
0.97-0.998, cars of different clips at 0.9 or less (A vs B: 0.87 median). Distinct clips with ticketed cars: A (24 cars), B (43), and three more:
C `ac483b8b` (16), D `e10b2564` (14), E `bd0d2944` (11). Total 108 cars, 1,262 photos (12 per car at most), all at 96x192.

**New clip** (`reid_recipes.py`, `reid_wise.py`: train on four clips, find the cars of the fifth again, mean of the 5 held-out clips)

| | rank-1 | mAP | AUC |
|---|---|---|---|
| stock `ckpt.t7` | 74.6 | 68.8 | 88.0 |
| fine-tuned, old recipe (classification over cars) | 74.0 | 66.8 | 86.6 |
| + triplet loss | 75.2 | 67.1 | 86.6 |
| + stronger augmentation | 74.2 | 66.7 | 87.3 |
| SimVeRi (synthetic) first, then fine-tune | 74.5 / 74.4 | 67.0 / 66.7 | 86.5 / 86.8 |
| blend of stock and fine-tuned weights (a = 0.25 / 0.5 / 0.75) | 73.5 / 74.1 / 75.3 | 68.0 / 67.7 / 67.6 | 87.7 / 87.3 / 87.0 |
| stock + mirror-image averaging | 74.8 | 68.5 | 87.9 |

**Nothing beats the stock matcher on a road it never saw.** Rank-1 moves within noise (clips of 11-43 cars), mAP and AUC are lower for every fine-tuned model. The
earlier gain (+8 points) is a same-cameras gain: the fine-tuned model has seen that road.

**Same cameras, new cars** (3 random splits of the 108 cars, 75 train / 33 test): stock 82.0 / 74.3 / 94.6, fine-tuned (CE + triplet) 85.1 / 75.7 / 92.4, blend a = 0.75
84.7 / 75.9 / 93.0. A smaller gain than before (+3 rank-1, AUC down 2) because the 96x192 stock is already better than the 64x128 one was.

**Colour fingerprint added to the stock matcher** (`reid_colour.py`, no training): at 64x128 rank-1 70.6 -> 75.1 (w = 0.7); at 96x192 74.6 -> 76.1. The bigger input already
captures most of what colour adds. Not deployed: it would also change the distance scale the locked tracker settings (`max_dist`) were set for.

**The change that is a real, tested gain is the input size.** Same stock weights, same 5 clips, each clip alone (how DeepSORT meets cars): 64x128 -> 96x192 lifts
rank-1 70.6 -> 74.6, mAP 66.5 -> 68.8, AUC 87.6 -> 88.0, and rank-1 is up on all five clips (57 -> 64, 72 -> 75, 78 -> 84, 89 -> 90, 57 -> 60). No training is involved, so there
is nothing to leak. It is live in `feature_extractor.py`. In real tracking (`reid_ab.py`, 64x128 vs 96x192, four more clips) the tracks and the suspected ID errors
are identical (36 vs 36 tracks, 3 vs 3 suspects; 8/8, 2/2; 12/12, 0/0; 25/25, 3/3): better photo matching, no visible change in tracking yet.

**The harvester, finalized (2026-11-03).** `datasets/reid` held 21 cars; `harvest.py reid-fill` filed the rest: 443 car folders, 15,227 photos, from 23 analyses. Two defects found and fixed first:
the same physical car filed by several analyses of one clip (24 of 24 cross-analysis near-duplicates in the old data) is now used once by `train_reid.py` (`drop_repeats`: 275 of 443 folders were repeats, 168 different cars left),
and an analysis with merged tickets ("412 & 5") no longer fails to open in the Cars tile. The Studio trainer on that data: 126 cars train, 42 cars it never saw test, rank-1 **84.2 % -> 88.7 %**, check passed
(`runs/reid/train_20261103_candidate`). Same-camera gain only: in real tracking (`reid_ab.py`) on two clips (one never trained on) the tracks and suspected ID errors are identical (36/36, 3/3 and 8/8, 2/2), and the
five-clip test above found no gain on a new road. It is therefore NOT deployed; to use it anyway: copy that `ckpt.t7` over the live one (keep `ckpt_original.t7`) and restart the backend.

**Decision.** `ckpt.t7` stays the stock file: with 108 cars from 5 roads a fine-tuned model is not clearly better anywhere but on the roads it trained on, so it fails
the Studio's own "better on cars it never saw" idea when the new cars come from a new road. Fine-tune per camera (Training Studio > Car Matching, which holds out whole cars of
the same cameras): that is the case that showed a gain. More distinct roads, or a public real vehicle set (VeRi-776 needs the authors' form), is what would change this answer.
