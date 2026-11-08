"""
tui_view.py - The "Harvest" tab of the terminal Training Lab (lab_tui.py).

A board (what is waiting, per model) and four buttons. The actual checking and labelling
happens on the web page (pictures need a real picture viewer); this tab only starts it.
Loaded defensively by lab_tui.py: if anything here breaks, the Training Lab still works.
"""
import json
import os
import subprocess
import sys
import time
import webbrowser

import psutil
from rich.text import Text
from textual import work
from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widgets import Button, DataTable, RichLog, Static

from .accept import TrainingBusy
from .config import LAB, MODELS, Paths
from .web import HarvestApp

STEPS = ("[b]The loop:[/] 1 Analyze clips  →  2 Collect  →  3 Check & label (browser)  →  "
         "4 Add to dataset  →  5 Train & deploy  →  test again")


class HarvestPanel(Vertical):
    DEFAULT_CSS = """
    HarvestPanel { padding: 0 1; }
    HarvestPanel #hv_steps { height: auto; margin-bottom: 1; }
    HarvestPanel #hv_table { height: auto; max-height: 9; }
    HarvestPanel #hv_auto { height: auto; margin: 1 0; color: $text-muted; }
    HarvestPanel Horizontal { height: 3; }
    HarvestPanel Button { margin-right: 1; }
    HarvestPanel #hv_log { height: 1fr; border: round $primary; }
    """

    def __init__(self):
        super().__init__()
        self.app_logic = HarvestApp(Paths())
        self._keys: list[str] = []

    def compose(self) -> ComposeResult:
        yield Static(STEPS, id="hv_steps")
        yield DataTable(id="hv_table", cursor_type="row", zebra_stripes=True)
        yield Static(id="hv_auto")
        with Horizontal():
            yield Button("2 Collect new pictures", id="hv_collect", variant="primary")
            yield Button("3 Check & label (opens browser)", id="hv_open", variant="success")
            yield Button("4 Add ready pictures to dataset", id="hv_accept", variant="warning")
        yield RichLog(id="hv_log", wrap=True, markup=True)

    def on_mount(self) -> None:
        table = self.query_one("#hv_table", DataTable)
        table.add_columns("Model", "Needs your eyes", "Ready", "Added so far", "Dataset pictures", "State")
        self.say("Select a model row, then use the buttons. Nothing is added to a dataset without your check.")
        self.set_interval(5.0, self.refresh_board)
        self.refresh_board()

    # ── board ──
    @work(thread=True, exclusive=True, group="hv_board")
    def refresh_board(self) -> None:
        try:
            board = self.app_logic.board()
        except Exception as e:                                    # never take the Training Lab down
            self.app.call_from_thread(self.say, f"[red]Could not read the harvest board: {e}[/]")
            return
        self.app.call_from_thread(self.show_board, board)

    def show_board(self, board: dict) -> None:
        table = self.query_one("#hv_table", DataTable)
        cursor = table.cursor_row
        table.clear()
        self._keys = []
        for m in board["models"]:
            c = m["counts"]
            state = (Text("TRAINING NOW", style="bold yellow") if m["training"]
                     else Text("idle" if m["model_file"] else "no model yet"))
            table.add_row(m["title"], str(c["needs_eyes"]), str(c["ready"]), str(c["accepted"]),
                          f"{m['dataset_images']:,}", state)
            self._keys.append(m["key"])
        if self._keys:
            table.move_cursor(row=min(cursor, len(self._keys) - 1))
        auto = "   ".join(f"{a['title']}: {a['count']:,}/{a['need']:,} {a['unit']} (automatic)"
                          for a in board["automatic"])
        self.query_one("#hv_auto", Static).update(auto)

    def selected_model(self) -> str | None:
        row = self.query_one("#hv_table", DataTable).cursor_row
        return self._keys[row] if 0 <= row < len(self._keys) else None

    def say(self, text: str) -> None:
        self.query_one("#hv_log", RichLog).write(text)

    # ── buttons ──
    def on_button_pressed(self, event: Button.Pressed) -> None:
        bid = event.button.id
        if bid == "hv_collect":
            self.collect()
        elif bid == "hv_open":
            self.open_page()
        elif bid == "hv_accept":
            self.accept_selected()

    @work(thread=True, exclusive=True, group="hv_collect")
    def collect(self) -> None:
        self.app.call_from_thread(self.say, "Collecting... (the model looks at each picture, on the CPU)")
        started = self.app_logic.start_collect()
        if not started.get("running"):
            self.app.call_from_thread(self.say, "[yellow]A collect is already running.[/]")
            return
        while self.app_logic._collect["running"]:
            time.sleep(1)
        result = self.app_logic._collect
        if result.get("error"):
            self.app.call_from_thread(self.say, f"[red]Collect failed: {result['error']}[/]")
            return
        s = result["summary"]
        added = sum(b["check"] + b["label"] for b in s["added"].values())
        self.app.call_from_thread(
            self.say, f"[green]Done.[/] {added} new picture(s) from {s['tickets']} ticket(s); "
                      f"{s['already_have']} were already here; {s['protected_tasks']} benchmark clip(s) skipped.")
        self.refresh_board()

    @work(thread=True, exclusive=True, group="hv_open")
    def open_page(self) -> None:
        info = Paths().inbox / "server.json"

        def running() -> dict | None:
            try:
                data = json.loads(info.read_text())
                # NOT os.kill(pid, 0): on Windows that terminates the process instead of checking it.
                return data if psutil.pid_exists(int(data["pid"])) else None
            except Exception:
                return None

        data = running()
        if data is None:
            flags = (subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP) if os.name == "nt" else 0
            subprocess.Popen([sys.executable, str(LAB / "harvest.py"), "serve", "--no-open"], cwd=LAB,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                             creationflags=flags, start_new_session=os.name != "nt")
            for _ in range(40):
                time.sleep(0.25)
                data = running()
                if data:
                    break
        if data is None:
            self.app.call_from_thread(self.say, "[red]Could not start the page. Try: python training_lab/harvest.py serve[/]")
            return
        webbrowser.open(data["url"])
        self.app.call_from_thread(self.say, f"Opened the page in your browser: {data['url']}")

    @work(thread=True, exclusive=True, group="hv_accept")
    def accept_selected(self) -> None:
        model = self.selected_model()
        if not model:
            return
        title = MODELS[model]["title"]
        try:
            r = self.app_logic.accept(model)
        except TrainingBusy as e:
            self.app.call_from_thread(self.say, f"[yellow]{e}[/]")
            return
        except Exception as e:
            self.app.call_from_thread(self.say, f"[red]Could not add pictures: {e}[/]")
            return
        if not r["ready"]:
            self.app.call_from_thread(self.say, f"{title}: nothing is ready yet. Check & label some pictures first.")
        else:
            self.app.call_from_thread(
                self.say, f"[green]{title}: added {r['added']} picture(s)[/] ({r['train']} for training, "
                          f"{r['val']} for checking). Train the model again to learn from them.")
        self.refresh_board()
