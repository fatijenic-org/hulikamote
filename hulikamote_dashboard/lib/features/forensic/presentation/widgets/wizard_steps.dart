import 'package:flutter/material.dart';

import '../../data/forensic_api.dart';
import '../../data/forensic_media.dart';
import '../../domain/analysis_draft.dart';
import '../../domain/analysis_runner.dart';
import '../../domain/violation_catalog.dart';
import '../../../trimmer/presentation/widgets/trim_player.dart';
import 'fx.dart';
import 'video_trim_panel.dart';
import 'violation_params.dart';
import 'zone_editor.dart';

/// Step 1: choose the video, then watch it and pick the part to analyze.
class VideoStep extends StatelessWidget {
  const VideoStep({
    super.key,
    required this.draft,
    required this.player,
    required this.preparing,
    required this.error,
    required this.onPick,
    required this.onConvert,
    this.filmstripUrl,
  });

  final AnalysisDraft draft;

  /// Shows the chosen video (made when the first video is picked).
  final TrimPlayer? player;

  /// The picture for drawing zones is being looked up.
  final bool preparing;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback onConvert;
  final String? filmstripUrl;

  @override
  Widget build(BuildContext context) {
    final shown = player;
    if (draft.hasVideoPath && shown != null) {
      return VideoTrimPanel(draft: draft, player: shown, preparing: preparing, onPick: onPick, filmstripUrl: filmstripUrl);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          FxBanner(message: error!),
          const SizedBox(height: Fx.s16),
        ],
        InkWell(
          borderRadius: BorderRadius.circular(Fx.radius),
          onTap: onPick,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: 56,
              horizontal: Fx.s24,
            ),
            decoration: BoxDecoration(
              color: Fx.panel(context),
              borderRadius: BorderRadius.circular(Fx.radius),
              border: Border.all(color: Fx.border(context), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(Fx.s16),
                  decoration: BoxDecoration(
                    color: Fx.accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.video_file_outlined,
                    size: 36,
                    color: Fx.accent,
                  ),
                ),
                const SizedBox(height: Fx.s16),
                Text('Choose a video to analyze', style: Fx.title(context)),
                const SizedBox(height: Fx.s8),
                Text(
                  'CCTV or dashcam footage (MP4, AVI, MOV, MKV). A clip of 30 seconds to 2 minutes is quickest to check.',
                  textAlign: TextAlign.center,
                  style: Fx.caption(context),
                ),
                const SizedBox(height: Fx.s24),
                FilledButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Choose video…'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Fx.s12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onConvert,
            icon: const Icon(Icons.transform, size: 16),
            label: const Text(
              'The video will not play? Convert it to H.264 first',
            ),
          ),
        ),
      ],
    );
  }
}

/// Step 2: which violations to look for, grouped, with what each one needs.
class ViolationsStep extends StatelessWidget {
  const ViolationsStep({super.key, required this.draft, required this.models});

  final AnalysisDraft draft;
  final ModelChoices models;

  @override
  Widget build(BuildContext context) {
    final all = ViolationCatalog.selectable;
    final n = draft.selection.length;
    return ListView(
      children: [
        Row(
          children: [
            Text('$n of ${all.length} selected', style: Fx.heading(context)),
            const Spacer(),
            TextButton(
              onPressed: () => draft.selectAll([
                for (final v in all)
                  if (v.needsModel == null) v.key,
              ]),
              child: const Text('Select all that need no model'),
            ),
            TextButton(
              onPressed: n == 0 ? null : draft.clearSelection,
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: Fx.s8),
        for (final g in ViolationGroup.values) ...[
          SectionLabel(g.title),
          Wrap(
            spacing: Fx.s12,
            runSpacing: Fx.s12,
            children: [
              for (final v in ViolationCatalog.inGroup(g))
                _PickCard(
                  info: v,
                  draft: draft,
                  modelMissing:
                      v.needsModel != null &&
                      models.loaded &&
                      !models.ready(v.needsModel!),
                ),
            ],
          ),
          const SizedBox(height: Fx.s24),
        ],
      ],
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.info,
    required this.draft,
    required this.modelMissing,
  });

  final ViolationInfo info;
  final AnalysisDraft draft;
  final bool modelMissing;

  @override
  Widget build(BuildContext context) {
    final on = draft.isSelected(info.key);
    return SizedBox(
      width: 300,
      child: FxCard(
        selected: on,
        padding: const EdgeInsets.all(Fx.s12),
        onTap: () => draft.toggle(info.key),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: info.color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(info.icon, size: 18, color: info.color),
                ),
                const SizedBox(width: Fx.s12),
                Expanded(child: Text(info.label, style: Fx.heading(context))),
                Icon(
                  on ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: on ? Fx.accent : Fx.muted(context),
                ),
              ],
            ),
            const SizedBox(height: Fx.s8),
            Text(info.blurb, style: Fx.caption(context)),
            const SizedBox(height: Fx.s8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (info.needsZone)
                  StatusPill(
                    label: 'Draw a zone',
                    color: Fx.muted(context),
                    icon: Icons.crop_free,
                    dense: true,
                  ),
                if (info.key == 'overloading')
                  StatusPill(
                    label: 'Set a rider limit',
                    color: Fx.muted(context),
                    icon: Icons.tune,
                    dense: true,
                  ),
                if (modelMissing)
                  const StatusPill(
                    label: 'Model not trained yet',
                    color: Fx.warning,
                    icon: Icons.warning_amber_rounded,
                    dense: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 3: set up each selected violation (zones, limits). A rail on the left, the editor on the right.
class RulesStep extends StatelessWidget {
  const RulesStep({
    super.key,
    required this.draft,
    required this.media,
    required this.current,
    required this.onPick,
    this.api,
  });

  final AnalysisDraft draft;
  final ForensicMedia media;
  final String current;
  final void Function(String key) onPick;

  /// Lets the zone editor suggest zones from the painted lines of the video.
  final ForensicApi? api;

  @override
  Widget build(BuildContext context) {
    final keys = draft.selection;
    // This step does not let the user go on without zones, so the "skip the drawing" switch has to be here too.
    final autoCard = AnalysisDraft.autoFlowKeys.contains(current)
        ? _AutoFlowCard(draft: draft)
        : null;
    return LayoutBuilder(
      builder: (context, box) {
        final rail = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final k in keys) _railItem(context, k)],
        );
        final editor =
            current == 'overloading' || !ViolationCatalog.of(current).needsZone
            ? _parametersOnly(context)
            : ZoneEditor(
                key: ValueKey('editor-$current'),
                draft: draft,
                violationKey: current,
                frame: media.frame(draft.frameUrl!),
                api: api,
              );
        if (box.maxWidth < 760) {
          return ListView(
            children: [
              SizedBox(
                height: 66,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final k in keys)
                      SizedBox(width: 220, child: _railItem(context, k)),
                  ],
                ),
              ),
              const SizedBox(height: Fx.s16),
              if (autoCard != null) ...[
                autoCard,
                const SizedBox(height: Fx.s12),
              ],
              editor,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 230, child: ListView(children: [rail])),
            const SizedBox(width: Fx.s16),
            Expanded(
              child: _scrollsItself(current)
                  ? (autoCard == null
                        ? editor
                        : Column(
                            children: [
                              autoCard,
                              const SizedBox(height: Fx.s12),
                              Expanded(child: editor),
                            ],
                          ))
                  : ListView(children: [editor]),
            ),
          ],
        );
      },
    );
  }

  /// The zone editor manages its own scrolling (canvas fixed, panel scrolls); other editors are plain lists.
  bool _scrollsItself(String key) =>
      key != 'overloading' && ViolationCatalog.of(key).needsZone;

  Widget _railItem(BuildContext context, String key) {
    final info = ViolationCatalog.of(key);
    final selected = key == current;
    final zones = draft.zones(key).length;
    final ready = draft.zonesReady(key);
    final automatic = zones == 0 && ready && info.needsZone;
    final subtitle = !info.needsZone
        ? 'No zone needed'
        : automatic
        ? 'Automatic: learns the flow'
        : (zones == 0
              ? 'Needs a zone'
              : '$zones zone${zones == 1 ? '' : 's'} saved');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FxCard(
        selected: selected,
        padding: const EdgeInsets.symmetric(
          horizontal: Fx.s12,
          vertical: Fx.s8,
        ),
        onTap: () => onPick(key),
        child: Row(
          children: [
            Icon(info.icon, size: 18, color: info.color),
            const SizedBox(width: Fx.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.label,
                    style: Fx.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: Fx.caption(
                      context,
                    ).copyWith(color: ready ? null : Fx.warning),
                  ),
                ],
              ),
            ),
            Icon(
              ready ? Icons.check_circle : Icons.error_outline,
              size: 18,
              color: ready ? Fx.success : Fx.warning,
            ),
          ],
        ),
      ),
    );
  }

  Widget _parametersOnly(BuildContext context) {
    final info = ViolationCatalog.of(current);
    return FxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(info.icon, color: info.color),
              const SizedBox(width: Fx.s12),
              Expanded(child: Text(info.label, style: Fx.title(context))),
            ],
          ),
          const SizedBox(height: Fx.s8),
          Text(info.blurb, style: Fx.caption(context)),
          const SizedBox(height: Fx.s16),
          ViolationParams(
            draft: draft,
            violationKey: current,
            onChanged: () {},
          ),
          if (current != 'overloading')
            Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: Fx.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Nothing to draw or set for this one. It is ready.',
                    style: Fx.body(context),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The same switch as in Settings (one shared value), shown above the zone editor of every rule in AnalysisDraft.autoFlowKeys.
class _AutoFlowCard extends StatelessWidget {
  const _AutoFlowCard({required this.draft});

  final AnalysisDraft draft;

  @override
  Widget build(BuildContext context) {
    final s = draft.settings;
    return FxCard(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s16, vertical: Fx.s8),
      child: Row(
        children: [
          const Icon(Icons.alt_route, size: 18, color: Fx.accent),
          const SizedBox(width: Fx.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detect traffic flow automatically',
                  style: Fx.body(context).copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Skip the drawing: the system learns which way traffic goes from the first minute of the video '
                  '(fixed camera and some traffic needed). A zone you do draw still takes priority.',
                  style: Fx.caption(context),
                ),
              ],
            ),
          ),
          Switch(
            value: s.autoFlow,
            onChanged: (v) {
              s.autoFlow = v;
              draft.touch();
            },
          ),
        ],
      ),
    );
  }
}

/// Step 4: pipeline options, grouped, with plain explanations and recommended defaults.
class SettingsStep extends StatelessWidget {
  const SettingsStep({super.key, required this.draft, required this.models});

  final AnalysisDraft draft;
  final ModelChoices models;

  PipelineSettings get s => draft.settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) => ListView(
        children: [
          _group(context, 'Detection', Icons.radar, [
            _row(
              context,
              'Vehicle detector',
              'Finds cars, motorcycles, buses and people in every frame.',
              _dropdown(s.primaryModel, [
                ('', 'Active model${_active('vehicles')}'),
                ...models.names('vehicles').map((n) => (n, n)),
              ], (v) => s.primaryModel = v),
            ),
            _row(
              context,
              'Tracker',
              'Keeps one ID per vehicle while it is on screen.',
              _segmented(s.tracker, const [
                ('bytetrack', 'ByteTrack (fast)'),
                ('deepsort', 'DeepSORT (accurate)'),
              ], (v) => s.tracker = v),
            ),
          ]),
          const SizedBox(height: Fx.s16),
          _group(context, 'License plates', Icons.pin_outlined, [
            _row(
              context,
              'Plate model',
              'Finds the plate on each vehicle.',
              _dropdown(s.plateModel, [
                ('', 'Active model${_active('plate')}'),
                ...models.names('plate').map((n) => (n, n)),
              ], (v) => s.plateModel = v),
            ),
            _row(
              context,
              'Plate search',
              'Smart looks for the plate first; Direct OCR reads the bumper area every time.',
              _segmented(s.plateMethod, const [
                ('smart', 'Smart'),
                ('direct_ocr', 'Direct OCR'),
              ], (v) => s.plateMethod = v),
            ),
            _row(
              context,
              'Plate format',
              'Used to correct common reading mistakes.',
              _dropdown(s.plateFormat, const [
                ('ph_standard', 'Philippines (ABC 1234)'),
                ('uk_standard', 'United Kingdom (AB12 CDE)'),
                ('raw', 'Raw, no correction'),
              ], (v) => s.plateFormat = v),
            ),
            _row(
              context,
              'OCR engine',
              'Reads the characters.',
              _segmented(s.ocrEngine, const [
                ('easyocr', 'EasyOCR'),
                ('paddleocr', 'PaddleOCR'),
              ], (v) => s.ocrEngine = v),
            ),
            _row(
              context,
              'Enhance plate crops',
              'Sharpens small plates before reading.',
              _dropdown(s.enhancement, const [
                ('realesrgan', 'Real-ESRGAN (best)'),
                ('lanczos', 'Lanczos (fast)'),
                ('lapsrn', 'LapSRN'),
                ('none', 'None'),
              ], (v) => s.enhancement = v),
            ),
          ]),
          const SizedBox(height: Fx.s16),
          _group(context, 'Review & storage', Icons.fact_check_outlined, [
            _slider(
              context,
              'Duplicate sensitivity',
              '${s.flagSensitivity} of 7 · ${s.flagSensitivity <= 2
                  ? 'strict'
                  : s.flagSensitivity >= 6
                  ? 'sensitive'
                  : 'balanced'}',
              'Higher flags more tickets as possible duplicates or tracker mix-ups. Lower flags only obvious cases.',
              s.flagSensitivity.toDouble(),
              1,
              7,
              (v) => s.flagSensitivity = v.round(),
            ),
            _slider(
              context,
              'Evidence photo gap',
              'every ${s.evidenceGap} frame${s.evidenceGap == 1 ? '' : 's'}',
              'About ${draft.photosPerSecond.toStringAsFixed(1)} photos per second of a flagged car'
                  '${draft.frameCount > 0 ? ', up to ~${(draft.frameCount / s.evidenceGap).ceil()} for a car seen the whole video' : ''}. '
                  'Lower means more photos, more disk space and a longer review.',
              s.evidenceGap.toDouble(),
              1,
              5,
              (v) => s.evidenceGap = v.round(),
            ),
            _row(
              context,
              'Detect traffic flow automatically',
              'Counterflow, swerving, illegal turn, illegal U-turn, signal light, truck ban, tricycle on highway, '
                  'illegal loading, double parking and illegal parking then need no zone or arrow: the system learns '
                  'which way traffic goes from the first minute of the video (needs a fixed camera and some traffic). '
                  'Zones you do draw still take priority.',
              Switch(
                value: s.autoFlow,
                onChanged: (v) {
                  s.autoFlow = v;
                  draft.touch();
                },
              ),
            ),
            _row(
              context,
              'Keep the uploaded video',
              'Off deletes it when the analysis ends (saves disk). Turn on for “Send to Live Monitor” and for more Harvest pictures.',
              Switch(
                value: s.keepInputVideo,
                onChanged: (v) {
                  s.keepInputVideo = v;
                  draft.touch();
                },
              ),
            ),
            _row(
              context,
              'Blur faces and other plates in saved photos',
              'On is the privacy rule of the study. Turn it off only for your own training videos, so heads and helmets stay '
                  'visible for Harvest. Never confirm or send tickets from a run with this off.',
              Switch(
                value: s.blurPrivacy,
                onChanged: (v) {
                  s.blurPrivacy = v;
                  draft.touch();
                },
              ),
            ),
          ]),
        ],
      ),
    );
  }

  String _active(String type) =>
      models.active(type) == null ? '' : ' (${models.active(type)})';

  Widget _group(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> rows,
  ) {
    return FxCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Fx.s16, Fx.s12, Fx.s16, Fx.s8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: Fx.muted(context)),
                const SizedBox(width: Fx.s8),
                Text(title, style: Fx.heading(context)),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            Divider(height: 1, color: Fx.border(context)),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String title, String help, Widget control) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s16, vertical: Fx.s12),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Fx.body(context).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(help, style: Fx.caption(context)),
              ],
            ),
          ),
          const SizedBox(width: Fx.s16),
          Expanded(
            flex: 4,
            child: Align(alignment: Alignment.centerRight, child: control),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    BuildContext context,
    String title,
    String value,
    String help,
    double v,
    double min,
    double max,
    void Function(double) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s16, vertical: Fx.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Fx.body(context).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(value, style: Fx.heading(context)),
            ],
          ),
          Slider(
            value: v,
            min: min,
            max: max,
            divisions: (max - min).toInt(),
            onChanged: (x) {
              onChanged(x);
              draft.touch();
            },
          ),
          Text(help, style: Fx.caption(context)),
        ],
      ),
    );
  }

  Widget _dropdown(
    String value,
    List<(String, String)> items,
    void Function(String) set,
  ) {
    final known = items.any((e) => e.$1 == value);
    return DropdownButton<String>(
      isExpanded: true,
      value: known ? value : items.first.$1,
      items: [
        for (final (v, label) in items)
          DropdownMenuItem(
            value: v,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v == null) return;
        set(v);
        draft.touch();
      },
    );
  }

  Widget _segmented(
    String value,
    List<(String, String)> items,
    void Function(String) set,
  ) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final (v, label) in items)
          ButtonSegment(value: v, label: Text(label)),
      ],
      selected: {value},
      onSelectionChanged: (sel) {
        set(sel.first);
        draft.touch();
      },
    );
  }
}

/// Step 5: a last look, the start button, and the live progress once it runs.
class RunStep extends StatelessWidget {
  const RunStep({
    super.key,
    required this.draft,
    required this.runner,
    required this.models,
    required this.onStart,
    required this.onBackToSettings,
    this.onUseForLive,
    this.onOpenLive,
  });

  final AnalysisDraft draft;
  final AnalysisRunner runner;
  final ModelChoices models;
  final VoidCallback onStart;
  final VoidCallback onBackToSettings;

  /// Sends these zones and settings to the Live Monitor without running an analysis.
  final VoidCallback? onUseForLive;

  /// Opens the tickets released so far, while the analysis is still reading the video.
  final VoidCallback? onOpenLive;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: runner,
      builder: (context, _) {
        switch (runner.phase) {
          case RunPhase.uploading:
          case RunPhase.running:
          case RunPhase.done:
            return _progress(context);
          case RunPhase.failed:
            return _failed(context);
          case RunPhase.idle:
            return _ready(context);
        }
      },
    );
  }

  Widget _ready(BuildContext context) {
    final sel = draft.selection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (runner.notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Fx.s12),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Fx.muted(context)),
                const SizedBox(width: Fx.s12),
                Expanded(child: Text(runner.notice!, key: const Key('run-notice'), style: Fx.body(context))),
              ],
            ),
          ),
        FxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.rocket_launch_outlined, color: Fx.accent),
                  const SizedBox(width: Fx.s12),
                  Text('Ready to analyze', style: Fx.title(context)),
                ],
              ),
              const SizedBox(height: Fx.s16),
              _line(
                context,
                Icons.video_file_outlined,
                'Video',
                draft.videoName ?? '—',
              ),
              _line(
                context,
                Icons.rule,
                'Violations',
                '${sel.length}: ${sel.map((k) => ViolationCatalog.of(k).label).join(', ')}',
              ),
              _line(
                context,
                Icons.crop_free,
                'Zones',
                '${[for (final k in sel) draft.zones(k).length].fold<int>(0, (a, b) => a + b)} drawn',
              ),
              _line(
                context,
                Icons.pin_outlined,
                'Plate model',
                draft.settings.plateModel.isEmpty
                    ? (models.active('plate') ?? 'active model')
                    : draft.settings.plateModel,
              ),
              _line(
                context,
                Icons.photo_library_outlined,
                'Evidence',
                'a photo every ${draft.settings.evidenceGap} frames',
              ),
              const SizedBox(height: Fx.s16),
              Text(
                'The analysis runs on the backend. You can leave this page; the result will wait in the Library.',
                style: Fx.caption(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: Fx.s16),
        Row(
          children: [
            TextButton.icon(
              onPressed: onBackToSettings,
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('Adjust settings'),
            ),
            const Spacer(),
            if (onUseForLive != null) ...[
              OutlinedButton.icon(
                onPressed: draft.canStart ? onUseForLive : null,
                icon: const Icon(Icons.sensors, size: 18),
                label: const Text('Use for Live Monitor'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
              const SizedBox(width: Fx.s12),
            ],
            FilledButton.icon(
              onPressed: draft.canStart ? onStart : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start analysis'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 28),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _line(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Fx.muted(context)),
        const SizedBox(width: Fx.s12),
        SizedBox(width: 110, child: Text(label, style: Fx.caption(context))),
        Expanded(child: Text(value, style: Fx.body(context))),
      ],
    ),
  );

  Widget _progress(BuildContext context) {
    final done = runner.phase == RunPhase.done;
    final indeterminate = runner.phase == RunPhase.uploading;
    final rem = runner.remaining;
    String mmss(Duration d) =>
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FxCard(
          padding: const EdgeInsets.all(Fx.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (done)
                    const Icon(Icons.check_circle, color: Fx.success)
                  else
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  const SizedBox(width: Fx.s12),
                  Expanded(
                    child: Text(runner.stage, style: Fx.heading(context)),
                  ),
                  Text(
                    indeterminate
                        ? ''
                        : '${runner.progress.toStringAsFixed(0)}%',
                    style: Fx.title(context),
                  ),
                ],
              ),
              const SizedBox(height: Fx.s16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: indeterminate ? null : runner.progress / 100,
                  minHeight: 8,
                  color: done ? Fx.success : Fx.accent,
                  backgroundColor: Fx.raised(context),
                ),
              ),
              const SizedBox(height: Fx.s12),
              Text(
                'Elapsed ${mmss(runner.elapsed)}${rem == null ? '' : '  ·  about ${mmss(rem)} left'}',
                style: Fx.caption(context),
              ),
              if (runner.phase == RunPhase.running && runner.ticketsReady > 0 && onOpenLive != null) ...[
                const SizedBox(height: Fx.s16),
                Row(
                  children: [
                    const Icon(Icons.fact_check_outlined, size: 20, color: Fx.accent),
                    const SizedBox(width: Fx.s12),
                    Expanded(
                      child: Text(
                        runner.ticketsReady == 1
                            ? '1 ticket is ready to review. More arrive as cars leave the video.'
                            : '${runner.ticketsReady} tickets are ready to review. More arrive as cars leave the video.',
                        key: const Key('tickets-ready'),
                        style: Fx.body(context),
                      ),
                    ),
                    FilledButton.icon(
                      key: const Key('review-ready'),
                      onPressed: onOpenLive,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Review them now'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: Fx.s16),
              Text(
                'You can leave this page. The analysis keeps running on the backend and will appear in the Library.',
                style: Fx.caption(context),
              ),
              if (runner.phase == RunPhase.running) ...[
                const SizedBox(height: Fx.s16),
                if (runner.stopError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Fx.s12),
                    child: Text(
                      runner.stopError!,
                      key: const Key('stop-error'),
                      style: Fx.caption(context).copyWith(color: Fx.danger),
                    ),
                  ),
                Row(
                  children: [
                    Tooltip(
                      message: 'End the analysis now and keep everything found so far',
                      child: OutlinedButton.icon(
                        key: const Key('stop-here'),
                        onPressed: runner.asking ? null : runner.stopHere,
                        icon: const Icon(Icons.content_cut, size: 18),
                        label: const Text('Stop here'),
                      ),
                    ),
                    const SizedBox(width: Fx.s12),
                    TextButton.icon(
                      key: const Key('cancel-analysis'),
                      onPressed: runner.asking ? null : () => _confirmCancel(context),
                      icon: const Icon(Icons.close, size: 18, color: Fx.danger),
                      label: const Text('Cancel analysis', style: TextStyle(color: Fx.danger)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Cancel throws everything away, so it asks once.
  Future<void> _confirmCancel(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this analysis?'),
        content: Text(
          'Everything found so far is thrown away: no tickets, no evidence, no result video. '
          '${runner.ticketsReady > 0 ? 'The ${runner.ticketsReady} ticket${runner.ticketsReady == 1 ? '' : 's'} already released (also any you confirmed) are removed too. ' : ''}'
          'To keep what was found, use Stop here instead.',
          key: const Key('cancel-warning'),
        ),
        actions: [
          TextButton(
            key: const Key('cancel-keep-going'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            key: const Key('cancel-confirm'),
            style: FilledButton.styleFrom(backgroundColor: Fx.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel analysis'),
          ),
        ],
      ),
    );
    if (sure == true) await runner.cancel();
  }

  Widget _failed(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FxCard(
          padding: const EdgeInsets.all(Fx.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline, color: Fx.danger),
                  const SizedBox(width: Fx.s12),
                  Expanded(
                    child: Text(
                      'The analysis did not finish',
                      style: Fx.heading(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Fx.s12),
              Text(runner.error ?? 'Unknown error.', style: Fx.body(context)),
              const SizedBox(height: Fx.s16),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: onBackToSettings,
                    child: const Text('Adjust settings'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
