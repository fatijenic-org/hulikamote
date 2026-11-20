import 'package:flutter/material.dart';

import '../../data/forensic_media.dart';
import '../../domain/forensic_models.dart';
import '../../domain/review_controller.dart';
import 'fx.dart';

/// How the plate was read: the plate of the ticket in a text field of its own (it starts with the best candidate; pick another
/// candidate or type), every candidate with its grade, and every crop the OCR looked at with its two readings (as seen / enhanced by
/// the GAN). Clicking a crop makes it the one plate feedback refers to.
class PlateReadsPanel extends StatefulWidget {
  const PlateReadsPanel({super.key, required this.controller, required this.media});

  final ReviewController controller;
  final ForensicMedia media;

  @override
  State<PlateReadsPanel> createState() => _PlateReadsPanelState();
}

class _PlateReadsPanelState extends State<PlateReadsPanel> {
  static const int _initialCount = 12;
  bool _all = false;
  final _field = TextEditingController();
  String? _filledFor;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  /// The field follows the open ticket: its plate, or the best candidate when the plate is not set. What is typed stays until the
  /// ticket (or its plate) changes.
  void _fill(ForensicTicket t) {
    final key = '${t.uid}|${t.plateText}|${t.plateManual}|${t.plateCandidates.length}|${t.crops.length}';
    if (_filledFor == key) return;
    _filledFor = key;
    final best = _candidates(t);
    final text = t.plateRead ? t.plateText : (best.isNotEmpty ? best.first.text : '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _field.text = text;
    });
  }

  /// The graded candidates of the backend, or (an older report) the vote tally as candidates.
  List<PlateCandidate> _candidates(ForensicTicket t) {
    if (t.plateCandidates.isNotEmpty) return t.plateCandidates;
    return [for (final e in t.candidates) PlateCandidate(text: e.key, points: e.value, tier: e.value >= 22 ? 'fair' : 'weak')];
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final t = c.selected;
        if (t == null) {
          return const EmptyState(icon: Icons.touch_app_outlined, title: 'Pick a ticket');
        }
        _fill(t);
        final chosen = c.chosenCrop(t);
        final shown = _all ? t.crops : t.crops.take(_initialCount).toList();
        return ListView(padding: const EdgeInsets.only(right: Fx.s4), children: [
          _plateCard(context, c, t),
          const SizedBox(height: Fx.s16),
          if (t.crops.isEmpty)
            _nothingYet(context, t)
          else ...[
            SectionLabel('${t.crops.length} plate crop${t.crops.length == 1 ? '' : 's'}, each read as seen and enhanced',
                trailing: Text('Click a crop to use it for plate feedback', style: Fx.caption(context))),
            Wrap(spacing: Fx.s12, runSpacing: Fx.s12, children: [
              for (final crop in shown)
                _CropCard(
                  crop: crop,
                  media: widget.media,
                  winner: crop.file == (t.bestCrop?.file),
                  chosen: crop.file == chosen?.file,
                  onTap: () => c.chooseCrop(t.uid, crop.file),
                ),
            ]),
            if (!_all && t.crops.length > _initialCount)
              Padding(
                padding: const EdgeInsets.only(top: Fx.s12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _all = true),
                    child: Text('Show all ${t.crops.length} crops'),
                  ),
                ),
              ),
          ],
        ]);
      },
    );
  }

  Widget _nothingYet(BuildContext context, ForensicTicket t) {
    final pending = t.plateStatus == 'pending';
    final reading = widget.controller.isReading(t.uid);
    return FxCard(
      child: Row(children: [
        reading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(pending ? Icons.hourglass_empty : Icons.pin_outlined, color: Fx.muted(context)),
        const SizedBox(width: Fx.s12),
        Expanded(
          child: Text(
            reading
                ? 'Reading the plate of this ticket: it is found in the photos and read twice, as seen and enhanced. It shows here when it is done.'
                : pending
                ? 'The plate of this ticket has not been read yet. "Read the plate" finds it in the photos of the ticket and reads it twice: as seen and enhanced.'
                : t.plateRead
                    ? 'The plate text came from the photos, not from a separate crop.'
                    : 'No plate crop was found in the photos read so far.',
            style: Fx.body(context),
          ),
        ),
      ]),
    );
  }

  /// "Read the plate": the photos of the ticket are searched for the plate and every crop is read as seen and enhanced.
  Future<void> _read(ForensicTicket t) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await widget.controller.rereadPlate(t, all: true);       // every photo that is in the ticket now
    if (r == null || !mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(r.found == 0
          ? 'Looked at ${r.checked} photo${r.checked == 1 ? '' : 's'}: no plate found in them.'
          : 'Looked at ${r.checked} photo${r.checked == 1 ? '' : 's'}: a plate was found in ${r.found}. Best candidate: ${r.suggested.isEmpty ? 'none' : r.suggested}${r.keptManual ? ' (your typed plate stays)' : ''}.'),
    ));
  }

  Widget _plateCard(BuildContext context, ReviewController c, ForensicTicket t) {
    final candidates = _candidates(t).take(6).toList();
    final busy = c.busy;
    final canMarkNoPlate = !t.plateRead || t.violations.contains('no_plate') && t.raw['no_plate_by_verdict'] == true;
    final verdict = t.raw['no_plate_by_verdict'] == true;
    return FxCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.plateRead ? (t.plateManual ? 'PLATE (TYPED BY A REVIEWER)' : 'PLATE (BEST CANDIDATE)') : 'PLATE', style: Fx.label(context)),
            const SizedBox(height: Fx.s8),
            TextField(
              key: const ValueKey('plate-reads-field'),
              controller: _field,
              textCapitalization: TextCapitalization.characters,
              style: Fx.plate.copyWith(fontSize: 24, letterSpacing: 2),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: t.plateRead ? 'Type the plate' : t.unreadPlateLabel,
              ),
            ),
            const SizedBox(height: Fx.s8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _field,
              builder: (context, value, _) {
                final typed = value.text.trim().toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
                final current = t.plateRead ? t.plateText.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '') : '';
                return Wrap(spacing: Fx.s8, runSpacing: Fx.s8, children: [
                  FilledButton.icon(
                    key: const ValueKey('plate-reads-save'),
                    onPressed: (busy || typed.isEmpty || typed == current) ? null : () => c.setPlate(t, typed),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Save this plate'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('plate-reads-read'),
                    onPressed: busy ? null : () => _read(t),
                    icon: busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.document_scanner_outlined, size: 18),
                    label: Text(t.crops.isEmpty ? 'Read the plate' : 'Read again'),
                  ),
                  if (canMarkNoPlate)
                    OutlinedButton.icon(
                      key: const ValueKey('plate-reads-no-plate'),
                      onPressed: busy
                          ? null
                          : () => c.ticketAction('no-plate', {'ticket_uid': t.uid, 'on': !verdict}, thenSelect: t.uid),
                      icon: Icon(verdict ? Icons.undo : Icons.block, size: 18),
                      label: Text(verdict ? 'Take back "no plate"' : 'The vehicle has no plate'),
                    ),
                ]);
              },
            ),
            if (verdict) ...[
              const SizedBox(height: Fx.s8),
              const StatusPill(label: 'Verdict: no plate number → violation "no plate"', color: Fx.warning, icon: Icons.block, dense: true),
            ],
            if (t.plateRaw != null && t.plateRead) ...[
              const SizedBox(height: Fx.s8),
              Text('Raw OCR output: ${t.plateRaw}', style: Fx.caption(context)),
            ],
            if (t.plateLengthWarning) ...[
              const SizedBox(height: Fx.s8),
              const StatusPill(
                label: 'Length unusual for a PH plate',
                color: Fx.warning,
                icon: Icons.warning_amber_rounded,
                dense: true,
              ),
            ],
          ]),
        ),
        const SizedBox(width: Fx.s16),
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CANDIDATES · TAP ONE TO USE IT', style: Fx.label(context)),
            const SizedBox(height: Fx.s8),
            if (candidates.isEmpty)
              Text('Nothing has been read yet.', style: Fx.caption(context))
            else
              for (var i = 0; i < candidates.length; i++) _candidateRow(context, candidates[i], best: i == 0),
          ]),
        ),
      ]),
    );
  }

  Widget _candidateRow(BuildContext context, PlateCandidate cand, {required bool best}) {
    final color = switch (cand.tier) {
      'strong' => Fx.success,
      'fair' => Fx.warning,
      _ => Fx.muted(context),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(Fx.radiusSm),
      onTap: () => _field.text = cand.text,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(children: [
          SizedBox(
            width: 104,
            child: Text(cand.text, overflow: TextOverflow.ellipsis, style: Fx.plate.copyWith(fontSize: 14, color: best ? Fx.success : null)),
          ),
          StatusPill(label: cand.tier, color: color, dense: true),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${cand.points.toStringAsFixed(1)} pts · ${cand.votes} read${cand.votes == 1 ? '' : 's'}'
              '${cand.sources.isEmpty ? '' : ' · ${cand.sources.map((s) => s == 'raw' ? 'as seen' : 'enhanced').join(' + ')}'}',
              style: Fx.caption(context),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (best) const Icon(Icons.emoji_events_outlined, size: 16, color: Fx.success),
        ]),
      ),
    );
  }
}

class _CropCard extends StatelessWidget {
  const _CropCard({
    required this.crop,
    required this.media,
    required this.winner,
    required this.chosen,
    required this.onTap,
  });

  final PlateCrop crop;
  final ForensicMedia media;
  final bool winner;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 216,
      child: FxCard(
        selected: chosen,
        padding: const EdgeInsets.all(Fx.s8),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (winner) const StatusPill(label: 'Winner', color: Fx.success, icon: Icons.emoji_events_outlined, dense: true),
            const Spacer(),
            if (chosen) const Icon(Icons.radio_button_checked, size: 16, color: Fx.accent),
          ]),
          const SizedBox(height: 6),
          _img(context, crop.file, 'Crop'),
          if (crop.enhanced != null) ...[
            const SizedBox(height: 4),
            _img(context, crop.enhanced!, 'Enhanced'),
          ],
          const SizedBox(height: 6),
          if (crop.reads.isNotEmpty)
            for (final r in crop.reads) _readRow(context, r)
          else ...[
            Row(children: [
              Expanded(
                child: Text(crop.hasRead ? crop.cleaned : '—',
                    overflow: TextOverflow.ellipsis, style: Fx.plate.copyWith(fontSize: 14)),
              ),
              if (crop.confidence != null)
                Text('${(crop.confidence! * 100).round()}%', style: Fx.caption(context)),
            ]),
            if (crop.raw.isNotEmpty && crop.raw != crop.cleaned)
              Text('raw: ${crop.raw}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Fx.caption(context)),
          ],
          if (crop.t != null) Text('at ${formatVideoTime(crop.t)}', style: Fx.caption(context)),
        ]),
      ),
    );
  }

  Widget _readRow(BuildContext context, PlateRead r) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(children: [
          SizedBox(width: 62, child: Text(r.sourceLabel, style: Fx.caption(context))),
          Expanded(
            child: Text(r.hasRead ? r.cleaned : '—', overflow: TextOverflow.ellipsis, style: Fx.plate.copyWith(fontSize: 13)),
          ),
          if (r.confidence != null) Text('${(r.confidence! * 100).round()}%', style: Fx.caption(context)),
        ]),
      );

  Widget _img(BuildContext context, String file, String label) => Container(
        height: 58,
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
        child: FxImage(image: media.thumb(file, width: 400), fit: BoxFit.contain, radius: 6, errorLabel: label),
      );
}
