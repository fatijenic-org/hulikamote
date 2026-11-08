import 'package:flutter/material.dart';

/// One line about the live camera: LIVE with size / fps / lag, CONNECTING, or OFFLINE while it reconnects.
/// [status] is the backend's `/settings/video/status` (or the `camera` field of a feed message).
class CameraStatusChip extends StatelessWidget {
  const CameraStatusChip({super.key, required this.status});

  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final state = (status['state'] ?? 'idle') as String;
    if (state == 'idle') return const SizedBox.shrink();

    final (colour, text) = switch (state) {
      'live' => (Colors.green, 'LIVE  ${_size()}  ${_num(status['input_fps'])} fps in  lag ${status['lag_ms'] ?? 0} ms'),
      'connecting' => (Colors.amber, 'CONNECTING to the camera...'),
      'offline' => (Colors.red, 'OFFLINE - reconnecting (${status['reconnects'] ?? 0} so far)'),
      'file' => (Colors.blueGrey, 'FILE  ${_size()}'),
      _ => (Colors.grey, state.toUpperCase()),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: colour),
        const SizedBox(width: 6),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colour))),
      ],
    );
  }

  String _size() {
    final w = status['width'] ?? 0, h = status['height'] ?? 0;
    return w == 0 ? '' : '${w}x$h';
  }

  String _num(Object? v) => v is num ? v.toStringAsFixed(0) : '0';
}
