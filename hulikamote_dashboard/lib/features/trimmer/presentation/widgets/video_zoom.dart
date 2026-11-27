import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Lets the video picture itself be zoomed (the timeline has its own zoom): Ctrl + mouse wheel zooms toward the pointer (so does a
/// pinch on a trackpad), dragging moves the picture while it is zoomed in, double click goes back to the whole picture. Small buttons in
/// the corner do the same. The plain wheel does nothing here.
class VideoZoom extends StatefulWidget {
  const VideoZoom({super.key, required this.child, this.maxScale = 10});

  final Widget child;
  final double maxScale;

  @override
  State<VideoZoom> createState() => _VideoZoomState();
}

class _VideoZoomState extends State<VideoZoom> {
  final _controller = TransformationController();
  Size _box = Size.zero;

  double get _scale => _controller.value.getMaxScaleOnAxis();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Zooms by [factor] around the middle of the picture.
  void _zoomBy(double factor) => _zoomAt(Offset(_box.width / 2, _box.height / 2), factor);

  /// Zooms by [factor] so the spot under [focal] (in the box) stays under the pointer.
  void _zoomAt(Offset focal, double factor) {
    final next = (_scale * factor).clamp(1.0, widget.maxScale).toDouble();
    if (next <= 1.001) {
      _reset();
      return;
    }
    final ratio = next / _scale;
    final around = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(ratio, ratio, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
    _controller.value = _keepInside(around * _controller.value);
  }

  bool get _ctrl => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;

  void _onSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _ctrl) {
      GestureBinding.instance.pointerSignalResolver.register(event, (e) {
        final scroll = e as PointerScrollEvent;
        _zoomAt(scroll.localPosition, scroll.scrollDelta.dy < 0 ? 1.25 : 0.8);
      });
    }
  }

  void _reset() => _controller.value = Matrix4.identity();

  /// The picture may not be dragged away from the box: its edges stay at or outside the box edges.
  Matrix4 _keepInside(Matrix4 m) {
    final s = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    final minX = _box.width - _box.width * s, minY = _box.height - _box.height * s;
    final x = t.x.clamp(math.min(minX, 0.0), 0.0).toDouble(), y = t.y.clamp(math.min(minY, 0.0), 0.0).toDouble();
    return Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _box = Size(box.maxWidth, box.maxHeight);
      return Stack(fit: StackFit.expand, children: [
        Listener(
          onPointerSignal: _onSignal,
          onPointerPanZoomUpdate: (e) {
            if (e.scale != 1.0) _zoomAt(e.localPosition, math.pow(e.scale, 0.15).toDouble());   // a pinch on a trackpad
          },
          child: GestureDetector(
            onDoubleTap: _reset,
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: 1,
              maxScale: widget.maxScale,
              panEnabled: true,
              scaleEnabled: false,                      // zoom is done above (Ctrl + wheel, pinch, buttons), the plain wheel must not zoom
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: box.maxWidth, height: box.maxHeight, child: widget.child),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final zoomed = _scale > 1.01;
              return DecoratedBox(
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    key: const ValueKey('video-zoom-out'),
                    tooltip: 'Zoom the picture out',
                    icon: const Icon(Icons.remove, size: 18, color: Colors.white),
                    visualDensity: VisualDensity.compact,
                    onPressed: zoomed ? () => _zoomBy(1 / 1.5) : null,
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('×${_scale.toStringAsFixed(_scale < 10 ? 1 : 0)}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    key: const ValueKey('video-zoom-in'),
                    tooltip: 'Zoom the picture in (or hold Ctrl and use the mouse wheel; double click goes back)',
                    icon: const Icon(Icons.add, size: 18, color: Colors.white),
                    visualDensity: VisualDensity.compact,
                    onPressed: _scale < widget.maxScale - 0.01 ? () => _zoomBy(1.5) : null,
                  ),
                  if (zoomed)
                    IconButton(
                      key: const ValueKey('video-zoom-reset'),
                      tooltip: 'Whole picture',
                      icon: const Icon(Icons.fit_screen, size: 18, color: Colors.white),
                      visualDensity: VisualDensity.compact,
                      onPressed: _reset,
                    ),
                ]),
              );
            },
          ),
        ),
      ]);
    });
  }
}
