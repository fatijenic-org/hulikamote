"""engine/phone_link.py - the laptop finds the phone app by itself: constant addresses, the same Wi-Fi, a USB cable."""
import ipaddress

from engine import phone_link as pl

NET = ipaddress.ip_network("192.168.1.0/24")


def run(camera_at=(), gateways=(), found_on_wifi=None, adb=None, devices="List of devices attached\n", cable_after=None, **extra):
    """connect() with everything outside the code replaced: `camera_at` = the addresses where the app answers."""
    calls = []
    clock = {"t": 0.0}

    def camera(host, port=pl.PORT, timeout=1.5):
        calls.append(("camera", host))
        if host == "127.0.0.1" and cable_after is not None and clock["t"] >= cable_after:
            return True
        return host in camera_at

    def adb_run(adb_path, *args, **kw):
        calls.append(("adb", *args))
        return (0, devices) if args and args[0] == "devices" else (0, "")

    def scan(network, own, port=pl.PORT):
        calls.append(("scan", str(network)))
        return found_on_wifi

    def sleep(seconds):
        clock["t"] += seconds

    result = pl.connect(
        camera=camera, gateways=lambda: list(gateways), subnets=lambda: [(NET, "192.168.1.5")], scan=scan,
        adb_path=lambda: adb, adb_run=adb_run, wait_s=5, sleep=sleep, now=lambda: clock["t"], **extra,
    )
    return result, calls


def test_a_usb_link_that_is_already_in_place_is_used_first():
    result, calls = run(camera_at={"127.0.0.1"})
    assert result["ok"] and result["via"] == "usb" and result["url"] == "http://127.0.0.1:8080/video"
    assert [c for c in calls if c[0] == "scan"] == []


def test_usb_tethering_is_found_at_its_constant_address_without_scanning():
    result, calls = run(camera_at={"192.168.42.129"})
    assert result["ok"] and result["via"] == "tethering" and result["url"] == "http://192.168.42.129:8080/video"
    assert [c for c in calls if c[0] == "scan"] == []


def test_the_phones_own_hotspot_constant_and_the_laptops_gateways_are_looked_at():
    assert run(camera_at={"192.168.43.1"})[0]["host"] == "192.168.43.1"
    assert run(camera_at={"10.20.30.1"}, gateways=["10.20.30.1"])[0]["host"] == "10.20.30.1"


def test_a_phone_on_the_same_wifi_is_found_by_looking_at_the_laptops_own_network():
    result, calls = run(found_on_wifi="192.168.1.77")
    assert result["ok"] and result["via"] == "wifi" and result["url"] == "http://192.168.1.77:8080/video"
    assert ("scan", "192.168.1.0/24") in calls


def test_a_usb_cable_with_debugging_forwards_the_port_opens_the_app_and_waits_for_the_picture():
    result, calls = run(adb="adb", devices="List of devices attached\nABC123\tdevice\n", cable_after=2)
    assert result["ok"] and result["via"] == "usb"
    assert ("adb", "-s", "ABC123", "forward", "tcp:8080", "tcp:8080") in calls
    assert ("adb", "-s", "ABC123", "shell", "am", "start", "-n", pl.APP_ACTIVITY) in calls


def test_nothing_found_says_what_to_do_in_plain_words():
    result, _ = run()
    assert not result["ok"] and "same Wi-Fi" in result["message"] and "tethering" in result["message"]
    assert all(not s["ok"] for s in result["steps"]) and len(result["steps"]) >= 3


def test_a_phone_that_waits_for_allow_is_told_so():
    result, _ = run(adb="adb", devices="List of devices attached\nABC123\tunauthorized\n")
    assert not result["ok"] and "Allow" in result["message"]


def test_a_linked_phone_whose_app_never_broadcasts_is_a_failure_with_a_clear_step():
    result, _ = run(adb="adb", devices="List of devices attached\nABC123\tdevice\n")
    assert not result["ok"] and any("not broadcasting" in s["text"] for s in result["steps"])


def test_parse_devices_separates_ready_and_waiting_phones():
    ready, waiting = pl.parse_devices("List of devices attached\nA\tdevice\nB\tunauthorized\nC\toffline\n\n")
    assert ready == ["A"] and waiting == ["B"]


def test_scan_network_skips_the_laptop_and_only_trusts_a_real_camera():
    seen = []
    host = pl.scan_network(
        NET, "192.168.1.5",
        port_open=lambda h, p, t: seen.append(h) or h in {"192.168.1.5", "192.168.1.9", "192.168.1.40"},
        camera=lambda h, p: h == "192.168.1.40",            # .9 has the port open but is not the phone app
    )
    assert host == "192.168.1.40" and "192.168.1.5" not in seen and len(seen) == 253


def test_find_adb_looks_in_the_usual_places(tmp_path):
    exe = "adb.exe" if pl.os.name == "nt" else "adb"
    tools = tmp_path / "Android" / "Sdk" / "platform-tools"
    tools.mkdir(parents=True)
    (tools / exe).write_text("x")
    assert pl.find_adb(env={"LOCALAPPDATA": str(tmp_path)}, which=lambda name: None) == str(tools / exe)
    assert pl.find_adb(env={}, which=lambda name: None, exists=lambda p: False) is None
