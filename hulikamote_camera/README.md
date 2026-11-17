# HULI-KAMOTE Camera

A small Android app. It makes a phone work like a CCTV camera for HULI-KAMOTE.

- **Live camera**: the phone camera is the source.
- **Gallery video**: a video from the phone gallery is the source. It plays at its own speed and starts again when it ends.
- The phone serves the picture as MJPEG on port 8080 (`/video`, `/snapshot.jpg`). The USB cable carries it to the laptop (`adb forward`). The Live Monitor reads `http://127.0.0.1:8080/video` like any camera.

## Install (once)

Plug the phone in (USB debugging on), then in this folder:

```
flutter run --release
```

Or install a built file: `flutter build apk --release`, then `adb install -r build\app\outputs\flutter-apk\app-release.apk`.

## Use

1. Phone: open **HULI-KAMOTE Camera**, choose Live camera or Gallery video, press **Start broadcasting**. Keep the screen on.
2. Laptop: start the backend and the dashboard. Double-click **Connect Phone.bat**. It links the cable and makes "Phone (USB)" the Live Monitor's source.
3. Dashboard: Live Monitor, **Start monitoring**. (Press **Set up violations** to draw zones on a frozen frame.)

Run **Connect Phone.bat** again whenever the cable was unplugged. By hand: `adb forward tcp:8080 tcp:8080`, then Live Monitor, Change source, Camera or phone, `http://127.0.0.1:8080/video`.

## Notes

- Private by default: the camera listens on the phone's loopback only, so only the USB cable can reach it. The switch "Also allow Wi-Fi / USB tethering" opens it to the network; the app then shows the addresses.
- Quality: Light 480p, Normal 720p, Sharp 1080p (long side), up to 15 / 20 / 25 pictures per second.
- A phone that is too slow skips pictures; the speed on the laptop stays real.
- Android only. Keep the app in front: Android stops camera apps that run in the background.

## Code

| File | Job |
|---|---|
| `lib/home_page.dart`, `lib/camera_bridge.dart` | the screen, and the link to Kotlin |
| `android/.../MainActivity.kt` | channels, camera permission, gallery picker |
| `android/.../Streamer.kt` | one broadcast: server + camera or video |
| `android/.../CameraFeed.kt`, `VideoFeed.kt` | the two sources (CameraX; MediaCodec) |
| `android/.../Jpeg.kt` | picture to upright JPEG, for both sources |
| `android/.../MjpegServer.kt` | the little web server |
| `connect_usb.ps1`, `Connect Phone.bat` | laptop side: adb forward + Live Monitor source |
