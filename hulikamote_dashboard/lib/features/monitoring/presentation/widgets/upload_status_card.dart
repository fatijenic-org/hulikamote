import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';

/// The four moments of a "Video file…" upload.
enum UploadStage {
  sending, // the file is going to the backend (a progress bar that fills)
  preparing, // all bytes are there; the backend checks the video and loads the models (no number to show, only the time)
  done, // the video is the live source
  failed,
}

/// Where an upload is. Immutable: the screen makes a new one on every change.
class UploadStatus {
  const UploadStatus({
    required this.name,
    required this.stage,
    this.sent = 0,
    this.total = 0,
    this.bytesPerSecond = 0,
    this.waited = Duration.zero,
    this.detail = '',
    this.error = '',
  });

  final String name;
  final UploadStage stage;
  final int sent;
  final int total;
  final double bytesPerSecond;

  /// preparing: how long the backend has been at it.
  final Duration waited;

  /// done: what the video is ("1920x1080 · 25 fps · 1 min 23 s").
  final String detail;

  /// failed: why, in words.
  final String error;

  double get fraction => total <= 0 ? 0 : (sent / total).clamp(0.0, 1.0);

  bool get active => stage == UploadStage.sending || stage == UploadStage.preparing;
}

/// "310 MB", "1.2 GB", "820 KB".
String formatBytes(num bytes) {
  const kb = 1024, mb = 1024 * 1024, gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(bytes >= 100 * mb ? 0 : 1)} MB';
  if (bytes >= kb) return '${(bytes / kb).round()} KB';
  return '${bytes.round()} B';
}

/// "14 s", "1 min 5 s".
String formatSeconds(int seconds) {
  if (seconds < 60) return '$seconds s';
  return '${seconds ~/ 60} min ${seconds % 60} s';
}

/// A card above the live picture that says, in words and numbers, where a "Video file…" upload is: how much went out, how
/// fast, what the backend is doing after that, and at the end that the video is ready (or why it is not).
class UploadStatusCard extends StatelessWidget {
  const UploadStatusCard({
    super.key,
    required this.status,
    required this.playing,
    this.onCancel,
    this.onRetry,
    this.onDismiss,
  });

  final UploadStatus status;

  /// The live view is running (the "ready" card then says it shows the video; else it says to press Start).
  final bool playing;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final (IconData icon, Color color, String title) = switch (s.stage) {
      UploadStage.sending => (Icons.cloud_upload_outlined, Fx.accent, 'Uploading ${s.name}'),
      UploadStage.preparing => (Icons.hourglass_top, Fx.warning, 'Upload finished. Getting the video ready…'),
      UploadStage.done => (Icons.check_circle, Fx.success, '${s.name} is ready'),
      UploadStage.failed => (Icons.error_outline, Fx.danger, 'Upload failed'),
    };
    return FxCard(
      key: const ValueKey('upload-card'),
      padding: const EdgeInsets.symmetric(horizontal: Fx.s16, vertical: Fx.s12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: Fx.s8),
          Expanded(child: Text(title, style: Fx.body(context).copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          if (s.stage == UploadStage.sending && onCancel != null)
            TextButton(key: const ValueKey('upload-cancel'), onPressed: onCancel, child: const Text('Cancel upload')),
          if (s.stage == UploadStage.failed && onRetry != null)
            TextButton(key: const ValueKey('upload-retry'), onPressed: onRetry, child: const Text('Try again')),
          if (!s.active && onDismiss != null)
            IconButton(key: const ValueKey('upload-dismiss'), tooltip: 'Close', visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18), onPressed: onDismiss),
        ]),
        if (s.active) ...[
          const SizedBox(height: Fx.s8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: const ValueKey('upload-bar'),
              minHeight: 6,
              value: s.stage == UploadStage.sending ? s.fraction : null, // preparing: no number, so the bar only moves
              color: color,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(_caption(s), key: const ValueKey('upload-caption'), style: Fx.caption(context)),
      ]),
    );
  }

  String _caption(UploadStatus s) {
    switch (s.stage) {
      case UploadStage.sending:
        final percent = (s.fraction * 100).floor();
        final speed = s.bytesPerSecond > 0 ? '  ·  ${formatBytes(s.bytesPerSecond)}/s' : '';
        final left = (s.bytesPerSecond > 0 && s.sent > 0) ? ((s.total - s.sent) / s.bytesPerSecond).ceil() : -1;
        final eta = left >= 0 ? '  ·  about ${formatSeconds(left)} left' : '';
        return '$percent%  ·  ${formatBytes(s.sent)} of ${formatBytes(s.total)}$speed$eta';
      case UploadStage.preparing:
        return 'The backend saves the file, checks it and loads the models. This can take up to a minute.  ·  ${formatSeconds(s.waited.inSeconds)} so far';
      case UploadStage.done:
        final next = playing ? 'Now showing in the live view.' : 'Press Start monitoring to watch it.';
        return s.detail.isEmpty ? next : '${s.detail}  ·  $next';
      case UploadStage.failed:
        return s.error;
    }
  }
}
