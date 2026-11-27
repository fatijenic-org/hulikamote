import 'package:flutter/material.dart';

import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/trim_session.dart';

/// The keys 1-9 switch these labels on the selected slices (shown on the chips); "C" switches "Clean".
const quickLabelKeys = [
  'counterflow', 'illegal_parking', 'restricted_lane', 'crossing_solid_line', 'illegal_loading', 'no_helmet', 'overloading', 'no_plate', 'passenger_outside',
];

/// The colour of a labelled slice on the timeline and in the list.
Color labelColor(Set<String> labels) {
  if (labels.isEmpty) return const Color(0xFF9AA4B2);
  final first = labels.first;
  if (first == cleanLabel) return const Color(0xFF3CCB8C);
  return ViolationCatalog.of(first).group.color;
}

/// The label list of the right sidebar. It shows while one or more slices are selected (click a slice on the timeline): search for a
/// label, or pick it from its category; a row is ticked when every selected slice has it, half-ticked when some do. Pressing the
/// number shown on a row does the same.
class LabelPanel extends StatefulWidget {
  const LabelPanel({super.key, required this.session, required this.onMessage});

  final TrimSession session;
  final void Function(String message) onMessage;

  @override
  State<LabelPanel> createState() => _LabelPanelState();
}

class _LabelPanelState extends State<LabelPanel> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String key) {
    if (widget.session.toggleLabel(key) == 0) widget.onMessage('Those slices are locked or already exported.');
  }

  /// "Clean for ...": a clean slice is judged only for the violations ticked here (none ticked = the common ones).
  Widget _cleanFor(BuildContext context) {
    final clean = [for (final c in widget.session.selectedClips) if (c.labels.contains(cleanLabel)) c];
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey('clean-for'),
        dense: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 6),
        title: Text('Clean for (optional)', style: Fx.label(context)),
        subtitle: Text(
          clean.every((c) => c.cleanFor.isEmpty) ? 'none picked: the common ones (helmet, overloading)' : '${{for (final c in clean) ...c.cleanFor}.length} picked',
          style: Fx.caption(context),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 6, runSpacing: 2, children: [
              for (final v in ViolationCatalog.selectable)
                FilterChip(
                  key: ValueKey('clean-for-${v.key}'),
                  visualDensity: VisualDensity.compact,
                  label: Text(v.label, style: const TextStyle(fontSize: 11)),
                  selected: clean.every((c) => c.cleanFor.contains(v.key)),
                  onSelected: (_) => widget.session.toggleCleanFor(v.key),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  bool _matches(String key, String text, String q) => q.isEmpty || text.toLowerCase().contains(q) || key.replaceAll('_', ' ').contains(q);

  Widget _row(BuildContext context, String key, String text, IconData icon, Color color, {String? shortcut}) {
    final chosen = widget.session.selectedClips;
    final have = chosen.where((c) => c.labels.contains(key)).length;
    final all = chosen.isNotEmpty && have == chosen.length;
    final some = have > 0 && !all;
    // one violation per slice: the mark is round, and picking a row replaces the old label
    return InkWell(
      key: ValueKey('label-$key'),
      borderRadius: BorderRadius.circular(Fx.radiusSm),
      onTap: () => _toggle(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(children: [
          Icon(all ? Icons.radio_button_checked : (some ? Icons.adjust : Icons.radio_button_unchecked), size: 20, color: all || some ? color : Fx.muted(context)),
          const SizedBox(width: 8),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, fontWeight: all ? FontWeight.w700 : FontWeight.w500), overflow: TextOverflow.ellipsis)),
          if (key != cleanLabel) Text('+${padOfLabel(key)} s  ', style: Fx.caption(context)),
          if (shortcut != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: Fx.border(context))),
              child: Text(shortcut, style: Fx.caption(context)),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.session, _search]),
      builder: (context, _) {
        final q = _search.text.trim().toLowerCase();
        final n = widget.session.selected.length;
        final quick = {for (final (i, k) in quickLabelKeys.indexed) k: '${i + 1}'};
        final children = <Widget>[];
        if (_matches(cleanLabel, 'clean nothing illegal', q)) {
          children.add(_row(context, cleanLabel, 'Clean (nothing illegal)', Icons.check_circle_outline, const Color(0xFF3CCB8C), shortcut: 'C'));
        }
        for (final group in ViolationGroup.values) {
          final items = [for (final v in ViolationCatalog.selectable) if (v.group == group && _matches(v.key, v.label, q)) v];
          if (items.isEmpty) continue;
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 2),
            child: Text(group.title.toUpperCase(), style: Fx.label(context).copyWith(color: group.color)),
          ));
          for (final v in items) {
            children.add(_row(context, v.key, v.label, v.icon, group.color, shortcut: quick[v.key]));
          }
        }
        if (children.isEmpty) {
          children.add(Padding(padding: const EdgeInsets.all(Fx.s12), child: Text('No label matches "${_search.text}".', style: Fx.caption(context))));
        }
        final one = widget.session.selectedClips.length == 1 ? widget.session.selectedClips.first : null;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Label ${n == 1 ? 'this slice' : '$n slices'}', style: Fx.label(context)),
          const SizedBox(height: 6),
          if (one != null) ...[
            Row(children: [
              Expanded(child: _PlateField(key: ValueKey('plate-${one.id}'), session: widget.session, clip: one)),
              const SizedBox(width: 8),
              _CountField(key: ValueKey('count-${one.id}'), session: widget.session, clip: one),
            ]),
            const SizedBox(height: 6),
          ],
          TextField(
            key: const ValueKey('label-search'),
            controller: _search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: 'Search a violation',
              suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close, size: 16), visualDensity: VisualDensity.compact, onPressed: _search.clear),
              border: const OutlineInputBorder(),
            ),
          ),
          if (widget.session.selectedClips.any((c) => c.labels.contains(cleanLabel))) _cleanFor(context),
          const SizedBox(height: 4),
          Expanded(child: ListView(children: children)),
        ]);
      },
    );
  }
}

/// The true plate of the vehicle of the selected slice. It is compared with what the system read (the plate scores LOAR, CER, WER).
/// Leave it empty when the plate cannot be read: the violation is still scored, only the plate scores skip it.
class _PlateField extends StatefulWidget {
  const _PlateField({super.key, required this.session, required this.clip});

  final TrimSession session;
  final TrimClip clip;

  @override
  State<_PlateField> createState() => _PlateFieldState();
}

class _PlateFieldState extends State<_PlateField> {
  late final _c = TextEditingController(text: widget.clip.plate);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.clip.locked || widget.clip.exported;
    return TextField(
      key: const ValueKey('plate-field'),
      controller: _c,
      enabled: !locked,
      textCapitalization: TextCapitalization.characters,
      onChanged: (text) => widget.session.setPlate(widget.clip.id, text),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.pin_outlined, size: 18),
        labelText: 'True plate (leave empty if unreadable)',
        helperText: locked ? 'Exported: the plate is saved with the clip.' : null,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// How many vehicles break the rule in the selected slice. A crowded stretch needs one number here: the benchmark then expects that many
/// tickets inside it (each ticket catches one event), so the other vehicles are not counted as false alarms.
class _CountField extends StatefulWidget {
  const _CountField({super.key, required this.session, required this.clip});

  final TrimSession session;
  final TrimClip clip;

  @override
  State<_CountField> createState() => _CountFieldState();
}

class _CountFieldState extends State<_CountField> {
  late final _c = TextEditingController(text: '${widget.clip.count}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.clip.locked || widget.clip.exported;
    return SizedBox(
      width: 96,
      child: TextField(
        key: const ValueKey('count-field'),
        controller: _c,
        enabled: !locked,
        keyboardType: TextInputType.number,
        onChanged: (text) {
          final n = int.tryParse(text.trim());
          if (n != null) widget.session.setCount(widget.clip.id, n);
        },
        decoration: const InputDecoration(isDense: true, labelText: 'Vehicles', border: OutlineInputBorder()),
      ),
    );
  }
}
