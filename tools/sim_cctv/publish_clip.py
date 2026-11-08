"""
publish_clip.py - make this computer behave like a CCTV camera: stream a video clip as RTSP.

Run it on "Laptop B". HULI-KAMOTE (Laptop A) then reads the printed address exactly like it would read a
real IP camera or DVR channel. Needs only ffmpeg (on PATH) and a MediaMTX server (a single exe).

    python publish_clip.py clip.mp4                          # loops the clip forever as rtsp://<this-ip>:8554/cam1
    python publish_clip.py clip.mp4 --path cam2 --fps 12     # second "camera", slower
    python publish_clip.py clip.mp4 --mediamtx C:\\tools\\mediamtx\\mediamtx.exe   # start MediaMTX too

The picture is re-encoded like a typical CCTV channel (H.264, 720p, 15 fps, ~2 Mbit/s) so the compression
artefacts are realistic. Use --height 1080 --bitrate 4M for a better camera. Ctrl+C stops it.
"""
import argparse
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path


def lan_ip() -> str:
    """The address other computers on the network can reach this one at."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("10.255.255.255", 1))     # no packet is sent; it only picks the right network card
        return probe.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        probe.close()


def listening(port: int) -> bool:
    with socket.socket() as s:
        s.settimeout(0.3)
        return s.connect_ex(("127.0.0.1", port)) == 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Stream a clip as an RTSP camera")
    ap.add_argument("clip", help="video file to play")
    ap.add_argument("--path", default="cam1", help="camera name in the address (default cam1)")
    ap.add_argument("--port", type=int, default=8554)
    ap.add_argument("--fps", type=int, default=15)
    ap.add_argument("--height", type=int, default=720)
    ap.add_argument("--bitrate", default="2M")
    ap.add_argument("--once", action="store_true", help="play the clip once instead of looping")
    ap.add_argument("--mediamtx", help="path to mediamtx.exe; started here if nothing listens on the port yet")
    args = ap.parse_args()

    if not shutil.which("ffmpeg"):
        print("ffmpeg not found. Install it (winget install ffmpeg) and open a new terminal.")
        return 1
    if not Path(args.clip).is_file():
        print(f"Clip not found: {args.clip}")
        return 1

    server = None
    if not listening(args.port):
        if not args.mediamtx:
            print(f"Nothing is listening on port {args.port}. Start MediaMTX first, or pass --mediamtx <path to mediamtx.exe>.")
            return 1
        exe = Path(args.mediamtx)
        server = subprocess.Popen([str(exe)], cwd=exe.parent, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(30):
            if listening(args.port):
                break
            time.sleep(0.2)

    url = f"rtsp://127.0.0.1:{args.port}/{args.path}"
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "warning", "-re",
        *([] if args.once else ["-stream_loop", "-1"]),
        "-i", args.clip,
        "-vf", f"scale=-2:{args.height},fps={args.fps}",
        "-c:v", "libx264", "-preset", "veryfast", "-tune", "zerolatency", "-pix_fmt", "yuv420p",
        "-b:v", args.bitrate, "-maxrate", args.bitrate, "-bufsize", "2M", "-g", str(args.fps * 2),
        "-an", "-f", "rtsp", "-rtsp_transport", "tcp", url,
    ]
    print(f"\nStreaming {Path(args.clip).name} as a camera.")
    print(f"  On this computer : rtsp://127.0.0.1:{args.port}/{args.path}")
    print(f"  From other laptops: rtsp://{lan_ip()}:{args.port}/{args.path}   <- put this in HULI-KAMOTE's Camera input")
    print("  (Windows may ask to allow MediaMTX through the firewall: allow it on the private network.)\n  Ctrl+C to stop.\n")
    try:
        return subprocess.call(cmd)
    except KeyboardInterrupt:
        return 0
    finally:
        if server is not None:
            server.terminate()


if __name__ == "__main__":
    sys.exit(main())
