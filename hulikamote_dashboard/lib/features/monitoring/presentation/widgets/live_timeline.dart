import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';

/// The Live Monitor's three timelines in one bar, and the controls to move over them:
///  - Video   (white line)   where the video itself would be, played at its own speed;
///  - Backend (blue)         how far the backend has finished (the blue stripe is what can be replayed);
///  - Output  (orange)       what the screen shows now.
/// The enforcer can pause (the backend keeps working), drag or tap the orange marker to go back or forward over what is finished (never beyond
/// the backend), and play again: it goes on from where the screen is, a bit faster while more is ready than the gap, never catching up with it.
///
/// [info] is the backend's playback state of the latest picture: paused, first_s, play_s, proc_s, video_s (seconds from the start of the run).
class LiveTimeline extends StatefulWidget {
  const LiveTimeline({super.key, required this.info, required this.onPause, required this.onPlay, required this.onSeek});

  final Map<String, dynamic> info;
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final ValueChanged<double> onSeek;

  @override
  State<LiveTimeline> createState() => _LiveTimelineState();
}

class _LiveTimelineState extends State<LiveTimeline> {
  static const _backendColor = Color(0xFF4FA3FF);

  double? _drag; // seconds, while the output marker is being dragged

  double? _num(String key) {
    final v = widget.info[key];
    return v is num ? v.toDouble() : null;
  }

  static String _clock(double seconds) {
    final t = seconds.round().clamp(0, 359999);
    final h = t ~/ 3600;
    final m = (t % 3600) ~/ 60;
    final s = t % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  Widget _legend(BuildContext context, Color color, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 4),
      Text(text, style: Fx.caption(context)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final proc = _num('proc_s');
    if (proc == null) return const SizedBox.shrink();
    final first = (_num('first_s') ?? 0.0).clamp(0.0, proc).toDouble();
    final play = _drag ?? _num('play_s') ?? first;
    final video = _num('video_s') ?? proc;
    final paused = widget.info['paused'] == true;
    final pauses = [for (final m in (widget.info['pauses'] as List? ?? const [])) if (m is num) m.toDouble()];   // replay: where it was saved and paused
    var span = 1.0;
    for (final v in [video, proc, play]) {
      if (v > span) span = v;
    }
    final delay = (proc - play).clamp(0.0, 359999.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(Fx.s8, Fx.s4, Fx.s12, Fx.s8),
      decoration: BoxDecoration(color: Fx.panel(context), border: Border(top: BorderSide(color: Fx.border(context)))),
      child: Row(children: [
        IconButton(
          key: const ValueKey('timeline-play'),
          tooltip: paused ? 'Play from here' : 'Pause (the backend keeps working)',
          icon: Icon(paused ? Icons.play_arrow : Icons.pause),
          onPressed: paused ? widget.onPlay : widget.onPause,
        ),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth;
              double x(double s) => (s / span).clamp(0.0, 1.0) * w;
              double secAt(double dx) => (dx / w * span).clamp(first, proc).toDouble();
              return GestureDetector(
                key: const ValueKey('timeline-bar'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => widget.onSeek(secAt(d.localPosition.dx)),
                onHorizontalDragStart: (d) => setState(() => _drag = secAt(d.localPosition.dx)),
                onHorizontalDragUpdate: (d) => setState(() => _drag = secAt(d.localPosition.dx)),
                onHorizontalDragEnd: (_) {
                  final to = _drag;
                  setState(() => _drag = null);
                  if (to != null) widget.onSeek(to);
                },
                child: SizedBox(
                  height: 30,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 13,
                      height: 4,
                      child: DecoratedBox(decoration: BoxDecoration(color: Fx.border(context), borderRadius: BorderRadius.circular(2))),
                    ),
                    // what is finished: the part that can be replayed
                    Positioned(
                      left: x(first),
                      width: (x(proc) - x(first)).clamp(0.0, w).toDouble(),
                      top: 11,
                      height: 8,
                      child: DecoratedBox(decoration: BoxDecoration(color: _backendColor.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(3))),
                    ),
                    // the video itself, at its own speed
                    Positioned(left: x(video) - 1, top: 4, width: 2, height: 22, child: const ColoredBox(color: Colors.white70)),
                    // where this monitoring was saved and paused (replay)
                    for (final m in pauses) Positioned(left: x(m) - 1.5, top: 2, width: 3, height: 26, child: const ColoredBox(color: Colors.amber)),
                    // the backend: how far it has finished
                    Positioned(
                      left: x(proc) - 5,
                      top: 8,
                      width: 10,
                      height: 14,
                      child: DecoratedBox(decoration: BoxDecoration(color: _backendColor, borderRadius: BorderRadius.circular(3))),
                    ),
                    // the output: what the screen shows
                    Positioned(
                      left: x(play) - 7,
                      top: 7,
                      width: 14,
                      height: 16,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Fx.accent, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white, width: 1.5)),
                      ),
                    ),
                  ]),
                ),
              );
            }),
            Wrap(spacing: Fx.s12, runSpacing: 2, children: [
              if (widget.info['demo'] == true)
                Container(
                  key: const ValueKey('demo-badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(border: Border.all(color: Fx.accent), borderRadius: BorderRadius.circular(4)),
                  child: Text('DEMO REPLAY', style: Fx.caption(context).copyWith(color: Fx.accent, fontWeight: FontWeight.w700)),
                ),
              if (widget.info['replay'] == true) ...[
                Container(
                  key: const ValueKey('replay-badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(border: Border.all(color: Fx.accent), borderRadius: BorderRadius.circular(4)),
                  child: Text('REPLAY OF A SAVED RUN', style: Fx.caption(context).copyWith(color: Fx.accent, fontWeight: FontWeight.w700)),
                ),
                _legend(context, Fx.accent, 'At ${_clock(play)} of ${_clock(proc)}'),
                if (pauses.isNotEmpty) ...[
                  _legend(context, Colors.amber, pauses.length == 1 ? 'Paused at ${_clock(pauses.last)}' : 'Last paused at ${_clock(pauses.last)} (${pauses.length} times)'),
                  InkWell(
                    key: const ValueKey('go-last-pause'),
                    onTap: () => widget.onSeek(pauses.last),
                    child: Text('Go to it', style: Fx.caption(context).copyWith(color: Fx.accent, decoration: TextDecoration.underline)),
                  ),
                ],
              ] else ...[
                _legend(context, Fx.accent, 'Output ${_clock(play)}'),
                _legend(context, _backendColor, 'Backend ${_clock(proc)}'),
                _legend(context, Colors.white70, 'Video ${_clock(video)}'),
                Text('${delay.round()} s behind the backend', style: Fx.caption(context)),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}
