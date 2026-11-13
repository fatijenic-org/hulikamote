import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../domain/forensic_models.dart';
import '../../domain/review_controller.dart';
import 'fx.dart';
import 'replay_boxes.dart';

/// Builds the result-video panel. The default uses media_kit; tests pass a stand-in
/// because media_kit needs native libraries.
typedef VideoPanelBuilder =
    Widget Function(
      BuildContext context,
      String url,
      ValueListenable<double?> seekRequest,
      ReviewController controller,
    );

Widget defaultVideoPanel(
  BuildContext context,
  String url,
  ValueListenable<double?> seek,
  ReviewController c,
) => ForensicVideoPanel(url: url, seekRequest: seek, controller: c);

/// The annotated result video, with a timeline that shows where every ticket happens.
/// Selecting a ticket (or pressing "show this moment" on a photo) seeks the video.
/// The video can be zoomed (mouse wheel, drag to move, or the buttons below it). The boxes are drawn over it from boxes.json,
/// so their lines stay thin at any zoom; a replay made before that file existed still plays, with its boxes burned in.
class ForensicVideoPanel extends StatefulWidget {
  const ForensicVideoPanel({
    super.key,
    required this.url,
    required this.seekRequest,
    required this.controller,
  });

  final String url;
  final ValueListenable<double?> seekRequest;
  final ReviewController controller;

  @override
  State<ForensicVideoPanel> createState() => _ForensicVideoPanelState();
}

class _ForensicVideoPanelState extends State<ForensicVideoPanel> with SingleTickerProviderStateMixin {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double? _pendingSeek; // asked for before the video was ready
  final List<StreamSubscription<dynamic>> _subs = [];
  final TransformationController _zoom = TransformationController();
  final GlobalKey _viewKey = GlobalKey();
  final ValueNotifier<double> _seconds = ValueNotifier(0); // the video's time, followed every screen frame so the boxes keep up
  late final Ticker _ticker;
  ReplayBoxes? _boxes;
  bool _playing = false;
  static const double _maxZoom = 10;

  @override
  void initState() {
    super.initState();
    _player.open(Media(widget.url), play: false);
    _subs.add(
      _player.stream.duration.listen((d) {
        if (!mounted) return;
        setState(() => _duration = d);
        final pending = _pendingSeek;
        if (pending != null && d > Duration.zero) {
          _pendingSeek = null;
          _player.seek(Duration(milliseconds: (pending * 1000).round()));
        }
      }),
    );
    _subs.add(
      _player.stream.position.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
    );
    _subs.add(_player.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
    }));
    _ticker = createTicker((_) {
      final t = _player.state.position.inMilliseconds / 1000.0;
      if (t != _seconds.value) _seconds.value = t;
    })..start();
    _loadBoxes();
    widget.seekRequest.addListener(_onSeek);
    _onSeek(); // a moment may already have been asked for (the tab opens on "show this moment")
  }

  /// boxes.json sits next to the video. Older replays have none (404): they keep their burned-in boxes.
  Future<void> _loadBoxes() async {
    try {
      final uri = Uri.parse(widget.url);
      final path = [...uri.pathSegments.take(uri.pathSegments.length - 1), 'boxes.json'];
      final res = await http.get(uri.replace(pathSegments: path));
      if (res.statusCode != 200 || !mounted) return;
      final boxes = ReplayBoxes.fromJson(jsonDecode(res.body));
      if (mounted) setState(() => _boxes = boxes);
    } catch (_) {
      // no boxes file: the video is shown as it is
    }
  }

  /// Zoom the video by [factor] about the middle of the picture (1 = whole picture).
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

  @override
  void dispose() {
    widget.seekRequest.removeListener(_onSeek);
    _ticker.dispose();
    _zoom.dispose();
    _seconds.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  void _onSeek() {
    final s = widget.seekRequest.value;
    if (s == null) return;
    if (_duration == Duration.zero) {
      _pendingSeek = s; // the media is still opening
    } else {
      _player.seek(Duration(milliseconds: (s * 1000).round()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Fx.radius),
            child: Container(
              color: Colors.black,
              child: InteractiveViewer(
                key: _viewKey,
                transformationController: _zoom,
                minScale: 1,
                maxScale: _maxZoom,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Video(controller: _video, controls: NoVideoControls),
                    if (_boxes != null)
                      IgnorePointer(
                        child: CustomPaint(painter: ReplayBoxesPainter(boxes: _boxes!, seconds: _seconds, zoom: _zoom)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _transport(context),
        const SizedBox(height: Fx.s8),
        ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => TicketTimeline(
            controller: widget.controller,
            duration: _duration,
            position: _position,
            onSeek: (s) =>
                _player.seek(Duration(milliseconds: (s * 1000).round())),
          ),
        ),
      ],
    );
  }
}

/// Play / pause, the time, and the zoom buttons (the wheel and dragging work on the picture itself).
extension on _ForensicVideoPanelState {
  Widget _transport(BuildContext context) {
    String clock(Duration d) => formatVideoTime(d.inMilliseconds / 1000.0);
    return Row(
      children: [
        IconButton(
          tooltip: _playing ? 'Pause' : 'Play',
          onPressed: _player.playOrPause,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
        ),
        Text('${clock(_position)} / ${clock(_duration)}', style: Fx.caption(context)),
        const Spacer(),
        ListenableBuilder(
          listenable: _zoom,
          builder: (context, _) {
            final z = _zoom.value.getMaxScaleOnAxis();
            return Row(
              children: [
                IconButton(
                  tooltip: 'Zoom out',
                  onPressed: z > 1.001 ? () => _zoomBy(1 / 1.5) : null,
                  icon: const Icon(Icons.zoom_out),
                ),
                SizedBox(width: 46, child: Text('${(z * 100).round()}%', textAlign: TextAlign.center, style: Fx.caption(context))),
                IconButton(
                  tooltip: 'Zoom in',
                  onPressed: z < _ForensicVideoPanelState._maxZoom - 0.001 ? () => _zoomBy(1.5) : null,
                  icon: const Icon(Icons.zoom_in),
                ),
                IconButton(
                  tooltip: 'Whole picture',
                  onPressed: z > 1.001 ? () => _zoom.value = Matrix4.identity() : null,
                  icon: const Icon(Icons.fit_screen),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Where each ticket's evidence sits in the video (a lane per overlap), coloured by review status.
class TicketTimeline extends StatelessWidget {
  const TicketTimeline({
    super.key,
    required this.controller,
    required this.duration,
    required this.position,
    required this.onSeek,
  });

  final ReviewController controller;
  final Duration duration;
  final Duration position;
  final void Function(double seconds) onSeek;

  static const double laneHeight = 10, laneGap = 3, maxLanes = 5;

  /// First-fit lane for every ticket with a time span, in order of start time.
  static Map<String, int> assignLanes(List<ForensicTicket> tickets) {
    final spans = [
      for (final t in tickets)
        if (t.span != null) (t.uid, t.span!),
    ]..sort((a, b) => a.$2.start.compareTo(b.$2.start));
    final laneEnds = <double>[];
    final out = <String, int>{};
    for (final (uid, s) in spans) {
      var lane = laneEnds.indexWhere((end) => end + 0.25 <= s.start);
      if (lane < 0) {
        lane = laneEnds.length < maxLanes
            ? laneEnds.length
            : maxLanes.toInt() - 1;
        if (lane == laneEnds.length) laneEnds.add(s.end);
      }
      laneEnds[lane] = s.end > laneEnds[lane] ? s.end : laneEnds[lane];
      out[uid] = lane;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds / 1000.0;
    final tickets = controller.all;
    if (total <= 0 || tickets.every((t) => t.span == null)) {
      return SizedBox(
        height: 28,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Loading timeline…', style: Fx.caption(context)),
        ),
      );
    }
    final lanes = assignLanes(tickets);
    final laneCount = (lanes.values.fold<int>(0, (m, v) => v > m ? v : m)) + 1;
    final height = laneCount * (laneHeight + laneGap) + 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('WHERE THE TICKETS HAPPEN', style: Fx.label(context)),
            const Spacer(),
            Text(
              '${formatVideoTime(position.inMilliseconds / 1000)} / ${formatVideoTime(total)}',
              style: Fx.caption(context),
            ),
          ],
        ),
        const SizedBox(height: Fx.s8),
        LayoutBuilder(
          builder: (context, box) {
            void pick(double dx) {
              final secs = (dx / box.maxWidth).clamp(0.0, 1.0) * total;
              // The ticket under the tap (or nearest), then seek to the tapped moment.
              ForensicTicket? best;
              var bestDist = double.infinity;
              for (final t in tickets) {
                final s = t.span;
                if (s == null) continue;
                final d = secs < s.start
                    ? s.start - secs
                    : (secs > s.end ? secs - s.end : 0.0);
                if (d < bestDist) {
                  bestDist = d;
                  best = t;
                }
              }
              if (best != null && bestDist < total * 0.02) {
                controller.select(best.uid);
              }
              onSeek(secs);
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => pick(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => onSeek(
                (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0) * total,
              ),
              child: SizedBox(
                height: height,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TimelinePainter(
                    tickets: tickets,
                    lanes: lanes,
                    total: total,
                    position: position.inMilliseconds / 1000.0,
                    selected: controller.selectedUid,
                    status: controller.statusOf,
                    track: Fx.raised(context),
                    playhead: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.tickets,
    required this.lanes,
    required this.total,
    required this.position,
    required this.selected,
    required this.status,
    required this.track,
    required this.playhead,
  });

  final List<ForensicTicket> tickets;
  final Map<String, int> lanes;
  final double total;
  final double position;
  final String? selected;
  final ReviewStatus Function(ForensicTicket) status;
  final Color track;
  final Color playhead;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()..color = track,
    );
    for (final t in tickets) {
      final s = t.span;
      final lane = lanes[t.uid];
      if (s == null || lane == null) continue;
      final x1 = s.start / total * size.width;
      final x2 = (s.end / total * size.width).clamp(x1 + 4, size.width);
      final y =
          2.0 + lane * (TicketTimeline.laneHeight + TicketTimeline.laneGap);
      final base = Fx.statusColor(status(t));
      final isSel = t.uid == selected;
      final paint = Paint()
        ..color = isSel
            ? Fx.accent
            : base.withValues(
                alpha: status(t) == ReviewStatus.pending ? 0.55 : 0.9,
              );
      final r = RRect.fromRectAndRadius(
        Rect.fromLTRB(x1, y, x2, y + TicketTimeline.laneHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(r, paint);
      if (isSel) {
        canvas.drawRRect(
          r,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
    final px = (position / total).clamp(0.0, 1.0) * size.width;
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      Paint()
        ..color = playhead
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => true;
}
