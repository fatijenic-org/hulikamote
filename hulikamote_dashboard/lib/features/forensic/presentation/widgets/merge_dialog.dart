import 'package:flutter/material.dart';

import '../../data/forensic_media.dart';
import '../../domain/forensic_models.dart';
import '../../domain/review_controller.dart';
import 'fx.dart';
import 'ticket_picker.dart';

/// "These are the same car": pick another ticket, then choose which of its photos join this
/// one (all of them = a plain merge and the other ticket disappears). Responsive; no fixed size.
Future<void> showMergeDialog(
  BuildContext context, {
  required ReviewController controller,
  required ForensicMedia media,
  required ForensicTicket ticket,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _MergeDialog(controller: controller, media: media, ticket: ticket),
  );
}

class _MergeDialog extends StatefulWidget {
  const _MergeDialog({required this.controller, required this.media, required this.ticket});

  final ReviewController controller;
  final ForensicMedia media;
  final ForensicTicket ticket;

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  ForensicTicket? _other;
  final Set<String> _picked = {};
  bool _working = false;

  void _choose(ForensicTicket t) => setState(() {
        _other = t;
        _picked
          ..clear()
          ..addAll(t.frames.map((f) => f.file));
      });

  Future<void> _apply() async {
    final other = _other;
    if (other == null || _picked.isEmpty) return;
    setState(() => _working = true);
    final c = widget.controller;
    final whole = _picked.length == other.frameCount;
    final ok = whole
        ? await c.ticketAction('merge', {'keep_uid': widget.ticket.uid, 'merge_uid': other.uid},
            thenSelect: widget.ticket.uid)
        : await c.ticketAction(
            'move-frames',
            {
              'keep_uid': widget.ticket.uid,
              'from_uid': other.uid,
              'frames': [for (final f in other.frames) if (_picked.contains(f.file)) f.file],
            },
            thenSelect: widget.ticket.uid);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final other = _other;
    return Dialog(
      insetPadding: const EdgeInsets.all(Fx.s24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 960, maxHeight: size.height * 0.86),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Fx.s24, Fx.s16, Fx.s8, Fx.s8),
            child: Row(children: [
              if (other != null)
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _working ? null : () => setState(() => _other = null),
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(other == null ? 'Merge with which ticket?' : 'Which photos are the same car?',
                      style: Fx.title(context)),
                  Text(
                    other == null
                        ? 'Pick the ticket that is the same vehicle as #${widget.ticket.trackId}.'
                        : 'Vehicle #${other.trackId}: tick the photos that show the same car as this ticket.',
                    style: Fx.caption(context),
                  ),
                ]),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: _working ? null : () => Navigator.of(context).pop()),
            ]),
          ),
          if (_working) const LinearProgressIndicator(minHeight: 2),
          Divider(height: 1, color: Fx.border(context)),
          Expanded(
            child: other == null
                ? TicketPicker(controller: widget.controller, media: widget.media, excludeUid: widget.ticket.uid, onPick: _choose)
                : _framePicker(context, other),
          ),
          if (other != null) _footer(context, other),
        ]),
      ),
    );
  }

  Widget _framePicker(BuildContext context, ForensicTicket other) {
    return GridView.builder(
      padding: const EdgeInsets.all(Fx.s16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 16 / 10,
        crossAxisSpacing: Fx.s8,
        mainAxisSpacing: Fx.s8,
      ),
      itemCount: other.frameCount,
      itemBuilder: (context, i) {
        final f = other.frames[i];
        final on = _picked.contains(f.file);
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => on ? _picked.remove(f.file) : _picked.add(f.file)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: on ? Fx.accent : Fx.border(context), width: on ? 2 : 1),
            ),
            child: Stack(fit: StackFit.expand, children: [
              FxImage(image: widget.media.thumb(f.file, width: 300), radius: 7, errorLabel: ''),
              Positioned(
                left: 4,
                top: 4,
                child: Icon(on ? Icons.check_box : Icons.check_box_outline_blank,
                    color: on ? Fx.accent : Colors.white70, size: 20),
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                  child: Text(f.timeLabel, style: const TextStyle(fontSize: 10, color: Colors.white)),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _footer(BuildContext context, ForensicTicket other) {
    final whole = _picked.length == other.frameCount;
    return Container(
      padding: const EdgeInsets.all(Fx.s16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Fx.border(context)))),
      child: Row(children: [
        TextButton(
          onPressed: _working ? null : () => setState(() => _picked.addAll(other.frames.map((f) => f.file))),
          child: const Text('Select all'),
        ),
        TextButton(onPressed: _working ? null : () => setState(_picked.clear), child: const Text('None')),
        const Spacer(),
        Text(
          whole ? 'The whole ticket will be merged in.' : '${_picked.length} of ${other.frameCount} photos will move here.',
          style: Fx.caption(context),
        ),
        const SizedBox(width: Fx.s16),
        FilledButton.icon(
          onPressed: (_picked.isEmpty || _working) ? null : _apply,
          icon: const Icon(Icons.merge_type, size: 18),
          label: Text(whole ? 'Merge whole ticket' : 'Move ${_picked.length} photos here'),
        ),
      ]),
    );
  }
}
