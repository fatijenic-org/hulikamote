import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/forensic_api.dart';
import '../../domain/analysis_draft.dart';
import '../../domain/ban_hours.dart';
import 'fx.dart';

/// "Time of the video" in the Settings step: what time of day the video was recorded and where that time came from, with a box to
/// type the start time when the video has none (or to test a ban hour). Shown when a rule that depends on the hour (the truck ban
/// with its hours) is selected. The backend looks in this order: typed > the clock in the picture > the file's own information >
/// the file name; with none of them it says so, and the tickets of that rule ask for a human check.
class VideoTimeCard extends StatefulWidget {
  const VideoTimeCard({super.key, required this.draft, required this.api, this.typingPause = const Duration(milliseconds: 700)});

  final AnalysisDraft draft;
  final ForensicApi api;

  /// How long to wait after the last typed letter before asking again.
  final Duration typingPause;

  @override
  State<VideoTimeCard> createState() => _VideoTimeCardState();
}

class _VideoTimeCardState extends State<VideoTimeCard> {
  late final TextEditingController _typed = TextEditingController(text: widget.draft.settings.videoStart);
  Timer? _pause;
  VideoClock? _clock;
  late bool _busy = widget.draft.videoPath != null; // the first look starts right after the first picture
  bool _unsupported = false;
  String? _error;
  int _asked = 0;
  double _trimAsked = -1;

  @override
  void initState() {
    super.initState();
    widget.draft.addListener(_draftChanged);
    Future.microtask(_look); // not setState inside initState
  }

  @override
  void dispose() {
    widget.draft.removeListener(_draftChanged);
    _pause?.cancel();
    _typed.dispose();
    super.dispose();
  }

  /// The start of the analysed part moves with the trim: ask again when it does (not on every other change of the draft).
  void _draftChanged() {
    if (widget.draft.trimStart != _trimAsked && !_busy) _look();
  }

  Future<void> _look() async {
    final path = widget.draft.videoPath;
    if (path == null) return;
    final ticket = ++_asked;
    _trimAsked = widget.draft.trimStart;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final clock = await widget.api.videoClock(path, videoStart: widget.draft.settings.videoStart, trimStart: widget.draft.trimStart);
      if (!mounted || ticket != _asked) return; // a newer question is on its way
      setState(() {
        _clock = clock;
        _unsupported = clock == null;
        _busy = false;
      });
    } catch (e) {
      if (!mounted || ticket != _asked) return;
      setState(() {
        _busy = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  void _typedChanged(String text) {
    widget.draft.settings.videoStart = text;
    _pause?.cancel();
    _pause = Timer(widget.typingPause, _look);
    setState(() {});
  }

  List get _hours => (widget.draft.config('truck_ban')['ban_windows'] as List?) ?? const [];

  @override
  Widget build(BuildContext context) {
    return FxCard(
      key: const ValueKey('video-time-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.schedule, size: 18, color: Fx.accent),
          const SizedBox(width: Fx.s8),
          Text('Time of the video', style: Fx.heading(context)),
        ]),
        const SizedBox(height: Fx.s4),
        Text(
          'The truck ban depends on the hour, so the system needs to know when this video was recorded.',
          style: Fx.caption(context),
        ),
        const SizedBox(height: Fx.s12),
        _answer(context),
        const SizedBox(height: Fx.s12),
        TextField(
          key: const ValueKey('video-start-field'),
          controller: _typed,
          onChanged: _typedChanged,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            labelText: 'Video start time (optional)',
            hintText: '7:40 AM   or   2026-11-05 07:40',
            helperText: 'Type it if the video has no time, or to test a ban hour: "pretend this video started at 7:30".',
            helperMaxLines: 2,
            suffixIcon: _typed.text.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey('video-start-clear'),
                    tooltip: 'Find the time in the video instead',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _typed.clear();
                      _typedChanged('');
                    },
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _answer(BuildContext context) {
    if (_busy) {
      return Row(key: const ValueKey('video-time-busy'), children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: Fx.s8),
        Text('Looking for the time in the video…', style: Fx.body(context)),
      ]);
    }
    if (_error != null) {
      return Text(_error!, key: const ValueKey('video-time-error'), style: Fx.body(context).copyWith(color: Fx.danger));
    }
    if (_unsupported) {
      return Text('This backend cannot look for the time yet. Type the start time below.',
          key: const ValueKey('video-time-unsupported'), style: Fx.body(context));
    }
    final clock = _clock;
    if (clock == null) return const SizedBox(height: 20);
    final start = clock.start;
    if (start == null) {
      final seen = switch (clock.daylight) {
        'day' => 'The picture looks like daytime.',
        'twilight' => 'The picture looks like dawn or dusk.',
        'night' => 'The picture looks like night.',
        _ => '',
      };
      return Column(key: const ValueKey('video-time-none'), crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.help_outline, size: 18, color: Fx.warning),
          const SizedBox(width: Fx.s8),
          Text('No time found in the video', style: Fx.heading(context)),
        ]),
        const SizedBox(height: 2),
        Text(
          '$seen Type the start time below, or the truck tickets will say "time not confirmed" for a human to check.'.trim(),
          style: Fx.caption(context),
        ),
      ]);
    }
    final hours = BanHours.describe(_hours);
    final inside = BanHours.contains(_hours, start);
    return Column(key: const ValueKey('video-time-found'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.check_circle, size: 18, color: Fx.success),
        const SizedBox(width: Fx.s8),
        Text(BanHours.clock(start), key: const ValueKey('video-time-value'), style: Fx.title(context)),
        const SizedBox(width: Fx.s8),
        Flexible(child: Text(clock.label, style: Fx.caption(context))),
      ]),
      if (clock.note.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(clock.note, style: Fx.caption(context)),
      ],
      if (hours.isNotEmpty) ...[
        const SizedBox(height: Fx.s4),
        Text(
          'Ban hours: $hours. This video starts ${inside ? 'inside' : 'outside'} them.',
          key: const ValueKey('video-time-verdict'),
          style: Fx.body(context).copyWith(color: inside ? Fx.danger : Fx.success),
        ),
      ],
    ]);
  }
}
