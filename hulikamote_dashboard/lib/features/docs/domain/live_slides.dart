import 'package:flutter/material.dart';

/// One screen of the Live camera presentation. One idea, at most [maxWords] words.
class LiveSlide {
  final String section;
  final String title;
  final String text;
  final IconData icon;

  /// Where this is in our code (file and function), shown as a small label.
  final String? code;

  const LiveSlide({
    required this.section,
    required this.title,
    required this.text,
    required this.icon,
    this.code,
  });

  static const int maxWords = 33;

  int get wordCount => text.trim().split(RegExp(r'\s+')).length;
}

const _basics = 'Foundations';
const _ours = 'Our code';

/// The Live camera story for laymen: from "what is a video" to the code that reads it.
/// Facts come from tools/doc_site/content_live.py and the files named in [LiveSlide.code].
const List<LiveSlide> liveSlides = [
  LiveSlide(
    section: _basics,
    title: 'Live camera, step by step',
    text: 'We start with what a video is. We end with the exact code that reads a camera in HULI-KAMOTE. Press the right arrow to begin.',
    icon: Icons.videocam_rounded,
  ),
  // ── Foundations ──────────────────────────────────────────────────────────
  LiveSlide(
    section: _basics,
    title: 'What is a video?',
    text: 'A video is many still pictures shown one after another, very fast. About 25 every second. Each single picture is called a frame.',
    icon: Icons.movie_rounded,
  ),
  LiveSlide(
    section: _basics,
    title: 'What is a stream?',
    text: 'A camera takes pictures and sends them out the moment they are taken. Nothing is saved first. Sending pictures live like this is called a stream.',
    icon: Icons.sensors_rounded,
  ),
  LiveSlide(
    section: _basics,
    title: 'What is CCTV?',
    text: 'CCTV means closed-circuit television. Cameras stay fixed in one place and send their pictures only to a few screens or recorders, not to everyone.',
    icon: Icons.videocam_outlined,
  ),
  LiveSlide(
    section: _basics,
    title: 'How do pictures travel?',
    text: 'Over a network cable or Wi-Fi, the same way a website reaches your phone. The camera does the sending. We are the one asking.',
    icon: Icons.lan_rounded,
  ),
  LiveSlide(
    section: _basics,
    title: 'What is an address?',
    text: 'To ask a camera for pictures you need its address, like a house address. For example rtsp://192.168.1.20:554/stream1. It says where the camera is and how to talk to it.',
    icon: Icons.link_rounded,
  ),
  LiveSlide(
    section: _basics,
    title: 'What is RTSP?',
    text: 'RTSP is the common language cameras use to stream. Most CCTV brands, such as Hikvision and Dahua, speak it. Older cameras and phones often use plain web video instead.',
    icon: Icons.translate_rounded,
  ),
  LiveSlide(
    section: _basics,
    title: 'What is detection?',
    text: 'An AI model looks at one frame and draws a box around what it finds: cars, motorcycles, people. Finding things in a picture is called detection.',
    icon: Icons.center_focus_strong_rounded,
  ),
  LiveSlide(
    section: _basics,
    title: 'What is tracking?',
    text: 'Tracking follows the same box from frame to frame. That way the system knows it is the same car moving, not a new car in every picture.',
    icon: Icons.timeline_rounded,
  ),
  LiveSlide(
    section: _basics,
    title: 'What is a violation?',
    text: 'A rule being broken, like driving the wrong way. The system checks every tracked vehicle against the rules, and flags the ones that break them.',
    icon: Icons.gavel_rounded,
  ),
  // ── Our code ─────────────────────────────────────────────────────────────
  LiveSlide(
    section: _ours,
    title: 'The whole path',
    text: 'Five steps: the camera, its address, our reader, the AI, the dashboard. The first two belong to the outside world. The last three are our code.',
    icon: Icons.account_tree_rounded,
  ),
  LiveSlide(
    section: _ours,
    title: 'One address, any source',
    text: 'To us, a CCTV camera, a phone, and a laptop playing a video file look the same: an address that gives back pictures. Only the address changes.',
    icon: Icons.swap_horiz_rounded,
  ),
  LiveSlide(
    section: _ours,
    title: 'Reading the address',
    text: 'One small function reads the text and decides: a webcam, a stream, or a file. Anything else is refused, so a typed address cannot open something unsafe.',
    icon: Icons.rule_rounded,
    code: 'camera_source.py · parse_source',
  ),
  LiveSlide(
    section: _ours,
    title: 'Passwords stay hidden',
    text: 'If an address contains a password, the screen shows stars instead: user:***@address. Passwords are never shown on screen and never written to logs.',
    icon: Icons.visibility_off_rounded,
    code: 'camera_source.py · mask_url',
  ),
  LiveSlide(
    section: _ours,
    title: 'The problem: AI is slower',
    text: 'The camera sends 25 pictures a second. The AI may need longer for each one. Old pictures would pile up in a queue, and the screen would fall behind.',
    icon: Icons.hourglass_bottom_rounded,
  ),
  LiveSlide(
    section: _ours,
    title: 'The fix: keep the newest',
    text: 'CameraSource keeps only one picture, the newest. When the AI is ready, it takes that one. Older pictures are dropped and counted. Lag cannot build up.',
    icon: Icons.filter_1_rounded,
    code: 'camera_source.py · CameraSource._publish',
  ),
  LiveSlide(
    section: _ours,
    title: 'The problem: cameras fail',
    text: 'Cameras get switched off and Wi-Fi drops. So we never wait forever. Connecting gives up after 5 seconds and tells the user in plain words.',
    icon: Icons.wifi_off_rounded,
    code: 'camera_source.py · OPEN_TIMEOUT_MS',
  ),
  LiveSlide(
    section: _ours,
    title: 'Reconnect by itself',
    text: 'If the stream drops, we wait 1 second and try again, then 2, 4, and 8. The screen shows OFFLINE meanwhile. Nobody has to press anything.',
    icon: Icons.sync_rounded,
    code: 'camera_source.py · CameraSource._run',
  ),
  LiveSlide(
    section: _ours,
    title: 'Clean pictures',
    text: 'We ask the camera to send over TCP, not UDP. UDP can lose pieces on Wi-Fi and smear the picture. TCP keeps it clean, and we ask for no buffering.',
    icon: Icons.high_quality_rounded,
    code: 'camera_source.py · FFMPEG_OPTIONS',
  ),
  LiveSlide(
    section: _ours,
    title: 'The AI step',
    text: 'For each newest picture, the AI finds vehicles, follows them, and runs the violation rules. Then it hands the result to the dashboard.',
    icon: Icons.psychology_rounded,
    code: 'routers/stream.py · _real_loop',
  ),
  LiveSlide(
    section: _ours,
    title: 'Boxes and picture together',
    text: 'The dashboard needs two things: the boxes and the picture. By default we send both in one message, so the boxes always sit exactly on the cars.',
    icon: Icons.layers_rounded,
    code: 'HK_PICTURE_MODE = synced',
  ),
  LiveSlide(
    section: _ours,
    title: 'Why one message',
    text: 'We first sent the picture by a longer route. It arrived two seconds after the boxes, so the boxes ran ahead of the cars. One message makes that impossible.',
    icon: Icons.sync_alt_rounded,
  ),
  LiveSlide(
    section: _ours,
    title: 'A real bug we fixed',
    text: 'When the video relay was off, the encoder stopped reading and the whole backend froze. Now a separate thread does the writing, and drops pictures when full.',
    icon: Icons.bug_report_rounded,
    code: 'hls_broadcaster.py · _write_loop',
  ),
  LiveSlide(
    section: _ours,
    title: 'Checks before it starts',
    text: 'Before starting, the Live Monitor checks the backend, the relay, and the first picture. If something is wrong, it says so in plain words.',
    icon: Icons.fact_check_rounded,
    code: 'live_monitoring_screen.dart · _loadSource',
  ),
  LiveSlide(
    section: _ours,
    title: 'Try it without CCTV',
    text: 'A small script plays any video file as if it were a camera. Copy the address it prints, paste it into Live Monitor, then press Start.',
    icon: Icons.play_circle_rounded,
    code: 'tools/sim_cctv/publish_clip.py',
  ),
  LiveSlide(
    section: _ours,
    title: 'What we tested',
    text: 'Video files, a stand-in camera, and every failure case: backend down, relay missing, no picture, dropped stream, and reconnecting.',
    icon: Icons.check_circle_rounded,
  ),
  LiveSlide(
    section: _ours,
    title: 'What we do not claim',
    text: 'We do not claim it works on a real barangay CCTV yet. A real camera needs only its address. Accuracy depends on the camera angle and picture quality.',
    icon: Icons.info_outline_rounded,
  ),
  LiveSlide(
    section: _ours,
    title: 'In one line',
    text: 'A camera is an address that gives pictures. We read it safely, keep the newest, find vehicles, check the rules, and show you.',
    icon: Icons.flag_rounded,
  ),
];
