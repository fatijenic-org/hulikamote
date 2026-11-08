import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hulikamote_dashboard/core/utils/app_toast.dart';
import 'package:hulikamote_dashboard/core/utils/external_apps.dart';

/// Quick access to the progress deck (opens in the browser).
class ProgressReportScreen extends StatefulWidget {
  const ProgressReportScreen({super.key});

  @override
  State<ProgressReportScreen> createState() => _ProgressReportScreenState();
}

class _ProgressReportScreenState extends State<ProgressReportScreen> {
  Future<void> _open() async {
    final error = await ExternalApps.openProgressReport();
    if (!mounted) return;
    AppToast.show(context, error ?? 'Progress report opened in your browser.', isError: error != null);
  }

  @override
  Widget build(BuildContext context) {
    final file = ExternalApps.progressReportFile;
    return _LauncherPage(
      icon: Icons.slideshow,
      title: 'Progress Report',
      description: 'Step-by-step presentation of the project: goal, what changed since Aug 25, every data source, '
          'model results, the evaluation plan and the questions to expect. It opens in your browser.',
      statusChip: file != null ? ('Found', Colors.green) : ('Not found', Colors.redAccent),
      detailLines: [
        file?.path ?? 'Progress Report/index.html was not found in the repository.',
        'In the deck: arrow keys move, N shows speaker notes, G shows all slides, T switches the theme, F is fullscreen.',
      ],
      actions: [
        FilledButton.icon(
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Open in browser'),
          onPressed: file == null ? null : _open,
        ),
      ],
    );
  }
}

/// Quick access to the educational visualizer (a separate desktop app).
class VisualizerScreen extends StatefulWidget {
  const VisualizerScreen({super.key});

  @override
  State<VisualizerScreen> createState() => _VisualizerScreenState();
}

class _VisualizerScreenState extends State<VisualizerScreen> {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final running = await ExternalApps.isVisualizerRunning();
    if (mounted) setState(() => _running = running);
  }

  Future<void> _launch() async {
    final error = await ExternalApps.launchVisualizer();
    if (!mounted) return;
    AppToast.show(context, error ?? 'Visualizer is open.', isError: error != null);
    await Future<void>.delayed(const Duration(seconds: 2));
    _refresh();
  }

  Future<void> _build() async {
    final error = await ExternalApps.buildVisualizer();
    if (!mounted) return;
    AppToast.show(context, error ?? 'Building in a new window. Come back and press Launch when it finishes.',
        isError: error != null);
  }

  @override
  Widget build(BuildContext context) {
    final exe = ExternalApps.visualizerExe;
    final stale = ExternalApps.visualizerBuildIsStale();
    final built = exe?.lastModifiedSync();
    final chip = _running
        ? ('Running', Colors.green)
        : exe == null
            ? ('Not built', Colors.redAccent)
            : stale
                ? ('Build is older than the source', Colors.orange)
                : ('Ready', Colors.green);
    return _LauncherPage(
      icon: Icons.school,
      title: 'Visualizer',
      description: 'Interactive teaching tool: each violation is explained step by step, from the naive approach to '
          'the AI pipeline. It runs as its own desktop app, so closing the dashboard does not close it.',
      statusChip: chip,
      detailLines: [
        exe == null
            ? 'No build found under hulikamote_visualizer/build/windows.'
            : 'Build: ${exe.path}\nBuilt ${_fmt(built!)}'
                '${stale ? '. Source files are newer: rebuild to see the latest visualizers.' : '.'}',
        if (!Platform.isWindows) 'Launching the built app is supported on Windows only.',
      ],
      actions: [
        FilledButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: Text(_running ? 'Already open' : 'Launch visualizer'),
          onPressed: (exe == null || _running) ? null : _launch,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.build),
          label: Text(exe == null ? 'Build it' : 'Rebuild'),
          onPressed: _build,
        ),
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Check again', onPressed: _refresh),
      ],
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _LauncherPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final (String, Color) statusChip;
  final List<String> detailLines;
  final List<Widget> actions;

  const _LauncherPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.statusChip,
    required this.detailLines,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(icon, size: 36, color: Colors.blueAccent),
                    const SizedBox(width: 12),
                    Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineMedium)),
                    Chip(
                      label: Text(statusChip.$1),
                      backgroundColor: statusChip.$2.withAlpha(40),
                      side: BorderSide(color: statusChip.$2),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Text(description, style: const TextStyle(fontSize: 16, height: 1.5)),
                  const SizedBox(height: 24),
                  Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
                  const SizedBox(height: 28),
                  for (final line in detailLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SelectableText(line, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
