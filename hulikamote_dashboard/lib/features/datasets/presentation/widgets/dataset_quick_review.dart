import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hulikamote_dashboard/features/datasets/data/dataset_viewer_api.dart';

/// Quick review: look at every truck (or car) box as a small picture, pick the pickups, move on.
/// One job, few buttons. A page is 6 x 5 boxes. "These are pickups" changes the picked ones and writes the rest of the page
/// down as "looked at", so the next page only shows boxes nobody has seen. Train, validation and test boxes are all here: if only
/// the training boxes were fixed the test score would be wrong.
class DatasetQuickReview extends StatefulWidget {
  const DatasetQuickReview({
    super.key,
    required this.api,
    required this.dataset,
    required this.classNames,
    required this.training,
    required this.onChanged,
  });

  final DatasetViewerApi api;
  final String dataset;
  final List<String> classNames;
  final bool training;
  final Future<void> Function() onChanged;

  @override
  State<DatasetQuickReview> createState() => _DatasetQuickReviewState();
}

class _DatasetQuickReviewState extends State<DatasetQuickReview> {
  static const _columns = 6;
  static const _pageSize = 30; // 6 x 5
  static const _target = 'pickup';
  static const _likely = 0.8;

  final FocusNode _focus = FocusNode(debugLabel: 'quick review');
  final Map<String, Map<String, dynamic>> _picked = {};
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic>? _state; // classes, target id
  Map<String, dynamic>? _counts; // reviewed / moved / kept / total of the class on show
  Map<String, dynamic>? _suggest;
  String _from = 'truck';
  bool _bySuggestion = false;
  bool _loading = true;
  bool _busy = false;
  int _offset = 0;
  int _unreviewed = 0;
  int? _last;
  String? _error;
  String? _note;
  Timer? _poll;

  List<String> get _classes => [for (final c in (_state?['classes'] as List? ?? const [])) '$c'];
  int? get _targetId => (_state?['target_id'] as num?)?.toInt();
  int get _fromId => _classes.indexOf(_from);
  bool get _locked => widget.training || (_state?['training'] == true);
  bool get _ready => _targetId != null && _fromId >= 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant DatasetQuickReview old) {
    super.didUpdateWidget(old);
    if (old.dataset != widget.dataset || old.classNames.length != widget.classNames.length) _init();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _focus.dispose();
    super.dispose();
  }

  String _key(Map<String, dynamic> i) => '${i['split']}/${i['name']}/${i['index']}';

  Map<String, Object?> _ref(Map<String, dynamic> i) => {'split': i['split'], 'name': i['name'], 'index': i['index']};

  String _n(num value) {
    final digits = value.toInt().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  // ── loading ──

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await widget.api.reviewState(widget.dataset);
      if (!mounted) return;
      _state = state;
      final counts = Map<String, dynamic>.from(state['counts'] as Map? ?? const {});
      if (!_classes.contains(_from) || !counts.containsKey(_from)) {
        _from = counts.containsKey('truck') ? 'truck' : (counts.keys.isEmpty ? _from : counts.keys.first);
      }
      if (_ready) {
        await _loadPage();
        await _loadSuggest();
      } else if (mounted) {
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

  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var result = await widget.api.labelItems(
        widget.dataset,
        classId: _fromId,
        offset: _offset,
        limit: _pageSize,
        unreviewed: true,
        bySuggestion: _bySuggestion,
      );
      var items = DatasetViewerApi.maps(result['items']);
      if (items.isEmpty && _offset > 0) {
        _offset = 0; // the skipped pages were all that was left: start again from the top
        result = await widget.api.labelItems(widget.dataset,
            classId: _fromId, limit: _pageSize, unreviewed: true, bySuggestion: _bySuggestion);
        items = DatasetViewerApi.maps(result['items']);
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _unreviewed = (result['total'] as num?)?.toInt() ?? 0;
        _counts = result['review'] == null ? _counts : Map<String, dynamic>.from(result['review'] as Map);
        _picked.clear();
        _last = null;
        _loading = false;
      });
      _focus.requestFocus();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
          _items = const [];
        });
      }
    }
  }

  Future<void> _loadSuggest() async {
    try {
      final s = await widget.api.suggestStatus(widget.dataset, _fromId);
      if (!mounted) return;
      setState(() => _suggest = s);
      final running = const {'preparing', 'embedding', 'training'}.contains(s['state']);
      _poll?.cancel();
      if (running) {
        _poll = Timer.periodic(const Duration(seconds: 2), (_) => _loadSuggest());
      }
    } catch (_) {
      // suggestions are optional: the page works without them
    }
  }

  // ── picking ──

  void _toggle(int index) {
    if (index < 0 || index >= _items.length) return;
    setState(() {
      if (HardwareKeyboard.instance.isShiftPressed && _last != null) {
        for (var i = math.min(_last!, index); i <= math.max(_last!, index); i++) {
          _picked[_key(_items[i])] = _items[i];
        }
      } else if (_picked.remove(_key(_items[index])) == null) {
        _picked[_key(_items[index])] = _items[index];
      }
      _last = index;
    });
  }

  void _pickAll() => setState(() {
        for (final i in _items) {
          _picked[_key(i)] = i;
        }
      });

  void _pickLikely() => setState(() {
        for (final i in _items) {
          if (((i['score'] as num?) ?? 0) >= _likely) _picked[_key(i)] = i;
        }
      });

  void _clear() => setState(_picked.clear);

  // ── deciding ──

  Future<void> _decide({required bool pickups}) async {
    if (_busy || _locked || _items.isEmpty || !_ready) return;
    if (pickups && _picked.isEmpty) return;
    final picked = pickups ? [for (final i in _picked.values) _ref(i)] : <Map<String, Object?>>[];
    final page = [for (final i in _items) _ref(i)];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Map<String, dynamic> result;
      try {
        result = await widget.api.decide(widget.dataset, toClass: _targetId!, fromClass: _fromId, picked: picked, page: page);
      } on DatasetViewerApiException catch (e) {
        if (e.needsConfirm != 'harvest') rethrow;
        if (!mounted || await _confirmMine() != true) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        result = await widget.api
            .decide(widget.dataset, toClass: _targetId!, fromClass: _fromId, picked: picked, page: page, confirmHarvest: true);
      }
      if (!mounted) return;
      setState(() {
        _note = '${result['moved']} marked as $_target, ${result['kept']} looked at and kept as $_from.';
        _counts = Map<String, dynamic>.from(result['review'] as Map);
      });
      await widget.onChanged();
      await _loadPage();
      await _loadSuggest();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmMine() => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Some of these are your own pictures'),
          content: const Text('Pictures named harvest__ are your own reviewed work. Change them too?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, change them')),
          ],
        ),
      );

  Future<void> _undo() async {
    if (_busy || _locked) return;
    setState(() => _busy = true);
    try {
      await widget.api.undo(widget.dataset);
      if (!mounted) return;
      setState(() => _note = 'Undid the last page.');
      await widget.onChanged();
      await _loadPage();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _skip() {
    if (_busy || _items.isEmpty) return;
    _offset += _pageSize;
    _loadPage();
  }

  Future<void> _addClass() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add the class 'pickup'?"),
        content: Text('Pickups are inside the truck class today. A new class is added with the next number '
            '(${_classes.length}). The old class numbers do not change. This is refused while a training runs.'),
        actions: [
          TextButton(key: const Key('quick-add-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('quick-add-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Add the class')),
        ],
      ),
    );
    if (sure != true) return;
    setState(() => _busy = true);
    try {
      await widget.api.addClass(widget.dataset, _target);
      await widget.onChanged();
      if (mounted) await _init();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reapply() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-apply my pickup decisions?'),
        content: const Text('Use this after the data was merged again or cleaned. Every box you marked as a pickup is put back. '
            'Boxes you only looked at are not changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('quick-reapply-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Re-apply')),
        ],
      ),
    );
    if (sure != true) return;
    setState(() => _busy = true);
    try {
      final r = await widget.api.reapplyDecisions(widget.dataset);
      final lost = ((r['image_missing'] as num?) ?? 0) + ((r['box_missing'] as num?) ?? 0) + ((r['different_class'] as num?) ?? 0);
      if (mounted) {
        setState(() => _note = 'Put back ${r['applied']} ($_target). ${r['already']} were already right'
            '${lost > 0 ? ', $lost could not be placed.' : '.'}');
      }
      await widget.onChanged();
      if (mounted) await _init();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _findPickups() async {
    setState(() => _error = null);
    try {
      final s = await widget.api.startSuggest(widget.dataset, _fromId);
      if (!mounted) return;
      setState(() => _suggest = s);
      await _loadSuggest();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _setMode(bool bySuggestion) {
    if (_bySuggestion == bySuggestion) return;
    setState(() {
      _bySuggestion = bySuggestion;
      _offset = 0;
    });
    _loadPage();
  }

  void _setFrom(String name) {
    if (_from == name) return;
    setState(() {
      _from = name;
      _offset = 0;
      _bySuggestion = false;
      _suggest = null;
    });
    _loadPage();
    _loadSuggest();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl && key == LogicalKeyboardKey.keyZ) {
      _undo();
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _decide(pickups: true);
    } else if (key == LogicalKeyboardKey.keyN) {
      _decide(pickups: false);
    } else if (key == LogicalKeyboardKey.keyA && !ctrl) {
      _pickAll();
    } else if (key == LogicalKeyboardKey.keyC) {
      _clear();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _skip();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading && _state == null) return const Center(child: CircularProgressIndicator());
    if (_state != null && _targetId == null) return _addClassCard(theme);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(theme),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: Text(_error!, key: const Key('quick-error'), style: TextStyle(color: theme.colorScheme.error)),
          ),
        Expanded(child: _grid(theme)),
        _actions(theme),
      ]),
    );
  }

  Widget _addClassCard(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Step 1: add the class 'pickup'", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('No picture set has a pickup class, so pickups are inside "truck" today. A truck ban must not ticket a pickup, '
              'so the model needs a class of its own.'),
          const SizedBox(height: 14),
          if (_error != null) Text(_error!, key: const Key('quick-error'), style: TextStyle(color: theme.colorScheme.error)),
          if (_locked)
            const Chip(avatar: Icon(Icons.lock_clock, size: 17), label: Text('Writes disabled during training'))
          else
            FilledButton(
              key: const Key('quick-add-class'),
              onPressed: _busy ? null : _addClass,
              child: const Text("Add the class 'pickup'"),
            ),
        ]),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final counts = _counts;
    final reviewed = (counts?['reviewed'] as num?) ?? 0;
    final total = (counts?['total'] as num?) ?? 0;
    final moved = (counts?['moved'] as num?) ?? 0;
    final options = [for (final c in Map<String, dynamic>.from(_state?['counts'] as Map? ?? const {}).keys) c];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Which boxes look like pickups?', style: theme.textTheme.titleMedium),
          if (options.length > 1)
            SegmentedButton<String>(
              key: const Key('quick-class'),
              showSelectedIcon: false,
              segments: [for (final c in options) ButtonSegment(value: c, label: Text('${c[0].toUpperCase()}${c.substring(1)}s'))],
              selected: {_from},
              onSelectionChanged: (s) => _setFrom(s.first),
            ),
          if (_locked) const Chip(avatar: Icon(Icons.lock_clock, size: 17), label: Text('Writes disabled during training')),
          TextButton(key: const Key('quick-reapply'), onPressed: _busy || _locked ? null : _reapply, child: const Text('Re-apply my pickup decisions')),
        ]),
        const SizedBox(height: 8),
        Text('Reviewed ${_n(reviewed)} of ${_n(total)} $_from boxes · ${_n(moved)} marked as $_target',
            key: const Key('quick-counter'), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: total == 0 ? 0 : (reviewed / total).clamp(0.0, 1.0).toDouble(), minHeight: 5),
        const SizedBox(height: 6),
        Text(
          'Pick the pickups, then press Enter. Train, validation and test boxes are all here, so the test score stays honest.',
          style: theme.textTheme.bodySmall,
        ),
        _suggestStrip(theme),
        if (_note != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_note!, key: const Key('quick-note'), style: theme.textTheme.bodySmall)),
      ]),
    );
  }

  Widget _suggestStrip(ThemeData theme) {
    final s = _suggest;
    if (s == null) return const SizedBox.shrink();
    final state = '${s['state']}';
    final running = const {'preparing', 'embedding', 'training'}.contains(state);
    final each = (s['min_each'] as num?)?.toInt() ?? 100;
    final yes = (s['marked_moved'] as num?)?.toInt() ?? 0;
    final no = (s['marked_kept'] as num?)?.toInt() ?? 0;
    final canStart = s['can_start'] == true;
    final accuracy = (s['accuracy'] as num?)?.toDouble();
    Widget body;
    if (running) {
      final done = (s['done'] as num?)?.toDouble() ?? 0;
      final of = (s['total'] as num?)?.toDouble() ?? 0;
      body = Row(children: [
        Expanded(child: Text('${s['message'] ?? 'Working...'}', key: const Key('quick-suggest-busy'))),
        SizedBox(width: 160, child: LinearProgressIndicator(value: of > 0 ? (done / of).clamp(0.0, 1.0) : null)),
      ]);
    } else if (state == 'ready' && ((s['scored'] as num?) ?? 0) > 0) {
      body = Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(accuracy == null
            ? 'Suggestions are ready.'
            : 'Suggestions are ready. On boxes it never saw, it was right ${(accuracy * 100).round()}% of the time.'),
        SegmentedButton<bool>(
          key: const Key('quick-mode'),
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: false, label: Text('In order')), ButtonSegment(value: true, label: Text('Suggested pickups'))],
          selected: {_bySuggestion},
          onSelectionChanged: (v) => _setMode(v.first),
        ),
        TextButton(onPressed: _busy ? null : _findPickups, child: const Text('Update')),
      ]);
    } else {
      body = Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(canStart
            ? 'Enough boxes are marked for a suggestion.'
            : 'For suggestions, mark at least $each pickups and $each that are not (now $yes and $no).',
            key: const Key('quick-suggest-info')),
        FilledButton.tonal(key: const Key('quick-find'), onPressed: canStart && !_busy ? _findPickups : null, child: const Text('Find likely pickups')),
        if (state == 'error') Text('${s['error']}', style: TextStyle(color: theme.colorScheme.error)),
      ]);
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor),
      ),
      child: body,
    );
  }

  Widget _grid(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return Center(
        child: Text(_bySuggestion ? 'No more suggestions.' : 'Everything is reviewed.', key: const Key('quick-done'), style: theme.textTheme.titleMedium),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.2,
      ),
      itemCount: _items.length,
      itemBuilder: (context, index) => _tile(theme, index),
    );
  }

  Widget _tile(ThemeData theme, int index) {
    final item = _items[index];
    final picked = _picked.containsKey(_key(item));
    final score = (item['score'] as num?)?.toDouble();
    final split = '${item['split']}';
    return GestureDetector(
      key: Key('quick-tile-$index'),
      onTap: () => _toggle(index),
      child: Container(
        decoration: BoxDecoration(
          color: picked ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: picked ? theme.colorScheme.primary : theme.dividerColor, width: picked ? 3 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Image.network(
              widget.api.cropUri(widget.dataset, split, '${item['name']}', (item['index'] as num).toInt()).toString(),
              headers: widget.api.endpoint.headers,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
          Positioned(
            left: 4,
            bottom: 4,
            child: _chip(split == 'train' ? 'train' : split, split == 'train' ? Colors.black54 : Colors.deepOrange),
          ),
          if (score != null) Positioned(right: 4, top: 4, child: _chip('${(score * 100).round()}%', Colors.teal)),
          if (picked) Positioned(right: 4, bottom: 4, child: Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 22)),
        ]),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10)),
      );

  Widget _actions(ThemeData theme) {
    final picked = _picked.length;
    final disabled = _busy || _locked || _items.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
      child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton(
          key: const Key('quick-pickups'),
          onPressed: disabled || picked == 0 ? null : () => _decide(pickups: true),
          child: Text(picked == 0 ? 'These are pickups  (Enter)' : '$picked ${picked == 1 ? 'is a pickup' : 'are pickups'}  (Enter)'),
        ),
        OutlinedButton(
          key: const Key('quick-none'),
          onPressed: disabled ? null : () => _decide(pickups: false),
          child: const Text('No pickups here  (N)'),
        ),
        TextButton(key: const Key('quick-all'), onPressed: _items.isEmpty ? null : _pickAll, child: const Text('Pick all on this page  (A)')),
        if (_bySuggestion) TextButton(key: const Key('quick-likely'), onPressed: _items.isEmpty ? null : _pickLikely, child: const Text('Pick the likely ones (80%+)')),
        if (picked > 0) TextButton(key: const Key('quick-clear'), onPressed: _clear, child: const Text('Clear  (C)')),
        TextButton(key: const Key('quick-undo'), onPressed: _busy || _locked ? null : _undo, child: const Text('Undo  (Ctrl+Z)')),
        TextButton(key: const Key('quick-skip'), onPressed: _busy || _items.isEmpty ? null : _skip, child: const Text('Skip  (→)')),
        Text('${_n(_unreviewed)} left', key: const Key('quick-left'), style: theme.textTheme.bodySmall),
      ]),
    );
  }
}
