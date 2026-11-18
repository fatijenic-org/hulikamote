"""
phone_link.py - find the HULI-KAMOTE Camera phone app and make it the Live Monitor's camera, with no address typed.

The app (hulikamote_camera/) broadcasts by itself when it is opened, on the network, on constant values:
    http://<phone>:8080/video        (MJPEG)        http://<phone>:8080/snapshot.jpg   (one picture)
So the laptop only has to FIND the phone. In this order, the first answer wins:
  1. 127.0.0.1           a USB cable with `adb forward` already in place
  2. constant addresses  USB tethering (the phone is 192.168.42.129) and the phone's own hotspot (192.168.43.1), then every
                         gateway this laptop has (a tethered / hotspot phone is the laptop's gateway, whatever its range)
  3. the same Wi-Fi      every address of the laptop's own networks (a quick look at port 8080)
  4. a USB cable with USB debugging: `adb forward`, open the app, look at 127.0.0.1 again
Nothing here changes the phone or the laptop's network. adb is only used in step 4, and only with fixed arguments.
"""
import ipaddress
import os
import re
import shutil
import socket
import subprocess
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

PORT = 8080
VIDEO_PATH = "/video"
SNAPSHOT_PATH = "/snapshot.jpg"
KNOWN_PHONE_ADDRESSES = ("192.168.42.129", "192.168.43.1")   # Android USB tethering, Android hotspot (the usual constants)
APP_PACKAGE = "com.hulikamote.hulikamote_camera"
APP_ACTIVITY = f"{APP_PACKAGE}/{APP_PACKAGE}.MainActivity"
WAIT_AFTER_ADB_S = 20.0            # the phone app needs a moment to open and start its camera
SCAN_WORKERS = 64
MAX_SUBNETS = 4
_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)       # Windows: no black console window

_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))   # a phone on the LAN never goes through a proxy


# ── looking at one address ────────────────────────────────────────────────────

def video_url(host: str, port: int = PORT) -> str:
    return f"http://{host}:{port}{VIDEO_PATH}"


def is_camera(host: str, port: int = PORT, timeout: float = 1.5) -> bool:
    """True when the phone app answers at this address with a picture (it only answers while it broadcasts)."""
    try:
        with _opener.open(f"http://{host}:{port}{SNAPSHOT_PATH}", timeout=timeout) as response:
            return response.status == 200 and response.read(2) == b"\xff\xd8"
    except Exception:
        return False


def _port_open(host: str, port: int, timeout: float) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


# ── where to look ─────────────────────────────────────────────────────────────

def default_gateways() -> list[str]:
    """The gateways of this laptop's networks (a tethered or hotspot phone is one of them). [] when they cannot be read."""
    try:
        if os.name == "nt":
            text = subprocess.run(["route", "print", "-4"], capture_output=True, text=True, timeout=6, creationflags=_NO_WINDOW).stdout
            found = re.findall(r"^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+(\d+\.\d+\.\d+\.\d+)\s", text, re.MULTILINE)
        else:
            text = subprocess.run(["ip", "route"], capture_output=True, text=True, timeout=6).stdout
            found = re.findall(r"^default via (\d+\.\d+\.\d+\.\d+)", text, re.MULTILINE)
    except Exception:
        return []
    return list(dict.fromkeys(found))


def local_subnets() -> list[tuple[ipaddress.IPv4Network, str]]:
    """The private networks this laptop is on, as (network, own address). A network larger than a /24 is cut down to the /24
    around the laptop, so one look never means thousands of addresses."""
    import psutil
    seen: dict = {}
    for addrs in psutil.net_if_addrs().values():
        for a in addrs:
            if a.family != socket.AF_INET or not a.netmask:
                continue
            try:
                iface = ipaddress.ip_interface(f"{a.address}/{a.netmask}")
            except ValueError:
                continue
            ip = iface.ip
            if ip.is_loopback or ip.is_link_local or not ip.is_private:
                continue
            network = iface.network if iface.network.prefixlen >= 24 else ipaddress.ip_network(f"{ip}/24", strict=False)
            if network.prefixlen > 30:
                continue
            seen[network] = str(ip)
    return list(seen.items())[:MAX_SUBNETS]


def scan_network(network: ipaddress.IPv4Network, own: str, port: int = PORT, timeout: float = 0.5,
                 port_open=_port_open, camera=is_camera) -> str | None:
    """The first address of `network` (besides the laptop's own) where the phone app answers, or None."""
    hosts = [str(h) for h in network.hosts() if str(h) != own]
    with ThreadPoolExecutor(max_workers=SCAN_WORKERS) as pool:
        opened = [h for h, ok in zip(hosts, pool.map(lambda h: port_open(h, port, timeout), hosts)) if ok]
    return next((h for h in opened if camera(h, port)), None)


# ── adb (step 4) ──────────────────────────────────────────────────────────────

def find_adb(env=None, which=shutil.which, exists=os.path.exists) -> str | None:
    env = os.environ if env is None else env
    exe = "adb.exe" if os.name == "nt" else "adb"
    places = [which("adb")]
    for var in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        if env.get(var):
            places.append(os.path.join(env[var], "platform-tools", exe))
    if env.get("LOCALAPPDATA"):
        places.append(os.path.join(env["LOCALAPPDATA"], "Android", "Sdk", "platform-tools", exe))
    return next((p for p in places if p and exists(p)), None)


def _adb(adb: str, *args: str, timeout: float = 12.0) -> tuple[int, str]:
    try:
        done = subprocess.run([adb, *args], capture_output=True, text=True, timeout=timeout, creationflags=_NO_WINDOW)
        return done.returncode, (done.stdout or "") + (done.stderr or "")
    except Exception as e:
        return 1, str(e)


def parse_devices(text: str) -> tuple[list[str], list[str]]:
    """`adb devices` output -> (ready serials, serials that still wait for 'Allow' on the phone)."""
    ready, waiting = [], []
    for line in text.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2:
            (ready if parts[1] == "device" else waiting if parts[1] == "unauthorized" else []).append(parts[0])
    return ready, waiting


# ── the one call ──────────────────────────────────────────────────────────────

def connect(port: int = PORT, *, camera=is_camera, gateways=default_gateways, subnets=local_subnets, scan=scan_network,
            adb_path=find_adb, adb_run=_adb, wait_s: float = WAIT_AFTER_ADB_S, sleep=time.sleep, now=time.monotonic) -> dict:
    """Find the phone. {"ok": True, "via": "usb" | "tethering" | "wifi", "host", "url", "message", "steps"} or
    {"ok": False, "message", "steps"}. `steps` = [{"text", "ok"}] for the dashboard to show what was looked at."""
    steps: list[dict] = []

    def done(via: str, host: str, text: str) -> dict:
        steps.append({"text": text, "ok": True})
        return {"ok": True, "via": via, "host": host, "url": video_url(host, port), "message": text, "steps": steps}

    # 1. a USB link that is already in place
    if camera("127.0.0.1", port):
        return done("usb", "127.0.0.1", "Phone found through the USB cable.")
    steps.append({"text": "USB cable link: no phone yet", "ok": False})

    # 2. the constant addresses of tethering and hotspot, then every gateway of this laptop
    candidates = list(dict.fromkeys([*KNOWN_PHONE_ADDRESSES, *gateways()]))
    with ThreadPoolExecutor(max_workers=max(1, len(candidates))) as pool:
        answers = list(pool.map(lambda h: camera(h, port), candidates))
    for host, ok in zip(candidates, answers):
        if ok:
            return done("tethering", host, f"Phone found over USB tethering or its hotspot ({host}).")
    steps.append({"text": "USB tethering / phone hotspot: no phone", "ok": False})

    # 3. the same Wi-Fi: look at every address of the laptop's own networks
    for network, own in subnets():
        host = scan(network, own, port)
        if host:
            return done("wifi", host, f"Phone found on the same network ({host}).")
    steps.append({"text": "Same Wi-Fi network: no phone", "ok": False})

    # 4. a USB cable with USB debugging: adb makes the phone's port the laptop's port, and opens the app
    adb = adb_path()
    waiting: list[str] = []
    if adb:
        adb_run(adb, "start-server")
        ready, waiting = parse_devices(adb_run(adb, "devices")[1])
        if ready:
            serial = ready[0]
            adb_run(adb, "-s", serial, "forward", f"tcp:{port}", f"tcp:{port}")
            adb_run(adb, "-s", serial, "shell", "am", "start", "-n", APP_ACTIVITY)
            deadline = now() + wait_s
            while now() < deadline:
                if camera("127.0.0.1", port):
                    return done("usb", "127.0.0.1", "Phone found through the USB cable (USB debugging).")
                sleep(1.0)
            steps.append({"text": "USB debugging: the phone is linked, but its app is not broadcasting", "ok": False})
        else:
            steps.append({"text": "USB debugging: no phone found" if not waiting else "USB debugging: the phone waits for Allow", "ok": False})
    else:
        steps.append({"text": "USB debugging: adb is not installed on this laptop (not needed for Wi-Fi or tethering)", "ok": False})

    if waiting:
        message = "The phone asks to allow this laptop. Look at the phone screen, tap Allow, then press Connect phone again."
    else:
        message = ("No phone found. 1) Open HULI-KAMOTE Camera on the phone: it starts by itself. "
                   "2) Put the phone and this laptop on the same Wi-Fi, or turn on USB tethering. 3) Press Connect phone again.")
    return {"ok": False, "message": message, "steps": steps}
