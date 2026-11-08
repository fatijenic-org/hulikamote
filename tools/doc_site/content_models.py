"""Page 2 - Models. Run settings and scores come from training_lab/runs/*/args.yaml and results.csv."""
from __future__ import annotations

import ast
import json
from pathlib import Path

from lib import (ROOT, Page, box, arrow, callout, chip, cmd, code, esc, figure, hbar, kv, linechart, ref, run_summary, svg,
                 table, tests_info)

MODELS = ROOT / "hulikamote_backend" / "models"
RUNS = ROOT / "training_lab" / "runs"


def mb(path) -> str:
    try:
        return f"{path.stat().st_size / 1e6:.1f} MB"
    except OSError:
        return "-"


def find(name: str):
    return next(MODELS.rglob(name), MODELS / name)


def targets() -> dict:
    """TARGET_MAP from training_lab/scripts/validate.py (read as text, no import)."""
    tree = ast.parse((ROOT / "training_lab" / "scripts" / "validate.py").read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "TARGET_MAP":
            return ast.literal_eval(node.value)
    return {}


def recipe_rows(runs: dict) -> list[list[str]]:
    """The settings of each run, side by side."""
    def a(r, k, fmt=str):
        v = r["args"].get(k)
        return fmt(v) if v is not None else "-"
    names = list(runs)
    rows = [
        ["Started from", *[("yolov8n.pt" if "last.pt" in str(runs[n]["args"].get("model", "")) or str(runs[n]["args"].get("model", "")).endswith("yolov8n.pt") else a(runs[n], "model")) for n in names]],
        ["Dataset", *["<code>datasets/" + Path(str(runs[n]["args"].get("data", "?"))).parent.name + "</code>" for n in names]],
        ["Epochs planned / done", *[f"{a(runs[n], 'epochs')} / {runs[n]['epochs_done']}" for n in names]],
        ["Patience ([[early stopping]])", *[a(runs[n], "patience") for n in names]],
        ["[[batch|Batch]] size", *[a(runs[n], "batch") for n in names]],
        ["[[image size|Image size]] used in training", *[a(runs[n], "imgsz") for n in names]],
        ["[[optimizer|Optimizer]] / start [[learning rate]]", *[f"{a(runs[n], 'optimizer')} / {a(runs[n], 'lr0')}" for n in names]],
        ["[[AMP]] (mixed precision)", *[a(runs[n], "amp") for n in names]],
        ["Random seed", *[a(runs[n], "seed") for n in names]],
        ["Colour / light changes (h, s, v)", *[f"{a(runs[n], 'hsv_h')} / {a(runs[n], 'hsv_s')} / {a(runs[n], 'hsv_v')}" for n in names]],
        ["Rotate / zoom / shift / flip", *[f"{a(runs[n], 'degrees')}&deg; / {a(runs[n], 'scale')} / {a(runs[n], 'translate')} / {a(runs[n], 'fliplr')}" for n in names]],
        ["[[mosaic]] (last N epochs off)", *[f"{a(runs[n], 'mosaic')} ({a(runs[n], 'close_mosaic')})" for n in names]],
        ["Resumed from a saved run", *[("yes" if str(runs[n]["args"].get("resume")) not in ("False", "None", "-") else "no") for n in names]],
    ]
    return rows


def build() -> Page:
    p = Page("2-models.html", "2", "Models",
             "Every model the system runs: what job it does, where it came from, which model it started from, how it was trained, how well it scored, and the exact code that loads and uses it.")
    tgt = targets()
    runs = {
        "Helmet": run_summary("helmet_specialist", "train-2"),
        "Plate": run_summary("plate_specialist", "train2"),
        "Cabin": run_summary("cabin_specialist", "train"),
        "Vehicles (6 classes)": run_summary("primary_anchor", "train"),
    }
    active_vehicle = (MODELS / "active_model.txt").read_text(encoding="utf-8").strip()
    manifest = json.loads((MODELS / "model_manifest.json").read_text(encoding="utf-8")).get("active_models", {})

    # ── overview ──────────────────────────────────────────────────────────────
    p.h2("overview", "All models at a glance", kicker="Start here", newpage=False)
    p.add("<p>The system is a <b>[[cascade]]</b>. One general [[object detection]] model looks at every frame and finds vehicles and people. Small [[specialist model]]s then look "
          "only at the crops they need (a rider, a plate, a windshield). A tracker keeps one steady number on each vehicle, and a text reader turns the plate crop into letters. "
          "Everything that is <i>not</i> a picture model (the rules that decide a violation) is explained on page 4.</p>")
    rows = [
        ["<b>Vehicle detector</b>", "Finds cars, motorcycles, buses, trucks, people in every frame.", f"<code>{esc(active_vehicle)}</code> (active)", mb(find(active_vehicle)),
         "Stock [[COCO]] model, not trained by us", chip("warn", "No tricycle / jeepney class")],
        ["<b>Helmet model</b>", "Is each rider wearing a helmet?", f"<code>{esc(manifest.get('helmet_specialist', '').split('/')[-1])}</code>", mb(find(manifest.get('helmet_specialist', '').split('/')[-1])),
         "[[YOLOv8n]] fine-tuned on the helmet set", chip("ok", "Trained")],
        ["<b>Plate model</b>", "Where is the licence plate?", f"<code>{esc(manifest.get('plate_specialist', '').split('/')[-1])}</code>", mb(find(manifest.get('plate_specialist', '').split('/')[-1])),
         "YOLOv8n fine-tuned on the (older) plate set", chip("warn", "Below target")],
        ["<b>Cabin model</b>", "Windshield, seatbelt, phone, side mirror.", f"<code>{esc(manifest.get('cabin_specialist', '').split('/')[-1])}</code>", mb(find(manifest.get('cabin_specialist', '').split('/')[-1])),
         "YOLOv8n fine-tuned on the cabin set", chip("warn", "Just under target")],
        ["<b>Car matcher</b> ([[ReID]])", "Is this the same car as before?", "<code>ckpt.t7</code>", mb(ROOT / "hulikamote_backend/engine/deep_sort/deep/checkpoint/ckpt.t7"),
         "Original [[DeepSORT]] network ([[Market-1501]] pedestrians)", chip("info", "Stock; retrain tool ready")],
        ["<b>Trackers</b>", "Keep one number on each vehicle.", "[[ByteTrack]] and DeepSORT", "-", "Algorithms, nothing to train", chip("ok", "Parameters locked")],
        ["<b>Plate reader</b> ([[OCR]])", "Letters and digits of the plate.", "[[EasyOCR]] (library)", "downloaded by the library", "Stock; PaddleOCR optional", chip("warn", "Cannot be fine-tuned here")],
        ["<b>Picture enhancers</b>", "Sharpen a small blurry plate before reading.", "[[Lanczos]], [[LapSRN]] x8, [[Real-ESRGAN]]", f"{mb(find('LapSRN_x8.pb'))} / {mb(find('realesrgan.onnx'))}",
         "Stock; a custom GAN trainer exists", chip("warn", "Experimental")],
    ]
    p.add(table(["Model", "Job", "File", "Size", "Origin", "State"], rows, "dense", ["15%", "21%", "21%", "8%", "20%", "15%"]))
    p.add(figure(_lineage(), "<b>How a trained model reaches the running system.</b> A pretrained model is fine-tuned on one of our datasets, exported to the ONNX format at the size it will run at, "
                 "copied to a folder in <code>hulikamote_backend/models/</code> and recorded in <code>model_manifest.json</code>; the registry loads it when the backend starts."))

    # scores
    groups = []
    for name, r in runs.items():
        b = r["best"]
        groups.append((f"{name} (epoch {b['epoch']} of {r['epochs_done']})", [b["P"], b["R"], b["map50"], b["map5095"]]))
    p.add(figure(hbar(groups, ["precision", "recall", "mAP@50", "mAP@50-95"], w=760, label_w=230, vmax=1.0, fmt=lambda v: f"{v:.2f}",
                      aria="Precision, recall, mAP at 50 and mAP at 50 to 95 of the four trained models on their validation sets"),
                 "<b>Scores of the four trained models</b> on the <i>validation</i> part of their own training data, at the best saved epoch. 1.00 would be perfect. "
                 "These are not scores on Zamboanga footage."))
    score_rows = []
    keymap = {"Helmet": "helmet_specialist", "Plate": "plate_specialist", "Cabin": "cabin_specialist", "Vehicles (6 classes)": "primary_anchor"}
    for name, r in runs.items():
        b, t = r["best"], tgt.get(keymap[name], 0.8)
        if name.startswith("Vehicles"):
            verdict = chip("bad", f"Run stopped at epoch {r['epochs_done']} of {r['args'].get('epochs')}; not deployed")
        elif b["map50"] >= t:
            verdict = chip("ok", "Meets the target")
        elif b["map50"] >= t - 0.05:
            peak = max(y for _, y in r["curve"])
            verdict = chip("warn", f"Just under (peak mAP@50 during training: {peak:.3f})")
        else:
            verdict = chip("bad", "Below the target")
        score_rows.append([f"<b>{name}</b>", f"{b['epoch']}", f"{b['P']:.3f}", f"{b['R']:.3f}", f"{b['map50']:.3f}", f"{b['map5095']:.3f}", f"{t:.2f}", verdict])
    p.add(table(["Model", "Best epoch", "[[precision]]", "[[recall]]", "[[mAP@50]]", "[[mAP@50-95]]", "Target mAP@50", "Verdict"], score_rows, "dense"))
    p.add(callout("warn", "Read every score above with three cautions",
                  "<ol><li><b>Validation, not test.</b> The numbers are from the validation part, which the training run also used to choose the best epoch. The sealed test part was never scored.</li>"
                  "<li><b>The data was cleaned later.</b> The helmet, plate and cabin models were trained on 2026-10-05, 09-24 and 10-13. The datasets were rebuilt and de-duplicated on 2026-10-25, and the cleaning "
                  "found near-identical pictures shared between train and validation (page 1). Scores from before that are likely optimistic; re-running <code>validate.py</code> on the cleaned sets will give the honest numbers.</li>"
                  "<li><b>Not our roads.</b> None of the training data is Zamboanga CCTV.</li></ol>"))
    p.add(figure(linechart([(f"{n.split(' (')[0]} ({r['epochs_done']})", r["curve"]) for n, r in runs.items()], xmax=100, ymax=1.0, ylabel="mAP@50 on validation",
                           aria="How mAP at 50 on the validation set changed epoch by epoch for the four runs"),
                 "<b>Learning curves.</b> Each line is one training run; the number in brackets is how many epochs it ran. Helmet stopped by itself after 62 epochs because it stopped improving ([[early stopping]]). "
                 "The vehicle run was interrupted at epoch 23. A flat line means the model has learned what it can from that data."))
    p.add(table(["Run folder", "Notes"], [
        ["<code>helmet_specialist/train</code>", "19 epochs, abandoned: it was killed when the backend reloaded while it ran inside the backend. Not used."],
        ["<code>helmet_specialist/train-2</code>", "The real helmet run (62 epochs, stopped early). Deployed on 2026-10-05."],
        ["<code>plate_specialist/train</code>", "The first plate run (only exported weights remain). Its ONNX is the legacy <code>plate_specialist.onnx</code>."],
        ["<code>plate_specialist/train2</code>", "The deployed plate run (100 epochs). Deployed on 2026-09-24."],
        ["<code>cabin_specialist/train</code>", "100 epochs, resumed after an interruption. Deployed on 2026-10-13."],
        ["<code>primary_anchor/train</code>", "The 6-class vehicle run, resumed; stopped at epoch 23 of 30; not deployed."],
    ], "dense", ["32%", "68%"]))
    p.end()

    # ── 1. vehicle detector ───────────────────────────────────────────────────
    p.h2("m-vehicle", "Vehicle detector", kicker="Model 1 &middot; first stage, every frame")
    p.add("<p><b>Job.</b> Look at the whole camera frame and draw a box around every vehicle and every person. Everything later (tracking, zones, riders, plates) starts from these boxes.</p>")
    p.add(kv([
        ("Active file", f"<code>{esc(active_vehicle)}</code> &middot; chosen in the dashboard <i>Models</i> tab and stored in <code>models/active_model.txt</code>"),
        ("Other files", "<code>yolov8n.onnx</code> (Ultralytics' own release of the pretrained nano model, fetched by <code>scripts/download_model.py</code>) and <code>yolo26_primary.onnx</code> (kept for comparison)"),
        ("Where it comes from", "Stock pretrained [[YOLO]] models trained by Ultralytics on [[COCO]]. The <code>yolo11</code> and <code>yolo26</code> files were exported to [[ONNX]] with Ultralytics 8.4.160 "
                                "(read from the files' own metadata); the exact source weights and who exported them are not recorded in the repository."),
        ("Starting model", "None: we use it as downloaded. We have <b>not</b> fine-tuned a deployed vehicle model."),
        ("Input", "One picture, [[letterbox]]ed to 640 x 640, RGB, values 0 to 1."),
        ("Output", "8,400 candidate boxes with 80 class scores each; boxes under [[confidence]] 0.45 are dropped, duplicates are removed by [[NMS]] (overlap above 0.50). People get their own NMS group so a rider does not delete the motorcycle."),
        ("Classes we keep", "From COCO's 80: person, bicycle, motorcycle, car, bus, truck, traffic light, stop sign. Everything else is ignored."),
        ("Not in COCO", "<b>Tricycle</b> and <b>jeepney</b>. They appear as motorcycle, car, bus or truck, or are missed."),
    ]))
    p.add(callout("info", "The Philippine fine-tune that exists but is not deployed",
                  "<p>A 6-class run (motorcycle, car, bus, truck, person, tricycle; jeepney as bus) started from <code>yolov8n.pt</code> on the vehicle set and was planned for 30 epochs. "
                  f"It stopped at epoch {runs['Vehicles (6 classes)']['epochs_done']} with mAP@50 {runs['Vehicles (6 classes)']['best']['map50']:.2f}, below the 0.80 target, and was never deployed. "
                  "Continue it (Training Studio &rarr; Continue) and test it on the local clip before switching.</p>"))
    p.add(code("hulikamote_backend/yolo_inference.py", symbol="YoloInference.preprocess", title="How a frame is prepared for the detector", walk=[
        ("scale = min(INPUT_SIZE", "Shrink the frame so the longer side is 640 pixels, keeping its shape."),
        ("padded = np.full", "Make a grey 640 x 640 square (grey value 114, the value the model was trained with)."),
        ("padded[pad_y", "Put the shrunk frame in the middle of the square: this is the [[letterbox]]."),
        ("[:, :, ::-1]", "OpenCV loads pictures as blue-green-red; the model was trained on red-green-blue, so the colour channels are flipped."),
    ]))
    p.add(code("hulikamote_backend/yolo_inference.py", symbol="YoloInference.infer", title="How the detector's answer is turned into vehicle boxes",
               skip=[("# ── sv.ByteTrack update", "self.tracker.update_with_detections(sv.Detections.empty(), frame)")], walk=[
        ("outputs = self._session.run", "Run the model. This is the only line that uses the neural network."),
        ("confidences >= CONFIDENCE_THRESHOLD", "Throw away guesses the model is not at least 45% sure of."),
        ("Undo letterbox", "Convert the boxes from the 640 x 640 square back to the original frame's pixels."),
        ("is_person = np.array", "People are grouped separately for [[NMS]], so riders are not deleted by the motorcycle they sit on."),
        ("COCO_VIOLATION_MAP.get", "Keep only the classes the system cares about (see the map near the top of the file)."),
    ]))
    p.add(ref("hulikamote_backend/models/active_model.txt", line=1, label="active_model.txt") + ref("hulikamote_backend/engine/model_catalog.py", symbol="activate", label="model_catalog.activate (switching the active model)")
          + ref("hulikamote_backend/scripts/download_model.py", symbol=None, line=1, label="download_model.py"))
    p.end()

    # ── 2-4. specialists ──────────────────────────────────────────────────────
    def specialist(ident, title, kicker, job, file_key, run_key, run_name, dataset_key, classes, extra_rows, base_note, limits, walk_block):
        p.h2(ident, title, kicker=kicker)
        fname = manifest.get(file_key, "").split("/")[-1]
        r = runs[run_name]
        b = r["best"]
        p.add(f"<p><b>Job.</b> {job}</p>")
        p.add(kv([
            ("Active file", f"<code>{esc(fname)}</code> ({mb(find(fname))}) &middot; listed in <code>models/model_manifest.json</code> under <code>{file_key}</code>"),
            ("Starting model", f"<code>yolov8n.pt</code>: the pretrained nano [[YOLOv8n]] from [[Ultralytics]], taught on [[COCO]] first. {base_note} This is [[transfer learning]]: the model already knows edges, shapes and textures, so our pictures only have to teach the new task ([[fine-tuning]])."),
            ("Trained on", f"<code>training_lab/datasets/{dataset_key}</code> &middot; {classes}"),
            ("Run that made it", f"<code>training_lab/runs/{run_key}/{run_name_folder(run_name)}/</code> ({r['epochs_done']} epochs; best saved at epoch {b['epoch']} by [[fitness]])"),
            ("Input / output", "A crop, [[letterbox]]ed to <b>320 x 320</b> RGB. Output: 2,100 candidate boxes, each with the class scores; duplicates removed by NMS (overlap above 0.45)."),
            *extra_rows,
        ]))
        p.add(table(["Setting"] + [run_name], [[row[0], row[1]] for row in recipe_rows({run_name: r})], "dense", ["38%", "62%"]))
        p.add("<p class='note'>Trained at image size 640, then exported to ONNX at 320 (the size of the crops the system really feeds it). The scores in the table above were measured at 640, "
              "so the 320 export may score a little differently.</p>")
        p.add("<h4>Known limits</h4><ul>" + "".join(f"<li>{x}</li>" for x in limits) + "</ul>")
        p.add(walk_block)
        p.end()

    specialist(
        "m-helmet", "Helmet model", "Model 2 &middot; specialist, one look per rider group",
        "Decide, for each rider on a motorcycle, whether the head is covered by a helmet. It is run on the motorcycle <i>together with its riders</i> so heads are never cut off.",
        "helmet_specialist", "helmet_specialist", "Helmet", "helmet_specialist", "2 classes: <code>rider_with_helmet</code>, <code>rider_without_helmet</code>",
        [("Used by", ref("hulikamote_backend/engine/violations/no_helmet.py", symbol="@doc", label="no_helmet.py") + " (page 4)")],
        "", ["Most helmet pictures are close-ups or stock photos; fixed-camera CCTV views are the minority.",
             "Heads are small at the distance of a road camera. The model was not tested on Zamboanga footage."],
        code("hulikamote_backend/engine/specialist_jobs.py", symbol="HelmetJob", title="How the helmet model is used", walk=[
            ("name = \"helmet\"", "This job is called 'helmet' and uses the model named helmet_specialist."),
            ("det.cls == \"motorcycle\"", "It only looks at motorcycles."),
            ("rider_boxes(det.bbox", "Find the people sitting on this motorcycle."),
            ("boxes = [det.bbox] + riders", "Make one box that covers the motorcycle AND its riders, so heads are inside."),
            ("specialists.detect(session, crop", "Run the model on that crop at 'check' confidence 0.4, then move the boxes back onto the full frame."),
        ]))
    specialist(
        "m-plate", "Plate model", "Model 3 &middot; specialist, runs for every ticketed vehicle",
        "Find the licence plate inside a vehicle box so it can be cropped and read. The result is on every ticket, and the <i>absence</i> of a plate is the no-plate violation.",
        "plate_specialist", "plate_specialist", "Plate", "plate_specialist", "1 class: <code>license_plate</code>",
        [("Older file", "<code>plate_specialist.onnx</code>: the first plate run, kept as a fallback. Choose either in the analysis wizard (<code>plate_model</code>)."),
         ("Used by", ref("hulikamote_backend/engine/violations/no_plate.py", symbol="@doc", label="no_plate.py") + " and every ticket's plate text")],
        "It was trained on the older plate set, before the dataset library existed.",
        ["It scores well below its 0.90 target, mainly because the plate pictures are not Philippine and the largest part is grey Vietnamese barrier footage.",
         "The models used to be fed BGR and stretched crops, and only the bottom 40% of the vehicle; that mistake (plate found in 7% of held-out photos instead of 83%) was fixed on 2026-10-24 in <code>engine/specialists.py</code>.",
         "Retraining on the cleaned set plus our own harvested plate pictures is the next step."],
        code("hulikamote_backend/engine/specialist_jobs.py", symbol="PlateJob.look", title="How the plate model is used", skip=[("if direct:", "ledger.plate_crops.append((area, area, stamp))")], walk=[
            ("area = frame[py1:py2", "Cut out the whole vehicle (not just a bumper strip): the model was trained on whole vehicles."),
            ("specialists.detect(session, area, specialists.SEARCH_CONF)", "Run the plate model at a low confidence (0.1): finding a plate only needs a box so it can be read."),
            ("best = plates[0]", "Keep the most confident plate."),
            ("tight = frame[", "Cut a tight crop with a 10% margin. This is what [[EasyOCR]] will read."),
            ("ledger.plate_crops.append((tight", "Keep up to 40 crops per vehicle with their time: later the best reading is chosen by voting."),
        ]))
    specialist(
        "m-cabin", "Cabin model", "Model 4 &middot; specialist, one model for three violations",
        "Look at a whole vehicle and find the windshield (clear or tinted), a seatbelt, a phone in the driver's hand and, on motorcycles, side mirrors.",
        "cabin_specialist", "cabin_specialist", "Cabin", "cabin_specialist", "5 classes: <code>clear_window</code>, <code>tinted_window</code>, <code>seatbelt</code>, <code>driver_phone</code>, <code>side_mirror</code>",
        [("Used by", ref("hulikamote_backend/engine/violations/no_seatbelt.py", symbol="@doc", label="no_seatbelt.py") + ref("hulikamote_backend/engine/violations/distracted_driving.py", symbol="@doc", label="distracted_driving.py")
          + ref("hulikamote_backend/engine/violations/missing_side_mirror.py", symbol="@doc", label="missing_side_mirror.py"))],
        "The run was resumed from its saved last.pt after an interruption.",
        ["There is no tinted-window or side-mirror example in validation or test, so those two classes have never been scored.",
         "The deployed file (2026-10-13) was trained before the side-mirror data was merged (2026-10-25): it has not learned mirrors, so <b>Missing Side Mirror cannot work yet</b>.",
         "Tinted windows are only taught from general car-sale photos; the safety gate must be tested on Zamboanga footage before it is trusted."],
        code("hulikamote_backend/engine/specialist_jobs.py", symbol="CabinJob", title="How the cabin model is used", walk=[
            ("violations = (\"no_seatbelt\"", "One look serves three violations, so the model runs once per vehicle, not three times."),
            ("det.cls in VEHICLE_CLASSES", "It looks at any vehicle class; each violation then decides whether the look applies to it (a motorcycle has no seatbelt rule)."),
            ("crop = NumpySlicer.crop_box(frame, det.bbox)", "Cut the whole vehicle out of the frame."),
            ("specialists.detect(session, crop", "Run the model on it at confidence 0.4 and map the boxes back to the frame."),
        ]))

    # ── how specialists are fed ───────────────────────────────────────────────
    p.h2("m-feeding", "How the specialist models are fed", kicker="One place does it right")
    p.add("<p>All three specialists are run through the same two functions. This matters: the models were trained by Ultralytics on <b>RGB</b> pictures that were <b>letterboxed</b>, and their duplicate boxes were removed with <b>NMS</b>. "
          "An earlier version of the app fed them BGR, stretched crops and no NMS, and on held-out photos the plate was found 7% of the time instead of 85%. The fix lives in one file so it cannot drift.</p>")
    p.add(code("hulikamote_backend/engine/specialists.py", symbol="letterbox", walk=[
        ("scale = min(size / w", "Work out how much to shrink the crop so it fits inside the square without changing its shape."),
        ("canvas = np.full", "A grey square (value 114) the size the model expects."),
        ("canvas[pad_y", "Put the crop in the centre."),
        ("rgb = canvas[:, :, ::-1]", "Flip the colour channels from OpenCV's BGR to the RGB the model was trained on."),
        ("/ 255.0", "Scale pixel values from 0..255 to 0..1 and arrange them as the model's input tensor."),
    ]))
    p.add(code("hulikamote_backend/engine/specialists.py", symbol="detect", walk=[
        ("blob, scale, pad_x, pad_y = letterbox", "Prepare the crop."),
        ("session.run(None", "Run the model."),
        ("class_scores.argmax", "Each candidate box has one score per class; take the best class and its score."),
        ("keep = confidences >= conf", "Drop candidates below the confidence limit. Finding things uses 0.1, deciding a violation uses 0.4."),
        ("x1 = ((cx - bw / 2 - pad_x) / scale)", "Undo the letterbox: turn model coordinates back into crop pixels."),
        ("nms(boxes[members]", "Remove duplicate boxes of the same class (overlap above 0.45)."),
    ]))
    p.add(code("hulikamote_backend/engine/registry.py", symbol="ModelRegistry._initialize_models", title="How the right file is found and loaded when the backend starts", walk=[
        ("model_manifest.json", "The manifest says which file is the active helmet, plate or cabin model."),
        ("def get_path(name)", "Look for the manifest's file first, then the default file name, then search the models folder."),
        ("self._load_model(\"primary_anchor\"", "A vehicle model must exist (the system stops without it). The frame detector actually used is chosen separately (see Vehicle detector)."),
        ("if \"no_helmet\" in self.active_violations", "A specialist is loaded only when a violation that needs it is switched on: this keeps the system light."),
        ("self._load_model(\"plate_specialist\"", "The plate model is always loaded, because every ticket carries a plate."),
        ("if {\"no_seatbelt\"", "The cabin model is loaded if any of its three violations is on."),
    ]))
    p.add(ref("hulikamote_backend/inference/providers.py", symbol=None, line=1, label="providers.py (GPU first, CPU fallback)") + ref("hulikamote_backend/engine/model_catalog.py", symbol="@doc", label="model_catalog.py"))
    p.end()

    # ── 5. tracker and ReID ───────────────────────────────────────────────────
    p.h2("m-tracker", "Trackers and the car matcher", kicker="Model 5 &middot; same number for the same car")
    p.add("<p><b>Job.</b> Give every vehicle one steady [[track ID]] from frame to frame, even when it is briefly hidden. Violations that depend on movement (counterflow, parking, turns) need this.</p>")
    p.add(kv([
        ("[[DeepSORT]]", "Predicts where a vehicle should be next and also compares what it <i>looks like</i> using a small network (the car matcher). The system uses it as the default for forensic analysis. Settings: forget a vehicle after 60 missed frames, 3 confirmed frames before an ID is locked, appearance distance limit 0.4."),
        ("[[ByteTrack]]", "Matches only by box overlap. Faster, but in one check on our footage it left 58% of detections without a track (DeepSORT: 2%). It is the analysis wizard's default, so <b>choose DeepSORT</b>. Settings: 60 missed frames, matching threshold 0.2."),
        ("Car matcher network", "<code>ckpt.t7</code> (46 MB). It is the original network shipped with DeepSORT, a small CNN trained on [[Market-1501]], a dataset of <b>pedestrians</b>; it reads a 64 x 128 picture and returns a [[fingerprint]]. It has not been replaced."),
        ("Starting point for our own", "The fine-tuning script starts from the current <code>ckpt.t7</code>, keeps its classifier layer so DeepSORT loads it with no code change, and deploys a new file only if it finds <i>unseen</i> cars better (page 3)."),
        ("Evidence it can improve", "On 67 real ticketed cars from two clips, the fine-tuned matcher found a car again 85.3% of the time versus 76.7% for the stock one, on new cars from the same cameras (3 of 3 random splits); on a different road there was no gain."),
        ("Locked", "The tracker settings are locked by the project owner: do not tune them. If tracking must improve, replace or fine-tune the matcher."),
    ]))
    p.add(code("hulikamote_backend/engine/tracker.py", symbol="DeepSortStrategy.__init__", walk=[
        ("ckpt_path", "The car matcher network is loaded from this file."),
        ("max_dist=max_dist", "How different two fingerprints may be and still count as the same car."),
        ("max_age=lost_track_buffer", "How many frames a vehicle may be missing before its track is dropped."),
        ("n_init=3", "A new object must be seen in 3 frames in a row before it gets an ID, which stops flickers from becoming vehicles."),
        ("use_cuda=use_cuda", "Use the graphics card when one is available."),
    ]))
    p.add(code("hulikamote_backend/engine/tracker.py", symbol="DeepSortStrategy.update_with_detections", skip=[("# Re-pack into sv.Detections", "tracked_class_ids.append")], walk=[
        ("boxes_xywh.append", "DeepSORT wants the CENTRE of each box plus its width and height; sending the top-left corner was a bug fixed in Session 014."),
        ("cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)", "The matcher reads RGB pictures, so the frame's colours are flipped first."),
        ("self.tracker.update(", "Match this frame's boxes with the tracks that already exist, using motion and fingerprints."),
    ]))
    p.add(ref("training_lab/scripts/train_reid.py", symbol="@doc", label="train_reid.py") + ref("training_lab/experiments/reid/RESULTS.md", line=1, label="RESULTS.md (the evidence)")
          + ref("hulikamote_backend/engine/track_stitcher.py", symbol="@doc", label="track_stitcher.py (re-joins a broken track by colour)"))
    p.end()

    # ── 6. OCR ────────────────────────────────────────────────────────────────
    p.h2("m-ocr", "Plate reader (OCR) and picture enhancers", kicker="Model 6 &middot; from plate picture to plate text")
    p.add("<p><b>Job.</b> Turn a cropped plate picture into letters and digits. The plate model finds the plate; this step reads it. Each vehicle keeps up to 40 plate crops, every crop is read, and the "
          "<b>most voted reading wins</b>, so one blurry frame cannot decide the plate.</p>")
    p.add(kv([
        ("Reader", "[[EasyOCR]] for English. It finds the text in the crop and reads each piece. It is restricted to the characters <code>0-9</code> and <code>A-Z</code>. Its network files are downloaded by the library on first use (not stored in this repository). PaddleOCR can be chosen instead if it is installed."),
        ("Not trained by us", "The EasyOCR package has no trainer, so the plate text set can only <b>score</b> it. A PaddleOCR trainer is written but its tools are not installed."),
        ("Format rule", "<code>ph_standard</code> assumes 3 letters then 4 digits and fixes look-alikes by position (for example an <code>O</code> in a digit place becomes <code>0</code>). <code>uk_standard</code> and <code>raw</code> also exist. Set <code>plate_format</code> to <code>ph_standard</code> for local demos."),
        ("Enhancers (before reading)", "<b>Lanczos</b> (classic, default): enlarge 4 times smoothly. <b>LapSRN x8</b>: a small network (<code>LapSRN_x8.pb</code>, 3.9 MB, from an open TensorFlow port, run through OpenCV) that enlarges 8 times. "
                                       "<b>Real-ESRGAN</b>: a [[GAN]] that enlarges 4 times (<code>realesrgan.onnx</code>, 67 MB, the size of the official x4plus model; the repository does not record which of its two scripts made the deployed file)."),
        ("Honest note", "Enhancers can invent plausible but wrong characters. They are optional, and a read is kept only as one vote among many."),
    ]))
    p.add(code("hulikamote_backend/engine/pipeline.py", symbol="_extract_plate_text", skip=[("if ocr_engine == \"paddleocr\":", "raw = re.sub(r'[^0-9A-Z]', '', raw)")], walk=[
        ("if enhancement == \"realesrgan\"", "Optionally enlarge and sharpen the crop first (three choices; Lanczos is the default)."),
        ("cv2.COLOR_BGR2GRAY", "EasyOCR reads a grey version."),
        ("readtext(gray", "Read the text. The allowlist keeps only digits and capital letters."),
        ("confidence = sum(confidences)", "The reading's confidence is the average of its pieces."),
        ("dict_char_to_int", "Look-alike tables: letters that are often mistaken for digits, and the reverse."),
        ("if plate_format == \"ph_standard\"", "By position: the first three characters must be letters, the next four digits."),
    ]))
    p.add(code("hulikamote_backend/routers/forensic.py", symbol="forensic_processing_task.get_vote_score", title="How the best plate reading is chosen (voting over many crops)", walk=[
        ("score = vote_count + conf_map", "A reading's score is how many crops gave it, plus the best confidence it got."),
        ("len(text) in (6, 7)", "A big bonus (+20) to readings with a plausible Philippine plate length, so a short or long misread cannot win."),
    ]))
    p.add(ref("hulikamote_backend/scripts/download_sr.py", line=1, label="download_sr.py (LapSRN)") + ref("training_lab/scripts/download_esrgan.py", symbol="@doc", label="download_esrgan.py")
          + ref("training_lab/scripts/train_realesrgan.py", symbol="@doc", label="train_realesrgan.py (experimental GAN trainer)"))
    p.end()

    # ── 7. not neural ─────────────────────────────────────────────────────────
    p.h2("m-other", "Parts that look intelligent but are not neural networks", kicker="So the word 'model' is not over-used")
    p.add("<p>Several decisions use <b>measurement and rules</b>, not a trained network. They are listed here because they are easy to mistake for models. Each is explained with its code on page 4.</p>")
    p.add(table(["Part", "What it does", "How", "Code"], [
        ["Traffic-light colour reader", "Says red, yellow or green from a box around the light.", "Counts bright, saturated pixels by [[HSV]] colour range.", ref("hulikamote_backend/engine/traffic_light.py", symbol="read_light_colour", label="read_light_colour")],
        ["Simulated light", "A timer that plays red, green, yellow for recorded clips.", "Arithmetic on the video time.", ref("hulikamote_backend/engine/traffic_light.py", symbol="timer_phase", label="timer_phase")],
        ["Indicator blink detector", "Sees an amber light blinking at the edge of a vehicle.", "Share of amber pixels over time, steady on/off at 0.5 to 3 [[Hz]].", ref("hulikamote_backend/engine/traffic_light.py", symbol="is_blinking", label="is_blinking")],
        ["Traffic-flow learner", "Learns the legal direction of traffic without drawn zones.", "A vote grid: each moving vehicle votes for its direction in its cell.", ref("hulikamote_backend/engine/flow_field.py", symbol="FlowField", label="FlowField")],
        ["Track stitcher", "Re-joins a vehicle whose track broke.", "Compares a colour signature, position and time.", ref("hulikamote_backend/engine/track_stitcher.py", symbol="@doc", label="track_stitcher")],
        ["Vote", "Turns many uncertain looks into one decision.", "'Bad in at least 60% of the last 10 looks.'", ref("hulikamote_backend/engine/ledger.py", symbol="ActiveLedgerManager.vote", label="vote")],
    ], "dense"))
    info = tests_info("hulikamote_backend/engine/specialists.py")
    if info:
        p.add(f"<p class='note'>Test coverage of <code>engine/specialists.py</code> (the feeding code): {info['coverage']}% of its lines, {info['tests']} tests (from the tests index built {esc(info['generated'])}).</p>")
    p.end()
    return p


def run_name_folder(run_name: str) -> str:
    return {"Helmet": "train-2", "Plate": "train2", "Cabin": "train"}.get(run_name, "train")


def _lineage() -> str:
    parts = [
        box(8, 110, 150, 70, ["Pretrained model", "yolov8n.pt", "(COCO, Ultralytics)"], "c1"),
        box(215, 14, 190, 46, ["Helmet set", "fine-tune, 62 epochs"], "c3"),
        box(215, 74, 190, 46, ["Plate set", "fine-tune, 100 epochs"], "c3"),
        box(215, 134, 190, 46, ["Cabin set", "fine-tune, 100 epochs"], "c3"),
        box(215, 194, 190, 46, ["Vehicle set (6 classes)", "stopped at epoch 23"], "c3 dash"),
        box(8, 250, 150, 44, ["Stock COCO models", "yolo11 / yolo26 / v8n"], "c1"),
        box(455, 70, 130, 60, ["Export to ONNX", "320 px (specialists)"], "c4"),
        box(455, 190, 130, 50, ["Export to ONNX", "640 px (vehicles)"], "c4 dash"),
        box(625, 14, 128, 70, ["models/ folder", "+ model_manifest", "(or active_model)"], "c7"),
        box(625, 120, 128, 70, ["Registry loads", "at backend start", "(only what is needed)"], "c7"),
        box(625, 224, 128, 70, ["Jobs run it", "on crops, vote,", "violation modules"], "c7"),
        arrow(158, 130, 215, 40), arrow(158, 140, 215, 97), arrow(158, 150, 215, 157), arrow(158, 160, 215, 217, "", True),
        arrow(405, 37, 455, 90), arrow(405, 97, 455, 100), arrow(405, 157, 455, 112),
        arrow(158, 272, 455, 215, "", True), arrow(585, 100, 625, 50), arrow(585, 215, 625, 60, "", True),
        arrow(689, 84, 689, 120), arrow(689, 190, 689, 224),
    ]
    return svg(760, 305, "".join(parts), "How a pretrained model becomes a deployed ONNX model")
