import 'dart:async';

import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';
import '../../domain/models/frame_job.dart';
import 'package:hulikamote_dashboard/core/theme/light_mode.dart';

/// The first step of the live setup: pictures of the source, one by one, and one to pick. A file gives pictures spread over the
/// whole video; a camera gives one a second for a few seconds, so a moment with the road clear and the paint easy to see can be
/// chosen. The first picture that arrives is picked at once (the operator can go on at that moment); a click picks another.
class FramePickerStep extends StatefulWidget {
  const FramePickerStep({super.key, required this.api, required this.onPicked});

  final CameraApi api;

  /// The number of the picked picture, or null when there is none to pick (a new grab has just started).
  final void Function(int? id) onPicked;

  @override
  State<FramePickerStep> createState() => _FramePickerStepState();
}

class _FramePickerStepState extends State<FramePickerStep> {
  FrameJob? _job;
  int _jobNumber = -1;     // the grab we follow: an answer about an older one is ignored
  int? _picked;
  String? _error;          // the grab could not even start
  Timer? _poll;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _begin();                  // the parent is still being built: it is told nothing yet, and there is nothing to reset
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  String _reason(Object e) => '$e'.replaceFirst('Exception: ', '');

  /// "Get new pictures": drops the pictures and the pick, then starts a new grab.
  void _again() {
    _poll?.cancel();
    final hadPick = _picked != null;
    setState(() {
      _job = null;
      _picked = null;
      _error = null;
      _jobNumber = -1;
    });
    if (hadPick) widget.onPicked(null);
    _begin();
  }

  /// Starts a grab and follows it until it is over.
  Future<void> _begin() async {
    try {
      final job = await widget.api.startFrames();
      if (!mounted) return;
      _jobNumber = job.job;
      _take(job);
      if (job.working) _poll = Timer.periodic(const Duration(milliseconds: 600), (_) => _refresh());
    } catch (e) {
      if (mounted) setState(() => _error = _reason(e));
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final job = await widget.api.frames();
      if (mounted && job.job == _jobNumber) _take(job);
    } catch (_) {
      // one missed answer is not worth a message: the next one comes in a moment
    } finally {
      _refreshing = false;
    }
  }

  void _take(FrameJob job) {
    int? autoPick;
    setState(() {
      _job = job;
      if (_picked == null && job.frames.isNotEmpty) {
        _picked = job.frames.first.id;
        autoPick = _picked;
      }
    });
    if (autoPick != null) widget.onPicked(autoPick);
    if (!job.working) _poll?.cancel();
  }

  void _pick(int id) {
    setState(() => _picked = id);
    widget.onPicked(id);
  }

  // ─── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final job = _job;
    if (_error != null) return _problem(_error!);
    if (job == null) return _message(const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)), 'Getting the first picture…');
    if (job.failed && job.frames.isEmpty) return _problem(job.error);
    // The picture takes the whole step; the status and the other pictures float over its edges.
    return Stack(fit: StackFit.expand, children: [
      _preview(job),
      Positioned(top: Fx.s8, left: Fx.s8, right: Fx.s8, child: _header(job)),
      Positioned(bottom: Fx.s8, left: Fx.s8, right: Fx.s8, child: _strip(job)),
    ]);
  }

  Widget _header(FrameJob job) {
    final count = job.frames.length;
    final String status;
    if (job.working) {
      status = 'Getting pictures… $count of ${job.expected}${job.fromCamera ? ' (one every second)' : ''}';
    } else if (job.failed) {
      status = 'Stopped: ${job.error} You can still pick one of the $count pictures.';
    } else {
      status = '$count pictures. Pick the one to set up on.';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s12, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(Fx.radiusSm)),
      child: Row(children: [
        if (job.working) ...[const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), const SizedBox(width: Fx.s8)],
        Expanded(
          child: Text(status, key: const ValueKey('frames-status'), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        const Tooltip(
          message: 'Pick a picture where the road is clear and the paint is easy to see. The violations are set up on this one picture.',
          child: Padding(padding: EdgeInsets.symmetric(horizontal: Fx.s8), child: Icon(Icons.info_outline, size: 18, color: Colors.white)),
        ),
        TextButton.icon(
          key: const ValueKey('frames-refresh'),
          onPressed: _again,
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Get new pictures'),
        ),
      ]),
    );
  }

  Widget _preview(FrameJob job) {
    FrameChoice? picked;
    for (final f in job.frames) {
      if (f.id == _picked) picked = f;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(Fx.radius),
        border: Border.all(color: Fx.border(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Fx.radius),
        child: picked == null
            ? const SizedBox.shrink()
            : KeepColors(child: Image.network(
                widget.api.frameUrl(job.job, picked.id),
                key: ValueKey('frame-preview-${job.job}-${picked.id}'),
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
                errorBuilder: (context, error, stack) => Center(child: Text('This picture could not be loaded.', style: Fx.caption(context))),
              )),
      ),
    );
  }

  Widget _strip(FrameJob job) {
    final slots = job.expected > job.frames.length ? job.expected : job.frames.length;
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: slots,
        separatorBuilder: (context, i) => const SizedBox(width: Fx.s8),
        itemBuilder: (context, i) => i < job.frames.length ? _thumb(job, job.frames[i]) : _waiting(),
      ),
    );
  }

  Widget _thumb(FrameJob job, FrameChoice f) {
    final selected = f.id == _picked;
    return GestureDetector(
      key: ValueKey('frame-thumb-${f.id}'),
      onTap: () => _pick(f.id),
      child: Container(
        width: 128,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Fx.radiusSm),
          border: Border.all(color: selected ? Fx.accent : Colors.white54, width: selected ? 3 : 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Fx.radiusSm - 1),
          child: Stack(fit: StackFit.expand, children: [
            KeepColors(child: Image.network(
              widget.api.frameUrl(job.job, f.id),
              fit: BoxFit.cover,
              cacheWidth: 320,
              errorBuilder: (context, error, stack) => ColoredBox(color: Fx.raised(context)),
            )),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                child: Text(f.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _waiting() => Container(
        width: 128,
        decoration: BoxDecoration(color: Fx.raised(context), borderRadius: BorderRadius.circular(Fx.radiusSm), border: Border.all(color: Fx.border(context))),
        child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );

  Widget _message(Widget icon, String text) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(height: Fx.s12), Text(text, style: Fx.body(context))]),
      );

  Widget _problem(String text) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 32, color: Fx.danger),
          const SizedBox(height: Fx.s12),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Text(text, textAlign: TextAlign.center, style: Fx.body(context))),
          const SizedBox(height: Fx.s12),
          FilledButton.icon(key: const ValueKey('frames-retry'), onPressed: _again, icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ]),
      );
}
