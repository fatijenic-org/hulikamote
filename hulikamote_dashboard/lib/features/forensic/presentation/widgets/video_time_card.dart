import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/forensic_api.dart';
import '../../domain/analysis_draft.dart';
import '../../domain/ban_hours.dart';
import 'fx.dart';

/// "Time of the video", shown right under the truck ban's hours: the ONE place the time is dealt with.
///
/// The backend starts reading the time of a video the moment it is picked (engine/video_clock.py look_ahead), so by the time the
/// operator gets here the answer is usually ready; nobody waits for it, and the analysis reuses it. The order of the search is: the
/// clock in the picture > the file's own information > the file name. With none of them the tickets of the truck ban say
/// "time not confirmed" for a human to check, and the box to type the start time opens by itself.
/// "Change" opens that box to correct a wrong time, or to test a ban hour ("pretend this video started at 7:30").
///
/// In the Live Monitor there is nothing to read: it uses this computer's clock; the same box only pretends another time, for a demo.
class VideoTimeCard extends StatefulWidget {
  const VideoTimeCard({super.key, required this.draft, this.api, this.typingPause = const Duration(milliseconds: 700)});

  final AnalysisDraft draft;

  /// Asks the backend for the time of the video. Without it (and not live) the card shows nothing.
  final ForensicApi? api;

  /// How long to wait after the last typed letter before asking again.
  final Duration typingPause;

  @override
  State<VideoTimeCard> createState() => _VideoTimeCardState();
}

class _VideoTimeCardState extends State<VideoTimeCard> {
  late final TextEditingController _typed = TextEditingController(text: widget.draft.settings.videoStart);
  Timer? _pause;
  VideoClock? _clock;
  bool _busy = false;
  bool _unsupported = false;
  bool _changing = false; // the operator pressed "Change"
  String? _error;
  int _asked = 0;
  double _trimAsked = -1;

  bool get _live => widget.draft.isLive;
  bool get _reads => !_live && widget.api != null && widget.draft.videoPath != null;

  @override
  void initState() {
    super.initState();
    widget.draft.addListener(_draftChanged);
    if (_reads) {
      _busy = true; // the first look starts right away
      Future.microtask(_look); // not setState inside initState
    }
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
    if (_reads && widget.draft.trimStart != _trimAsked && !_busy) _look();
  }

  Future<void> _look() async {
    final path = widget.draft.videoPath;
    final api = widget.api;
    if (path == null || api == null) return;
    final ticket = ++_asked;
    _trimAsked = widget.draft.trimStart;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final clock = await api.videoClock(path, videoStart: widget.draft.settings.videoStart, trimStart: widget.draft.trimStart);
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
    if (_reads) _pause = Timer(widget.typingPause, _look);
    setState(() {});
  }

  List get _hours => (widget.draft.config('truck_ban')['ban_windows'] as List?) ?? const [];

  /// The box to type the start time: when asked for, when something is typed, and when the video has no time at all.
  bool get _fieldOpen => _changing || _typed.text.isNotEmpty || (_reads && !_busy && _clock != null && _clock!.start == null);

  @override
  Widget build(BuildContext context) {
    if (!_live && !_reads) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('video-time-card'),
      margin: const EdgeInsets.only(top: Fx.s12),
      padding: const EdgeInsets.all(Fx.s12),
      decoration: BoxDecoration(
        border: Border.all(color: Fx.border(context)),
        borderRadius: BorderRadius.circular(Fx.radiusSm),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.schedule, size: 18, color: Fx.accent),
          const SizedBox(width: Fx.s8),
          Text(_live ? 'Time' : 'Time of the video', style: Fx.heading(context)),
        ]),
        const SizedBox(height: Fx.s8),
        _answer(context),
        if (_fieldOpen) ...[
          const SizedBox(height: Fx.s12),
          TextField(
            key: const ValueKey('video-start-field'),
            controller: _typed,
            onChanged: _typedChanged,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              labelText: _live ? 'Pretend it is (demo only)' : 'Start time of the video',
              hintText: '7:40 AM   or   2026-11-05 07:40',
              helperText: _live
                  ? 'Leave empty to use this computer\'s clock.'
                  : 'Only when the time above is wrong or missing, or to test a ban hour: "pretend this video started at 7:30".',
              helperMaxLines: 2,
              suffixIcon: _typed.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('video-start-clear'),
                      tooltip: _live ? 'Use this computer\'s clock' : 'Read the time from the video instead',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _typed.clear();
                        _changing = false;
                        _typedChanged('');
                      },
                    ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _change() => TextButton(
        key: const ValueKey('video-time-change'),
        onPressed: () => setState(() => _changing = !_changing),
        child: Text(_changing ? 'Done' : (_live ? 'Pretend another time' : 'Change')),
      );

  Widget _answer(BuildContext context) {
    if (_live) {
      return Row(key: const ValueKey('video-time-live'), children: [
        Expanded(
          child: Text(
            _typed.text.isEmpty
                ? 'Live: the ban hours follow this computer\'s clock.'
                : 'Live, pretending it is ${_typed.text.trim()} when monitoring starts.',
            style: Fx.body(context),
          ),
        ),
        _change(),
      ]);
    }
    if (_busy) {
      return Row(key: const ValueKey('video-time-busy'), children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: Fx.s8),
        Expanded(child: Text('Reading the time in the video. You can carry on.', style: Fx.body(context))),
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
        const Spacer(),
        _change(),
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
