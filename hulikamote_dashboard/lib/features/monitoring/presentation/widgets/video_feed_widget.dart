import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../domain/models/detection.dart';

class VideoFeedWidget extends StatefulWidget {
  final Stream<dynamic>? stream;
  final Function(VideoFrame frame)? onFrame;

  /// The boxes arrive over the socket at once, but the picture takes the longer way through the encoder and the video
  /// relay, so without this the boxes run ahead of the vehicles. Boxes are shown this long after they arrive.
  final int boxDelayMs;

  const VideoFeedWidget({super.key, this.stream, this.onFrame, this.boxDelayMs = 0});

  @override
  State<VideoFeedWidget> createState() => _VideoFeedWidgetState();
}

class _VideoFeedWidgetState extends State<VideoFeedWidget> {
  StreamSubscription? _sub;
  Uint8List? _frameBytes;
  List<Detection>? _detections;
  List<RoadZone> _roadZones = const [];
  int? _frameWidth;
  int? _frameHeight;
  final List<DateTime> _frameTimestamps = [];
  double _currentFps = 0.0;
  bool _isMock = false;
  bool _isWaiting = true;
  String? _error;
  
  final Set<Timer> _waiting = {};          // boxes waiting for the picture to catch up

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
    });

    _sub = widget.stream!.listen(
      (message) {
        try {
          final data = jsonDecode(message);
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
              if (widget.boxDelayMs <= 0 || frame.transport != 'hls') {   // a picture sent with the boxes needs no delay
                _detections = frame.detections;
                _roadZones = frame.roadZones;
              } else {
                final boxes = frame.detections;
                final zones = frame.roadZones;
                late final Timer timer;
                timer = Timer(Duration(milliseconds: widget.boxDelayMs), () {
                  _waiting.remove(timer);
                  if (mounted) {
                    setState(() {
                      _detections = boxes;
                      _roadZones = zones;
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
    super.dispose();
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
          ? const Center(child: CircularProgressIndicator())
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
                    if (isVideoReady)
                      Video(
                        controller: _videoController!,
                        fit: BoxFit.contain,
                      )
                    else if (_frameBytes != null)
                    Image.memory(
                      _frameBytes!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                      isAntiAlias: false,
                    )
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
                      ),
                      size: Size.infinite,
                    ),

                  Positioned(
                    top: 8,
                    right: 8,
                    child: _ModeBadge(isMock: _isMock),
                  ),

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

  BoundingBoxPainter(this.detections, {this.streamWidth = 1280.0, this.streamHeight = 720.0, this.roadZones = const []});

  /// The zones the system learned from the road paint, under the boxes: a soft fill, a dashed outline and a label.
  /// Lines are amber and say "best effort": the finder is weaker there.
  void _paintRoadZones(Canvas canvas, double scaleX, double scaleY) {
    for (final zone in roadZones) {
      if (zone.polygon.length < 3) continue;
      final pts = [for (final p in zone.polygon) Offset(p[0] * scaleX, p[1] * scaleY)];
      final colour = switch (zone.violation) {
        'road' => Colors.lightBlueAccent,
        'sidewalk' => Colors.lightGreenAccent,
        _ => zone.hint ? Colors.white70 : (zone.bestEffort ? Colors.amberAccent : Colors.cyanAccent),
      };
      final path = Path()..addPolygon(pts, true);
      canvas.drawPath(path, Paint()..color = colour.withValues(alpha: zone.hint ? 0.07 : 0.16)..style = PaintingStyle.fill);
      final edge = Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      for (var i = 0; i < pts.length; i++) {
        _dashed(canvas, pts[i], pts[(i + 1) % pts.length], edge);
      }
      if (zone.line.length == 2) {
        canvas.drawLine(
          Offset(zone.line[0][0] * scaleX, zone.line[0][1] * scaleY),
          Offset(zone.line[1][0] * scaleX, zone.line[1][1] * scaleY),
          edge..strokeWidth = 3.0,
        );
      }
      final text = TextPainter(
        text: TextSpan(
          text: ' ${zone.label} ',
          style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold, backgroundColor: colour),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final top = pts.map((p) => p.dy).reduce(math.min);
      final left = pts.map((p) => p.dx).reduce(math.min);
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
