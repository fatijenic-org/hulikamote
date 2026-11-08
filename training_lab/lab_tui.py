"""
lab_tui.py — HULI-KAMOTE Training Lab in the terminal.

Trains the YOLO models in their own background process (not inside the backend, so the
dashboard can be closed and a backend restart cannot stop it) and explains training in
plain language: scores, mistakes, a verdict, the live epoch, every past run and the dataset.
It also follows trainings started elsewhere (Training Studio): it reads YOLO's own files
(runs/<model>/<run>/results.csv every epoch, and the training log every batch).

Run (repo root):  hulikamote_backend/venv/Scripts/python.exe training_lab/lab_tui.py
Mouse works everywhere. Keys: m next model · 1-4 views · s start · u resume · x stop · d deploy · q quit
"""
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import yaml
from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Grid, Horizontal, Vertical, VerticalScroll
from textual.screen import ModalScreen
from textual.widgets import (Button, DataTable, Footer, Header, Input, Label, ProgressBar, RichLog, Static,
                             TabbedContent, TabPane)
from textual_plotext import PlotextPlot

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
from fetch_datasets import split_dirs, target_classes  # noqa: E402
from run_state import (launch_detached, model_runs, read_run, resumable, run_finished,  # noqa: E402
                       resume_command, training_process)

# The Harvest tab is optional: a problem inside it must never take training control down.
HARVEST_ERROR = ""
try:
    sys.path.insert(0, str(ROOT))
    from harvest_tool.tui_view import HarvestPanel  # noqa: E402
except Exception as _e:                              # noqa: BLE001
    HarvestPanel, HARVEST_ERROR = None, f"{type(_e).__name__}: {_e}"

from lab_core import (CONFIG, IMAGE_EXT, LOGS, MANIFEST, MODELS, TARGET, _BATCH, _VAL, bar, dataset_stats,  # noqa: E402
                      deployed_run, find_log, gpu_stats, minutes, parse_log, tail, trend, verdict)


# ─── Dialogs ─────────────────────────────────────────────────────────────────

class StartDialog(ModalScreen):
    """New training: settings with the recommended values filled in."""
    BINDINGS = [("escape", "dismiss(None)", "Cancel")]

    def __init__(self, model: str):
        super().__init__()
        self.model = model

    def compose(self) -> ComposeResult:
        per = CONFIG.get("models", {}).get(self.model, {})
        imgsz = 640 if self.model == "primary_anchor" else 320
        with Vertical(classes="dialog"):
            yield Label(f"[b]Start a new {MODELS[self.model][0]} training[/]")
            yield Label(f"Base model: [b]{CONFIG['base_model']}[/]  ·  stops early after {CONFIG['patience']} "
                        f"epochs without improvement", classes="muted")
            with Grid(classes="form"):
                yield Label("Epochs")
                yield Input(str(per.get("epochs", CONFIG["epochs"])), id="f_epochs", type="integer")
                yield Label("[dim]passes over the data; early stop usually ends sooner[/]")
                yield Label("Image size")
                yield Input(str(imgsz), id="f_imgsz", type="integer")
                yield Label(f"[dim]{'640: this model sees whole frames' if imgsz == 640 else '320: the app gives this model small crops'}[/]")
                yield Label("Batch")
                yield Input(str(CONFIG["batch"]), id="f_batch", type="integer")
                yield Label("[dim]photos per step; use 8 if the GPU runs out of memory[/]")
            with Horizontal(classes="dialog-buttons"):
                yield Button("Start", id="ok", variant="success")
                yield Button("Cancel", id="cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "ok":
            self.dismiss({k: self.query_one(f"#f_{k}", Input).value or "0" for k in ("epochs", "imgsz", "batch")})
        else:
            self.dismiss(None)


class ConfirmDialog(ModalScreen):
    BINDINGS = [("escape", "dismiss(False)", "Cancel")]

    def __init__(self, question: str, yes: str):
        super().__init__()
        self.question, self.yes = question, yes

    def compose(self) -> ComposeResult:
        with Vertical(classes="dialog"):
            yield Label(self.question)
            with Horizontal(classes="dialog-buttons"):
                yield Button(self.yes, id="yes", variant="warning")
                yield Button("Cancel", id="no")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id == "yes")


# ─── Main app ────────────────────────────────────────────────────────────────

class TrainingLab(App):
    TITLE = "HULI-KAMOTE Training Lab"
    CSS = """
    #modelbar { height: 3; padding: 0 1; }
    #modelbar Button { min-width: 12; margin-right: 1; }
    #modelbar Button.active { background: $accent; text-style: bold; }
    #state { width: 1fr; content-align: right middle; height: 3; }
    TabbedContent { height: 1fr; }
    VerticalScroll { padding: 0 1; }
    .section { margin-top: 1; text-style: bold; }
    .muted { color: $text-muted; }
    #summary, #verdict { height: auto; border: round $primary; padding: 0 1; margin-top: 1; }
    .cards { height: auto; }
    .card { width: 1fr; height: auto; min-height: 6; border: round $secondary; padding: 0 1; }
    .charts { height: 18; }
    .charts PlotextPlot { width: 1fr; }
    #ep_chart, #run_chart_map, #run_chart_loss { height: 16; }
    #ds_plot { height: 18; }
    #runs { height: auto; max-height: 12; }
    #rawlog { height: 14; border: round $primary; }
    ProgressBar { width: 1fr; }
    ProgressBar Bar { width: 1fr; }
    #actions { dock: bottom; height: 3; padding: 0 1; background: $panel; }
    #actions Button { margin-right: 1; }
    #hint { width: 1fr; content-align: left middle; height: 3; color: $text-muted; }
    .dialog { width: 90; max-width: 95%; height: auto; border: thick $accent; background: $surface; padding: 1 2; }
    ModalScreen { align: center middle; }
    .form { grid-size: 3; grid-columns: 12 14 1fr; grid-rows: 3; height: auto; margin-top: 1; }
    .form Label { padding-top: 1; }
    .dialog-buttons { height: 3; margin-top: 1; }
    .dialog-buttons Button { margin-right: 2; }
    """
    # View keys are shown on the tabs themselves ("1 Overview" ...), so the footer stays short
    BINDINGS = [Binding("m", "next_model", "Next model"),
                Binding("1", "view('overview')", show=False), Binding("2", "view('epoch')", show=False),
                Binding("3", "view('runs')", show=False), Binding("4", "view('data')", show=False),
                Binding("5", "view('harvest')", show=False),
                Binding("s", "start", "Start"), Binding("u", "resume", "Resume"), Binding("x", "stop", "Stop"),
                Binding("d", "deploy", "Deploy"), Binding("q", "quit", "Quit")]

    def __init__(self):
        super().__init__()
        self.model = next(iter(MODELS))
        self.proc: subprocess.Popen | None = None
        self.started_at = 0.0
        self.run_cache: dict = {}
        self.selected_run: Path | None = None

    # ── layout ──
    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal(id="modelbar"):
            for key, (title, _) in MODELS.items():
                yield Button(title, id=f"m_{key}", classes="model")
            yield Static(id="state")
        with TabbedContent(id="tabs"):
            with TabPane("1 Overview", id="overview"):
                with VerticalScroll():
                    yield Static(id="summary")
                    yield ProgressBar(id="epochs_bar", show_eta=False)
                    with Horizontal(classes="cards"):
                        for cid in ("c_score", "c_trust", "c_cover", "c_mistakes"):
                            yield Static(classes="card", id=cid)
                    with Horizontal(classes="charts"):
                        yield PlotextPlot(id="chart_quality")
                        yield PlotextPlot(id="chart_loss")
                    yield Static(id="verdict")
                    yield Static(id="gpu", classes="muted")
            with TabPane("2 Live epoch", id="epoch"):
                with VerticalScroll():
                    yield Static(id="ep_title")
                    yield Label("Epochs", classes="section")
                    yield ProgressBar(id="ep_all", show_eta=False)
                    yield Label("This epoch (batches of photos)", classes="section")
                    yield ProgressBar(id="ep_batch", show_eta=False)
                    with Horizontal(classes="cards"):
                        for cid in ("e_box", "e_cls", "e_dfl", "e_gpu"):
                            yield Static(classes="card", id=cid)
                    yield PlotextPlot(id="ep_chart")
                    yield Label("Training log (important lines)", classes="section")
                    yield RichLog(id="rawlog", wrap=True, markup=False)
            with TabPane("3 Runs & logs", id="runs_tab"):
                with VerticalScroll():
                    yield Static("Every training of this model. Click a run to see its history.", classes="muted")
                    yield DataTable(id="runs", cursor_type="row", zebra_stripes=True)
                    yield Static(id="run_title", classes="section")
                    with Horizontal(classes="charts"):
                        yield PlotextPlot(id="run_chart_map")
                        yield PlotextPlot(id="run_chart_loss")
                    yield Static(id="run_verdict")
            with TabPane("4 Dataset", id="data"):
                with VerticalScroll():
                    yield Static("Counting...", id="ds_text")
                    yield PlotextPlot(id="ds_plot")
            with TabPane("5 Harvest", id="harvest"):
                yield HarvestPanel() if HarvestPanel else Static(f"The Harvest tab is unavailable: {HARVEST_ERROR}")
        with Horizontal(id="actions"):
            yield Button("▶ Start new", id="a_start", variant="success")
            yield Button("⟳ Resume", id="a_resume", variant="primary")
            yield Button("■ Stop", id="a_stop", variant="error")
            yield Button("⇪ Deploy best", id="a_deploy", variant="warning")
            yield Static(id="hint")
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one("#runs", DataTable)
        table.add_columns("Run", "Started", "Epochs", "Best score", "Best at", "Status", "In app")
        self.select_model(self.model)
        self.set_interval(2.0, self.tick)
        self.set_interval(20.0, lambda: self.load_runs(self.model))

    # ── model / view switching ──
    def select_model(self, model: str) -> None:
        self.model = model
        self.selected_run = None
        for key in MODELS:
            self.query_one(f"#m_{key}", Button).set_class(key == model, "active")
        self.sub_title = f"{MODELS[model][0]} — finds {MODELS[model][1]}"
        self.query_one("#rawlog", RichLog).clear()
        self.query_one("#ds_text", Static).update(f"Counting the {MODELS[model][0]} dataset...")
        self.count_dataset(model)
        self.load_runs(model)
        self.tick()

    def action_next_model(self) -> None:
        keys = list(MODELS)
        self.select_model(keys[(keys.index(self.model) + 1) % len(keys)])

    def action_view(self, view: str) -> None:
        self.query_one("#tabs", TabbedContent).active = {"runs": "runs_tab"}.get(view, view)

    # ── periodic refresh (work in threads, UI updates on the main thread) ──
    def tick(self) -> None:
        self.refresh_live(self.model)

    @work(thread=True, exclusive=True, group="live")
    def refresh_live(self, model: str) -> None:
        proc = training_process(model)
        runs = model_runs(model)
        run = runs[0] if runs else None
        data = read_run(run) if run else None
        can_resume, resume_msg = (False, "Training now.") if proc else resumable(run)
        log = None
        if proc or (self.proc and self.proc.poll() is None):
            started = proc.create_time() if proc else self.started_at
            path = find_log(model, started - 5)
            log = parse_log(tail(path)) if path else None
        gpu = gpu_stats()
        if model == self.model:
            self.call_from_thread(self.show_live, proc, run, data, can_resume, resume_msg, log, gpu)

    def show_live(self, proc, run, data, can_resume, resume_msg, log, gpu) -> None:
        name = MODELS[self.model][0]
        has_weights = bool(run and (run / "weights" / "best.pt").exists())
        # action bar
        self.query_one("#a_start", Button).disabled = bool(proc)
        self.query_one("#a_resume", Button).disabled = not can_resume
        self.query_one("#a_stop", Button).disabled = not proc
        self.query_one("#a_deploy", Button).disabled = bool(proc) or not has_weights
        self.query_one("#hint", Static).update(resume_msg if can_resume else
                                               "Training in its own background process — safe to close this window."
                                               if proc else "")
        self.query_one("#state", Static).update(
            f"[b green]● TRAINING[/]" if proc else "[dim]○ idle[/]")
        g = "GPU not found — training would use the CPU (very slow)." if gpu is None else (
            f"GPU {gpu['name']} · load {bar(gpu['util'] / 100, 10)} {gpu['util']}% · "
            f"memory {gpu['used'] / 1024:.1f}/{gpu['total'] / 1024:.1f} GB · {gpu['temp']}°C")
        self.query_one("#gpu", Static).update(g)

        # overview
        cols = data["cols"] if data else {}
        if not cols.get("epoch"):
            self.query_one("#summary", Static).update(
                f"[b]{name}[/] has no trained run yet. Press [b]▶ Start new[/] (or s) to train it."
                if not proc else f"[b]{name}[/] is starting its first epoch...")
            self.show_epoch(log, None)
            return
        done, total = len(cols["epoch"]), data["epochs"] or len(cols["epoch"])
        t = cols.get("time", [])     # older YOLO versions do not log time
        gaps = sorted(b - a for a, b in zip(t[-6:], t[-5:]))
        per_epoch = gaps[len(gaps) // 2] if gaps else 0
        m50 = cols.get("metrics/mAP50(B)", [0])
        best_i = max(range(len(m50)), key=lambda i: m50[i])
        deployed = deployed_run(self.model)
        state = ("[b green]training now[/]" if proc else "[green]finished[/]" if run_finished(run)
                 else "[yellow]interrupted[/] — press ⟳ Resume to continue")
        self.query_one("#summary", Static).update(
            f"[b]{name}[/] · latest run [b]{run.name}[/] is {state}\n"
            f"Epoch {done} of {total}" + (f" · {per_epoch / 60:.1f} min per epoch" if per_epoch else "")
            + (f" · about {minutes((total - done) * per_epoch)} left (less if it stops early)"
               if proc and per_epoch else "")
            + f"\nBest score {m50[best_i]:.2f} at epoch {best_i + 1} · base {data['base']} · image size {data['imgsz']}"
            + (f"\nThe app currently uses run [b]{deployed}[/]." if deployed else
               "\nThe app is not using a model trained here yet (⇪ Deploy best)."))
        self.query_one("#epochs_bar", ProgressBar).update(total=total, progress=done)
        prec, rec = cols.get("metrics/precision(B)", [0]), cols.get("metrics/recall(B)", [0])
        tl, vl = cols.get("train/box_loss", [0]), cols.get("val/box_loss", [0])
        self.query_one("#c_score", Static).update(
            f"[b]Overall score[/] [dim](mAP@50)[/]\n[b]{m50[-1]:.2f}[/] {bar(m50[-1], 12)}\n"
            f"[dim]target {TARGET[self.model]:.2f} · 1.00 = perfect[/]")
        self.query_one("#c_trust", Static).update(
            f"[b]Trust[/] [dim](precision)[/]\n[b]{prec[-1]:.0%}[/] {bar(prec[-1], 12)}\n"
            "[dim]when it says “found”, it's right[/]")
        self.query_one("#c_cover", Static).update(
            f"[b]Coverage[/] [dim](recall)[/]\n[b]{rec[-1]:.0%}[/] {bar(rec[-1], 12)}\n[dim]of all real objects, found[/]")
        direction = "falling ✓" if trend(vl) < 0 else "rising !" if trend(vl) > 0.002 else "flat"
        self.query_one("#c_mistakes", Static).update(
            f"[b]Mistakes[/] [dim](loss, lower = better)[/]\ntraining {tl[-1]:.2f} · new photos {vl[-1]:.2f}\n"
            f"[dim]on new photos: {direction}[/]")
        self.plot_run(cols, "#chart_quality", "#chart_loss")
        self.query_one("#verdict", Static).update("\n".join(verdict(self.model, cols)))
        self.show_epoch(log, cols)

    def plot_run(self, cols: dict, quality_id: str, loss_id: str) -> None:
        ep = cols.get("epoch", [])
        q = self.query_one(quality_id, PlotextPlot)
        plt = q.plt
        plt.clear_data()
        plt.plot(ep, cols.get("metrics/mAP50(B)", []), label="score")
        plt.plot(ep, cols.get("metrics/precision(B)", []), label="trust")
        plt.plot(ep, cols.get("metrics/recall(B)", []), label="coverage")
        plt.hline(TARGET[self.model])
        plt.ylim(0, 1)
        plt.title("Getting better?  (higher = better · line = target)")
        q.refresh()
        lp = self.query_one(loss_id, PlotextPlot)
        plt = lp.plt
        plt.clear_data()
        plt.plot(ep, cols.get("train/box_loss", []), label="training photos")
        plt.plot(ep, cols.get("val/box_loss", []), label="new photos")
        plt.title("Mistakes  (lower = better · gap growing = overfitting)")
        lp.refresh()

    def show_epoch(self, log: dict | None, cols: dict | None) -> None:
        cur = log["current"] if log else None
        title = self.query_one("#ep_title", Static)
        if cur is None:
            title.update("[dim]Nothing is training right now. This view comes alive while a training runs: "
                         "progress inside the epoch, live mistake values and a chart of them.[/]")
            return
        title.update(f"[b]Epoch {cur['epoch']} of {cur['epochs']}[/] · batch {cur['batch']}/{cur['batches']} · "
                     f"{cur['speed']} · {cur['elapsed']} elapsed, {cur['left'] or '?'} left in this epoch")
        self.query_one("#ep_all", ProgressBar).update(total=cur["epochs"], progress=cur["epoch"] - 1)
        self.query_one("#ep_batch", ProgressBar).update(total=cur["batches"], progress=cur["batch"])
        self.query_one("#e_box", Static).update(
            f"[b]Box mistakes[/]\n[b]{cur['box']:.3f}[/]\n[dim]how far the drawn boxes are off[/]")
        self.query_one("#e_cls", Static).update(
            f"[b]Label mistakes[/]\n[b]{cur['cls']:.3f}[/]\n[dim]wrong class (e.g. helmet vs none)[/]")
        self.query_one("#e_dfl", Static).update(
            f"[b]Edge mistakes[/]\n[b]{cur['dfl']:.3f}[/]\n[dim]how sharp the box edges are[/]")
        self.query_one("#e_gpu", Static).update(
            f"[b]GPU memory[/]\n[b]{cur['gpu_gb']:.1f} GB[/]\n[dim]{cur['objects']} objects in this batch[/]")
        series = log["series"]
        chart = self.query_one("#ep_chart", PlotextPlot)
        plt = chart.plt
        plt.clear_data()
        xs = [b["batch"] for b in series]
        plt.plot(xs, [b["box"] for b in series], label="box")
        plt.plot(xs, [b["cls"] for b in series], label="label")
        plt.plot(xs, [b["dfl"] for b in series], label="edge")
        plt.title(f"Mistakes during epoch {cur['epoch']}  (average so far · should drift down)")
        chart.refresh()

    # ── runs & logs ──
    @work(thread=True, exclusive=True, group="runs")
    def load_runs(self, model: str) -> None:
        rows = []
        deployed = deployed_run(model)
        proc = training_process(model)
        for i, run in enumerate(model_runs(model)):
            data = read_run(run)
            m50 = data["cols"].get("metrics/mAP50(B)", [0])
            best_i = max(range(len(m50)), key=lambda k: m50[k])
            status = ("training" if proc and i == 0 else "finished" if run_finished(run) else "interrupted")
            started = time.strftime("%b %d %H:%M", time.localtime((run / "args.yaml").stat().st_mtime)) \
                if (run / "args.yaml").exists() else "?"
            rows.append((run, (run.name, started, f"{len(m50)}/{data['epochs']}", f"{m50[best_i]:.3f}",
                               f"epoch {best_i + 1}", status, "✓ in use" if run.name == deployed else "")))
        if model == self.model:
            self.call_from_thread(self.show_runs, rows)

    def show_runs(self, rows: list) -> None:
        table = self.query_one("#runs", DataTable)
        table.clear()
        self.run_cache = {}
        for run, cells in rows:
            table.add_row(*cells, key=str(run))
            self.run_cache[str(run)] = run
        if not rows:
            self.query_one("#run_title", Static).update("[dim]No runs yet.[/]")
        elif self.selected_run is None:
            self.show_run_detail(rows[0][0])

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        run = self.run_cache.get(str(event.row_key.value))
        if run:
            self.show_run_detail(run)

    def show_run_detail(self, run: Path) -> None:
        self.selected_run = run
        data = read_run(run)
        self.query_one("#run_title", Static).update(
            f"Run [b]{run.name}[/] · base {data['base']} · image size {data['imgsz']} · "
            f"{len(data['cols'].get('epoch', []))} of {data['epochs']} epochs · folder {run}")
        self.plot_run(data["cols"], "#run_chart_map", "#run_chart_loss")
        self.query_one("#run_verdict", Static).update("\n".join(verdict(self.model, data["cols"])))

    # ── dataset ──
    @work(thread=True, exclusive=True, group="dataset")
    def count_dataset(self, model: str) -> None:
        try:
            stats = dataset_stats(model)
        except Exception as e:
            self.call_from_thread(self.query_one("#ds_text", Static).update, f"[red]Could not read the dataset: {e}[/]")
            return
        if model == self.model:
            self.call_from_thread(self.show_dataset, stats)

    def show_dataset(self, stats: dict) -> None:
        names, splits = stats["classes"], stats["splits"]
        train = splits.get("train", {"images": 0, "per_class": [0] * len(names)})
        lines = [f"[b]{MODELS[self.model][0]} dataset[/] — " + " · ".join(
            f"{s}: {d['images']:,} photos" for s, d in splits.items()),
            "[dim]train = what it learns from · val = checked every epoch · test = final exam[/]", ""]
        most = max(train["per_class"] + [1])
        total = sum(train["per_class"]) or 1
        for name, n in zip(names, train["per_class"]):
            note = ("  [red]← no examples: this check cannot be learned[/]" if n == 0 else
                    "  [yellow]← very few[/]" if n < 0.05 * total else "")
            lines.append(f"  {name:22} {bar(n / most, 20)} {n:8,}{note}")
        if not splits.get("val", {}).get("images"):
            lines.append("[red]No validation photos — scores cannot be measured.[/]")
        self.query_one("#ds_text", Static).update("\n".join(lines))
        plot = self.query_one("#ds_plot", PlotextPlot)
        plt = plot.plt
        plt.clear_data()
        plt.bar(names, train["per_class"])
        plt.title("Objects per class in the training photos  (even bars = balanced)")
        plot.refresh()

    # ── actions ──
    def on_button_pressed(self, event: Button.Pressed) -> None:
        bid = event.button.id or ""
        if bid.startswith("m_"):
            self.select_model(bid.removeprefix("m_"))
        elif bid.startswith("a_"):
            getattr(self, f"action_{bid.removeprefix('a_')}")()

    def _busy(self) -> bool:
        if training_process(self.model) or (self.proc and self.proc.poll() is None):
            self.notify(f"{MODELS[self.model][0]} is already training.", severity="warning")
            return True
        return False

    def action_start(self) -> None:
        if self._busy():
            return

        def go(values: dict | None) -> None:
            if values:
                self.launch([sys.executable, str(ROOT / "scripts" / "train.py"), "--model", self.model,
                             "--epochs", values["epochs"], "--imgsz", values["imgsz"], "--batch", values["batch"]],
                            f"train_{self.model}")
        self.push_screen(StartDialog(self.model), go)

    def action_resume(self) -> None:
        if self._busy():
            return
        runs = model_runs(self.model)
        ok, msg = resumable(runs[0] if runs else None)
        if not ok:
            self.notify(msg, severity="warning")
            return
        # YOLO continues from the saved epoch with the run's original settings
        self.launch(resume_command(sys.executable, self.model), f"resume_{self.model}")
        self.notify(msg)

    def action_stop(self) -> None:
        target = self.proc if self.proc and self.proc.poll() is None else training_process(self.model)
        if target is None:
            self.notify("Nothing is training.")
            return

        def go(yes: bool) -> None:
            if yes:
                target.terminate()
                self.notify("Stopped. The best weights so far are kept — ⟳ Resume continues later.")
        self.push_screen(ConfirmDialog(f"Stop the {MODELS[self.model][0]} training?", "Stop"), go)

    def action_deploy(self) -> None:
        if training_process(self.model):
            self.notify("Wait for training to finish first.", severity="warning")
            return
        runs = model_runs(self.model)
        if not runs or not (runs[0] / "weights" / "best.pt").exists():
            self.notify("No trained weights to deploy.", severity="warning")
            return

        def go(yes: bool) -> None:
            if yes:
                self.launch([sys.executable, str(ROOT / "scripts" / "export_onnx.py"), "--model", self.model,
                             "--run", runs[0].name], f"export_{self.model}")
                self.notify("Deploying... then restart the backend so the app loads it.")
        self.push_screen(ConfirmDialog(
            f"Deploy the best epoch of run '{runs[0].name}' as the {MODELS[self.model][0]} model the app uses?",
            "Deploy"), go)

    def launch(self, cmd: list[str], tag: str) -> None:
        """Run in its own background process (see run_state.launch_detached). Output goes to runs/logs/."""
        log_path = LOGS / f"tui_{tag}_{time.strftime('%Y%m%d_%H%M%S')}.log"
        self.proc = launch_detached(cmd, log_path)
        self.started_at = time.time()
        self.query_one("#rawlog", RichLog).write(f"Started {tag} (pid {self.proc.pid}) · log {log_path.name}")
        self.follow_log(log_path)

    @work(thread=True, exclusive=True, group="follow")
    def follow_log(self, path: Path) -> None:
        """Copy the important log lines (not the per-batch bar) into the log panel while it runs."""
        pos = 0
        while True:
            with open(path, encoding="utf-8", errors="replace") as f:
                f.seek(pos)
                chunk = f.read()
                pos = f.tell()
            for raw in chunk.replace("\r", "\n").split("\n"):
                line = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", raw).rstrip()
                if line and not _BATCH.search(line) and "it/s" not in line and "s/it" not in line:
                    self.call_from_thread(self.query_one("#rawlog", RichLog).write, line)
            if self.proc is None or self.proc.poll() is not None:
                code = self.proc.returncode if self.proc else 0
                self.call_from_thread(self.notify, "Finished." if code == 0 else f"Exited with code {code} — see the log.",
                                      severity="information" if code == 0 else "error")
                self.call_from_thread(self.load_runs, self.model)
                return
            time.sleep(1.5)


if __name__ == "__main__":
    TrainingLab().run()
