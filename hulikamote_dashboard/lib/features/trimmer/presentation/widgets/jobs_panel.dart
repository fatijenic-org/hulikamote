import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/trimmer_controller.dart';
import '../../domain/trimmer_models.dart';

/// The exports. They run on the laptop on their own, so this list keeps moving while the person edits or opens
/// another video.
class JobsPanel extends StatelessWidget {
  const JobsPanel({super.key, required this.controller, required this.reveal, required this.onMessage});

  final TrimmerController controller;

  /// Shows a finished file in its folder.
  final void Function(String path) reveal;
  final void Function(String message) onMessage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final jobs = controller.jobs;
        final running = controller.activeJobCount;
        final finished = jobs.length - running;
        return SizedBox(
          height: jobs.isEmpty ? 64 : 200,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(running > 0 ? 'EXPORTS · $running RUNNING' : 'EXPORTS', style: Fx.label(context))),
            if (finished > 0) TextButton(onPressed: controller.clearFinished, child: const Text('Clear finished')),
          ]),
          Expanded(
            child: jobs.isEmpty
                ? Center(child: Text('Nothing exported yet.', style: Fx.caption(context)))
                : ListView.separated(
                    itemCount: jobs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Fx.s4),
                    itemBuilder: (context, i) => _JobRow(job: jobs[i], controller: controller, reveal: reveal, onMessage: onMessage),
                  ),
          ),
        ]));
      },
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.controller, required this.reveal, required this.onMessage});

  final TrimJob job;
  final TrimmerController controller;
  final void Function(String path) reveal;
  final void Function(String message) onMessage;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (job.status) {
      JobStatus.queued => (Fx.muted(context), Icons.schedule),
      JobStatus.running => (Fx.accent, Icons.content_cut),
      JobStatus.done => (Fx.success, Icons.check_circle),
      JobStatus.failed => (Fx.danger, Icons.error_outline),
      JobStatus.cancelled => (Fx.muted(context), Icons.block),
    };
    final label = job.status == JobStatus.running ? 'Cutting ${(job.progress * 100).round()}%' : job.status.label;
    return FxCard(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s12, vertical: Fx.s8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: Fx.s8),
          Expanded(child: Tooltip(message: job.output, child: Text(job.outputName, style: Fx.body(context), overflow: TextOverflow.ellipsis))),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          if (job.active) IconButton(tooltip: 'Stop', icon: const Icon(Icons.close, size: 16), visualDensity: VisualDensity.compact, onPressed: () => controller.cancel(job)),
          if (job.status == JobStatus.done) ...[
            IconButton(tooltip: 'Show in folder', icon: const Icon(Icons.folder_open, size: 16), visualDensity: VisualDensity.compact, onPressed: () => reveal(job.output)),
            IconButton(
              tooltip: 'Copy the file path',
              icon: const Icon(Icons.copy, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: job.output));
                onMessage('Path copied.');
              },
            ),
          ],
        ]),
        if (job.status == JobStatus.running || job.status == JobStatus.queued)
          Padding(
            padding: const EdgeInsets.only(top: Fx.s4),
            child: LinearProgressIndicator(value: job.status == JobStatus.queued ? 0 : job.progress, minHeight: 3),
          ),
        if (job.status == JobStatus.failed && job.error.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: Fx.s4), child: Text(job.error, style: Fx.caption(context).copyWith(color: Fx.danger), maxLines: 3, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}
