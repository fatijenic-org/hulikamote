"""Page 6: how a camera's picture gets into HULI-KAMOTE, from first principles to the exact code."""
from __future__ import annotations

from lib import Page, arrow, box, callout, chip, cmd, code, figure, ref, span, steps, svg, table, tests_info

CAM = "hulikamote_backend/engine/camera_source.py"
HLS = "hulikamote_backend/engine/hls_broadcaster.py"
SETTINGS = "hulikamote_backend/routers/settings.py"
STREAM = "hulikamote_backend/routers/stream.py"
SCREEN = "hulikamote_dashboard/lib/features/monitoring/presentation/screens/live_monitoring_screen.dart"
SIM = "tools/sim_cctv/publish_clip.py"


def _path() -> str:
    parts = [
        box(0, 20, 132, 84, ["1 The camera", "CCTV, phone", "or a clip"], "c1"),
        box(157, 20, 132, 84, ["2 The address", "rtsp:// http://", "or a file"], "c2"),
        box(314, 20, 132, 84, ["3 CameraSource", "keeps only the", "newest picture"], "c3"),
        box(471, 20, 132, 84, ["4 The AI", "finds vehicles and", "violations"], "c4"),
        box(628, 20, 132, 84, ["5 The dashboard", "picture and", "tickets"], "c7"),
        arrow(132, 62, 157, 62), arrow(289, 62, 314, 62), arrow(446, 62, 471, 62), arrow(603, 62, 628, 62),
    ]
    return svg(760, 124, "".join(parts), "Five steps from the camera to the dashboard")


def build() -> Page:
    p = Page("6-live-camera.html", "6", "Live camera: how the picture gets in",
             "From the first idea (what a camera really sends) to the exact code that connects it to HULI-KAMOTE, "
             "and how we know it is working. Every code box is the real source file; Open in VS Code jumps to the line.")

    # ── 1 first principles ───────────────────────────────────────────────────
    p.h2("idea", "Start here: what a camera really sends", kicker="First principles", newpage=False)
    p.add("<p>A video is not a special thing. It is many still pictures, called [[frame|frames]], shown one after the other, "
          "about 25 every second. A <b>network camera</b> takes those pictures and sends them over the network to anyone who asks. "
          "Sending them while they are being filmed, instead of saving a file, is called a [[stream]].</p>")
    p.add("<p>To ask for a stream you need only one thing: <b>where the camera is</b>. That is its address, made of an "
          "[[IP address|IP address]], a [[port]] and a path, for example <code>rtsp://192.168.1.20:554/stream1</code>. "
          "HULI-KAMOTE is the one asking. So from our side, a CCTV camera, a phone and a laptop playing a clip are the same thing: "
          "<b>an address that gives back pictures</b>.</p>")
    p.add(table(["Idea", "What it means for the system"], [
        ["The camera only sends pictures", "We never control the camera (no turning or zooming). We only read."],
        ["It is addressed, like a website", "Only the address changes when a real CCTV replaces our stand-in. The rest of the system does not change."],
        ["The network can fail", "Cameras get switched off and Wi-Fi drops. The system must notice, say so in words, and reconnect by itself."],
        ["The AI can be slower than the camera", "If the AI needs more time than 40 ms per frame, old frames pile up and the picture falls behind. We keep only the newest."],
    ], "dense", ["34%", "66%"]))
    p.add(figure(_path(), "<b>The whole path in five steps.</b> Steps 1 and 2 are the outside world; steps 3 to 5 are our code, explained below."))
    p.end()

    # ── 2 the address ───────────────────────────────────────────────────────
    p.h2("address", "Step 2: the address, and which setups we accept", kicker="How CCTV hands out its picture")
    p.add("<p>CCTV systems from different makers all end up giving you one of a few kinds of address. We looked up the common ones "
          "and made the Live Monitor accept them. The right-hand column is honest about what we have and have not tried.</p>")
    p.add(table(["Setup", "Looks like", "What the sources say", "In our system"], [
        ["<b>[[RTSP]]</b>: the standard way cameras and recorders stream", "<code>rtsp://user:pass@192.168.1.20:554/path</code>",
         "An IETF standard, <a href='https://www.rfc-editor.org/rfc/rfc7826.html'>RFC 7826</a>. The viewer can choose UDP, multicast or TCP delivery.",
         chip("ok", "Accepted") + " TCP, 5 s timeouts, reconnects"],
        ["<b>[[ONVIF]] cameras</b>: the vendor-neutral standard", "The camera offers an RTSP address",
         "<a href='https://www.onvif.org/profiles/profile-s/'>Profile S</a> covers live video over RTSP; "
         "<a href='https://ipvm.com/reports/1182'>IPVM review</a>.",
         chip("ok", "Accepted") + " by RTSP address; " + chip("warn", "No auto-discovery")],
        ["<b>Hikvision</b> recorders and cameras", "<code>/Streaming/Channels/101</code> (channel 1 main), <code>102</code> (sub), <code>1701</code> (channel 17)",
         "<a href='https://supportusa.hikvision.com/support/solutions/articles/17000129024-do-you-have-an-example-showing-the-format-for-getting-a-rtsp-stream-from-a-nvr-dvr-'>Hikvision support page</a>; "
         "<a href='https://www.smartrtsp.com/guides/rtsp-url-list'>list of RTSP URLs</a>.",
         chip("ok", "Accepted") + " paste the address"],
        ["<b>Dahua</b> recorders and cameras", "<code>/cam/realmonitor?channel=1&amp;subtype=0</code> (0 main, 1 sub)",
         "<a href='https://securitycamcenter.com/rtsp-url-address-format-dahua/'>Dahua RTSP format</a>.",
         chip("ok", "Accepted") + " paste the address"],
        ["<b>[[MJPEG]] over HTTP</b>: older cameras, many phone apps", "<code>http://192.168.1.5:8080/video</code>",
         "<a href='https://bensoftware.com/blog/comparison-of-streaming-formats'>Comparison of streaming formats</a>.",
         chip("info", "Accepted, not tested") + " snapshot-only URLs are not supported"],
        ["<b>RTMP / UDP</b> streams", "<code>rtmp://...</code>, <code>udp://...</code>", "Streaming apps.",
         chip("info", "Accepted, not tested")],
        ["<b>Webcam or video file</b>", "<code>0</code>, <code>C:\\clips\\test.mp4</code>", "Plain input.", chip("ok", "Works") + " the main tested path"],
    ], "dense", ["20%", "22%", "34%", "24%"]))
    p.add(callout("info", "About these sources",
                  "<p>The Hikvision and Dahua paths agree across vendor and installer pages, but many are third-party, and ports and paths can differ by model and "
                  "firmware, so the camera's own manual decides. The sources also disagree on which video format ONVIF Profile S makes mandatory, so read the ONVIF "
                  "specification itself before quoting that detail.</p>"))
    p.add("<h4>Where the system decides what an address means</h4>"
          "<p>One small function, " + ref(CAM, "parse_source") + ", looks at the text and decides: a webcam number, a stream address, or a file. "
          "It refuses anything else, so a typed address can never be used to make the system open something it should not.</p>")
    p.add(code(CAM, "parse_source", title="What an address means", walk=[
        ("isdigit()", "A plain number such as 0 means a webcam plugged into this computer."),
        ('re.match(r"^([a-zA-Z]', "Something like rtsp:// or http:// means a stream. The part before the // is the kind."),
        ("if scheme not in STREAM_SCHEMES", "Only rtsp, rtsps, http, https, rtmp and udp are allowed. Any other kind is refused."),
        ("mask_url(text)", "The label shown on screen hides the password: user:***@address."),
        ("concat:", "A trick some video tools understand (joining or piping files) is refused on purpose."),
        ('return SourceSpec("file"', "Anything left is a video file on this computer."),
    ]))
    p.end()

    # ── 3 reading the picture ───────────────────────────────────────────────
    p.h2("read", "Step 3: reading the picture without falling behind", kicker="CameraSource")
    p.add("<p>" + ref(CAM, "CameraSource", label="CameraSource") + " is the part that talks to the camera. It has three jobs, "
          "and each one answers a problem from the first section.</p>")
    p.add(steps([
        "<b>Do not wait forever.</b> Connecting to a dead address must give up after a few seconds, and tell the user.",
        "<b>Ask for the safe, low-delay way.</b> Video over UDP can lose pieces on Wi-Fi and smear the picture, so we ask for TCP and for no buffering.",
        "<b>Keep only the newest picture.</b> A reader thread keeps taking pictures from the camera. When the AI is ready, it gets the latest one; older ones are dropped. Lag cannot pile up.",
        "<b>Reconnect by itself.</b> If the stream drops, wait 1, 2, 4, 8 seconds and try again, and show OFFLINE meanwhile.",
    ]))
    p.add(code(CAM, lines=span(CAM, "OPEN_TIMEOUT_MS = 5000", end_text="STREAM_SCHEMES"), title="The settings that make it safe", walk=[
        ("OPEN_TIMEOUT_MS = 5000", "Wait at most 5 seconds to connect."),
        ("READ_TIMEOUT_MS = 5000", "Wait at most 5 seconds for the next picture."),
        ("RETRY_DELAYS_S", "After a drop, retry after 1, 2, 4, then every 8 seconds."),
        ("FFMPEG_OPTIONS", "Ask for TCP (no smeared pictures) and low delay (show pictures as they arrive)."),
    ]))
    p.add(code(CAM, "CameraSource._run", title="The reader loop: connect, read, reconnect", walk=[
        ("cap = self._open()", "Try to connect to the camera."),
        ("self._retry_delays[min(attempt", "Could not connect: wait a little longer each time, then try again."),
        ("ok, image = cap.read()", "Take the next picture from the camera."),
        ("self._publish(image)", "Hand it over as the newest picture."),
        ("self.reconnects += 1", "The stream dropped: count it, show OFFLINE, and go round again."),
    ]))
    p.add(code(CAM, "CameraSource._publish", title="Keeping only the newest picture", walk=[
        ("self.dropped += 1", "Nobody took the previous picture, so it is old now. Count it as dropped."),
        ("self._latest = Frame(image, arrived)", "Replace it with the new one, stamped with the time it arrived. That stamp gives the lag number on screen."),
        ("self._cond.notify_all()", "Wake the AI if it was waiting for a picture."),
    ]))
    t = tests_info(CAM) or {}
    p.add(callout("ok", "How this is tested",
                  f"<p>{t.get('tests', 0)} automated tests cover this file, using a scripted fake camera (no network needed). They check what an address means, "
                  "that the newest picture wins, that a silent camera gives up, that a dropped stream reconnects, and that stopping never releases a camera that is "
                  "still being read.</p>"))
    p.end()

    # ── 4 AI to screen ──────────────────────────────────────────────────────
    p.h2("show", "Steps 4 and 5: from the AI to your screen", kicker="The relay")
    p.add("<p>The AI loop is in " + ref(STREAM, "_real_loop") + ". For each picture it finds vehicles and runs the violation rules. "
          "The dashboard then needs two things: the data (boxes, tickets) and the picture. There are two ways to send the picture, chosen by "
          "<code>HK_PICTURE_MODE</code>:</p>")
    p.add(table(["Mode", "How the picture travels", "Good for", "Watch out"], [
        ["<b>synced</b> (default)", "A small JPEG inside the <b>same message</b> as the boxes", "Boxes that sit exactly on the vehicles. No encoder and no relay to go wrong.", "A bit more network and CPU per picture (fine on one computer)"],
        ["<b>relay</b>", "[[FFmpeg]] compresses it ([[H.264]]) and sends it through [[MediaMTX]]", "Smooth video that also works for other viewers", "The picture arrives later than the boxes, so the dashboard has to delay the boxes by eye"],
    ], "dense", ["16%", "30%", "30%", "24%"]))
    p.add(callout("info", "Why synced is the default",
                  "<p>We first used only the relay. The picture took the longer way (encoder, relay, player) and showed up two seconds or more after the boxes, "
                  "so the boxes ran ahead of the vehicles, and no fixed delay could cure it. Putting the picture in the same message makes it impossible for them to disagree.</p>"))
    p.add("<p>The rest of this section is about the <b>relay</b> mode.</p>")
    p.add("<p>In relay mode, without the relay there is no picture, so the backend starts it by itself when it is installed in "
          "<code>hulikamote_backend/tools/mediamtx</code>.</p>")
    p.add(code(HLS, "server_status", title="Making sure the relay is running", walk=[
        ("if _port_open():", "Is something already listening on the video port? Then there is nothing to do."),
        ('exe = MEDIAMTX_DIR / "mediamtx.exe"', "Look for the program in our tools folder. If it is missing, say exactly where it belongs."),
        ("subprocess.Popen(", "Start it, hidden, with its own settings file."),
        ("deadline = time.time() + wait_s", "Wait up to a few seconds until it answers. If it never does, report that instead of pretending."),
    ]))
    p.add(callout("warn", "A real bug we found and fixed (worth telling the panel)",
                  "<p>When the relay was <b>not</b> running, the encoder could not send anywhere and stopped reading. The backend kept writing pictures into it, "
                  "the pipe filled up, and the <b>whole backend froze</b>: uploads and Start hung for ever. The fix has two parts: pictures are handed to a separate "
                  "writer thread through a small queue that <b>drops</b> pictures when it is full, and stopping <b>kills</b> the encoder first instead of waiting on it. "
                  "An automated test makes a deliberately stuck encoder and checks that nothing blocks.</p>"))
    p.add(code(HLS, "HLSBroadcaster._write_loop", title="Only this thread can ever get stuck on the encoder", walk=[
        ("data = frames.get()", "Take the next waiting picture from the queue."),
        ("proc.stdin.write(data)", "Write it to the encoder. This is the call that can block, so it runs in its own thread."),
        ("self._started = False", "If the encoder is gone, mark it stopped and quit this thread."),
    ]))
    p.add(code(HLS, "HLSBroadcaster.stop", title="Stopping never waits on a stuck encoder", walk=[
        ("proc.kill()", "Kill the encoder first. Closing a pipe that nobody reads from would wait for ever."),
        ("proc.stdin.close()", "Only now close the pipe; it cannot block any more."),
        ("writer.join(timeout=1)", "Give the writer thread one second to finish, then move on."),
    ]))
    p.end()

    # ── 5 the dashboard ─────────────────────────────────────────────────────
    p.h2("dash", "How the Live Monitor makes sure it works", kicker="The dashboard side")
    p.add("<p>A frozen or missing part used to look like endless loading. Now the screen checks before it starts and says what is wrong, in words:</p>")
    p.add(table(["What is wrong", "What the screen says", "What to do"], [
        ["The backend is stopped or frozen", "The backend is not answering. Restart it, then press Try again.", "Restart the backend"],
        ["The video relay is missing", "The video relay (MediaMTX) is not running... Then press Try again.", "Install or start MediaMTX"],
        ["Connected, but no picture in 12 seconds", "Connected, but no picture yet. Check the source with Change source.", "Pick another source or check the camera"],
    ], "dense", ["30%", "46%", "24%"]))
    a, b = span(SCREEN, "Future<bool> _loadSource() async {", end_text="/// Why the video relay")
    p.add(code(SCREEN, lines=(a, b - 1), lang="dart", title="The check that runs when the screen opens and when you press Start", walk=[
        ("/settings/camera-config", "Ask the backend which source it uses. Give it 4 seconds."),
        ("problem = await _relayProblem();", "Then ask whether the video relay is ready."),
        ("problem = _backendDown;", "Any failure becomes one plain sentence."),
        ("return problem == null;", "Start only continues when everything is ready."),
    ]))
    p.end()

    # ── 6 try it ────────────────────────────────────────────────────────────
    p.h2("try", "How to try it without a real CCTV", kicker="Demonstration")
    p.add("<p>" + ref(SIM, label="publish_clip.py") + " plays a video clip as if it were a camera, with the same kind of address a real one gives. "
          "Run it on the same laptop, or on a second laptop on the same hotspot.</p>")
    p.add(cmd("hulikamote_backend\\venv\\Scripts\\python.exe tools\\sim_cctv\\publish_clip.py C:\\path\\to\\clip.mp4 --mediamtx hulikamote_backend\\tools\\mediamtx\\mediamtx.exe"))
    p.add(steps([
        "Copy the address it prints (like <code>rtsp://192.168.1.20:8554/cam1</code>).",
        "In the Live Monitor choose <b>Change source</b>, then <b>Camera or phone...</b>, and paste it.",
        "Press <b>Test</b>. It reports the picture size, speed and time to the first picture. The code is " + ref(SETTINGS, "test_video_source") + ".",
        "Press <b>Use this camera</b>, then <b>Start monitoring</b>.",
    ]))
    p.add("<p>A phone works the same way: install an Android RTSP camera app, start it, and paste the address it shows. "
          "Use your own phone hotspot or router, not venue Wi-Fi, which often stops devices from seeing each other.</p>")
    p.end()

    # ── 7 limits ────────────────────────────────────────────────────────────
    p.h2("limits", "What we claim, and what we do not", kicker="The honest version")
    p.add(callout("ok", "The claim",
                  "<p>We do not claim that HULI-KAMOTE works on a real barangay CCTV. We surveyed how CCTV systems usually hand out their picture, "
                  "built the Live Monitor to accept those inputs, and tested the same path with stand-in cameras. A real camera needs only its address.</p>"))
    p.add(table(["Tested", "Not tested"], [
        ["Video files (the main path)<br>A stand-in camera from publish_clip.py<br>Failure handling: backend down, relay missing, no picture, dropped stream, reconnect<br>The freeze fix, with a deliberately stuck encoder",
         "A real CCTV or recorder<br>A real phone camera app<br>MJPEG and RTMP sources<br>H.265 video<br>Night, rain and glare footage"],
    ], "dense", ["50%", "50%"]))
    p.add("<p>Two honest limits: accuracy depends on the camera's angle and quality (blur, glare, small plates), and opening a barangay's CCTV needs "
          "their permission, the recorder's address and its password. The system only reads the picture; it has no pan, tilt, zoom or audio.</p>")
    p.end()
    return p
