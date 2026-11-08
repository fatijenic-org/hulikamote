# Simulated CCTV (for the defense and for testing live mode)

HULI-KAMOTE reads its camera as an **address**. A real CCTV / DVR channel, a phone camera app and a second
laptop playing a clip all give an `rtsp://...` address, so to the system they are the same thing.
We have no CCTV, so we feed it one of the others. Only the address changes when a real camera is available.

| Camera input profile | Address looks like |
|---|---|
| CCTV / DVR (when present) | `rtsp://user:password@<dvr-ip>:554/<channel path>` (see the DVR's manual) |
| Phone camera | `rtsp://<phone-ip>:<port>/<path>` shown by an RTSP camera app (Android), or `http://<phone-ip>:<port>/video` |
| Laptop B (clip as a camera) | `rtsp://<laptop-b-ip>:8554/cam1` (printed by `publish_clip.py`) |
| File | `C:\clips\test.mp4` (last fallback) |

## Laptop B: play a clip as a camera
Needs `ffmpeg` on PATH and `mediamtx.exe` (already in `hulikamote_backend/tools/mediamtx/`, or download from
github.com/bluenviron/mediamtx/releases).

```
python publish_clip.py clip.mp4 --mediamtx C:\path\to\mediamtx.exe
```
It prints the address for Laptop A. Windows asks once to allow MediaMTX through the firewall: allow it on the
**private** network. Re-encoding is CCTV-like (H.264, 720p, 15 fps, ~2 Mbit/s); change with `--height`, `--fps`, `--bitrate`.

## Phone: a real camera device
Install an Android RTSP camera app, start it, copy the address it shows. Point the phone at Laptop B's screen
(playing the clip) or at a real road. Expect glare / moire from a screen: use the clean Laptop B stream to show
accuracy and the phone to show a real device.

## Network
Put both laptops (and the phone) on **your own phone hotspot or router**, not venue Wi-Fi (it often isolates devices).
Check from Laptop A first: `ffplay rtsp://<address>` or the **Test** button in Live Monitor > Camera input.

## What the system does with it
- keeps only the newest frame (no lag build-up if the AI is slower than the camera), shows live FPS and lag
- reconnects by itself if the stream drops (1, 2, 4, 8 s), and shows OFFLINE meanwhile
- never shows or logs the password of an address
