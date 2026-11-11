import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/visible_poller.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';
import '../widgets/camera_input_dialog.dart';
import '../widgets/camera_status_chip.dart';
import '../widgets/road_detect_view.dart';
import '../widgets/road_learning_chip.dart';
import '../widgets/video_feed_widget.dart';
import '../widgets/alert_list_widget.dart';

class LiveMonitoringScreen extends StatefulWidget {
  const LiveMonitoringScreen({super.key, this.client});

  /// Injected by tests; the app talks to the backend.
  final http.Client? client;

  @override
  State<LiveMonitoringScreen> createState() => _LiveMonitoringScreenState();
}

class _LiveMonitoringScreenState extends State<LiveMonitoringScreen> {
  WebSocketChannel? _channel;
  Stream<dynamic>? _broadcastStream;
  bool _isMocking = false;
  bool _isPlaying = false;
  bool _showPanel = true;    // the detections list on the right can be folded away to give the picture the whole width
  bool _roadDetecting = false;   // "Detect road": the live video is a small window and the frozen frame is shown large
  int _roadDetectRun = 0;        // a new walkthrough starts from a clean view
  String _sourceName = 'Intersection_01';

  int _reconnectTries = 0;

  late final http.Client _client = widget.client ?? http.Client();
  String? _problem;          // what is wrong, in words, shown above the picture until it is fixed
  Timer? _noPicture;         // fires when the feed connected but no picture arrived
  bool _gotFrame = false;

  /// Boxes are shown this long after they arrive, because the picture reaches the screen later (see VideoFeedWidget).
  /// Adjust by eye in the More menu; the choice is kept.
  static const _delayKey = 'live_box_delay_ms';
  int _boxDelayMs = 400;

  final CameraApi _cameraApi = CameraApi();
  Map<String, dynamic>? _camera; // the backend's view of the camera: state, fps, lag (shown while monitoring)
  late final VisiblePoller _poller =
      VisiblePoller(interval: const Duration(seconds: 2), onTick: _pollCamera, initiallyActive: false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.attach(context);
  }

  @override
  void initState() {
    super.initState();
    // Do NOT connect automatically. Let the user explicitly start it
    // so it doesn't run in the background and spam the database.
    _loadSource();
    _loadBoxDelay();
  }

  Future<void> _loadBoxDelay() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getInt(_delayKey);
      if (saved != null && mounted) setState(() => _boxDelayMs = saved);
    } catch (_) {}
  }

  Future<void> _nudgeBoxDelay(int by) async {
    setState(() => _boxDelayMs = (_boxDelayMs + by).clamp(0, 2000));
    try {
      await (await SharedPreferences.getInstance()).setInt(_delayKey, _boxDelayMs);
    } catch (_) {}
  }

  static const _backendDown = 'The backend is not answering. Restart it, then press Try again.';
  static const _noPictureYet = 'Connected, but no picture yet. Check the source with Change source.';

  /// Asks the backend which source it uses, and tells the operator in words when something is missing: the backend
  /// not answering, or the video relay (MediaMTX) not running (it starts the relay itself when it can). Without the
  /// relay no picture can ever arrive. Returns whether everything is ready.
  Future<bool> _loadSource() async {
    String? problem;
    try {
      final res = await _client.get(Uri.parse('${ApiConstants.baseUrl}/settings/camera-config')).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final src = (jsonDecode(res.body) as Map)['source_url'] as String?;
      if (mounted && src != null && src.isNotEmpty) setState(() => _sourceName = src.split(RegExp(r'[\\/]')).last);
      problem = await _relayProblem();
    } catch (_) {
      problem = _backendDown;
    }
    if (mounted) {
      setState(() {
        if (problem != null) {
          _problem = problem;
        } else if (_problem != _noPictureYet) {
          _problem = null;                      // fixed; a "no picture" warning is only cleared by a picture arriving
        }
      });
    }
    return problem == null;
  }

  /// Why the video relay is not usable, or null when it is (an older backend without the question counts as fine).
  Future<String?> _relayProblem() async {
    try {
      final res = await _client.get(Uri.parse('${ApiConstants.baseUrl}/settings/video-server')).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final info = jsonDecode(res.body) as Map;
      return info['ready'] == false ? '${info['message']} Then press Try again.' : null;
    } catch (_) {
      return _backendDown;
    }
  }

  void _retry() {
    if (_isPlaying) {
      _stopMonitoring();
      _startMonitoring();
    } else {
      _loadSource();
    }
  }

  Future<void> _pollCamera() async {
    final status = await _cameraApi.status();
    if (!mounted) return;
    final label = (status['label'] ?? '') as String;
    setState(() {
      _camera = status;
      if (label.isNotEmpty) _sourceName = label;
    });
  }

  /// "Re-learn" / "Forget" of the road the camera learned; refreshes the status at once.
  Future<void> _roadAction(Future<void> Function() action) async {
    try {
      await action();
      await _pollCamera();
    } catch (_) {}
  }

  /// Pick a CCTV / DVR, phone camera, another laptop or a file. The backend closes the feed when the source
  /// changes and [_onChannelClosed] reconnects, so a running feed switches by itself.
  Future<void> _openCameraInput() async {
    final changed = await showDialog<bool>(context: context, builder: (_) => CameraInputDialog(api: _cameraApi));
    if (changed == true && mounted) {
      try {
        await _pollCamera();
      } catch (_) {}
    }
  }

  Future<void> _startMonitoring() async {
    if (!await _loadSource()) {
      if (_isPlaying) _stopMonitoring();       // a reconnect found the backend gone
      return;
    }
    if (!mounted) return;
    final channel = WebSocketChannel.connect(Uri.parse(ApiConstants.wsVideoFeed));
    final stream = channel.stream.asBroadcastStream();
    setState(() {
      _isPlaying = true;
      _gotFrame = false;
      _problem = null;
      _channel = channel;
      _broadcastStream = stream;
    });
    _poller.active = true;
    stream.listen((_) {
      _reconnectTries = 0;
      if (!_gotFrame) {
        _gotFrame = true;
        _noPicture?.cancel();
        if (mounted && _problem == _noPictureYet) setState(() => _problem = null);
      }
    }, onDone: () => _onChannelClosed(channel), onError: (_) => _onChannelClosed(channel));
    _noPicture?.cancel();
    _noPicture = Timer(const Duration(seconds: 12), () {
      if (mounted && _isPlaying && !_gotFrame) setState(() => _problem = _noPictureYet);
    });
  }

  /// The backend closes the feed when the source changes (e.g. "Send to Live Monitor"
  /// or an upload), so reconnect to pick up the new source. Gives up after a few quick failures.
  void _onChannelClosed(WebSocketChannel channel) {
    if (!mounted || !_isPlaying || !identical(_channel, channel)) return;
    if (++_reconnectTries > 5) {
      _stopMonitoring();
      return;
    }
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _isPlaying && identical(_channel, channel)) _startMonitoring();
    });
  }

  void _stopMonitoring() {
    _poller.active = false;
    _noPicture?.cancel();
    setState(() {
      _isPlaying = false;
      _roadDetecting = false;
      _camera = null;
      _channel?.sink.close();
      _channel = null;
      _broadcastStream = null;
    });
  }

  /// Upload a video file and make it the live monitor source (stand-in for a real camera).
  Future<void> _uploadVideoSource() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await FilePicker.pickFile(type: FileType.video);
      if (file == null || file.path == null) return;
      messenger.showSnackBar(const SnackBar(content: Text('Uploading video...')));

      final request = http.MultipartRequest(
          'POST', Uri.parse('${ApiConstants.baseUrl}/settings/video/upload'));
      request.files.add(await http.MultipartFile.fromPath('file', file.path!));
      final response = await request.send().timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) {
        throw Exception('Upload failed (${response.statusCode})');
      }
      if (!mounted) return;
      setState(() => _sourceName = file.name);
      // Reconnect so the feed picks up the new source.
      if (_isPlaying) {
        _stopMonitoring();
        _startMonitoring();
      }
      messenger.showSnackBar(SnackBar(content: Text('Source set to ${file.name}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Video upload failed: $e')));
    }
  }

  Future<void> _toggleMock(bool value) async {
    setState(() => _isMocking = value);
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/settings/mock?enabled=$value');
      await http.post(url);
    } catch (e) {
      debugPrint('Failed to toggle mock mode: $e');
    }
  }

  @override
  void dispose() {
    _noPicture?.cancel();
    _poller.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  // ─── layout ────────────────────────────────────────────────────────────────
  // One job per area: the top bar says WHAT is watched and lets you change it, the stage shows the picture (or one
  // clear Start button), the side panel lists what was caught. Rarely used things live in the menus.

  bool get _playing => _isPlaying && _broadcastStream != null;

  @override
  Widget build(BuildContext context) {
    final stage = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sourceBar(),
      const SizedBox(height: Fx.s16),
      if (_problem != null) ...[
        FxBanner(message: _problem!, action: TextButton(onPressed: _retry, child: const Text('Try again'))),
        const SizedBox(height: Fx.s12),
      ],
      Expanded(child: _playing ? _videoArea() : _pausedStage()),
    ]);
    final detections = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Live detections', style: Fx.heading(context).copyWith(fontSize: 18)),
      const SizedBox(height: Fx.s12),
      Expanded(child: _playing ? AlertListWidget(frameStream: _broadcastStream!) : _noDetections()),
    ]);
    return Scaffold(
      backgroundColor: Fx.page(context),
      body: Padding(
        padding: const EdgeInsets.all(Fx.s24),
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 1000
              ? Row(children: [
                  Expanded(child: stage),
                  // Offstage keeps the list (and what it already caught) alive while it is folded away
                  Offstage(
                    offstage: !_showPanel,
                    child: Padding(
                      padding: const EdgeInsets.only(left: Fx.s24),
                      child: SizedBox(width: (box.maxWidth - Fx.s24) * 0.3, child: detections),
                    ),
                  ),
                ])
              : Column(children: [
                  Expanded(child: stage),
                  Offstage(
                    offstage: !_showPanel,
                    child: Padding(
                      padding: const EdgeInsets.only(top: Fx.s16),
                      child: SizedBox(height: box.maxHeight * 0.4, child: detections),
                    ),
                  ),
                ]),
        ),
      ),
    );
  }

  Widget _sourceBar() {
    return Row(children: [
      StatusPill(
        label: _playing ? 'LIVE' : 'Paused',
        color: _playing ? Fx.danger : Fx.muted(context),
        icon: _playing ? Icons.fiber_manual_record : Icons.pause,
      ),
      const SizedBox(width: Fx.s12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_sourceName, overflow: TextOverflow.ellipsis, style: Fx.heading(context).copyWith(fontSize: 18)),
          if (_camera != null && _playing) CameraStatusChip(status: _camera!),
          if (_camera?['road'] is Map && _playing)
            RoadLearningChip(
              road: Map<String, dynamic>.from(_camera!['road'] as Map),
              onRelearn: () => _roadAction(_cameraApi.relearnRoad),
              onForget: () => _roadAction(_cameraApi.forgetRoad),
            ),
        ]),
      ),
      const SizedBox(width: Fx.s12),
      if (_playing) ...[
        _roadDetecting
            ? FilledButton.tonalIcon(
                key: const ValueKey('road-detect-toggle'),
                onPressed: _toggleRoadDetect,
                icon: const Icon(Icons.close),
                label: const Text('Back to live'),
              )
            : OutlinedButton.icon(
                key: const ValueKey('road-detect-toggle'),
                onPressed: _toggleRoadDetect,
                icon: const Icon(Icons.route),
                label: const Text('Detect road'),
              ),
        const SizedBox(width: Fx.s8),
      ],
      _sourceMenu(),
      if (_playing) ...[
        const SizedBox(width: Fx.s8),
        FilledButton.icon(
          onPressed: _stopMonitoring,
          icon: const Icon(Icons.stop),
          label: const Text('Stop monitoring'),
          style: FilledButton.styleFrom(backgroundColor: Fx.danger, foregroundColor: Colors.black),
        ),
      ],
      IconButton(
        tooltip: _showPanel ? 'Hide detections' : 'Show detections',
        icon: Icon(_showPanel ? Icons.keyboard_double_arrow_right : Icons.keyboard_double_arrow_left),
        onPressed: () => setState(() => _showPanel = !_showPanel),
      ),
      _moreMenu(),
    ]);
  }

  // ─── "Detect road" ─────────────────────────────────────────────────────────
  // The operator presses Detect road while the video plays: the backend freezes that frame and reads the road, the live video
  // shrinks into the top-right corner (still playing) and the frozen frame is shown large with every step swept over it.

  static const _pipSize = Size(300, 169);

  /// Press (or press again to go back to the live picture).
  Future<void> _toggleRoadDetect() async {
    if (_roadDetecting) {
      try {
        await _cameraApi.discardRoadDetect();
      } catch (_) {}
      if (mounted) setState(() => _roadDetecting = false);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _cameraApi.startRoadDetect();
      if (mounted) {
        setState(() {
          _roadDetecting = true;
          _roadDetectRun++;
        });
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e is Exception ? e.toString().replaceFirst('Exception: ', '') : e}')));
    }
  }

  void _closeRoadDetect({required bool applied}) {
    if (!mounted) return;
    setState(() => _roadDetecting = false);
    if (applied) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Road applied: the live monitor now uses the crosswalk.')));
    }
    _pollCamera();
  }

  /// The live video, full size, or - while the road is being detected - a small window in the top-right corner over the walkthrough.
  Widget _videoArea() {
    return LayoutBuilder(builder: (context, box) {
      final detecting = _roadDetecting;
      return Stack(children: [
        Positioned.fill(
          child: detecting
              ? RoadDetectView(
                  key: ValueKey('road-detect-$_roadDetectRun'),
                  api: _cameraApi,
                  onClose: _closeRoadDetect,
                  reserveTopRight: _pipSize,
                )
              : const SizedBox.shrink(),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOutCubic,
          left: detecting ? box.maxWidth - _pipSize.width - Fx.s16 : 0,
          top: detecting ? Fx.s16 : 0,
          width: detecting ? _pipSize.width : box.maxWidth,
          height: detecting ? _pipSize.height : box.maxHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Fx.radiusSm),
              border: detecting ? Border.all(color: Colors.white70, width: 1.5) : null,
              boxShadow: detecting ? const [BoxShadow(color: Colors.black54, blurRadius: 12)] : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(detecting ? Fx.radiusSm : 0),
              child: VideoFeedWidget(stream: _broadcastStream!, boxDelayMs: _boxDelayMs),
            ),
          ),
        ),
      ]);
    });
  }

  /// "Change source": a phone, CCTV or another laptop (by address), or a video file.
  Widget _sourceMenu() {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(leadingIcon: const Icon(Icons.videocam_outlined), onPressed: _openCameraInput, child: const Text('Camera or phone…')),
        MenuItemButton(leadingIcon: const Icon(Icons.upload_file), onPressed: _uploadVideoSource, child: const Text('Video file…')),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Change source'),
      ),
    );
  }

  /// Demo tools that are not needed while working.
  Widget _moreMenu() {
    return MenuAnchor(
      menuChildren: [
        CheckboxMenuButton(value: _isMocking, onChanged: (v) => _toggleMock(v ?? false), child: const Text('Simulate violations (demo)')),
        const Divider(height: 1),
        MenuItemButton(leadingIcon: const Icon(Icons.timer_outlined), onPressed: null, child: Text('Box delay (relay video only): $_boxDelayMs ms')),
        MenuItemButton(
            closeOnActivate: false, leadingIcon: const Icon(Icons.add), onPressed: () => _nudgeBoxDelay(100), child: const Text('Boxes ahead of the vehicles? Delay more')),
        MenuItemButton(
            closeOnActivate: false, leadingIcon: const Icon(Icons.remove), onPressed: () => _nudgeBoxDelay(-100), child: const Text('Boxes behind the vehicles? Delay less')),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  Widget _pausedStage() {
    return Container(
      decoration: BoxDecoration(
        color: Fx.panel(context),
        borderRadius: BorderRadius.circular(Fx.radius),
        border: Border.all(color: Fx.border(context)),
      ),
      child: EmptyState(
        icon: Icons.videocam_off_outlined,
        title: 'Monitoring is off',
        message: 'Source: $_sourceName\nPress Start to watch the live feed and catch violations.',
        action: FilledButton.icon(
          onPressed: _startMonitoring,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start monitoring'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
        ),
      ),
    );
  }

  Widget _noDetections() {
    return Container(
      decoration: BoxDecoration(
        color: Fx.panel(context),
        borderRadius: BorderRadius.circular(Fx.radius),
        border: Border.all(color: Fx.border(context)),
      ),
      child: const EmptyState(
        icon: Icons.notifications_none,
        title: 'No detections yet',
        message: 'Violations appear here as soon as they are seen.',
      ),
    );
  }
}
