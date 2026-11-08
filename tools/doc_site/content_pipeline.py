"""Page 3 - Training pipeline, and why it is sufficient. Numbers come from the dataset cards, the tests index and the run folders."""
from __future__ import annotations

import re

from content_models import MODELS, targets
from lib import (ROOT, Page, arrow, box, callout, card, chip, cmd, code, esc, figure, kv, ref, run_summary, span, steps, svg,
                 table, tests_info, whole)

MODEL_KEYS = [("primary_anchor", "Vehicle"), ("helmet_specialist", "Helmet"), ("plate_specialist", "Plate"), ("cabin_specialist", "Cabin")]


def leak_rows() -> list[list[str]]:
    rows = []
    for key, name in MODEL_KEYS:
        text = card(key)["text"]
        m = re.search(r"(\d+) val and (?:about )?(\d+) test pictures had a near-identical twin in train", text)
        if m:
            rows.append([f"<b>{name}</b> set", m.group(1), m.group(2)])
    return rows


def size_rows() -> list[list[str]]:
    rows = []
    for key, name in MODEL_KEYS:
        text = card(key)["text"]
        m = re.search(r"A box covers \(10th pct / median / 90th pct of the picture\): (\d+\.\d+) / (\d+\.\d+) / (\d+\.\d+)", text)
        if m:
            lo, med, hi = (float(x) for x in m.groups())
            rows.append([f"<b>{name}</b> set", f"{lo * 100:.2f}%", f"{med * 100:.2f}%", f"{hi * 100:.1f}%"])
    return rows


def _flow() -> str:
    w = 130
    xs = [i * 157.5 for i in range(5)]
    parts = [
        box(xs[0], 20, w, 70, ["1 Collect", "download + merge", "public data"], "c1"),
        box(xs[1], 20, w, 70, ["2 Clean", "fix, quarantine,", "remove twins"], "c1"),
        box(xs[2], 20, w, 70, ["3 Describe", "dataset cards", "+ catalog"], "c1"),
        box(xs[3], 20, w, 70, ["4 Train", "fine-tune YOLO", "on a laptop GPU"], "c3"),
        box(xs[4], 20, w, 70, ["5 Check", "score on the", "validation set"], "c3"),
        box(xs[3], 150, w, 70, ["6 Export + deploy", "ONNX file +", "manifest"], "c4"),
        box(xs[2], 150, w, 70, ["7 Run", "registry loads it", "into the pipeline"], "c4"),
        box(xs[1], 150, w, 70, ["8 Benchmark", "caught / missed /", "false alarms"], "c7"),
        box(xs[0], 150, w, 70, ["9 Harvest", "pick, check, add", "our own pictures"], "c2"),
    ]
    for i in range(4):
        parts.append(arrow(xs[i] + w, 55, xs[i + 1], 55))
    parts.append(arrow(xs[4] + 65, 90, xs[3] + 100, 150))
    parts.append(arrow(xs[3], 185, xs[2] + w, 185))
    parts.append(arrow(xs[2], 185, xs[1] + w, 185))
    parts.append(arrow(xs[1], 185, xs[0] + w, 185))
    parts.append(arrow(65, 150, 65, 90, "new pictures from our footage", True, 152, 124))
    return svg(760, 240, "".join(parts), "The training pipeline as a loop: collect, clean, describe, train, check, export, run, benchmark, harvest, and back to training")


def build() -> Page:
    p = Page("3-training-pipeline.html", "3", "Training pipeline",
             "How a picture collection becomes a model that runs in the system: every step, the command and the code behind it, "
             "and an honest argument for why this pipeline is enough for the thesis, and where it is not.")
    tgt = targets()
    ti = tests_info("hulikamote_backend/engine/specialists.py") or {}
    runs = ti.get("runs", {})

    # ── overview ──────────────────────────────────────────────────────────────
    p.h2("overview", "The whole pipeline in one picture", kicker="Start here", newpage=False)
    p.add("<p>Training here is a <b>loop</b>, not a one-time job. Public data gives the models a start (steps 1 to 5). The system then runs on our own footage (7), "
          "is scored on clips with known answers (8), and its mistakes become new, human-checked training pictures (9) that go back into step 4. "
          "Each step has a script, so any of them can be repeated and audited.</p>")
    p.add(figure(_flow(), "<b>Read it like a clock.</b> Top row left to right, then the bottom row right to left, then up the left side back to the start. "
                 "Blue boxes prepare data, green boxes make and check a model, yellow boxes put it in the system, purple measures the whole system, orange is our own footage coming in."))
    p.add(table(["Step", "What happens", "Script (run from <code>training_lab/</code>)", "Written to"], [
        ["1 Collect", "Download public datasets and map their class names onto ours.", "<code>scripts/fetch_datasets.py</code>", "<code>datasets/_downloads/</code> then <code>datasets/&lt;model&gt;/</code>"],
        ["2 Clean", "Check every picture and label; quarantine bad files and training pictures that duplicate validation or test pictures.", "<code>data.py curate --apply</code>", "<code>datasets/_quarantine/</code>"],
        ["3 Describe", "Write one card per dataset and one catalog.", "<code>data.py report</code>", "<code>DATASET_CARD.md</code>, <code>CATALOG.md</code>"],
        ["4 Train", "Fine-tune a pretrained YOLO on the dataset.", "<code>scripts/train.py</code> (or Training Studio, or the terminal lab)", "<code>runs/&lt;model&gt;/&lt;run&gt;/</code>"],
        ["5 Check", "Score on validation; compare with the target.", "<code>scripts/validate.py</code>", "printed + <code>results.csv</code>"],
        ["6 Export + deploy", "Convert to ONNX at the running size, copy to the backend, point the manifest at it.", "<code>scripts/export_onnx.py</code>", "<code>hulikamote_backend/models/&lt;folder&gt;/</code>, <code>model_manifest.json</code>"],
        ["7 Run", "The registry loads the file when the backend starts.", "(automatic)", "-"],
        ["8 Benchmark", "Run clips with known answers through the whole system and count caught, missed and false alarms.", "<code>python -m tools.benchmark run</code>", "<code>benchmarks/reports/</code>"],
        ["9 Harvest", "Collect uncertain pictures, a person checks them, accepted ones join the dataset.", "<code>harvest.py</code>", "<code>harvest_inbox/</code>, then datasets"],
    ], "dense", ["11%", "37%", "30%", "22%"]))
    p.end()

    # ── 1 collect ─────────────────────────────────────────────────────────────
    p.h2("t-collect", "Step 1. Collect: public data, mapped to our classes", kicker="Stage 1")
    p.add("<p>Every source is one entry in a single list, the [[manifest]]. An entry says where to get the data, how <i>its</i> class names map to <i>ours</i> (a class that is not listed is dropped), "
          "its licence and country, and how much to trust it ([[trust grade]]). The script downloads it once, converts it to YOLO format, and merges it with a file-name prefix "
          "(<code>&lt;id&gt;__</code>), so running it again overwrites instead of duplicating.</p>")
    p.add(code("training_lab/configs/datasets_manifest.yaml", lines=span("training_lab/configs/datasets_manifest.yaml", "- id: edgevision_helmet", end_text="classes: {NoHelmet"), lang="yaml",
               title="One manifest entry (the Indian helmet photos)", walk=[
        ("source: mendeley", "Where it is hosted. Mendeley Data needs no account; Roboflow sets need your own free key."),
        ("license: CC BY 4.0", "The licence. CC BY means credit the author (page 1, Licences)."),
        ("trust: A", "Our own grade: A = official or peer-reviewed host."),
        ("citation:", "The citation to put in the thesis."),
        ("classes: {NoHelmet", "Their class names (left) become ours (right). 'BikeWithRider' is not listed, so it is dropped."),
    ]))
    p.add(code("training_lab/scripts/fetch_datasets.py", symbol="download", title="How one source is downloaded", walk=[
        ("(out / \"data.yaml\").exists()", "Already downloaded? Then use the saved copy (downloads are cached; delete the folder to fetch again)."),
        ("sources.fetch(src)", "Mendeley, Zenodo, Hugging Face, Open Images and plain URLs need no account."),
        ("_api_key()", "Roboflow needs your own free key (read from the environment, or asked for once, hidden). Without it the source is skipped, not fatal. The key is never saved."),
        ("DOWNLOAD_TRIES", "A cut-off download is retried (3 times), and the broken partial folder is cleared between tries."),
    ]))
    p.add(cmd("python scripts/fetch_datasets.py                       # every model in the manifest\npython scripts/fetch_datasets.py --model helmet_specialist\n"
              "python scripts/fetch_datasets.py --only edgevision_helmet --stage-only   # download one source, merge nothing\npython scripts/fetch_datasets.py --dry-run             # only show the class mapping"))
    p.end()

    # ── 2-3 clean / describe ──────────────────────────────────────────────────
    p.h2("t-clean", "Steps 2 and 3. Clean the data and write it down", kicker="Stages 2 and 3")
    p.add("<p>Raw public data is messy: broken files, boxes outside the picture, the same photo in training and in validation. Cleaning fixes what it can, <b>moves</b> (never deletes) what it cannot, "
          "and then writes a dataset card so nobody has to guess what is in a folder. This is the step that found the [[data leakage]] shown below.</p>")
    p.add(code("training_lab/data_tools/curate.py", symbol="@doc", title="What the cleaner checks, per picture (its own description)"))
    p.add(table(["Dataset", "Validation pictures with a twin in training", "Test pictures with a twin in training"], leak_rows(), "dense"))
    p.add("<p class='note'>These are the numbers the cleaner found <b>before</b> its first run, read from each dataset card. A twin means a [[near-duplicate]] found by a [[perceptual hash]]. "
          "A validation or test picture that is also in training makes a model look better than it is, so the training copy was moved to <code>datasets/_quarantine/</code>.</p>")
    p.add(cmd("python data.py curate --apply     # check + clean + standard layout (a dry run without --apply)\npython data.py report            # DATASET_CARD.md for each dataset + CATALOG.md\npython data.py sheet --staged ID # a picture grid with the boxes drawn, to look at a source by eye"))
    p.add(callout("ok", "Why the by-eye step matters",
                  "<p>Project names lied: <code>ph_plates</code> is Vietnamese and <code>colorum_plates</code> is Indian, UK and US. Every Roboflow source was checked on a picture sheet before it was labelled "
                  "Philippine or not. The command's own help says not to curate a model while it is training (the Training Studio and the terminal lab show which runs are active).</p>"))
    p.end()

    # ── 4 train ───────────────────────────────────────────────────────────────
    p.h2("t-train", "Step 4. Train: fine-tune a pretrained model", kicker="Stage 4")
    p.add("<p>[[Training]] starts from <code>yolov8n.pt</code>, the small pretrained [[YOLOv8n]], and continues learning on our dataset ([[fine-tuning]]). "
          "Every setting lives in one config file, so every run uses the same recipe unless a person overrides it on purpose. The learned settings of a finished run are saved next to it, in "
          "<code>args.yaml</code> (the settings) and <code>results.csv</code> (one line per [[epoch]]), which is where page 2's tables come from.</p>")
    p.add(code("training_lab/configs/training_config.yaml", lines=whole("training_lab/configs/training_config.yaml"), lang="yaml", title="The master recipe", walk=[
        ("base_model: yolov8n.pt", "The starting model. 'n' is the nano size: small and fast. A larger one (s) is the planned upgrade if a score is too low."),
        ("patience: 30", "Stop by itself if the score has not improved for 30 epochs ([[early stopping]])."),
        ("hsv_v: 0.4", "[[Augmentation]]: random brightness changes, to imitate night and shade. The other lines imitate camera tilt, zoom and flipping."),
        ("mosaic: 1.0", "[[Mosaic]]: stick four pictures into one so the model sees objects in new surroundings."),
        ("imgsz: 320", "Specialists are trained for small crops. (The Training Studio's own default is 640; see the note on page 2.)"),
    ]))
    p.add(code("training_lab/scripts/train.py", symbol="train", title="The training script", walk=[
        ("resolved_epochs = epochs or", "Order of priority: what the person typed, then the per-model note in the config, then the master default."),
        ("data[\"path\"] = str(", "Ultralytics resolves a relative dataset path against its own folder, so the script hands it an absolute path."),
        ("model = YOLO(cfg[\"base_model\"])", "Load the pretrained starting model."),
        ("model.train(", "Train. Everything after this line is the recipe: epochs, size, batch, device, patience, augmentations."),
        ("fraction=fraction", "Optional: use only a share of the pictures for a quick check."),
    ]))
    p.add(table(["Way to start", "Where it runs", "Survives a backend restart?", "Use it for"], [
        ["Terminal Training Lab (<code>lab_tui.py</code>)", "Its own background process", chip("ok", "Yes"), "Real trainings. Shows scores, the live epoch, past runs and the dataset in plain language."],
        ["Command line (<code>scripts/train.py</code>)", "Your terminal", chip("ok", "Yes"), "Repeatable runs and quick checks."],
        ["Training Studio button in the dashboard", "<i>Inside</i> the backend", chip("bad", "No"), "Short tests. The backend reloads when its files change, which kills a run started this way."],
        ["Studio <i>Continue</i>", "Own detached process", chip("ok", "Yes"), "Resuming an interrupted run."],
    ], "dense"))
    p.add(code("training_lab/scripts/run_state.py", symbol="resumable", title="Pause and continue", walk=[
        ("last.pt", "Ultralytics saves the last finished epoch to last.pt, which is what lets a stopped run continue."),
        ("run_finished(run)", "A run that already finished (including one that stopped early by itself) cannot be resumed: start a new one."),
    ]))
    p.add(code("training_lab/scripts/run_state.py", symbol="launch_detached", walk=[
        ("DETACHED_PROCESS", "On Windows, start the training as its own process with no console, so closing a window or restarting the backend does not stop it."),
    ]))
    p.add(callout("warn", "A rule learned the hard way",
                  "<p>Do not edit files under <code>hulikamote_backend/</code>, and do not install packages into its environment, while a Studio-started training runs: the backend restarts and the training dies. "
                  "This cost one helmet run (<code>helmet_specialist/train</code>, 19 epochs).</p>"))
    p.add(kv([("Hardware", "A laptop with an NVIDIA RTX 3050 (6 GB). Under load its clock is power-capped, so trainings are slow: a car-matcher epoch of about 800 photos took about 30 seconds."),
              ("Why small models", "[[YOLOv8n]] exports to about 12 MB and runs on this laptop; the pipeline is built to stay light (page 2).")]))
    p.end()

    # ── 5-6 check/export ──────────────────────────────────────────────────────
    p.h2("t-export", "Steps 5 and 6. Check the score, export, deploy", kicker="Stages 5 and 6")
    p.add("<p>A model is <b>checked before it is trusted</b>. Each model has a target [[mAP@50]] written in the validation script; the script prints PASS or FAIL. "
          "Ultralytics keeps the best epoch by [[fitness]] (10% mAP@50 plus 90% mAP@50-95), which prefers tight boxes over lucky ones. Then the model is converted to [[ONNX]] and copied where the backend looks.</p>")
    p.add(table(["Model", "Target mAP@50"], [[f"<b>{n}</b>", f"{tgt.get(k, 0):.2f}"] for k, n in MODEL_KEYS], "dense"))
    p.add(code("training_lab/scripts/validate.py", symbol="validate", walk=[
        ("best_pt = weights_dir", "Always the best saved weights of the chosen run."),
        ("model.val(data=", "Run the model over the validation pictures and compute the scores."),
        ("map50 >= target", "Compare with the target and print PASS or FAIL."),
    ]))
    p.add(code("training_lab/scripts/export_onnx.py", symbol="export", skip=[("print(\"To publish this release", "Restart the FastAPI backend")], walk=[
        ("imgsz = 640 if model_name == \"primary_anchor\" else 320", "The vehicle detector is exported at 640; the specialists at 320, the size of the crops they are really fed."),
        ("model.export(format=\"onnx\"", "Convert from the training format to ONNX (simplified, fixed size)."),
        ("unique_name = f\"{model_name}_{run}_{date_str}.onnx\"", "A dated, unique name such as helmet_specialist_train-2_20261005.onnx, so older files are never overwritten."),
        ("category_map", "Each model goes to its own folder: Vehicle Detectors, Helmet Detectors, Plate Models, Cabin Models."),
        ("manifest[\"active_models\"][model_name]", "Point the manifest at the new file. The next backend start (or the Models tab) uses it."),
    ]))
    p.add(code("hulikamote_backend/routers/training.py", symbol="_run_training_pipeline_inner", title="What the dashboard's Train button does, in order",
               skip=[("if task_type == \"ocr\":", "Enhancer training + ONNX export complete")], walk=[
        ("split_dataset.py", "1. Split (a no-op for datasets that are already split, which all of ours now are)."),
        ("train.py", "2. Train."),
        ("export_onnx.py", "3. Export and deploy straight away. The Studio route deploys without a person comparing scores, so check the scores afterwards (the car matcher is the exception: it has its own gate)."),
    ]))
    p.add(cmd("python scripts/train.py --model helmet_specialist --epochs 100 --imgsz 320 --batch 16\npython scripts/validate.py --model helmet_specialist --run train-2\npython scripts/export_onnx.py --model helmet_specialist --run train-2   # add --no-deploy to only convert"))
    p.end()

    # ── 7 harvest ─────────────────────────────────────────────────────────────
    p.h2("t-harvest", "Step 9. The harvest loop: our own footage, human-checked", kicker="Stage 9 &middot; closes the gap to Zamboanga")
    p.add("<p>Public data cannot teach what <i>our cameras</i> see. The [[harvest]] tool copies pictures from finished analyses, shows the model's guess, and asks a person to confirm or fix it, "
          "one picture at a time. Only a checked picture is ever added, and only while that model is <b>not</b> training. The rules are in code, not just in a README.</p>")
    p.add(code("training_lab/harvest_tool/accept.py", symbol="accept", walk=[
        ("is_training(model)", "Refuse to touch a dataset while its model is being trained; the pictures wait safely in the inbox."),
        ("pick_split(item.group_id", "Choose train or validation from the picture's CAR group, so all pictures of one car land on the same side."),
        ("harvest__", "Accepted files get a <code>harvest__</code> name, which the cleaner never moves or changes."),
        ("yolo_text(item.boxes)", "Write the checked boxes in YOLO format. An empty list is a valid label: 'nothing here' becomes a negative example."),
    ]))
    p.add(code("training_lab/harvest_tool/accept.py", symbol="pick_split", walk=[
        ("hashlib.sha1(group_id", "A fixed fingerprint of the group id gives the same split every time: repeatable, and never random per picture."),
    ]))
    p.add(table(["Rule", "Why"], [
        ["A person checks every picture", "Wrong labels teach wrong things; the system's own guesses are never trusted unchecked."],
        ["Benchmark clips are protected (<code>harvest.py protect &lt;id&gt;</code>)", "A clip used to teach the model cannot also be used to score it."],
        ["The test split is never written", "Old and new models stay comparable."],
        ["Never writes inside <code>hulikamote_backend/</code>; never uploads", "Safe while the backend runs; nothing leaves the machine."],
    ], "dense", ["38%", "62%"]))
    p.end()

    # ── 8 reid + ocr + enhancer ───────────────────────────────────────────────
    p.h2("t-others", "Other things that are trained, and what is not", kicker="Helper models")
    p.add(table(["Model", "Trainable here?", "How", "Gate before deploying"], [
        ["Car matcher ([[ReID]])", chip("ok", "Yes"), "<code>scripts/train_reid.py</code>, also from Training Studio &rarr; Car Matching. Starts from the live <code>ckpt.t7</code>.",
         "Automatic: tested on cars it never saw."],
        ["Plate reader ([[OCR]])", chip("bad", "Not as installed"), "<code>scripts/train_ocr.py</code> exists, but the EasyOCR package has no trainer and the PaddleOCR tools are missing.", "-"],
        ["Picture enhancer ([[Real-ESRGAN]])", chip("warn", "Experimental"), "<code>scripts/train_realesrgan.py</code> (a lightweight RRDB GAN on sharp plate crops). Never shown to beat the ready-made model.", "None; optional at run time."],
        ["Trackers, flow learner, light readers", chip("off", "Nothing to train"), "Algorithms and rules.", "-"],
    ], "dense"))
    p.add(code("training_lab/scripts/train_reid.py", symbol="split_cars", walk=[
        ("random.Random(seed).shuffle", "Shuffle whole CARS (not photos) with a fixed seed."),
        ("order[n_test:], order[:n_test]", "About a quarter of the cars are set aside and never trained on."),
    ]))
    p.add(code("training_lab/scripts/train_reid.py", symbol="decide", walk=[
        ("cars < MIN_TO_VERIFY", "Fewer than 8 cars: not enough to test on unseen cars, so it is never deployed."),
        ("after < before + MIN_GAIN", "The new matcher must find the right car at least 2 points more often than the old one."),
        ("after_map < before_map", "And it must not order the other cars worse."),
    ]))
    p.add(ref("training_lab/experiments/reid/RESULTS.md", line=1, label="RESULTS.md (evidence for the car matcher)"))
    p.end()

    # ── 9 benchmark ───────────────────────────────────────────────────────────
    p.h2("t-benchmark", "Step 8. Benchmark: scoring the whole system, not just a model", kicker="Stage 8")
    p.add("<p>A good detector does not guarantee a good system. mAP says how well boxes are found; the thesis also needs to know whether the <b>right violation</b> was logged for the <b>right vehicle</b> with the <b>right plate</b>. "
          "The benchmark runs clips whose real events a person wrote down through the same code the dashboard uses, and counts:</p>")
    p.add(table(["Word", "Meaning", "Metric"], [
        ["[[caught]]", "A ticket of the same violation whose evidence time is within 3 s of a real event. Each ticket and event is used once.", "recall = caught / (caught + missed)"],
        ["[[false alarm]]", "A ticket with no real event.", "precision = caught / (caught + false alarms); false alarms per minute"],
        ["[[missed]]", "A real event with no ticket.", "recall"],
        ["[[LOAR]]", "Of the caught events, how many were logged with the right violation, vehicle and exact plate.", "the thesis' system metric"],
        ["[[CER]] / [[WER]]", "How wrongly plates were read: character errors, and the share of plates not exactly right.", "plate reading"],
    ], "dense", ["16%", "56%", "28%"]))
    p.add(code("tools/benchmark/scoring.py", symbol="match", walk=[
        ("p.violation != e.violation", "A ticket can only match an event of the same violation."),
        ("g = gap(e, p)", "How many seconds apart are the real event and the ticket's evidence? 0 means they overlap."),
        ("if g <= t:", "Close enough (default tolerance 3 s): they could be a pair."),
        ("cands.sort()", "Pair the closest first."),
        ("if i not in used_e and j not in used_p", "Each event and each ticket is used once, so one ticket cannot excuse two misses."),
    ]))
    p.add(callout("warn", "Where the benchmark stands",
                  "<p>The tool, the clip checklist and the dashboard tab are built and tested. <b>The clip registry is still empty</b> "
                  f"({esc(str(runs.get('backend', {}).get('passed', '?')))} backend tests pass, but there are no real-footage scores yet). "
                  "A violation is only given a pass or fail once it has at least 10 real events; the others are reported as 'implemented, not scored'. "
                  "Filling the registry from your own footage is the most valuable remaining task.</p>"))
    p.end()

    # ── sufficiency ───────────────────────────────────────────────────────────
    p.h2("t-defense", "Why this pipeline is sufficient (and where it is not)", kicker="The defense")
    p.add(callout("ok", "The honest one-sentence answer",
                  "<p>This pipeline is <b>sufficient to demonstrate what the thesis sets out to show</b>: that automated, contactless traffic-violation detection is technically feasible with local, "
                  "open tools. It is <b>not yet sufficient to claim field accuracy on Zamboanga roads</b>, because no model has been scored on real local footage; the loop that closes that gap is built, and the first local clip is in it.</p>"))

    p.h3("t-claims", "Seven reasons it is enough for the claim being made")
    p.add(table(["#", "Claim", "What we did", "Evidence you can open", "Status"], [
        ["1", "<b>The method is the standard one for small teams.</b>",
         "Fine-tune a pretrained nano [[YOLO]] on task data ([[transfer learning]]), instead of training from nothing. It needs far less data and time, and exports to a 12 MB file.",
         ref("training_lab/scripts/train.py", symbol="train", label="train.py") + ref("training_lab/configs/training_config.yaml", line=9, label="base_model"), chip("ok", "Done")],
        ["2", "<b>Models are small and specialised because the objects are small.</b>",
         "One detector finds vehicles; specialists look only at crops. A plate fills about 0.3% of a frame, so a whole-frame model would lose it (table below).",
         ref("hulikamote_backend/engine/specialist_jobs.py", symbol="@doc", label="specialist_jobs.py"), chip("ok", "Done")],
        ["3", "<b>The scores are not inflated.</b>",
         "Training and validation/test pictures are separated; near-twins found and removed; the test part is never written; the best epoch is chosen by a strict score.",
         ref("training_lab/data_tools/curate.py", symbol="@doc", label="curate.py") + ref("training_lab/datasets/CATALOG.md", line=1, label="CATALOG.md"), chip("ok", "Done")],
        ["4", "<b>Targets were fixed before the results.</b>",
         "Each model has a target written in the code, and results below the target are reported as below target (plate, cabin, vehicles).",
         ref("training_lab/scripts/validate.py", symbol="validate", label="validate.py"), chip("ok", "Done")],
        ["5", "<b>Model score and system score are measured separately.</b>",
         "mAP for the detectors; caught / missed / false alarms / LOAR / plate error for the whole system on clips with known answers.",
         ref("tools/benchmark/scoring.py", symbol="match", label="scoring.py") + ref("benchmarks/README.md", line=1, label="benchmarks/README.md"), chip("warn", "Built, registry empty")],
        ["6", "<b>The local gap is closed by design, with a person in the loop.</b>",
         "Harvest collects uncertain pictures from our own analyses; a person checks them; they join training only when the model is idle. The car matcher gained 8.6 points on new cars from the same cameras.",
         ref("training_lab/harvest_tool/accept.py", symbol="accept", label="accept.py") + ref("training_lab/experiments/reid/RESULTS.md", line=1, label="RESULTS.md"), chip("warn", "Built, little local data yet")],
        ["7", "<b>It is reproducible and tested.</b>",
         f"Every dataset has a card; every run keeps its settings and scores; every step is a script. Automated tests: {runs.get('backend', {}).get('passed', '?')} backend, {runs.get('training_lab', {}).get('passed', '?')} training-lab, {runs.get('flutter', {}).get('passed', '?')} dashboard.",
         ref("docs/project_map/tests_index.json", line=1, label="tests_index.json"), chip("ok", "Done")],
    ], "dense", ["3%", "20%", "34%", "28%", "15%"]))

    p.h3("t-size", "How small are the things the models must find?")
    p.add("<p>This is the argument for the cascade. Each number is the share of the whole picture that a typical labelled box covers.</p>")
    p.add(table(["Dataset", "Smallest 10%", "Typical (median)", "Biggest 10%"], size_rows(), "dense"))
    p.add("<p class='note'>The plate model's typical target covers about a third of one percent of the picture. A single detector looking at a whole frame would see a few pixels. That is why the plate is searched <i>inside</i> a vehicle crop.</p>")

    p.h3("t-leaks", "What the cleaning found (proof the numbers are taken seriously)")
    p.add(table(["Dataset", "Validation pictures that had a twin in training", "Test pictures that had a twin in training"], leak_rows(), "dense"))
    p.add("<p class='note'>The cabin set was the worst: most of its validation and test pictures were near-copies of training pictures. Scores measured before cleaning were therefore too good, "
          "and the helmet and cabin models were trained before the cleaning. Re-scoring them on the cleaned sets is listed below.</p>")

    p.h3("t-gaps", "What this pipeline does not prove yet, and what closes each gap")
    p.add(table(["Gap", "Why it matters", "What closes it"], [
        ["No Zamboanga data in any training set", "Roads, cameras, plates and riders here look different; scores may not carry over.", "Harvest from the local clips, retrain, compare on protected clips."],
        ["Plate model below target (mAP@50 well under 0.90)", "Plates are the weakest link: they are on every ticket.", "Retrain on the cleaned set plus harvested plates; report the read rate by vehicle size."],
        ["Cabin model just under target; no tint or mirror in validation or test", "The tint gate and Missing Side Mirror cannot be trusted or scored.", "Add mirror and tint pictures from our footage; retrain."],
        ["Vehicle model: stock COCO, 6-class run unfinished", "No tricycle or jeepney class.", "Finish the run, test on the local clip, then switch."],
        ["Helmet and cabin scores predate dataset cleaning", "They are probably optimistic.", "Re-run <code>validate.py</code> on the cleaned sets."],
        ["Trained at image size 640, run at 320", "A small mismatch between how it was scored and how it runs.", "Train and score at 320 for the specialists."],
        ["The benchmark has no real clips yet", "There is no system-level accuracy number.", "Add 3 clips (one rainy, two dry-day, fixed camera), write the true events, run."],
        ["The plate reader cannot be fine-tuned here", "Read errors cannot be trained away.", "Use format rules and voting (done), or switch to a trainable reader."],
        ["Training is slow on a power-capped laptop GPU", "Fewer experiments per day.", "Windows high-performance mode; shorter test runs with <code>--fraction</code>."],
    ], "dense", ["30%", "34%", "36%"]))

    p.h3("t-qa", "Questions the panel may ask, with short answers")
    qa = [
        ("Why YOLOv8n and not a bigger model?", "It is small, fast and exports to a 12 MB file that runs on a laptop; the project aims to stay light enough for a barangay trial. The config says to move up to the 's' size if a score stays too low."),
        ("Why not one model for everything?", "The objects differ hugely in size. A plate is a fraction of a percent of the frame. Cropping first lets each small model see its object large."),
        ("How do you know the scores are not inflated?", "The cleaner found near-copies shared between training and validation or test, and removed the training copies. The test part is never written, and the best epoch is chosen by a strict score."),
        ("Your plate score is below target. Is the system usable?", "Say so plainly: it is below target on the public validation set. The plate step is voted over up to 40 crops and read with format rules, and the plan to retrain on harvested local plates is built. Real read rates must be benchmarked."),
        ("Where is the accuracy on real roads?", "Not measured yet, and we say so. The benchmark and clip checklist are built; the registry needs real clips. Claims are limited to violations with at least 10 real events."),
        ("Is the data legal to use?", "Every source is listed with its licence and country (page 1). Most are CC BY 4.0 with credit; one is research-use only; unclear sources were excluded."),
    ]
    p.add("".join(f"<details class='qa' open><summary><b>{q}</b></summary><p>{a}</p></details>" for q, a in qa))
    p.end()
    return p
