import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:hulikamote_dashboard/core/constants/api_constants.dart';
import 'package:hulikamote_dashboard/core/utils/app_toast.dart';
import 'package:hulikamote_dashboard/core/utils/visible_poller.dart';
import 'package:hulikamote_dashboard/features/forensic/data/harvest_source.dart';
import 'package:hulikamote_dashboard/features/training/data/dataset_browser.dart';
import 'package:hulikamote_dashboard/features/training/presentation/widgets/training_images_card.dart';
import 'package:hulikamote_dashboard/features/training/presentation/widgets/model_guide_panel.dart';
import 'package:hulikamote_dashboard/features/training/presentation/widgets/model_history_panel.dart';
import 'package:hulikamote_dashboard/features/training/presentation/widgets/training_report_widget.dart';
import 'package:hulikamote_dashboard/features/training/presentation/widgets/training_state_bar.dart';

/// One screen for every trainable model: pick a model on the left, check its data,
/// choose how long to train, press Start. The backend (`/api/train/overview`) says what
/// exists and whether each model has enough data.
///
/// With [modelKey] it is the panel the Models page opens for "Train new version": only that model's data,
/// settings, Start and current run, with no model list, title bar, History or Guide (the page shows the versions).
class TrainingStudioScreen extends StatefulWidget {
  const TrainingStudioScreen({super.key, this.harvest, this.datasets, this.modelKey, this.onRunEnded});

  /// Injected by tests; the app reads the Training Lab's datasets and harvest inbox from disk.
  final HarvestSource? harvest;
  final DatasetBrowser? datasets;

  /// Show only this model (its Studio key, e.g. `primary_anchor`) without the chrome around it.
  final String? modelKey;

  /// A run finished, failed or was paused: the Models page reloads its versions.
  final VoidCallback? onRunEnded;

  @override
  State<TrainingStudioScreen> createState() => _TrainingStudioScreenState();
}

class _ModelInfo {
  final String key, name, kind, purpose, detail, datasetPath;
  final String? hint;
  final int images, recommended;
  final bool canTrain, enough;
  final double? lastTrained;

  _ModelInfo(Map<String, dynamic> j)
      : key = j['key'],
        name = j['name'],
        kind = j['kind'],
        purpose = j['purpose'],
        detail = j['detail'] ?? '',
        datasetPath = j['dataset_path'] ?? '',
        hint = j['hint'],
        images = (j['images'] as num?)?.toInt() ?? 0,
        recommended = (j['recommended'] as num?)?.toInt() ?? 0,
        canTrain = j['can_train'] == true,
        enough = j['enough_for_good_results'] == true,
        lastTrained = (j['last_trained'] as num?)?.toDouble();

  IconData get icon => switch (kind) {
        'ocr' => Icons.text_fields,
        'reid' => Icons.compare,
        'enhancer' => Icons.auto_fix_high,
        _ => Icons.crop_free,
      };
}

class _TrainingStudioScreenState extends State<TrainingStudioScreen> {
  List<_ModelInfo> _models = [];
  String _selected = 'plate_specialist';
  bool _loading = true;
  String? _loadError;

  // Settings (shared across models; each kind reads what it needs)
  double _epochs = 100;
  double _imgsz = 640;
  double _batch = 8;
  bool _autoSplit = true;
  String _ocrEngine = 'easyocr';
  String _preset = 'Balanced';

  // Run state
  String? _taskId;
  String? _runModel;
  String _status = 'idle';
  String _logs = '';
  int _epoch = 0, _totalEpochs = 0;
  Map<String, dynamic>? _result;
  bool _starting = false, _uploading = false;

  // Follows the run while this page is shown. The page stays alive behind the other tabs, and
  // the status answer carries the whole training log (1.5 MB and growing), so asking for it in
  // the background held the backend for a fifth of a second or more every few seconds.
  late final VisiblePoller _poller = VisiblePoller(interval: const Duration(seconds: 3), onTick: _tick, initiallyActive: false);
  int _tab = 0;   // 0 = Train, 1 = History, 2 = Guide
  int _historyVersion = 0;   // bumps when a run ends so the history list reloads

  _ModelInfo? get _model => _models.where((m) => m.key == _selected).firstOrNull;
  bool get _running => _status == 'starting' || _status == 'running';
  bool get _embedded => widget.modelKey != null;

  @override
  void initState() {
    super.initState();
    _selected = widget.modelKey ?? _selected;
    _loadOverview();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.attach(context);
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  Future<void> _loadOverview() async {
    setState(() {
      _loading = _models.isEmpty;
      _loadError = null;
    });
    try {
      final res = await http.get(Uri.parse('${ApiConstants.baseUrl}/api/train/overview'));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final list = (jsonDecode(res.body)['models'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _models = list.map(_ModelInfo.new).toList();
        _loading = false;
      });
      _applyPreset(_preset);
    } catch (e) {
      setState(() {
        _loading = false;
        _loadError = 'Could not load models: $e';
      });
    }
  }

  // --- presets -------------------------------------------------------------
  static const _presetEpochs = {
    'yolo': {'Quick': 30.0, 'Balanced': 100.0, 'Thorough': 200.0},
    'ocr': {'Quick': 20.0, 'Balanced': 50.0, 'Thorough': 100.0},
    'reid': {'Quick': 15.0, 'Balanced': 30.0, 'Thorough': 60.0},
    'enhancer': {'Quick': 50.0, 'Balanced': 200.0, 'Thorough': 400.0},
  };

  void _applyPreset(String preset) {
    final kind = _model?.kind ?? 'yolo';
    setState(() {
      _preset = preset;
      _epochs = _presetEpochs[kind]![preset]!;
      _batch = switch (kind) { 'reid' => 32, 'ocr' => 8, _ => 8 };
    });
  }

  void _select(String key) {
    if (_running) return; // do not switch away from a live run
    setState(() {
      _selected = key;
      _tab = 0;
    });
    _applyPreset(_preset);
  }

  // --- actions ---------------------------------------------------------------
  Future<void> _uploadZip() async {
    final m = _model!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace this model\'s dataset?'),
        content: Text('The ZIP will REPLACE the current data for ${m.name} (${m.detail}). '
            'It must contain images/ and labels/ folders in YOLO format.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Choose ZIP')),
        ],
      ),
    );
    if (ok != true) return;
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null || file.path == null) return;
    setState(() => _uploading = true);
    try {
      final request = http.MultipartRequest('POST', Uri.parse('${ApiConstants.baseUrl}/api/train/upload'));
      request.fields['model_name'] = m.key;
      request.files.add(await http.MultipartFile.fromPath('file', file.path!));
      final response = await request.send();
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      if (mounted) AppToast.show(context, 'Dataset uploaded for ${m.name}.');
      await _loadOverview();
    } catch (e) {
      if (mounted) AppToast.show(context, 'Upload failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Map<String, dynamic> _config(_ModelInfo m) => switch (m.kind) {
        'ocr' => {'task_type': 'ocr', 'model_name': m.key, 'engine': _ocrEngine, 'epochs': _epochs.toInt(), 'batch': _batch.toInt()},
        'reid' => {'task_type': 'reid', 'model_name': m.key, 'epochs': _epochs.toInt(), 'batch': _batch.toInt()},
        'enhancer' => {'task_type': 'enhancer', 'model_name': m.key, 'epochs': _epochs.toInt()},
        _ => {'model_name': m.key, 'epochs': _epochs.toInt(), 'imgsz': _imgsz.toInt(), 'auto_split': _autoSplit},
      };

  /// Opens the terminal Training Lab (the plain menu) in its own window, straight on the model picked here
  /// when it is a detector. It keeps running after the dashboard is closed, so training can go on while
  /// this app's memory is freed.
  Future<void> _openTrainingLab() async {
    try {
      final picked = _model;
      final query = (picked != null && picked.kind == 'yolo') ? '?model=${picked.key}' : '';
      final res = await http.post(Uri.parse('${ApiConstants.baseUrl}/api/train/open-lab$query'));
      if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
      if (mounted) {
        AppToast.show(context, 'Training Lab opened in a new window. You can close the dashboard; training keeps running.');
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'Could not open the Training Lab: $e', isError: true);
    }
  }

  Future<void> _start() async {
    final m = _model!;
    setState(() {
      _starting = true;
      _result = null;
    });
    try {
      final request = http.MultipartRequest('POST', Uri.parse('${ApiConstants.baseUrl}/api/train/start'));
      request.fields['config_json'] = jsonEncode(_config(m));
      final response = await request.send();
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final json = jsonDecode(await response.stream.bytesToString());
      setState(() {
        _taskId = json['task_id'];
        _runModel = m.key;
        _status = 'starting';
        _logs = '';
        _epoch = 0;
        _totalEpochs = _epochs.toInt();
        _starting = false;
        _tab = _runTab;
      });
      _poll();
    } catch (e) {
      setState(() => _starting = false);
      if (mounted) AppToast.show(context, 'Could not start training: $e', isError: true);
    }
  }

  void _poll() => _poller.active = true;

  Future<void> _tick() async {
    final id = _taskId;
    if (id == null) return;
    final res = await http.get(Uri.parse('${ApiConstants.baseUrl}/api/train/status/$id'));
    if (res.statusCode == 404) {
      // The backend restarted and forgot this run (its training process was stopped with it)
      _poller.active = false;
      if (mounted) setState(() => _status = 'lost');
      return;
    }
    if (res.statusCode != 200 || !mounted || id != _taskId) return;
    final j = jsonDecode(res.body);
    setState(() {
      _status = j['status'];
      _logs = j['logs'] ?? '';
      _epoch = (j['current_epoch'] as num?)?.toInt() ?? _epoch;
      _totalEpochs = (j['total_epochs'] as num?)?.toInt() ?? _totalEpochs;
      _result = (j['result'] as Map?)?.cast<String, dynamic>();
    });
    if (_status == 'completed' || _status == 'failed' || _status == 'paused') {
      _poller.active = false;
      setState(() => _historyVersion++);
      _loadOverview();
      widget.onRunEnded?.call();
    }
  }

  /// Show and follow a run started outside the Start button (e.g. Continue).
  void _followRun(String taskId, String modelKey) {
    setState(() {
      _taskId = taskId;
      _runModel = modelKey;
      _status = 'running';
      _logs = '';
      _epoch = 0;
      _tab = _runTab;
    });
    _poll();
  }

  void _dismissRun() => setState(() {
        _poller.active = false;
        _taskId = null;
        _runModel = null;
        _status = 'idle';
        _result = null;
        if (_tab == _runTab) _tab = 0;
      });

  /// Tab index of the "Current run" view (shown next to Train / History / Guide while a run exists).
  static const int _runTab = 3;

  // --- UI ----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_embedded) {
      return Material(
        color: Colors.transparent,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!, style: const TextStyle(color: Colors.redAccent)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _loadOverview, child: const Text('Retry')),
                  ]))
                : _model == null ? const SizedBox() : _detail(_model!),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Training Studio'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.terminal),
            label: const Text('Open Training Lab (terminal)'),
            onPressed: _openTrainingLab,
          ),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh data counts', onPressed: _running ? null : _loadOverview),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_loadError!, style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _loadOverview, child: const Text('Retry')),
                ]))
              : Row(children: [
                  SizedBox(width: 340, child: _modelList()),
                  const VerticalDivider(width: 1),
                  Expanded(child: _model == null ? const SizedBox() : _detail(_model!)),
                ]),
    );
  }

  Widget _modelList() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final m in _models)
          Card(
            color: m.key == _selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15) : null,
            child: ListTile(
              selected: m.key == _selected,
              leading: Icon(m.icon),
              title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(m.detail),
              trailing: m.canTrain
                  ? Icon(m.enough ? Icons.check_circle : Icons.warning_amber_rounded,
                      color: m.enough ? Colors.green : Colors.orange)
                  : const Icon(Icons.block, color: Colors.grey),
              onTap: () => _select(m.key),
            ),
          ),
      ],
    );
  }

  Widget _detail(_ModelInfo m) {
    final hasRun = _taskId != null && _runModel == m.key;
    final tab = (_tab == _runTab && !hasRun) ? 0 : _tab;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (!_embedded) ...[
          Row(children: [
            Icon(m.icon, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Text(m.name, style: Theme.of(context).textTheme.headlineSmall)),
          ]),
          const SizedBox(height: 4),
          Text(m.purpose, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
        ],
        // Pause / Continue, for any training of this model (the Models page shows it above the versions instead)
        if (m.kind == 'yolo' && !_embedded) TrainingStateBar(modelKey: m.key, onResumed: (id) => _followRun(id, m.key)),
        // Always visible, so History / Guide stay reachable during and after a run
        if (!_embedded || hasRun)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SegmentedButton<int>(
              segments: [
                if (hasRun)
                  ButtonSegment(
                    value: _runTab,
                    icon: Icon(_running ? Icons.hourglass_top : Icons.flag),
                    label: Text(_running ? 'Current run' : 'Last run'),
                  ),
                const ButtonSegment(value: 0, icon: Icon(Icons.tune), label: Text('Train')),
                if (!_embedded) const ButtonSegment(value: 1, icon: Icon(Icons.history), label: Text('History')),
                if (!_embedded) const ButtonSegment(value: 2, icon: Icon(Icons.menu_book), label: Text('Guide')),
              ],
              selected: {tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
          ),
        if (tab == _runTab)
          _runPanel(m)
        else if (tab == 2)
          ModelGuidePanel(key: ValueKey('guide-${m.key}'), modelKey: m.key)
        else if (tab == 1)
          ModelHistoryPanel(key: ValueKey('${m.key}-$_historyVersion'), modelKey: m.key, kind: m.kind)
        else ...[
          _dataCard(m),
          const SizedBox(height: 16),
          // The pictures of THIS model, to look at: the original dataset and the harvested ones, apart
          TrainingImagesCard(
            key: ValueKey('pictures-${m.key}'),
            modelKey: m.key,
            harvest: widget.harvest,
            datasets: widget.datasets,
            onOpenHarvest: () => context.go('/forensic-analyzer?tab=harvest'),
          ),
          const SizedBox(height: 16),
          _settingsCard(m),
          const SizedBox(height: 20),
          _startButton(m),
          if (_embedded) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('How training works'),
              children: [ModelGuidePanel(key: ValueKey('guide-${m.key}'), modelKey: m.key)],
            ),
          ],
        ],
      ],
    );
  }

  Widget _dataCard(_ModelInfo m) {
    final Color chip = !m.canTrain ? Colors.grey : (m.enough ? Colors.green : Colors.orange);
    final String label = !m.canTrain ? 'Not enough data' : (m.enough ? 'Ready' : 'Usable, but small');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('1. Training data', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            Chip(label: Text(label), backgroundColor: chip.withValues(alpha: 0.2), side: BorderSide(color: chip)),
          ]),
          const SizedBox(height: 8),
          Text('${m.detail}  -  folder: ${m.datasetPath}'),
          Text('Recommended for good results: ${m.recommended}+ images', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          if (m.hint != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(m.hint!, style: const TextStyle(color: Colors.orange)),
          ),
          if (m.canTrain && !m.enough)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('You can train now, but with this little data the result may be weak.', style: TextStyle(color: Colors.orange)),
            ),
          if (m.lastTrained != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Last trained: ${DateTime.fromMillisecondsSinceEpoch((m.lastTrained! * 1000).toInt()).toString().split('.')[0]}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          if (m.kind == 'yolo') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: _uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file),
              label: const Text('Replace dataset with a ZIP...'),
              onPressed: _uploading ? null : _uploadZip,
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Data is collected automatically from your review work; no upload needed.',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
        ]),
      ),
    );
  }

  Widget _settingsCard(_ModelInfo m) {
    final (double eMin, double eMax) = switch (m.kind) {
      'ocr' => (10.0, 200.0),
      'reid' => (5.0, 150.0),
      'enhancer' => (20.0, 600.0),
      _ => (10.0, 500.0),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('2. How long to train', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (final p in const ['Quick', 'Balanced', 'Thorough'])
              ChoiceChip(label: Text(p), selected: _preset == p, onSelected: (_) => _applyPreset(p)),
          ]),
          const SizedBox(height: 4),
          Text('${_epochs.toInt()} passes over the data. More passes = smarter but slower.',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Advanced settings'),
            children: [
              Align(alignment: Alignment.centerLeft, child: Text('Passes (epochs): ${_epochs.toInt()}')),
              Slider(
                value: _epochs.clamp(eMin, eMax),
                min: eMin,
                max: eMax,
                onChanged: (v) => setState(() {
                  _epochs = v.roundToDouble();
                  _preset = 'Custom';
                }),
              ),
              if (m.kind == 'yolo') ...[
                Align(alignment: Alignment.centerLeft, child: Text('Image size: ${_imgsz.toInt()}px (match your dataset)')),
                Slider(value: _imgsz, min: 320, max: 1280, divisions: 15, onChanged: (v) => setState(() => _imgsz = v)),
                SwitchListTile(
                  title: const Text('Auto-split into train / validation (80/20)'),
                  value: _autoSplit,
                  onChanged: (v) => setState(() => _autoSplit = v),
                ),
              ],
              if (m.kind == 'ocr') ...[
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'OCR engine', border: OutlineInputBorder()),
                  value: _ocrEngine,
                  items: const [
                    DropdownMenuItem(value: 'easyocr', child: Text('EasyOCR (standard)')),
                    DropdownMenuItem(value: 'paddleocr', child: Text('PaddleOCR (enterprise)')),
                  ],
                  onChanged: (v) => setState(() => _ocrEngine = v!),
                ),
                const SizedBox(height: 8),
              ],
              if (m.kind == 'ocr' || m.kind == 'reid') ...[
                Align(alignment: Alignment.centerLeft, child: Text('Batch size: ${_batch.toInt()}')),
                Slider(value: _batch.clamp(1, 64), min: 1, max: 64, divisions: 63, onChanged: (v) => setState(() => _batch = v)),
              ],
            ],
          ),
          if (m.kind == 'reid')
            const Text('The new car-matching model is saved as a new version. It goes live only when you press Use this on the Models page.',
                style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
          if (m.kind == 'enhancer')
            const Text('Experimental: installs extra packages and can fail on newer PyTorch versions.',
                style: TextStyle(color: Colors.orange, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _startButton(_ModelInfo m) {
    final busy = _starting || _running;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: _starting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.play_arrow),
          label: Text(m.canTrain ? 'Start training' : 'Not enough data to train'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          onPressed: (!m.canTrain || busy) ? null : _start,
        ),
      ),
      if (_taskId != null && _runModel != m.key && !_embedded)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextButton(onPressed: () => setState(() => _selected = _runModel!), child: const Text('A different model is training. View it.')),
        ),
    ]);
  }

  Widget _runPanel(_ModelInfo m) {
    final failed = _status == 'failed';
    final done = _status == 'completed';
    final lost = _status == 'lost';
    final paused = _status == 'paused';
    final progress = (_totalEpochs > 0) ? (_epoch / _totalEpochs).clamp(0.0, 1.0) : null;
    final color = (lost || paused) ? Colors.orange : failed ? Colors.redAccent : (done ? Colors.green : Colors.blueAccent);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(paused ? Icons.pause_circle : lost ? Icons.link_off : failed ? Icons.error : (done ? Icons.check_circle : Icons.hourglass_top), color: color),
              const SizedBox(width: 8),
              Text(paused ? 'Paused' : lost ? 'Run no longer tracked' : failed ? 'Training failed' : (done ? 'Training finished' : 'Training in progress...'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            ]),
            const SizedBox(height: 12),
            if (lost)
              const Text('The backend restarted, which also stopped this training. Its best epoch so far is kept: '
                  'continue it with "Resume" in the Training Lab (terminal), or see it under History.'),
            if (paused)
              const Text('Stopped on request. Press Continue (above) to resume from the last finished epoch.'),
            if (!done && !failed && !lost && !paused) LinearProgressIndicator(value: _epoch > 0 ? progress : null),
            if (!done && !failed && !lost && !paused && _epoch > 0)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('Pass $_epoch of $_totalEpochs')),
            if (done && _result != null) _reidResult(_result!),
            if (failed) const Text('Open the log below to see what went wrong.', style: TextStyle(color: Colors.redAccent)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      ExpansionTile(
        initiallyExpanded: failed,
        title: const Text('Training log'),
        children: [
          Container(
            height: 280,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(_logs.isEmpty ? 'Waiting for output...' : _logs,
                  style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent, fontSize: 12)),
            ),
          ),
        ],
      ),
      if ((done || _running) && m.kind == 'yolo') ...[
        const SizedBox(height: 16),
        TrainingReportWidget(modelName: m.key),
      ],
      if (done || failed || lost || paused) ...[
        const SizedBox(height: 16),
        Row(children: [
          FilledButton.icon(icon: const Icon(Icons.close), label: const Text('Close this run'), onPressed: _dismissRun),
          if (done && (m.kind == 'ocr' || m.kind == 'enhancer')) ...[
            const SizedBox(width: 12),
            const Expanded(child: Text('Restart the backend so it loads any newly deployed model.', style: TextStyle(color: Colors.grey))),
          ] else if (done) ...[
            const SizedBox(width: 12),
            const Expanded(child: Text('It is a new version. Close this and press Use this on the Models page when you want it live.',
                style: TextStyle(color: Colors.grey))),
          ],
        ]),
      ],
    ]);
  }

  Widget _reidResult(Map<String, dynamic> r) {
    final checked = r['before'] != null && r['after'] != null;
    final before = ((r['before'] as num?) ?? 0) * 100;
    final after = ((r['after'] as num?) ?? 0) * 100;
    final passed = r['passed'] == true;
    final note = r['note'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(checked
          ? 'Finds the right car: ${before.toStringAsFixed(1)}%  ->  ${after.toStringAsFixed(1)}%  '
              '(tested on ${r['held_out_cars'] ?? r['cars']} cars it never saw)'
          : 'Trained on ${r['cars']} cars: too few to test on cars it never saw.'),
      const SizedBox(height: 4),
      // Training no longer switches the model on: it is a new version, and the Models page does the switching
      Text(passed ? 'Passed the check. Saved as a new version: press Use this on the Models page to switch to it.'
              : 'Did not pass the check: ${note ?? 'the new model was not better than the current one.'} It is still saved as a version.',
          style: TextStyle(color: passed ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
    ]);
  }
}
