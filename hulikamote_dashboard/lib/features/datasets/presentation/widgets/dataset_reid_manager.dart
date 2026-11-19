import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hulikamote_dashboard/features/datasets/data/dataset_viewer_api.dart';
import 'package:hulikamote_dashboard/core/theme/light_mode.dart';

/// Clean the car-matcher (ReID) data before it is trained on. A folder of photos is one vehicle (car, motorcycle, tricycle,
/// jeepney, bus, truck ...), so a tracker jump is fixed by moving photos or merging two vehicles, and two vehicles under one
/// number by moving the odd photos out. Photos you are unsure about can be set aside (Temporary: not trained on) and later
/// kept as a vehicle of their own or merged into a known one.
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
    'temporary': 'Temporary',
    'repeats': 'Repeats',
    'small': 'Few photos',
  };
  static const _reasons = <String, String>{
    'not_a_car': 'Not a vehicle',
    'bad_photo': 'Bad photo (blurry, tiny, blocked)',
    'wrong_car': 'Wrong vehicle (does not belong anywhere here)',
  };

  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _analyses = const [];
  List<Map<String, dynamic>> _cars = const [];
  String _filter = 'all';
  String? _analysis;
  String? _classFilter;
  String _query = '';
  String? _key;
  Map<String, dynamic>? _detail;
  final Map<String, List<String>> _partnerPhotos = {};
  final Set<String> _picked = {};
  final Set<String> _listPicked = {};
  int? _lastPhoto;
  int? _lastListIndex;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _message;
  Timer? _jobPoll;

  DatasetViewerApi get _api => widget.api;
  bool get _training => _summary['training'] == true;
  bool get _canUndo => _summary['can_undo'] == true && !_training;
  int get _temporaryCount => (_summary['temporary'] as num?)?.toInt() ?? 0;
  List<String> get _classList =>
      (_summary['class_list'] as List? ?? const []).map((e) => '$e').toList();
  Map<String, dynamic>? get _scan => _summary['scan'] is Map
      ? Map<String, dynamic>.from(_summary['scan'] as Map)
      : null;
  bool get _shift => HardwareKeyboard.instance.isShiftPressed;
  bool get _ctrl =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

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

  Map<String, dynamic>? _carByKey(String key) {
    for (final c in _cars) {
      if (c['key'] == key) return c;
    }
    return null;
  }

  Future<void> _reload({bool keepDetail = true}) async {
    try {
      final summary = await _api.reidSummary();
      final cars = await _api.reidCars(
        analysis: _analysis,
        filter: _filter,
        q: _query,
        cls: _classFilter,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _analyses = DatasetViewerApi.maps(cars['analyses']);
        _cars = DatasetViewerApi.maps(cars['cars']);
        final keys = _cars.map((c) => '${c['key']}').toSet();
        _listPicked.retainAll(keys);
        _loading = false;
        _error = null;
      });
      if (keepDetail && _key != null) {
        await _openDetail(_key!, keepPicks: true);
      }
      final job = summary['job'];
      if (job is Map && job['state'] == 'running') {
        _pollJob('${job['id']}', '${job['kind'] ?? 'scan'}');
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
        if (_key != key) _lastPhoto = null;
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
        _lastPhoto = null;
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

  static String _label(String key) =>
      key.contains('/') ? key.split('/').last : key;

  // ---------------------------------------------------------------- scan

  Future<void> _startJob(Future<Map<String, dynamic>> Function() start, String kind) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final job = await start();
      _pollJob('${job['id']}', '${job['kind'] ?? kind}');
    } on DatasetViewerApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanNow() => _startJob(_api.reidScan, 'scan');

  Future<void> _suggestNow() => _startJob(_api.reidSuggest, 'suggest');

  void _pollJob(String id, String kind) {
    _jobPoll?.cancel();
    _jobPoll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final job = await _api.reidJob(id);
        if (!mounted) return timer.cancel();
        if (job['state'] != 'running') {
          timer.cancel();
          final what = kind == 'suggest' ? 'Class suggestion' : 'Scan';
          setState(
            () => _message = job['state'] == 'done'
                ? (kind == 'suggest'
                      ? 'Class suggestions are ready. They are marked (suggested): change any you do not agree with.'
                      : 'Scan finished.')
                : '$what failed: ${job['text']}',
          );
          await _reload();
        }
      } catch (_) {
        timer.cancel();
      }
    });
    if (mounted) {
      setState(
        () => _summary = {
          ..._summary,
          'job': {'id': id, 'state': 'running', 'kind': kind},
        },
      );
    }
  }

  // ---------------------------------------------------------------- photo actions

  Future<void> _newVehicle({required bool temporary}) async {
    final refs = _pickedRefs;
    final result = await _run(
      () => _api.reidMove(refs, temporary: temporary),
      '',
    );
    if (result != null && mounted) {
      final name = _label('${result['to']}');
      setState(_picked.clear);
      setState(
        () => _message = temporary
            ? 'Set ${refs.length} photo(s) aside as $name (Temporary: not trained on). Keep it, merge it, or open another vehicle.'
            : 'Moved ${refs.length} photo(s) into a new vehicle, $name.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> _ranked({List<String>? photos}) async {
    try {
      final r = await _api.reidSimilar(_key!, photos: photos);
      return DatasetViewerApi.maps(r['vehicles']);
    } catch (_) {
      return DatasetViewerApi.maps(_detail?['siblings']);
    }
  }

  String _vehicleLine(Map<String, dynamic> v) {
    final bits = <String>['${v['photos']} photos'];
    if (v['class'] != null) bits.add('${v['class']}');
    final alike = v['alike'];
    if (alike is num && alike > 0) {
      bits.add('looks ${(alike * 100).round()}% alike');
    }
    return bits.join(' · ');
  }

  Future<void> _moveDialog() async {
    final picked = _picked.toList()..sort();
    final ranked = await _ranked(photos: picked);
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Move ${picked.length} photo(s) to…'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__new__'),
            child: const ListTile(
              leading: Icon(Icons.add_circle_outline),
              title: Text('A new vehicle'),
              subtitle: Text('The selected photos become their own vehicle.'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__temporary__'),
            child: const ListTile(
              leading: Icon(Icons.inventory_2_outlined),
              title: Text('A temporary vehicle'),
              subtitle: Text('Set aside: not trained on until you decide.'),
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            width: 480,
            height: 320,
            child: ListView(
              children: [
                for (final v in ranked)
                  ListTile(
                    leading: _thumb('${v['key']}', v['thumb'], 44),
                    title: Text(_label('${v['key']}')),
                    subtitle: Text(_vehicleLine(v)),
                    trailing: v['temporary'] == true
                        ? _tag('Temporary', Colors.blueGrey)
                        : null,
                    onTap: () => Navigator.pop(context, '${v['key']}'),
                  ),
                if (ranked.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('This analysis has no other vehicle.'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == '__new__') return _newVehicle(temporary: false);
    if (choice == '__temporary__') return _newVehicle(temporary: true);
    final refs = _pickedRefs;
    final result = await _run(
      () => _api.reidMove(refs, to: choice),
      'Moved ${refs.length} photo(s) to ${_label(choice)}.',
    );
    if (result != null && mounted) setState(_picked.clear);
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
    final result = await _run(
      () => _api.reidRemove(refs, reason),
      'Removed ${refs.length} photo(s).',
    );
    if (result != null && mounted) setState(_picked.clear);
  }

  // ---------------------------------------------------------------- vehicle actions

  Future<void> _mergeOthersDialog() async {
    final ranked = await _ranked();
    if (!mounted) return;
    final chosen = <String>{};
    final keys = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Merge vehicles into ${_label(_key!)}'),
          content: SizedBox(
            width: 480,
            height: 360,
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Tick the vehicles that are really this vehicle (most alike first). Their photos move here and their folders go away.',
                  ),
                ),
                for (final v in ranked)
                  CheckboxListTile(
                    value: chosen.contains('${v['key']}'),
                    onChanged: (on) => setLocal(() {
                      on == true
                          ? chosen.add('${v['key']}')
                          : chosen.remove('${v['key']}');
                    }),
                    secondary: _thumb('${v['key']}', v['thumb'], 44),
                    title: Text(_label('${v['key']}')),
                    subtitle: Text(_vehicleLine(v)),
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
      'Merged ${keys.length} vehicle(s) into ${_label(into)}.',
    );
  }

  Future<void> _mergeIntoDialog() async {
    final ranked = await _ranked();
    if (!mounted) return;
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Merge ${_label(_key!)} into…'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Pick the known vehicle this one really is (most alike first). All its photos move there.',
            ),
          ),
          SizedBox(
            width: 480,
            height: 340,
            child: ListView(
              children: [
                for (final v in ranked)
                  ListTile(
                    leading: _thumb('${v['key']}', v['thumb'], 44),
                    title: Text(_label('${v['key']}')),
                    subtitle: Text(_vehicleLine(v)),
                    trailing: v['temporary'] == true
                        ? _tag('Temporary', Colors.blueGrey)
                        : null,
                    onTap: () => Navigator.pop(context, '${v['key']}'),
                  ),
                if (ranked.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('This analysis has no other vehicle.'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (target == null) return;
    final from = _key!;
    await _run(
      () => _api.reidMerge([from], target),
      'Merged ${_label(from)} into ${_label(target)}.',
      openAfter: target,
    );
  }

  Future<void> _removeVehicle() async {
    final key = _key!;
    final reason = await _reasonDialog(
      'Remove the whole vehicle ${_label(key)}?',
      'All ${(_detail?['photos'] as List? ?? const []).length} photos leave the training data (kept in quarantine, restorable).',
    );
    if (reason == null) return;
    setState(() {
      _key = null;
      _detail = null;
    });
    await _run(
      () => _api.reidRemoveCars([key], reason),
      'Removed the vehicle.',
    );
  }

  Future<void> _holdVehicle() => _run(
    () => _api.reidHold([_key!]),
    'Set ${_label(_key!)} aside (Temporary: not trained on).',
  );

  Future<void> _keepVehicle() => _run(
    () => _api.reidKeep([_key!]),
    '${_label(_key!)} is now a vehicle of its own and is trained on.',
  );

  Future<String?> _classDialog(String title) => showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final c in _classList)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, c),
            child: Text(c),
          ),
        const Divider(height: 1),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'auto'),
          child: const Text("Use the ticket's class"),
        ),
      ],
    ),
  );

  Future<void> _setClass(List<String> keys, String value) => _run(
    () => _api.reidSetClass(keys, value),
    value == 'auto'
        ? "Class set back to the ticket's."
        : 'Class set to $value for ${keys.length} vehicle(s).',
  );

  // ---------------------------------------------------------------- several vehicles at once

  List<String> get _picks => _listPicked.toList();

  Future<void> _bulkMerge() async {
    final keys = _picks;
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Merge ${keys.length} vehicles into one'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Which one stays? The photos of the others move into it and their folders go away.',
            ),
          ),
          for (final k in keys)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, k),
              child: ListTile(
                leading: _thumb(k, _carByKey(k)?['thumb'], 44),
                title: Text(_label(k)),
                subtitle: Text(
                  '${_carByKey(k)?['photos']} photos${_carByKey(k)?['class'] != null ? ' · ${_carByKey(k)?['class']}' : ''}',
                ),
              ),
            ),
        ],
      ),
    );
    if (target == null) return;
    final others = keys.where((k) => k != target).toList();
    setState(_listPicked.clear);
    await _run(
      () => _api.reidMerge(others, target),
      'Merged ${others.length} vehicle(s) into ${_label(target)}.',
      openAfter: target,
    );
  }

  Future<void> _bulkClass() async {
    final keys = _picks;
    final value = await _classDialog('Class of ${keys.length} vehicles');
    if (value == null) return;
    await _setClass(keys, value);
  }

  Future<void> _bulkHold() async {
    final keys = _picks
        .where((k) => _carByKey(k)?['temporary'] != true)
        .toList();
    setState(_listPicked.clear);
    await _run(
      () => _api.reidHold(keys),
      'Set ${keys.length} vehicle(s) aside (Temporary: not trained on).',
    );
  }

  Future<void> _bulkKeep() async {
    final keys = _picks
        .where((k) => _carByKey(k)?['temporary'] == true)
        .toList();
    setState(_listPicked.clear);
    await _run(
      () => _api.reidKeep(keys),
      '${keys.length} vehicle(s) are now vehicles of their own and are trained on.',
    );
  }

  Future<void> _bulkRemove() async {
    final keys = _picks;
    final reason = await _reasonDialog(
      'Remove ${keys.length} whole vehicles?',
      'All their photos leave the training data (kept in quarantine, restorable).',
    );
    if (reason == null) return;
    setState(() {
      _listPicked.clear();
      if (keys.contains(_key)) {
        _key = null;
        _detail = null;
      }
    });
    await _run(
      () => _api.reidRemoveCars(keys, reason),
      'Removed ${keys.length} vehicle(s).',
    );
  }

  // ---------------------------------------------------------------- merge suspects, removed photos

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
                              KeepColors(child: Image.network(
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
                              )),
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
    'Marked as two different vehicles.',
  );

  void _showPhoto(String key, String name) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: KeepColors(child: Image.network(
            _api.reidPhotoUri(key, name).toString(),
            headers: _api.endpoint.headers,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(40),
              child: Icon(Icons.broken_image_outlined, size: 48),
            ),
          )),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- selecting

  void _tapPhoto(int index, String name, List<String> photos) {
    setState(() {
      final last = _lastPhoto;
      if (_shift && last != null && last < photos.length) {
        final from = math.min(last, index);
        final to = math.max(last, index);
        _picked.addAll(photos.sublist(from, to + 1));
      } else {
        _picked.contains(name) ? _picked.remove(name) : _picked.add(name);
      }
      _lastPhoto = index;
    });
  }

  void _tapVehicle(int index, String key) {
    if (_shift || _ctrl) {
      setState(() {
        final last = _lastListIndex;
        if (_shift && last != null && last < _cars.length) {
          final from = math.min(last, index);
          final to = math.max(last, index);
          for (var i = from; i <= to; i++) {
            _listPicked.add('${_cars[i]['key']}');
          }
        } else {
          _listPicked.contains(key)
              ? _listPicked.remove(key)
              : _listPicked.add(key);
        }
        _lastListIndex = index;
      });
      return;
    }
    setState(() {
      _listPicked.clear();
      _lastListIndex = index;
    });
    _openDetail(key);
  }

  // ---------------------------------------------------------------- widgets

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
      child: KeepColors(child: Image.network(
        _api.reidPhotoUri(key, '$name', thumbnail: true).toString(),
        headers: _api.endpoint.headers,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const ColoredBox(
          color: Color(0xFF242A32),
          child: Icon(Icons.broken_image_outlined, size: 18),
        ),
      )),
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
            Text('Could not load the vehicle data: $_error'),
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
        if (_message != null && _message!.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Text(_message!),
          ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            children: [
              SizedBox(width: 392, child: _leftPane(context)),
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
              'Clean the vehicles before training: set the class, move or merge, set doubtful photos aside, take out bad photos.',
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
    final suggesting = scanning && job['kind'] == 'suggest';
    final noClass = ((_summary['classes'] as Map?)?['unset'] as num?)?.toInt() ?? 0;
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
                '${_summary['cars'] ?? 0} vehicles · ${_summary['photos'] ?? 0} photos · ${_summary['analyses'] ?? 0} analyses',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (_temporaryCount > 0)
                Text(
                  '$_temporaryCount temporary (${_summary['temporary_photos'] ?? 0} photos), not trained on',
                  style: theme.textTheme.labelMedium,
                ),
              const SizedBox(height: 6),
              if (scanning)
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        suggesting
                            ? 'Asking the vehicle model what each vehicle is (about a minute)…'
                            : 'Scanning every vehicle (about a minute)…',
                      ),
                    ),
                  ],
                )
              else if (scan == null)
                const Text(
                  'Not scanned yet. The scan finds vehicles that look like one vehicle split in two, and vehicles filed twice.',
                )
              else ...[
                Text(
                  'Training would use ${scan['used']} different vehicles (${scan['photos_used']} photos).',
                ),
                Text(
                  '${scan['jumps']} maybe the same vehicle · ${scan['mixed']} maybe two vehicles · ${scan['repeats']} repeats not used',
                  style: theme.textTheme.labelMedium,
                ),
                if (scan['stale'] == true)
                  Text(
                    'You made ${scan['edits']} change(s) since this scan: scan again to refresh.',
                    style: const TextStyle(color: Color(0xFFDBA64A)),
                  ),
              ],
              if (noClass > 0)
                Text(
                  '$noClass vehicles have no class yet.',
                  style: const TextStyle(color: Color(0xFFDBA64A)),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: scanning || _busy ? null : _scanNow,
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(scan == null ? 'Scan now' : 'Scan again'),
                  ),
                  Tooltip(
                    message:
                        'Guess the class of vehicles that have none, with the vehicle model. A class you set always wins.',
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: scanning || _busy || _training
                          ? null
                          : _suggestNow,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Suggest classes'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              for (final e in _filters.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      e.key == 'temporary' && _temporaryCount > 0
                          ? '${e.value} ($_temporaryCount)'
                          : e.value,
                    ),
                    selected: _filter == e.key,
                    onSelected: (_) {
                      setState(() => _filter = e.key);
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                flex: 3,
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
                          '${a['short']} · ${a['cars']}${(a['flagged'] as num? ?? 0) > 0 ? ' · ${a['flagged']} suspects' : ''}',
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
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String?>(
                  key: const ValueKey('class-filter'),
                  initialValue: _classFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Class',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All classes'),
                    ),
                    for (final c in _classList)
                      DropdownMenuItem<String?>(value: c, child: Text(c)),
                    const DropdownMenuItem<String?>(
                      value: 'unset',
                      child: Text('Not set'),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _classFilter = v);
                    _reload();
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search vehicle name',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: Text(
            'Click opens a vehicle. Shift+click or Ctrl+click selects several.',
            style: theme.textTheme.labelSmall,
          ),
        ),
        Expanded(
          child: _cars.isEmpty
              ? const Center(child: Text('No vehicles match this filter.'))
              : ListView.builder(
                  itemCount: _cars.length,
                  itemBuilder: (context, i) => _carTile(i, _cars[i]),
                ),
        ),
        if (_listPicked.isNotEmpty) _bulkBar(context),
      ],
    );
  }

  Widget _bulkBar(BuildContext context) {
    final keys = _picks;
    final temps = keys.where((k) => _carByKey(k)?['temporary'] == true).length;
    final perms = keys.length - temps;
    final locked = _training || _busy;
    return Container(
      key: const ValueKey('bulk-bar'),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: Colors.blueAccent.withAlpha(24),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${keys.length} vehicles selected',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          FilledButton.tonal(
            onPressed: locked || keys.length < 2 ? null : _bulkMerge,
            child: const Text('Merge into one…'),
          ),
          FilledButton.tonal(
            onPressed: locked ? null : _bulkClass,
            child: const Text('Set class…'),
          ),
          FilledButton.tonal(
            onPressed: locked || perms == 0 ? null : _bulkHold,
            child: Text('Set aside ($perms)'),
          ),
          FilledButton.tonal(
            onPressed: locked || temps == 0 ? null : _bulkKeep,
            child: Text('Keep ($temps)'),
          ),
          FilledButton.tonal(
            onPressed: locked ? null : _bulkRemove,
            child: const Text('Remove…'),
          ),
          TextButton(
            onPressed: () => setState(_listPicked.clear),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _carTile(int index, Map<String, dynamic> car) {
    final key = '${car['key']}';
    final picked = _listPicked.contains(key);
    final tags = <Widget>[
      if (car['temporary'] == true)
        _tag('Temporary · not trained on', Colors.indigo),
      if ((car['jump'] as List? ?? const []).isNotEmpty)
        _tag('Maybe the same vehicle as another', const Color(0xFFDBA64A)),
      if (car['mixed'] != null)
        _tag('Maybe two vehicles', const Color(0xFFD9534F)),
      if (car['repeat_of'] != null) _tag('Repeat · not used', Colors.blueGrey),
      if (car['small'] == true && car['temporary'] != true)
        _tag('1 photo · not used', Colors.blueGrey),
    ];
    return ListTile(
      key: ValueKey('car-$key'),
      selected: key == _key || picked,
      selectedTileColor: picked ? Colors.blueAccent.withAlpha(30) : null,
      dense: true,
      leading: _thumb(key, car['thumb'], 46),
      title: Row(
        children: [
          Expanded(
            child: Text('${car['car']}', overflow: TextOverflow.ellipsis),
          ),
          Text(
            car['class'] == null
                ? 'no class'
                : '${car['class']}${car['class_source'] == 'model' ? ' (suggested)' : ''}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: car['class'] == null ? const Color(0xFFDBA64A) : null,
            ),
          ),
        ],
      ),
      subtitle: Wrap(
        spacing: 4,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [Text('${car['photos']} photos'), ...tags],
      ),
      trailing: picked
          ? const Icon(Icons.check_circle, color: Colors.blueAccent, size: 20)
          : null,
      onTap: () => _tapVehicle(index, key),
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

  Widget _classPicker(Map<String, dynamic> detail) {
    final current = detail['class'] as String?;
    final source = detail['class_source'] as String?;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Class: '),
        DropdownButton<String>(
          key: const ValueKey('class-dropdown'),
          value: _classList.contains(current) ? current : null,
          hint: const Text('not set'),
          isDense: true,
          items: [
            for (final c in _classList)
              DropdownMenuItem<String>(value: c, child: Text(c)),
            const DropdownMenuItem<String>(
              value: 'auto',
              child: Text("Use the ticket's class"),
            ),
          ],
          onChanged: _training || _busy
              ? null
              : (v) {
                  if (v != null) _setClass([_key!], v);
                },
        ),
        if (source == 'ticket' || source == 'model')
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              source == 'ticket' ? '(from the ticket)' : '(suggested by the model)',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
      ],
    );
  }

  Widget _rightPane(BuildContext context) {
    final detail = _detail;
    if (detail == null || _key == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Pick a vehicle on the left. Start with the Suspects filter: vehicles marked "Maybe the same vehicle" '
            'are probably one vehicle the tracker gave two numbers.',
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
    final temporary = detail['temporary'] == true;
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
              _classPicker(detail),
              const SizedBox(width: 16),
              Text(
                'analysis ${'${detail['analysis']}'.substring(0, '${detail['analysis']}'.length.clamp(0, 8))}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
        if (temporary)
          _note(
            'Set aside (Temporary): these photos are not trained on. Keep them as a vehicle of their own, or merge them into a vehicle you know.',
            Colors.indigo,
          ),
        if (detail['repeat_of'] != null)
          _note(
            'This is a repeat of ${_label('${detail['repeat_of']}')} (another analysis of the same clip). '
            'Training uses that one, so cleaning this folder changes nothing.',
            Colors.blueGrey,
          ),
        if (detail['mixed'] != null)
          _note(
            'About ${((detail['mixed'] as num) * 100).round()}% of these photos look unlike the rest: two vehicles may share this folder. '
            'Select the odd photos and set them aside or move them to a new vehicle.',
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
                onPressed: () => setState(
                  () => _picked
                    ..clear()
                    ..addAll(photos),
                ),
                child: const Text('Select all'),
              ),
              TextButton(
                onPressed: _picked.isEmpty ? null : () => setState(_picked.clear),
                child: const Text('Clear'),
              ),
              Text('${_picked.length} selected'),
              Text(
                'Click a photo to pick it. Shift+click picks a range.',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(
                onPressed: locked || _picked.isEmpty ? null : _moveDialog,
                icon: const Icon(Icons.drive_file_move_outline, size: 18),
                label: const Text('Move to…'),
              ),
              FilledButton.tonalIcon(
                onPressed: locked || _picked.isEmpty
                    ? null
                    : () => _newVehicle(temporary: false),
                icon: const Icon(Icons.call_split, size: 18),
                label: const Text('New vehicle'),
              ),
              FilledButton.tonalIcon(
                onPressed: locked || _picked.isEmpty
                    ? null
                    : () => _newVehicle(temporary: true),
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Set aside (temporary)'),
              ),
              FilledButton.tonalIcon(
                onPressed: locked || _picked.isEmpty ? null : _removePhotos,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove photos'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: locked || siblings.isEmpty ? null : _mergeOthersDialog,
                icon: const Icon(Icons.merge_type, size: 18),
                label: const Text('Merge another vehicle into this'),
              ),
              OutlinedButton.icon(
                onPressed: locked || siblings.isEmpty ? null : _mergeIntoDialog,
                icon: const Icon(Icons.call_merge, size: 18),
                label: const Text('Merge this into…'),
              ),
              if (temporary)
                FilledButton.icon(
                  onPressed: locked ? null : _keepVehicle,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Keep as its own vehicle'),
                )
              else
                OutlinedButton.icon(
                  onPressed: locked ? null : _holdVehicle,
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Set this vehicle aside'),
                ),
              OutlinedButton.icon(
                onPressed: locked ? null : _removeVehicle,
                icon: const Icon(Icons.folder_off_outlined, size: 18),
                label: const Text('Remove whole vehicle'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: photos.isEmpty
              ? const Center(child: Text('This vehicle has no photos.'))
              : GridView.extent(
                  padding: const EdgeInsets.all(14),
                  maxCrossAxisExtent: 150,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.72,
                  children: [
                    for (var i = 0; i < photos.length; i++)
                      _photoTile(i, photos[i], photos),
                  ],
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
            'Looks $alike% like ${_label(partner)} (${partnerNames.length} photos). Probably one vehicle the tracker gave two numbers.',
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
                child: const Text('Same vehicle — merge'),
              ),
              OutlinedButton(
                onPressed: _busy || _training ? null : () => _notSame(partner),
                child: const Text('Not the same vehicle'),
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

  Widget _photoTile(int index, String name, List<String> photos) {
    final picked = _picked.contains(name);
    return Material(
      key: ValueKey('photo-$name'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: () => _tapPhoto(index, name, photos),
        child: Stack(
          fit: StackFit.expand,
          children: [
            KeepColors(child: Image.network(
              _api.reidPhotoUri(_key!, name, thumbnail: true).toString(),
              headers: _api.endpoint.headers,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Color(0xFF242A32),
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            )),
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
