import 'package:flutter/material.dart';

import '../../../../core/ui/page_parts.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/registry_api.dart';
import '../../domain/registry_models.dart';
import '../widgets/notice_card.dart';

/// The Motorists tab: who owns which plate and where to e-mail them. When a reviewer confirms a ticket, the
/// motorist registered for its plate gets the ticket in their app and an e-mail (if an address is on file).
class RegistryScreen extends StatefulWidget {
  const RegistryScreen({super.key, this.api});

  /// Injected by tests; the app uses the real backend.
  final RegistryApi? api;

  @override
  State<RegistryScreen> createState() => _RegistryScreenState();
}

class _RegistryScreenState extends State<RegistryScreen> {
  late final RegistryApi _api = widget.api ?? RegistryApi();

  final _noticeKey = GlobalKey();       // keeps the card (and what is typed in it) when the list reloads
  int _refresh = 0;
  List<Motorist>? _motorists;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _load() async {
    try {
      final motorists = await _api.motorists();
      if (mounted) {
        setState(() {
          _motorists = motorists;
          _error = null;
          _refresh++;
        });
      }
    } on RegistryApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Runs a change, says how it went, and shows what is saved now.
  Future<void> _change(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) _toast(done);
    } on RegistryApiException catch (e) {
      if (mounted) _toast(e.message);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final motorists = _motorists;
    return Scaffold(
      backgroundColor: Fx.page(context),
      body: Padding(
        padding: const EdgeInsets.all(Fx.s24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(
            title: 'Motorists',
            subtitle: 'Who owns which plate, and where to e-mail them when a ticket is confirmed.',
            actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load)],
          ),
          if (_error != null && motorists != null) ...[
            FxBanner(message: _error!, action: TextButton(onPressed: _load, child: const Text('Try again'))),
            const SizedBox(height: Fx.s16),
          ],
          Expanded(
            child: motorists == null
                ? (_error == null ? const SkeletonRows(count: 4, height: 96) : ErrorPanel(message: _error!, onRetry: _load))
                : motorists.isEmpty
                    ? const EmptyState(icon: Icons.people_outline, title: 'No motorists yet')
                    : ListView.separated(
                        itemCount: motorists.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: Fx.s12),
                        itemBuilder: (context, i) {
                          if (i == 0) return NoticeCard(key: _noticeKey, api: _api, onMessage: _toast, refresh: _refresh);
                          final m = motorists[i - 1];
                          return _MotoristCard(
                            key: ValueKey(m.id),
                            motorist: m,
                            onSaveEmail: (email) => _change(() => _api.setEmail(m.id, email), email.isEmpty ? 'E-mail removed.' : 'E-mail saved.'),
                            onAddPlate: (plate) => _change(() => _api.registerPlate(plate, m.id), 'Plate registered to ${m.name}.'),
                            onRemovePlate: (plate) => _change(() => _api.removePlate(plate), 'Plate $plate removed.'),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

class _MotoristCard extends StatefulWidget {
  const _MotoristCard({
    super.key,
    required this.motorist,
    required this.onSaveEmail,
    required this.onAddPlate,
    required this.onRemovePlate,
  });

  final Motorist motorist;
  final Future<void> Function(String email) onSaveEmail;
  final Future<void> Function(String plate) onAddPlate;
  final Future<void> Function(String plate) onRemovePlate;

  @override
  State<_MotoristCard> createState() => _MotoristCardState();
}

class _MotoristCardState extends State<_MotoristCard> {
  late final _email = TextEditingController(text: widget.motorist.email);
  final _plate = TextEditingController();

  @override
  void didUpdateWidget(_MotoristCard old) {
    super.didUpdateWidget(old);
    if (old.motorist.email != widget.motorist.email) _email.text = widget.motorist.email;     // saved or reloaded
  }

  @override
  void dispose() {
    _email.dispose();
    _plate.dispose();
    super.dispose();
  }

  bool get _emailChanged => _email.text.trim() != widget.motorist.email;

  void _addPlate() {
    final plate = _plate.text.trim();
    if (plate.isEmpty) return;
    _plate.clear();
    widget.onAddPlate(plate);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.motorist;
    return FxCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.person_outline, size: 20),
          const SizedBox(width: Fx.s8),
          Text(m.name, style: Fx.heading(context)),
          const SizedBox(width: Fx.s12),
          Text('Licence ${m.licenseNo}', style: Fx.caption(context)),
        ]),
        const SizedBox(height: Fx.s16),
        const SectionLabel('E-mail'),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _emailChanged ? widget.onSaveEmail(_email.text.trim()) : null,
              decoration: const InputDecoration(isDense: true, hintText: 'No e-mail: this motorist is not e-mailed', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: Fx.s8),
          FilledButton(
            onPressed: _emailChanged ? () => widget.onSaveEmail(_email.text.trim()) : null,
            child: const Text('Save'),
          ),
        ]),
        const SizedBox(height: Fx.s16),
        const SectionLabel('Plates'),
        Wrap(spacing: Fx.s8, runSpacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final plate in m.plates)
            InputChip(
              label: Text(plate, style: Fx.plate),
              onDeleted: () => widget.onRemovePlate(plate),
              deleteButtonTooltipMessage: 'Remove $plate',
            ),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => _addPlate(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Add a plate',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.add), tooltip: 'Add plate', onPressed: _addPlate),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
