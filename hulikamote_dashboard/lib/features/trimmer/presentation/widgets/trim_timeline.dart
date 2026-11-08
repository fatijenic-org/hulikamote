import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/time_format.dart';
import '../../domain/timeline_geometry.dart';
import '../../domain/trim_session.dart';

/// Colours of the clips. Every clip also shows its number, so colour is never the only sign.
const clipColors = [
  Color(0xFF4C8DFF), Color(0xFF3CCB8C), Color(0xFFFFB454), Color(0xFFB57CFF), Color(0xFFFF6B8B), Color(0xFF3CC4D8),
];

Color clipColor(TrimClip c) => clipColors[(c.id - 1) % clipColors.length];

/// The strip under the video. Drag the left or right edge of a clip to trim it, drag its middle to slide it, drag on an
/// empty spot to make a new clip, click to move the playhead. Locked clips only select. Ctrl + mouse wheel zooms.
class TrimTimeline extends StatefulWidget {
  const TrimTimeline({
    super.key,
    required this.session,
    required this.position,
    required this.onSeek,
    this.filmstripUrl,
    this.onInteract,
    this.zoom = 1,
    this.onZoom,
    this.height = 112,
  });

  final TrimSession session;
  final ValueListenable<double> position;
  final void Function(double seconds) onSeek;

  /// Called when the pointer touches the timeline, so the screen takes back the keyboard from any box being typed in.
  final VoidCallback? onInteract;

  /// A wide picture of frames to show behind the clips; the plain bar is used if it cannot be loaded.
  final String? filmstripUrl;

  /// 1 = the whole video fits; more = zoomed in (the strip scrolls sideways).
  final double zoom;
  final void Function(double zoom)? onZoom;
  final double height;

  @override
  State<TrimTimeline> createState() => _TrimTimelineState();
}

enum _Drag { none, start, end, body, create, scrub }

class _TrimTimelineState extends State<TrimTimeline> {
  static const _rulerHeight = 22.0;

  final _scroll = ScrollController();
  TimelineGeometry _geo = const TimelineGeometry(width: 1, duration: 1);
  TimelineHit _down = const TimelineHit(HitKind.empty);
  double _downX = 0;           // where the pointer went down (a drag is only noticed a few pixels later)
  double _downY = 0;
  _Drag _drag = _Drag.none;
  int? _clipId;
  double _grabOffset = 0;      // body drag: where inside the clip it was grabbed
  double _anchor = 0;          // create drag: where it began
  double _viewport = 1;

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_followPlayhead);
  }

  @override
  void didUpdateWidget(TrimTimeline old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      old.position.removeListener(_followPlayhead);
      widget.position.addListener(_followPlayhead);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_followPlayhead);
    _scroll.dispose();
    super.dispose();
  }

  /// When zoomed in, scroll so the playhead stays in view (while playing, or after a jump from the clip list).
  void _followPlayhead() {
    if (widget.zoom <= 1 || !_scroll.hasClients) return;
    final x = _geo.xOf(widget.position.value);
    final left = _scroll.offset;
    if (x < left || x > left + _viewport) {
      _scroll.jumpTo((x - _viewport * 0.2).clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  TrimSession get _s => widget.session;
  bool get _multi => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed || HardwareKeyboard.instance.isMetaPressed;

  /// The playhead's time, so a handle that is dragged close to it snaps onto it.
  double _snap(double t) {
    final p = widget.position.value;
    return (_geo.xOf(t) - _geo.xOf(p)).abs() <= 6 ? p : t;
  }

  void _onPanDown(DragDownDetails d) {
    widget.onInteract?.call();
    _downX = d.localPosition.dx;
    _downY = d.localPosition.dy;
    _down = _geo.hit(_downX, _s.clips, _s.selected);
    _drag = _Drag.none;
  }

  void _onPanStart(DragStartDetails d) {
    final hit = _down;
    final clip = hit.clip;
    if (_downY < _rulerHeight) {
      _drag = _Drag.scrub;                 // the ruler: move the playhead, like scrubbing a video
      return;
    }
    if (hit.kind == HitKind.empty) {
      _drag = _Drag.create;
      _anchor = _snap(_geo.tOf(_downX));
      _clipId = null;
      return;
    }
    _clipId = clip!.id;
    if (!_s.selected.contains(clip.id) || _s.selected.length > 1) _s.select(clip.id);
    if (clip.locked) {
      _drag = _Drag.none;                  // locked: selecting is all a drag does
      return;
    }
    _drag = switch (hit.kind) {
      HitKind.start => _Drag.start,
      HitKind.end => _Drag.end,
      _ => _Drag.body,
    };
    _grabOffset = _geo.tOf(_downX) - (hit.kind == HitKind.end ? clip.end : clip.start);   // an edge moves with the pointer, it does not jump
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final t = _geo.tOf(d.localPosition.dx);
    final id = _clipId;
    switch (_drag) {
      case _Drag.start:
        _s.setStart(id!, _snap(t - _grabOffset));
      case _Drag.end:
        _s.setEnd(id!, _snap(t - _grabOffset));
      case _Drag.body:
        _s.moveClip(id!, t - _grabOffset);
      case _Drag.create:
        if ((_geo.xOf(t) - _geo.xOf(_anchor)).abs() < 4) return;     // not a drag yet
        _clipId ??= _s.addClip(_anchor, _anchor).id;
        final clip = _s.clipById(_clipId!);
        if (clip == null) return;
        // the new clip grows from where it began, in whichever direction the pointer goes
        final lo = math.min(_anchor, _snap(t)), hi = math.max(_anchor, _snap(t));
        _s.setRange(clip.id, lo, math.min(_s.duration, math.max(hi, lo + TrimSession.minLength)));
      case _Drag.scrub:
        widget.onSeek(t);
      case _Drag.none:
        break;
    }
  }

  void _onPanEnd([Object? _]) {
    _drag = _Drag.none;
    _clipId = null;
  }

  void _onTapUp(TapUpDetails d) {
    final hit = _geo.hit(d.localPosition.dx, _s.clips, _s.selected);
    final t = _geo.tOf(d.localPosition.dx);
    if (d.localPosition.dy < _rulerHeight) {
      widget.onSeek(t);                    // a click on the ruler only moves the playhead
      return;
    }
    if (hit.clip != null) {
      _s.select(hit.clip!.id, additive: _multi);
    } else {
      _s.clearSelection();
    }
    if (hit.kind == HitKind.empty || hit.kind == HitKind.body) widget.onSeek(t);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) {
      widget.onZoom?.call((widget.zoom * (event.scrollDelta.dy < 0 ? 1.25 : 0.8)).clamp(1.0, 80.0));
    } else if (_scroll.hasClients) {
      _scroll.jumpTo((_scroll.offset + event.scrollDelta.dy + event.scrollDelta.dx).clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _viewport = constraints.maxWidth;
      final width = _viewport * widget.zoom;
      _geo = TimelineGeometry(width: width, duration: _s.duration);
      return Listener(
        onPointerSignal: _onPointerSignal,
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),     // dragging edits clips; the scrollbar and the wheel scroll
            child: SizedBox(
              width: width,
              height: widget.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: _onPanDown,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                onPanCancel: _onPanEnd,
                onTapUp: _onTapUp,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(fit: StackFit.expand, children: [
                    ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                    if (widget.filmstripUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(top: _rulerHeight),
                        child: Opacity(
                          opacity: 0.55,
                          child: Image.network(widget.filmstripUrl!, fit: BoxFit.fill, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                        ),
                      ),
                    ListenableBuilder(
                      listenable: _s,
                      builder: (context, _) => CustomPaint(
                        painter: _ClipsPainter(session: _s, geo: _geo, rulerHeight: _rulerHeight, textColor: Theme.of(context).colorScheme.onSurface),
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

class _ClipsPainter extends CustomPainter {
  _ClipsPainter({required this.session, required this.geo, required this.rulerHeight, required this.textColor}) : super(repaint: session);

  final TrimSession session;
  final TimelineGeometry geo;
  final double rulerHeight;
  final Color textColor;

  void _text(Canvas canvas, String text, Offset at, {double size = 11, FontWeight weight = FontWeight.w500, Color? color, double maxWidth = 400}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, fontWeight: weight, color: color ?? textColor)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    paintTimelineRuler(canvas, size, geo, rulerHeight, textColor);

    // clips (the selected ones on top)
    final order = [...session.clips.where((c) => !session.selected.contains(c.id)), ...session.clips.where((c) => session.selected.contains(c.id))];
    final top = rulerHeight + 4, bottom = size.height - 6;
    for (final c in order) {
      final isSelected = session.selected.contains(c.id);
      final color = clipColor(c);
      final rect = RRect.fromLTRBR(geo.xOf(c.start), top, geo.xOf(c.end), bottom, const Radius.circular(6));
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: isSelected ? 0.42 : 0.28));
      canvas.drawRRect(rect, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3 : 1.5
        ..color = c.locked ? Colors.white70 : color);
      if (c.locked) _hatch(canvas, rect, color);

      // handles
      final handle = Paint()..color = c.locked ? Colors.white54 : color;
      for (final x in [rect.left, rect.right]) {
        final bar = RRect.fromLTRBR(x - (isSelected ? 5 : 3), top + 4, x + (isSelected ? 5 : 3), bottom - 4, const Radius.circular(3));
        canvas.drawRRect(bar, handle);
        if (isSelected && !c.locked) {
          final grip = Paint()..color = Colors.white.withValues(alpha: 0.85)..strokeWidth = 1;
          canvas.drawLine(Offset(x - 1.5, top + 14), Offset(x - 1.5, bottom - 14), grip);
          canvas.drawLine(Offset(x + 1.5, top + 14), Offset(x + 1.5, bottom - 14), grip);
        }
      }

      // number, name and length
      final room = rect.width - 24;
      if (room > 26) {
        _text(canvas, '${session.clips.indexOf(c) + 1}  ${session.titleOf(c)}', Offset(rect.left + 12, top + 6), weight: FontWeight.w700, maxWidth: room - (c.locked ? 18 : 0));
        if (room > 70) _text(canvas, formatClock(c.length), Offset(rect.left + 12, top + 22), size: 10, color: textColor.withValues(alpha: 0.8), maxWidth: room);
      }
      if (c.locked && room > 8) _lock(canvas, Offset(rect.right - 20, top + 6));
    }
  }

  void _hatch(Canvas canvas, RRect rect, Color color) {
    canvas.save();
    canvas.clipRRect(rect);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.10)..strokeWidth = 2;
    for (var x = rect.left - rect.height; x < rect.right; x += 10) {
      canvas.drawLine(Offset(x, rect.bottom), Offset(x + rect.height, rect.top), paint);
    }
    canvas.restore();
  }

  void _lock(Canvas canvas, Offset at) {
    final painter = TextPainter(
      text: TextSpan(text: String.fromCharCode(Icons.lock.codePoint), style: TextStyle(fontSize: 14, fontFamily: Icons.lock.fontFamily, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_ClipsPainter old) => old.geo.width != geo.width || old.geo.duration != geo.duration || old.textColor != textColor;
}

/// The ticks and time labels along the top of a timeline.
void paintTimelineRuler(Canvas canvas, Size size, TimelineGeometry geo, double rulerHeight, Color textColor) {
  final tick = Paint()..color = textColor.withValues(alpha: 0.35);
  final step = geo.rulerStep();
  for (var t = 0.0; t <= geo.duration + 1e-6; t += step) {
    final x = geo.xOf(t);
    canvas.drawLine(Offset(x, rulerHeight - 7), Offset(x, rulerHeight), tick);
    if (x + 50 < size.width) {
      final label = TextPainter(
        text: TextSpan(text: formatClock(t, tenths: step < 1), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: textColor.withValues(alpha: 0.7))),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      label.paint(canvas, Offset(x + 3, 3));
    }
  }
}

/// The red line (with its flag) where the video is now.
class PlayheadPainter extends CustomPainter {
  PlayheadPainter({required this.x, required this.height});

  final double x;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    const color = Color(0xFFFF4D4D);
    canvas.drawLine(Offset(x, 0), Offset(x, height), Paint()..color = color..strokeWidth = 2);
    canvas.drawPath(Path()..moveTo(x - 6, 0)..lineTo(x + 6, 0)..lineTo(x, 9)..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(PlayheadPainter old) => old.x != x || old.height != height;
}
