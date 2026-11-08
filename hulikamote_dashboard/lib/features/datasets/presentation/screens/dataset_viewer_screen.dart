import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:hulikamote_dashboard/core/utils/external_apps.dart';
import 'package:hulikamote_dashboard/features/datasets/data/dataset_viewer_api.dart';
import 'package:hulikamote_dashboard/features/datasets/presentation/widgets/dataset_reid_manager.dart';
import 'package:hulikamote_dashboard/features/datasets/presentation/widgets/dataset_relabel_tab.dart';

typedef DatasetViewerConnect = Future<DatasetViewerApi> Function();

class DatasetViewerScreen extends StatefulWidget {
  final DatasetViewerConnect? connect;
  const DatasetViewerScreen({super.key, this.connect});

  @override
  State<DatasetViewerScreen> createState() => _DatasetViewerScreenState();
}

class _DatasetViewerScreenState extends State<DatasetViewerScreen>
    with TickerProviderStateMixin {
  DatasetViewerApi? _api;
  List<Map<String, dynamic>> _datasets = const [];
  String? _dataset;
  String? _error;
  bool _connecting = true;
  int _aboutRevision = 0;
  Timer? _indexPoll;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _connect();
  }

  @override
  void dispose() {
    _indexPoll?.cancel();
    _tabs.dispose();
    _api?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final api = widget.connect != null
          ? await widget.connect!()
          : DatasetViewerApi(await ExternalApps.connectDatasetViewer());
      final datasets = await api.datasets();
      if (!mounted) {
        api.close();
        return;
      }
      _api?.close();
      setState(() {
        _api = api;
        _datasets = datasets;
        _dataset =
            _dataset != null && datasets.any((d) => d['name'] == _dataset)
            ? _dataset
            : datasets.isEmpty
            ? null
            : '${datasets.first['name']}';
        _connecting = false;
      });
      _pollIndex();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = '$e';
      });
    }
  }

  void _pollIndex() {
    _indexPoll?.cancel();
    final api = _api;
    if (api == null) return;
    _indexPoll = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final latest = await api.datasets();
        if (!mounted) return;
        setState(() => _datasets = latest);
        final building = latest.any(
          (d) => (d['index'] as Map?)?['state'] == 'building',
        );
        if (!building) _indexPoll?.cancel();
      } catch (_) {
        _indexPoll?.cancel();
      }
    });
  }

  Future<void> _refreshDatasets() async {
    final api = _api;
    if (api == null) return;
    try {
      final latest = await api.datasets();
      if (mounted) setState(() => _datasets = latest);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _reportCompleted() async {
    await _refreshDatasets();
    if (mounted) setState(() => _aboutRevision++);
  }

  Map<String, dynamic>? get _selectedDataset {
    for (final item in _datasets) {
      if (item['name'] == _dataset) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    if (_connecting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || api == null) {
      return _ConnectionError(
        message: _error ?? 'Dataset viewer is unavailable.',
        onRetry: _connect,
      );
    }
    final selected = _selectedDataset;
    final index = selected?['index'] as Map?;
    final building = index?['state'] == 'building';
    final names = (selected?['classes'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 248,
            child: _DatasetRail(
              datasets: _datasets,
              selected: _dataset,
              onSelect: (name) => setState(() => _dataset = name),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DatasetHeader(
                  dataset: selected,
                  refreshing: building,
                  onRefresh: _refreshDatasets,
                ),
                if (building)
                  LinearProgressIndicator(
                    value: _progressValue(index?['progress']),
                    minHeight: 2,
                  ),
                if (selected?['training'] == true)
                  const _InlineNotice(
                    icon: Icons.lock_clock,
                    text:
                        'Training is running. Dataset changes are disabled until it finishes.',
                    color: Color(0xFFDBA64A),
                  ),
                if (selected?['card_stale'] == true)
                  _CardStaleNotice(
                    api: api,
                    dataset: _dataset!,
                    onDone: _reportCompleted,
                  ),
                if (selected == null)
                  const Expanded(
                    child: Center(child: Text('No YOLO datasets were found.')),
                  )
                else if (selected['kind'] == 'reid')
                  Expanded(
                    child: DatasetReidManager(
                      key: const ValueKey('reid-manager'),
                      api: api,
                      onChanged: _refreshDatasets,
                    ),
                  )
                else if (building && selected['total'] == null)
                  Expanded(
                    child: _IndexProgress(
                      dataset: _dataset!,
                      progress: index?['progress'],
                    ),
                  )
                else ...[
                  TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabs: const [
                      Tab(text: 'Gallery'),
                      Tab(text: 'Relabel'),
                      Tab(text: 'Overview'),
                      Tab(text: 'About'),
                      Tab(text: 'Clean'),
                      Tab(text: 'Quarantine'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _GalleryTab(
                          key: ValueKey('gallery-$_dataset'),
                          api: api,
                          dataset: _dataset!,
                          classNames: names,
                          onRefreshDataset: _refreshDatasets,
                        ),
                        DatasetRelabelTab(
                          key: ValueKey('relabel-$_dataset'),
                          api: api,
                          dataset: _dataset!,
                          classNames: names,
                          training: selected['training'] == true,
                          onChanged: _refreshDatasets,
                        ),
                        _OverviewTab(
                          key: ValueKey('overview-$_dataset'),
                          api: api,
                          dataset: _dataset!,
                        ),
                        _AboutTab(
                          key: ValueKey('about-$_dataset-$_aboutRevision'),
                          api: api,
                          dataset: _dataset!,
                        ),
                        _CleanTab(
                          key: ValueKey('clean-$_dataset'),
                          api: api,
                          dataset: _dataset!,
                        ),
                        _QuarantineTab(
                          key: ValueKey('quarantine-$_dataset'),
                          api: api,
                          dataset: _dataset!,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

double? _progressValue(Object? raw) {
  if (raw is! Map) return null;
  final done = raw['done'];
  final total = raw['total'];
  if (done is! num || total is! num || total <= 0) return null;
  return (done / total).clamp(0, 1).toDouble();
}

class _DatasetHeader extends StatelessWidget {
  final Map<String, dynamic>? dataset;
  final bool refreshing;
  final VoidCallback onRefresh;

  const _DatasetHeader({
    required this.dataset,
    required this.refreshing,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final total = dataset?['total'];
    final images = total is num ? _count(total.toInt()) : 'Indexing…';
    final ph = dataset?['ph_share'];
    final warnings = dataset?['warnings'] as List? ?? const [];
    final isReid = dataset?['kind'] == 'reid';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Row(
        children: [
          const Icon(Icons.photo_library_outlined, size: 25),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${dataset?['title'] ?? dataset?['name'] ?? 'Datasets'}',
              style: Theme.of(context).textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 20),
          _Metric(label: isReid ? 'Photos' : 'Images', value: images),
          const SizedBox(width: 18),
          _Metric(
            label: isReid ? 'Car folders' : 'Philippine share',
            value: isReid
                ? '${dataset?['cars'] ?? '—'}'
                : ph is num
                ? '${(ph * 100).round()}%'
                : '—',
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(width: 16),
            Tooltip(
              message:
                  '${warnings.length} validation/test class-balance warnings',
              child: _StatusTag(
                label: '${warnings.length} score warnings',
                color: const Color(0xFFDBA64A),
              ),
            ),
          ],
          if (dataset?['training'] == true) ...[
            const SizedBox(width: 14),
            const _StatusTag(label: 'Training now', color: Color(0xFFDBA64A)),
          ],
          const SizedBox(width: 8),
          IconButton(
            tooltip: refreshing ? 'Refreshing dataset index' : 'Refresh',
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _DatasetRail extends StatelessWidget {
  final List<Map<String, dynamic>> datasets;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _DatasetRail({
    required this.datasets,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 12, 4),
            child: Text(
              'Datasets',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 14),
            child: Text('Training library', style: theme.textTheme.labelMedium),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final item in datasets)
                  _DatasetRailItem(
                    item: item,
                    selected: item['name'] == selected,
                    onTap: () => onSelect('${item['name']}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DatasetRailItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool selected;
  final VoidCallback onTap;

  const _DatasetRailItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final classes = (item['classes'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    final splitCounts = Map<String, dynamic>.from(
      item['images'] as Map? ?? const {},
    );
    final warnings = item['warnings'] as List? ?? const [];
    final total = item['total'];
    final ph = item['ph_share'];
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? Colors.blueAccent : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withAlpha(70),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item['title'] ?? item['name']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item['training'] == true)
                    const Tooltip(
                      message: 'Training now — writes disabled',
                      child: Icon(
                        Icons.lock_clock,
                        size: 16,
                        color: Color(0xFFDBA64A),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                item['kind'] == 'reid'
                    ? '${_count((total as num? ?? 0).toInt())} photos · ${item['cars'] ?? 0} cars'
                    : total is num
                    ? '${_count(total.toInt())} images'
                    : 'Building index…',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              if (item['kind'] == 'reid')
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Clean the cars before training',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              if (ph is num)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Philippine sources ${(ph * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              if (classes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    classes.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              if (splitCounts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    'tr ${splitCounts['train'] ?? 0}   va ${splitCounts['val'] ?? 0}   te ${splitCounts['test'] ?? 0}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              if (warnings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${warnings.length} evaluation warnings',
                    style: const TextStyle(
                      color: Color(0xFFDBA64A),
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _StatusTag extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      border: Border.all(color: color),
      color: color.withAlpha(25),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

class _InlineNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _InlineNotice({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    color: color.withAlpha(24),
    child: Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: color)),
      ],
    ),
  );
}

class _CardStaleNotice extends StatefulWidget {
  final DatasetViewerApi api;
  final String dataset;
  final Future<void> Function() onDone;

  const _CardStaleNotice({
    required this.api,
    required this.dataset,
    required this.onDone,
  });

  @override
  State<_CardStaleNotice> createState() => _CardStaleNoticeState();
}

class _CardStaleNoticeState extends State<_CardStaleNotice> {
  Map<String, dynamic>? _job;
  String? _error;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _job = {'state': 'running', 'text': 'Starting report regeneration…'};
    });
    try {
      final job = await widget.api.startReport(widget.dataset);
      if (!mounted) return;
      setState(() => _job = job);
      if (job['state'] == 'done') {
        await widget.onDone();
      } else if (job['state'] == 'running') {
        _watch('${job['id']}');
      } else {
        setState(
          () => _error = '${job['error'] ?? 'Report regeneration failed.'}',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _watch(String id) {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final job = await widget.api.job(id);
        if (!mounted) return;
        setState(() => _job = job);
        if (job['state'] == 'done') {
          _poll?.cancel();
          await widget.onDone();
        } else if (job['state'] == 'error') {
          _poll?.cancel();
          setState(
            () => _error = '${job['error'] ?? 'Report regeneration failed.'}',
          );
        }
      } catch (error) {
        _poll?.cancel();
        if (mounted) setState(() => _error = '$error');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final running = _job?['state'] == 'running';
    final color = Theme.of(context).colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      color: color.withAlpha(20),
      child: Row(
        children: [
          Icon(Icons.sync_problem_outlined, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error ??
                  (running
                      ? '${_job?['text'] ?? 'Regenerating dataset card…'}'
                      : 'Dataset changed since the card was written.'),
              style: TextStyle(
                color: _error == null
                    ? color
                    : Theme.of(context).colorScheme.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (running)
            const SizedBox(width: 120, child: LinearProgressIndicator())
          else
            TextButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.description_outlined),
              label: Text(_error == null ? 'Regenerate card' : 'Retry'),
            ),
        ],
      ),
    );
  }
}

class _ConnectionError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ConnectionError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 42),
          const SizedBox(height: 12),
          const Text(
            'Could not connect to the dataset service',
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 8),
          SelectableText(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _IndexProgress extends StatelessWidget {
  final String dataset;
  final Object? progress;
  const _IndexProgress({required this.dataset, required this.progress});

  @override
  Widget build(BuildContext context) {
    final map = progress is Map ? progress as Map : const {};
    final text = '${map['text'] ?? 'Reading image and label files'}';
    final done = map['done'];
    final total = map['total'];
    return Center(
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preparing $dataset',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(text),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progressValue(map)),
            const SizedBox(height: 8),
            Text(
              done is num && total is num
                  ? '${_count(done.toInt())} of ${_count(total.toInt())} pictures'
                  : 'The cached index will be ready shortly.',
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryTab extends StatefulWidget {
  final DatasetViewerApi api;
  final String dataset;
  final List<String> classNames;
  final Future<void> Function() onRefreshDataset;

  const _GalleryTab({
    super.key,
    required this.api,
    required this.dataset,
    required this.classNames,
    required this.onRefreshDataset,
  });

  @override
  State<_GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<_GalleryTab> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _facets = const {};
  final Set<String> _selected = {};
  String _split = 'all';
  String _source = 'all';
  String _sort = 'name';
  String _filter = 'all';
  final Set<int> _classes = {};
  bool _showBoxes = true;
  double _thumbnailSize = 220;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _canUndo = false;
  bool _selecting = false;
  String? _error;
  int _request = 0;
  int? _lastSelectedIndex;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 900 &&
        !_loadingMore &&
        _items.length < _total) {
      _loadPage();
    }
  }

  Future<void> _reload() async {
    final id = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
      _lastSelectedIndex = null;
    });
    try {
      final results = await Future.wait([
        widget.api.facets(widget.dataset, split: _split),
        widget.api.items(
          widget.dataset,
          split: _split,
          classes: _classes.toList()..sort(),
          sources: _source == 'all' ? const [] : [_source],
          q: _search.text.trim(),
          sort: _sort,
          filter: _filter,
          offset: 0,
          limit: 150,
        ),
      ]);
      if (!mounted || id != _request) return;
      final items = DatasetViewerApi.maps(results[1]['items']);
      setState(() {
        _facets = results[0];
        _items = items;
        _total = (results[1]['total'] as num?)?.toInt() ?? 0;
        _canUndo = results[1]['can_undo'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _request) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadPage() async {
    if (_loadingMore || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.api.items(
        widget.dataset,
        split: _split,
        classes: _classes.toList()..sort(),
        sources: _source == 'all' ? const [] : [_source],
        q: _search.text.trim(),
        sort: _sort,
        filter: _filter,
        offset: _items.length,
        limit: 150,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...DatasetViewerApi.maps(result['items'])];
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = '$e';
      });
    }
  }

  String _key(Map<String, dynamic> item) => '${item['s']}/${item['n']}';

  Future<void> _mutate(String action) async {
    final selected = _selected.toList();
    if (selected.isEmpty) return;
    final harvest = selected.any(
      (key) => key.split('/').last.startsWith('harvest__'),
    );
    if (harvest) {
      final confirmed = await _confirm(
        context,
        'These are your reviewed pictures. $action them anyway?',
      );
      if (!mounted || !confirmed) return;
    }
    try {
      final keys = selected.map((key) {
        final separator = key.indexOf('/');
        return {
          'split': key.substring(0, separator),
          'name': key.substring(separator + 1),
        };
      }).toList();
      if (action == 'Quarantine') {
        await widget.api.quarantineItems(
          widget.dataset,
          keys,
          confirmHarvest: harvest,
        );
      } else {
        await widget.api.setFlag(widget.dataset, keys, action == 'Flag');
      }
      if (!mounted) return;
      _notice(
        context,
        '$action complete for ${_count(selected.length)} picture${selected.length == 1 ? '' : 's'}.',
      );
      await _reload();
      await widget.onRefreshDataset();
    } catch (e) {
      if (!mounted) return;
      _notice(context, '$e', error: true);
    }
  }

  Future<void> _undo() async {
    try {
      await widget.api.undo(widget.dataset);
      await _reload();
      await widget.onRefreshDataset();
    } catch (e) {
      if (mounted) _notice(context, '$e', error: true);
    }
  }

  Future<void> _selectAll() async {
    if (_selecting) return;
    setState(() => _selecting = true);
    try {
      final result = await widget.api.keys(
        widget.dataset,
        split: _split,
        classes: _classes.toList()..sort(),
        sources: _source == 'all' ? const [] : [_source],
        q: _search.text.trim(),
        sort: _sort,
        filter: _filter,
      );
      if (!mounted) return;
      setState(() {
        _selected.addAll(
          (result['keys'] as List? ?? const []).map(
            (key) => '${key[0]}/${key[1]}',
          ),
        );
        _selecting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _selecting = false);
        _notice(context, '$e', error: true);
      }
    }
  }

  void _selectRange(int index, String key, {bool force = false}) {
    final last = _lastSelectedIndex;
    setState(() {
      if (HardwareKeyboard.instance.isShiftPressed && last != null) {
        final start = math.min(last, index);
        final end = math.max(last, index);
        for (var i = start; i <= end && i < _items.length; i++) {
          _selected.add(_key(_items[i]));
        }
      } else if (_selected.isNotEmpty ||
          force ||
          HardwareKeyboard.instance.isShiftPressed) {
        if (!_selected.add(key)) _selected.remove(key);
        _lastSelectedIndex = index;
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (HardwareKeyboard.instance.isControlPressed &&
        key == LogicalKeyboardKey.keyA) {
      _selectAll();
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed &&
        key == LogicalKeyboardKey.keyZ) {
      _undo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete && _selected.isNotEmpty) {
      _mutate('Quarantine');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF && _selected.isNotEmpty) {
      _mutate('Flag');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB) {
      setState(() => _showBoxes = !_showBoxes);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyO && _selected.length == 1) {
      _revealSelection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _revealSelection() async {
    for (final item in _items) {
      if (_selected.contains(_key(item))) {
        try {
          await widget.api.reveal(
            widget.dataset,
            '${item['s']}',
            '${item['n']}',
          );
        } catch (e) {
          if (mounted) _notice(context, '$e', error: true);
        }
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = (Map<String, dynamic>.from(
      _facets['sources'] as Map? ?? const {},
    )).keys.toList();
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _dropdown(
                  'Split',
                  _split,
                  const ['all', 'train', 'val', 'test'],
                  (v) {
                    _split = v;
                    _reload();
                  },
                ),
                _dropdown('Source', _source, ['all', ...sources], (v) {
                  _source = v;
                  _reload();
                }),
                _dropdown(
                  'Filter',
                  _filter,
                  const [
                    'all',
                    'flagged',
                    'relabeled',
                    'mine',
                    'no_boxes',
                    'many',
                    'tiny',
                  ],
                  (v) {
                    _filter = v;
                    _reload();
                  },
                  labels: const {
                    'all': 'All pictures',
                    'flagged': 'Flagged',
                    'relabeled': 'Relabeled',
                    'mine': 'Harvested (mine)',
                    'no_boxes': 'Has no boxes',
                    'many': 'Many boxes',
                    'tiny': 'Tiny boxes',
                  },
                ),
                _dropdown(
                  'Sort',
                  _sort,
                  const ['name', 'boxes', 'size', 'random'],
                  (v) {
                    _sort = v;
                    _reload();
                  },
                  labels: const {
                    'name': 'Name',
                    'boxes': 'Number of boxes',
                    'size': 'Image size',
                    'random': 'Random',
                  },
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 19),
                      hintText: 'File name',
                      suffixIcon: IconButton(
                        tooltip: 'Search',
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        onPressed: _reload,
                      ),
                    ),
                    onSubmitted: (_) => _reload(),
                  ),
                ),
                Text(
                  '${_count(_total)} pictures',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                FilterChip(
                  avatar: const Icon(Icons.crop_free, size: 17),
                  label: const Text('Boxes (B)'),
                  selected: _showBoxes,
                  onSelected: (value) => setState(() => _showBoxes = value),
                ),
                SizedBox(
                  width: 155,
                  child: Row(
                    children: [
                      const Icon(Icons.photo_size_select_small, size: 17),
                      Expanded(
                        child: Slider(
                          min: 160,
                          max: 340,
                          divisions: 9,
                          value: _thumbnailSize,
                          onChanged: (value) =>
                              setState(() => _thumbnailSize = value),
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _selecting
                      ? null
                      : _selected.isEmpty
                      ? _selectAll
                      : () => setState(_selected.clear),
                  icon: Icon(
                    _selected.isEmpty ? Icons.select_all : Icons.deselect,
                  ),
                  label: Text(
                    _selecting
                        ? 'Selecting…'
                        : _selected.isEmpty
                        ? 'Select all matching'
                        : 'Clear selection',
                  ),
                ),
              ],
            ),
          ),
          if (widget.classNames.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < widget.classNames.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(
                          '${widget.classNames[i]}  ${((Map<String, dynamic>.from(_facets['classes'] as Map? ?? const {}))[('$i')] ?? 0)}',
                        ),
                        selected: _classes.contains(i),
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              _classes.add(i);
                            } else {
                              _classes.remove(i);
                            }
                          });
                          _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
          if (_selected.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${_selected.length} selected'),
                  TextButton.icon(
                    onPressed: () => _mutate('Flag'),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Flag'),
                  ),
                  TextButton.icon(
                    onPressed: () => _mutate('Unflag'),
                    icon: const Icon(Icons.outlined_flag),
                    label: const Text('Unflag'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _mutate('Quarantine'),
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Move to quarantine'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : _items.isEmpty
                ? const Center(child: Text('No pictures match these filters.'))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = (constraints.maxWidth / _thumbnailSize)
                          .floor()
                          .clamp(2, 8);
                      return GridView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(14),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.18,
                        ),
                        itemCount: _items.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _items.length) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final item = _items[index];
                          final key = _key(item);
                          final chosen = _selected.contains(key);
                          return _PictureTile(
                            api: widget.api,
                            dataset: widget.dataset,
                            item: item,
                            classNames: widget.classNames,
                            showBoxes: _showBoxes,
                            selected: chosen,
                            onTap: () async {
                              if (_selected.isNotEmpty ||
                                  HardwareKeyboard.instance.isShiftPressed) {
                                _selectRange(index, key);
                                return;
                              }
                              final changed = await showDialog<bool>(
                                context: context,
                                builder: (_) => _ItemDialog(
                                  api: widget.api,
                                  dataset: widget.dataset,
                                  split: '${item['s']}',
                                  name: '${item['n']}',
                                  classNames: widget.classNames,
                                ),
                              );
                              if (changed == true) {
                                await _reload();
                                await widget.onRefreshDataset();
                              }
                            },
                            onLongPress: () =>
                                _selectRange(index, key, force: true),
                          );
                        },
                      );
                    },
                  ),
          ),
          if (_canUndo)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _undo,
                icon: const Icon(Icons.undo),
                label: const Text('Undo latest change'),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _dropdown(
  String label,
  String value,
  List<String> values,
  ValueChanged<String> onChanged, {
  Map<String, String> labels = const {},
}) {
  final safeValue = values.contains(value) ? value : values.first;
  return DropdownButtonHideUnderline(
    child: DropdownButton<String>(
      value: safeValue,
      hint: Text(label),
      items: [
        for (final v in values)
          DropdownMenuItem(
            value: v,
            child: Text(labels[v] ?? (v == 'all' ? '$label: all' : v)),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );
}

class _PictureTile extends StatelessWidget {
  final DatasetViewerApi api;
  final String dataset;
  final Map<String, dynamic> item;
  final List<String> classNames;
  final bool showBoxes;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PictureTile({
    required this.api,
    required this.dataset,
    required this.item,
    required this.classNames,
    required this.showBoxes,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final boxes = item['b'] as List? ?? const [];
    final ratio = item['w'] is num && item['h'] is num && (item['h'] as num) > 0
        ? (item['w'] as num) / (item['h'] as num)
        : 1.5;
    final split = '${item['s']}';
    final name = '${item['n']}';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: ratio.toDouble(),
                      child: Image.network(
                        api
                            .imageUri(dataset, split, name, thumbnail: true)
                            .toString(),
                        headers: api.endpoint.headers,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xFF242A32),
                          child: Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showBoxes && boxes.isNotEmpty)
                    CustomPaint(painter: _BoxesPainter(boxes, classNames)),
                  if (selected)
                    Container(
                      color: Colors.blueAccent.withAlpha(55),
                      child: const Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: EdgeInsets.all(7),
                          child: Icon(
                            Icons.check_circle,
                            color: Colors.lightBlueAccent,
                          ),
                        ),
                      ),
                    ),
                  Positioned(left: 7, top: 7, child: _SmallTag(label: split)),
                  if (item['flag'] == true)
                    const Positioned(
                      right: 8,
                      top: 8,
                      child: Icon(Icons.flag, color: Colors.amber, size: 18),
                    ),
                  if (item['rl'] == true)
                    const Positioned(
                      right: 8,
                      bottom: 8,
                      child: Tooltip(
                        message: 'Relabeled',
                        child: Icon(
                          Icons.drive_file_rename_outline,
                          color: Colors.lightBlueAccent,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${boxes.length} box${boxes.length == 1 ? '' : 'es'}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoxesPainter extends CustomPainter {
  final List boxes;
  final List<String> classNames;
  _BoxesPainter(this.boxes, this.classNames);

  @override
  void paint(Canvas canvas, Size size) {
    for (final raw in boxes) {
      if (raw is! List || raw.length < 5) continue;
      final classId = (raw[0] as num?)?.toInt() ?? 0;
      final color = _classColor(classId);
      final rect = Rect.fromLTRB(
        ((raw[1] as num).toDouble() - (raw[3] as num).toDouble() / 2) *
            size.width,
        ((raw[2] as num).toDouble() - (raw[4] as num).toDouble() / 2) *
            size.height,
        ((raw[1] as num).toDouble() + (raw[3] as num).toDouble() / 2) *
            size.width,
        ((raw[2] as num).toDouble() + (raw[4] as num).toDouble() / 2) *
            size.height,
      );
      canvas.drawRect(rect, Paint()..color = color.withAlpha(35));
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (classId >= 0 && classId < classNames.length) {
        final label = TextPainter(
          text: TextSpan(
            text: classNames[classId],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelRect = Rect.fromLTWH(
          rect.left.clamp(0, math.max(0, size.width - label.width)).toDouble(),
          (rect.top - label.height).clamp(0, size.height).toDouble(),
          label.width + 6,
          label.height + 3,
        );
        canvas.drawRect(labelRect, Paint()..color = color);
        label.paint(canvas, labelRect.topLeft + const Offset(3, 1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoxesPainter oldDelegate) =>
      oldDelegate.boxes != boxes || oldDelegate.classNames != classNames;
}

class _SmallTag extends StatelessWidget {
  final String label;
  const _SmallTag({required this.label});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: Colors.black.withAlpha(170)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
    ),
  );
}

class _ItemDialog extends StatefulWidget {
  final DatasetViewerApi api;
  final String dataset;
  final String split;
  final String name;
  final List<String> classNames;

  const _ItemDialog({
    required this.api,
    required this.dataset,
    required this.split,
    required this.name,
    required this.classNames,
  });

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  int? _boxIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.item(
        widget.dataset,
        widget.split,
        widget.name,
      );
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<bool> _confirmHarvest() async {
    if (_data?['harvest'] != true) return true;
    return _confirm(
      context,
      'This is one of your reviewed pictures. Change its label anyway?',
    );
  }

  Future<void> _changeBox({int? classId, bool remove = false}) async {
    if (_busy) return;
    if (!await _confirmHarvest() || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.editBox(
        widget.dataset,
        widget.split,
        widget.name,
        _boxIndex!,
        classId: classId,
        remove: remove,
        confirmHarvest: _data?['harvest'] == true,
      );
      if (!mounted) return;
      await _load();
      setState(() {
        _boxIndex = null;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _notice(context, '$e', error: true);
    }
  }

  Future<void> _toggleFlag() async {
    try {
      await widget.api.setFlag(widget.dataset, [
        {'split': widget.split, 'name': widget.name},
      ], !(_data?['flag'] == true));
      await _load();
    } catch (e) {
      if (mounted) _notice(context, '$e', error: true);
    }
  }

  KeyEventResult _onBoxKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_boxIndex == null) {
      if (event.logicalKey == LogicalKeyboardKey.delete) {
        _quarantineImage();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyF) {
        _toggleFlag();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyO) {
        _revealImage();
        return KeyEventResult.handled;
      }
      if (HardwareKeyboard.instance.isControlPressed &&
          event.logicalKey == LogicalKeyboardKey.keyZ) {
        _undoAction();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      _changeBox(remove: true);
      return KeyEventResult.handled;
    }
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final classId = digits.indexOf(event.logicalKey);
    if (classId >= 0 && classId < widget.classNames.length) {
      _changeBox(classId: classId);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _quarantineImage() async {
    final confirmed = await _confirm(
      context,
      'Move this picture to quarantine? It will not be deleted.',
    );
    if (!mounted || !confirmed) return;
    final harvest = _data?['harvest'] == true;
    if (harvest && (!await _confirmHarvest() || !mounted)) return;
    try {
      await widget.api.quarantineItems(widget.dataset, [
        {'split': widget.split, 'name': widget.name},
      ], confirmHarvest: harvest);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _notice(context, '$e', error: true);
    }
  }

  Future<void> _revealImage() async {
    try {
      await widget.api.reveal(widget.dataset, widget.split, widget.name);
    } catch (e) {
      if (mounted) _notice(context, '$e', error: true);
    }
  }

  Future<void> _undoAction() async {
    try {
      await widget.api.undo(widget.dataset);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) _notice(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final size = data?['size'] as List?;
    final ratio = size != null && size.length > 1 && (size[1] as num) > 0
        ? (size[0] as num).toDouble() / (size[1] as num).toDouble()
        : 1.5;
    final boxRows = (data?['boxes'] as List? ?? const []).map((box) {
      final entry = box as Map;
      return [entry['cls'], ...(entry['box'] as List)];
    }).toList();
    return Focus(
      autofocus: true,
      onKeyEvent: _onBoxKey,
      child: Dialog(
        child: SizedBox(
          width: 1050,
          height: 680,
          child: data == null
              ? Center(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : Text(_error!),
                )
              : Row(
                  children: [
                    Expanded(
                      flex: 7,
                      child: Container(
                        color: Colors.black,
                        child: InteractiveViewer(
                          child: AspectRatio(
                            aspectRatio: ratio,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  widget.api
                                      .imageUri(
                                        widget.dataset,
                                        widget.split,
                                        widget.name,
                                      )
                                      .toString(),
                                  headers: widget.api.endpoint.headers,
                                  fit: BoxFit.fill,
                                ),
                                CustomPaint(
                                  painter: _BoxesPainter(
                                    boxRows,
                                    widget.classNames,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 330,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                IconButton(
                                  onPressed: _toggleFlag,
                                  icon: Icon(
                                    data['flag'] == true
                                        ? Icons.flag
                                        : Icons.outlined_flag,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            Text(
                              '${data['split']} · ${data['source']?['id'] ?? 'legacy'}',
                            ),
                            const Divider(height: 24),
                            _metaLine(
                              'Image',
                              '${(data['size'] as List?)?.join(' × ') ?? 'unknown'} px',
                            ),
                            _metaLine(
                              'File size',
                              '${_count((data['bytes'] as num?)?.toInt() ?? 0)} bytes',
                            ),
                            _metaLine(
                              'License',
                              '${data['source']?['license'] ?? 'unknown'}',
                            ),
                            _metaLine(
                              'Country',
                              '${data['source']?['country'] ?? 'unknown'}',
                            ),
                            if (data['label_missing'] == true)
                              const _InlineNotice(
                                icon: Icons.warning_amber,
                                text: 'No label file',
                                color: Color(0xFFDBA64A),
                              ),
                            const SizedBox(height: 14),
                            Text(
                              'Boxes (${(data['boxes'] as List? ?? const []).length})',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: ListView.builder(
                                itemCount:
                                    (data['boxes'] as List? ?? const []).length,
                                itemBuilder: (context, index) {
                                  final box =
                                      (data['boxes'] as List)[index] as Map;
                                  final selected = _boxIndex == index;
                                  final size = box['px'] as List?;
                                  return ListTile(
                                    dense: true,
                                    selected: selected,
                                    onTap: () =>
                                        setState(() => _boxIndex = index),
                                    title: Text('${box['name']}'),
                                    subtitle: Text(
                                      size == null
                                          ? 'Pixel size unavailable'
                                          : '${size[0]} × ${size[1]} px',
                                    ),
                                    trailing: selected
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              PopupMenuButton<int>(
                                                tooltip: 'Change class',
                                                onSelected: (id) =>
                                                    _changeBox(classId: id),
                                                itemBuilder: (_) => [
                                                  for (
                                                    var i = 0;
                                                    i <
                                                        widget
                                                            .classNames
                                                            .length;
                                                    i++
                                                  )
                                                    PopupMenuItem(
                                                      value: i,
                                                      child: Text(
                                                        widget.classNames[i],
                                                      ),
                                                    ),
                                                ],
                                                child: const Icon(
                                                  Icons.edit_outlined,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Remove box',
                                                onPressed: () =>
                                                    _changeBox(remove: true),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                ),
                                              ),
                                            ],
                                          )
                                        : null,
                                  );
                                },
                              ),
                            ),
                            if (_busy) const LinearProgressIndicator(),
                            if (data['harvest'] == true)
                              const Text(
                                'Your reviewed picture — edits require confirmation.',
                                style: TextStyle(
                                  color: Color(0xFFDBA64A),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

Widget _metaLine(String label, String value) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 82,
        child: Text(label, style: const TextStyle(color: Colors.grey)),
      ),
      Expanded(child: Text(value)),
    ],
  ),
);

class _OverviewTab extends StatefulWidget {
  final DatasetViewerApi api;
  final String dataset;
  const _OverviewTab({super.key, required this.api, required this.dataset});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  Map<String, dynamic>? _data;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await widget.api.startSizes(widget.dataset);
      final data = await widget.api.overview(widget.dataset);
      if (!mounted) return;
      setState(() => _data = data);
      final sizes = data['sizes'] as Map?;
      if (sizes?['state'] == 'running') _watchSizes();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _watchSizes() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final data = await widget.api.overview(widget.dataset);
        if (!mounted) return;
        setState(() => _data = data);
        if ((data['sizes'] as Map?)?['state'] != 'running') _poll?.cancel();
      } catch (e) {
        _poll?.cancel();
        if (mounted) setState(() => _error = '$e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Text(_error!),
      );
    }
    final splits = Map<String, dynamic>.from(
      data['images_per_split'] as Map? ?? const {},
    );
    final classes = data['classes'] as List? ?? const [];
    final boxes = Map<String, dynamic>.from(
      data['boxes_per_class'] as Map? ?? const {},
    );
    final warnings = data['warnings'] as List? ?? const [];
    final report = data['report'] as Map?;
    final ph = Map<String, dynamic>.from(data['ph'] as Map? ?? const {});
    final sizeData = data['sizes'] as Map? ?? const {};
    final perSource = Map<String, dynamic>.from(
      data['per_source'] as Map? ?? const {},
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final split in ['train', 'val', 'test'])
              _StatPanel(
                title: '$split pictures',
                value: _count((splits[split] as num?)?.toInt() ?? 0),
              ),
            _StatPanel(
              title: 'Empty pictures',
              value: _count((data['empty'] as num?)?.toInt() ?? 0),
            ),
            _StatPanel(
              title: 'Philippine sources',
              value: _count((ph['ph'] as num?)?.toInt() ?? 0),
            ),
            _StatPanel(
              title: 'Foreign sources',
              value: _count((ph['foreign'] as num?)?.toInt() ?? 0),
            ),
            if (report != null)
              _StatPanel(
                title: 'Curator report',
                value: report['match'] == true ? 'Matches' : 'Differs',
                subtitle: report['when'] as String?,
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Boxes per class and split',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        for (final split in ['train', 'val', 'test'])
          _ClassChart(
            split: split,
            names: classes.map((e) => '$e').toList(),
            counts: (boxes[split] as List? ?? const [])
                .map((e) => (e as num).toInt())
                .toList(),
          ),
        const SizedBox(height: 24),
        Text('Boxes by source', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final entry in perSource.entries)
          _SourceChart(
            name: entry.key,
            images: (entry.value['images'] as num?)?.toInt() ?? 0,
            boxes: (entry.value['boxes'] as List? ?? const [])
                .map((e) => (e as num).toInt())
                .toList(),
            classNames: classes.map((e) => '$e').toList(),
          ),
        const SizedBox(height: 20),
        Text(
          'Boxes per picture',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        _SimpleChart(
          data['boxes_per_image'] as List? ?? const [],
          suffix: 'boxes',
        ),
        const SizedBox(height: 20),
        Text(
          'Box size as share of picture',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        _SimpleChart(data['box_area'] as List? ?? const [], suffix: ''),
        const SizedBox(height: 20),
        Text('Aspect ratios', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _SimpleChart(sizeData['aspect'] as List? ?? const [], suffix: 'images'),
        const SizedBox(height: 8),
        _SimpleChart(
          sizeData['box_aspect'] as List? ?? const [],
          suffix: 'boxes',
        ),
        const SizedBox(height: 24),
        Text(
          'Class-balance warnings',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (warnings.isEmpty) const Text('No class-balance warnings.'),
        for (final warning in warnings)
          ListTile(
            dense: true,
            leading: Icon(
              Icons.warning_amber,
              color: warning['level'] == 'bad'
                  ? Colors.orangeAccent
                  : Colors.amber,
            ),
            title: Text('${warning['text']}'),
          ),
        if (sizeData['state'] == 'running') ...[
          const SizedBox(height: 18),
          LinearProgressIndicator(value: _progressValue(sizeData['progress'])),
          Text(
            'Reading image dimensions: ${_count((sizeData['have'] as num?)?.toInt() ?? 0)} of ${_count((sizeData['of'] as num?)?.toInt() ?? 0)}',
          ),
        ],
        const SizedBox(height: 20),
        Text('Image long side', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _SimpleChart(
          sizeData['long_side'] as List? ?? const [],
          suffix: 'images',
        ),
      ],
    );
  }
}

class _StatPanel extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  const _StatPanel({required this.title, required this.value, this.subtitle});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          if (subtitle != null)
            Text(subtitle!, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ),
  );
}

class _ClassChart extends StatelessWidget {
  final String split;
  final List<String> names;
  final List<int> counts;
  const _ClassChart({
    required this.split,
    required this.names,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    final maxCount = counts.fold<int>(
      1,
      (max, count) => max > count ? max : count,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(split, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 5),
          for (var i = 0; i < names.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(names[i], overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: i < counts.length ? counts[i] / maxCount : 0,
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      _count(i < counts.length ? counts[i] : 0),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SimpleChart extends StatelessWidget {
  final List values;
  final String suffix;
  const _SimpleChart(this.values, {this.suffix = ''});

  @override
  Widget build(BuildContext context) {
    final maxCount = values.fold<int>(1, (max, entry) {
      final count = ((entry as Map)['n'] as num?)?.toInt() ?? 0;
      return math.max(max, count).toInt();
    });
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in values)
          SizedBox(
            width: 145,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry['label']}${suffix.isEmpty ? '' : ' $suffix'}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                LinearProgressIndicator(
                  value: ((entry['n'] as num?)?.toDouble() ?? 0) / maxCount,
                ),
                Text(_count((entry['n'] as num?)?.toInt() ?? 0)),
              ],
            ),
          ),
      ],
    );
  }
}

class _SourceChart extends StatelessWidget {
  final String name;
  final int images;
  final List<int> boxes;
  final List<String> classNames;

  const _SourceChart({
    required this.name,
    required this.images,
    required this.boxes,
    required this.classNames,
  });

  @override
  Widget build(BuildContext context) {
    final total = boxes.fold<int>(0, (sum, n) => sum + n);
    final maxBoxes = boxes.fold<int>(1, (max, n) => max > n ? max : n);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(name),
      subtitle: Text('${_count(images)} images · ${_count(total)} boxes'),
      children: [
        for (var i = 0; i < boxes.length && i < classNames.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(classNames[i], overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: LinearProgressIndicator(value: boxes[i] / maxBoxes),
                ),
                SizedBox(
                  width: 64,
                  child: Text(_count(boxes[i]), textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AboutTab extends StatefulWidget {
  final DatasetViewerApi api;
  final String dataset;
  const _AboutTab({super.key, required this.api, required this.dataset});

  @override
  State<_AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends State<_AboutTab> {
  Map<String, dynamic>? _data;
  String? _error;
  late final TextEditingController _notes = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.about(widget.dataset);
      if (!mounted) return;
      _notes.text = '${data['notes'] ?? ''}';
      setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.api.saveNotes(widget.dataset, _notes.text);
      if (mounted) _notice(context, 'Notes saved.');
    } catch (e) {
      if (mounted) _notice(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Text(_error!),
      );
    }
    final sources = data['sources'] as List? ?? const [];
    final catalog = data['catalog'] as Map?;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(widget.dataset, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        if ('${data['card']}'.trim().isNotEmpty)
          MarkdownBody(
            data: '${data['card']}',
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
                  h1: Theme.of(context).textTheme.headlineSmall,
                  h2: Theme.of(context).textTheme.titleLarge,
                  h3: Theme.of(context).textTheme.titleMedium,
                  p: Theme.of(context).textTheme.bodyMedium,
                  tableBorder: TableBorder.all(
                    color: Theme.of(context).dividerColor,
                  ),
                  tableCellsPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
          )
        else
          const Text('No dataset card found.'),
        const SizedBox(height: 20),
        Text('Classes', style: Theme.of(context).textTheme.titleLarge),
        Wrap(
          spacing: 8,
          children: [
            for (final name in data['classes'] as List? ?? const [])
              Chip(label: Text('$name')),
          ],
        ),
        const SizedBox(height: 20),
        Text('Sources', style: Theme.of(context).textTheme.titleLarge),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Source')),
              DataColumn(label: Text('License')),
              DataColumn(label: Text('Country')),
              DataColumn(label: Text('PH')),
              DataColumn(label: Text('Trust')),
              DataColumn(label: Text('Images')),
            ],
            rows: [
              for (final source in sources)
                DataRow(
                  cells: [
                    DataCell(Text('${source['id'] ?? 'unknown'}')),
                    DataCell(Text('${source['license'] ?? '—'}')),
                    DataCell(Text('${source['country'] ?? '—'}')),
                    DataCell(Text('${source['ph'] ?? '—'}')),
                    DataCell(Text('${source['trust'] ?? '—'}')),
                    DataCell(
                      Text(_count((source['images'] as num?)?.toInt() ?? 0)),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (catalog != null) ...[
          const SizedBox(height: 20),
          Text('Catalog entry', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                for (final heading in catalog['header'] as List? ?? const [])
                  DataColumn(label: Text('$heading')),
              ],
              rows: [
                DataRow(
                  cells: [
                    for (final cell in catalog['row'] as List? ?? const [])
                      DataCell(Text('$cell')),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('Dataset notes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        TextField(
          controller: _notes,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: 'Write notes for this dataset…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save notes'),
          ),
        ),
      ],
    );
  }
}

class _CleanTab extends StatefulWidget {
  final DatasetViewerApi api;
  final String dataset;
  const _CleanTab({super.key, required this.api, required this.dataset});

  @override
  State<_CleanTab> createState() => _CleanTabState();
}

class _CleanTabState extends State<_CleanTab> {
  Map<String, dynamic>? _job;
  bool _running = false;
  String? _error;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start({bool apply = false}) async {
    if (apply &&
        !await _confirm(
          context,
          'Apply the curator’s changes? Pictures will be moved to quarantine and cleaned labels may be rewritten. Nothing is permanently deleted.',
        )) {
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _job = null;
    });
    try {
      final job = apply
          ? await widget.api.applyClean(widget.dataset)
          : await widget.api.startClean(widget.dataset);
      if (!mounted) return;
      setState(() => _job = job);
      _watch('${job['id']}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = '$e';
        });
      }
    }
  }

  void _watch(String id) {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final job = await widget.api.job(id);
        if (!mounted) return;
        setState(() {
          _job = job;
          _running = job['state'] == 'running';
        });
        if (!_running) _poll?.cancel();
      } catch (e) {
        _poll?.cancel();
        if (mounted) {
          setState(() {
            _running = false;
            _error = '$e';
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final result = job?['result'] as Map?;
    final findings = result?['findings'] as Map?;
    final total = (job?['total'] as num?)?.toInt() ?? 0;
    final done = (job?['done'] as num?)?.toInt() ?? 0;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Run the dataset curator',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'The dry run uses the existing cleaning checks and does not change any files.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _running ? null : () => _start(),
              icon: const Icon(Icons.manage_search),
              label: const Text('Run dry check'),
            ),
            OutlinedButton.icon(
              onPressed: _running ? null : () => _start(apply: true),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Apply cleaning…'),
            ),
          ],
        ),
        if (_running) ...[
          const SizedBox(height: 18),
          LinearProgressIndicator(value: total > 0 ? done / total : null),
          const SizedBox(height: 6),
          Text(
            '${job?['text'] ?? 'Starting'}${total > 0 ? ' ($done / $total)' : ''}',
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        if (job?['state'] == 'error')
          Text(
            '${job?['error']}',
            style: const TextStyle(color: Colors.redAccent),
          ),
        if (findings != null) ...[
          const SizedBox(height: 20),
          Text(
            'Dry-run findings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final key in findings.keys)
            ExpansionTile(
              title: Text(_humanize('$key')),
              trailing: Text('${findings[key]['count']}'),
              children: [
                for (final sample
                    in findings[key]['samples'] as List? ?? const [])
                  ListTile(
                    dense: true,
                    leading: SizedBox(
                      width: 72,
                      height: 52,
                      child: Image.network(
                        widget.api
                            .imageUri(
                              widget.dataset,
                              '${sample['split']}',
                              '${sample['name']}',
                              thumbnail: true,
                            )
                            .toString(),
                        headers: widget.api.endpoint.headers,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                    title: Text('${sample['name']}'),
                    subtitle: Text('${sample['split']}'),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

class _QuarantineTab extends StatefulWidget {
  final DatasetViewerApi api;
  final String dataset;
  const _QuarantineTab({super.key, required this.api, required this.dataset});

  @override
  State<_QuarantineTab> createState() => _QuarantineTabState();
}

class _QuarantineTabState extends State<_QuarantineTab> {
  List<Map<String, dynamic>> _reasons = const [];
  List<Map<String, dynamic>> _items = const [];
  final Set<String> _selected = {};
  String? _reason;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadReasons();
  }

  Future<void> _loadReasons() async {
    try {
      final result = await widget.api.quarantine(widget.dataset);
      if (!mounted) return;
      final reasons = DatasetViewerApi.maps(result['reasons']);
      setState(() {
        _reasons = reasons;
        _reason = _reason != null && reasons.any((r) => r['reason'] == _reason)
            ? _reason
            : reasons.isEmpty
            ? null
            : '${reasons.first['reason']}';
      });
      if (_reason != null) {
        await _loadItems();
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _loadItems() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() {
      _loading = true;
      _selected.clear();
    });
    try {
      final result = await widget.api.quarantine(
        widget.dataset,
        reason: reason,
      );
      if (mounted) {
        setState(() {
          _items = DatasetViewerApi.maps(result['items']);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _restore() async {
    final reason = _reason;
    if (reason == null || _selected.isEmpty) return;
    final chosen = _items
        .where((i) => _selected.contains('${i['name']}'))
        .toList();
    final harvest = chosen.any(
      (i) => i['harvest'] == true || '${i['name']}'.startsWith('harvest__'),
    );
    final needsSplit = chosen.any((i) => i['split'] == null);
    String? split;
    if (needsSplit) {
      split = await _chooseSplit(context);
      if (!mounted || split == null) return;
    }
    if (harvest) {
      final confirmed = await _confirm(
        context,
        'Some selected pictures are your reviewed work. Restore them anyway?',
      );
      if (!mounted || !confirmed) return;
    }
    final payload = chosen
        .map((i) => {'name': '${i['name']}', 'split': '${i['split'] ?? split}'})
        .toList();
    setState(() => _busy = true);
    try {
      try {
        await widget.api.restoreItems(
          widget.dataset,
          reason,
          payload,
          confirmHarvest: harvest,
        );
      } on DatasetViewerApiException catch (e) {
        if (e.needsConfirm != 'leak') rethrow;
        if (!mounted) return;
        final confirmLeak = await _confirm(
          context,
          'Restoring these pictures may put the same photo in two splits, making evaluation scores unreliable. Restore anyway?',
        );
        if (!mounted || !confirmLeak) {
          return;
        }
        await widget.api.restoreItems(
          widget.dataset,
          reason,
          payload,
          confirmHarvest: harvest,
          confirmLeak: true,
        );
      }
      if (!mounted) return;
      _notice(
        context,
        'Restored ${chosen.length} picture${chosen.length == 1 ? '' : 's'}.',
      );
      await _loadReasons();
    } catch (e) {
      if (mounted) _notice(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Quarantine reason'),
              SizedBox(
                width: 240,
                child: DropdownButton<String>(
                  value: _reason,
                  isExpanded: true,
                  items: [
                    for (final r in _reasons)
                      DropdownMenuItem(
                        value: '${r['reason']}',
                        child: Text('${r['reason']} (${r['count']})'),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _reason = v);
                    _loadItems();
                  },
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy || _selected.isEmpty ? null : _restore,
                icon: const Icon(Icons.restore),
                label: Text(_busy ? 'Restoring…' : 'Restore selected'),
              ),
            ],
          ),
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? const Center(
                  child: Text('Quarantine is empty for this reason.'),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = (constraints.maxWidth / 220).floor().clamp(
                      2,
                      8,
                    );
                    return GridView.builder(
                      padding: const EdgeInsets.all(14),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.18,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final name = '${item['name']}';
                        final selected = _selected.contains(name);
                        return InkWell(
                          onTap: () => setState(
                            () => selected
                                ? _selected.remove(name)
                                : _selected.add(name),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                widget.api
                                    .quarantineImageUri(
                                      widget.dataset,
                                      _reason!,
                                      name,
                                      thumbnail: true,
                                    )
                                    .toString(),
                                headers: widget.api.endpoint.headers,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                              Positioned(
                                left: 8,
                                right: 8,
                                bottom: 8,
                                child: ColoredBox(
                                  color: Colors.black.withAlpha(180),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Text(
                                      '$name${item['split'] == null ? ' · choose split on restore' : ' · ${item['split']}'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                              if (selected)
                                const Align(
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: EdgeInsets.all(7),
                                    child: Icon(
                                      Icons.check_circle,
                                      color: Colors.lightBlueAccent,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<bool> _confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> _chooseSplit(BuildContext context) => showDialog<String>(
  context: context,
  builder: (context) {
    var split = 'train';
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Choose a split'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The curator did not record the original split. Choose where to restore this picture.',
            ),
            DropdownButton<String>(
              value: split,
              items: const [
                DropdownMenuItem(value: 'train', child: Text('train')),
                DropdownMenuItem(value: 'val', child: Text('val')),
                DropdownMenuItem(value: 'test', child: Text('test')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => split = value);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, split),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  },
);

void _notice(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade800 : null,
    ),
  );
}

String _count(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

String _humanize(String value) => value
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');

Color _classColor(int index) {
  const colors = [
    Color(0xFF7ED7C1),
    Color(0xFFFFB86B),
    Color(0xFF8DAAFF),
    Color(0xFFF58C9A),
    Color(0xFFDAC47A),
    Color(0xFFBA9CF3),
  ];
  return colors[index % colors.length];
}
