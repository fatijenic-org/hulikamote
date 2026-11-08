"""
lab.py - the Training Lab as a plain menu: pick a number, one step at a time, the screen is cleared at every step.
No full-screen app, no mouse, only ASCII symbols. Same engine as lab_tui.py: a training runs in its own background
process, so closing this window, the dashboard or a backend restart never stops it.

Run (repo root):  hulikamote_backend/venv/Scripts/python.exe training_lab/lab.py
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))
from fetch_datasets import split_dirs  # noqa: E402
from lab_core import (CONFIG, IMAGE_EXT, LOGS, MODELS, TARGET, dataset_stats, deployed_run, find_log,  # noqa: E402
                      gpu_stats, parse_log, tail, verdict)
from run_state import (launch_detached, model_runs, pause, read_run, resumable, resume_command,  # noqa: E402
                       training_processes)

WIDTH = 78
COUNTS = LOGS / "lab_counts.json"          # image counts per folder, refreshed when the folder changes (big folders are slow to scan)
ORDER = ["primary_anchor", "helmet_specialist", "plate_specialist", "cabin_specialist"]
# How long a training runs: (name, epochs, share of the pictures, what it is for). Same epochs as the Training Studio.
PRESETS = [
    ("Test run", 2, 0.05, "2 epochs on 5% of the pictures: only checks that everything runs"),
    ("Quick", 30, 1.0, "30 epochs: a first real result"),
    ("Balanced", 100, 1.0, "100 epochs: the usual choice (stops early when it stops improving)"),
    ("Thorough", 200, 1.0, "200 epochs: the long one"),
]


# --- screen pieces -------------------------------------------------------------------------------------------------

def clear() -> None:
    if sys.stdout.isatty():
        os.system("cls" if os.name == "nt" else "clear")


def table(headers: list, rows: list) -> str:
    """A plain table drawn with + - | only."""
    rows = [[str(c) for c in r] for r in rows]
    widths = [max([len(str(h))] + [len(r[i]) for r in rows]) for i, h in enumerate(headers)]
    line = "+" + "+".join("-" * (w + 2) for w in widths) + "+"

    def fmt(r) -> str:
        return "| " + " | ".join(str(c).ljust(w) for c, w in zip(r, widths)) + " |"
    return "\n".join([line, fmt(headers), line, *map(fmt, rows), line])


def ascii_bar(fraction: float, width: int = 30) -> str:
    filled = int(round(max(0.0, min(1.0, fraction)) * width))
    return "#" * filled + "-" * (width - filled)


def plain(text: str) -> str:
    """Strip the app's colour tags and symbols so the line is plain ASCII."""
    text = re.sub(r"\[/?[a-z ]*\]", "", text)
    for a, b in (("—", "-"), ("✓", "OK"), ("≈", "~"), ("…", "..."), ("→", "->")):
        text = text.replace(a, b)
    return text.encode("ascii", "ignore").decode()


def show(*path: str, blocks: tuple = ()) -> None:
    clear()
    print("=" * WIDTH)
    print(" HULI-KAMOTE TRAINING LAB  >  " + "  >  ".join(path))
    print("=" * WIDTH + "\n")
    for b in blocks:
        print(b + "\n")


def ask(options: list[tuple[str, str]], note: str = "") -> str:
    """Show the choices as a table, read one valid key (case does not matter)."""
    print(table(["Key", "What it does"], options))
    if note:
        print(note)
    valid = {k.lower() for k, _ in options}
    while True:
        try:
            answer = input("\nChoose: ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            return "q" if "q" in valid else "b"
        if answer in valid:
            return answer
        print("Not one of the keys above.")


def pause_screen(text: str = "Press Enter to go back.") -> None:
    try:
        input("\n" + text)
    except (EOFError, KeyboardInterrupt):
        pass


def confirm(question: str, yes: str = "Yes") -> bool:
    print(question + "\n")
    return ask([("y", yes), ("n", "No, go back")]) == "y"


def number(prompt: str, default: float, integer: bool = True) -> float:
    while True:
        try:
            raw = input(f"{prompt} [{default:g}]: ").strip()
        except (EOFError, KeyboardInterrupt):
            return default
        if not raw:
            return default
        try:
            value = float(raw)
        except ValueError:
            print("Type a number.")
            continue
        if value > 0:
            return int(value) if integer else value
        print("It must be more than 0.")


def key_pressed() -> bool:
    """True when a key was pressed (consumed), without waiting."""
    if os.name == "nt":
        import msvcrt
        if msvcrt.kbhit():
            msvcrt.getwch()
            return True
        return False
    import select
    ready, _, _ = select.select([sys.stdin], [], [], 0)
    if ready:
        sys.stdin.readline()
        return True
    return False


# --- what the screens show -----------------------------------------------------------------------------------------

def image_count(model: str, split: str) -> int:
    """Pictures in a split. Remembered until the folder changes: scanning 30k files takes a while on this disk."""
    img_dir, _ = split_dirs(model, split)
    if not img_dir.exists():
        return 0
    stamp, key = img_dir.stat().st_mtime, f"{model}/{split}"
    try:
        cache = json.loads(COUNTS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        cache = {}
    if cache.get(key, [None])[0] == stamp:
        return cache[key][1]
    count = sum(1 for e in os.scandir(img_dir) if Path(e.name).suffix.lower() in IMAGE_EXT)
    cache[key] = [stamp, count]
    try:
        COUNTS.parent.mkdir(parents=True, exist_ok=True)
        COUNTS.write_text(json.dumps(cache), encoding="utf-8")
    except OSError:
        pass
    return count


def run_summary(run: Path) -> dict:
    data = read_run(run)
    cols = data["cols"]
    m50, m5095 = cols.get("metrics/mAP50(B)", []), cols.get("metrics/mAP50-95(B)", [])
    return {"name": run.name, "done": len(cols.get("epoch", [])), "planned": data["epochs"],
            "best50": max(m50) if m50 else None, "best5095": max(m5095) if m5095 else None, "cols": cols}


def score(value: float | None) -> str:
    return "-" if value is None else f"{value:.2f}"


def busy_models() -> list[str]:
    return [m for m in ORDER if training_processes(m)]


def defaults(model: str) -> tuple[int, int]:
    """Image size and batch the Training Lab recommends: whole frames (640) for vehicles, crops (320) otherwise."""
    return (640 if model == "primary_anchor" else 320), int(CONFIG["batch"])


def train_command(model: str, epochs: int, imgsz: int, batch: int, fraction: float = 1.0) -> list[str]:
    cmd = [sys.executable, str(ROOT / "scripts" / "train.py"), "--model", model, "--epochs", str(epochs),
           "--imgsz", str(imgsz), "--batch", str(batch)]
    return cmd + (["--fraction", f"{fraction:g}"] if fraction < 1.0 else [])


def start_detached(cmd: list[str], tag: str) -> subprocess.Popen:
    return launch_detached(cmd, LOGS / f"lab_{tag}_{time.strftime('%Y%m%d_%H%M%S')}.log")


def run_foreground(cmd: list[str]) -> int:
    """A short job whose output the user should see (export, data cleaning): runs here, then waits for Enter."""
    print()
    code = subprocess.run(cmd, cwd=ROOT).returncode
    print("\nFinished." if code == 0 else f"\nStopped with an error (code {code}).")
    pause_screen()
    return code


# --- screens -------------------------------------------------------------------------------------------------------

def main_screen() -> None:
    while True:
        rows = []
        for i, model in enumerate(ORDER, 1):
            runs = model_runs(model)
            last = run_summary(runs[0]) if runs else None
            rows.append([i, MODELS[model][0], f"{image_count(model, 'train')} / {image_count(model, 'val')}",
                         last["name"] if last else "-", f"{last['done']}/{last['planned']}" if last else "-",
                         score(last["best50"]) if last else "-", "TRAINING" if training_processes(model) else "idle"])
        gpu = gpu_stats()
        gpu_line = (f"GPU: {gpu['name']}  |  memory {gpu['used']}/{gpu['total']} MB  |  busy {gpu['util']}%  |  {gpu['temp']} C"
                    if gpu else "GPU: not found")
        show("Home", blocks=(table(["#", "Model", "Pictures (train/val)", "Latest run", "Epochs", "Best mAP50", "Now"], rows),
                             gpu_line))
        options = [(str(i), f"Open {MODELS[m][0]}: {MODELS[m][1]}") for i, m in enumerate(ORDER, 1)]
        choice = ask(options + [("d", "Data tools (report, clean)"), ("q", "Quit (a running training keeps going)")])
        if choice == "q":
            return
        if choice == "d":
            data_screen()
        else:
            model_screen(ORDER[int(choice) - 1])


def model_screen(model: str) -> None:
    name = MODELS[model][0]
    while True:
        runs = model_runs(model)
        training = bool(training_processes(model))
        deployed = deployed_run(model)
        rows = []
        for i, run in enumerate(runs[:5]):
            s = run_summary(run)
            note = ("TRAINING" if training and i == 0 else "") + (" DEPLOYED" if run.name == deployed else "")
            rows.append([s["name"], f"{s['done']}/{s['planned']}", score(s["best50"]), score(s["best5095"]), note.strip() or "-"])
        sizes = table(["Split", "Pictures"], [[s, image_count(model, s)] for s in ("train", "val", "test")])
        latest = run_summary(runs[0]) if runs else None
        goal = f"Goal before deploying: mAP50 {TARGET[model]:.2f}" + (f"   (best so far {score(latest['best50'])})" if latest else "")
        show("Home", name, blocks=(f"{name}: {MODELS[model][1]}", sizes,
                                   table(["Run", "Epochs", "mAP50", "mAP50-95", "Note"], rows) if rows else "No training yet.", goal))
        # a run that reached its planned epochs cannot be resumed: skip the check (it loads torch, which is slow)
        unfinished = bool(latest) and latest["done"] < latest["planned"]
        can_resume = (not training) and unfinished and resumable(runs[0])[0]
        can_deploy = (not training) and bool(runs) and (runs[0] / "weights" / "best.pt").exists()
        options = [("1", "Start a new training")]
        if can_resume:
            options.append(("2", "Resume the stopped run"))
        if training:
            options += [("3", "Watch the live training"), ("4", "Stop the training")]
        if can_deploy:
            options.append(("5", "Export / deploy the best epoch"))
        options += [("6", "Dataset details (objects per class; can take a minute)"), ("b", "Back")]
        choice = ask(options)
        if choice == "b":
            return
        if choice == "1":
            start_screen(model)
        elif choice == "2":
            resume_screen(model, runs[0])
        elif choice == "3":
            watch_screen(model)
        elif choice == "4":
            stop_screen(model)
        elif choice == "5":
            deploy_screen(model, runs[0])
        elif choice == "6":
            dataset_screen(model)


def start_screen(model: str) -> None:
    name = MODELS[model][0]
    others = busy_models()
    if others:
        show("Home", name, "Start", blocks=(f"{MODELS[others[0]][0]} is training right now.",
                                            "Only one training at a time: the GPU has 6 GB."))
        pause_screen()
        return
    if image_count(model, "train") == 0:
        show("Home", name, "Start", blocks=(f"There are no training pictures for {name} yet.",))
        pause_screen()
        return
    # step 1: how long
    show("Home", name, "Start", "Step 1 of 2: how long?", blocks=(f"New {name} training.",))
    rows = [(str(i), f"{p[0]}  -  {p[3]}") for i, p in enumerate(PRESETS, 1)]
    choice = ask(rows + [("c", "Custom: type the number of epochs"), ("b", "Back")])
    if choice == "b":
        return
    if choice == "c":
        epochs, fraction = number("Epochs", 30), 1.0
    else:
        _, epochs, fraction, _ = PRESETS[int(choice) - 1]
    imgsz, batch = defaults(model)
    # step 2: check and start
    while True:
        settings = table(["Setting", "Value"], [
            ["Model", f"{name} ({MODELS[model][1]})"], ["Starts from", CONFIG["base_model"]], ["Epochs", epochs],
            ["Pictures used", f"{fraction * 100:.0f}% of {image_count(model, 'train')}"], ["Image size", imgsz],
            ["Batch", batch], ["Stops early after", f"{CONFIG['patience']} epochs without improvement"]])
        gpu = gpu_stats()
        busy = (f"WARNING: the GPU is busy with something else ({gpu['used']}/{gpu['total']} MB in use, {gpu['util']}% busy). "
                "Starting now can be slow or run out of memory.") if gpu and gpu["used"] > 0.5 * gpu["total"] else ""
        show("Home", name, "Start", "Step 2 of 2: check", blocks=tuple(b for b in (settings, busy) if b))
        choice = ask([("y", "Start now (it keeps running if you close this window)"),
                      ("c", "Change image size / batch"), ("b", "Back")])
        if choice == "b":
            return
        if choice == "c":
            imgsz, batch = int(number("Image size", imgsz)), int(number("Batch (use 8 if the GPU runs out of memory)", batch))
            continue
        break
    proc = start_detached(train_command(model, epochs, imgsz, batch, fraction), f"train_{model}")
    time.sleep(1.0)
    watch_screen(model, since=time.time() - 30, proc=proc)


def resume_screen(model: str, run: Path) -> None:
    ok, message = resumable(run)
    show("Home", MODELS[model][0], "Resume", blocks=(message,))
    if not ok or busy_models():
        pause_screen("Nothing to resume (or another training is running). Press Enter.")
        return
    if confirm("Continue from the last finished epoch? (the unfinished epoch starts again)", "Resume"):
        proc = start_detached(resume_command(sys.executable, model), f"resume_{model}")
        time.sleep(1.0)
        watch_screen(model, since=time.time() - 30, proc=proc)


def stop_screen(model: str) -> None:
    show("Home", MODELS[model][0], "Stop")
    if confirm(f"Stop the {MODELS[model][0]} training? The best weights so far are kept and it can be resumed.", "Stop it"):
        print(f"\nStopped {pause(model)} process(es).")
        pause_screen()


def watch_screen(model: str, since: float | None = None, proc: subprocess.Popen | None = None) -> None:
    """The live training, redrawn every 2 seconds. Any key goes back; the training keeps running."""
    name = MODELS[model][0]
    log = None
    while True:
        procs = training_processes(model)
        if since is None and procs:
            since = min(p.create_time() for p in procs) - 10
        log = find_log(model, since) if since else None
        info = parse_log(tail(log)) if log else {"current": None, "series": [], "val": None}
        runs = model_runs(model)
        latest = run_summary(runs[0]) if runs else None
        running = bool(procs) or (proc is not None and proc.poll() is None)
        cur = info["current"]
        lines = []
        if cur:
            frac = cur["batch"] / cur["batches"] if cur["batches"] else 0
            lines.append(f"Epoch {cur['epoch']}/{cur['epochs']}   [{ascii_bar(frac)}] {frac * 100:.0f}%   "
                         f"batch {cur['batch']}/{cur['batches']}   {cur['speed']}   left {cur['left'] or '?'}")
        elif running:
            lines.append("Starting up: loading the pictures (the first epoch takes a moment to appear)...")
        else:
            lines.append("Nothing is training.")
        state = "TRAINING" if running else "FINISHED / STOPPED"
        blocks = [f"State: {state}", *lines]
        if latest and latest["done"]:
            cols = latest["cols"]
            n = len(cols["epoch"])
            rows = [[int(cols["epoch"][i]), f"{cols['metrics/mAP50(B)'][i]:.3f}", f"{cols['metrics/mAP50-95(B)'][i]:.3f}",
                     f"{cols['metrics/precision(B)'][i]:.3f}", f"{cols['metrics/recall(B)'][i]:.3f}"] for i in range(max(0, n - 6), n)]
            blocks.append(table(["Epoch", "mAP50", "mAP50-95", "Precision", "Recall"], rows))
            blocks.append("\n".join(plain(v) for v in verdict(model, cols)))
        gpu = gpu_stats()
        if gpu:
            blocks.append(f"GPU: memory {gpu['used']}/{gpu['total']} MB  |  busy {gpu['util']}%  |  {gpu['temp']} C")
        blocks.append("Press any key to go back. The training keeps running." if running else "Press any key to go back.")
        show("Home", name, "Live", blocks=tuple(blocks))
        if not running:
            return pause_screen()
        for _ in range(20):
            if key_pressed():
                return
            time.sleep(0.1)


def deploy_screen(model: str, run: Path) -> None:
    s = run_summary(run)
    show("Home", MODELS[model][0], "Export / deploy",
         blocks=(f"Run '{s['name']}': best mAP50 {score(s['best50'])} (goal {TARGET[model]:.2f}).",))
    choice = ask([("1", "Export only: convert to ONNX, the app is NOT changed (test it first)"),
                  ("2", "Deploy: the app uses it as the " + MODELS[model][0] + " model (writes into the backend folder)"),
                  ("b", "Back")],
                 note="After a deploy, restart the backend so it loads the new model.")
    if choice == "b":
        return
    cmd = [sys.executable, str(ROOT / "scripts" / "export_onnx.py"), "--model", model, "--run", run.name]
    run_foreground(cmd + (["--no-deploy"] if choice == "1" else []))


def dataset_screen(model: str) -> None:
    show("Home", MODELS[model][0], "Dataset details", blocks=("Counting objects in every label file (can take a minute)...",))
    stats = dataset_stats(model)
    splits = [s for s in ("train", "val", "test") if s in stats["splits"]]
    rows = [["(pictures)"] + [stats["splits"][s]["images"] for s in splits]]
    rows += [[cls] + [stats["splits"][s]["per_class"][i] for s in splits] for i, cls in enumerate(stats["classes"])]
    show("Home", MODELS[model][0], "Dataset details", blocks=("Objects per class in each split:", table(["Class"] + splits, rows)))
    pause_screen()


def data_screen() -> None:
    while True:
        show("Home", "Data tools", blocks=("Run these only while no training is running.",))
        choice = ask([("1", "Report: write the dataset cards and the catalog"),
                      ("2", "Clean one dataset: move near-duplicate pictures into quarantine"), ("b", "Back")])
        if choice == "b":
            return
        py = [sys.executable, str(ROOT / "data.py")]
        if choice == "1":
            run_foreground(py + ["report"])
            continue
        show("Home", "Data tools", "Clean", blocks=("Which dataset?",))
        rows = [(str(i), MODELS[m][0]) for i, m in enumerate(ORDER, 1)]
        pick = ask(rows + [("b", "Back")])
        if pick == "b":
            continue
        model = ORDER[int(pick) - 1]
        if busy_models():
            print(f"\n{MODELS[busy_models()[0]][0]} is training: wait until it finishes.")
            pause_screen()
        elif confirm(f"Clean the {MODELS[model][0]} dataset? Near-duplicates move to a quarantine folder inside it.", "Clean"):
            run_foreground(py + ["curate", "--model", model, "--apply"])


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description="The Training Lab as a plain menu.")
    ap.add_argument("--model", choices=ORDER, help="open straight on this model (the dashboard button does this)")
    args = ap.parse_args(argv)
    if os.name == "nt":
        os.system("title HULI-KAMOTE Training Lab")
    print("Reading the dataset folders (the first time can take a minute)...")
    try:
        if args.model:
            model_screen(args.model)
        main_screen()
    except KeyboardInterrupt:
        pass
    except Exception:                      # a window that closes by itself hides the error: show it and wait
        traceback.print_exc()
        pause_screen("The Training Lab hit an error (above). Press Enter to close.")
        return
    print("\nBye. A running training keeps going.")


if __name__ == "__main__":
    main()
