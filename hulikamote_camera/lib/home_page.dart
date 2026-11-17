import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_bridge.dart';

const _live = Color(0xFFEF4444);
const _ok = Color(0xFF22C55E);
const _card = Color(0xFF111A2E);
const _line = Color(0xFF1F2B45);

/// One screen: choose what the phone broadcasts, press the big button, connect the cable.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  final CameraBridge _bridge = CameraBridge();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  SourceMode _mode = SourceMode.camera;
  bool _front = false;
  String _quality = 'medium';
  bool _wifi = false;
  PickedVideo? _video;

  BroadcastStatus _status = const BroadcastStatus();
  Uint8List? _frame;
  String? _problem;
  bool _busy = false;
  Timer? _timer;
  StreamSubscription<Uint8List>? _sub;

  bool get _running => _status.running;

  @override
  void initState() {
    super.initState();
    _sub = _bridge.preview.listen((bytes) {
      if (mounted) setState(() => _frame = bytes);
    }, onError: (_) {});
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final s = await _bridge.status();
      if (!mounted) return;
      setState(() {
        _status = s;
        if (!s.running) _frame = null;
      });
    } catch (_) {}
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (_running) {
      await _bridge.stop();
      await _poll();
      return;
    }
    if (_mode == SourceMode.video && _video == null) {
      setState(() => _problem = 'Choose a video from the gallery first.');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final error = await _bridge.start(mode: _mode, front: _front, quality: _quality, wifi: _wifi, video: _video?.uri);
      if (mounted) setState(() => _problem = error);
    } catch (e) {
      if (mounted) setState(() => _problem = 'The broadcast could not start: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _poll();
    }
  }

  Future<void> _chooseVideo() async {
    try {
      final picked = await _bridge.pickVideo();
      if (picked != null && mounted) setState(() => _video = picked);
    } catch (e) {
      if (mounted) setState(() => _problem = 'The gallery could not be opened: $e');
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address copied'), duration: Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem ?? (_running ? _status.error : null);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            _header(),
            const SizedBox(height: 16),
            _previewBox(),
            const SizedBox(height: 16),
            _sourcePicker(),
            const SizedBox(height: 12),
            _options(),
            const SizedBox(height: 16),
            _bigButton(),
            if (problem != null) ...[const SizedBox(height: 12), _banner(problem)],
            const SizedBox(height: 20),
            _connectCard(),
          ],
        ),
      ),
    );
  }

  // ── pieces ──
  Widget _header() {
    return Row(children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: const Color(0xFF4F8CFF).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.videocam_rounded, color: Color(0xFF4F8CFF), size: 26),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('HULI-KAMOTE Camera', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Text('Your phone, as a CCTV camera', style: TextStyle(fontSize: 13, color: Colors.white60)),
        ]),
      ),
      _pill(_running ? 'LIVE' : 'Ready', _running ? _live : Colors.white38, dot: _running),
    ]);
  }

  Widget _pill(String text, Color color, {bool dot = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          FadeTransition(opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse), child: Icon(Icons.circle, size: 9, color: color)),
          const SizedBox(width: 6),
        ],
        Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ]),
    );
  }

  Widget _previewBox() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (_frame != null)
            Image.memory(_frame!, fit: BoxFit.contain, gaplessPlayback: true)
          else
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_mode == SourceMode.camera ? Icons.videocam_off_outlined : Icons.movie_outlined, size: 38, color: Colors.white24),
                const SizedBox(height: 8),
                Text(_running ? 'Waiting for the first picture…' : 'What the laptop will see appears here', style: const TextStyle(color: Colors.white38, fontSize: 13)),
              ]),
            ),
          if (_running)
            Positioned(
              left: 10,
              bottom: 10,
              child: _pill('${_status.clients} viewer${_status.clients == 1 ? '' : 's'}  ·  ${_status.fps.toStringAsFixed(0)} fps', Colors.white70),
            ),
        ]),
      ),
    );
  }

  Widget _sourcePicker() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<SourceMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: SourceMode.camera, icon: Icon(Icons.videocam_outlined), label: Text('Live camera')),
          ButtonSegment(value: SourceMode.video, icon: Icon(Icons.video_library_outlined), label: Text('Gallery video')),
        ],
        selected: {_mode},
        onSelectionChanged: _running ? null : (s) => setState(() => _mode = s.first),
      ),
    );
  }

  Widget _options() {
    final locked = _running;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
      child: _mode == SourceMode.camera
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Camera', style: TextStyle(color: Colors.white60, fontSize: 12.5)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.camera_rear_outlined), label: Text('Back')),
                  ButtonSegment(value: true, icon: Icon(Icons.camera_front_outlined), label: Text('Front')),
                ],
                selected: {_front},
                onSelectionChanged: locked ? null : (s) => setState(() => _front = s.first),
              ),
              const SizedBox(height: 14),
              const Text('Picture quality', style: TextStyle(color: Colors.white60, fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final q in const [('low', 'Light  480p'), ('medium', 'Normal  720p'), ('high', 'Sharp  1080p')])
                  ChoiceChip(label: Text(q.$2), selected: _quality == q.$1, onSelected: locked ? null : (_) => setState(() => _quality = q.$1)),
              ]),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Video', style: TextStyle(color: Colors.white60, fontSize: 12.5)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: locked ? null : _chooseVideo,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(_video?.name ?? 'Choose a video from the gallery', overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 8),
              const Text('It plays at its own speed and starts again when it ends, like a camera that never stops.', style: TextStyle(color: Colors.white54, fontSize: 12.5)),
              const SizedBox(height: 12),
              const Text('Picture quality', style: TextStyle(color: Colors.white60, fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final q in const [('low', 'Light  480p'), ('medium', 'Normal  720p'), ('high', 'Sharp  1080p')])
                  ChoiceChip(label: Text(q.$2), selected: _quality == q.$1, onSelected: locked ? null : (_) => setState(() => _quality = q.$1)),
              ]),
            ]),
    );
  }

  Widget _bigButton() {
    return SizedBox(
      height: 62,
      child: FilledButton.icon(
        onPressed: _busy ? null : _toggle,
        icon: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 30),
        label: Text(_running ? 'Stop broadcasting' : 'Start broadcasting', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          backgroundColor: _running ? _live : const Color(0xFF3B82F6),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }

  Widget _banner(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _live.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: _live.withValues(alpha: 0.5))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline, color: _live, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
      ]),
    );
  }

  Widget _connectCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.usb_rounded, color: _ok, size: 20),
          SizedBox(width: 8),
          Text('Connect to the laptop by USB', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
        ]),
        const SizedBox(height: 10),
        _step('1', 'Plug the phone into the laptop. Turn on USB debugging and allow the laptop.'),
        _step('2', 'On the laptop, double-click "Connect Phone.bat" in the hulikamote_camera folder.'),
        _step('3', 'Open the dashboard, Live Monitor, and press Start monitoring.'),
        const SizedBox(height: 10),
        _address('What the laptop opens', _status.usbUrl),
        const Divider(height: 28, color: _line),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Also allow Wi-Fi / USB tethering', style: TextStyle(fontSize: 14.5)),
          subtitle: const Text('Off: only the USB cable can reach the camera (private). On: anyone on the same network can open it.', style: TextStyle(fontSize: 12.5)),
          value: _wifi,
          onChanged: _running ? null : (v) => setState(() => _wifi = v),
        ),
        if (_running && _wifi)
          for (final a in _status.addresses) _address(a.label, a.url),
        if (_running && _wifi && _status.addresses.isEmpty)
          const Text('No network address found. Connect the phone to Wi-Fi or turn on USB tethering.', style: TextStyle(color: Colors.white54, fontSize: 12.5)),
      ]),
    );
  }

  Widget _step(String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 10, backgroundColor: Colors.white12, child: Text(n, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, color: Colors.white70))),
      ]),
    );
  }

  Widget _address(String label, String url) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.white54)),
              Text(url, style: const TextStyle(fontSize: 13.5, fontFamily: 'monospace')),
            ]),
          ),
          IconButton(tooltip: 'Copy', icon: const Icon(Icons.copy_rounded, size: 19), onPressed: () => _copy(url)),
        ]),
      ),
    );
  }
}
