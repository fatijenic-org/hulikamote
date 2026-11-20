import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/forensic_api.dart';
import '../../domain/analysis_draft.dart';
import '../../domain/violation_catalog.dart';
import 'ban_hours_editor.dart';
import 'fx.dart';
import 'video_time_card.dart';

/// The numbers and choices of one violation that are not drawn: time limits, which vehicle
/// types are allowed or banned, the rider limit, how the red light is known.
/// Edits go straight into [draft]'s config map for that violation.
class ViolationParams extends StatelessWidget {
  const ViolationParams({super.key, required this.draft, required this.violationKey, required this.onChanged, this.api});

  final AnalysisDraft draft;
  final String violationKey;
  final VoidCallback onChanged;

  /// Lets the truck ban's time card read the time of the video (without it the card shows only in the Live Monitor).
  final ForensicApi? api;

  Map<String, dynamic> get cfg => draft.config(violationKey);

  void _set(String k, Object? v) {
    cfg[k] = v;
    draft.touch();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (violationKey == 'illegal_parking')
        _slider(context, 'How long may a vehicle stop here?', 'time_limit', 3, 300, suffix: 'seconds'),
      if (violationKey == 'pedestrian_lane')
        _slider(context, 'How long may a vehicle stop on the crosswalk?', 'time_limit', 1, 60, suffix: 'seconds'),
      if (violationKey == 'blocking_intersection')
        _slider(context, 'How long may a vehicle stand in the junction box?', 'time_limit', 1, 60, suffix: 'seconds'),
      if (violationKey == 'illegal_loading') ...[
        _slider(context, 'How long may a vehicle stop here?', 'time_limit', 3, 120, suffix: 'seconds'),
        _chips(context, 'Vehicle types that may NOT load or unload here', 'banned_classes'),
      ],
      if (violationKey == 'illegal_turn' && draft.roadHint('illegal_turn') != null)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.alt_route, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(draft.roadHint('illegal_turn')!, key: const ValueKey('turn-road-hint'), style: Fx.caption(context))),
        ]),
      if (violationKey == 'illegal_turn')
        _chips(context, 'Turns that are NOT allowed. Used for the whole picture and for the roads marked in the Road step. Both off: this check does not apply.', 'banned_turns',
            options: const ['left', 'right']),
      if (violationKey == 'double_parking')
        _slider(context, 'How long may a vehicle stand in the lane?', 'time_limit', 3, 120, suffix: 'seconds'),
      if (violationKey == 'sidewalk_driving')   // the truck ban bans trucks and the tricycle rule tricycles only: nothing to pick
        _chips(context, 'Vehicle types NOT allowed here', 'banned_classes'),
      // The truck ban only holds at certain hours in most cities (Zamboanga's are in its ordinance). With hours it needs the time
      // of the video, which is read from the video by itself and shown right under them: the one place the time is dealt with.
      if (violationKey == 'truck_ban')
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BanHoursEditor(draft: draft, violationKey: violationKey, onChanged: onChanged),
          if (((cfg['ban_windows'] as List?) ?? const []).isNotEmpty) VideoTimeCard(draft: draft, api: api),
        ]),
      if (violationKey == 'disregarding_signs') ...[
        _slider(context, 'No-stopping limit (for “No stopping” zones)', 'time_limit', 1, 60, suffix: 'seconds'),
        _chips(context, 'Vehicle types banned (for “Vehicle type banned” zones)', 'banned_classes'),
      ],
      if (violationKey == 'restricted_lane')
        _chips(context, 'Vehicle types that ARE allowed in this lane (where no sign says otherwise)', 'allowed_classes'),
      if (violationKey == 'overloading')
        _slider(context, 'Most people allowed on one motorcycle', 'max_riders', 1, 4, suffix: 'people', integer: true),
      if (violationKey == 'crossing_solid_line') _lineOverlap(context),
      if (violationKey == 'red_light') _redLight(context),
      if (violationKey == 'counterflow') ...[
        _switch(
          context,
          'Show the traffic-flow arrows',
          'Draws the flow the system learned (automatic mode) on the saved photos and the result video. '
              'Turn it off for a cleaner picture.',
          'show_flow',
          onByDefault: true,
        ),
        _switch(
          context,
          'Test: treat the opposite direction as legal',
          'Flips the flow (learned or drawn), so ordinary traffic gets flagged. Use it to check that counterflow '
              'works on a clip with no wrong-way vehicle. Photos and video are marked TEST: never confirm or send those tickets.',
          'invert_flow',
        ),
      ],
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final c in children) Padding(padding: const EdgeInsets.only(bottom: Fx.s16), child: c),
    ]);
  }

  Widget _switch(BuildContext context, String title, String caption, String key, {bool onByDefault = false}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Fx.body(context)),
          const SizedBox(height: 2),
          Text(caption, style: Fx.caption(context)),
        ]),
      ),
      const SizedBox(width: Fx.s12),
      Switch(value: (cfg[key] as bool?) ?? onByDefault, onChanged: (v) => _set(key, v)),
    ]);
  }

  Widget _slider(BuildContext context, String title, String key, double min, double max,
      {required String suffix, bool integer = false}) {
    final value = (cfg[key] as num).toDouble().clamp(min, max);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: Fx.body(context))),
        Text('${value.toInt()} $suffix', style: Fx.heading(context)),
      ]),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: (max - min).toInt(),
        label: '${value.toInt()}',
        onChanged: (v) => _set(key, integer ? v.round() : v),
      ),
    ]);
  }

  /// Crossing a solid line: how much of the vehicle must be past the line before it is flagged. It is measured on the part that touches the
  /// road (the bottom edge of the box, from the lower left to the lower right corner; a motorcycle: the middle of it), like an IoU with the far side.
  Widget _lineOverlap(BuildContext context) {
    final value = (((cfg['min_overlap'] as num?) ?? 0.3).toDouble() * 100).clamp(5.0, 100.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('How much of the vehicle must be over the line?', style: Fx.body(context))),
        Text('${value.round()} %', style: Fx.heading(context)),
      ]),
      Slider(
        key: const ValueKey('solid-line-overlap'),
        value: value,
        min: 5,
        max: 100,
        divisions: 19,
        label: '${value.round()} %',
        onChanged: (v) => _set('min_overlap', v.round() / 100),
      ),
      Text(
        'Counted on the part of the vehicle that touches the road: its bottom edge, lower corner to lower corner (a motorcycle: the middle of it). '
        'Lower flags a vehicle sooner, higher only when most of it is across.',
        style: Fx.caption(context),
      ),
    ]);
  }

  Widget _chips(BuildContext context, String title, String key, {List<String>? options}) {
    final selected = (cfg[key] as List).cast<String>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Fx.body(context)),
      const SizedBox(height: Fx.s8),
      Wrap(spacing: Fx.s8, runSpacing: Fx.s8, children: [
        for (final type in options ?? ViolationCatalog.vehicleTypes)
          FilterChip(
            label: Text('${type[0].toUpperCase()}${type.substring(1)}'),
            selected: selected.contains(type),
            visualDensity: VisualDensity.compact,
            onSelected: (on) {
              final next = [...selected];
              on ? next.add(type) : next.remove(type);
              _set(key, next);
            },
          ),
      ]),
    ]);
  }

  Widget _redLight(BuildContext context) {
    final virtual = cfg['light_mode'] == 'timer';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('How do we know the light is red?', style: Fx.body(context)),
      const SizedBox(height: Fx.s8),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'timer', icon: Icon(Icons.timer_outlined, size: 18), label: Text('Virtual light')),
          ButtonSegment(value: 'camera', icon: Icon(Icons.traffic, size: 18), label: Text('Read the real light')),
        ],
        selected: {cfg['light_mode'] as String},
        onSelectionChanged: (s) => _set('light_mode', s.first),
      ),
      const SizedBox(height: Fx.s8),
      if (virtual) ...[
        Text(
          'A simulated light is drawn on every frame of the result video. Set when it first turns red '
          '(seconds into the video) and how long each colour lasts. The cycle repeats red, green, yellow.',
          style: Fx.caption(context),
        ),
        const SizedBox(height: Fx.s12),
        Wrap(spacing: Fx.s12, runSpacing: Fx.s12, children: [
          for (final (k, label) in const [
            ('red_start', 'Red starts at (s)'),
            ('red', 'Red lasts (s)'),
            ('green', 'Green lasts (s)'),
            ('yellow', 'Yellow lasts (s)'),
          ])
            SizedBox(
              width: 132,
              child: TextFormField(
                key: ValueKey('$violationKey-$k'),
                initialValue: '${cfg[k]}',
                decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                onChanged: (v) {
                  final n = double.tryParse(v);
                  if (n != null) _set(k, n);
                },
              ),
            ),
        ]),
      ] else
        Text('Each zone also needs a box drawn tightly around the traffic light.', style: Fx.caption(context)),
    ]);
  }
}
