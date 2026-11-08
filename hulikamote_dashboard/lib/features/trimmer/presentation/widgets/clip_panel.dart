import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/time_format.dart';
import '../../domain/trim_session.dart';
import '../../domain/trimmer_controller.dart';
import 'time_field.dart';
import 'trim_timeline.dart' show clipColor;

/// The list of clips of the open video: pick several, lock them, change their times by typing, and export.
class ClipPanel extends StatelessWidget {
  const ClipPanel({
    super.key,
    required this.session,
    required this.controller,
    required this.position,
    required this.onSeek,
    required this.onPlayClip,
    required this.pickFolder,
    required this.onMessage,
  });

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
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _bulkBar(context, clips.length, selected),
          const SizedBox(height: Fx.s8),
          Expanded(
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
                      onExport: () => _export([clips[i]]),
                      onMessage: onMessage,
                    ),
                  ),
          ),
          const SizedBox(height: Fx.s8),
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

  Widget _footer(BuildContext context, int total, int selected) {
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
  });

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
          IconButton(tooltip: 'Export this clip', icon: const Icon(Icons.file_download_outlined, size: 18), visualDensity: VisualDensity.compact, onPressed: onExport),
          IconButton(
            tooltip: clip.locked ? 'Unlock to delete' : 'Delete this clip',
            icon: const Icon(Icons.delete_outline, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: clip.locked ? null : () => session.remove(clip.id),
          ),
        ]),
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
