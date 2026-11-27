import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/time_format.dart';
import '../../domain/trim_session.dart';
import '../../domain/trimmer_controller.dart';
import 'time_field.dart';
import 'trim_setup_dialog.dart';
import 'trim_timeline.dart' show clipColor;
import 'label_palette.dart' show labelColor;

/// Which part of the clip panel to show: the sidebar gives each part its own dropdown section.
enum ClipPart { all, list, footer }

/// The list of clips of the open video: pick several, lock them, change their times by typing, and export.
class ClipPanel extends StatelessWidget {
  const ClipPanel({
    super.key,
    this.part = ClipPart.all,
    required this.session,
    required this.controller,
    required this.position,
    required this.onSeek,
    required this.onPlayClip,
    required this.pickFolder,
    required this.onMessage,
  });

  final ClipPart part;
  final TrimSession session;
  final TrimmerController controller;
  final ValueListenable<double> position;
  final void Function(double seconds) onSeek;
  final void Function(TrimClip clip) onPlayClip;
  final Future<String?> Function() pickFolder;
  final void Function(String message) onMessage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([session, controller]),
      builder: (context, _) {
        final clips = session.clips;
        final selected = session.selected.length;
        if (part == ClipPart.footer) return _footer(context, clips.length, selected);
        if (part == ClipPart.list) {
          // inside a scrolling sidebar: the rows take their own height, the sidebar scrolls
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _bulkBar(context, clips.length, selected),
            const SizedBox(height: Fx.s8),
            if (clips.isEmpty)
              const SizedBox(
                height: 150,
                child: EmptyState(
                  icon: Icons.content_cut,
                  title: 'No clips yet',
                  message: 'Drag on the timeline to mark a clip, or press "Add clip" to start one at the playhead.',
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: clips.length,
                separatorBuilder: (_, _) => const SizedBox(height: Fx.s8),
                itemBuilder: (context, i) => _ClipRow(
                  key: ValueKey(clips[i].id),
                  session: session,
                  clip: clips[i],
                  position: position,
                  onSeek: onSeek,
                  onPlay: () => onPlayClip(clips[i]),
                  benchmark: controller.benchmarkMode,
                  onExport: () => _export([clips[i]]),
                  onMessage: onMessage,
                ),
              ),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _bulkBar(context, clips.length, selected),
          const SizedBox(height: Fx.s8),
          Expanded(
            flex: controller.benchmarkMode ? 2 : 1,
            child: clips.isEmpty
                ? const EmptyState(
                    icon: Icons.content_cut,
                    title: 'No clips yet',
                    message: 'Drag on the timeline to mark a clip, or press "Add clip" to start one at the playhead.',
                  )
                : ListView.separated(
                    itemCount: clips.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Fx.s8),
                    itemBuilder: (context, i) => _ClipRow(
                      key: ValueKey(clips[i].id),
                      session: session,
                      clip: clips[i],
                      position: position,
                      onSeek: onSeek,
                      onPlay: () => onPlayClip(clips[i]),
                      benchmark: controller.benchmarkMode,
                      onExport: () => _export([clips[i]]),
                      onMessage: onMessage,
                    ),
                  ),
          ),
          const SizedBox(height: Fx.s8),
          // the benchmark footer is tall (setup, switches, seconds, export): it scrolls inside its own share instead of overflowing
          if (controller.benchmarkMode)
            Flexible(flex: 3, child: SingleChildScrollView(child: _footer(context, clips.length, selected)))
          else
            _footer(context, clips.length, selected),
        ]);
      },
    );
  }

  Future<void> _export(List<TrimClip> clips) async {
    final ok = await controller.export(session, clips);
    onMessage(ok ? (clips.length == 1 ? 'Exporting 1 clip. You can keep working.' : 'Exporting ${clips.length} clips. You can keep working.') : (controller.error ?? 'Could not start the export.'));
    controller.clearError();
  }

  Widget _bulkBar(BuildContext context, int total, int selected) {
    final all = total > 0 && selected == total;
    return Row(children: [
      Checkbox(
        tristate: true,
        value: all ? true : (selected == 0 ? false : null),
        onChanged: total == 0 ? null : (_) => all ? session.clearSelection() : session.selectAll(),
      ),
      Expanded(child: Text(selected == 0 ? '$total clips' : '$selected of $total selected', style: Fx.caption(context))),
      IconButton(
        tooltip: 'Lock the selected clips',
        icon: const Icon(Icons.lock_outline, size: 20),
        visualDensity: VisualDensity.compact,
        onPressed: selected == 0 ? null : () => session.lockSelected(true),
      ),
      IconButton(
        tooltip: 'Unlock the selected clips',
        icon: const Icon(Icons.lock_open, size: 20),
        visualDensity: VisualDensity.compact,
        onPressed: selected == 0 ? null : () => session.lockSelected(false),
      ),
      IconButton(
        tooltip: 'Delete the selected clips (locked ones stay)',
        icon: const Icon(Icons.delete_outline, size: 20),
        visualDensity: VisualDensity.compact,
        onPressed: selected == 0
            ? null
            : () {
                final kept = session.selectedClips.where((c) => c.locked).length;
                session.removeSelected();
                if (kept > 0) onMessage('$kept locked clip${kept == 1 ? '' : 's'} kept. Unlock to delete.');
              },
      ),
    ]);
  }

  Future<void> _exportBenchmark() async {
    final ok = await controller.exportBenchmark(session);
    onMessage(ok ? (controller.benchNote ?? 'Exporting.') : (controller.error ?? 'Could not start the export.'));
    controller.clearError();
  }

  /// Opens the setup editor on the open video's picture at the playhead; the saved setup is picked at once (and is in the Live Monitor's list too).
  Future<void> _setupHere(BuildContext context) async {
    final id = await showTrimSetupDialog(context, videoPath: session.path, videoName: session.name, seconds: position.value);
    if (id == null) return;
    await controller.loadSetups();
    controller.setSetup(id);
    onMessage('Setup saved and picked. It is in the Live Monitor list too.');
  }

  Widget _benchmarkFooter(BuildContext context) {
    final pending = session.toExport.length;
    final done = session.clips.where((c) => c.exported).length;
    final unlabelled = session.clips.where((c) => c.labels.isEmpty).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        '$pending slice${pending == 1 ? '' : 's'} ready · $done exported${unlabelled > 0 ? ' · $unlabelled without a label (skipped)' : ''}',
        style: Fx.caption(context),
      ),
      const SizedBox(height: 2),
      Text(
        'Extra seconds of normal traffic before and after each violation. Auto = the recommended seconds of each label (the longest wins when a slice '
        'has several). Saved in A:/huli-kamote/benchmark-videos, in a folder for each violation, and added to the benchmark list with its events. Cutting runs in the background.',
        style: Fx.caption(context),
      ),
      const SizedBox(height: Fx.s8),
      DropdownButtonFormField<String?>(
        key: const ValueKey('bench-setup'),
        isExpanded: true,
        initialValue: controller.setupId,
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'Setup with the zones and overlays',
          helperText: 'A saved setup of this camera view. Zone rules (parking, counterflow ...) are scored inside its zones.',
          helperMaxLines: 2,
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('None (no zones)')),
          for (final s in controller.setups)
            DropdownMenuItem<String?>(value: s.id, child: Text('${s.name}  ·  ${s.violations.length} violations', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: controller.setSetup,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('bench-setup-here'),
          onPressed: () => _setupHere(context),
          icon: const Icon(Icons.draw_outlined, size: 18),
          label: const Text('Set up here (draw zones and signs on this video)'),
        ),
      ),
      // a setting shows only when a slice waiting to be exported has the violation it belongs to
      if (session.pendingHas((k) => k == 'counterflow'))
        SwitchListTile(
          key: const ValueKey('reverse-counterflow'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: controller.reverseCounterflow,
          onChanged: controller.setReverseCounterflow,
          title: const Text('Reverse counterflow (simulated)'),
          subtitle: const Text('No real wrong-way traffic? Flip the legal direction so normal traffic counts as wrong-way. Say "simulated" in the thesis.'),
        ),
      if (session.pendingHas(twoWheelerRules.contains))
        SwitchListTile(
          key: const ValueKey('incoming-two-wheelers'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: controller.incomingTwoWheelers,
          onChanged: controller.setIncomingTwoWheelers,
          title: const Text('Judge incoming motorcycles and tricycles (demo)'),
          subtitle: const Text('Normally they are left out when they come toward the camera (no plate is seen). Turn on to benchmark them; report them as a separate demo group.'),
        ),
      if (session.pendingHas((k) => k == 'overloading')) ...[
        Row(children: [
          Expanded(child: Text('Overloading limit (riders)', style: Fx.body(context))),
          SegmentedButton<int>(
            key: const ValueKey('overloading-limit'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [ButtonSegment(value: 2, label: Text('2 normal')), ButtonSegment(value: 1, label: Text('1 demo'))],
            selected: {controller.overloadingLimit.clamp(1, 2)},
            onSelectionChanged: (v) => controller.setOverloadingLimit(v.first),
          ),
        ]),
        Text('Demo 1: a motorcycle with two riders counts as overloaded, for when you have few real cases. Report it as a demo.', style: Fx.caption(context)),
      ],
      const SizedBox(height: Fx.s4),
      SegmentedButton<int>(
        key: const ValueKey('bench-pad'),
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: 0, label: Text('Auto')),
          ButtonSegment(value: 3, label: Text('3 s')),
          ButtonSegment(value: 5, label: Text('5 s')),
          ButtonSegment(value: 8, label: Text('8 s')),
        ],
        selected: {controller.benchPad},
        onSelectionChanged: (v) => controller.setBenchPad(v.first),
      ),
      const SizedBox(height: Fx.s4),
      Row(children: [
        Expanded(
          child: Tooltip(
            message: 'When every cut of this export is done, the benchmark starts on the new clips by itself. It is slow (about 10 times the '
                'footage) and uses the graphics card, so turn it off if you want to keep the laptop free.',
            child: Text('Score automatically when cutting is done', style: Fx.body(context)),
          ),
        ),
        Switch(key: const ValueKey('auto-score'), value: controller.autoScore, onChanged: controller.setAutoScore),
      ]),
      const SizedBox(height: Fx.s4),
      FilledButton.icon(
        key: const ValueKey('export-benchmark'),
        onPressed: pending == 0 ? null : _exportBenchmark,
        icon: const Icon(Icons.rocket_launch_outlined, size: 18),
        label: Text(pending == 0 ? 'Export to benchmark' : 'Export $pending to benchmark'),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
      ),
    ]);
  }

  Widget _footer(BuildContext context, int total, int selected) {
    if (controller.benchmarkMode) return _benchmarkFooter(context);
    final folder = controller.outputDir;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.folder_outlined, size: 18),
        const SizedBox(width: Fx.s8),
        Expanded(child: Text(folder.isEmpty ? 'Save next to the video' : folder, style: Fx.caption(context), overflow: TextOverflow.ellipsis)),
        if (folder.isNotEmpty) IconButton(tooltip: 'Back to next to the video', icon: const Icon(Icons.close, size: 16), visualDensity: VisualDensity.compact, onPressed: () => controller.setOutputDir('')),
        TextButton(
          onPressed: () async {
            final picked = await pickFolder();
            if (picked != null) controller.setOutputDir(picked);
          },
          child: const Text('Choose folder'),
        ),
      ]),
      Row(children: [
        Expanded(
          child: Tooltip(
            message: 'Off: the clip is copied as it is, which is instant and loses no quality, but it starts at the nearest earlier keyframe '
                '(usually within a second or two).\nOn: the clip is re-encoded so it starts exactly where you put it. Slower.',
            child: Text('Exact cut (slower)', style: Fx.body(context)),
          ),
        ),
        Switch(value: controller.exact, onChanged: controller.setExact),
      ]),
      const SizedBox(height: Fx.s4),
      Row(children: [
        Expanded(
          flex: 3,
          child: FilledButton(
            onPressed: selected == 0 ? null : () => _export(session.selectedClips),
            child: Text(selected == 0 ? 'Export selected' : 'Export selected ($selected)', overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: Fx.s8),
        Expanded(
          flex: 2,
          child: OutlinedButton(
            onPressed: total == 0 ? null : () => _export(List.of(session.clips)),
            child: Text('Export all ($total)', overflow: TextOverflow.ellipsis),
          ),
        ),
      ]),
    ]);
  }
}

class _ClipRow extends StatelessWidget {
  const _ClipRow({
    super.key,
    required this.session,
    required this.clip,
    required this.position,
    required this.onSeek,
    required this.onPlay,
    required this.onExport,
    required this.onMessage,
    this.benchmark = false,
  });

  /// Benchmark labelling: the row shows the slice's labels and has no single-clip export.
  final bool benchmark;

  final TrimSession session;
  final TrimClip clip;
  final ValueListenable<double> position;
  final void Function(double seconds) onSeek;
  final VoidCallback onPlay;
  final VoidCallback onExport;
  final void Function(String message) onMessage;

  @override
  Widget build(BuildContext context) {
    final isSelected = session.selected.contains(clip.id);
    final number = session.clips.indexOf(clip) + 1;
    final color = clipColor(clip);
    final labelsText = session.labelText(clip);
    return FxCard(
      selected: isSelected,
      padding: const EdgeInsets.symmetric(horizontal: Fx.s4, vertical: Fx.s4),
      onTap: () {
        final multi = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed;
        session.select(clip.id, additive: multi);
        if (!multi) onSeek(clip.start);                     // clicking a clip takes the playhead to its start
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Checkbox(value: isSelected, onChanged: (_) => session.select(clip.id, additive: true), visualDensity: VisualDensity.compact),
          CircleAvatar(radius: 11, backgroundColor: color, child: Text('$number', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87))),
          const SizedBox(width: Fx.s8),
          Expanded(
            child: _NameField(clip: clip, hint: 'Clip $number', onSubmit: (text) {
              if (!session.rename(clip.id, text)) onMessage('Unlock the clip to rename it.');
            }),
          ),
          Text(formatClock(clip.length), style: Fx.caption(context)),
          IconButton(
            tooltip: clip.locked ? 'Locked: click to unlock' : 'Lock this clip so it cannot be moved by accident',
            icon: Icon(clip.locked ? Icons.lock : Icons.lock_open, size: 18, color: clip.locked ? Fx.warning : null),
            visualDensity: VisualDensity.compact,
            onPressed: () => session.setLocked(clip.id, !clip.locked),
          ),
          IconButton(tooltip: 'Play this clip', icon: const Icon(Icons.play_arrow, size: 20), visualDensity: VisualDensity.compact, onPressed: onPlay),
          if (!benchmark) IconButton(tooltip: 'Export this clip', icon: const Icon(Icons.file_download_outlined, size: 18), visualDensity: VisualDensity.compact, onPressed: onExport),
          if (benchmark && clip.exported) const Tooltip(message: 'Exported to the benchmark folder', child: Icon(Icons.check_circle, size: 18, color: Color(0xFF3CCB8C))),
          IconButton(
            tooltip: clip.locked ? 'Unlock to delete' : 'Delete this clip',
            icon: const Icon(Icons.delete_outline, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: clip.locked ? null : () => session.remove(clip.id),
          ),
        ]),
        if (benchmark)
          Padding(
            padding: const EdgeInsets.fromLTRB(Fx.s8, 0, Fx.s8, Fx.s4),
            child: Row(children: [
              Icon(clip.labels.isEmpty ? Icons.label_off_outlined : Icons.label, size: 14, color: labelColor(clip.labels)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  clip.labels.isEmpty
                      ? 'No label yet: click one in the list'
                      : '$labelsText${session.recommendedPad(clip) > 0 ? '  ·  +${session.recommendedPad(clip)} s each side' : ''}${clip.plate.isNotEmpty ? '  ·  ${clip.plate}' : ''}${clip.count > 1 ? '  ·  ${clip.count} vehicles' : ''}',
                  style: Fx.caption(context).copyWith(color: clip.labels.isEmpty ? Fx.warning : null, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Fx.s8, 0, Fx.s8, Fx.s4),
          child: Row(children: [
            Expanded(child: TimeField(label: 'Start', value: clip.start, enabled: !clip.locked, onSubmit: (t) => _setRange(t, clip.end), onSetToPlayhead: () => _setRange(position.value, clip.end))),
            const SizedBox(width: Fx.s8),
            Expanded(child: TimeField(label: 'End', value: clip.end, enabled: !clip.locked, onSubmit: (t) => _setRange(clip.start, t), onSetToPlayhead: () => _setRange(clip.start, position.value))),
          ]),
        ),
      ]),
    );
  }

  /// False (with a message) when the clip is locked or the times do not fit the video.
  bool _setRange(double start, double end) {
    final ok = session.setRange(clip.id, start, end);
    if (!ok) {
      onMessage(clip.locked ? 'Unlock the clip to change it.' : 'That does not fit: a clip is at least ${TrimSession.minLength} s long and stays inside the video.');
    }
    return ok;
  }
}

class _NameField extends StatefulWidget {
  const _NameField({required this.clip, required this.hint, required this.onSubmit});

  final TrimClip clip;
  final String hint;
  final void Function(String text) onSubmit;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final _controller = TextEditingController(text: widget.clip.label);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onSubmit(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      readOnly: widget.clip.locked,
      onSubmitted: widget.onSubmit,
      decoration: InputDecoration(isDense: true, hintText: widget.hint, border: InputBorder.none),
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }
}
