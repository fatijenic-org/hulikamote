"""Page 4 - Violations. The 20 cards come from violation_cards.py; code is quoted from the real modules."""
from __future__ import annotations

from lib import (Page, arrow, box, callout, chip, cmd, code, esc, figure, ref, span, steps, svg, table, tests_info)
from sketches import sketch
from violation_cards import cards, ENG, V

FAMILY = {
    "zone": ("Zone rule", "judged from the vehicle's path inside zones the operator draws"),
    "frame": ("Frame check", "judged from what is on screen right now"),
    "model": ("Model check", "judged from a specialist model's look at the vehicle"),
}
STATUS_CHIP = {
    "thesis": ("info", "In the thesis list"),
    "extra": ("off", "Extra: not in the thesis list"),
    "new": ("info", "Added after the consultation"),
    "experimental": ("warn", "Experimental"),
}
DRAW = {
    "counterflow": "zone + arrow (nothing: whole picture)", "illegal_parking": "zone + time limit", "restricted_lane": "zone + allowed types",
    "pedestrian_lane": "zone + time limit", "illegal_turn": "zone + arrow", "illegal_u_turn": "zone", "swerving": "zone (or nothing: whole picture)",
    "crossing_solid_line": "zone + line", "blocking_intersection": "zone + time limit", "red_light": "zone + stop line + light",
    "disregarding_signs": "one zone per sign", "signal_light": "zone", "overloading": "max riders", "pickup_passengers": "nothing",
    "riding_outside_vehicle": "nothing", "no_plate": "nothing", "no_helmet": "nothing", "no_seatbelt": "nothing", "distracted_driving": "nothing",
    "missing_side_mirror": "nothing",
}


def _cascade() -> str:
    parts = [
        box(0, 10, 112, 64, ["Camera or clip", "frame by frame"], "c1"),
        box(137, 10, 130, 64, ["Vehicle detector", "boxes + classes", "(every frame)"], "c3"),
        box(292, 10, 120, 64, ["Tracker", "one ID per", "vehicle"], "c3"),
        box(437, 10, 130, 64, ["Ledger", "path, speed,", "votes, class"], "c4"),
        box(592, 10, 168, 64, ["Evidence + ticket", "photos with the", "'why' boxes"], "c7"),
        box(60, 150, 190, 64, ["Zone rules (12)", "need zones drawn", "path, speed, direction"], "c2"),
        box(285, 150, 190, 64, ["Frame checks (3)", "people on a vehicle", "counted now, by vote"], "c2"),
        box(510, 150, 250, 64, ["Model checks (5)", "specialist looks every 5th frame", "helmet, plate, cabin, by vote"], "c2"),
        arrow(112, 42, 137, 42), arrow(267, 42, 292, 42), arrow(412, 42, 437, 42), arrow(567, 42, 592, 42),
        arrow(502, 74, 155, 150), arrow(502, 74, 380, 150), arrow(502, 74, 635, 150),
        '<text x="676" y="96" class="sk" text-anchor="middle">a flag from any of the</text><text x="676" y="110" class="sk" text-anchor="middle">three kinds of check</text>',
    ]
    return svg(760, 235, "".join(parts), "How a frame becomes a ticket: detector, tracker, ledger, then three kinds of violation checks, then evidence")


# ── Scope of the study (the table for the panel). Edit here when the scope changes; see docs/final_documents/. ──────────────
LAW = ("ok", "Law text read")
ORDER = ("info", "Order read (copy)")
UNSURE = ("warn", "Not opened")
NONE = ("warn", "None found")
BUILT = ("ok", "Built")
NOT_BUILT = ("bad", "Not built yet")
EXPERIMENTAL = ("warn", "Built, experimental")
# (key, name, applies to, kind, state, legal basis, source strength)
MANDATORY = [
    ("counterflow", "Counterflow", "All vehicles", "Zone rule", BUILT, "RA 4136 &sect;37", LAW),
    ("illegal_parking", "Illegal parking", "All vehicles", "Zone rule", BUILT, "RA 4136 &sect;46", LAW),
    ("illegal_turn", "Illegal turn", "All vehicles", "Zone rule", BUILT, "RA 4136 &sect;45", LAW),
    ("disregarding_signs", "Disregarding traffic signs (stop sign)", "All vehicles", "Zone rule", BUILT, "JAO 2014-01 (RA 4136 has no stop-sign rule)", UNSURE),
    ("no_plate", "No visible plate number", "All vehicles", "Model check", BUILT, "RA 4136 &sect;18; motorcycles: RA 11235 &sect;5 as amended by RA 12209", LAW),
    ("no_helmet", "No helmet", "Motorcycle only", "Model check", BUILT, "RA 10054 &sect;3; LTO AO AHS-2008-015 &sect;VII", LAW),
    ("missing_side_mirror", "Missing side mirror", "Motorcycle only", "Model check", BUILT, "LTO AO AHS-2008-015 &sect;VIII", ORDER),
    ("overloading", "Overloading", "Motorcycle only", "Frame check", BUILT, "RA 4136 &sect;32; LTO AO AHS-2008-015 &sect;VI", LAW),
    ("no_seatbelt", "No seatbelt", "Car only", "Model check", BUILT, "RA 8750 &sect;4", LAW),
    ("kuliglig_passenger", "Passenger in a kuliglig", "Kuliglig only", "Frame check", NOT_BUILT, "No national rule found; nearest: RA 4136 &sect;32(b), &sect;51", NONE),
    ("pickup_passengers", "Passengers in a pickup bed", "Pickup, truck", "Frame check", BUILT, "RA 4136 &sect;32(b), &sect;51", LAW),
    ("riding_outside_vehicle", "Riding outside the vehicle", "All except motorcycle", "Frame check", BUILT, "RA 4136 &sect;32(b), (c), &sect;51", LAW),
    ("signal_light", "Signal light", "All vehicles", "Zone rule", EXPERIMENTAL, "RA 4136 &sect;44", LAW),
    ("red_light", "Red light running", "All vehicles", "Zone rule", BUILT, "JAO 2014-01 (RA 4136 has no signal rule)", UNSURE),
    ("swerving", "Swerving", "All vehicles", "Zone rule", BUILT, "RA 4136 &sect;48", LAW),
    ("pedestrian_lane", "Pedestrian lane obstruction", "All vehicles", "Zone rule", BUILT, "RA 4136 &sect;46(b)", LAW),
    ("illegal_u_turn", "Illegal U-turn", "All vehicles", "Zone rule", BUILT, "No U-turn section in RA 4136; charged by sign", NONE),
    ("crossing_solid_line", "Crossing a solid line", "All vehicles", "Zone rule", BUILT, "RA 4136 &sect;41(a)", LAW),
    ("restricted_lane", "Restricted lane", "All vehicles", "Zone rule", BUILT, "No national source; local ordinance", NONE),
    ("overtaking_on_right", "Overtaking on the right", "All vehicles", "Zone rule", NOT_BUILT, "RA 4136 &sect;39 (pass on the left; right allowed on multi-lane one-way roads)", LAW),
]
EXTRAS = [
    ("blocking_intersection", "Blocking the intersection", "All vehicles", "Zone rule", "RA 4136 &sect;54, &sect;46(a)"),
    ("sidewalk_driving", "Driving on the sidewalk", "All vehicles", "Zone rule", "RA 4136 &sect;52"),
    ("illegal_loading", "Illegal loading / unloading", "Bus, jeepney, tricycle, truck", "Zone rule", "RA 4136 &sect;54"),
    ("truck_ban", "Truck ban", "Truck", "Zone rule", "No national source; local ordinance"),
    ("tricycle_on_highway", "Tricycle on a national highway", "Tricycle", "Zone rule", "DILG MC 2020-036 and 2023-195"),
    ("double_parking", "Double parking", "All vehicles", "Zone rule", "RA 4136 &sect;46(g)"),
    ("distracted_driving", "Phone use while driving", "Car", "Model check", "RA 10913 &sect;4"),
]
CARD_KEYS = {"counterflow", "illegal_parking", "restricted_lane", "pedestrian_lane", "illegal_turn", "illegal_u_turn", "swerving", "crossing_solid_line",
             "blocking_intersection", "red_light", "disregarding_signs", "signal_light", "overloading", "pickup_passengers", "riding_outside_vehicle",
             "no_plate", "no_helmet", "no_seatbelt", "distracted_driving", "missing_side_mirror"}


def _name(key: str, name: str) -> str:
    return f"<a href='#v-{key}'><b>{name}</b></a>" if key in CARD_KEYS else f"<b>{name}</b>"


def _scope(p: Page) -> None:
    built = sum(1 for m in MANDATORY if m[4] is not NOT_BUILT)
    p.h2("scope", "Scope of the study", kicker="Start here", newpage=False)
    p.add(f"<p><b>{len(MANDATORY)} mandatory violations</b> ({built} built, {len(MANDATORY) - built} not built yet) and <b>{len(EXTRAS)} optional extras</b> (built, not promised). "
          "The vehicles covered are those common in Zamboanga City: motorcycle, car, tricycle, jeepney, bus, truck, pickup and kuliglig.</p>")
    rows = []
    for i, (key, name, who, kind, state, law, strength) in enumerate(MANDATORY, 1):
        rows.append([str(i), _name(key, name), who, kind, chip(*state), law, chip(*strength)])
    p.h3("scope-mandatory", "The 20 mandatory violations")
    p.add(table(["#", "Violation", "Applies to", "Kind", "In the system", "Legal basis", "Source check"], rows, "dense", ["3%", "20%", "12%", "9%", "11%", "32%", "13%"]))
    p.add("<p class='note'><b>Source check:</b> 'Law text read' = the section was read on lawphil.net. 'Order read (copy)' = read on a legal-text site, not on the LTO site. "
          "'Not opened' = the LTO page blocks the request, so the item number is still to be added. 'None found' = no national law names it; the nearest law and the local ordinance apply. "
          "The study tests detection, not the legal case.</p>")
    rows = [[_name(k, n), who, kind, chip(*BUILT), law, "Card below" if k in CARD_KEYS else "No card yet"] for k, n, who, kind, law in EXTRAS]
    p.h3("scope-extras", "The 7 optional extras")
    p.add(table(["Violation", "Applies to", "Kind", "In the system", "Legal basis", "Card"], rows, "dense", ["22%", "17%", "9%", "11%", "28%", "13%"]))
    p.h3("scope-camera", "Camera, light and data")
    p.add(table(["Topic", "In scope", "Out of scope"], [
        ["<b>Camera</b>", "Fixed camera, 3 to 8 m above the road, looking down 15 to 45 degrees; vehicles move toward or away from the camera", "Moving or hand-held camera; straight top-down view"],
        ["<b>Light and weather</b>", "Daylight; no strong backlight; no heavy rain; clean lens", "Night; heavy rain; strong backlight"],
        ["<b>Video</b>", "720p or higher; 15 fps or higher; vehicle at least 120 px wide (plate: 60 px); each vehicle visible 3 s or more (swerving: 6 s)", "Lower quality footage"],
        ["<b>Training and test data</b>", "Barangay CCTV first; if it is low quality or outside the camera limits: public datasets and our own recordings", "Game footage, simulator footage, MMDA footage"],
    ], "dense", ["16%", "56%", "28%"]))
    p.add(callout("warn", "Limits to say plainly",
                  "<ol><li><b>Two mandatory violations are not built yet:</b> kuliglig passenger and overtaking on the right.</li>"
                  "<li><b>Missing side mirror</b> is judged from the front or rear only: mirrors are small, arms hide them, and from the side one mirror is always hidden.</li>"
                  "<li><b>Disregarding signs</b> covers the stop sign only. The sign and the traffic light are drawn on the picture by the operator; the system never reads a sign from the image.</li>"
                  "<li><b>Vehicle classes:</b> the active detector has no tricycle or kuliglig class. It calls pickups 'truck' and jeepneys 'bus'.</li>"
                  "<li><b>No violation is scored on real footage yet.</b> Results will be reported on barangay or own footage.</li></ol>"))
    p.end()


def render_card(c: dict) -> str:
    info = tests_info(c["module"])
    fam_name, fam_desc = FAMILY[c["family"]]
    sk, st = STATUS_CHIP[c["status"]]
    models = table(["Model or part", "How it is used here"], [[f"<b>{a}</b>", b] for a, b in c["models_text"]], "dense", ["32%", "68%"])
    params = table(["What is measured", "Value", "Why"], [[a, b, d] for a, b, d in c["params"]], "dense", ["28%", "40%", "32%"]) if c["params"] else ""
    test_box = ""
    if info:
        sample = "".join(f"<li>{esc(s)}</li>" for s in info["sentences"][:4])
        test_box = (f"<div class='mini'><b>How it is tested</b><span class='note'>{info['tests']} automated tests touch this file; "
                    f"{info['coverage']}% of its lines are run by them (tests index, {esc(info['generated'])}).</span><ul>{sample}</ul></div>")
    code_html = "".join(f() for f in c["code"])
    return f"""
<article class="vcard" id="v-{c['key']}">
<header><h3>{c['name']}</h3><span class="vkey">{c['key']}</span>{chip('info', fam_name)}{chip(sk, st)}{chip(*c['state'])}</header>
<div class="vgrid"><div>
<h4>What it means</h4><p>{c['what']}</p>
<h4>Where it comes from in law</h4><p>{c['law']}</p>
<h4>How it is decided, step by step</h4>{steps(c['steps'])}
<h4>Models and parts involved</h4>{models}
<h4>How to set it up</h4>{steps(c['setup'])}<p class="note">Configuration: {c['config']}</p>
</div><div>
{sketch(c['sketch'])}
<div class="mini"><b>Camera view needed</b><span class="note">{c['view']}</span></div>
{test_box}
</div></div>
<h4>The numbers (the heuristic)</h4>{params}
<h4>Limits and honest notes</h4><ul>{''.join(f'<li>{x}</li>' for x in c['limits'])}</ul>
<h4>The code</h4><p class="note">{fam_name}: {fam_desc}. Every quote below is cut from the real file; the numbers are real line numbers, and the link opens that line in [[VS Code]].</p>
{code_html}
</article>"""


def build() -> Page:
    p = Page("4-violations.html", "4", "Violations",
             "The scope of the study (20 mandatory violations and 7 optional extras, in one table), then for the built violations: where each comes from in law, how it is decided step by step, "
             "which models help, how to set it up in the dashboard, and the exact code.")
    allc = cards()

    _scope(p)

    # ── overview ──────────────────────────────────────────────────────────────
    p.h2("overview", "How a violation is decided", kicker="How it works")
    p.add("<p>The system does not use one big model to say 'violation'. A violation is a <b>decision</b> built from three layers: <b>models</b> that find what is in the picture, "
          "<b>tracking</b> that follows each vehicle over time, and a small <b>rule</b> (a [[heuristic]]) that turns the picture and the path into a yes or no. "
          "Each of the 20 violations is its own small file in <code>hulikamote_backend/engine/violations/</code> with the same shape, so any one of them can be read, tested, switched off or replaced alone.</p>")
    p.add(figure(_cascade(), "<b>One frame, left to right.</b> The detector finds vehicles and people, the tracker gives each a steady ID, and the ledger keeps its history. "
                 "Then the three kinds of checks run. Whatever is flagged gets evidence photos and a ticket that a person reviews."))
    p.add(table(["Kind", "How many", "What it looks at", "Needs a drawing?", "Example"], [
        ["<b>Zone rules</b>", "12", "The vehicle's path and speed inside zones the operator draws.", "Yes (a zone, sometimes an arrow, a line or a time limit)", "counterflow, parking, red light"],
        ["<b>Frame checks</b>", "3", "How many people are on a vehicle <i>right now</i>.", "No", "overloading, pickup passengers"],
        ["<b>Model checks</b>", "5", "What a specialist model sees in a crop of the vehicle.", "No", "no helmet, no plate, no seatbelt"],
    ], "dense"))

    rows = []
    for i, c in enumerate(allc, 1):
        info = tests_info(c["module"])
        cov = f"{info['coverage']}% &middot; {info['tests']} tests" if info else "-"
        sk, st = STATUS_CHIP[c["status"]]
        rows.append([str(i), f"<a href='#v-{c['key']}'><b>{c['name']}</b></a>", FAMILY[c["family"]][0], DRAW[c["key"]], chip(sk, st), cov, chip(*c["state"])])
    p.add(table(["#", "Violation", "Kind", "What you set up", "Origin", "Tests (lines run &middot; count)", "State"], rows, "dense", ["3%", "22%", "9%", "19%", "14%", "13%", "20%"]))
    p.add(callout("warn", "The most important caveat of this page",
                  "<p><b>No violation has been scored on real footage yet.</b> Every rule has automated tests on scripted paths and boxes, and the benchmark tool to score them on real clips is built, "
                  "but its clip list is still empty. 'Rule + tests' means the logic does what it is written to do; it does not yet mean it is accurate on Zamboanga roads. "
                  "The five rules added after the panel consultation were never seen on real footage at all.</p>"))

    # model matrix
    head = "".join(f"<th>{h}</th>" for h in ["Vehicle detector", "Tracker", "Helmet model", "Plate model", "Cabin model"])
    body = ""
    for c in allc:
        cells = "".join("<td class='y'>uses</td>" if flag else "<td class='o'>&ndash;</td>" for flag in c["models"])
        people = " + people" if c["key"] in ("overloading", "pickup_passengers", "riding_outside_vehicle") else ""
        body += f"<tr><td><b>{c['name']}</b>{people}</td>{cells}</tr>"
    p.add("<h3 id='matrix'>Which model helps which violation</h3>")
    p.toc.append(("matrix", "Which model helps which violation", 3))
    p.add(f'<div class="tbl"><table class="heat dense"><thead><tr><th>Violation</th>{head}</tr></thead><tbody>{body}</tbody></table></div>')
    p.add("<p class='note'>Zone rules need only the vehicle detector and the tracker; the rest of the work is geometry. Overloading, pickup passengers and riding outside also use the detector's "
          "<b>person</b> class. Only five violations depend on a specialist model, which is why the system can stay light: a specialist is loaded only when a violation that needs it is switched on.</p>")
    p.end()

    # ── setup ─────────────────────────────────────────────────────────────────
    p.h2("setup", "How to set up an analysis", kicker="Using the dashboard")
    p.add("<p>Violations are switched on and set up in the dashboard's <b>Forensic Analyzer</b> wizard. The same settings are saved in <code>camera_config.json</code>, which the live monitor reads too.</p>")
    p.add(steps([
        "<b>Video.</b> Choose the clip. Turn on <i>Keep the uploaded video</i> if you want to harvest pictures or benchmark it later.",
        "<b>Violations.</b> Tick the violations to look for. Each shows what it needs: <i>Draw a zone</i>, <i>Set a rider limit</i> or <i>Model not trained yet</i>.",
        "<b>Rules &amp; zones.</b> For each violation, draw what it asks for on the video's first frame (the hint is written in the editor). Draw one zone per place; some violations also take an arrow, a stop line, a light box, a time limit or a list of allowed vehicle types.",
        "<b>Settings.</b> Choose the tracker (<b>DeepSORT</b>, not the ByteTrack default), the plate model, plate format (<code>ph_standard</code>), reader, enhancement, evidence photo gap, and automatic flow detection.",
        "<b>Run.</b> Start the analysis. The result is a list of tickets with evidence photos for a person to review; <i>Use for Live Monitor</i> sends the same setup to the live view.",
    ]))
    p.add(table(["Setting (in <code>camera_config.json</code>)", "Meaning", "Value we use"], [
        ["<code>active_violations</code>", "Which violations are switched on. A violation that is off does not run, and its model is not loaded.", "your choice"],
        ["<code>regions_of_interest.&lt;name&gt;_zones</code>", "The zones, arrows, lines and limits for each zone violation (names are in each card below).", "drawn in the wizard"],
        ["<code>video_native_width</code> / <code>video_native_height</code>", "The picture size the zones were drawn at, so they can be scaled to the frame being processed.", "set by the wizard"],
        ["<code>tracker</code>", "<code>deepsort</code> or <code>bytetrack</code>.", "<b>deepsort</b>"],
        ["<code>flow_mode</code> / <code>flow_prescan_seconds</code>", "<code>zones</code> (drawn) or <code>auto</code> (learn the flow); how many seconds of a recorded clip to scan first.", "auto, 60"],
        ["<code>plate_model</code>, <code>plate_method</code>", "Which plate model file; <code>smart</code> (detector then reader) or <code>direct_ocr</code> (read the bumper strip).", "active plate model, smart"],
        ["<code>plate_format</code>, <code>ocr_engine</code>, <code>enhancement</code>", "Plate text rules, the reader, and how a small plate is enlarged first.", "ph_standard, easyocr, lanczos"],
        ["<code>evidence_gap</code>", "Save one evidence photo every N frames of a flagged vehicle (1 to 5).", "5"],
        ["<code>max_riders</code>, <code>bed_passengers_allowed</code>", "Limits for overloading (default 2) and for people tolerated in a pickup bed (default 0).", "2, 0"],
    ], "dense", ["31%", "50%", "19%"]))
    p.add(callout("info", "The camera must be right for the rules to be right",
                  "<ul><li><b>Fixed</b> camera: no panning, zooming or hand-held footage (zones and the learned flow assume one view).</li>"
                  "<li>Mounted <b>3 to 8 m</b> above the road, looking down 15 to 45 degrees, not straight down.</li>"
                  "<li>Vehicles at least 120 px wide for plate, helmet and seatbelt checks (the plate check ignores vehicles under 60 px).</li>"
                  "<li>At least 720p and 15 fps (25 to 30 fps is better); daylight for the first test set.</li>"
                  "<li>Each vehicle visible for 3 seconds or more (swerving needs 6).</li>"
                  "<li>No heavy rain, lens dirt or strong backlight in the main test set.</li></ul>"
                  "<p>These are working values for this study and are tightened or relaxed by the benchmark results. Each card below says which view its violation needs.</p>"))
    p.add(callout("ok", "Live demonstration",
                  "<p>The same pipeline runs on a live feed. The camera input accepts a recorded file, a webcam or an [[RTSP]] address, the protocol IP cameras and [[CCTV]] recorders use. "
                  "For the defense, a second laptop or a phone publishes the test footage as an RTSP stream and the system reads it exactly as it would a real camera; when a CCTV recorder exists, only the address changes. "
                  "All accuracy numbers are measured on recorded footage.</p>"))
    p.end()

    # ── shared building blocks ────────────────────────────────────────────────
    p.h2("shared", "The shared building blocks", kicker="Read once, understand all 20")
    p.add("<p>Every violation uses the same few pieces. They are shown here once, with the code, so each card below can stay short.</p>")
    p.h3("sh-ledger", "1. The ledger: a notebook for each vehicle")
    p.add("<p>For each tracked vehicle the [[ledger]] keeps its recent positions, its class, its votes and its suspicions. Every zone test uses the vehicle's <b>[[ground point]]</b>, the bottom-centre of its box, "
          "because that is where the tyres touch the road, and the zones are drawn on the road.</p>")
    p.add(code(ENG + "ledger.py", "TrackLedger.update_position", walk=[
        ("cy = y + h", "The ground point: the bottom of the box, not its middle."),
        ("self.history.append((t, cx, cy, bbox))", "A short history (30 updates) with the box, for speed and 'moves with' tests."),
        ("self.path.append((t, cx, cy, w))", "A longer path (300 updates, about 10 seconds) with the box width, for turns, swerving and lines."),
    ]))
    p.h3("sh-pipeline", "2. The pipeline calls the violation modules; it contains no violation logic")
    p.add(code(ENG + "pipeline.py", "DecoupledPipeline.process_frame", walk=[
        ("yolo.infer(frame)", "Find vehicles and people, and track them."),
        ("self.ledger_manager.update(detections", "Update each vehicle's ledger (and re-join broken tracks)."),
        ("self.flow.observe_frame(", "When a rule needs the traffic flow (counterflow, parking, loading) and has no zone: let the traffic teach the flow field."),
        ("self._run_specialists(frame", "Helmet, plate and cabin models look at the vehicles they apply to."),
        ("self._judge(frame", "Zone rules and frame checks run."),
        ("self._capture_evidence_frame(frame, det, tid, detections)", "Anything flagged gets an evidence photo with the 'why' boxes."),
    ]))
    p.add(code(ENG + "pipeline.py", "DecoupledPipeline._run_specialists", walk=[
        ("(frame_count + i) % SPECIALIST_INTERVAL", "A specialist runs on every 5th look, spread across vehicles so there is never one big pause."),
        ("job.wanted(active, det)", "A job (helmet, plate, cabin) only looks at the vehicles it applies to."),
        ("violation.judge(self, det, look)", "One look is shared by every violation that uses that model."),
    ]))
    p.add(code(ENG + "pipeline.py", "DecoupledPipeline._judge", walk=[
        ("violation.prepare(self, frame", "Violations that read the picture (light colour, indicators) do it first."),
        ("violation.evaluate(self.ledger_manager", "Every zone rule judges every tracked vehicle (people are skipped)."),
        ("violation.check_frame(self, detections)", "Then the frame checks look at what is on screen."),
    ]))
    p.h3("sh-shape", "3. Every violation has the same shape")
    p.add(code(V + "base.py", "Violation", walk=[
        ("key: str = \"\"", "The violation's name, used in tickets and in the configuration."),
        ("zone_key: str | None", "For zone rules: the name of its list of zones in the configuration."),
        ("job: str | None", "For model checks: which specialist job it is judged from."),
        ("def parse_zone(", "How one zone from the configuration becomes what the rule reads."),
        ("def evaluate(", "Zone rules judge one tracked vehicle here."),
        ("def check_frame(", "Frame checks judge everything on screen here."),
        ("def judge(", "Model checks judge one vehicle from a specialist's look."),
        ("def decide_end(", "When the vehicle leaves: turn a pending suspicion into a violation, or drop it."),
    ]))
    p.add(code(V + "__init__.py", lines=span(V + "__init__.py", "ALL: list[Violation] = [", end_text="]"), title="The list of all 20", walk=[
        ("Counterflow(), IllegalParking()", "Zone rules (12): judged from the path inside drawn zones."),
        ("Overloading(), PickupPassengers()", "Frame checks (3)."),
        ("NoPlate(), NoHelmet()", "Model checks (5)."),
    ]))
    p.h3("sh-vote", "4. Votes and pending: why one wrong frame never makes a ticket")
    p.add("<p>A model can be wrong on a single frame. So single-frame checks (helmet, seatbelt, phone, mirror, overloading, passengers) use a <b>[[vote]]</b> over the last 10 looks, and the no-plate suspicion is "
          "<b>[[pending]]</b> until the vehicle leaves. If the suspicion is cleared, its evidence photos are deleted.</p>")
    p.add(code(ENG + "ledger.py", "ActiveLedgerManager.decide_end_of_track", walk=[
        ("for violation in ALL_VIOLATIONS", "Every violation may turn a pending suspicion into a violation now."),
        ("ledger.pending.clear()", "Whatever is still pending is final: decided or dropped."),
        ("if not ledger.violations and ledger.evidence_paths", "No violation in the end: delete the photos taken only because of a suspicion."),
    ]))
    p.end()

    # ── cards ─────────────────────────────────────────────────────────────────
    groups = [("zone", "cards-zone", "The 12 zone rules", "Judged from the vehicle's path inside zones the operator draws. They need only the vehicle detector and the tracker."),
              ("frame", "cards-frame", "The 3 frame checks", "Judged from what is on screen right now: how many people are on a vehicle and where."),
              ("model", "cards-model", "The 5 model checks", "Judged from a specialist model's look at the vehicle, always through a vote. These are the violations that depend on trained models.")]
    for fam, ident, title, blurb in groups:
        p.h2(ident, title, kicker="Violation cards")
        p.add(f"<p>{blurb}</p>")
        for c in allc:
            if c["family"] == fam:
                p.toc.append((f"v-{c['key']}", c["name"], 3))
                p.add(render_card(c))
        p.end()

    # ── status ────────────────────────────────────────────────────────────────
    p.h2("status", "Where each violation stands", kicker="Honest summary")
    rows = []
    for c in allc:
        info = tests_info(c["module"])
        sk, st = STATUS_CHIP[c["status"]]
        rows.append([f"<a href='#v-{c['key']}'><b>{c['name']}</b></a>", chip(sk, st), chip(*c["state"]), f"{info['coverage']}%" if info else "-", str(info["tests"]) if info else "-"])
    p.add(table(["Violation", "Origin", "State", "Lines run by tests", "Tests"], rows, "dense"))
    p.add(callout("bad", "Three things to say plainly",
                  "<ol><li><b>Missing Side Mirror cannot work yet</b>: the cabin model has not been trained on mirror pictures.</li>"
                  "<li><b>Signal light is experimental</b>: hand signals are lawful and motorcycles are exempt, so it can over-flag.</li>"
                  "<li><b>Nothing is scored on real footage</b>, and the five newest rules have never seen a real clip.</li></ol>"))
    p.end()

    # ── adding a violation ────────────────────────────────────────────────────
    p.h2("add", "How to add a 21st violation", kicker="For the next builder")
    p.add(steps([
        "Create <code>hulikamote_backend/engine/violations/&lt;name&gt;.py</code> with a class that extends <code>Violation</code> (see the base class above). Give it a <code>key</code>; for a zone rule also a <code>zone_key</code> and a <code>color</code>.",
        "Implement only the hook it needs: <code>evaluate</code> (zone rule), <code>check_frame</code> (frame check) or <code>judge</code> (model check, with a <code>job</code>).",
        "Add it to <code>ALL</code> in <code>engine/violations/__init__.py</code>. A test guards the count, so it must be updated on purpose.",
        "Add its wizard entry in <code>hulikamote_dashboard/lib/features/forensic/domain/violation_catalog.dart</code> (label, hint, whether it needs a zone or a model).",
        "Write its tests (<code>tests/engine/test_new_violations.py</code> shows how), then run it on a real clip and add that clip to the benchmark.",
    ]))
    p.add(ref("hulikamote_backend/engine/violations/base.py", symbol="@doc", label="base.py") + ref("hulikamote_dashboard/lib/features/forensic/domain/violation_catalog.dart", line=1, label="violation_catalog.dart")
          + ref("hulikamote_backend/tests/engine/test_new_violations.py", line=1, label="test_new_violations.py"))
    p.end()
    return p
