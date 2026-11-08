import 'package:flutter/material.dart';

import '../../data/forensic_media.dart';
import '../../domain/forensic_models.dart';
import '../../domain/review_controller.dart';
import 'fx.dart';

/// Search the other tickets of the analysis and pick one: a grid of each ticket's best photo, plate and photo count.
class TicketPicker extends StatefulWidget {
  const TicketPicker({
    super.key,
    required this.controller,
    required this.media,
    required this.excludeUid,
    required this.onPick,
  });

  final ReviewController controller;
  final ForensicMedia media;

  /// The ticket that is open (it cannot be picked as its own target).
  final String excludeUid;
  final ValueChanged<ForensicTicket> onPick;

  @override
  State<TicketPicker> createState() => _TicketPickerState();
}

class _TicketPickerState extends State<TicketPicker> {
  String _query = '';

  List<ForensicTicket> get _candidates {
    final q = _query.trim().toLowerCase();
    return [
      for (final t in widget.controller.all)
        if (t.uid != widget.excludeUid &&
            t.hasUid &&
            (q.isEmpty || '${t.plateText} ${t.trackId} ${t.vehicleClass ?? ''}'.toLowerCase().contains(q)))
          t,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final list = _candidates;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(Fx.s16),
        child: TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search by plate or vehicle ID',
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            filled: true,
            fillColor: Fx.raised(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Fx.radiusSm), borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(
        child: list.isEmpty
            ? const EmptyState(icon: Icons.search_off, title: 'No other tickets', message: 'Nothing matches that search.')
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(Fx.s16, 0, Fx.s16, Fx.s16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisExtent: 168,
                  crossAxisSpacing: Fx.s12,
                  mainAxisSpacing: Fx.s12,
                ),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final t = list[i];
                  return FxCard(
                    padding: const EdgeInsets.all(Fx.s8),
                    onTap: () => widget.onPick(t),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: SizedBox(
                          width: double.infinity,
                          child: t.hero == null
                              ? Container(color: Fx.raised(context))
                              : FxImage(image: widget.media.thumb(t.hero!.file, width: 400), radius: 6, errorLabel: ''),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(t.plateRead ? t.plateText : 'Plate unread',
                          style: t.plateRead ? Fx.plate.copyWith(fontSize: 14) : Fx.caption(context)),
                      Text('#${t.trackId} · ${t.frameCount} photos', style: Fx.caption(context)),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}

/// "Which ticket?": pick one of the other tickets. Returns it, or null when the window is closed.
Future<ForensicTicket?> showTicketPickerDialog(
  BuildContext context, {
  required ReviewController controller,
  required ForensicMedia media,
  required ForensicTicket? exclude, // null: every ticket can be picked (photos coming from Holding)
  required String title,
  required String subtitle,
}) {
  return showDialog<ForensicTicket>(
    context: context,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      return Dialog(
        insetPadding: const EdgeInsets.all(Fx.s24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 960, maxHeight: size.height * 0.86),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Fx.s24, Fx.s16, Fx.s8, Fx.s8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: Fx.title(ctx)),
                    Text(subtitle, style: Fx.caption(ctx)),
                  ]),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
              ]),
            ),
            Divider(height: 1, color: Fx.border(ctx)),
            Expanded(
              child: TicketPicker(
                controller: controller,
                media: media,
                excludeUid: exclude?.uid ?? '',
                onPick: (t) => Navigator.of(ctx).pop(t),
              ),
            ),
          ]),
        ),
      );
    },
  );
}
