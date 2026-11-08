import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hulikamote_dashboard/features/datasets/data/dataset_viewer_api.dart';

/// Clean the car-matcher (ReID) data before it is trained on: a folder of photos is one car, so a tracker jump is
/// fixed by moving photos or merging two cars, and two cars under one number by moving the odd photos out.
class DatasetReidManager extends StatefulWidget {
  final DatasetViewerApi api;
  final Future<void> Function() onChanged;

  const DatasetReidManager({
    super.key,
    required this.api,
    required this.onChanged,
  });

  @override
  State<DatasetReidManager> createState() => _DatasetReidManagerState();
}

class _DatasetReidManagerState extends State<DatasetReidManager> {
  static const _filters = <String, String>{
    'all': 'All',
    'flagged': 'Suspects',
    'used': 'Trained on',
    'repeats': 'Repeats',
    'small': 'Few photos',
  };
  static const _reasons = <String, String>{
    'not_a_car': 'Not a car',
    'bad_photo': 'Bad photo (blurry, tiny, blocked)',
    'wrong_car': 'Wrong car (does not belong anywhere here)',
  };

  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _analyses = const [];
  List<Map<String, dynamic>> _cars = const [];
  String _filter = 'all';
  String? _analysis;
  String _query = '';
  String? _key;
  Map<String, dynamic>? _detail;
  final Map<String, List<String>> _partnerPhotos = {};
  final Set<String> _picked = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _message;
  Timer? _jobPoll;

  DatasetViewerApi get _api => widget.api;
  bool get _training => _summary['training'] == true;
  bool get _canUndo => _summary['can_undo'] == true && !_training;
  Map<String, dynamic>? get _scan => _summary['scan'] is Map
      ? Map<String, dynamic>.from(_summary['scan'] as Map)
      : null;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _jobPoll?.cancel();
    super.dispose();
  }

  Future<void> _reload({bool keepDetail = true}) async {
    try {
      final summary = await _api.reidSummary();
      final cars = await _api.reidCars(
        analysis: _analysis,
        filter: _filter,
        q: _query,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _analyses = DatasetViewerApi.maps(cars['analyses']);
        _cars = DatasetViewerApi.maps(cars['cars']);
        _loading = false;
        _error = null;
      });
      if (keepDetail && _key != null) {
        await _openDetail(_key!, keepPicks: true);
      }
      final job = summary['job'];
      if (job is Map && job['state'] == 'running') {
        _pollJob('${job['id']}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _openDetail(String key, {bool keepPicks = false}) async {
    try {
      final detail = await _api.reidCar(key);
      final partners = <String, List<String>>{};
      for (final j in (detail['jump'] as List? ?? const []).take(2)) {
        final partner = '${(j as Map)['key']}';
        try {
          final other = await _api.reidCar(partner);
          partners[partner] = (other['photos'] as List? ?? const [])
              .map((e) => '$e')
              .toList();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _key = key;
        _detail = detail;
        _partnerPhotos
          ..clear()
          ..addAll(partners);
        final names = (detail['photos'] as List? ?? const []).map((e) => '$e');
        if (keepPicks) {
          _picked.retainAll(names.toSet());
        } else {
          _picked.clear();
        }
      });
    } on DatasetViewerApiException catch (_) {
      if (!mounted) return;
      setState(() {
        _key = null;
        _detail = null;
        _picked.clear();
      });
    }
  }

  Future<Map<String, dynamic>?> _run(
    Future<Map<String, dynamic>> Function() action,
    String done, {
    String? openAfter,
  }) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await action();
      if (!mounted) return null;
      _message = done;
      if (openAfter != null) _key = openAfter;
      await _reload();
      await widget.onChanged();
      return result;
    } on DatasetViewerApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  List<Map<String, String>> get _pickedRefs => [
    for (final name in _picked) {'car': _key!, 'name': name},
  ];

  Future<void> _scanNow() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final job = await _api.reidScan();
      _pollJob('${job['id']}');
    } on DatasetViewerApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pollJob(String id) {
    _jobPoll?.cancel();
    _jobPoll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final job = await _api.reidJob(id);
        if (!mounted) return timer.cancel();
        if (job['state'] != 'running') {
          timer.cancel();
          setState(
            () => _message = job['state'] == 'done'
                ? 'Scan finished.'
                : 'Scan failed: ${job['text']}',
          );
          await _reload();
        }
      } catch (_) {
        timer.cancel();
      }
    });
    if (mounted) setState(() => _summary = {..._summary, 'job': {'id': id, 'state': 'running'}});
  }

  Future<void> _move({String? to}) async {
    final refs = _pickedRefs;
    final result = await _run(
      () => _api.reidMove(refs, to: to),
      to == null
          ? 'Moved ${refs.length} photo(s) into a new car.'
          : 'Moved ${refs.length} photo(s).',
    );
    if (to == null && result != null && mounted) {
      await _openDetail('${result['to']}');          // follow the photos into the new car
    }
  }

  Future<void> _moveDialog() async {
    final siblings = DatasetViewerApi.maps(_detail?['siblings']);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Move ${_picked.length} photo(s) to…'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__new__'),
            child: const ListTile(
              leading: Icon(Icons.add_circle_outline),
              title: Text('A new car'),
              subtitle: Text('The selected photos become their own car.'),
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            width: 460,
            height: 320,
            child: ListView(
              children: [
                for (final s in siblings)
                  ListTile(
                    leading: _thumb('${s['key']}', s['thumb'], 44),
                    title: Text(_label('${s['key']}')),
                    subtitle: Text(
                      '${s['photos']} photos${s['alike'] is num ? ' · looks ${((s['alike'] as num) * 100).round()}% alike' : ''}',
                    ),
                    onTap: () => Navigator.pop(context, '${s['key']}'),
                  ),
                if (siblings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('This analysis has no other car.'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await _move(to: choice == '__new__' ? null : choice);
  }

  Future<void> _mergeDialog() async {
    final siblings = DatasetViewerApi.maps(_detail?['siblings']);
    final chosen = <String>{};
    final keys = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Merge cars into ${_label(_key!)}'),
          content: SizedBox(
            width: 460,
            height: 340,
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Pick the cars that are really this car. Their photos move here and their folders go away.',
                  ),
                ),
                for (final s in siblings)
                  CheckboxListTile(
                    value: chosen.contains('${s['key']}'),
                    onChanged: (on) => setLocal(() {
                      on == true
                          ? chosen.add('${s['key']}')
                          : chosen.remove('${s['key']}');
                    }),
                    secondary: _thumb('${s['key']}', s['thumb'], 44),
                    title: Text(_label('${s['key']}')),
                    subtitle: Text(
                      '${s['photos']} photos${s['alike'] is num ? ' · looks ${((s['alike'] as num) * 100).round()}% alike' : ''}',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: chosen.isEmpty
                  ? null
                  : () => Navigator.pop(context, chosen.toList()),
              child: const Text('Merge'),
            ),
          ],
        ),
      ),
    );
    if (keys == null || keys.isEmpty) return;
    final into = _key!;
    await _run(
      () => _api.reidMerge(keys, into),
      'Merged ${keys.length} car(s) into ${_label(into)}.',
    );
  }

  Future<String?> _reasonDialog(String title, String body) async {
    var reason = 'bad_photo';
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: reason,
                onChanged: (v) => setLocal(() => reason = v ?? reason),
                child: Column(
                  children: [
                    for (final e in _reasons.entries)
                      RadioListTile<String>(
                        value: e.key,
                        title: Text(e.value),
                        dense: true,
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, reason),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removePhotos() async {
    final refs = _pickedRefs;
    final reason = await _reasonDialog(
      'Remove ${refs.length} photo(s)?',
      'They leave the training data but are kept in a quarantine folder: you can restore them (Removed) or undo.',
    );
    if (reason == null) return;
    await _run(
      () => _api.reidRemove(refs, reason),
      'Removed ${refs.length} photo(s).',
    );
  }

  Future<void> _removeCar() async {
    final key = _key!;
    final reason = await _reasonDialog(
      'Remove the whole car ${_label(key)}?',
      'All ${(_detail?['photos'] as List? ?? const []).length} photos leave the training data (kept in quarantine, restorable).',
    );
    if (reason == null) return;
    setState(() {
      _key = null;
      _detail = null;
    });
    await _run(() => _api.reidRemoveCars([key], reason), 'Removed the car.');
  }

  Future<void> _removedDialog() async {
    Map<String, dynamic> data;
    try {
      data = await _api.reidRemoved();
    } on DatasetViewerApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
      return;
    }
    if (!mounted) return;
    final items = DatasetViewerApi.maps(data['items']);
    final chosen = <int>{};
    final restore = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Removed photos (${items.length})'),
          content: SizedBox(
            width: 640,
            height: 420,
            child: items.isEmpty
                ? const Center(child: Text('Nothing was removed.'))
                : GridView.extent(
                    maxCrossAxisExtent: 110,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        InkWell(
                          key: ValueKey('removed-$i'),
                          onTap: () => setLocal(() {
                            chosen.contains(i)
                                ? chosen.remove(i)
                                : chosen.add(i);
                          }),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                _api
                                    .reidRemovedPhotoUri(
                                      items[i],
                                      thumbnail: true,
                                    )
                                    .toString(),
                                headers: _api.endpoint.headers,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const ColoredBox(
                                  color: Color(0xFF242A32),
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                              if (chosen.contains(i))
                                Container(
                                  color: Colors.blueAccent.withAlpha(70),
                                  child: const Icon(
                                    Icons.check_circle,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: chosen.isEmpty
                  ? null
                  : () => Navigator.pop(context, [
                      for (final i in chosen) items[i],
                    ]),
              child: Text('Restore ${chosen.length}'),
            ),
          ],
        ),
      ),
    );
    if (restore == null || restore.isEmpty) return;
    await _run(
      () => _api.reidRestore(restore),
      'Restored ${restore.length} photo(s).',
    );
  }

  Future<void> _mergeSuspect(String partner) async {
    final mine = (_detail?['photos'] as List? ?? const []).length;
    final theirs = _partnerPhotos[partner]?.length ?? 0;
    final into = mine >= theirs ? _key! : partner;
    final from = mine >= theirs ? partner : _key!;
    await _run(
      () => _api.reidMerge([from], into),
      'Merged into ${_label(into)}.',
      openAfter: into,
    );
  }

  Future<void> _notSame(String partner) => _run(
    () => _api.reidDismiss(_key!, partner),
    'Marked as two different cars.',
  );

  void _showPhoto(String key, String name) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Image.network(
            _api.reidPhotoUri(key, name).toString(),
            headers: _api.endpoint.headers,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(40),
              child: Icon(Icons.broken_image_outlined, size: 48),
            ),
          ),
        ),
      ),
    );
  }

  static String _label(String key) => key.contains('/') ? key.split('/').last : key;

  Widget _thumb(String key, Object? name, double size) {
    if (name == null) {
      return SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        _api.reidPhotoUri(key, '$name', thumbnail: true).toString(),
        headers: _api.endpoint.headers,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const ColoredBox(
          color: Color(0xFF242A32),
          child: Icon(Icons.broken_image_outlined, size: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load the car data: $_error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _reload, child: const Text('Try again')),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _topBar(context),
        if (_training)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            color: const Color(0xFFDBA64A).withAlpha(24),
            child: const Text(
              'The car matcher is training. Changes are disabled until it finishes.',
              style: TextStyle(color: Color(0xFFDBA64A)),
            ),
          ),
        if (_message != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Text(_message!),
          ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            children: [
              SizedBox(width: 372, child: _leftPane(context)),
              const VerticalDivider(width: 1),
              Expanded(child: _rightPane(context)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topBar(BuildContext context) {
    final removed = (_summary['removed'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Clean the cars before training: move photos between cars, merge a car the tracker split in two, take out bad photos.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TextButton.icon(
            onPressed: _canUndo && !_busy
                ? () => _run(_api.reidUndo, 'Undone.')
                : null,
            icon: const Icon(Icons.undo),
            label: const Text('Undo'),
          ),
          TextButton.icon(
            onPressed: _busy || _training ? null : _removedDialog,
            icon: const Icon(Icons.restore_from_trash_outlined),
            label: Text('Removed ($removed)'),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _leftPane(BuildContext context) {
    final scan = _scan;
    final job = _summary['job'];
    final scanning = job is Map && job['state'] == 'running';
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: theme.colorScheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_summary['cars'] ?? 0} car folders · ${_summary['photos'] ?? 0} photos · ${_summary['analyses'] ?? 0} analyses',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              if (scanning)
                const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Expanded(child: Text('Scanning every car (about a minute)…')),
                  ],
                )
              else if (scan == null)
                const Text(
                  'Not scanned yet. The scan finds cars that look like one car split in two, and cars filed twice.',
                )
              else ...[
                Text(
                  'Training would use ${scan['used']} different cars (${scan['photos_used']} photos).',
                ),
                Text(
                  '${scan['jumps']} maybe the same car · ${scan['mixed']} maybe two cars · ${scan['repeats']} repeats not used',
                  style: theme.textTheme.labelMedium,
                ),
                if (scan['stale'] == true)
                  Text(
                    'You made ${scan['edits']} change(s) since this scan: scan again to refresh.',
                    style: const TextStyle(color: Color(0xFFDBA64A)),
                  ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: scanning || _busy ? null : _scanNow,
                icon: const Icon(Icons.search),
                label: Text(scan == null ? 'Scan now' : 'Scan again'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final e in _filters.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _filter == e.key,
                  onSelected: (_) {
                    setState(() => _filter = e.key);
                    _reload();
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _analysis,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Analysis',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All analyses'),
                    ),
                    for (final a in _analyses)
                      DropdownMenuItem<String?>(
                        value: '${a['id']}',
                        child: Text(
                          '${a['short']} · ${a['cars']} cars${(a['flagged'] as num? ?? 0) > 0 ? ' · ${a['flagged']} suspects' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _analysis = v);
                    _reload();
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search car name',
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              setState(() => _query = v.trim());
              _reload();
            },
          ),
        ),
        Expanded(
          child: _cars.isEmpty
              ? const Center(child: Text('No cars match this filter.'))
              : ListView.builder(
                  itemCount: _cars.length,
                  itemBuilder: (context, i) => _carTile(_cars[i]),
                ),
        ),
      ],
    );
  }

  Widget _carTile(Map<String, dynamic> car) {
    final key = '${car['key']}';
    final tags = <Widget>[
      if ((car['jump'] as List? ?? const []).isNotEmpty)
        _tag('Maybe the same car as another', const Color(0xFFDBA64A)),
      if (car['mixed'] != null) _tag('Maybe two cars', const Color(0xFFD9534F)),
      if (car['repeat_of'] != null)
        _tag('Repeat · not used', Colors.blueGrey),
      if (car['small'] == true) _tag('1 photo · not used', Colors.blueGrey),
    ];
    return ListTile(
      key: ValueKey('car-$key'),
      selected: key == _key,
      dense: true,
      leading: _thumb(key, car['thumb'], 46),
      title: Text('${car['car']}', overflow: TextOverflow.ellipsis),
      subtitle: Wrap(
        spacing: 4,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [Text('${car['photos']} photos'), ...tags],
      ),
      onTap: () => _openDetail(key),
    );
  }

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withAlpha(30),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(fontSize: 10.5, color: color)),
  );

  Widget _rightPane(BuildContext context) {
    final detail = _detail;
    if (detail == null || _key == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Pick a car on the left. Start with the Suspects filter: cars marked "Maybe the same car" '
            'are probably one car the tracker gave two numbers.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final photos = (detail['photos'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    final jumps = DatasetViewerApi.maps(detail['jump']);
    final siblings = DatasetViewerApi.maps(detail['siblings']);
    final locked = _training || _busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${detail['car']}  ·  ${photos.length} photos',
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'analysis ${'${detail['analysis']}'.substring(0, '${detail['analysis']}'.length.clamp(0, 8))}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
        if (detail['repeat_of'] != null)
          _note(
            'This is a repeat of ${_label('${detail['repeat_of']}')} (another analysis of the same clip). '
            'Training uses that one, so cleaning this folder changes nothing.',
            Colors.blueGrey,
          ),
        if (detail['mixed'] != null)
          _note(
            'About ${((detail['mixed'] as num) * 100).round()}% of these photos look unlike the rest: two cars may share this folder. '
            'Select the odd photos and move them to a new car.',
            const Color(0xFFD9534F),
          ),
        for (final j in jumps) _suspectCard(context, j, siblings),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() => _picked
                  ..clear()
                  ..addAll(photos)),
                child: const Text('Select all'),
              ),
              TextButton(
                onPressed: _picked.isEmpty
                    ? null
                    : () => setState(_picked.clear),
                child: const Text('Clear'),
              ),
              Text('${_picked.length} selected'),
              FilledButton.tonalIcon(
                onPressed: locked || _picked.isEmpty ? null : _moveDialog,
                icon: const Icon(Icons.drive_file_move_outline, size: 18),
                label: const Text('Move to…'),
              ),
              FilledButton.tonalIcon(
                onPressed: locked || _picked.isEmpty
                    ? null
                    : () => _move(to: null),
                icon: const Icon(Icons.call_split, size: 18),
                label: const Text('New car from selection'),
              ),
              FilledButton.tonalIcon(
                onPressed: locked || _picked.isEmpty ? null : _removePhotos,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove photos'),
              ),
              OutlinedButton.icon(
                onPressed: locked || siblings.isEmpty ? null : _mergeDialog,
                icon: const Icon(Icons.merge_type, size: 18),
                label: const Text('Merge another car into this'),
              ),
              OutlinedButton.icon(
                onPressed: locked ? null : _removeCar,
                icon: const Icon(Icons.folder_off_outlined, size: 18),
                label: const Text('Remove whole car'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: photos.isEmpty
              ? const Center(child: Text('This car has no photos.'))
              : GridView.extent(
                  padding: const EdgeInsets.all(14),
                  maxCrossAxisExtent: 150,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.72,
                  children: [for (final name in photos) _photoTile(name)],
                ),
        ),
      ],
    );
  }

  Widget _note(String text, Color color) => Container(
    margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withAlpha(24),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: TextStyle(color: color)),
  );

  Widget _suspectCard(
    BuildContext context,
    Map<String, dynamic> jump,
    List<Map<String, dynamic>> siblings,
  ) {
    final partner = '${jump['key']}';
    final partnerNames = _partnerPhotos[partner] ?? const <String>[];
    final alike = ((jump['alike'] as num? ?? 0) * 100).round();
    return Container(
      key: ValueKey('suspect-$partner'),
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFDBA64A).withAlpha(24),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFDBA64A).withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Looks $alike% like ${_label(partner)} (${partnerNames.length} photos). Probably one car the tracker gave two numbers.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 70,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final n in partnerNames.take(8))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => _showPhoto(partner, n),
                      child: _thumb(partner, n, 70),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _busy || _training
                    ? null
                    : () => _mergeSuspect(partner),
                child: const Text('Same car — merge'),
              ),
              OutlinedButton(
                onPressed: _busy || _training ? null : () => _notSame(partner),
                child: const Text('Not the same car'),
              ),
              TextButton(
                onPressed: () => _openDetail(partner),
                child: const Text('Open it'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _photoTile(String name) {
    final picked = _picked.contains(name);
    return Material(
      key: ValueKey('photo-$name'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: () => setState(() {
          picked ? _picked.remove(name) : _picked.add(name);
        }),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              _api.reidPhotoUri(_key!, name, thumbnail: true).toString(),
              headers: _api.endpoint.headers,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Color(0xFF242A32),
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
            if (picked)
              Container(
                color: Colors.blueAccent.withAlpha(70),
                child: const Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.check_circle, color: Colors.white),
                  ),
                ),
              ),
            Positioned(
              right: 2,
              bottom: 2,
              child: IconButton(
                tooltip: 'Enlarge',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () => _showPhoto(_key!, name),
                icon: const Icon(Icons.zoom_in, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
