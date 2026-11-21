import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/visible_poller.dart';
import '../../../forensic/data/forensic_api.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';
import '../../data/video_upload.dart';
import '../../domain/live_overlay_layers.dart';
import '../widgets/camera_input_dialog.dart';
import '../widgets/camera_status_chip.dart';
import '../widgets/flow_controls.dart';
import '../widgets/performance_dialog.dart';
import '../widgets/processing_scan.dart';
import 'live_tickets_screen.dart';
import '../widgets/phone_connect_dialog.dart';
import '../widgets/road_detect_view.dart';
import '../widgets/upload_status_card.dart';
import '../widgets/video_feed_widget.dart';
import '../widgets/live_tickets_panel.dart';
import '../widgets/live_rules_bar.dart';
import '../widgets/live_timeline.dart';
import '../widgets/demo_dialog.dart';
import '../widgets/replay_dialog.dart';
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
  final ValueNotifier<Map<String, dynamic>?> _bufferInfo = ValueNotifier(null);   // the numbers of the timeline bar (the backend's playback state)
  bool _awayPaused = false;                // the picture was held because the enforcer is looking at a ticket (not paused by them)
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
  List<OverlayLayer> _overlayLayers = const [];   // the overlay objects of the set-up violations (rows of the Layers checklist)
  Set<String> _hiddenOverlays = {};
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
  bool _applyingSetup = false;     // Apply was pressed in the setup: the rules are on their way, the "Processing" view shows meanwhile
  bool _applyReady = false;        // ... and the rules are in: the next message of a NEW connection ends the view
  WebSocketChannel? _applyChannel; // the connection that was open when the rules went in (its messages do not count)
  Uint8List? _applyPicture;        // the picture the setup was made on, dimmed under the scan
  Size? _applyPictureSize;
  Timer? _applyGuard;              // the view never stays longer than this
  double? _resumeAtS;              // a video file: where on the video the picture was (Refresh and Resume go on from here)
  bool _resumable = false;         // the feed ran and was stopped (or lost): Resume goes on with the same setup, no new setup
  String? _resumeSource;           // the source it ran on: another source has nothing to resume
  String? _positionSource;         // the source that _resumeAtS belongs to
  DateTime _lastMessage = DateTime.now();
  Timer? _watchdog;                // refreshes a feed that has gone silent

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
    setState(() => _flowBusy = true);
    try {
      await _cameraApi.reverseFlow(on);
      await _pollCamera();
    } catch (_) {
      // the status poll shows the state as it really is
    } finally {
      if (mounted) setState(() => _flowBusy = false);
    }
  }

  /// Forget the learned flow and learn it again from the traffic (e.g. the camera was moved).
  Future<void> _relearnFlow() async {
    if (_flowBusy) return;
    setState(() => _flowBusy = true);
    try {
      await _cameraApi.relearnFlow();
      await _pollCamera();
    } catch (_) {
      // the status poll shows the state as it really is
    } finally {
      if (mounted) setState(() => _flowBusy = false);
    }
  }

  /// How many violations the live monitor watches now (shown next to the camera name).
  Future<void> _loadSetup() async {
    try {
      final setup = await _cameraApi.liveSetup();
      if (mounted) {
        setState(() {
          _violationsOn = (setup['active_violations'] as List?)?.length ?? 0;
          _overlayLayers = OverlayLayer.of(setup);
        });
      }
      final hidden = await _cameraApi.hiddenOverlays();               // what the backend leaves off the picture now
      if (mounted) setState(() => _hiddenOverlays = {...hidden});
    } catch (_) {}
  }

  /// Layers checklist: show or hide the overlay objects of one violation on the live picture.
  Future<void> _showOverlay(String key, bool shown) async {
    setState(() => shown ? _hiddenOverlays.remove(key) : _hiddenOverlays.add(key));
    try {
      await _cameraApi.setHiddenOverlays(_hiddenOverlays);
    } catch (_) {
      if (mounted) {
        setState(() => shown ? _hiddenOverlays.add(key) : _hiddenOverlays.remove(key));   // the backend did not take it: back as it was
      }
    }
  }

  /// "Set up violations": the Forensic Analyzer's own steps, drawn on ONE picture of the source, then applied.
  ///  - playing: the picture is frozen from the running feed; the feed restarts with the new rules by itself ([_onChannelClosed] reconnects);
  ///  - not playing (Start was pressed, or the button on the paused screen): the first step collects pictures of the source and the
  ///    operator picks one; when the setup is applied, monitoring starts.
  Future<void> _openSetup() async {
    if (_preparingSetup || _uploading) return;
    setState(() => _preparingSetup = true);
    unawaited(_cameraApi.prepareFeed());                   // (again: it is quick when the models are loaded already) the setup takes a while
    try {
      await _setupEmptied;                                 // the clearing of the last visit is done before a setup is read
      if (!mounted) return;
      final Object? result;
      if (_playing) {
        Map<String, dynamic> shot = {'ok': false};
        for (var i = 0; i < 20 && mounted; i++) {   // the first picture of a camera can take a few seconds
          shot = await _cameraApi.captureReference();
          if (shot['ok'] == true) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (!mounted) return;
        if (shot['ok'] != true) {
          return;
        }
        result = await Navigator.of(context).push<Object>(
          MaterialPageRoute(builder: (_) => LiveSetupScreen(cameraApi: _cameraApi, shot: shot, deferApply: true)),
        );
      } else {
        if (!await _loadSource() || !mounted) {            // the backend, or the video relay, is not ready
          return;
        }
        if (!await _emptySetup() && mounted) {            // nothing runs: the last setup, road and learned flow are cleared for a clean start
          return;
        }
        result = await Navigator.of(context).push<Object>(
          MaterialPageRoute(builder: (_) => LiveSetupScreen(cameraApi: _cameraApi, chooseFrame: true, deferApply: true)),
        );
      }
      if (!mounted) return;
      if (result is LiveSetupPending) {
        unawaited(_applyPending(result));                 // the wizard is gone at once; the rules are sent behind the "Processing" view
      } else if (result is int) {
        _loadSetup();
        if (!_playing) await _connect();                  // applied before the feed ran: now it starts
      }
    } catch (_) {
      // nothing is shown: the screen stays as it is
    } finally {
      if (mounted) setState(() => _preparingSetup = false);
    }
  }

  /// Apply (last step of the setup): the wizard has closed already. The rules go to the backend (it builds the pipeline and loads the
  /// models: seconds) while the "Processing" view shows over the picture the setup was made on. Then the feed starts (a running feed restarts
  /// by itself) and the view goes when the first message of the new connection arrives.
  Future<void> _applyPending(LiveSetupPending p) async {
    setState(() {
      _applyingSetup = true;
      _applyReady = false;
      _applyChannel = _channel;                           // the connection open NOW (a running feed): only a newer one ends the view
      _applyPicture = null;
      _applyPictureSize = null;
    });
    _applyGuard?.cancel();
    _applyGuard = Timer(const Duration(seconds: 120), () {
      if (mounted && _applyingSetup) setState(() => _applyingSetup = false);
    });
    unawaited(_loadApplyPicture());
    // Everything the start needs goes NOW, side by side, behind the "Processing" view: the old tickets are cleared (when chosen), the rules
    // are sent (the backend loads and warms what it still lacks, off its event loop) and the source and the video relay are checked. The
    // feed connects the moment all of it is done: nothing waits for something it does not depend on.
    final sourceReady = _loadSource();
    try {
      String? clearError;
      await Future.wait<Object?>([
        ForensicApi().useForLive(p.config),
        if (p.clearTickets)
          _cameraApi.clearLiveTickets().then<Object?>((_) => null, onError: (Object e) {
            clearError = '$e'.replaceFirst('Exception: ', '');
            return null;
          }),
      ]);
      if (!mounted) return;
      if (clearError != null) {                           // (the old order stopped here too: tickets that stay would mix with the new ones)
        setState(() => _applyingSetup = false);
        return;
      }
      _applyReady = true;
      _loadSetup();
      if (!_playing) {                                    // applied before the feed ran: now it starts
        if (await sourceReady) await _connect(checked: true);
        if (mounted && !_playing && _applyingSetup) setState(() => _applyingSetup = false);   // it could not start: the reason shows, not a scan
      }
    } catch (e) {
      if (mounted) {
        setState(() => _applyingSetup = false);
      }
    }
  }

  Future<void> _loadApplyPicture() async {
    try {
      final bytes = await _cameraApi.referenceFrameBytes();
      if (bytes == null || !mounted || !_applyingSetup) return;
      final image = await decodeImageFromList(bytes);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      if (mounted && _applyingSetup) {
        setState(() {
          _applyPicture = bytes;
          _applyPictureSize = size;
        });
      }
    } catch (_) {
      // the view then shows the scan without a picture
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
  static const _stalledText = 'The feed stopped answering. Refreshing it…';

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
        if (problem == _backendDown) {
          // no banner for "backend not answering": it came up while the backend was still starting and only got in the way
        } else if (problem != null) {
          _problem = problem;
        } else if (_problem != _noPictureYet && _problem != _stalledText) {
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
      _refreshFeed();
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

  /// "Replay a saved run…": pick a saved run (a folder with its pictures, boxes and tickets). The Live Monitor plays it in order with no
  /// backend work, no setup and no models; its tickets show as they happened, and everything done on them is saved back into that folder.
  Future<void> _openReplay() async {
    final picked = await ReplayDialog.show(context, _cameraApi);
    final run = picked?['run'] as String?;
    if (run == null || !mounted) return;
    if (_isPlaying) _stopMonitoring();
    _resumable = false;
    _resumeAtS = null;
    setState(() {
      _sourceName = run;
      _gate = false;
    });
    await _connect(checked: true);
  }

  /// "Continue a saved monitoring…": a monitoring that was saved with "Save and pause" comes back as it was (setup, learned road, source,
  /// tickets) and the real monitoring goes on from where the video was; new pictures and tickets are added to the same run folder.
  Future<void> _continueSaved() async {
    final picked = await ReplayDialog.show(context, _cameraApi, forContinue: true);
    if (picked == null || !mounted) return;
    if (_isPlaying) _stopMonitoring();
    final name = ((picked['source_name'] as String?) ?? '').isNotEmpty ? picked['source_name'] as String : (picked['run'] as String);
    final at = (picked['pos_s'] as num?)?.toDouble() ?? 0.0;
    _resumable = false;
    _resumeAtS = null;
    setState(() {
      _sourceName = name;
      _positionSource = name;
      _gate = false;
    });
    unawaited(_cameraApi.prepareFeed());          // the models load while the feed opens
    await _connect(startAt: at, checked: true);
  }

  /// "Save and pause": everything to go on later is written into the run folder, then the monitoring stops. Continue it from the source menu.
  Future<void> _saveAndPause() async {
    try {
      // Where to go on: where the BACKEND has finished (not where the screen is). What lies between them is already processed and saved.
      final info = _bufferInfo.value;
      final play = (info?['play_s'] as num?)?.toDouble();
      final proc = (info?['proc_s'] as num?)?.toDouble();
      final ahead = (play != null && proc != null && proc > play) ? proc - play : 0.0;
      await _cameraApi.saveSession((_resumeAtS ?? 0.0) + ahead);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
      return;
    }
    _stopMonitoring();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved. Continue it from Change source, Continue a saved monitoring.')));
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
    unawaited(_cameraApi.prepareFeed());        // the models load and warm up in the backend while the operator sets up (or skips)
    if (mounted) setState(() => _gate = true);
  }

  /// Skip the setup: watch with the violations that are set up now.
  void _skipSetup() => _connect();

  /// Opens the feed. Also what reconnecting after a source change does.
  Future<void> _connect({double? startAt, bool checked = false}) async {
    if (!checked && !await _loadSource()) {
      if (_isPlaying) _stopMonitoring();       // a reconnect found the backend gone
      return;
    }
    if (!mounted) return;
    if (_positionSource != _sourceName) startAt = null;     // the position belongs to another video: start that one from the beginning
    final feed = Uri.parse(ApiConstants.wsVideoFeed);
    final channel = WebSocketChannel.connect(startAt != null && startAt > 0 ? feed.replace(queryParameters: {'start': startAt.toStringAsFixed(2)}) : feed);
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
      _lastMessage = DateTime.now();
      if (_problem == _stalledText && mounted) setState(() => _problem = null);
      if (_applyingSetup && _applyReady && identical(_channel, channel) && !identical(channel, _applyChannel) && mounted) {
        setState(() => _applyingSetup = false);          // the new feed speaks: its own "Processing" view takes over
      }
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
    // A feed that has gone silent (nothing for 25 s) is refreshed once for each silence, with the same setup.
    _lastMessage = DateTime.now();
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_isPlaying || !_gotFrame) return;
      if (DateTime.now().difference(_lastMessage) < const Duration(seconds: 25)) return;
      _lastMessage = DateTime.now();
      setState(() => _problem = _stalledText);
      _refreshFeed();
    });
  }

  /// Refresh: open the feed again with the same setup (no new setup). A video file goes on from where the picture was.
  Future<void> _refreshFeed() async {
    if (!_isPlaying) return;
    _reconnectTries = 0;
    _channel?.sink.close();
    await _connect(startAt: _resumeAtS);
  }

  /// Resume after a stop (or a lost feed): the same setup, no new setup. A video file goes on from where the picture was.
  Future<void> _resume() => _connect(startAt: _resumeAtS);

  bool get _canResume => _resumable && _resumeSource == _sourceName;
  String get _resumeLabel => _resumeAtS != null && _resumeAtS! >= 1 ? 'Resume from ${_clock(_resumeAtS!)}' : 'Resume';
  static String _clock(double seconds) {
    final t = seconds.round();
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  /// A command for the backend's playback: {cmd: pause | play | seek, t: seconds from the start of the run}.
  void _sendLive(Map<String, dynamic> command) {
    try {
      _channel?.sink.add(jsonEncode(command));
    } catch (_) {
      // the feed is closing: nothing to move then
    }
  }

  /// The enforcer goes to look at a ticket (away) or is back: the picture holds meanwhile, the backend goes on, so the delay grows and
  /// nothing that was processed is missed. Back: it plays on from where it was, a bit faster until the gap is back.
  void _onAway(bool away) {
    if (away) {
      if (_bufferInfo.value?['paused'] != true) {
        _awayPaused = true;
        _sendLive({'cmd': 'pause'});
      }
    } else if (_awayPaused) {
      _awayPaused = false;
      _sendLive({'cmd': 'play'});
    }
  }

  void _onBuffer(Map<String, dynamic>? b) {
    _bufferInfo.value = b;
    if (b != null && b['pos_s'] is num) {
      _resumeAtS = (b['pos_s'] as num).toDouble();   // where the picture is on the video
      _positionSource = _sourceName;
    }
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
      if (mounted && _isPlaying && identical(_channel, channel)) _connect(startAt: _resumeAtS);
    });
  }

  void _stopMonitoring() {
    _poller.active = false;
    _noPicture?.cancel();
    _watchdog?.cancel();
    if (_isPlaying) {                          // what it ran on is kept, so Resume can go on with the same setup
      _resumable = true;
      _resumeSource = _sourceName;
    }
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
    try {
      final picked = await widget.pickVideo();
      if (picked == null || !mounted) return;
      await _useFile(picked.path, picked.name);
    } catch (_) {
      // the upload card shows what went wrong, when there is one
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
    _resumable = false;                         // a new video: nothing to resume
    _resumeAtS = null;
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
    _applyGuard?.cancel();
    _noPicture?.cancel();
    _watchdog?.cancel();
    _uploadTicker?.cancel();
    _uploadFade?.cancel();
    _poller.dispose();
    _channel?.sink.close();
    _bufferInfo.dispose();
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
      Expanded(
        child: Stack(fit: StackFit.expand, children: [
          _playing ? _videoArea() : (_applyingSetup ? const SizedBox.shrink() : (_gate ? _gateStage() : _pausedStage())),
          // Apply was pressed: the rules are on their way. Only "Processing" is shown, over the picture the setup was made on.
          if (_applyingSetup)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Fx.radius),
                child: ColoredBox(
                  color: Colors.black,
                  child: ProcessingScan(picture: _applyPicture, pictureWidth: _applyPictureSize?.width, pictureHeight: _applyPictureSize?.height),
                ),
              ),
            ),
        ]),
      ),
    ]);
    // The live tickets: the review's own list. Tickets are queued in the backend, the plates are read one by one, and a ticket shows here
    // when it is done. It stays alive (hidden) while the panel is folded away.
    final detections = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: _playing ? LiveTicketsPanel(onAway: _onAway) : _noDetections()),
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
    // One line: in a narrower window the buttons turn into icons (the words are in their tooltips) so they stay side by side.
    return LayoutBuilder(builder: (context, box) => _sourceRow(compact: box.maxWidth < 1180, width: box.maxWidth));
  }

  /// The buttons in a row with a fixed order and even gaps.
  static List<Widget> _spaced(List<Widget> items, double gap) => [
    for (var i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(width: gap), items[i]],
  ];

  Widget _sourceRow({required bool compact, required double width}) {
    return Row(children: [
      StatusPill(
        label: _playing ? 'LIVE' : 'Paused',
        color: _playing ? Fx.danger : Fx.muted(context),
        icon: _playing ? Icons.fiber_manual_record : Icons.pause,
      ),
      const SizedBox(width: Fx.s12),
      // Left: what is being watched (name, then its status side by side). It gives way first: long text is cut with "...".
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(_sourceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Fx.heading(context).copyWith(fontSize: 18)),
          const SizedBox(height: 4),
          Wrap(spacing: Fx.s12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (_violationsOn != null)
              StatusPill(
                key: const ValueKey('violations-on-chip'),
                label: _violationsOn == 0 ? 'No violations set up yet' : 'Watching $_violationsOn violation${_violationsOn == 1 ? '' : 's'}',
                color: _violationsOn == 0 ? Fx.warning : Fx.success,
                icon: _violationsOn == 0 ? Icons.rule : Icons.fact_check_outlined,
                dense: true,
              ),
            if (_camera != null && _playing) CameraStatusChip(status: _camera!),
          ]),
        ]),
      ),
      const SizedBox(width: Fx.s16),
      // Right: ONE row, always: setup | tools | Stop, even gaps, never stacked. If the window is too small even for icons, the row slides sideways.
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width * 0.66),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(mainAxisSize: MainAxisSize.min, children: _spaced([
          if (_playing)
            _toolGroup([
              _setupButton(compact: compact),
              if (compact)
                IconButton(
                  key: const ValueKey('road-detect-toggle'),
                  tooltip: _roadDetecting ? 'Back to live' : 'Detect road',
                  onPressed: _toggleRoadDetect,
                  icon: Icon(_roadDetecting ? Icons.close : Icons.route),
                )
              else if (_roadDetecting)
                FilledButton.tonalIcon(
                  key: const ValueKey('road-detect-toggle'),
                  onPressed: _toggleRoadDetect,
                  icon: const Icon(Icons.close),
                  label: const Text('Back to live'),
                )
              else
                TextButton.icon(
                  key: const ValueKey('road-detect-toggle'),
                  onPressed: _toggleRoadDetect,
                  icon: const Icon(Icons.route),
                  label: const Text('Detect road'),
                ),
            ]),
          if (!_playing) _sourceMenu(),
          _toolGroup([
            if (_playing) ...[
              _sourceMenu(compact: true),
              IconButton(
                key: const ValueKey('refresh-feed'),
                tooltip: 'Refresh the feed (same setup)',
                icon: const Icon(Icons.refresh),
                onPressed: _refreshFeed,
              ),
            ],
            IconButton(
              tooltip: _showPanel ? 'Hide detections' : 'Show detections',
              icon: Icon(_showPanel ? Icons.keyboard_double_arrow_right : Icons.keyboard_double_arrow_left),
              onPressed: () => setState(() => _showPanel = !_showPanel),
            ),
            IconButton(
              key: const ValueKey('live-tickets-button'),
              tooltip: 'Live tickets: read plates, set photos aside, merge',
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveTicketsScreen())),
            ),
            IconButton(
              key: const ValueKey('demo-button'),
              tooltip: 'Demo replay: play a recorded run for a video file',
              icon: const Icon(Icons.slideshow),
              onPressed: () => DemoDialog.show(context, _cameraApi),
            ),
            IconButton(
              key: const ValueKey('performance-button'),
              tooltip: 'Performance: CPU, GPU, RAM and every step of the pipeline',
              icon: const Icon(Icons.speed),
              onPressed: () => PerformanceDialog.show(context, _cameraApi),
            ),
            _moreMenu(),
          ]),
          if (_playing)
            OutlinedButton.icon(
              key: const ValueKey('save-pause-button'),
              onPressed: _saveAndPause,
              icon: const Icon(Icons.save_outlined),
              label: Text(compact ? 'Save' : 'Save and pause'),
            ),
          if (_playing)
            FilledButton.icon(
              onPressed: _stopMonitoring,
              icon: const Icon(Icons.stop),
              label: Text(compact ? 'Stop' : 'Stop monitoring'),
              style: FilledButton.styleFrom(backgroundColor: Fx.danger, foregroundColor: Colors.black),
            ),
          ], Fx.s12)),
        ),
      ),
    ]);
  }

  /// A quiet box that holds buttons that belong together (one outline, thin dividers between them).
  Widget _toolGroup(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Fx.panel(context),
        borderRadius: BorderRadius.circular(Fx.radiusSm),
        border: Border.all(color: Fx.border(context)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: 22, child: VerticalDivider(width: 8, thickness: 1, color: Fx.border(context))),
          children[i],
        ],
      ]),
    );
  }

  /// "Set up violations": while monitoring it freezes one picture of the feed; from the paused screen it collects pictures of the source first.
  Widget _setupButton({bool filled = true, bool compact = false}) {
    final onPressed = (_roadDetecting || _preparingSetup || _uploading) ? null : _openSetup;
    final icon = _preparingSetup ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.tune);
    final label = Text(_playing ? 'Edit violations' : 'Set up violations');
    if (compact) {
      return IconButton(key: const ValueKey('live-setup-button'), tooltip: _playing ? 'Edit violations' : 'Set up violations', onPressed: onPressed, icon: icon);
    }
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
    try {
      await _cameraApi.startRoadDetect();
      if (mounted) {
        setState(() {
          _roadDetecting = true;
          _roadDetectRun++;
        });
      }
    } catch (_) {
      // the button stays; nothing is shown
    }
  }

  void _closeRoadDetect({required bool applied}) {
    if (!mounted) return;
    setState(() {
      _roadDetecting = false;
      _roadEditing = false;
    });
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
      overlays: _overlayLayers,
      hiddenOverlays: _hiddenOverlays,
      onShowOverlay: _showOverlay,
      showArrows: _showFlowArrows,
      busy: _flowBusy,
      onShowArrows: _setShowFlowArrows,
      onReverse: _reverseFlow,
      onRelearn: _relearnFlow,
    );
  }

  /// The live video with the timeline bar under it (output | backend | video; pause, go back, go forward over what is finished).
  Widget _videoArea() {
    return Column(children: [
      Expanded(child: _videoStack()),
      if (!_roadDetecting)
        ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: _bufferInfo,
          // the switch needs the running backend: a replay of a saved run has none
          builder: (context, info, _) => (info == null || info['replay'] == true) ? const SizedBox.shrink() : LiveRulesBar(api: _cameraApi),
        ),
      if (!_roadDetecting)
        ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: _bufferInfo,
          builder: (context, info, _) => info == null
              ? const SizedBox.shrink()
              : LiveTimeline(
                  info: info,
                  onPause: () {
                    _awayPaused = false;
                    _sendLive({'cmd': 'pause'});
                  },
                  onPlay: () {
                    _awayPaused = false;
                    _sendLive({'cmd': 'play'});
                  },
                  onSeek: (t) => _sendLive({'cmd': 'seek', 't': t}),
                ),
        ),
    ]);
  }

  /// The live video, full size, or - while the road is being detected - a small window in the top-right corner over the walkthrough.
  Widget _videoStack() {
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
                child: VideoFeedWidget(stream: _broadcastStream!, onBuffer: _onBuffer, boxDelayMs: _boxDelayMs, showFlow: _showFlowArrows, showRoadArrows: _showRoadArrows, showRoadZones: _showRoadZones),
              ),
            ),
          ),
        ),
        if (flowControls != null) Positioned(left: Fx.s12, bottom: Fx.s12, child: flowControls),
      ]);
    });
  }

  /// "Change source": a phone, CCTV or another laptop (by address), or a video file.
  Widget _sourceMenu({bool compact = false}) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(leadingIcon: const Icon(Icons.phone_android), onPressed: _connectPhone, child: const Text('Connect phone (one click)')),
        MenuItemButton(leadingIcon: const Icon(Icons.videocam_outlined), onPressed: _openCameraInput, child: const Text('Camera or address…')),
        MenuItemButton(leadingIcon: const Icon(Icons.upload_file), onPressed: _uploadVideoSource, child: const Text('Video file…')),
        MenuItemButton(leadingIcon: const Icon(Icons.history), onPressed: _openReplay, child: const Text('Replay a saved run…')),
        MenuItemButton(leadingIcon: const Icon(Icons.restore), onPressed: _continueSaved, child: const Text('Continue a saved monitoring…')),
      ],
      builder: (context, controller, _) {
        final onPressed = _uploading ? null : () => controller.isOpen ? controller.close() : controller.open();   // not while a file is going up
        return compact
            ? IconButton(key: const ValueKey('change-source'), tooltip: 'Change source', icon: const Icon(Icons.swap_horiz), onPressed: onPressed)
            : OutlinedButton.icon(onPressed: onPressed, icon: const Icon(Icons.swap_horiz), label: const Text('Change source'));
      },
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
              title: _canResume ? 'Monitoring is off' : 'Set up the violations',
              message: _canResume
                  ? 'Source: $_sourceName\nMonitoring is stopped. Resume goes on with the same setup.'
                  : 'Source: $_sourceName\nPick a picture of the video, then choose what to watch for. Monitoring starts when you apply.',
              // First visit: ONE button. The setup is the start, so there is no separate Start button here.
              action: !_canResume
                  ? FilledButton.icon(
                      key: const ValueKey('live-setup-button'),
                      onPressed: (_preparingSetup || _uploading) ? null : _openSetup,
                      icon: _preparingSetup ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.tune),
                      label: const Text('Set up violations'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
                    )
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                if (_canResume) ...[
                  FilledButton.icon(
                    key: const ValueKey('resume-button'),
                    onPressed: _uploading ? null : _resume,
                    icon: const Icon(Icons.play_circle_outline),
                    label: Text(_resumeLabel),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
                  ),
                  const SizedBox(height: Fx.s12),
                ],
                FilledButton.icon(
                  onPressed: _uploading ? null : _startMonitoring,       // the new video is not the source yet
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start over (set up again)'),
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
