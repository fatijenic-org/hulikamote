import 'package:flutter/material.dart';

import '../../data/forensic_media.dart';
import '../../domain/forensic_models.dart';
import '../../domain/review_controller.dart';
import 'fx.dart';
import 'plate_draw_dialog.dart';

/// Under the plate box: "Read again" looks for the plate once more in the photos; "Draw plate" lets the reviewer
/// draw a box around it by hand when the system missed it. Either way the reviewer's own number wins.
class PlateTools extends StatelessWidget {
  const PlateTools({super.key, required this.controller, required this.media, required this.ticket, this.onSaved});

  final ReviewController controller;
  final ForensicMedia media;
  final ForensicTicket ticket;
  final VoidCallback? onSaved;

  Future<void> _reread(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Reading the plate again…'), duration: Duration(seconds: 2)));
    final result = await controller.rereadPlate(ticket);
    if (result == null) return; // the workspace shows the reason
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message), duration: const Duration(seconds: 5)));
  }

  @override
  Widget build(BuildContext context) {
    final busy = controller.busy;
    final canRead = ticket.hasUid && ticket.frameCount > 0 && !busy;
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: canRead ? () => _reread(context) : null,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Read again'),
        ),
      ),
      const SizedBox(width: Fx.s8),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: canRead
              ? () => showPlateDrawDialog(context, controller: controller, media: media, ticket: ticket, onSaved: onSaved)
              : null,
          icon: const Icon(Icons.crop_free, size: 18),
          label: const Text('Draw plate'),
        ),
      ),
    ]);
  }
}
