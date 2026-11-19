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
import '../../data/video_upload.dart';
import '../widgets/camera_input_dialog.dart';
import '../widgets/camera_status_chip.dart';
import '../widgets/flow_controls.dart';
import '../widgets/performance_dialog.dart';
import '../widgets/phone_connect_dialog.dart';
import '../widgets/road_detect_view.dart';
import '../widgets/upload_status_card.dart';
import '../widgets/video_feed_widget.dart';
import '../widgets/alert_list_widget.dart';
import 'live_setup_screen.dart';

/// Picks the video file to upload. Replaceable in tests.
typedef LiveVideoPicker = Future<({String path, String name})?> Function();

Future<({String path, String name})?> pickLiveVideoFile() async {
  final file = await FilePicker.pickFile(type: FileType.video);
  if (file == null || file.path == null) return null;
  return (path: file.path!, name: file.name);
}

class LiveMonitoringScreen extends StatefulWidget {
  const LiveMonitoringScreen({super.key, this.client, this.pickVideo = pickLiveVideoFile});

  /// Injected by tests; the app talks to the backend.
  final http.Client? client;

  /// "Video file…": the dialog that picks the file (a test gives a fixed one).
  final LiveVideoPicker pickVideo;

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
  bool _roadEditing = false;     // ... and the operator is correcting the road: the picture gets the whole page, the small live window steps aside
  int _roadDetectRun = 0;        // a new walkthrough starts from a clean view
  String _sourceName = 'Intersection_01';
  bool _preparingSetup = false;  // "Set up violations": the camera is being started / a picture is being taken
  bool _gate = false;            // Start was pressed: nothing plays yet, the violations are set up first (or skipped)
  int? _violationsOn;            // how many violations the live monitor watches now (null until asked)

  // "Video file…": where the upload is, shown as a card above the picture (null = no upload to show)
  UploadStatus? _upload;
  Completer<void>? _cancelUpload;   // complete it to stop an upload that is still going out
  Timer? _uploadTicker;             // counts the seconds while the backend gets the video ready
  Timer? _uploadFade;               // clears the "ready" card after a while
  String? _uploadPath;              // the file of the last upload, for Try again

  /// The learned traffic-flow arrows on the live picture can be switched off; the choice is kept.
  static const _flowKey = 'live_show_flow_arrows';
  static const _roadArrowsKey = 'live_show_road_arrows';
  static const _roadZonesKey = 'live_show_road_zones';
  bool _showFlowArrows = true;
  bool _showRoadArrows = true;
  bool _showRoadZones = true;
  bool _flowBusy = false;        // a flow action (reverse / learn again) is on its way

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
    _setupEmptied = _emptySetup();
    _loadFlowChoice();
  }

  /// The Live Monitor starts empty each time it is opened: the setup of the last visit is cleared, then the (empty) count is read.
  late final Future<void> _setupEmptied;

  /// Clears the setup of the last visit on the backend, then reads the (empty) count. False when the backend could not do it.
  Future<bool> _emptySetup() async {
    var cleared = true;
    try {
      await _cameraApi.resetLiveSetup();
    } catch (_) {
      cleared = false;                                   // an older backend has no reset (restart it), or it did not answer
    }
    await _loadSetup();
    return cleared;
  }

  Future<void> _loadFlowChoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_flowKey), roads = prefs.getBool(_roadArrowsKey), zones = prefs.getBool(_roadZonesKey);
      if (mounted) {
        setState(() {
          if (saved != null) _showFlowArrows = saved;
          if (roads != null) _showRoadArrows = roads;
          if (zones != null) _showRoadZones = zones;
        });
      }
    } catch (_) {}
  }

  Future<void> _setShowFlowArrows(bool on) async {
    setState(() => _showFlowArrows = on);
    try {
      await (await SharedPreferences.getInstance()).setBool(_flowKey, on);
    } catch (_) {}
  }

  Future<void> _setShowRoadZones(bool on) async {
    setState(() => _showRoadZones = on);
    try {
      await (await SharedPreferences.getInstance()).setBool(_roadZonesKey, on);
    } catch (_) {}
  }

  Future<void> _setShowRoadArrows(bool on) async {
    setState(() => _showRoadArrows = on);
    try {
      await (await SharedPreferences.getInstance()).setBool(_roadArrowsKey, on);
    } catch (_) {}
  }

  /// Counterflow demo: the opposite direction counts as legal (or normal again). The backend does it on the next frame and keeps
  /// what was learned; the status poll then shows the new state, and the picture carries the "TEST: FLOW REVERSED" label.
  Future<void> _reverseFlow(bool on) async {
    if (_flowBusy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _flowBusy = true);
    try {
      final answer = await _cameraApi.reverseFlow(on);
      if (answer['ok'] != true) {
        messenger.showSnackBar(SnackBar(content: Text('${answer['reason'] ?? 'The flow could not be changed.'}')));
      }
      await _pollCamera();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('The flow could not be changed: ${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _flowBusy = false);
    }
  }

  /// Forget the learned flow and learn it again from the traffic (e.g. the camera was moved).
  Future<void> _relearnFlow() async {
    if (_flowBusy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _flowBusy = true);
    try {
      final answer = await _cameraApi.relearnFlow();
      messenger.showSnackBar(SnackBar(
        content: Text(answer['ok'] == true ? 'Learning the traffic flow again. The arrows come back as traffic passes.' : '${answer['reason'] ?? 'Could not start again.'}'),
      ));
      await _pollCamera();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not start again: ${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _flowBusy = false);
    }
  }

  /// How many violations the live monitor watches now (shown next to the camera name).
  Future<void> _loadSetup() async {
    try {
      final setup = await _cameraApi.liveSetup();
      if (mounted) setState(() => _violationsOn = (setup['active_violations'] as List?)?.length ?? 0);
    } catch (_) {}
  }

  /// "Set up violations": the Forensic Analyzer's own steps, drawn on ONE picture of the source, then applied.
  ///  - playing: the picture is frozen from the running feed; the feed restarts with the new rules by itself ([_onChannelClosed] reconnects);
  ///  - not playing (Start was pressed, or the button on the paused screen): the first step collects pictures of the source and the
  ///    operator picks one; when the setup is applied, monitoring starts.
  Future<void> _openSetup() async {
    if (_preparingSetup || _uploading) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _preparingSetup = true);
    try {
      await _setupEmptied;                                 // the clearing of the last visit is done before a setup is read
      if (!mounted) return;
      final int? count;
      if (_playing) {
        Map<String, dynamic> shot = {'ok': false};
        for (var i = 0; i < 20 && mounted; i++) {   // the first picture of a camera can take a few seconds
          shot = await _cameraApi.captureReference();
          if (shot['ok'] == true) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (!mounted) return;
        if (shot['ok'] != true) {
          messenger.showSnackBar(SnackBar(content: Text('${shot['reason'] ?? 'No picture from the camera yet.'}')));
          return;
        }
        count = await Navigator.of(context).push<int>(
          MaterialPageRoute(builder: (_) => LiveSetupScreen(cameraApi: _cameraApi, shot: shot)),
        );
      } else {
        if (!await _loadSource() || !mounted) return;     // the backend, or the video relay, is not ready: the reason is shown
        if (!await _emptySetup() && mounted) {            // nothing runs: the last setup, road and learned flow are cleared for a clean start
          messenger.showSnackBar(const SnackBar(content: Text('The old setup could not be cleared. Restart the backend, then try again.')));
          return;
        }
        count = await Navigator.of(context).push<int>(
          MaterialPageRoute(builder: (_) => LiveSetupScreen(cameraApi: _cameraApi, chooseFrame: true)),
        );
      }
      if (!mounted) return;
      if (count != null) {
        messenger.showSnackBar(SnackBar(content: Text('The live monitor now watches $count violation${count == 1 ? '' : 's'}.')));
        _loadSetup();
        if (!_playing) await _connect();                  // applied before the feed ran: now it starts
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not set up violations: ${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _preparingSetup = false);
    }
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
      _connect();
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

  /// "Connect phone", one click: the backend finds the phone app by itself (USB tethering, hotspot, same Wi-Fi or a USB cable) and makes
  /// it the camera. Then monitoring starts; a running feed switches to the phone by itself (the backend closes it, [_onChannelClosed]
  /// reconnects).
  Future<void> _connectPhone() async {
    final found = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => PhoneConnectDialog(api: _cameraApi));
    if (found != true || !mounted) return;
    if (_playing) {
      await _pollCamera();
    } else {
      await _startMonitoring();
    }
  }

  /// Start: the violations are set up first, so the one thing the screen then offers is the button for that (Skip uses what is set up
  /// now). Nothing is connected until the setup is applied or skipped.
  Future<void> _startMonitoring() async {
    if (!await _loadSource()) return;           // the backend, or the video relay, is not ready: the reason is shown
    if (mounted) setState(() => _gate = true);
  }

  /// Skip the setup: watch with the violations that are set up now.
  void _skipSetup() => _connect();

  /// Opens the feed. Also what reconnecting after a source change does.
  Future<void> _connect() async {
    if (!await _loadSource()) {
      if (_isPlaying) _stopMonitoring();       // a reconnect found the backend gone
      return;
    }
    if (!mounted) return;
    final channel = WebSocketChannel.connect(Uri.parse(ApiConstants.wsVideoFeed));
    final stream = channel.stream.asBroadcastStream();
    setState(() {
      _gate = false;
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
      if (mounted && _isPlaying && identical(_channel, channel)) _connect();
    });
  }

  void _stopMonitoring() {
    _poller.active = false;
    _noPicture?.cancel();
    setState(() {
      _gate = false;
      _isPlaying = false;
      _roadDetecting = false;
      _roadEditing = false;
      _camera = null;
      _channel?.sink.close();
      _channel = null;
      _broadcastStream = null;
    });
  }

  // ─── "Video file…" ─────────────────────────────────────────────────────────
  // Upload a video file and make it the live monitor source (stand-in for a real camera). A card above the picture says where the
  // upload is: how much went out, how fast, what the backend does after that, and at the end that the video is ready (or why not).

  bool get _uploading => _upload?.active ?? false;

  /// Why an upload failed, in words (a backend that does not answer gets its own sentence).
  String _uploadReason(Object e) {
    if (e is http.ClientException || e is TimeoutException) return 'The backend is not answering. Check that it is running, then try again.';
    return '$e'.replaceFirst('Exception: ', '');
  }

  Future<void> _uploadVideoSource() async {
    if (_uploading) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await widget.pickVideo();
      if (picked == null || !mounted) return;
      await _useFile(picked.path, picked.name);
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Could not open the file: ${_uploadReason(e)}')));
    }
  }

  /// "Video file…": the backend uses the file WHERE IT IS: nothing to upload, nothing to wait for. Only a backend that cannot see the file
  /// (it runs on another PC) gets a copy uploaded, with a slim bar that shows the progress.
  Future<void> _useFile(String path, String name) async {
    _uploadFade?.cancel();
    _uploadPath = path;
    try {
      final answer = await useLocalVideo(path, client: _client);
      if (mounted) _fileReady(name, answer);
    } on FileNotOnBackend {
      await _sendVideo(path, name);
    } catch (e) {
      if (mounted) setState(() => _upload = UploadStatus(name: name, stage: UploadStage.failed, error: _uploadReason(e)));
    }
  }

  /// The video is the source now. Another video needs its own setup, so a running feed stops and Start asks for it again.
  void _fileReady(String name, Map<String, dynamic> answer) {
    if (_isPlaying) _stopMonitoring();
    setState(() {
      _sourceName = name;
      _gate = false;
      _upload = UploadStatus(name: name, stage: UploadStage.done, detail: _describeVideo(answer['video']));
    });
    _uploadFade?.cancel();
    _uploadFade = Timer(const Duration(seconds: 25), () {
      if (mounted && _upload?.stage == UploadStage.done) setState(() => _upload = null);
    });
  }

  Future<void> _sendVideo(String path, String name) async {
    _uploadFade?.cancel();
    _uploadTicker?.cancel();
    final cancel = Completer<void>();
    final clock = Stopwatch()..start();
    final waiting = Stopwatch();       // starts when the last byte is out
    var lastShown = -1000;
    var allSent = false;
    _uploadPath = path;
    setState(() {
      _cancelUpload = cancel;
      _upload = UploadStatus(name: name, stage: UploadStage.sending);
    });
    try {
      final answer = await uploadLiveVideo(
        path,
        client: _client,
        cancel: cancel.future,
        onProgress: (sent, total) {
          if (!mounted || allSent) return;
          final now = clock.elapsedMilliseconds;
          final finished = total > 0 && sent >= total;
          if (!finished && now - lastShown < 120) return;      // a few updates a second are plenty
          lastShown = now;
          if (finished) {
            allSent = true;
            waiting.start();
            setState(() => _upload = UploadStatus(name: name, stage: UploadStage.preparing, sent: total, total: total));
            _uploadTicker = Timer.periodic(const Duration(seconds: 1), (_) {
              if (mounted && _upload?.stage == UploadStage.preparing) {
                setState(() => _upload = UploadStatus(name: name, stage: UploadStage.preparing, sent: total, total: total, waited: waiting.elapsed));
              }
            });
            return;
          }
          final seconds = (now / 1000).clamp(0.2, double.infinity);
          setState(() => _upload = UploadStatus(name: name, stage: UploadStage.sending, sent: sent, total: total, bytesPerSecond: sent / seconds));
        },
      );
      _uploadTicker?.cancel();
      if (mounted) _fileReady(name, answer);
    } on UploadCancelled {
      _uploadTicker?.cancel();
      if (!mounted) return;
      setState(() => _upload = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload cancelled. The source did not change.')));
    } catch (e) {
      _uploadTicker?.cancel();
      if (mounted) setState(() => _upload = UploadStatus(name: name, stage: UploadStage.failed, error: _uploadReason(e)));
    } finally {
      _cancelUpload = null;
    }
  }

  /// "1920x1080  ·  25 fps  ·  1 min 23 s  ·  312 MB" from the backend's description of the video ('' when it gave none).
  String _describeVideo(Object? video) {
    if (video is! Map) return '';
    final width = (video['width'] as num?)?.toInt() ?? 0;
    final height = (video['height'] as num?)?.toInt() ?? 0;
    final fps = (video['fps'] as num?)?.toDouble() ?? 0;
    final seconds = (video['duration'] as num?)?.round() ?? 0;
    final size = (video['size_mb'] as num?)?.toDouble() ?? 0;
    return [
      if (width > 0 && height > 0) '${width}x$height',
      if (fps > 0) '${fps.toStringAsFixed(fps.truncateToDouble() == fps ? 0 : 1)} fps',
      if (seconds > 0) formatSeconds(seconds),
      if (size > 0) formatBytes(size * 1024 * 1024),
    ].join('  ·  ');
  }

  void _stopUpload() {
    final cancel = _cancelUpload;
    if (cancel != null && !cancel.isCompleted && _upload?.stage == UploadStage.sending) cancel.complete();
  }

  void _retryUpload() {
    final path = _uploadPath;
    final name = _upload?.name;
    if (path != null && name != null && !_uploading) _useFile(path, name);
  }

  void _dismissUpload() {
    if (_uploading) return;
    _uploadFade?.cancel();
    setState(() => _upload = null);
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
    _uploadTicker?.cancel();
    _uploadFade?.cancel();
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
      if (_upload != null) ...[
        UploadStatusCard(
          status: _upload!,
          playing: _playing,
          compact: true,
          onCancel: _stopUpload,
          onRetry: _retryUpload,
          onDismiss: _dismissUpload,
        ),
        const SizedBox(height: Fx.s12),
      ],
      if (_problem != null) ...[
        FxBanner(message: _problem!, action: TextButton(onPressed: _retry, child: const Text('Try again'))),
        const SizedBox(height: Fx.s12),
      ],
      Expanded(child: _playing ? _videoArea() : (_gate ? _gateStage() : _pausedStage())),
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
          if (_violationsOn != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: StatusPill(
                key: const ValueKey('violations-on-chip'),
                label: _violationsOn == 0 ? 'No violations set up yet' : 'Watching $_violationsOn violation${_violationsOn == 1 ? '' : 's'}',
                color: _violationsOn == 0 ? Fx.warning : Fx.success,
                icon: _violationsOn == 0 ? Icons.rule : Icons.fact_check_outlined,
                dense: true,
              ),
            ),
          if (_camera != null && _playing) CameraStatusChip(status: _camera!),
        ]),
      ),
      const SizedBox(width: Fx.s12),
      // The buttons wrap onto a second line in a narrow window instead of overflowing the bar.
      Flexible(
        child: Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: Fx.s8, runSpacing: Fx.s8, children: [
      if (_playing) ...[
        _setupButton(),
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
      ],
      _sourceMenu(),
      if (_playing) ...[
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
      IconButton(
        key: const ValueKey('performance-button'),
        tooltip: 'Performance: CPU, GPU, RAM and every step of the pipeline',
        icon: const Icon(Icons.speed),
        onPressed: () => PerformanceDialog.show(context, _cameraApi),
      ),
      _moreMenu(),
        ]),
      ),
    ]);
  }

  /// "Set up violations": while monitoring it freezes one picture of the feed; from the paused screen it collects pictures of the source first.
  Widget _setupButton({bool filled = true}) {
    final onPressed = (_roadDetecting || _preparingSetup || _uploading) ? null : _openSetup;
    final icon = _preparingSetup ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.tune);
    final label = Text(_playing ? 'Edit violations' : 'Set up violations');
    return filled
        ? FilledButton.tonalIcon(key: const ValueKey('live-setup-button'), onPressed: onPressed, icon: icon, label: label)
        : OutlinedButton.icon(
            key: const ValueKey('live-setup-button'),
            onPressed: onPressed,
            icon: icon,
            label: label,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          );
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
      if (mounted) {
        setState(() {
          _roadDetecting = false;
          _roadEditing = false;
        });
      }
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
    setState(() {
      _roadDetecting = false;
      _roadEditing = false;
    });
    if (applied) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Road applied: the live monitor now uses the crosswalk.')));
    }
    _pollCamera();
  }

  /// The traffic flow controls over the live picture (bottom-left). Null while no rule uses the flow (the backend then reports none).
  Widget? _flowControls() {
    final flow = _camera?['flow'];
    return FlowControls(
      flow: flow is Map ? flow : const {},
      showRoadArrows: _showRoadArrows,
      onShowRoadArrows: _setShowRoadArrows,
      showRoadZones: _showRoadZones,
      onShowRoadZones: _setShowRoadZones,
      showArrows: _showFlowArrows,
      busy: _flowBusy,
      onShowArrows: _setShowFlowArrows,
      onReverse: _reverseFlow,
      onRelearn: _relearnFlow,
    );
  }

  /// The live video, full size, or - while the road is being detected - a small window in the top-right corner over the walkthrough.
  Widget _videoArea() {
    return LayoutBuilder(builder: (context, box) {
      final detecting = _roadDetecting;
      final flowControls = detecting ? null : _flowControls();
      return Stack(children: [
        Positioned.fill(
          child: detecting
              ? RoadDetectView(
                  key: ValueKey('road-detect-$_roadDetectRun'),
                  api: _cameraApi,
                  onClose: _closeRoadDetect,
                  reserveTopRight: _pipSize,
                  onEditingChanged: (editing) => setState(() => _roadEditing = editing),
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
          // While the road is being corrected the live window steps aside (hidden, but it keeps running) so it never covers the picture.
          child: Visibility(
            visible: !(detecting && _roadEditing),
            maintainState: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Fx.radiusSm),
                border: detecting ? Border.all(color: Colors.white70, width: 1.5) : null,
                boxShadow: detecting ? const [BoxShadow(color: Colors.black54, blurRadius: 12)] : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(detecting ? Fx.radiusSm : 0),
                child: VideoFeedWidget(stream: _broadcastStream!, boxDelayMs: _boxDelayMs, showFlow: _showFlowArrows, showRoadArrows: _showRoadArrows, showRoadZones: _showRoadZones),
              ),
            ),
          ),
        ),
        if (flowControls != null) Positioned(left: Fx.s12, bottom: Fx.s12, child: flowControls),
      ]);
    });
  }

  /// "Change source": a phone, CCTV or another laptop (by address), or a video file.
  Widget _sourceMenu() {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(leadingIcon: const Icon(Icons.phone_android), onPressed: _connectPhone, child: const Text('Connect phone (one click)')),
        MenuItemButton(leadingIcon: const Icon(Icons.videocam_outlined), onPressed: _openCameraInput, child: const Text('Camera or address…')),
        MenuItemButton(leadingIcon: const Icon(Icons.upload_file), onPressed: _uploadVideoSource, child: const Text('Video file…')),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: _uploading ? null : () => controller.isOpen ? controller.close() : controller.open(),   // not while a file is going up
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
      // scrolls when the window is too small for everything, instead of overflowing
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: EmptyState(
              icon: Icons.videocam_off_outlined,
              title: 'Monitoring is off',
              message: 'Source: $_sourceName\nPress Start to watch the live feed and catch violations.',
              action: Column(mainAxisSize: MainAxisSize.min, children: [
                FilledButton.icon(
                  onPressed: _uploading ? null : _startMonitoring,       // the new video is not the source yet
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start monitoring'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
                ),
                const SizedBox(height: Fx.s12),
                Wrap(alignment: WrapAlignment.center, spacing: Fx.s12, runSpacing: Fx.s12, children: [
                  OutlinedButton.icon(
                    key: const ValueKey('connect-phone-button'),
                    onPressed: _connectPhone,
                    icon: const Icon(Icons.phone_android),
                    label: const Text('Connect phone'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                  ),
                  _setupButton(filled: false),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// After Start, before anything plays: the one thing to do is set up the violations (pictures of the video come first).
  Widget _gateStage() {
    final hasSetup = (_violationsOn ?? 0) > 0;
    return Container(
      decoration: BoxDecoration(
        color: Fx.panel(context),
        borderRadius: BorderRadius.circular(Fx.radius),
        border: Border.all(color: Fx.border(context)),
      ),
      child: EmptyState(
        icon: Icons.tune,
        title: 'Set up the violations first',
        message: 'Source: $_sourceName\nPick a picture of the video, then choose what to watch for.',
        action: Column(mainAxisSize: MainAxisSize.min, children: [
          FilledButton.icon(
            key: const ValueKey('gate-setup-button'),
            onPressed: _preparingSetup ? null : _openSetup,
            icon: _preparingSetup ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.tune),
            label: const Text('Set up violations'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
          ),
          const SizedBox(height: Fx.s8),
          if (hasSetup)
            TextButton(key: const ValueKey('gate-skip'), onPressed: _preparingSetup ? null : _skipSetup, child: Text('Skip: watch with the current setup ($_violationsOn)')),
          TextButton(key: const ValueKey('gate-cancel'), onPressed: _preparingSetup ? null : () => setState(() => _gate = false), child: const Text('Cancel')),
        ]),
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
