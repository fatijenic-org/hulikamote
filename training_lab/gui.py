# -*- coding: utf-8 -*-
"""
gui.py — HULI-KAMOTE Training Lab GUI
Run: python training_lab/gui.py

Zero extra dependencies beyond Python standard library + ultralytics/opencv
(which are already required for training).
"""
import sys
import subprocess
import threading
import queue
from pathlib import Path
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext

# ─── Paths ────────────────────────────────────────────────────────────────────
TRAINING_LAB = Path(__file__).parent
REPO_ROOT     = TRAINING_LAB.parent
SCRIPTS       = TRAINING_LAB / "scripts"
DATASETS      = TRAINING_LAB / "datasets"
BACKEND_MODELS = REPO_ROOT / "hulikamote_backend" / "models"

MODELS = ["helmet_specialist", "plate_specialist", "cabin_specialist", "primary_anchor"]

# Deployment target filenames (mirrors export_onnx.py)
DEPLOY_NAMES = {
    "primary_anchor":    "yolov8n.onnx",
    "helmet_specialist": "helmet_specialist.onnx",
    "plate_specialist":  "plate_specialist.onnx",
    "cabin_specialist":  "cabin_specialist.onnx",
}

# ─── Colour palette ───────────────────────────────────────────────────────────
BG       = "#1e1e2e"
SURFACE  = "#2a2a3e"
ACCENT   = "#7c6af7"
GREEN    = "#50fa7b"
RED      = "#ff5555"
YELLOW   = "#f1fa8c"
FG       = "#cdd6f4"
FG_DIM   = "#585b70"
FONT     = ("Segoe UI", 10)
FONT_B   = ("Segoe UI", 10, "bold")
MONO     = ("Consolas", 9)


# ─── Helpers ──────────────────────────────────────────────────────────────────

def count_images(model: str, split: str) -> int:
    d = DATASETS / model / "images" / split
    if not d.exists():
        return 0
    return len([f for f in d.iterdir() if f.suffix.lower() in {".jpg", ".jpeg", ".png"}])


def count_raw(model: str) -> int:
    d = DATASETS / model / "raw" / "images"
    if not d.exists():
        return 0
    return len([f for f in d.iterdir() if f.suffix.lower() in {".jpg", ".jpeg", ".png"}])


def best_pt_exists(model: str) -> bool:
    runs = TRAINING_LAB / "runs" / model
    if not runs.exists():
        return False
    for pt in runs.rglob("best.pt"):
        return True
    return False


def onnx_deployed(model: str) -> bool:
    return (BACKEND_MODELS / DEPLOY_NAMES[model]).exists()


def python_exe() -> str:
    """Return the current Python interpreter (works inside virtualenvs)."""
    return sys.executable


# ─── App ─────────────────────────────────────────────────────────────────────

class TrainingLabApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("HULI-KAMOTE  |  Training Lab")
        self.geometry("1100x700")
        self.minsize(900, 600)
        self.configure(bg=BG)
        self._log_queue: queue.Queue = queue.Queue()
        self._proc: subprocess.Popen | None = None
        self._build_ui()
        self._refresh_status()
        self._poll_log()

    # ──────────────────────────── UI construction ────────────────────────────

    def _build_ui(self):
        # Title bar
        title_bar = tk.Frame(self, bg=ACCENT, height=4)
        title_bar.pack(fill="x")

        header = tk.Frame(self, bg=SURFACE, padx=20, pady=12)
        header.pack(fill="x")
        tk.Label(header, text="HULI-KAMOTE Training Lab",
                 font=("Segoe UI", 16, "bold"), bg=SURFACE, fg=FG).pack(side="left")
        tk.Label(header, text="Decoupled Cascading Pipeline — Specialist Model Trainer",
                 font=FONT, bg=SURFACE, fg=FG_DIM).pack(side="left", padx=16)

        # Main body: left panel + right panel
        body = tk.Frame(self, bg=BG)
        body.pack(fill="both", expand=True, padx=12, pady=8)

        # ── Left: Dataset Status ──────────────────────────────────────────
        left = tk.Frame(body, bg=SURFACE, width=240, padx=12, pady=12)
        left.pack(side="left", fill="y", padx=(0, 8))
        left.pack_propagate(False)

        tk.Label(left, text="Dataset Status", font=FONT_B, bg=SURFACE, fg=FG).pack(anchor="w")
        tk.Frame(left, bg=ACCENT, height=2).pack(fill="x", pady=(4, 12))

        self._status_rows: dict[str, dict] = {}
        for m in MODELS:
            frame = tk.Frame(left, bg=SURFACE)
            frame.pack(fill="x", pady=3)

            tk.Label(frame, text=m.replace("_", " ").title(),
                     font=FONT, bg=SURFACE, fg=FG, width=16, anchor="w").pack(side="left")

            pill = tk.Label(frame, text="0 raw", font=("Segoe UI", 8),
                            bg=FG_DIM, fg=BG, padx=6, pady=1)
            pill.pack(side="right")
            self._status_rows[m] = {
                "raw": pill,
            }

            sub = tk.Frame(left, bg=SURFACE)
            sub.pack(fill="x", padx=4, pady=(0, 6))
            tr = tk.Label(sub, text="train: 0", font=("Segoe UI", 8), bg=SURFACE, fg=FG_DIM)
            tr.pack(side="left")
            vl = tk.Label(sub, text="val: 0",   font=("Segoe UI", 8), bg=SURFACE, fg=FG_DIM)
            vl.pack(side="left", padx=8)
            dp = tk.Label(sub, text="⬛",        font=("Segoe UI", 8), bg=SURFACE, fg=FG_DIM)
            dp.pack(side="right")
            self._status_rows[m]["train"] = tr
            self._status_rows[m]["val"]   = vl
            self._status_rows[m]["deploy"] = dp

        tk.Frame(left, bg=FG_DIM, height=1).pack(fill="x", pady=8)

        self._refresh_btn = tk.Button(
            left, text="⟳  Refresh Status", font=FONT, bg=SURFACE, fg=ACCENT,
            relief="flat", cursor="hand2", command=self._refresh_status,
            activebackground=SURFACE, activeforeground=FG
        )
        self._refresh_btn.pack(fill="x")

        tk.Frame(left, bg=FG_DIM, height=1).pack(fill="x", pady=8)

        # Legend
        for symbol, label in [("🟢", "Deployed"), ("🟡", "Trained, not deployed"), ("⬛", "Not trained")]:
            row = tk.Frame(left, bg=SURFACE)
            row.pack(fill="x")
            tk.Label(row, text=symbol, bg=SURFACE, font=("Segoe UI", 8)).pack(side="left")
            tk.Label(row, text=label, bg=SURFACE, fg=FG_DIM, font=("Segoe UI", 8)).pack(side="left", padx=4)

        # ── Right: Workflow panels ────────────────────────────────────────
        right = tk.Frame(body, bg=BG)
        right.pack(side="left", fill="both", expand=True)

        # Model selector (shared across all panels)
        sel_frame = tk.Frame(right, bg=SURFACE, padx=12, pady=8)
        sel_frame.pack(fill="x", pady=(0, 8))
        tk.Label(sel_frame, text="Active Model:", font=FONT_B, bg=SURFACE, fg=FG).pack(side="left")
        self._model_var = tk.StringVar(value=MODELS[0])
        cb = ttk.Combobox(sel_frame, textvariable=self._model_var,
                          values=MODELS, state="readonly", width=22, font=FONT)
        cb.pack(side="left", padx=8)
        cb.bind("<<ComboboxSelected>>", lambda _: self._refresh_status())

        # Notebook tabs
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("TNotebook",        background=BG,      borderwidth=0)
        style.configure("TNotebook.Tab",    background=SURFACE, foreground=FG,
                        padding=[14, 6],    font=FONT_B)
        style.map("TNotebook.Tab",
                  background=[("selected", ACCENT)],
                  foreground=[("selected", "#ffffff")])

        nb = ttk.Notebook(right)
        nb.pack(fill="both", expand=True)

        self._build_tab_prepare(nb)
        self._build_tab_train(nb)
        self._build_tab_full_pipeline(nb)

        # ── Log panel ────────────────────────────────────────────────────
        log_frame = tk.Frame(self, bg=SURFACE, padx=8, pady=6)
        log_frame.pack(fill="x", padx=12, pady=(0, 8))

        log_header = tk.Frame(log_frame, bg=SURFACE)
        log_header.pack(fill="x")
        tk.Label(log_header, text="Console Output", font=FONT_B, bg=SURFACE, fg=FG).pack(side="left")
        self._stop_btn = tk.Button(log_header, text="⬛ Stop", font=("Segoe UI", 9),
                                   bg=RED, fg="white", relief="flat", cursor="hand2",
                                   command=self._stop_proc, state="disabled",
                                   padx=8, pady=2)
        self._stop_btn.pack(side="right")
        tk.Button(log_header, text="Clear", font=("Segoe UI", 9),
                  bg=SURFACE, fg=FG_DIM, relief="flat", cursor="hand2",
                  command=self._clear_log, padx=8, pady=2).pack(side="right", padx=4)

        self._log = scrolledtext.ScrolledText(
            log_frame, height=8, font=MONO, bg="#11111b", fg="#a6e3a1",
            insertbackground=FG, relief="flat", state="disabled"
        )
        self._log.pack(fill="x", pady=(4, 0))

    def _card(self, parent, title) -> tk.Frame:
        """Styled card container."""
        outer = tk.Frame(parent, bg=SURFACE, padx=16, pady=14)
        outer.pack(fill="x", pady=6, padx=4)
        tk.Label(outer, text=title, font=FONT_B, bg=SURFACE, fg=ACCENT).pack(anchor="w")
        tk.Frame(outer, bg=FG_DIM, height=1).pack(fill="x", pady=(4, 10))
        return outer

    def _action_btn(self, parent, text, cmd, color=ACCENT) -> tk.Button:
        btn = tk.Button(parent, text=text, font=FONT_B, bg=color, fg="white",
                        relief="flat", cursor="hand2", command=cmd,
                        padx=16, pady=6, activebackground=color, activeforeground="white")
        btn.pack(side="left", padx=(0, 8))
        return btn

    # ─── Tab: Prepare ────────────────────────────────────────────────────────

    def _build_tab_prepare(self, nb: ttk.Notebook):
        tab = tk.Frame(nb, bg=BG)
        nb.add(tab, text="  1 · Prepare Dataset  ")
        inner = tk.Frame(tab, bg=BG)
        inner.pack(fill="both", expand=True, padx=8, pady=8)

        # Split
        c1 = self._card(inner, "Split Raw Data → train / val")
        tk.Label(c1, text="Randomly splits images from datasets/<model>/raw/ into train and val sets.",
                 font=FONT, bg=SURFACE, fg=FG_DIM, wraplength=600, justify="left").pack(anchor="w")
        row = tk.Frame(c1, bg=SURFACE)
        row.pack(fill="x", pady=(8, 0))
        tk.Label(row, text="Ratio:", font=FONT, bg=SURFACE, fg=FG).pack(side="left")
        self._ratio_var = tk.DoubleVar(value=0.8)
        tk.Scale(row, from_=0.6, to=0.95, resolution=0.05, orient="horizontal",
                 variable=self._ratio_var, bg=SURFACE, fg=FG, highlightthickness=0,
                 troughcolor=BG, length=200).pack(side="left", padx=8)
        self._ratio_lbl = tk.Label(row, text="80% train", font=FONT, bg=SURFACE, fg=FG)
        self._ratio_lbl.pack(side="left")
        self._ratio_var.trace_add("write", lambda *_: self._ratio_lbl.config(
            text=f"{int(self._ratio_var.get()*100)}% train"))
        self._action_btn(row, "▶  Split Dataset", self._run_split)

        # Augment
        c2 = self._card(inner, "Augment Training Data")
        tk.Label(c2, text="Generates synthetic copies with brightness, noise, blur, and flip variations.",
                 font=FONT, bg=SURFACE, fg=FG_DIM, wraplength=600, justify="left").pack(anchor="w")
        row2 = tk.Frame(c2, bg=SURFACE)
        row2.pack(fill="x", pady=(8, 0))
        tk.Label(row2, text="Generate:", font=FONT, bg=SURFACE, fg=FG).pack(side="left")
        self._aug_var = tk.IntVar(value=500)
        tk.Spinbox(row2, from_=100, to=5000, increment=100,
                   textvariable=self._aug_var, width=8, font=FONT,
                   bg=BG, fg=FG, insertbackground=FG, relief="flat").pack(side="left", padx=8)
        tk.Label(row2, text="images", font=FONT, bg=SURFACE, fg=FG).pack(side="left")
        self._action_btn(row2, "▶  Augment", self._run_augment)

    # ─── Tab: Train & Validate ───────────────────────────────────────────────

    def _build_tab_train(self, nb: ttk.Notebook):
        tab = tk.Frame(nb, bg=BG)
        nb.add(tab, text="  2 · Train & Validate  ")
        inner = tk.Frame(tab, bg=BG)
        inner.pack(fill="both", expand=True, padx=8, pady=8)

        # Train
        c1 = self._card(inner, "Train Model")
        tk.Label(c1, text="Launches YOLOv8 training. Epochs and image size are read from training_config.yaml.",
                 font=FONT, bg=SURFACE, fg=FG_DIM, wraplength=600, justify="left").pack(anchor="w")
        row = tk.Frame(c1, bg=SURFACE)
        row.pack(fill="x", pady=(8, 0))
        tk.Label(row, text="Epoch override:", font=FONT, bg=SURFACE, fg=FG).pack(side="left")
        self._epoch_var = tk.StringVar(value="")
        tk.Entry(row, textvariable=self._epoch_var, width=6, font=FONT,
                 bg=BG, fg=FG, insertbackground=FG, relief="flat").pack(side="left", padx=8)
        tk.Label(row, text="(blank = use config)", font=("Segoe UI", 8),
                 bg=SURFACE, fg=FG_DIM).pack(side="left")
        self._action_btn(row, "▶  Start Training", self._run_train)

        # Validate
        c2 = self._card(inner, "Validate Trained Model")
        tk.Label(c2, text="Runs mAP@0.5 evaluation against the val set and checks the deployment threshold.",
                 font=FONT, bg=SURFACE, fg=FG_DIM, wraplength=600, justify="left").pack(anchor="w")
        row2 = tk.Frame(c2, bg=SURFACE)
        row2.pack(fill="x", pady=(8, 0))
        self._action_btn(row2, "▶  Validate", self._run_validate)

        # Deploy
        c3 = self._card(inner, "Export ONNX & Deploy to Backend")
        tk.Label(c3, text="Converts best.pt → .onnx and copies it to hulikamote_backend/models/.",
                 font=FONT, bg=SURFACE, fg=FG_DIM, wraplength=600, justify="left").pack(anchor="w")
        row3 = tk.Frame(c3, bg=SURFACE)
        row3.pack(fill="x", pady=(8, 0))
        self._action_btn(row3, "▶  Export & Deploy", self._run_export, color="#50fa7b")

    # ─── Tab: Full Pipeline ──────────────────────────────────────────────────

    def _build_tab_full_pipeline(self, nb: ttk.Notebook):
        tab = tk.Frame(nb, bg=BG)
        nb.add(tab, text="  3 · One-Click Pipeline  ")
        inner = tk.Frame(tab, bg=BG)
        inner.pack(fill="both", expand=True, padx=8, pady=8)

        c = self._card(inner, "Full Pipeline  —  Split → Augment → Train → Validate → Deploy")
        tk.Label(
            c,
            text=(
                "Runs the complete training pipeline for the selected model in sequence.\n"
                "Stops automatically if validation fails the mAP threshold.\n"
                "Only export & deploy if all steps pass."
            ),
            font=FONT, bg=SURFACE, fg=FG_DIM, justify="left"
        ).pack(anchor="w")

        # Progress steps
        self._step_labels: list[tk.Label] = []
        steps = ["Split Dataset", "Augment", "Train", "Validate", "Export & Deploy"]
        steps_frame = tk.Frame(c, bg=SURFACE)
        steps_frame.pack(fill="x", pady=(12, 0))
        for s in steps:
            lbl = tk.Label(steps_frame, text=f"◦  {s}", font=FONT,
                           bg=SURFACE, fg=FG_DIM, anchor="w")
            lbl.pack(fill="x", pady=1)
            self._step_labels.append(lbl)

        row = tk.Frame(c, bg=SURFACE)
        row.pack(fill="x", pady=(14, 0))
        self._action_btn(row, "🚀  Run Full Pipeline", self._run_full_pipeline, color=ACCENT)

    # ─── Status refresh ──────────────────────────────────────────────────────

    def _refresh_status(self):
        for m in MODELS:
            raw   = count_raw(m)
            train = count_images(m, "train")
            val   = count_images(m, "val")
            deployed = onnx_deployed(m)
            trained  = best_pt_exists(m)

            r = self._status_rows[m]
            r["raw"].config(text=f"{raw} raw",
                            bg=GREEN if raw > 0 else FG_DIM,
                            fg=BG if raw > 0 else BG)
            r["train"].config(text=f"train: {train}")
            r["val"].config(text=f"val: {val}")

            if deployed:
                r["deploy"].config(text="🟢", fg=GREEN)
            elif trained:
                r["deploy"].config(text="🟡", fg=YELLOW)
            else:
                r["deploy"].config(text="⬛", fg=FG_DIM)

    # ─── Script runners ──────────────────────────────────────────────────────

    def _run_script(self, args: list[str], on_done=None):
        """Run a script in a background thread, streaming output to the log."""
        if self._proc is not None:
            messagebox.showwarning("Busy", "A process is already running. Stop it first.")
            return

        self._log_append(f"\n$ {' '.join(args)}\n", color="#bd93f9")
        self._stop_btn.config(state="normal")

        def worker():
            try:
                self._proc = subprocess.Popen(
                    args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, bufsize=1, cwd=str(TRAINING_LAB)
                )
                for line in self._proc.stdout:
                    self._log_queue.put(("line", line))
                self._proc.wait()
                code = self._proc.returncode
                self._log_queue.put(("done", code))
            except Exception as e:
                self._log_queue.put(("err", str(e)))
            finally:
                self._proc = None

            if on_done:
                self.after(100, on_done)

        threading.Thread(target=worker, daemon=True).start()

    def _model(self) -> str:
        return self._model_var.get()

    def _run_split(self):
        ratio = str(round(self._ratio_var.get(), 2))
        self._run_script([python_exe(), str(SCRIPTS / "split_dataset.py"),
                          "--model", self._model(), "--ratio", ratio],
                         on_done=self._refresh_status)

    def _run_augment(self):
        count = str(self._aug_var.get())
        self._run_script([python_exe(), str(SCRIPTS / "augment.py"),
                          "--model", self._model(), "--count", count],
                         on_done=self._refresh_status)

    def _run_train(self):
        args = [python_exe(), str(SCRIPTS / "train.py"), "--model", self._model()]
        ep = self._epoch_var.get().strip()
        if ep.isdigit():
            args += ["--epochs", ep]
        self._run_script(args, on_done=self._refresh_status)

    def _run_validate(self):
        self._run_script([python_exe(), str(SCRIPTS / "validate.py"),
                          "--model", self._model()])

    def _run_export(self):
        self._run_script([python_exe(), str(SCRIPTS / "export_onnx.py"),
                          "--model", self._model()],
                         on_done=self._refresh_status)

    # ─── Full pipeline (sequential, uses after() chaining) ───────────────────

    def _run_full_pipeline(self):
        model = self._model()
        steps = self._step_labels

        def reset_steps():
            for s in steps:
                s.config(text=f"◦  {s.cget('text')[3:]}", fg=FG_DIM)

        def mark(idx, ok: bool):
            icon = "✅" if ok else "❌"
            txt = steps[idx].cget("text")[3:]
            steps[idx].config(text=f"{icon}  {txt}", fg=GREEN if ok else RED)

        reset_steps()
        step_idx = [0]

        pipeline = [
            ([python_exe(), str(SCRIPTS / "split_dataset.py"), "--model", model,
              "--ratio", str(round(self._ratio_var.get(), 2))], True),
            ([python_exe(), str(SCRIPTS / "augment.py"), "--model", model,
              "--count", str(self._aug_var.get())], True),
            ([python_exe(), str(SCRIPTS / "train.py"), "--model", model], False),
            ([python_exe(), str(SCRIPTS / "validate.py"), "--model", model], False),
            ([python_exe(), str(SCRIPTS / "export_onnx.py"), "--model", model], False),
        ]

        def run_next():
            i = step_idx[0]
            if i >= len(pipeline):
                self._log_append("\n🎉 Full pipeline complete!\n", color=GREEN)
                self._refresh_status()
                return

            args, optional = pipeline[i]
            steps[i].config(text=f"⏳  {steps[i].cget('text')[3:]}", fg=YELLOW)

            def on_done():
                code = 0  # approximate; real check in _poll_log
                mark(i, True)
                step_idx[0] += 1
                self.after(300, run_next)

            self._run_script(args, on_done=on_done)

        run_next()

    # ─── Log helpers ─────────────────────────────────────────────────────────

    def _poll_log(self):
        try:
            while True:
                kind, val = self._log_queue.get_nowait()
                if kind == "line":
                    self._log_append(val)
                elif kind == "done":
                    color = GREEN if val == 0 else RED
                    self._log_append(f"\n[Process exited with code {val}]\n", color=color)
                    self._stop_btn.config(state="disabled")
                elif kind == "err":
                    self._log_append(f"\n[Error: {val}]\n", color=RED)
                    self._stop_btn.config(state="disabled")
        except queue.Empty:
            pass
        self.after(80, self._poll_log)

    def _log_append(self, text: str, color: str | None = None):
        self._log.config(state="normal")
        if color:
            tag = f"c_{color.replace('#', '')}"
            self._log.tag_config(tag, foreground=color)
            self._log.insert("end", text, tag)
        else:
            self._log.insert("end", text)
        self._log.see("end")
        self._log.config(state="disabled")

    def _clear_log(self):
        self._log.config(state="normal")
        self._log.delete("1.0", "end")
        self._log.config(state="disabled")

    def _stop_proc(self):
        if self._proc:
            self._proc.terminate()
            self._log_append("\n[Process terminated by user]\n", color=YELLOW)
            self._stop_btn.config(state="disabled")


# ─── Entry ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app = TrainingLabApp()
    app.mainloop()
