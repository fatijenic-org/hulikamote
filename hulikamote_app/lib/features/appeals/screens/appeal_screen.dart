import 'package:flutter/material.dart';

import '../../../core/services/friendly_error.dart';
import '../../../core/services/portal_api.dart';
import '../../../core/services/session.dart';
import '../../../core/ui/app_theme.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets.dart';
import '../../home/models/violation.dart';
import '../../home/widgets/ticket_card.dart';

const _maxReason = 1000;

/// Reasons people most often have, one tap to start writing. They are only a start: the motorist edits the words.
const _quickReasons = [
  'I was not the one driving.',
  'The plate in the photo is not mine.',
  'I was not breaking the rule.',
  'The photos do not show my vehicle.',
];

/// Appeal one ticket. One appeal per ticket; afterwards the ticket page shows how it stands.
class AppealScreen extends StatefulWidget {
  const AppealScreen({super.key, required this.violation, this.api});

  final Violation violation;
  final PortalApi? api;

  @override
  State<AppealScreen> createState() => _AppealScreenState();
}

class _AppealScreenState extends State<AppealScreen> {
  PortalApi get _api => widget.api ?? PortalApi();

  final _reason = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  Violation get v => widget.violation;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _addQuick(String text) {
    final current = _reason.text.trim();
    _reason.text = current.isEmpty ? text : '$current $text';
    _reason.selection = TextSelection.collapsed(offset: _reason.text.length);
    setState(() => _error = null);
  }

  Future<void> _send() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Tell the reviewer why you think this ticket is wrong.');
      return;
    }
    final account = await Session.current();
    if (account == null) {
      setState(() => _error = 'Sign in again to send an appeal.');
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.fileAppeal(violationId: v.id, userId: account.userId, reason: reason);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_sent ? '' : 'Appeal this ticket'),
        automaticallyImplyLeading: !_sent,
      ),
      body: SafeArea(child: AnimatedSwitcher(duration: quick, child: _sent ? _done(context) : _form(context))),
    );
  }

  Widget _form(BuildContext context) {
    final count = _reason.text.length;
    return SingleChildScrollView(
      key: const ValueKey('form'),
      padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x2, Sp.page, Sp.x6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Sp.x3),
            child: Row(children: [
              TicketThumb(v, size: 48),
              const SizedBox(width: Sp.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.displayClass, style: context.text.titleMedium),
                  Text(dateTimeOf(v.time, v.timestamp), style: context.text.bodyMedium?.copyWith(color: context.muted)),
                  Text('Case ${v.caseNo}', style: context.text.bodyMedium?.copyWith(color: context.muted)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: Sp.x6),
        Text('Why do you think it is wrong?', style: context.text.titleMedium),
        const SizedBox(height: Sp.x2),
        Wrap(spacing: Sp.x2, children: [
          for (final text in _quickReasons) ActionChip(label: Text(text), onPressed: _busy ? null : () => _addQuick(text)),
        ]),
        const SizedBox(height: Sp.x4),
        AppField(
          controller: _reason,
          label: 'Your reason',
          helper: 'A reviewer reads this. Say what happened, in your own words.',
          minLines: 5,
          maxLines: 8,
          maxLength: _maxReason,
          keyboard: TextInputType.multiline,
          capitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() => _error = null),
          enabled: !_busy,
        ),
        Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(top: Sp.x1), child: Text('$count / $_maxReason', style: context.text.bodyMedium?.copyWith(color: context.muted)))),
        if (_error != null) ...[
          const SizedBox(height: Sp.x3),
          InfoBanner(message: _error!, tone: Tone.danger),
        ],
        const SizedBox(height: Sp.x4),
        const InfoBanner(message: 'You can appeal a ticket once. Do not send a false appeal.', icon: Icons.info_outline),
        const SizedBox(height: Sp.x6),
        AppButton(label: 'Send appeal', icon: Icons.send_rounded, onPressed: _send, loading: _busy),
      ]),
    );
  }

  Widget _done(BuildContext context) {
    return Center(
      key: const ValueKey('done'),
      child: Padding(
        padding: const EdgeInsets.all(Sp.x8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 420),
            curve: Curves.elasticOut,
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: context.status.success, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, size: 48, color: context.status.onSuccess),
            ),
          ),
          const SizedBox(height: Sp.x6),
          Semantics(header: true, liveRegion: true, child: Text('Appeal sent', style: context.text.headlineSmall)),
          const SizedBox(height: Sp.x2),
          Text(
            'A reviewer will look at it. You will see the result on this ticket.',
            style: context.text.bodyLarge?.copyWith(color: context.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Sp.x8),
          AppButton(label: 'Back to the ticket', onPressed: () => Navigator.of(context).pop(true)),
        ]),
      ),
    );
  }
}
