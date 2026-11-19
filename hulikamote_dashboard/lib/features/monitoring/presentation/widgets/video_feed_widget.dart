import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../domain/models/detection.dart';
import '../../../forensic/presentation/widgets/replay_boxes.dart';
import 'processing_scan.dart';
import 'road_arrow.dart';
import 'package:hulikamote_dashboard/core/theme/light_mode.dart';

class VideoFeedWidget extends StatefulWidget {
  final Stream<dynamic>? stream;
  final Function(VideoFrame frame)? onFrame;

  /// The boxes arrive over the socket at once, but the picture takes the longer way through the encoder and the video
  /// relay, so without this the boxes run ahead of the vehicles. Boxes are shown this long after they arrive.
  final int boxDelayMs;

  /// Draw the learned traffic-flow arrows. The "TEST: FLOW REVERSED" banner is drawn whatever this says.
  final bool showFlow;

  /// The arrows of the incoming / outgoing sides of the road (set up in the Road step): shown or hidden.
  final bool showRoadArrows;

  /// The outlines, fills and labels of the set-up and learned zones (the arrows have their own switch).
  final bool showRoadZones;

  /// Told the backend's playback buffer state of each picture ({state, ahead_s, speed, pos_s, live}); a video file's pos_s is where on the video it is.
  final ValueChanged<Map<String, dynamic>?>? onBuffer;

  const VideoFeedWidget({super.key, this.stream, this.onFrame, this.onBuffer, this.boxDelayMs = 0, this.showFlow = true, this.showRoadArrows = true, this.showRoadZones = true});

  @override
  State<VideoFeedWidget> createState() => _VideoFeedWidgetState();
}

class _VideoFeedWidgetState extends State<VideoFeedWidget> {
  StreamSubscription? _sub;
  Uint8List? _frameBytes;
  List<Detection>? _detections;
  List<RoadZone> _roadZones = const [];
  FlowInfo? _flow;
  List<BoxSpec>? _specs;
  final TransformationController _zoom = TransformationController();   // mouse wheel, drag or the buttons, like the Forensic replay
  final GlobalKey _viewKey = GlobalKey();
  static const double _maxZoom = 10;
  int? _frameWidth;
  int? _frameHeight;
  final List<DateTime> _frameTimestamps = [];
  double _currentFps = 0.0;
  bool _isMock = false;
  bool _isWaiting = true;
  String? _error;
  
  final Set<Timer> _waiting = {};          // boxes waiting for the picture to catch up
  Map<String, dynamic>? _buffer;           // the backend's playback buffer: {state: filling | playing | done, percent, ahead_s, speed, need_s, live}
  Uint8List? _previewBytes;                // while it fills: the newest finished picture, for the "Processing" view only
  double? _previewW, _previewH;
  List<Rect> _previewBoxes = const [];

  String? _currentHlsUrl;
  Player? _player;
  VideoController? _videoController;
  
  // Track if video is playing correctly
  bool get isVideoReady => _videoController != null;

  @override
  void initState() {
    super.initState();
    if (widget.stream != null) {
      _subscribe();
    }
  }

  @override
  void didUpdateWidget(covariant VideoFeedWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stream != oldWidget.stream) {
      _sub?.cancel();
      if (widget.stream != null) {
        _subscribe();
      } else {
        setState(() {
          _isWaiting = true;
          _error = null;
        });
      }
    }
  }

  void _subscribe() {
    setState(() {
      _isWaiting = true;
      _error = null;
      _buffer = null;
    });

    _sub = widget.stream!.listen(
      (message) {
        try {
          final data = jsonDecode(message);
          if (data is Map && data['type'] == 'buffer') {   // the picture is not ready yet: "Processing... 60%"
            final pv = data['preview'];
            Uint8List? bytes;
            var boxes = <Rect>[];
            if (pv is Map && pv['picture'] is String) {
              bytes = base64Decode(pv['picture'] as String);
              for (final b in (pv['boxes'] as List? ?? const [])) {
                if (b is List && b.length >= 4) boxes.add(Rect.fromLTWH((b[0] as num).toDouble(), (b[1] as num).toDouble(), (b[2] as num).toDouble(), (b[3] as num).toDouble()));
              }
            }
            if (mounted) {
              setState(() {
                _buffer = Map<String, dynamic>.from(data);
                if (bytes != null) {
                  _previewBytes = bytes;
                  _previewW = (pv as Map)['w'] is num ? ((pv['w']) as num).toDouble() : null;
                  _previewH = pv['h'] is num ? ((pv['h']) as num).toDouble() : null;
                  _previewBoxes = boxes;
                }
              });
            }
            return;
          }
          if (data is Map && data['type'] == 'status') return; // camera silent / offline: no picture to draw
          final frame = VideoFrame.fromJson(data);
          
          widget.onFrame?.call(frame);
          
          Uint8List? nextFrame;
          if (frame.frameBase64 != null && frame.frameBase64!.isNotEmpty) {
            nextFrame = base64Decode(frame.frameBase64!);
          }
          
          // HLS Transport Handling
          if (frame.transport == 'hls' && frame.hlsUrl != null) {
            if (_currentHlsUrl != frame.hlsUrl) {
              _currentHlsUrl = frame.hlsUrl;
              _initVideoPlayer(_currentHlsUrl!);
            }
          }

          if (mounted) {
            final now = DateTime.now();
            _frameTimestamps.add(now);
            _frameTimestamps.removeWhere((t) => now.difference(t).inMilliseconds > 1000);

            setState(() {
              _currentFps = _frameTimestamps.length.toDouble();
              if (nextFrame != null) _frameBytes = nextFrame;
              final buf = data is Map ? data['buffer'] : null;
              _buffer = buf is Map ? Map<String, dynamic>.from(buf) : null;
              widget.onBuffer?.call(_buffer);
              _previewBytes = null;
              _previewBoxes = const [];
              if (widget.boxDelayMs <= 0 || frame.transport != 'hls') {   // a picture sent with the boxes needs no delay
                _detections = frame.detections;
                _roadZones = frame.roadZones;
                _flow = frame.flow;
                _specs = frame.boxes;
              } else {
                final boxes = frame.detections;
                final zones = frame.roadZones;
                final flow = frame.flow;
                final specs = frame.boxes;
                late final Timer timer;
                timer = Timer(Duration(milliseconds: widget.boxDelayMs), () {
                  _waiting.remove(timer);
                  if (mounted) {
                    setState(() {
                      _detections = boxes;
                      _roadZones = zones;
                      _flow = flow;
                      _specs = specs;
                    });
                  }
                });
                _waiting.add(timer);
              }
              if (frame.frameWidth != null) _frameWidth = frame.frameWidth;
              if (frame.frameHeight != null) _frameHeight = frame.frameHeight;
              _isMock = frame.mock;
              _isWaiting = false;
              _error = null;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() => _error = 'Error parsing frame: $e');
          }
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _error = 'Stream connection error';
            _isWaiting = true;
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() => _isWaiting = true);
        }
      },
    );
  }

  Future<void> _initVideoPlayer(String url) async {
    final oldPlayer = _player;
    final oldController = _videoController;
    
    try {
      final newPlayer = Player();
      final platform = newPlayer.platform;
      if (platform is NativePlayer) {
        // Show pictures as they arrive instead of buffering seconds ahead: the less the picture lags, the closer the boxes.
        await platform.setProperty('profile', 'low-latency');
        await platform.setProperty('cache', 'no');
      }
      final newController = VideoController(newPlayer);
      
      await newPlayer.open(Media(url));
      
      if (!mounted) {
        newPlayer.dispose();
        return;
      }

      setState(() {
        _player = newPlayer;
        _videoController = newController;
        _error = null;
      });
      
      oldPlayer?.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load video stream (MediaMTX offline?): $e';
        _isWaiting = false;
      });
    }
  }

  @override
  void dispose() {
    for (final t in _waiting) {
      t.cancel();
    }
    _sub?.cancel();
    _player?.dispose();
    _zoom.dispose();
    super.dispose();
  }

  /// Zoom by [factor] about the middle of the picture (1 = whole picture).
  void _zoomBy(double factor) {
    final size = _viewKey.currentContext?.size;
    if (size == null) return;
    final now = _zoom.value.getMaxScaleOnAxis();
    final target = (now * factor).clamp(1.0, _maxZoom);
    if (target <= 1.001) {
      _zoom.value = Matrix4.identity();
      return;
    }
    final k = target / now;
    final c = Offset(size.width / 2, size.height / 2);
    _zoom.value = Matrix4.translationValues(c.dx, c.dy, 0) * Matrix4.diagonal3Values(k, k, 1) * Matrix4.translationValues(-c.dx, -c.dy, 0) * _zoom.value;
  }

  Widget _zoomBar() {
    return ListenableBuilder(
      listenable: _zoom,
      builder: (context, _) {
        final z = _zoom.value.getMaxScaleOnAxis();
        Widget button(String tip, IconData icon, VoidCallback? onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, size: 18, color: onTap == null ? Colors.white30 : Colors.white),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        );
        return Container(
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            button('Zoom out', Icons.zoom_out, z > 1.001 ? () => _zoomBy(1 / 1.5) : null),
            SizedBox(width: 40, child: Text('${(z * 100).round()}%', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11))),
            button('Zoom in', Icons.zoom_in, z < _maxZoom - 0.001 ? () => _zoomBy(1.5) : null),
            button('Whole picture', Icons.fit_screen, z > 1.001 ? () => _zoom.value = Matrix4.identity() : null),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // The picture keeps its own shape. The box is centred (so the parent cannot stretch it) and the boxes are drawn on
    // exactly the same rectangle, so they stay on the vehicles.
    final ratio = (_frameWidth != null && _frameHeight != null && _frameHeight! > 0) ? _frameWidth! / _frameHeight! : 16.0 / 9.0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: widget.stream == null
          ? const _DisconnectedView()
          : _isWaiting
          ? _waitingView()
          : _error != null
          ? _errorBox(_error!)
          : Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: ratio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    InteractiveViewer(
                      key: _viewKey,
                      transformationController: _zoom,
                      minScale: 1,
                      maxScale: _maxZoom,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                    if (isVideoReady)
                      KeepColors(child: Video(
                        controller: _videoController!,
                        fit: BoxFit.contain,
                      ))
                    else if (_frameBytes != null)
                    KeepColors(child: Image.memory(
                      _frameBytes!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                      isAntiAlias: false,
                    ))
                  else
                    Container(
                      color: Colors.black,
                      child: const _MockFeedPlaceholder(),
                    ),
                  
                  // JSON Overlay Architecture: Draw the bounding boxes in Flutter natively!
                  if (_detections != null)
                    CustomPaint(
                      painter: BoundingBoxPainter(
                        _detections!,
                        streamWidth: _frameWidth?.toDouble() ?? 1280.0,
                        streamHeight: _frameHeight?.toDouble() ?? 720.0,
                        roadZones: _roadZones,
                        flow: _flow,
                        specs: _specs,
                        zoom: _zoom,
                        showFlow: widget.showFlow,
                        showRoadArrows: widget.showRoadArrows,
                        showRoadZones: widget.showRoadZones,
                      ),
                      size: Size.infinite,
                    ),
                        ],
                      ),
                    ),

                  Positioned(
                    top: 8,
                    right: 8,
                    child: _ModeBadge(isMock: _isMock),
                  ),

                  Positioned(bottom: 8, right: 8, child: _zoomBar()),

                  // The playback buffer: "Processing..." while it fills (also when it ran dry), and how late / how slow the picture is.
                  if (_buffer?['state'] == 'filling') const Positioned.fill(child: ProcessingScan(overPicture: true)),
                  if (_buffer?['state'] == 'playing') Positioned(top: 8, left: 8, child: _bufferChip(_buffer!)),

                  // FPS Meter
                  Positioned(
                    top: 40,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_currentFps.toStringAsFixed(1)} FPS',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
    );
  }

  /// Before the first picture: a spinner, or, while the backend fills its buffer, the "Processing" view.
  Widget _waitingView() {
    final b = _buffer;
    return b != null && b['state'] == 'filling'
        ? ProcessingScan(picture: _previewBytes, pictureWidth: _previewW, pictureHeight: _previewH, boxes: _previewBoxes)
        : const Center(child: CircularProgressIndicator());
  }

  /// A live camera: how late the picture is. A video file: how much is ready, and "slow motion" when the backend is slower than the video.
  Widget _bufferChip(Map<String, dynamic> b) {
    final speed = (b['speed'] as num?)?.toDouble() ?? 1.0;
    final ahead = (b['ahead_s'] as num?)?.toDouble() ?? 0.0;
    final live = b['live'] == true;
    final slow = !live && speed < 0.97;
    final text = live
        ? 'Delayed ${ahead.toStringAsFixed(1)} s'
        : slow
        ? 'Slow motion ${speed.toStringAsFixed(2)}×  ·  ${ahead.toStringAsFixed(1)} s ready'
        : '${ahead.toStringAsFixed(1)} s ready';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: slow ? Colors.amberAccent : Colors.white70, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  Widget _errorBox(String msg) => Center(
    child: Text(
      msg,
      style: const TextStyle(color: Colors.redAccent, fontSize: 16),
    ),
  );
}

/// Draws the detections over the video: a box and label per vehicle (red when flagged) and, for a flagged one,
/// the "why" boxes in red with their labels.
class BoundingBoxPainter extends CustomPainter {
  final List<Detection> detections;
  final double streamWidth;
  final double streamHeight;
  final List<RoadZone> roadZones;
  final FlowInfo? flow;
  final bool showFlow;
  final bool showRoadArrows;
  final bool showRoadZones;

  /// The boxes as the Forensic Analyzer draws them (label lines, colours, plate, why-marks, stopwatch). Null: [detections] are drawn plain.
  final List<BoxSpec>? specs;

  /// The zoom of the picture the painter sits on: box lines and label text stay the same size on screen when it is zoomed.
  final TransformationController? zoom;

  BoundingBoxPainter(
    this.detections, {
    this.streamWidth = 1280.0,
    this.streamHeight = 720.0,
    this.roadZones = const [],
    this.flow,
    this.showFlow = true,
    this.showRoadArrows = true,
    this.showRoadZones = true,
    this.specs,
    this.zoom,
  }) : super(repaint: zoom);

  /// The learned traffic flow: an arrow per block (teal; amber while the demo reversal is on, like the saved photos), with a dark
  /// edge so it shows on any road. Hidden by the Live Monitor's "Flow arrows" switch.
  void _paintFlow(Canvas canvas, double scaleX, double scaleY) {
    final info = flow;
    if (info == null || !showFlow || info.arrows.isEmpty) return;
    final ink = info.reversed ? const Color(0xFFFF8C00) : const Color(0xFF00BEAA);
    final shadow = Paint()
      ..color = const Color(0xFF1E1E1E).withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = ink.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final a in info.arrows) {
      final tail = Offset(a.x1 * scaleX, a.y1 * scaleY);
      final head = Offset(a.x2 * scaleX, a.y2 * scaleY);
      final path = Path()..moveTo(tail.dx, tail.dy)..lineTo(head.dx, head.dy);
      final d = head - tail;
      if (d.distance > 0) {
        final wing = d.distance * 0.35;
        final angle = math.atan2(d.dy, d.dx);
        for (final side in const [math.pi / 6, -math.pi / 6]) {
          path
            ..moveTo(head.dx, head.dy)
            ..lineTo(head.dx - wing * math.cos(angle - side), head.dy - wing * math.sin(angle - side));
        }
      }
      canvas.drawPath(path, shadow);
      canvas.drawPath(path, line);
    }
  }

  /// While the demo reversal is on: tickets made now are tests. This label is always drawn, whatever the arrows switch says.
  void _paintReversedBanner(Canvas canvas) {
    final text = TextPainter(
      text: const TextSpan(text: 'TEST: FLOW REVERSED', style: TextStyle(color: Color(0xFF141414), fontSize: 13, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(10, 10, text.width + 20, text.height + 12), const Radius.circular(4));
    canvas.drawRRect(box, Paint()..color = const Color(0xFFFF8C00));
    text.paint(canvas, const Offset(20, 16));
  }

  /// The zones the system learned from the road paint, and the ones the operator set up, under the boxes: a soft fill, a dashed
  /// outline and a label. Learned lines are amber and say "best effort": the finder is weaker there. Set-up zones are orange.
  void _paintRoadZones(Canvas canvas, double scaleX, double scaleY) {
    for (final zone in roadZones) {
      final hasArea = zone.polygon.length >= 3;
      if (!hasArea && zone.line.length < 2) continue;          // a line alone (a drawn solid line) is shown too
      final pts = [for (final p in zone.polygon) Offset(p[0] * scaleX, p[1] * scaleY)];
      final linePts = [for (final p in zone.line) Offset(p[0] * scaleX, p[1] * scaleY)];
      final colour = switch (zone.violation) {
        'road' => flowColour(zone.flow),
        'sidewalk' => Colors.lightGreenAccent,
        _ => zone.drawn ? Colors.orangeAccent : (zone.hint ? Colors.white70 : (zone.bestEffort ? Colors.amberAccent : Colors.cyanAccent)),
      };
      final edge = Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      if (showRoadZones && hasArea) {
        final path = Path()..addPolygon(pts, true);
        canvas.drawPath(path, Paint()..color = colour.withValues(alpha: zone.hint ? 0.07 : 0.16)..style = PaintingStyle.fill);
        for (var i = 0; i < pts.length; i++) {
          _dashed(canvas, pts[i], pts[(i + 1) % pts.length], edge);
        }
      }
      if (showRoadZones && linePts.length >= 2) {
        edge.strokeWidth = 3.0;
        for (var i = 0; i < linePts.length - 1; i++) {
          canvas.drawLine(linePts[i], linePts[i + 1], edge);
        }
      }
      if (showRoadArrows && (zone.flow != null || zone.violation == 'counterflow') && zone.arrow.length >= 2) {          // the way the traffic goes on this side of the road
        paintRoadPath(canvas, [for (final p in zone.arrow) Offset(p[0] * scaleX, p[1] * scaleY)], colour, width: 5, head: 20);
      }
      if (!showRoadZones) continue;                          // hidden: no label either
      final labelPts = hasArea ? pts : linePts;
      final text = TextPainter(
        text: TextSpan(
          text: ' ${zone.label} ',
          style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold, backgroundColor: colour),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final top = labelPts.map((p) => p.dy).reduce(math.min);
      final left = labelPts.map((p) => p.dx).reduce(math.min);
      text.paint(canvas, Offset(left, math.max(0, top - text.height)));
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, {double dash = 9, double gap = 6}) {
    final length = (b - a).distance;
    if (length == 0) return;
    final dir = (b - a) / length;
    for (double d = 0; d < length; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, length), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / streamWidth;
    final double scaleY = size.height / streamHeight;
    _paintRoadZones(canvas, scaleX, scaleY);
    _paintFlow(canvas, scaleX, scaleY);

    final shared = specs;
    if (shared != null) {
      canvas.save();
      canvas.scale(scaleX, scaleY);
      ReplayBoxesPainter.paintSpecs(canvas, shared, streamWidth, streamHeight, 1 / (scaleX * (zoom?.value.getMaxScaleOnAxis() ?? 1.0)));
      canvas.restore();
      if (flow?.reversed == true) _paintReversedBanner(canvas);
      return;
    }

    for (final det in detections) {
      if (det.bbox.length != 4) continue;
      
      final double x = det.bbox[0] * scaleX;
      final double y = det.bbox[1] * scaleY;
      final double w = det.bbox[2] * scaleX;
      final double h = det.bbox[3] * scaleY;
      
      final rect = Rect.fromLTWH(x, y, w, h);
      
      final isViolator = det.isViolator;
      final color = isViolator ? Colors.redAccent : Colors.greenAccent;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawRect(rect, paint);

      // Draw Label Background
      final textStyle = TextStyle(
        color: Colors.black,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        backgroundColor: color,
      );
      
      final label = '${det.cls.toUpperCase()} ${det.trackId ?? ""}';
      final textSpan = TextSpan(text: ' $label ', style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      
      // Draw text above the box
      textPainter.paint(canvas, Offset(x, y - textPainter.height));

      // Why it was flagged: the bare head, the phone, each rider...
      for (final mark in det.marks) {
        if (mark.bbox.length != 4) continue;
        final markRect = Rect.fromLTWH(
          mark.bbox[0] * scaleX,
          mark.bbox[1] * scaleY,
          mark.bbox[2] * scaleX,
          mark.bbox[3] * scaleY,
        );
        canvas.drawRect(
          markRect,
          Paint()
            ..color = Colors.redAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0,
        );
        if (mark.label.isEmpty) continue;
        final markText = TextPainter(
          text: TextSpan(
            text: ' ${mark.label} ',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              backgroundColor: Colors.redAccent,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        markText.paint(canvas, Offset(markRect.left, math.max(0, markRect.top - markText.height)));
      }
    }
    if (flow?.reversed == true) _paintReversedBanner(canvas);        // last, on top of everything
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) => true;
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _ModeBadge extends StatelessWidget {
  final bool isMock;
  const _ModeBadge({required this.isMock});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isMock
            ? Colors.orange.withAlpha(200)
            : Colors.green.withAlpha(200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isMock ? 'MOCK' : 'LIVE',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _MockFeedPlaceholder extends StatelessWidget {
  const _MockFeedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam, size: 64, color: Colors.grey.shade700),
          const SizedBox(height: 12),
          Text(
            'Simulated Video Feed',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Set USE_MOCK = False in store.py for live inference',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DisconnectedView extends StatelessWidget {
  const _DisconnectedView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Awaiting stream...', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
