import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/timeline_geometry.dart';
import 'trim_timeline.dart' show PlayheadPainter, paintTimelineRuler;

/// One range on a timeline: the part of the video to keep. Drag the left or right end to move it (the video jumps to that
/// frame so the cut can be judged), drag anywhere else (or along the ruler) to scrub through the video like a player.
/// Ctrl + mouse wheel zooms in for frame-exact work.
class RangeTimeline extends StatefulWidget {
  const RangeTimeline({
    super.key,
    required this.duration,
    required this.start,
    required this.end,
    required this.position,
    required this.onSeek,
    required this.onRange,
    this.onInteract,
    this.filmstripUrl,
    this.zoom = 1,
    this.onZoom,
    this.height = 100,
  });

  /// Seconds, all of them.
  final double duration;

  /// The part that is kept, in seconds.
  final double start;
  final double end;
  final ValueListenable<double> position;

  /// The video should show this moment (scrubbing, clicking, or a dragged end).
  final void Function(double seconds) onSeek;
  final void Function({double? start, double? end}) onRange;

  /// The pointer touched the timeline (the screen takes the keyboard back).
  final VoidCallback? onInteract;
  final String? filmstripUrl;
  final double zoom;
  final void Function(double zoom)? onZoom;
  final double height;

  @override
  State<RangeTimeline> createState() => _RangeTimelineState();
}

enum _Grab { none, start, end, scrub }

class _RangeTimelineState extends State<RangeTimeline> {
  static const _rulerHeight = 22.0;
  static const _handleWidth = 12.0;

  final _scroll = ScrollController();
  TimelineGeometry _geo = const TimelineGeometry(width: 1, duration: 1);
  double _viewport = 1;
  _Grab _grab = _Grab.none;
  double _grabGap = 0;          // seconds between the pointer and the end it holds, so the end does not jump when grabbed off-centre

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_followPlayhead);
  }

  @override
  void didUpdateWidget(RangeTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      oldWidget.position.removeListener(_followPlayhead);
      widget.position.addListener(_followPlayhead);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_followPlayhead);
    _scroll.dispose();
    super.dispose();
  }

  /// When zoomed in, keep the playhead in view (while playing, or after a jump).
  void _followPlayhead() {
    if (widget.zoom <= 1 || !_scroll.hasClients) return;
    final x = _geo.xOf(widget.position.value);
    if (x < _scroll.offset || x > _scroll.offset + _viewport) {
      _scroll.jumpTo((x - _viewport * 0.2).clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  /// A dragged end snaps onto the playhead when it comes close, so "cut exactly here" is easy.
  double _snap(double t) {
    final p = widget.position.value;
    return (_geo.xOf(t) - _geo.xOf(p)).abs() <= 6 ? p : t;
  }

  _Grab _hit(Offset at) {
    if (at.dy < _rulerHeight) return _Grab.scrub;
    // A very short part: the two handles overlap, so the side of the middle the pointer is on decides.
    final left = _geo.xOf(widget.start), right = _geo.xOf(widget.end);
    if (right - left < 2 * _handleWidth) {
      return (at.dx >= left - _handleWidth && at.dx <= right + _handleWidth)
          ? (at.dx < (left + right) / 2 ? _Grab.start : _Grab.end)
          : _Grab.scrub;
    }
    // The handles sit just inside the kept part (so they stay visible at the very start and end of the video).
    final toStart = (at.dx - (_geo.xOf(widget.start) + _handleWidth / 2)).abs();
    final toEnd = (at.dx - (_geo.xOf(widget.end) - _handleWidth / 2)).abs();
    const slop = _handleWidth / 2 + 4;
    if (toStart > slop && toEnd > slop) return _Grab.scrub;
    // Both on top of each other (a very short part): the side of the middle the pointer is on decides, so either can be pulled away.
    if ((toStart - toEnd).abs() < 0.5) return at.dx < (_geo.xOf(widget.start) + _geo.xOf(widget.end)) / 2 ? _Grab.start : _Grab.end;
    return toStart < toEnd ? _Grab.start : _Grab.end;
  }

  void _onPanDown(DragDownDetails d) {
    widget.onInteract?.call();
    _grab = _hit(d.localPosition);
    final pointer = _geo.tOf(d.localPosition.dx);
    _grabGap = switch (_grab) {
      _Grab.start => pointer - widget.start,
      _Grab.end => pointer - widget.end,
      _ => 0,
    };
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final t = _geo.tOf(d.localPosition.dx);
    switch (_grab) {
      case _Grab.start:
        final snapped = _snap(t - _grabGap).clamp(0.0, widget.duration);
        widget.onRange(start: snapped);
        widget.onSeek(snapped.clamp(0.0, widget.end));
      case _Grab.end:
        final snapped = _snap(t - _grabGap).clamp(0.0, widget.duration);
        widget.onRange(end: snapped);
        widget.onSeek(snapped.clamp(widget.start, widget.duration));
      case _Grab.scrub:
        widget.onSeek(t);
      case _Grab.none:
        break;
    }
  }

  void _onPanEnd([Object? _]) => _grab = _Grab.none;

  void _onTapUp(TapUpDetails d) {
    if (_hit(d.localPosition) == _Grab.scrub) widget.onSeek(_geo.tOf(d.localPosition.dx));
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) {
      widget.onZoom?.call((widget.zoom * (event.scrollDelta.dy < 0 ? 1.25 : 0.8)).clamp(1.0, 200.0));
    } else if (_scroll.hasClients) {
      _scroll.jumpTo((_scroll.offset + event.scrollDelta.dy + event.scrollDelta.dx).clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      _viewport = constraints.maxWidth;
      final width = _viewport * widget.zoom;
      _geo = TimelineGeometry(width: width, duration: widget.duration);
      return Listener(
        onPointerSignal: _onPointerSignal,
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),     // dragging scrubs or moves an end; the scrollbar and wheel scroll
            child: SizedBox(
              width: width,
              height: widget.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: _onPanDown,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                onPanCancel: _onPanEnd,
                onTapUp: _onTapUp,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(fit: StackFit.expand, children: [
                    ColoredBox(color: scheme.surfaceContainerHighest),
                    if (widget.filmstripUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(top: _rulerHeight),
                        child: Opacity(
                          opacity: 0.6,
                          child: Image.network(widget.filmstripUrl!, fit: BoxFit.fill, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                        ),
                      ),
                    CustomPaint(
                      painter: _RangePainter(
                        geo: _geo,
                        start: widget.start,
                        end: widget.end,
                        rulerHeight: _rulerHeight,
                        handleWidth: _handleWidth,
                        accent: scheme.primary,
                        textColor: scheme.onSurface,
                        shade: scheme.surface.withValues(alpha: 0.72),
                      ),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: widget.position,
                      builder: (context, position, _) => CustomPaint(painter: PlayheadPainter(x: _geo.xOf(position), height: widget.height)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _RangePainter extends CustomPainter {
  _RangePainter({
    required this.geo,
    required this.start,
    required this.end,
    required this.rulerHeight,
    required this.handleWidth,
    required this.accent,
    required this.textColor,
    required this.shade,
  });

  final TimelineGeometry geo;
  final double start;
  final double end;
  final double rulerHeight;
  final double handleWidth;
  final Color accent;
  final Color textColor;
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    paintTimelineRuler(canvas, size, geo, rulerHeight, textColor);

    final x1 = geo.xOf(start), x2 = geo.xOf(end);
    // what is left out is dimmed
    final dim = Paint()..color = shade;
    canvas.drawRect(Rect.fromLTRB(0, rulerHeight, x1, size.height), dim);
    canvas.drawRect(Rect.fromLTRB(x2, rulerHeight, size.width, size.height), dim);

    // the part that is kept
    final frame = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(Rect.fromLTRB(x1, rulerHeight + 1.5, x2, size.height - 1.5), frame);

    // the two ends
    final bar = Paint()..color = accent;
    final grip = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 1.5;
    for (final isStart in [true, false]) {
      final rect = RRect.fromLTRBR(
        isStart ? x1 : x2 - handleWidth,
        rulerHeight,
        isStart ? x1 + handleWidth : x2,
        size.height,
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, bar);
      final mid = rect.left + handleWidth / 2;
      canvas.drawLine(Offset(mid - 2, rulerHeight + 14), Offset(mid - 2, size.height - 14), grip);
      canvas.drawLine(Offset(mid + 2, rulerHeight + 14), Offset(mid + 2, size.height - 14), grip);
    }
  }

  @override
  bool shouldRepaint(_RangePainter old) =>
      old.geo.width != geo.width || old.geo.duration != geo.duration || old.start != start || old.end != end || old.accent != accent || old.textColor != textColor;
}
