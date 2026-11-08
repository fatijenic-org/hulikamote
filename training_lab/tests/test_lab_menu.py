"""The plain terminal menu (training_lab/lab.py): its tables, the training command it builds, and the screens driven by scripted keys."""
import os
import sys

import torch  # noqa: F401  (import torch before anything loads onnxruntime: a Windows DLL quirk)

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
import lab  # noqa: E402


def drive(monkeypatch, keys, running=None):
    """Replace the keyboard with `keys`, and everything slow or real (disk scans, GPU, processes, the screen clear) with stubs."""
    keys = iter(keys)
    monkeypatch.setattr("builtins.input", lambda *_: next(keys))
    monkeypatch.setattr(lab, "clear", lambda: None)
    monkeypatch.setattr(lab, "image_count", lambda model, split: 120)
    monkeypatch.setattr(lab, "model_runs", lambda model: [])
    monkeypatch.setattr(lab, "gpu_stats", lambda: None)
    monkeypatch.setattr(lab, "deployed_run", lambda model: None)
    monkeypatch.setattr(lab, "training_processes", lambda model: [object()] if model == running else [])
    monkeypatch.setattr(lab.time, "sleep", lambda s: None)


class FakeProc:
    pid = 1

    def poll(self):
        return 0


# --- pieces ----------------------------------------------------------------------------------------------------

def test_table_is_plain_ascii_and_lines_up():
    out = lab.table(["Key", "What"], [["1", "Start"], ["b", "Back to the home screen"]])
    lines = out.splitlines()
    assert len({len(line) for line in lines}) == 1                       # every line is as wide as the border
    assert lines[0] == lines[2] == lines[-1] and set(lines[0]) <= set("+-")
    assert out.isascii() and "| b   | Back to the home screen |" in out


def test_table_without_rows_still_draws():
    assert lab.table(["A", "B"], []).count("+") >= 9


def test_plain_strips_colour_tags_and_symbols():
    text = "[green]✓ Good enough[/] — best 0.9 [yellow]…[/]"
    assert lab.plain(text) == "OK Good enough - best 0.9 ..."


def test_progress_bar_fills_with_hashes():
    assert lab.ascii_bar(0.5, 10) == "#####-----" and lab.ascii_bar(2, 4) == "####" and lab.ascii_bar(-1, 4) == "----"


def test_presets_use_the_training_studios_epochs():
    assert {p[0]: p[1] for p in lab.PRESETS} == {"Test run": 2, "Quick": 30, "Balanced": 100, "Thorough": 200}


def test_vehicles_train_on_whole_frames_and_the_others_on_crops():
    assert lab.defaults("primary_anchor")[0] == 640
    assert {lab.defaults(m)[0] for m in ("helmet_specialist", "plate_specialist", "cabin_specialist")} == {320}


def test_train_command_names_the_model_and_only_adds_fraction_when_it_is_partial():
    full = lab.train_command("primary_anchor", 30, 640, 16)
    assert full[1].endswith("train.py") and full[2:4] == ["--model", "primary_anchor"] and "--fraction" not in full
    assert lab.train_command("primary_anchor", 2, 640, 16, 0.05)[-2:] == ["--fraction", "0.05"]


def test_ask_repeats_until_the_key_is_valid(monkeypatch, capsys):
    keys = iter(["x", "", "B"])
    monkeypatch.setattr("builtins.input", lambda *_: next(keys))
    assert lab.ask([("1", "One"), ("b", "Back")]) == "b"
    assert capsys.readouterr().out.count("Not one of the keys") == 2


def test_number_takes_the_default_on_enter_and_refuses_nonsense(monkeypatch):
    keys = iter(["abc", "-4", "12"])
    monkeypatch.setattr("builtins.input", lambda *_: next(keys))
    assert lab.number("Epochs", 30) == 12
    monkeypatch.setattr("builtins.input", lambda *_: "")
    assert lab.number("Epochs", 30) == 30


# --- screens, driven by keys --------------------------------------------------------------------------------------

def test_home_lists_the_four_models_and_quits(monkeypatch, capsys):
    drive(monkeypatch, ["q"])
    lab.main_screen()
    out = capsys.readouterr().out
    assert "HULI-KAMOTE TRAINING LAB  >  Home" in out
    for name in ("Vehicles", "Helmet", "Plate", "Cabin"):
        assert name in out
    assert out.isascii()


def test_a_model_screen_opens_and_goes_back(monkeypatch, capsys):
    drive(monkeypatch, ["1", "b", "q"])
    lab.main_screen()
    out = capsys.readouterr().out
    assert "Home  >  Vehicles" in out and "No training yet." in out and "Start a new training" in out
    assert "Resume" not in out and "Watch the live training" not in out      # only offered when they apply


def test_starting_a_test_run_launches_one_detached_training(monkeypatch, capsys):
    drive(monkeypatch, ["1", "1", "1", "y", "b", "q"])        # Vehicles > start > Test run > start now > (after watch) back > quit
    launched, watched = [], []
    monkeypatch.setattr(lab, "start_detached", lambda cmd, tag: launched.append((cmd, tag)) or FakeProc())
    monkeypatch.setattr(lab, "watch_screen", lambda *a, **k: watched.append(a))
    lab.main_screen()
    assert len(launched) == 1 and watched == [("primary_anchor",)]        # it opens the live view of that model
    cmd, tag = launched[0]
    assert tag == "train_primary_anchor" and cmd[2:4] == ["--model", "primary_anchor"]
    assert cmd[cmd.index("--epochs") + 1] == "2" and cmd[cmd.index("--fraction") + 1] == "0.05"
    assert cmd[cmd.index("--imgsz") + 1] == "640"


def test_settings_can_be_changed_before_starting(monkeypatch, capsys):
    drive(monkeypatch, ["2", "1", "2", "c", "320", "8", "y", "b", "q"])     # Helmet > start > Quick > change > 320 / 8 > start
    launched = []
    monkeypatch.setattr(lab, "start_detached", lambda cmd, tag: launched.append(cmd) or FakeProc())
    monkeypatch.setattr(lab, "watch_screen", lambda *a, **k: None)
    lab.main_screen()
    cmd = launched[0]
    assert cmd[cmd.index("--epochs") + 1] == "30" and cmd[cmd.index("--imgsz") + 1] == "320" and cmd[cmd.index("--batch") + 1] == "8"
    assert "--fraction" not in cmd


def test_backing_out_of_the_check_step_launches_nothing(monkeypatch):
    drive(monkeypatch, ["1", "1", "2", "b", "b", "q"])
    launched = []
    monkeypatch.setattr(lab, "start_detached", lambda cmd, tag: launched.append(cmd) or FakeProc())
    lab.main_screen()
    assert launched == []


def test_a_second_training_is_refused_while_one_runs(monkeypatch, capsys):
    drive(monkeypatch, ["1", "1", "", "b", "q"], running="helmet_specialist")        # Vehicles > start > (message, Enter)
    launched = []
    monkeypatch.setattr(lab, "start_detached", lambda cmd, tag: launched.append(cmd) or FakeProc())
    lab.main_screen()
    assert launched == []
    assert "Helmet is training right now" in capsys.readouterr().out


def test_no_pictures_means_no_training(monkeypatch, capsys):
    drive(monkeypatch, ["1", "1", "", "b", "q"])
    monkeypatch.setattr(lab, "image_count", lambda model, split: 0)
    launched = []
    monkeypatch.setattr(lab, "start_detached", lambda cmd, tag: launched.append(cmd) or FakeProc())
    lab.main_screen()
    assert launched == [] and "no training pictures" in capsys.readouterr().out


def test_a_running_model_offers_watch_and_stop(monkeypatch, capsys):
    drive(monkeypatch, ["1", "b", "q"], running="primary_anchor")
    lab.main_screen()
    out = capsys.readouterr().out
    assert "TRAINING" in out and "Watch the live training" in out and "Stop the training" in out
    assert "Export / deploy" not in out


class RunningProc:
    pid = 2

    def poll(self):
        return None


def test_watch_draws_the_live_epoch_and_any_key_goes_back(monkeypatch, capsys, tmp_path):
    drive(monkeypatch, [])
    log = tmp_path / "train.log"
    log.write_text("3/30 1.99G 1.106 1.722 1.098 29 640: 50% ---- 150/300 1.8it/s 3:06<1:23\n")
    monkeypatch.setattr(lab, "find_log", lambda model, since: log)
    monkeypatch.setattr(lab, "key_pressed", lambda: True)
    lab.watch_screen("primary_anchor", since=1.0, proc=RunningProc())
    out = capsys.readouterr().out
    assert "State: TRAINING" in out and "Epoch 3/30" in out and "[" + "#" * 15 + "-" * 15 + "]" in out
    assert "batch 150/300" in out and "Press any key to go back. The training keeps running." in out and out.isascii()


def test_watch_says_so_when_nothing_is_training(monkeypatch, capsys):
    drive(monkeypatch, [""])
    lab.watch_screen("primary_anchor")
    assert "Nothing is training." in capsys.readouterr().out


def test_stop_asks_first_and_only_then_stops(monkeypatch, capsys):
    drive(monkeypatch, ["1", "4", "n", "b", "q"], running="primary_anchor")
    stopped = []
    monkeypatch.setattr(lab, "pause", lambda model: stopped.append(model) or 1)
    lab.main_screen()
    assert stopped == []
    drive(monkeypatch, ["1", "4", "y", "", "b", "q"], running="primary_anchor")
    lab.main_screen()
    assert stopped == ["primary_anchor"]


# --- how the dashboard button starts it ------------------------------------------------------------------------

def test_the_menu_can_open_straight_on_a_model(monkeypatch, capsys):
    drive(monkeypatch, ["b", "q"])                                    # the model screen first, Back lands on the home screen
    lab.main(["--model", "plate_specialist"])
    out = capsys.readouterr().out
    assert out.index("Home  >  Plate") < out.index("Pictures (train/val)")
    assert "Bye." in out


def test_an_error_is_shown_and_waited_on_so_the_window_does_not_vanish(monkeypatch, capsys):
    drive(monkeypatch, [])
    prompts = []
    monkeypatch.setattr("builtins.input", lambda prompt="": prompts.append(prompt) or "")     # records what it waits on
    monkeypatch.setattr(lab, "main_screen", lambda: (_ for _ in ()).throw(RuntimeError("boom")))
    lab.main([])
    shown = capsys.readouterr()
    assert "RuntimeError: boom" in shown.err                          # the traceback is printed (to the error stream)
    assert len(prompts) == 1 and "hit an error" in prompts[0] and "Bye." not in shown.out
