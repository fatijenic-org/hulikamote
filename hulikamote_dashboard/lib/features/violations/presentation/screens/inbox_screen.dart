import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/constants/api_constants.dart';
import '../../../../core/ui/page_parts.dart';
import '../../../../core/utils/app_toast.dart';
import '../../../forensic/presentation/widgets/fx.dart';

/// The three places a ticket can come from, in the order the tabs are shown.
const _sources = [
  ('forensic', 'Forensic', Icons.biotech_outlined),
  ('live', 'Live stream', Icons.videocam_outlined),
  ('video_analysis', 'Video analysis', Icons.video_library_outlined),
];

String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, this.client, this.baseUrl = ApiConstants.baseUrl});

  /// Injected by tests; the app uses the real backend.
  final http.Client? client;
  final String baseUrl;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with AutomaticKeepAliveClientMixin {
  late final http.Client _client = widget.client ?? http.Client();
  Map<String, Map<String, List<dynamic>>> _sessions = {for (final s in _sources) s.$1: {}};
  bool _isLoading = true;
  String? _error;
  String _source = _sources.first.$1;
  bool _picked = false; // the officer chose a tab: stop moving it on their own

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  Future<void> _fetchSessions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await _client.get(Uri.parse('${widget.baseUrl}/violations/sessions')).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw 'HTTP ${response.statusCode}';
      final data = jsonDecode(response.body) as Map;
      final sessions = {
        for (final s in _sources) s.$1: Map<String, List<dynamic>>.from((data[s.$1] as Map?) ?? const {}),
      };
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        // Open on the first tab that has something to do, unless the officer already chose one.
        if (!_picked) _source = _sources.firstWhere((s) => sessions[s.$1]!.isNotEmpty, orElse: () => _sources.first).$1;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'The backend did not answer. Start it with tools\\run_demo_backend.bat, then try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _count(String source) => _sessions[source]!.values.fold<int>(0, (sum, t) => sum + t.length);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final total = _sources.fold<int>(0, (sum, s) => sum + _count(s.$1));
    return Scaffold(
      backgroundColor: Fx.page(context),
      body: Padding(
        padding: const EdgeInsets.all(Fx.s24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(
            title: 'Inbox',
            subtitle: 'Tickets waiting for a decision. Open a batch, check the photos, then confirm or reject each ticket.',
            actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _isLoading ? null : _fetchSessions)],
          ),
          Row(children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(selectedBackgroundColor: Fx.accent.withValues(alpha: 0.22), selectedForegroundColor: Fx.accent),
              segments: [for (final s in _sources) ButtonSegment(value: s.$1, icon: Icon(s.$3, size: 18), label: Text('${s.$2} · ${_count(s.$1)}'))],
              selected: {_source},
              onSelectionChanged: (v) => setState(() {
                _source = v.first;
                _picked = true;
              }),
            ),
            const Spacer(),
            if (!_isLoading && _error == null) Text(total == 0 ? 'Nothing waiting' : '$total waiting', style: Fx.caption(context)),
          ]),
          const SizedBox(height: Fx.s16),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_isLoading && _sessions.values.every((m) => m.isEmpty)) return const SkeletonRows(count: 4);
    if (_error != null) return ErrorPanel(message: _error!, onRetry: _fetchSessions);
    final batches = _sessions[_source]!;
    if (batches.isEmpty) {
      return EmptyState(
        icon: Icons.done_all,
        title: 'All caught up',
        message: _sources.every((s) => _count(s.$1) == 0)
            ? 'No ticket is waiting. Analyse a video and its tickets will arrive here.'
            : 'Nothing is waiting in this tab. Check the others.',
      );
    }
    return ListView.separated(
      itemCount: batches.length,
      separatorBuilder: (_, _) => const SizedBox(height: Fx.s8),
      itemBuilder: (context, index) {
        final sessionId = batches.keys.elementAt(index);
        final tickets = batches[sessionId]!;
        final classes = {for (final t in tickets) (t as Map)['cls']?.toString() ?? ''}..remove('');
        final newest = tickets.map((t) => DateTime.tryParse((t as Map)['timestamp']?.toString() ?? '')).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
        return FxCard(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => InboxReplayScreen(sessionId: sessionId, source: _source, tickets: tickets, onTicketsUpdated: _fetchSessions, client: _client),
          )),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Fx.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Fx.radiusSm)),
              child: Icon(_sources.firstWhere((s) => s.$1 == _source).$3, color: Fx.accent),
            ),
            const SizedBox(width: Fx.s16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Batch ${_short(sessionId)}', style: Fx.heading(context)),
                  const SizedBox(width: Fx.s8),
                  StatusPill(label: '${tickets.length} ${tickets.length == 1 ? 'ticket' : 'tickets'}', color: Fx.warning, dense: true),
                ]),
                const SizedBox(height: Fx.s8),
                Wrap(spacing: Fx.s8, runSpacing: Fx.s4, children: [for (final c in classes.take(4)) ViolationChip(c, dense: true)]),
              ]),
            ),
            if (newest != null) Padding(padding: const EdgeInsets.only(right: Fx.s12), child: Text(ago(newest.toLocal()), style: Fx.caption(context))),
            Icon(Icons.chevron_right, color: Fx.muted(context)),
          ]),
        );
      },
    );
  }
}

class InboxReplayScreen extends StatefulWidget {
  final String sessionId;
  final String source;
  final List<dynamic> tickets;
  final VoidCallback onTicketsUpdated;

  /// Injected by tests; the app uses the real backend.
  final http.Client? client;

  const InboxReplayScreen({
    super.key,
    required this.sessionId,
    required this.source,
    required this.tickets,
    required this.onTicketsUpdated,
    this.client,
  });

  @override
  State<InboxReplayScreen> createState() => _InboxReplayScreenState();
}

class _InboxReplayScreenState extends State<InboxReplayScreen> {
  late List<dynamic> _currentTickets;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentTickets = List.from(widget.tickets);
  }

  void _removeTicket(String id) {
    setState(() {
      _currentTickets.removeWhere((t) => t['id'] == id);

      // Auto-select the next available item
      if (_currentTickets.isNotEmpty && _selectedIndex >= _currentTickets.length) {
        _selectedIndex = _currentTickets.length - 1;
      }
    });

    widget.onTicketsUpdated();

    if (_currentTickets.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Batch ${_short(widget.sessionId)}';
    if (_currentTickets.isEmpty) {
      return Scaffold(
        backgroundColor: Fx.page(context),
        appBar: AppBar(title: Text(title)),
        body: const EmptyState(icon: Icons.done_all, title: 'Every ticket in this batch has a decision'),
      );
    }

    final selectedTicket = _currentTickets[_selectedIndex];
    final left = _currentTickets.length;

    return Scaffold(
      backgroundColor: Fx.page(context),
      appBar: AppBar(
        title: Row(children: [
          Text(title),
          const SizedBox(width: Fx.s12),
          StatusPill(label: '$left left', color: Fx.warning, dense: true),
        ]),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Master pane: the tickets still to decide
          Container(
            width: 300,
            decoration: BoxDecoration(border: Border(right: BorderSide(color: Fx.border(context))), color: Fx.panel(context)),
            child: ListView.builder(
              padding: const EdgeInsets.all(Fx.s8),
              itemCount: _currentTickets.length,
              itemBuilder: (context, index) {
                final ticket = _currentTickets[index];
                final selected = index == _selectedIndex;
                final plate = (ticket['user_name'] ?? '').toString();
                final read = plate.isNotEmpty && plate != 'UNIDENTIFIED';
                return Padding(
                  padding: const EdgeInsets.only(bottom: Fx.s4),
                  child: FxCard(
                    selected: selected,
                    padding: const EdgeInsets.symmetric(horizontal: Fx.s12, vertical: Fx.s12),
                    onTap: () => setState(() => _selectedIndex = index),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          ViolationChip(ticket['cls'].toString(), dense: true),
                          const SizedBox(height: Fx.s4),
                          Text(read ? plate : 'Plate not read', maxLines: 1, overflow: TextOverflow.ellipsis, style: read ? Fx.plate.copyWith(fontSize: 15) : Fx.caption(context)),
                        ]),
                      ),
                      Text(ago(DateTime.tryParse(ticket['timestamp'].toString())?.toLocal()), style: Fx.caption(context)),
                    ]),
                  ),
                );
              },
            ),
          ),

          // Detail pane: the ticket being decided
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Fx.s24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: TicketReviewWidget(
                    key: ValueKey(selectedTicket['id']),
                    ticket: selectedTicket,
                    client: widget.client,
                    onProcessed: () => _removeTicket(selectedTicket['id']),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TicketReviewWidget extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onProcessed;
  final http.Client? client;

  const TicketReviewWidget({required this.ticket, required this.onProcessed, this.client, super.key});

  @override
  State<TicketReviewWidget> createState() => _TicketReviewWidgetState();
}

class _TicketReviewWidgetState extends State<TicketReviewWidget> {
  late final http.Client _client = widget.client ?? http.Client();
  late TextEditingController _plateController;
  bool _isProcessing = false;
  bool _isEdited = false;
  String? _error;
  late String _originalText;

  @override
  void initState() {
    super.initState();
    _originalText = widget.ticket['user_name'] ?? 'UNIDENTIFIED';
    final initialStr = _originalText == 'UNIDENTIFIED' ? '' : _originalText;
    _plateController = TextEditingController(text: initialStr);
    _plateController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _plateController.removeListener(_onTextChanged);
    _plateController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final currentText = _plateController.text.trim();
    // Consider edited if the text is not empty and differs from original
    final isEdited = currentText.isNotEmpty && currentText != (_originalText == 'UNIDENTIFIED' ? '' : _originalText);
    if (_isEdited != isEdited) {
      setState(() => _isEdited = isEdited);
    }
  }

  /// The plate pictures the backend saved for this ticket, or null when it has none.
  Map<String, dynamic>? get _crop {
    final raw = widget.ticket['crop_results_json'];
    if (raw == null) return null;
    try {
      final crops = jsonDecode(raw as String) as List;
      return crops.isEmpty ? null : Map<String, dynamic>.from(crops.first as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _processTicket(String dbAction, {required bool sendToVault, bool isFalsePositive = false, required String done}) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    final id = widget.ticket['id'];

    // For false positives, we send an empty string so it becomes a background training image.
    final textToSend = isFalsePositive ? '' : _plateController.text.trim();

    try {
      if (sendToVault) {
        List<String> pathsToSend = [];
        // First try to extract the specific plate crops (RAW and GAN Enhanced)
        final crop = _crop;
        if (crop != null) {
          final rawCrop = crop['image_raw'];
          final srCrop = crop['image_sr'];

          // CRITICAL ML ALIGNMENT:
          // We strictly send the GAN Enhanced crop because that is what the OCR engine
          // processes in the live production pipeline.
          if (srCrop != null) {
            pathsToSend.add('snapshots/evidence/$srCrop');
          } else if (rawCrop != null) {
            // Fallback only if GAN failed
            pathsToSend.add('snapshots/evidence/$rawCrop');
          }
        }

        // Fallback to original image path if crops failed
        if (pathsToSend.isEmpty) {
          final imgP = widget.ticket['image_path'] as String;
          if (imgP.isNotEmpty) pathsToSend.add(imgP);
        }

        for (final p in pathsToSend) {
          try {
            final imgRes = await _client.get(Uri.parse('${ApiConstants.baseUrl}/$p'));
            if (imgRes.statusCode == 200) {
              final base64Img = base64Encode(imgRes.bodyBytes);
              await _client.post(
                Uri.parse('${ApiConstants.baseUrl}/api/feedback/pop-quiz'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'image_base64': base64Img,
                  'corrected_label': textToSend,
                  'class_id': 0
                }),
              );
            }
          } catch (_) {
            // Ignore Vault failures: the training feedback is a bonus, the decision is what matters
          }
        }
      }

      final response = await _client.patch(
        Uri.parse('${ApiConstants.baseUrl}/violations/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': dbAction}),
      );

      if (response.statusCode != 200) throw 'HTTP ${response.statusCode}';
      if (mounted) AppToast.show(context, done);
      widget.onProcessed();
    } catch (_) {
      if (mounted) setState(() => _error = 'The decision was not saved. Check that the backend is running, then press the button again.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;

    // Parse evidence paths to match Forensic UI layout
    List<String> evPaths = [];
    if (ticket['evidence_paths'] != null) {
      try {
        final parsed = jsonDecode(ticket['evidence_paths']);
        if (parsed is List) {
          evPaths = parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    if (evPaths.isEmpty && ticket['image_path'] != '') {
      // Fallback if no full paths, just use the main image
      final p = ticket['image_path'] as String;
      if (p.startsWith('snapshots/evidence/')) {
        evPaths.add(p.replaceFirst('snapshots/evidence/', ''));
      } else {
        evPaths.add(p);
      }
    }

    final crop = _crop;
    final plateCrop = crop?['image_sr'] ?? crop?['image_raw'];
    final at = DateTime.tryParse(ticket['timestamp'].toString())?.toLocal();
    final busy = _isProcessing;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        ViolationChip(ticket['cls'].toString()),
        const SizedBox(width: Fx.s12),
        Text(ago(at), style: Fx.caption(context)),
      ]),
      const SizedBox(height: Fx.s24),
      const SectionLabel('Photos from the camera'),
      SizedBox(
        height: 220,
        child: evPaths.isEmpty
            ? const FxCard(child: Center(child: Text('No photos were saved for this ticket.')))
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: evPaths.length,
                separatorBuilder: (_, _) => const SizedBox(width: Fx.s12),
                itemBuilder: (context, index) {
                  final url = '${ApiConstants.baseUrl}/snapshots/evidence/${evPaths[index]}';
                  return Semantics(
                    button: true,
                    label: 'Photo ${index + 1} of ${evPaths.length}. Open full screen.',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Fx.radius),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => FullScreenEvidenceViewer(evPaths: evPaths, initialIndex: index),
                      )),
                      child: Stack(alignment: Alignment.bottomRight, children: [
                        Container(
                          width: 340,
                          decoration: BoxDecoration(border: Border.all(color: Fx.border(context)), borderRadius: BorderRadius.circular(Fx.radius), color: Colors.black26),
                          child: FxImage(image: NetworkImage(url), fit: BoxFit.contain, radius: Fx.radius),
                        ),
                        const Padding(padding: EdgeInsets.all(Fx.s8), child: Icon(Icons.fullscreen, color: Colors.white, size: 28)),
                      ]),
                    ),
                  );
                },
              ),
      ),
      const SizedBox(height: Fx.s24),
      const SectionLabel('Plate number'),
      FxCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (plateCrop != null) ...[
            SizedBox(
              width: 200,
              height: 80,
              child: FxImage(image: NetworkImage('${ApiConstants.baseUrl}/snapshots/evidence/$plateCrop'), fit: BoxFit.contain, radius: Fx.radiusSm, errorLabel: 'Close-up missing'),
            ),
            const SizedBox(width: Fx.s24),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_originalText == 'UNIDENTIFIED' ? 'The system could not read the plate.' : 'The system read this plate. Correct it if it is wrong.', style: Fx.caption(context)),
              const SizedBox(height: Fx.s8),
              TextFormField(
                controller: _plateController,
                enabled: !busy,
                textCapitalization: TextCapitalization.characters,
                style: Fx.plate.copyWith(fontSize: 26, letterSpacing: 3),
                decoration: const InputDecoration(hintText: 'Type the plate', border: OutlineInputBorder()),
              ),
            ]),
          ),
        ]),
      ),
      if (crop != null) ...[
        const SizedBox(height: Fx.s8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('More close-ups', style: Fx.body(context)),
            children: [
              Wrap(spacing: Fx.s12, runSpacing: Fx.s12, children: [
                for (final (label, key) in const [('Vehicle', 'image_context'), ('Plate as seen', 'image_raw'), ('Plate sharpened', 'image_sr')])
                  if (crop[key] != null)
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: Fx.caption(context)),
                      const SizedBox(height: Fx.s4),
                      SizedBox(width: 260, height: 120, child: FxImage(image: NetworkImage('${ApiConstants.baseUrl}/snapshots/evidence/${crop[key]}'), fit: BoxFit.contain, radius: Fx.radiusSm)),
                    ]),
              ]),
            ],
          ),
        ),
      ],
      const SizedBox(height: Fx.s24),
      if (_error != null) ...[FxBanner(message: _error!), const SizedBox(height: Fx.s12)],
      Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: Fx.s12, runSpacing: Fx.s12, children: [
        if (_isEdited) Text('You changed the plate, so this ticket can only be confirmed.', style: Fx.caption(context)),
        Tooltip(
          message: 'Remove the ticket without sending the photo for training',
          child: TextButton.icon(
            onPressed: busy ? null : () => _processTicket('rejected', sendToVault: false, done: 'Ticket discarded'),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Discard'),
          ),
        ),
        Tooltip(
          message: 'The system was wrong: there is no violation',
          child: OutlinedButton.icon(
            onPressed: (busy || _isEdited) ? null : () => _processTicket('rejected', sendToVault: true, isFalsePositive: true, done: 'Marked as a false alarm'),
            icon: const Icon(Icons.close),
            label: const Text('False alarm'),
            style: OutlinedButton.styleFrom(foregroundColor: Fx.danger, minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: Fx.s24)),
          ),
        ),
        FilledButton.icon(
          onPressed: busy ? null : () => _processTicket('approved', sendToVault: true, done: 'Violation confirmed'),
          icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
          label: Text(_isEdited ? 'Confirm with this plate' : 'Confirm violation'),
          style: FilledButton.styleFrom(backgroundColor: Fx.success, foregroundColor: const Color(0xFF06210F), minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: Fx.s24)),
        ),
      ]),
    ]);
  }
}

class FullScreenEvidenceViewer extends StatefulWidget {
  final List<String> evPaths;
  final int initialIndex;

  const FullScreenEvidenceViewer({super.key, required this.evPaths, required this.initialIndex});

  @override
  State<FullScreenEvidenceViewer> createState() => _FullScreenEvidenceViewerState();
}

class _FullScreenEvidenceViewerState extends State<FullScreenEvidenceViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentIndex < widget.evPaths.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _prevPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Photo ${_currentIndex + 1} of ${widget.evPaths.length}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemCount: widget.evPaths.length,
            itemBuilder: (context, index) {
              final url = '${ApiConstants.baseUrl}/snapshots/evidence/${widget.evPaths[index]}';
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: FxImage(image: NetworkImage(url), fit: BoxFit.contain),
              );
            },
          ),
          if (_currentIndex > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(iconSize: 56, tooltip: 'Previous photo', icon: const Icon(Icons.chevron_left, color: Colors.white70), onPressed: _prevPage),
            ),
          if (_currentIndex < widget.evPaths.length - 1)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(iconSize: 56, tooltip: 'Next photo', icon: const Icon(Icons.chevron_right, color: Colors.white70), onPressed: _nextPage),
            ),
        ],
      ),
    );
  }
}
