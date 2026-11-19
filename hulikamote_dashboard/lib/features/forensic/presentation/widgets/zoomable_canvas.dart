import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fx.dart';

/// Zoom and move for the picture a rule is set up on. Wrap the WHOLE canvas (the picture, its shapes and the gesture detector that edits
/// them): the picture and every marker on it are scaled together, and taps and drags reach the child already in the picture's own
/// pixels (a Transform maps them back), so the editor works the same at any zoom.
///
///   - Ctrl + wheel, the + / - buttons, or a pinch on a touchpad zoom (up to 8x)
///   - zoomed in: the wheel, the middle mouse button, or a two-finger scroll moves the picture; "fit" shows all of it again
class ZoomableCanvas extends StatefulWidget {
  const ZoomableCanvas({super.key, required this.child});

  final Widget child;

  @override
  State<ZoomableCanvas> createState() => _ZoomableCanvasState();
}

class _ZoomableCanvasState extends State<ZoomableCanvas> {
  static const _maxZoom = 8.0;
  double _zoom = 1;
  Offset _pan = Offset.zero; // where the picture's top-left corner is, in the box's own pixels (never positive)
  Size _box = Size.zero;
  bool _middleDrag = false;
  double _zoomAtStart = 1;
  Offset _panAtStart = Offset.zero;

  static Offset _clamp(Offset pan, double zoom, Size box) =>
      Offset(pan.dx.clamp(box.width - box.width * zoom, 0.0), pan.dy.clamp(box.height - box.height * zoom, 0.0));

  void _zoomTo(double zoom, Offset focus) {
    final next = zoom.clamp(1.0, _maxZoom);
    setState(() {
      _pan = _clamp(focus - (focus - _pan) * (next / _zoom), next, _box);
      _zoom = next;
    });
  }

  void _zoomBy(double factor) => _zoomTo(_zoom * factor, Offset(_box.width / 2, _box.height / 2));

  void _fit() => setState(() {
    _zoom = 1;
    _pan = Offset.zero;
  });

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final held = HardwareKeyboard.instance;
    final focus = event.localPosition; // read here: the resolver hands the callback the untransformed event
    final delta = event.scrollDelta;
    if (held.isControlPressed || held.isMetaPressed) {
      GestureBinding.instance.pointerSignalResolver.register(event, (_) => _zoomTo(_zoom * math.exp(-delta.dy * 0.002), focus));
    } else if (_zoom > 1) {
      final sideways = held.isShiftPressed;
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        setState(() => _pan = _clamp(_pan - (sideways ? Offset(delta.dy, 0) : delta), _zoom, _box));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _box = box.biggest;
      final pan = _clamp(_pan, _zoom, _box);
      final zoomed = Matrix4.identity()
        ..setEntry(0, 0, _zoom)
        ..setEntry(1, 1, _zoom)
        ..setEntry(0, 3, pan.dx)
        ..setEntry(1, 3, pan.dy);
      return Listener(
        onPointerSignal: _onSignal,
        onPointerDown: (e) => _middleDrag = e.kind == PointerDeviceKind.mouse && e.buttons == kMiddleMouseButton,
        onPointerMove: (e) {
          if (_middleDrag) setState(() => _pan = _clamp(_pan + e.delta, _zoom, _box));
        },
        onPointerUp: (_) => _middleDrag = false,
        onPointerCancel: (_) => _middleDrag = false,
        onPointerPanZoomStart: (_) {
          _zoomAtStart = _zoom;
          _panAtStart = _pan;
        },
        onPointerPanZoomUpdate: (e) {
          if ((e.scale - 1).abs() >= 0.01) {
            final next = (_zoomAtStart * e.scale).clamp(1.0, _maxZoom);
            setState(() {
              _pan = _clamp(e.localPosition - (e.localPosition - _panAtStart) * (next / _zoomAtStart), next, _box);
              _zoom = next;
            });
          } else if (_zoom > 1) {
            setState(() => _pan = _clamp(_panAtStart + e.pan, _zoom, _box)); // a two-finger scroll moves the picture
          }
        },
        child: Stack(children: [
          Positioned.fill(child: Transform(transform: zoomed, child: widget.child)),
          Positioned(top: Fx.s8, right: Fx.s8, child: _bar()),
        ]),
      );
    });
  }

  Widget _bar() {
    const tint = Colors.white;
    return Material(
      color: Colors.black.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(Fx.radiusSm),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: const ValueKey('canvas-zoom-out'),
          tooltip: 'Zoom out',
          visualDensity: VisualDensity.compact,
          color: tint,
          onPressed: _zoom > 1 ? () => _zoomBy(1 / 1.4) : null,
          icon: const Icon(Icons.remove, size: 18),
        ),
        SizedBox(
          width: 44,
          child: Text('${(_zoom * 100).round()}%', key: const ValueKey('canvas-zoom-level'), textAlign: TextAlign.center, style: const TextStyle(color: tint, fontSize: 12)),
        ),
        IconButton(
          key: const ValueKey('canvas-zoom-in'),
          tooltip: 'Zoom in (or Ctrl + wheel). Zoomed in: the wheel or the middle mouse button moves the picture. Markers grow with it.',
          visualDensity: VisualDensity.compact,
          color: tint,
          onPressed: _zoom < _maxZoom ? () => _zoomBy(1.4) : null,
          icon: const Icon(Icons.add, size: 18),
        ),
        IconButton(
          key: const ValueKey('canvas-zoom-fit'),
          tooltip: 'Show the whole picture',
          visualDensity: VisualDensity.compact,
          color: tint,
          onPressed: _zoom > 1 ? _fit : null,
          icon: const Icon(Icons.fit_screen, size: 18),
        ),
      ]),
    );
  }
}
