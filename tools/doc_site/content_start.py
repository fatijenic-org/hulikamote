"""Start page: what the site is, how to read and print it, the project in one minute."""
from __future__ import annotations

from lib import Page, arrow, box, callout, chip, cmd, figure, ref, steps, svg, table, tests_info


def _map() -> str:
    parts = [
        box(0, 20, 170, 80, ["1 Datasets", "the pictures", "models learn from"], "c1"),
        box(195, 20, 170, 80, ["2 Models", "what was learned,", "and how it is run"], "c3"),
        box(390, 20, 170, 80, ["3 Training pipeline", "how a model is made,", "checked, defended"], "c4"),
        box(585, 20, 175, 80, ["4 Violations", "how each of the 20", "is decided"], "c7"),
        arrow(170, 60, 195, 60), arrow(365, 60, 390, 60), arrow(560, 60, 585, 60),
    ]
    return svg(760, 120, "".join(parts), "The four pages in reading order: datasets, models, training pipeline, violations")


def build() -> Page:
    p = Page("index.html", "Start", "HULI-KAMOTE technical documentation",
             "A printable reference for the thesis: every dataset, every model, the whole training pipeline and a defense of it, and every violation with its code. "
             "Words are kept simple; technical terms are kept, with a plain explanation one hover away.")
    t = (tests_info("hulikamote_backend/engine/specialists.py") or {}).get("runs", {})

    p.h2("what", "What HULI-KAMOTE is, in one minute", kicker="The project", newpage=False)
    p.add("<p><b>HULI-KAMOTE</b> is a thesis project of the College of Computing Studies in Zamboanga City: a computer-vision system that finds traffic violations in video, "
          "so officers can review them without standing at the roadside. <i>Huli</i> means 'caught'; <i>kamote</i> is slang for a reckless driver. "
          "It finds vehicles with a [[YOLO]] detector, follows each one with a tracker ([[DeepSORT]]), reads licence plates ([[OCR]]), and then decides each violation with a small, explainable rule. "
          "A person always reviews what the system flags.</p>")
    p.add(figure(_map(), "<b>Read the four pages in this order.</b> What the models learned from, what they are, how they were made, and what they are used for."))
    p.add(table(["Page", "Answers", "You will find"], [
        ["<a href='1-datasets.html'><b>1 Datasets</b></a>", "What did the models learn from, and can we use it?", "Every dataset: contents, sources, licences, the model it trains, what it adds to the study, its limits, and how it was cleaned. Charts of size and Philippine share."],
        ["<a href='2-models.html'><b>2 Models</b></a>", "What models do we run, and how good are they?", "Every model: origin, starting model, training settings, scores against targets, learning curves, and the code that loads and feeds it."],
        ["<a href='3-training-pipeline.html'><b>3 Training pipeline</b></a>", "How is a model made, and is that enough?", "The loop from download to deploy to harvest, each step with its command and code, the benchmark, and an honest defense with its gaps."],
        ["<a href='4-violations.html'><b>4 Violations</b></a>", "How is each violation decided?", "All 20 violations: law, steps, models used, dashboard setup, the numbers, limits, tests and the real code, with the model-feeding code."],
        ["<a href='5-qa.html'><b>5 Q&amp;A</b></a>", "What will the panel ask, and what do we answer?", "Your own list of questions and answers. Add, edit and delete them; answers accept Markdown; saved to a JSON file on this computer."],
        ["<a href='6-live-camera.html'><b>6 Live camera</b></a>", "How does a camera's picture get in, and how do we know it works?", "From what a camera really sends, to the address, the reader code, the video relay and the checks on screen. Which setups we accept, with sources, and what we did and did not test."],
    ], "dense", ["20%", "28%", "52%"]))
    p.end()

    p.h2("how", "How to read this site", kicker="Reading guide")
    p.add(table(["You see", "It means"], [
        ["A <span class='term' tabindex='0' data-tip='This is a tooltip: hover or press Tab to read the meaning of a technical word.'>dotted word</span>", "A technical term. Hover (or press Tab on it) for a plain-language meaning. In print, all terms used on a page are listed at its end."],
        ["A code box with a path and 'lines 12-30'", "A quote cut from the real source file at the time the site was built. The line numbers are the true ones. <b>Open in VS Code</b> jumps to that line (VS Code must be installed on this computer)."],
        ["Numbered badges (&#9312; &#9313; &#9314;) on code lines", "The numbered sentences under the code explain those lines in plain words, in reading order."],
        ["Coloured chips", chip("ok", "Done") + " " + chip("warn", "Needs attention") + " " + chip("bad", "Not working / below target") + " " + chip("info", "Note") + " each with an icon and a label, never colour alone."],
        ["Bars and lines", "Charts drawn from the real numbers. Each has a caption that says what to look at."],
    ], "dense", ["34%", "66%"]))
    p.add(callout("ok", "How to print",
                  "<p>Open a page in Chrome or Edge, press <b>Ctrl+P</b>, choose <i>Save as PDF</i> (or a printer), paper <b>A4</b>, and switch on <b>Background graphics</b> so the charts keep their colours. "
                  "The page switches to black on white, hides the menu and starts each big section on a new page. Do this for each of the four pages.</p>"))
    p.add("<h4>Keeping it up to date</h4><p>The tables, numbers and code are read from the repository when the site is built. After the code or the data changes, rebuild it:</p>"
          + cmd("hulikamote_backend/venv/Scripts/python.exe tools/doc_site/build_site.py")
          + "<p>To use the <b>Q&amp;A</b> page with saving, start the local server instead of opening the file directly. It also serves all the other pages:</p>"
          + cmd("hulikamote_backend/venv/Scripts/python.exe tools/doc_site/serve.py --open"))
    p.end()

    p.h2("status", "Where the project honestly stands", kicker="One table, no spin")
    p.add(table(["Area", "State", "Detail"], [
        ["Violations", chip("ok", "20 coded") + " " + chip("warn", "0 scored on real footage"), "Each has automated tests on scripted data. The benchmark that scores them on real clips is built; its clip list is still empty. Page 4."],
        ["Detection models", chip("ok", "3 trained") + " " + chip("warn", "1 below target"), "Helmet meets its target on validation data; cabin is just under; plate is well under. The vehicle detector is the stock one. Page 2."],
        ["Training data", chip("warn", "Not Zamboanga"), "Public datasets with open licences; none is local CCTV. The harvest loop is built to add local pictures. Pages 1 and 3."],
        ["Missing features", chip("bad", "Missing Side Mirror cannot work yet"), "Needs the cabin model retrained on mirror pictures."],
        ["Tests", chip("ok", "All passing"), f"{t.get('backend', {}).get('passed', '?')} backend, {t.get('training_lab', {}).get('passed', '?')} training-lab and {t.get('flutter', {}).get('passed', '?')} dashboard tests."],
        ["Live demo", chip("info", "Simulated CCTV"), "A second laptop or phone streams the footage over RTSP; the system reads it as a camera. Page 4, set-up."],
    ], "dense", ["18%", "32%", "50%"]))
    p.add(callout("warn", "What this documentation does not claim",
                  "<p>It does not claim accuracy on Zamboanga roads. It documents what is built, how it works, what it was trained on, and what still has to be measured. "
                  "Legal references marked <b>to confirm</b> are not yet checked with an adviser; fine amounts are not quoted.</p>"))
    p.add(ref("docs/HANDOVER.md", line=1, label="HANDOVER.md (living status)") + ref("docs/PROJECT_CONTEXT.md", line=1, label="PROJECT_CONTEXT.md (the thesis scope)")
          + ref("docs/THESIS_REVISIONS.md", line=1, label="THESIS_REVISIONS.md (paste-ready thesis text)"))
    p.end()
    return p
