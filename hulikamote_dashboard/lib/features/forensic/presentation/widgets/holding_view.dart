import 'package:flutter/material.dart';

import '../../data/forensic_media.dart';
import '../../domain/forensic_models.dart';
import '../../domain/holding_models.dart';
import '../../domain/review_controller.dart';
import '../../domain/violation_catalog.dart';
import 'fx.dart';
import 'ticket_picker.dart';

/// Holding: photos that were set aside from a ticket because the tracker followed another car for a while. One card per
/// set of photos, with what can be done: make a new ticket of them, add them to another ticket (a plate read there names
/// them), put them back where they came from, or throw them away. Nothing here is sent to a motorist.
class HoldingView extends StatelessWidget {
  const HoldingView({
    super.key,
    required this.controller,
    required this.media,
    this.onShowTicket,
    this.onMessage,
  });

  final ReviewController controller;
  final ForensicMedia media;

  /// After photos became part of a ticket: go back to the review, where that ticket is open.
  final VoidCallback? onShowTicket;
  final ValueChanged<String>? onMessage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final batches = controller.holding;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Fx.s16, Fx.s16, Fx.s16, Fx.s8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Holding', style: Fx.title(context)),
              const SizedBox(height: 2),
              Text(
                'Photos you set aside because the tracker followed another car. Decide what each set is: nothing here is sent to a motorist.',
                style: Fx.caption(context),
              ),
            ]),
          ),
          Expanded(
            child: batches.isEmpty
                ? const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Nothing is set aside',
                    message: 'Tick photos in a ticket and press "Set aside for later". They wait here until you decide.',
                  )
                : ListView.separated(
                    key: const Key('holding-list'),
                    padding: const EdgeInsets.fromLTRB(Fx.s16, Fx.s8, Fx.s16, Fx.s24),
                    itemCount: batches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Fx.s12),
                    itemBuilder: (context, i) => _BatchCard(
                      batch: batches[i],
                      controller: controller,
                      media: media,
                      onShowTicket: onShowTicket,
                      onMessage: onMessage,
                    ),
                  ),
          ),
        ]);
      },
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({
    required this.batch,
    required this.controller,
    required this.media,
    this.onShowTicket,
    this.onMessage,
  });

  final HoldingBatch batch;
  final ReviewController controller;
  final ForensicMedia media;
  final VoidCallback? onShowTicket;
  final ValueChanged<String>? onMessage;

  static const _shown = 6;

  ReviewController get c => controller;

  Future<void> _makeTicket() async {
    if (!await c.holdingAction('make-ticket', batch)) return;
    onMessage?.call('Made a new ticket from ${batch.frameCount} photo${batch.frameCount == 1 ? '' : 's'}.');
    onShowTicket?.call();
  }

  Future<void> _addToTicket(BuildContext context) async {
    final other = await showTicketPickerDialog(
      context,
      controller: c,
      media: media,
      exclude: null,
      title: 'Add these photos to which ticket?',
      subtitle: 'They show the same car as the ticket you pick. If a plate was read there, it names them too.',
    );
    if (other == null) return;
    if (!await c.holdingAction('add-to-ticket', batch, into: other)) return;
    onMessage?.call('Added ${batch.frameCount} photo${batch.frameCount == 1 ? '' : 's'} to vehicle #${other.trackId}.');
    onShowTicket?.call();
  }

  Future<void> _putBack() async {
    if (!await c.holdingAction('put-back', batch)) return;
    onMessage?.call('Put the photos back into vehicle #${batch.fromTrack}.');
    onShowTicket?.call();
  }

  Future<void> _throwAway(BuildContext context) async {
    final n = batch.frameCount;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Throw away $n photo${n == 1 ? '' : 's'}?'),
        content: const Text('They are not evidence of anything and leave Holding. The picture files stay on disk until the run is cleaned.'),
        actions: [
          TextButton(key: const Key('throw-keep'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep them')),
          FilledButton(
            key: const Key('throw-confirm'),
            style: FilledButton.styleFrom(backgroundColor: Fx.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Throw away'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    if (await c.holdingAction('throw-away', batch)) onMessage?.call('Threw the photos away.');
  }

  @override
  Widget build(BuildContext context) {
    final t = batch.ticket;
    final files = [for (final f in t.frames) f.file];
    final span = t.span;
    final busy = c.busy;
    final canPutBack = c.all.any((x) => x.uid == batch.fromUid);
    return FxCard(
      key: Key('batch-${batch.id}'),
      padding: const EdgeInsets.all(Fx.s12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 72,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final f in files.take(_shown))
              Padding(
                padding: const EdgeInsets.only(right: Fx.s8),
                child: SizedBox(width: 110, child: FxImage(image: media.thumb(f, width: 260), radius: 6, errorLabel: '')),
              ),
            if (files.length > _shown)
              Padding(
                padding: const EdgeInsets.only(left: Fx.s4),
                child: Center(child: Text('+${files.length - _shown} more', style: Fx.caption(context))),
              ),
          ]),
        ),
        const SizedBox(height: Fx.s12),
        Wrap(spacing: Fx.s12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${t.frameCount} photo${t.frameCount == 1 ? '' : 's'} from vehicle #${batch.fromTrack}', style: Fx.heading(context)),
          if (span != null) Text('at ${formatVideoTime(span.start)}', style: Fx.caption(context)),
          t.plateRead
              ? Text(t.plateText, key: Key('batch-plate-${batch.id}'), style: Fx.plate.copyWith(fontSize: 14))
              : Text('No plate read', key: Key('batch-plate-${batch.id}'), style: Fx.caption(context)),
          for (final v in t.violations.take(2)) StatusPill(label: ViolationCatalog.of(v).label, color: Fx.muted(context), dense: true),
        ]),
        const SizedBox(height: Fx.s12),
        Wrap(spacing: Fx.s8, runSpacing: Fx.s8, children: [
          FilledButton.icon(
            key: Key('batch-new-${batch.id}'),
            onPressed: busy ? null : _makeTicket,
            icon: const Icon(Icons.call_split, size: 16),
            label: const Text('Make a new ticket'),
          ),
          OutlinedButton.icon(
            key: Key('batch-add-${batch.id}'),
            onPressed: busy ? null : () => _addToTicket(context),
            icon: const Icon(Icons.merge_type, size: 16),
            label: const Text('Add to a ticket…'),
          ),
          Tooltip(
            message: canPutBack ? 'It was a mistake: they go back into the ticket they came from' : 'That ticket is gone: add them to another ticket instead',
            child: TextButton.icon(
              key: Key('batch-back-${batch.id}'),
              onPressed: busy || !canPutBack ? null : _putBack,
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Put back'),
            ),
          ),
          TextButton.icon(
            key: Key('batch-drop-${batch.id}'),
            onPressed: busy ? null : () => _throwAway(context),
            icon: const Icon(Icons.delete_outline, size: 16, color: Fx.danger),
            label: const Text('Throw away', style: TextStyle(color: Fx.danger)),
          ),
        ]),
      ]),
    );
  }
}
