import 'package:flutter/material.dart';

import '../../data/forensic_media.dart';
import '../../domain/forensic_models.dart';
import '../../domain/review_controller.dart';
import 'fx.dart';

/// How the plate was read: the final answer, the competing reads with their votes, and
/// every crop the OCR looked at. Clicking a crop makes it the one plate feedback refers to.
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
        if (t.crops.isEmpty) {
          return EmptyState(
            icon: Icons.pin_outlined,
            title: 'No plate was found on this vehicle',
            message: t.plateRead
                ? 'The plate text came from the photos, not from a separate crop.'
                : 'The plate detector never located a plate, so there is nothing to read.',
          );
        }
        final chosen = c.chosenCrop(t);
        final shown = _all ? t.crops : t.crops.take(_initialCount).toList();
        return ListView(padding: const EdgeInsets.only(right: Fx.s4), children: [
          _summary(context, t),
          const SizedBox(height: Fx.s16),
          SectionLabel('${t.crops.length} plate crop${t.crops.length == 1 ? '' : 's'}',
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
        ]);
      },
    );
  }

  Widget _summary(BuildContext context, ForensicTicket t) {
    final candidates = t.candidates.take(5).toList();
    final top = candidates.isEmpty ? 1.0 : candidates.first.value;
    return FxCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('FINAL READ', style: Fx.label(context)),
            const SizedBox(height: Fx.s8),
            if (t.plateRead)
              Text(t.plateText, style: Fx.plate.copyWith(fontSize: 28))
            else
              Text('Could not be read', style: Fx.heading(context).copyWith(color: Fx.muted(context))),
            const SizedBox(height: Fx.s8),
            if (t.plateRaw != null) Text('Raw OCR output: ${t.plateRaw}', style: Fx.caption(context)),
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
        if (candidates.isNotEmpty)
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('COMPETING READS (VOTES)', style: Fx.label(context)),
              const SizedBox(height: Fx.s8),
              for (var i = 0; i < candidates.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    SizedBox(
                      width: 96,
                      child: Text(candidates[i].key,
                          overflow: TextOverflow.ellipsis,
                          style: Fx.plate.copyWith(fontSize: 12, color: i == 0 ? Fx.success : null)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (candidates[i].value / top).clamp(0.0, 1.0),
                          minHeight: 8,
                          color: i == 0 ? Fx.success : Fx.muted(context),
                          backgroundColor: Fx.raised(context),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(candidates[i].value.toStringAsFixed(1),
                          textAlign: TextAlign.right, style: Fx.caption(context)),
                    ),
                  ]),
                ),
            ]),
          ),
      ]),
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
          if (crop.t != null) Text('at ${formatVideoTime(crop.t)}', style: Fx.caption(context)),
        ]),
      ),
    );
  }

  Widget _img(BuildContext context, String file, String label) => Container(
        height: 58,
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
        child: FxImage(image: media.thumb(file, width: 400), fit: BoxFit.contain, radius: 6, errorLabel: label),
      );
}
