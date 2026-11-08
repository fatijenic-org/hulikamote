"""Page 1 - Datasets. Counts, sources and licences are read from the dataset cards and the manifest."""
from __future__ import annotations

import re
import sqlite3

from lib import (ROOT, Page, callout, card, chip, cmd, code, esc, figure, hbar, kv, manifest, md_inline, num, ref, steps,
                 svg, table, whole, box, arrow)

DATASETS = ROOT / "training_lab" / "datasets"

# Plain-language meaning of every class, per dataset
CLASS_MEANING = {
    "primary_anchor": {
        "motorcycle": "A motorcycle (the rider is a separate 'person' box).",
        "car": "Cars and vans. A van is merged into car.",
        "bus": "Buses and also jeepneys, because there is no jeepney class.",
        "truck": "Trucks and semi-trucks. Pickups are usually found here too.",
        "person": "A person: rider, passenger or pedestrian. Needed to count riders and passengers.",
        "tricycle": "The Philippine motorcycle with a sidecar, including the electric kind.",
    },
    "helmet_specialist": {
        "rider_with_helmet": "A whole rider (torso and head) wearing a helmet, full-face or half.",
        "rider_without_helmet": "A whole rider with a bare head.",
    },
    "plate_specialist": {"license_plate": "A tight box around the licence plate itself."},
    "cabin_specialist": {
        "clear_window": "A windshield you can see through. Needed before seatbelt or phone can be judged.",
        "tinted_window": "A tinted window. It switches the seatbelt and phone checks off (safety gate).",
        "seatbelt": "The diagonal strap across the driver's chest.",
        "driver_phone": "A phone held by the driver, near the head or the wheel.",
        "side_mirror": "A side mirror seen on a motorcycle.",
    },
}

# What each source is, in plain words, and what it adds (by source id)
SOURCE_NOTE = {
    # primary_anchor
    "ph_vehicles": "Philippine vehicle photos with jeepneys and tricycles, mixed with ordinary web, stock and Street View pictures. Heavily augmented (rotated, upside-down, noisy copies). Contributes most of the vehicle pictures and the only large tricycle and jeepney examples.",
    "ph_plate_vehicle": "A small Philippine set of vehicles and plates, including e-jeepney and e-tricycle. Few pictures, but all Philippine.",
    "ph_vehicles_selfdev": "Philippine web photos of single vehicles (jeepney, van, bus, tricycle) with large boxes. All of it is used for training only, because its own validation and test parts hold almost no motorcycle, tricycle or bus boxes.",
    # helmet
    "edgevision_helmet": "2,392 real motorcycle-traffic photos from Gujarat, India, from a peer-reviewed data paper. Head-level boxes. The most trustworthy road photos in the helmet set, but not Philippine.",
    "flashys_helmet": "Mostly stock photos of people on scooters (watermarks visible) with head-level boxes and augmented copies. Weak evidence for real road accuracy; kept because it is large. Trust grade C.",
    "martinez_helmet": "Philippine CCTV from one Manila street camera, cut to motorcycle-plus-riders crops (the shape the helmet model is fed). Only about 105 no-helmet boxes, so it mostly adds compliant riders as seen by a CCTV camera. Training only.",
    "naratip_helmet": "Close-up photos of riders from Thailand, head-level boxes, some stock-like. The training part holds rotated copies with black corners.",
    # plate
    "colorum_plates": "Indian, UK and US plates from car-sale photos, despite the Philippine-sounding name. A few boxes sit on the wrong spot (a headlight).",
    "govviolation_plates": "Egyptian enforcement cameras with Arabic plates.",
    "indonesia_plates": "South-East Asian plates (Indonesia) in YOLO format, from Zenodo. The original project named no licence, so research use only.",
    "legacy": "Roboflow exports that were already committed to the repository before the dataset library existed. Their exact origins are not recorded.",
    "my_plates": "Malaysian car plates from Multimedia University, hosted on Mendeley Data. Trust grade A.",
    "oi_plates": "Real colour photos of plates from all over the world, from Google's Open Images, sampled to 3,000 / 400 / 400 pictures. Trust grade A.",
    "ph_plates": "Named 'ph' but the pictures are grey Vietnamese parking-barrier photos with heavy augmentation. One camera view repeated many times.",
    "tr_plates250": "250 real Turkish plates, text in the file name, from Zenodo. Trust grade A.",
    # cabin
    "govviolation_cabin": "Egyptian enforcement cameras seen through the windshield (Arabic plates): windshield, seatbelt and phone.",
    "mc_helmet_overload": "A Philippine street camera (jeepneys and tricycles are visible): about 3,100 small motorcycle crops with side-mirror boxes. The only side-mirror data we have. Training only; each crop is only about 40 x 90 pixels.",
    "menna_cabin": "Enforcement-camera views through the windshield (Arabic plates): windshield, seatbelt, phone. The same cars repeat across train, validation and test (video frames and augmented copies), which the cleaning step reduced.",
    "tint_windows": "General car-sale photos with a box on every tinted window; many pictures are taken from INSIDE the car and the set has no clear windows. Training only: the tint gate must be tested on Zamboanga footage before it is trusted.",
    "tpnew_seatbelt": "A small seatbelt set. Its first export put every picture in 'test', so all of it is used for training.",
}

MODEL_LABEL = {
    "primary_anchor": "Vehicle detector",
    "helmet_specialist": "Helmet model",
    "plate_specialist": "Plate model",
    "cabin_specialist": "Cabin model",
}


def ph_share(model: str) -> tuple[int, int, int]:
    """(Philippine pictures, all pictures, percent) from the card line."""
    m = re.search(r"Philippine pictures: \*\*([\d,]+) of ([\d,]+) \((\d+)%\)", card(model)["text"])
    return (int(m.group(1).replace(",", "")), int(m.group(2).replace(",", "")), int(m.group(3))) if m else (0, 0, 0)


def split_totals(model: str) -> dict:
    out = {}
    for row in card(model)["contents"]:
        out[row["split"]] = int(row["pictures"].replace(",", ""))
    return out


def count_files(folder, pattern="*.jpg") -> int:
    try:
        return sum(1 for _ in folder.rglob(pattern))
    except Exception:
        return 0


def harvest_counts() -> dict:
    """Items in the harvest inbox by model and state (read-only)."""
    db = ROOT / "training_lab" / "harvest_inbox" / "harvest.db"
    try:
        con = sqlite3.connect(f"file:{db.as_posix()}?mode=ro", uri=True)
        rows = con.execute("select model, state, count(*) from items group by model, state").fetchall()
        con.close()
        return {(m, s): n for m, s, n in rows}
    except Exception:
        return {}


def yolo_section(p: Page, key: str, title: str, ident: str, intro: str, contribution: str, extra_limits: list[str] = ()) -> None:
    c = card(key)
    mf = manifest().get(key, []) or []
    by_id = {e["id"]: e for e in mf}
    totals = split_totals(key)
    ph, allp, pct = ph_share(key)

    p.h2(ident, title, kicker=f"Dataset &middot; trains the {MODEL_LABEL[key].lower()}")
    p.add(intro)
    p.add(kv([
        ("Pictures", f"{num(totals.get('train', 0))} train &middot; {num(totals.get('val', 0))} validation &middot; {num(totals.get('test', 0))} test"),
        ("Philippine share", f"{ph:,} of {allp:,} pictures ({pct}%)" if allp else "-"),
        ("Folder", ref(f"training_lab/datasets/{key}/data.yaml", line=1, label=f"datasets/{key}/")),
        ("Full card", ref(f"training_lab/datasets/{key}/DATASET_CARD.md", line=1, label="DATASET_CARD.md")),
    ]))

    p.h3(f"{ident}-classes", "What the [[label]]s say")
    meaning = CLASS_MEANING[key]
    class_cols = [k for k in c["contents"][0].keys() if k not in ("split", "pictures")]
    rows = []
    for i, cls in enumerate(class_cols):
        vals = {r["split"]: r[cls] for r in c["contents"]}
        rows.append([f"<b>{i}</b>", f"<code>{esc(cls)}</code>", meaning.get(cls, ""),
                     vals.get("train", "0"), vals.get("val", "0"), vals.get("test", "0")])
    p.add(table(["id", "[[class]]", "Plain meaning", "train boxes", "val boxes", "test boxes"], rows, "dense"))

    p.h3(f"{ident}-sources", "Where the pictures come from")
    srows = []
    for r in c["sources"]:
        sid = r["source"]
        entry = by_id.get(sid, {})
        mapping = entry.get("classes")
        mapped = "<br>".join(f"<code>{esc(k)}</code> &rarr; <code>{esc(v)}</code>" for k, v in mapping.items()) if mapping else "<span class='note'>as committed</span>"
        link = f'<a href="{esc(r["link"])}" target="_blank" rel="noopener">source</a>' if r.get("link", "").startswith("http") else "-"
        cite = f"<br><span class='note'>{esc(entry['citation'])}</span>" if entry.get("citation") else ""
        srows.append([
            f"<b>{esc(sid)}</b><br>{link}",
            SOURCE_NOTE.get(sid, "") + cite,
            esc(r["country"]),
            esc(r["licence"]),
            esc(r["trust"].split(" ")[0]),
            f"{r['train']} / {r['val']} / {r['test']}",
            mapped,
        ])
    p.add(table(["Source", "What it is and what it adds", "Country", "Licence", "[[trust grade|Trust]]", "train / val / test", "Their class &rarr; ours"], srows, "dense",
                ["12%", "34%", "8%", "12%", "5%", "9%", "20%"]))

    p.h3(f"{ident}-study", "How it contributes to the study")
    p.add(contribution)

    p.h3(f"{ident}-limits", "Known limits")
    items = [md_inline(i) for i in c["limits"]] + list(extra_limits)
    p.add("<ul>" + "".join(f"<li>{i}</li>" for i in items) + "</ul>")

    clean = md_inline(c["cleaning"])
    p.add(callout("info", "How it was cleaned", f"<p>{clean.replace(chr(10), '<br>')}</p>"))
    p.add(f"<p class='note'>Rebuild this dataset from scratch:</p>" + cmd(
        f"python scripts/fetch_datasets.py --model {key}\npython data.py curate --model {key} --apply\npython data.py report"))
    p.end()


def build() -> Page:
    p = Page("1-datasets.html", "1", "Datasets",
             "Every picture collection our models learn from: what is in it, who made it, what the licence says, which model it trains and what it adds to the study. "
             "Read this page first, because a model is only as good as the pictures it was taught with.")

    sizes = {k: split_totals(k) for k in MODEL_LABEL}
    shares = {k: ph_share(k) for k in MODEL_LABEL}

    # ── 0. Overview ───────────────────────────────────────────────────────────
    p.h2("overview", "The big picture", kicker="Start here", newpage=False)
    p.add("<p>A [[dataset]] is a folder of pictures plus the correct answer for each one. We use <b>four detection datasets</b> (one for each [[YOLO]] model) and "
          "<b>four helper collections</b> (plate text, car look-alikes, a synthetic car-matching set and sharp plates for the picture enhancer). "
          "Almost everything comes from <b>public sources with open licences</b>, because no large labelled collection of Zamboanga traffic exists yet. "
          "That is the most important fact on this page: the models have learned what helmets, plates and windshields <i>look like</i>, "
          "but they have not yet been taught what <i>our</i> roads look like. The harvest loop (page 3) is how that gap is closed.</p>")

    groups = [(MODEL_LABEL[k] + " set", [sizes[k].get("train", 0), sizes[k].get("val", 0), sizes[k].get("test", 0)]) for k in MODEL_LABEL]
    p.add(figure(hbar(groups, ["train", "validation", "test"], w=760, label_w=190,
                      aria="Number of pictures in the train, validation and test parts of the four detection datasets"),
                 "<b>Pictures per dataset.</b> Most pictures are for learning (train). The validation part is used while training to choose the best moment to stop; "
                 "the test part is kept sealed for the final score. Exact counts of every class are in each dataset's own section below."))

    share_groups = [(MODEL_LABEL[k] + " set", [shares[k][2]]) for k in MODEL_LABEL]
    p.add(figure(hbar(share_groups, ["Philippine share"], w=760, label_w=190, vmax=100, fmt=lambda v: f"{int(v)}%",
                      aria="Share of Philippine pictures in each detection dataset, in percent"),
                 "<b>How much of each dataset is Philippine.</b> The vehicle set counts only pictures known to be Philippine (a further 80% comes from a source that mixes "
                 "Philippine and generic photos). The plate set has no Philippine pictures at all. No dataset contains Zamboanga CCTV yet."))

    # contribution map
    rows = []
    cols = ["Vehicle detector", "Helmet model", "Plate model", "Cabin model", "Plate reader ([[OCR]])", "Car matcher ([[ReID]])", "Picture enhancer"]
    def cell(v):
        return {"T": "<td class='y'>trains</td>", "S": "<td class='m'>scores</td>", "P": "<td class='m'>pre-trains</td>", "-": "<td class='o'>&ndash;</td>"}[v]
    matrix = [
        ("primary_anchor", "T-----" + "-"),
        ("helmet_specialist", "-T" + "-" * 5),
        ("plate_specialist", "--T" + "-" * 4),
        ("cabin_specialist", "---T" + "-" * 3),
        ("plate_ocr", "-" * 4 + "S--"),
        ("reid (own cars)", "-" * 5 + "T-"),
        ("reid_public", "-" * 5 + "P-"),
        ("sr_plates", "-" * 6 + "T"),
    ]
    body = "".join(f"<tr><td><b>{esc(n)}</b></td>" + "".join(cell(v) for v in flags) + "</tr>" for n, flags in matrix)
    head = "".join(f"<th>{c}</th>" for c in cols)
    p.add('<div class="tbl"><table class="heat dense"><thead><tr><th>Dataset</th>' + head + "</tr></thead><tbody>" + body + "</tbody></table></div>")
    p.add("<p class='note'>Read across: the dataset in the first column <b>trains</b> (or only <b>scores</b>, or <b>pre-trains</b>) the model in the column. "
          "Plate text is only used for scoring because the text-reading trainer cannot run as installed (page 3).</p>")
    p.add(callout("warn", "Honest reading of this page",
                  "<p>Every score in this project so far was measured on the <b>validation</b> part of these public datasets, not on Zamboanga footage. "
                  "The scores show that the models learned their pictures; they do not yet show accuracy on our roads. Page 3 explains how that is being closed, "
                  "and page 4 states the status of each violation.</p>"))
    p.end()

    # ── 1-4. the four detection datasets ──────────────────────────────────────
    yolo_section(
        p, "primary_anchor", "Vehicle and rider set (primary_anchor)", "ds-vehicle",
        "<p>Wide road pictures with a box around every motorcycle, car, bus, truck, tricycle and <b>person</b>. This is the set for the <b>first-stage detector</b>: the model that "
        "looks at every frame and finds the vehicles and the people on them. Pictures are 640 pixels on the longest side, the size this detector runs at. "
        "Today the system uses a stock [[COCO]] detector, which does not know tricycles or jeepneys. This set is how a Philippine detector would be fine-tuned.</p>",
        "<p>Every violation starts here: no vehicle box, no track, no violation. The <code>person</code> class is what makes <b>overloading</b>, <b>pickup passengers</b>, "
        "<b>riding outside</b> and the helmet crop possible, because riders are people standing on a motorcycle box. The <code>tricycle</code> class and jeepneys (as <code>bus</code>) "
        "are what the stock COCO model lacks, so this set is the path to detecting Philippine road users properly. A 6-class training run on it reached epoch 23 of 30 "
        "(page 2) and was not deployed.</p>",
        ["The tricycle class is thin in validation and test, so its score is unreliable until our own footage is added (harvest, Vehicles tile).",
         "Jeepneys share the class <code>bus</code>: the system cannot tell a jeepney from a bus."])
    dl = DATASETS / "_downloads" / "ph_vehicle_classification" / "data.yaml"
    state = "downloaded and staged; it joins this set after <code>curate --apply</code> and <code>report</code>" if dl.exists() else "not downloaded yet"
    p.add(f"<p><b>Waiting to join:</b> <code>ph_vehicle_classification</code> (about 6,854 pictures, 7 classes, Philippine, CC BY 4.0). Status when this page was built: {state}.</p>")

    yolo_section(
        p, "helmet_specialist", "Helmet set (helmet_specialist)", "ds-helmet",
        "<p>Pictures of motorcycles <b>together with their riders</b>. The model is not asked to find a helmet; it is asked to look at a <b>whole rider</b> (body and head) "
        "and say <i>with</i> or <i>without</i> a helmet. This is on purpose: boxing only the helmet misses a helmet carried on the lap, which is not a helmet worn.</p>",
        "<p>This set teaches the <b>no-helmet</b> violation. At run time the pipeline crops the motorcycle <i>plus</i> its riders (so heads are never cut off) and the model "
        "judges each rider; the ticket needs a [[vote]] over several looks. Training crops were cut the same way, so what the model sees in training matches what it sees in the system.</p>",
        ["Many pictures are close-ups or stock photos; CCTV-style views from a fixed camera are the minority. This is why the harvest loop matters for this model."])

    yolo_section(
        p, "plate_specialist", "Licence plate set (plate_specialist)", "ds-plate",
        "<p>Pictures of vehicles with a <b>tight box around the licence plate</b>. The box must be tight, because the text reader ([[EasyOCR]]) reads whatever is inside the crop, "
        "and a loose crop adds noise. One class only: <code>license_plate</code>.</p>",
        "<p>This set teaches the <b>plate finder</b>. It feeds two things: the <b>plate text</b> on every ticket (find the plate, crop it, read it) and the <b>no-plate</b> violation "
        "(no plate found in any fair look). It is the weakest dataset for our purpose: none of its pictures is Philippine, and the largest part is grey Vietnamese barrier-camera "
        "footage. The plate model trained on it scores clearly below its target (page 2), and the plate model is the first one that should be retrained on our own harvested pictures.</p>",
        ["The plate set contains no Philippine plates. Real read rates on Zamboanga footage have to be measured (benchmark, page 3)."])

    yolo_section(
        p, "cabin_specialist", "Cabin set (cabin_specialist)", "ds-cabin",
        "<p>Pictures of a vehicle seen from the front through the windshield, plus motorcycle crops for mirrors. Five classes cover four checks: is the window clear or tinted, "
        "is a seatbelt on, is a phone in hand, and how many side mirrors does a motorcycle have.</p>",
        "<p>This one model supports three violations: <b>no seatbelt</b>, <b>phone use</b> (distracted driving) and <b>missing side mirror</b>. The <code>tinted_window</code> class acts as a "
        "[[safety gate]]: if the windshield is tinted, nothing inside can be judged, so no seatbelt or phone ticket is made. The side-mirror class comes from one Philippine street camera "
        "and was found after the deployed cabin model was trained, so the deployed model has not learned mirrors yet.</p>",
        ["Validation and test contain no tinted_window and no side_mirror boxes, so those two classes have never been scored.",
         "The cabin model deployed today was trained on 2026-10-13, before the mirror data was merged (2026-10-25)."])

    # ── 5. helper collections ─────────────────────────────────────────────────
    ocr = card_ocr()
    p.h2("ds-ocr", "Plate text set (plate_ocr)", kicker="Helper collection &middot; scores the plate reader")
    p.add("<p>Cropped plate pictures with their <b>text</b> written next to them (one line, <code>0 ABC1234</code>). It is not a detection set; it answers a different question: "
          "<i>how well can we read a plate once we have found it?</i></p>")
    p.add(kv([("Pictures", ocr["split_text"]), ("Folder", ref("training_lab/datasets/plate_ocr/DATASET_CARD.md", line=1, label="datasets/plate_ocr/"))]))
    p.add(table(["Source", "Pictures", "Licence", "Country", "Trust"], ocr["rows"], "dense"))
    p.add("<p><b>Contribution.</b> The Turkish crops give plates with known text, so the reader can be scored (character and whole-plate error, called [[CER]] and [[WER]]). "
          "The 42 'Pop Quiz' corrections are the most valuable: they are real Zamboanga plates whose text a person typed in the review screen (<i>Send plate</i>). "
          "The [[EasyOCR]] package has no trainer, so these crops currently <b>score</b> the reader rather than train it.</p>")
    p.add(callout("warn", "Limit", "<p>No Philippine plate text exists in the set except the Pop Quiz corrections. The most useful next data is a plate-text collection with motorcycle plates "
                  "(request-only academic sets are listed under 'Waiting' below) and our own reviewed plates.</p>"))
    p.end()

    reid_dirs = list((DATASETS / "reid" / "images").glob("*/*")) if (DATASETS / "reid" / "images").exists() else []
    reid_pics = count_files(DATASETS / "reid" / "images")
    pub_pics = count_files(DATASETS / "reid_public" / "images")
    pub_ids = len(list((DATASETS / "reid_public" / "images" / "simveri").glob("*"))) if (DATASETS / "reid_public" / "images" / "simveri").exists() else 0
    p.h2("ds-reid", "Car look-alike sets (reid and reid_public)", kicker="Helper collection &middot; trains the car matcher")
    p.add("<p>The tracker must decide whether a car that reappears after being hidden is the <b>same car</b>. It does this with a [[fingerprint]] made by a small network ([[ReID]]). "
          "To improve that network we need <b>folders of photos where each folder is one physical car</b>.</p>")
    p.add(table(["Collection", "What it is", "Size now", "Licence / origin"], [
        ["<b>reid</b> (ours)", "Photos of real Zamboanga cars from our own clips. Each folder is one car. Made by the reviewers' answers: <i>same car</i>, <i>different car</i>, <i>rest are fine</i> (Forensic review and the harvest 'Same car?' tile). Ignored by git.",
         f"{num(len(reid_dirs))} car folders, {num(reid_pics)} photos", "Own data (real CCTV footage)"],
        ["<b>reid_public</b> (SimVeRi)", "A public set of <b>simulated</b> cars (made in the CARLA and SUMO simulators), six pictures per car from different cameras, fetched as a sample without downloading the 2.3 GB zip. "
         "Kept in its own folder so a new matcher is still scored on <i>real</i> cars.", f"{num(pub_ids)} cars, {num(pub_pics)} photos", "CC BY 4.0 &middot; Zenodo record 21980379 &middot; trust A"],
    ], "dense"))
    p.add("<p><b>Contribution.</b> A test on 67 ticketed cars from two real clips showed that fine-tuning on our own car folders raised the 'find this car again' rate on <i>new</i> cars from the same cameras "
          "from 76.7% to 85.3% (three of three random splits better), but gave no gain on a different road. So this data helps on the cameras it came from. "
          "Details and the exact method: <code>training_lab/experiments/reid/RESULTS.md</code>.</p>")
    p.end()

    sr_pics = count_files(DATASETS / "sr_plates" / "clean")
    p.h2("ds-sr", "Sharp plate set (sr_plates)", kicker="Helper collection &middot; teaches the picture enhancer")
    p.add("<p>Clear plate crops, cut from the labelled pictures of the plate set. A [[super-resolution]] model learns to rebuild a clear plate from a blurry one, so it needs <i>clear</i> plates to learn from; "
          "the trainer makes the blurry copies itself. A crop is kept only if it is big enough, plate-shaped, sharp and not a repeat, and it inherits the split of its picture so the enhancer "
          "is never scored on a plate it saw in training.</p>")
    p.add(kv([("Pictures", f"{num(sr_pics)} crops"), ("Made by", ref("training_lab/data_tools/sr.py", symbol="@doc", label="data_tools/sr.py")),
              ("Build command", "<code>python data.py sr-build</code>")]))
    p.add("<p><b>Contribution.</b> Plates on CCTV are small and blurry, and the reader fails on blur. The enhancer is the experiment that tries to help; it is listed in the Training Studio but "
          "its training is unproven (the custom [[GAN]] was never shown to beat the ready-made [[Real-ESRGAN]], page 2).</p>")
    p.end()

    # ── 6. local footage ──────────────────────────────────────────────────────
    hc = harvest_counts()
    by_model: dict[str, int] = {}
    for (m, s), n in hc.items():
        by_model[m] = by_model.get(m, 0) + n
    p.h2("ds-local", "Our own footage and the harvest inbox", kicker="The data that matters most")
    p.add("<p>Public data teaches what things look like. Only <b>our own footage</b> teaches what <i>our cameras</i> see. The project has one confirmed local clip so far "
          "(a rainy, wide-angle, 4K crossing in Zamboanga, analysis id <code>9db131ee</code>). The [[harvest]] tool turns finished analyses into training material: "
          "it copies pictures the system was unsure about, shows them one at a time, a person checks or draws the boxes, and the accepted pictures join the dataset.</p>")
    if by_model:
        p.add(table(["Model", "Pictures in the inbox (all states)"], [[esc(k), num(v)] for k, v in sorted(by_model.items())], "dense"))
    p.add(steps(["<b>Analyze</b> a clip in the Forensic Analyzer (turn on <i>Keep the uploaded video</i> so frames can be sampled later).",
                 "<b>Collect</b>: pictures are copied into <code>training_lab/harvest_inbox/</code> with the model's suggested boxes.",
                 "<b>Check</b>: one picture at a time; Enter = boxes are right, drag = draw one, N = nothing here, S = not sure.",
                 "<b>Accept</b>: finished pictures are added to the model's dataset, only while that model is not training.",
                 "<b>Train and compare</b> on the same protected benchmark clips."]))
    p.add(callout("ok", "Safety rules built into the harvest tool",
                  "<ul><li>It never writes inside <code>hulikamote_backend/</code> and never uploads anything.</li>"
                  "<li>A picture is added only after a person has checked it.</li>"
                  "<li>Benchmark clips are protected and never harvested.</li>"
                  "<li>All pictures of one car stay on the same side of the train / validation split, and the test split is never written.</li></ul>"))
    p.end()

    # ── 7. waiting / not used ─────────────────────────────────────────────────
    man = manifest()
    manual = man.get("_manual", {})
    p.h2("ds-waiting", "Held back, waiting, or deliberately not used", kicker="So nothing is hidden")
    p.add("<p>Choices about data are part of the method. These sources were looked at and <b>not</b> put into training, with the reason.</p>")
    rows = []
    status = {
        "mapua_helmet": ("warn", "Held back"), "ph_vehicle_classification": ("info", "Staged"), "rodosol_alpr": ("info", "Request needed"),
        "ufpr_alpr": ("info", "Request needed"), "veri_776": ("info", "Request needed"), "ufpr_sr_plates": ("info", "Check licence"),
        "seatbelt_phone_kaggle": ("info", "Account needed"), "side_mirror": ("warn", "In use, weak"), "window_tint_seg": ("info", "To check"),
        "ph_plate_t1lqw": ("info", "To check"), "ridesafe_400": ("off", "Not released"), "not_used": ("bad", "Excluded"),
    }
    for k, v in manual.items():
        kind, label = status.get(k, ("info", "Note"))
        rows.append([f"<b>{esc(k)}</b>", chip(kind, label), esc(v)])
    p.add(table(["Source", "Status", "Why / what is needed"], rows, "dense", ["16%", "12%", "72%"]))
    p.add("<p class='note'>Also downloaded but not merged: <code>augmented_plates</code> (8,823 more pictures of the same Vietnamese barrier camera, which would drown the varied plate sets).</p>")
    p.end()

    # ── 8. licences ───────────────────────────────────────────────────────────
    p.h2("ds-licences", "Licences and credits", kicker="Required by the licences")
    p.add("<p>Most sources are [[CC BY 4.0]], which allows use and changes <b>if the author is credited</b>. One source is under the [[MIT licence]]. "
          "One (Indonesia plates) names no licence in its original project, so it is treated as research use only. Open Images pictures are credited to their Flickr authors. "
          "The full per-source licence is in each table above and in <code>configs/datasets_manifest.yaml</code>.</p>")
    cites = []
    for model, entries in man.items():
        if model.startswith("_") or not isinstance(entries, list):
            continue
        for e in entries:
            if e.get("citation"):
                cites.append([f"<b>{esc(e['id'])}</b>", esc(e["citation"]), esc(e.get("license", "")), esc(model)])
    p.add(table(["Source", "Citation", "Licence", "Used for"], cites, "dense"))
    p.add(callout("warn", "For the thesis text", "<p>The thesis must credit the CC BY sources (author and link, listed in the tables above) and must state that the plate, helmet and cabin "
                  "data are not Zamboanga footage. The wording is prepared in <code>docs/THESIS_REVISIONS.md</code>, block I.</p>"))
    p.end()

    # ── 9. rules ──────────────────────────────────────────────────────────────
    p.h2("ds-rules", "Rules that keep the numbers honest", kicker="Method")
    p.add(table(["Rule", "Why it matters"], [
        ["One standard layout: <code>images/{train,val,test}</code> + <code>labels/{train,val,test}</code> + <code>data.yaml</code>", "Every trainer and checker reads the same shape, so nothing depends on a source's own folder style."],
        ["A source's own train / valid / test split is kept (valid becomes val)", "Near-identical augmented copies never leak into the test part."],
        ["<code>force_split: train</code> for one fixed camera filmed over time", "Neighbouring video frames in validation or test would make the score look better than it is."],
        ["The same photo in two splits: the <b>train</b> copy is quarantined", "Test and validation stay as they are, so scores stay comparable. Nothing is deleted: files are moved to <code>datasets/_quarantine/</code>."],
        ["Near-duplicates are found with a [[perceptual hash]]", "Catches the same scene resized, re-encoded or slightly rotated. Unrelated pictures sit far apart."],
        ["Files named <code>harvest__*</code> (our reviewed CCTV pictures) are never moved, fixed or re-saved", "Our own checked work is protected from the automatic cleaner."],
        ["Country and 'Philippine' flags were checked <b>by eye</b> on picture sheets, not from project names", "'ph_plates' is Vietnamese and 'colorum_plates' is Indian / UK / US. A name is not evidence."],
    ], "dense", ["46%", "54%"]))
    p.add(code("training_lab/datasets/helmet_specialist/data.yaml", lines=whole("training_lab/datasets/helmet_specialist/data.yaml"), lang="yaml",
               title="What a dataset's data.yaml says (the helmet set)"))
    p.add(figure(_split_diagram(), "<b>How one source is split.</b> The source's own validation and test parts are kept; a photo found in both train and validation is removed from train."))
    p.end()
    return p


def card_ocr() -> dict:
    text = (DATASETS / "plate_ocr" / "DATASET_CARD.md").read_text(encoding="utf-8")
    from lib import md_tables
    tabs = md_tables(text)
    splits = [r for r in tabs[0][1]]
    split_text = " &middot; ".join(f"{num(r['pictures'])} {r['split']}" for r in splits)
    rows = []
    for r in tabs[1][1]:
        rows.append([f"<b>{esc(r['source'])}</b>", r["pictures"], esc(r["licence"]), esc(r["country"]), esc(r["trust"])])
    return {"split_text": split_text, "rows": rows}


def _split_diagram() -> str:
    parts = [
        box(10, 20, 150, 58, ["Source dataset", "its own train / valid / test"], "c1"),
        box(215, 20, 150, 58, ["Merge", "names get '<id>__' prefix"], "c3"),
        box(420, 20, 150, 58, ["Check and clean", "broken, tiny, duplicate"], "c4"),
        box(625, 20, 125, 58, ["Standard layout", "images / labels"], "c7"),
        arrow(160, 49, 215, 49), arrow(365, 49, 420, 49), arrow(570, 49, 625, 49),
        box(420, 105, 150, 44, ["Quarantine folder", "nothing is deleted"], "c8 dash"),
        arrow(495, 78, 495, 105, "", True),
    ]
    return svg(760, 165, "".join(parts), "How a source dataset flows into the standard layout")
