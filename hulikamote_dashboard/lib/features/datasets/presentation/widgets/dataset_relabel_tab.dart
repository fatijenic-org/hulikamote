import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hulikamote_dashboard/features/datasets/data/dataset_viewer_api.dart';

class DatasetRelabelTab extends StatefulWidget {
  final DatasetViewerApi api;
  final String dataset;
  final List<String> classNames;
  final bool training;
  final Future<void> Function() onChanged;

  const DatasetRelabelTab({
    super.key,
    required this.api,
    required this.dataset,
    required this.classNames,
    required this.training,
    required this.onChanged,
  });

  @override
  State<DatasetRelabelTab> createState() => _DatasetRelabelTabState();
}

class _DatasetRelabelTabState extends State<DatasetRelabelTab> {
  static const _pageSize = 100;
  String _split = 'all';
  String _source = 'all';
  int? _classFilter;
  int _minBoxPx = 0;
  int _targetClass = 0;
  String _ruleSource = 'all';
  String _ruleSplit = 'all';
  int _ruleFrom = 0;
  int _ruleTo = 0;
  List<String> _sources = const [];
  List<Map<String, dynamic>> _items = const [];
  int _total = 0;
  int _offset = 0;
  bool _loading = true;
  bool _sizesPending = false;
  String? _error;
  Timer? _sizePoll;
  int? _lastSelected;
  final Map<String, Map<String, dynamic>> _selected = {};
  final Map<String, GlobalKey> _tileKeys = {};

  @override
  void initState() {
    super.initState();
    _targetClass = widget.classNames.isEmpty ? 0 : widget.classNames.length - 1;
    _ruleTo = _targetClass;
    _load();
  }

  @override
  void didUpdateWidget(covariant DatasetRelabelTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataset != widget.dataset ||
        oldWidget.classNames != widget.classNames) {
      _split = 'all';
      _source = 'all';
      _classFilter = null;
      _offset = 0;
      _selected.clear();
      _targetClass = widget.classNames.isEmpty
          ? 0
          : widget.classNames.length - 1;
      _ruleFrom = 0;
      _ruleTo = _targetClass;
      _load();
    }
  }

  @override
  void dispose() {
    _sizePoll?.cancel();
    super.dispose();
  }

  String _key(Map<String, dynamic> item) =>
      '${item['split']}/${item['name']}/${item['index']}';

  List<Map<String, Object?>> get _selectedRefs => _selected.values
      .map(
        (item) => <String, Object?>{
          'split': item['split'],
          'name': item['name'],
          'index': item['index'],
        },
      )
      .toList();

  Future<void> _load() async {
    _sizePoll?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final facets = await widget.api.facets(widget.dataset);
      final result = await widget.api.labelItems(
        widget.dataset,
        split: _split,
        source: _source,
        classId: _classFilter,
        minBoxPx: _minBoxPx,
        offset: _offset,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _sources =
            (facets['sources'] as Map? ?? const {}).keys
                .map((source) => '$source')
                .toList()
              ..sort();
        _items = DatasetViewerApi.maps(result['items']);
        _total = (result['total'] as num?)?.toInt() ?? 0;
        _sizesPending = result['size_pending'] == true;
        _loading = false;
      });
      if (_sizesPending) _watchSizes();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  void _watchSizes() {
    _sizePoll?.cancel();
    _sizePoll = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final state = await widget.api.startSizes(widget.dataset);
        if (!mounted) return;
        if (state['state'] == 'ready') {
          _sizePoll?.cancel();
          _load();
        } else if (state['state'] == 'error') {
          _sizePoll?.cancel();
          setState(() {
            _sizesPending = false;
            _error = '${state['error'] ?? 'Could not read image dimensions.'}';
          });
        }
      } catch (error) {
        _sizePoll?.cancel();
        if (mounted) {
          setState(() {
            _sizesPending = false;
            _error = '$error';
          });
        }
      }
    });
  }

  void _selectAt(int index) {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    final key = _key(item);
    setState(() {
      if (HardwareKeyboard.instance.isShiftPressed && _lastSelected != null) {
        final first = math.min(_lastSelected!, index);
        final last = math.max(_lastSelected!, index);
        for (var i = first; i <= last; i++) {
          _selected[_key(_items[i])] = _items[i];
        }
      } else if (_selected.remove(key) == null) {
        _selected[key] = item;
      }
      _lastSelected = index;
    });
  }

  void _dragTo(Offset globalPosition) {
    for (final entry in _tileKeys.entries) {
      final context = entry.value.currentContext;
      if (context == null) continue;
      final render = context.findRenderObject();
      if (render is! RenderBox || !render.hasSize) continue;
      final origin = render.localToGlobal(Offset.zero);
      if ((origin & render.size).contains(globalPosition)) {
        final item = _items.cast<Map<String, dynamic>?>().firstWhere(
          (candidate) => candidate != null && _key(candidate) == entry.key,
          orElse: () => null,
        );
        if (item != null && !_selected.containsKey(entry.key)) {
          setState(() => _selected[entry.key] = item);
        }
        return;
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed &&
        event.logicalKey == LogicalKeyboardKey.keyA) {
      setState(() {
        for (final item in _items) {
          _selected[_key(item)] = item;
        }
      });
      return KeyEventResult.handled;
    }
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) &&
        _selected.length == 1) {
      _showContext(_selected.values.single);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _preview({
    required int targetClass,
    List<Map<String, Object?>>? items,
    Map<String, Object?>? rule,
  }) async {
    try {
      final result = await widget.api.previewRelabel(
        widget.dataset,
        targetClass,
        items: items,
        rule: rule,
      );
      if (!mounted) return;
      if ((result['boxes'] as num? ?? 0) == 0) {
        _message('No boxes need this class change.');
        return;
      }
      final confirmed = await _confirmPreview(result, targetClass);
      if (confirmed != true || !mounted) return;
      final response = await widget.api.relabel(
        widget.dataset,
        targetClass,
        items: items,
        rule: rule,
        confirmHarvest: (result['harvest_count'] as num? ?? 0) > 0,
      );
      if (!mounted) return;
      setState(_selected.clear);
      _message(
        'Relabeled ${response['boxes']} boxes in ${response['pictures']} pictures.',
      );
      await _load();
      await widget.onChanged();
    } catch (error) {
      if (mounted) _message('$error', error: true);
    }
  }

  Future<bool?> _confirmPreview(Map<String, dynamic> preview, int target) {
    final boxes = (preview['boxes'] as num?)?.toInt() ?? 0;
    final pictures = (preview['pictures'] as num?)?.toInt() ?? 0;
    final harvest = (preview['harvest_count'] as num?)?.toInt() ?? 0;
    final samples = DatasetViewerApi.maps(preview['samples']);
    var confirmMine = harvest == 0;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Review label changes'),
            content: SizedBox(
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$boxes boxes in $pictures pictures will be changed to '
                    '${widget.classNames[target]}.',
                  ),
                  if (samples.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('Sample boxes'),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 128,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final sample in samples)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 120,
                                    height: 92,
                                    child: _cropImage(sample),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      '${sample['name']} · box ${((sample['index'] as num?)?.toInt() ?? 0) + 1}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (harvest > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      '$harvest pictures are your reviewed harvest__ images. '
                      'They will be changed only after this extra confirmation.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: confirmMine,
                      title: const Text(
                        'I explicitly approve changing these pictures',
                      ),
                      onChanged: (value) =>
                          setDialogState(() => confirmMine = value == true),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: confirmMine
                    ? () => Navigator.pop(context, true)
                    : null,
                child: const Text('Confirm and relabel'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showContext(Map<String, dynamic> crop) async {
    try {
      final item = await widget.api.item(
        widget.dataset,
        '${crop['split']}',
        '${crop['name']}',
      );
      if (!mounted) return;
      final box =
          (item['boxes'] as List)[(crop['index'] as num).toInt()] as Map;
      final size = item['size'] as List? ?? const [3, 2];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${crop['name']} · ${crop['split']}'),
          content: SizedBox(
            width: 760,
            child: Row(
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: (size[0] as num) / (size[1] as num),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          widget.api
                              .imageUri(
                                widget.dataset,
                                '${crop['split']}',
                                '${crop['name']}',
                              )
                              .toString(),
                          headers: widget.api.endpoint.headers,
                          fit: BoxFit.fill,
                        ),
                        CustomPaint(
                          painter: _HighlightPainter(box['box'] as List),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  width: 150,
                  child: Text(
                    'Box ${((crop['index'] as num).toInt()) + 1}\n'
                    'Current label: ${box['name']}\n'
                    'Source: ${crop['source']}',
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
          ],
        ),
      );
    } catch (error) {
      if (mounted) _message('$error', error: true);
    }
  }

  Widget _cropImage(Map<String, dynamic> item) => Image.network(
    widget.api
        .cropUri(
          widget.dataset,
          '${item['split']}',
          '${item['name']}',
          (item['index'] as num).toInt(),
        )
        .toString(),
    headers: widget.api.endpoint.headers,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) =>
        const Center(child: Icon(Icons.broken_image_outlined)),
  );

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Widget _choice<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => DropdownButtonHideUnderline(
    child: DropdownButton<T>(
      value: value,
      isDense: true,
      hint: Text(label),
      items: items,
      onChanged: onChanged,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final selected = _selected.values.toList();
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Review individual boxes and correct their class labels.',
                ),
                if (widget.training)
                  const Chip(
                    avatar: Icon(Icons.lock_clock, size: 17),
                    label: Text('Writes disabled during training'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _choice<String>(
                  label: 'Split',
                  value: _split,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All splits')),
                    DropdownMenuItem(value: 'train', child: Text('Train')),
                    DropdownMenuItem(value: 'val', child: Text('Val')),
                    DropdownMenuItem(value: 'test', child: Text('Test')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _split = value;
                      _offset = 0;
                      _selected.clear();
                    });
                    _load();
                  },
                ),
                _choice<String>(
                  label: 'Source',
                  value: _source,
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All sources'),
                    ),
                    for (final source in _sources)
                      DropdownMenuItem(value: source, child: Text(source)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _source = value;
                      _offset = 0;
                      _selected.clear();
                    });
                    _load();
                  },
                ),
                _choice<String>(
                  label: 'Class',
                  value: _classFilter?.toString() ?? 'all',
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All classes'),
                    ),
                    for (var i = 0; i < widget.classNames.length; i++)
                      DropdownMenuItem(
                        value: '$i',
                        child: Text(widget.classNames[i]),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _classFilter = value == null || value == 'all'
                          ? null
                          : int.parse(value);
                      _offset = 0;
                      _selected.clear();
                    });
                    _load();
                  },
                ),
                _choice<int>(
                  label: 'Minimum box size',
                  value: _minBoxPx,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Any box size')),
                    DropdownMenuItem(value: 8, child: Text('At least 8 px')),
                    DropdownMenuItem(value: 16, child: Text('At least 16 px')),
                    DropdownMenuItem(value: 32, child: Text('At least 32 px')),
                    DropdownMenuItem(value: 64, child: Text('At least 64 px')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _minBoxPx = value;
                      _offset = 0;
                      _selected.clear();
                    });
                    _load();
                  },
                ),
                Text('${_total.toString()} boxes'),
                TextButton.icon(
                  onPressed: _items.isEmpty
                      ? null
                      : () => setState(() {
                          for (final item in _items) {
                            _selected[_key(item)] = item;
                          }
                        }),
                  icon: const Icon(Icons.select_all),
                  label: const Text('Select page'),
                ),
                if (selected.length == 1)
                  TextButton.icon(
                    onPressed: () => _showContext(selected.single),
                    icon: const Icon(Icons.image_search_outlined),
                    label: const Text('View context'),
                  ),
              ],
            ),
          ),
          if (selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 6),
              child: Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${selected.length} selected'),
                  _choice<int>(
                    label: 'Set class',
                    value: _targetClass,
                    items: [
                      for (var i = 0; i < widget.classNames.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(widget.classNames[i]),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _targetClass = value ?? _targetClass),
                  ),
                  FilledButton.tonal(
                    onPressed: widget.training
                        ? null
                        : () => _preview(
                            targetClass: _targetClass,
                            items: _selectedRefs,
                          ),
                    child: const Text('Preview class change'),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Reading image dimensions…'),
                      ],
                    ),
                  )
                : _error != null
                ? Center(child: Text(_error!))
                : _sizesPending
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? const Center(child: Text('No boxes match these filters.'))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = (constraints.maxWidth / 190)
                          .floor()
                          .clamp(2, 7);
                      return GridView.builder(
                        padding: const EdgeInsets.all(14),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.15,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final key = _key(item);
                          final tileKey = _tileKeys.putIfAbsent(
                            key,
                            GlobalKey.new,
                          );
                          final isSelected = _selected.containsKey(key);
                          return GestureDetector(
                            key: tileKey,
                            onLongPressStart: (_) {
                              _selectAt(index);
                            },
                            onLongPressMoveUpdate: (details) =>
                                _dragTo(details.globalPosition),
                            child: Material(
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                side: BorderSide(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).dividerColor,
                                  width: isSelected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _selectAt(index),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(5),
                                          child: _cropImage(item),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        4,
                                        8,
                                        7,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${item['class_name']}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (item['harvest'] == true)
                                            const Icon(
                                              Icons.person_outline,
                                              size: 16,
                                            ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        0,
                                        8,
                                        6,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${item['name']}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelSmall,
                                            ),
                                          ),
                                          Text(
                                            '${item['split']}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _offset == 0
                      ? null
                      : () {
                          setState(() {
                            _offset = math.max(0, _offset - _pageSize);
                            _selected.clear();
                          });
                          _load();
                        },
                  child: const Text('Previous'),
                ),
                Text(
                  '${_total == 0 ? 0 : _offset + 1}–${math.min(_offset + _pageSize, _total)} of $_total',
                ),
                TextButton(
                  onPressed: _offset + _pageSize >= _total
                      ? null
                      : () {
                          setState(() {
                            _offset += _pageSize;
                            _selected.clear();
                          });
                          _load();
                        },
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
          ExpansionTile(
            title: const Text('Rule-based bulk relabel'),
            subtitle: const Text(
              'Preview all boxes of one class from a source and split before changing them.',
            ),
            childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _choice<String>(
                    label: 'Source',
                    value: _ruleSource,
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('Choose source'),
                      ),
                      for (final source in _sources)
                        DropdownMenuItem(value: source, child: Text(source)),
                    ],
                    onChanged: (value) =>
                        setState(() => _ruleSource = value ?? 'all'),
                  ),
                  _choice<String>(
                    label: 'Split',
                    value: _ruleSplit,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All splits')),
                      DropdownMenuItem(value: 'train', child: Text('Train')),
                      DropdownMenuItem(value: 'val', child: Text('Val')),
                      DropdownMenuItem(value: 'test', child: Text('Test')),
                    ],
                    onChanged: (value) =>
                        setState(() => _ruleSplit = value ?? 'all'),
                  ),
                  _choice<int>(
                    label: 'Current class',
                    value: _ruleFrom,
                    items: [
                      for (var i = 0; i < widget.classNames.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(widget.classNames[i]),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _ruleFrom = value ?? _ruleFrom),
                  ),
                  const Icon(Icons.arrow_forward, size: 18),
                  _choice<int>(
                    label: 'New class',
                    value: _ruleTo,
                    items: [
                      for (var i = 0; i < widget.classNames.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(widget.classNames[i]),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _ruleTo = value ?? _ruleTo),
                  ),
                  FilledButton.tonal(
                    onPressed: widget.training || _ruleSource == 'all'
                        ? null
                        : () => _preview(
                            targetClass: _ruleTo,
                            rule: {
                              'source': _ruleSource,
                              'split': _ruleSplit,
                              'from_class': _ruleFrom,
                            },
                          ),
                    child: const Text('Preview rule'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HighlightPainter extends CustomPainter {
  final List box;
  const _HighlightPainter(this.box);

  @override
  void paint(Canvas canvas, Size size) {
    if (box.length < 4) return;
    final cx = (box[0] as num).toDouble();
    final cy = (box[1] as num).toDouble();
    final width = (box[2] as num).toDouble();
    final height = (box[3] as num).toDouble();
    final rect = Rect.fromLTRB(
      (cx - width / 2) * size.width,
      (cy - height / 2) * size.height,
      (cx + width / 2) * size.width,
      (cy + height / 2) * size.height,
    );
    canvas.drawRect(rect, Paint()..color = Colors.amber.withAlpha(45));
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter oldDelegate) =>
      oldDelegate.box != box;
}
