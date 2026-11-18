# HULI-KAMOTE Camera

A small Android app. It makes a phone work like a CCTV camera for HULI-KAMOTE.

- **Live camera**: the phone camera is the source.
- **Gallery video**: a video from the phone gallery is the source. It plays at its own speed and starts again when it ends.
- The app starts broadcasting **by itself** when it is opened, and remembers its last choice (camera or gallery video, quality).
- The phone serves the picture as MJPEG on constant values: port `8080`, `/video` (stream) and `/snapshot.jpg` (one picture).

## Install (once)

Plug the phone in (USB debugging on, only for this step), then in this folder:

```
flutter run --release
```

Or install a built file: `flutter build apk --release`, then `adb install -r build\app\outputs\flutter-apk\app-release.apk`.
The first time, the phone asks to allow the camera: tap Allow.

## Use (nothing to type, nothing to set up)

1. Phone: be on the **same Wi-Fi as the laptop**, or turn on **USB tethering** (or let the laptop use the phone's hotspot).
2. Phone: open **HULI-KAMOTE Camera**. It broadcasts by itself. Keep the screen on.
3. Laptop: start the backend and the dashboard. In **Live Monitor** press **Connect phone**.
   It finds the phone, makes it the camera and starts monitoring. Both modes (live camera, gallery video) work the same way.

Where the laptop looks, in this order (`hulikamote_backend/engine/phone_link.py`): a USB cable link on `127.0.0.1`; the constant
addresses `192.168.42.129` (USB tethering) and `192.168.43.1` (phone hotspot) and the laptop's gateways; every address of the
laptop's own network (the same Wi-Fi); last, a USB cable with USB debugging (`adb forward` and opening the app).

If "Connect phone" does not find it, the dialog says what to do and what was looked at. Check by hand: open
`http://<phone address>:8080/snapshot.jpg` in a browser (the app lists its addresses on its screen).

## Notes

- **Privacy:** the camera listens on the phone's network, so anyone on the same network can open the picture. Use your own Wi-Fi or hotspot.
  The switch "Let the laptop reach the camera over the network" turns it off: then only a USB cable with USB debugging reaches it.
- Quality: Light 480p, Normal 720p, Sharp 1080p (long side), up to 15 / 20 / 25 pictures per second.
- A phone that is too slow skips pictures; the speed on the laptop stays real.
- Android only. Keep the app in front: Android stops camera apps that run in the background. Huawei: Settings, Battery, App launch,
  HULI-KAMOTE Camera, switch off "Manage automatically", allow all three.
- `Connect Phone.bat` (the older USB-cable way) still works.

## Code

| File | Job |
|---|---|
| `lib/home_page.dart`, `lib/camera_bridge.dart` | the screen (starts by itself, remembers its choice), and the link to Kotlin |
| `android/.../MainActivity.kt` | channels, camera permission, gallery picker |
| `android/.../Streamer.kt` | one broadcast: server + camera or video |
| `android/.../CameraFeed.kt`, `VideoFeed.kt` | the two sources (CameraX; MediaCodec) |
| `android/.../Jpeg.kt` | picture to upright JPEG, for both sources |
| `android/.../MjpegServer.kt` | the little web server |
| `connect_usb.ps1`, `Connect Phone.bat` | the older laptop-side USB cable script |
