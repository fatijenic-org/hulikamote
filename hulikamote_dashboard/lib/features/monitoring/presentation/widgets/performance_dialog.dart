import 'dart:async';

import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';

/// "Performance" of the Live Monitor: what the backend is doing right now, so a slow step can be seen.
///
///  - the status strip: CPU, RAM, page file, the backend's own load, and the GPU (load, memory, heat, power, clock);
///  - CPU and GPU load for the last 90 seconds;
///  - a timeline of the last 2.5 seconds: every step the pipeline runs, in its own row, one colour for each step
///    (the row "GPU busy" shows when a GPU step ran);
///  - the average and the worst time of each step, and the device each model runs on.
///
/// The numbers come from GET /settings/live/perf (engine/stage_timer.py and engine/system_stats.py), once every half second while open.
class PerformanceDialog extends StatefulWidget {
  const PerformanceDialog({super.key, required this.api, this.every = const Duration(milliseconds: 500)});

  final CameraApi api;
  final Duration every;

  static Future<void> show(BuildContext context, CameraApi api) =>
      showDialog<void>(context: context, barrierColor: Colors.black38, builder: (_) => PerformanceDialog(api: api));

  @override
  State<PerformanceDialog> createState() => _PerformanceDialogState();
}

class _PerformanceDialogState extends State<PerformanceDialog> {
  Map<String, dynamic>? _data;
  String? _error;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(widget.every, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final data = await widget.api.livePerf();
      if (mounted) setState(() { _data = data; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Fx.panel(context),
      insetPadding: const EdgeInsets.all(Fx.s24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.all(Fx.s16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Performance', style: Fx.title(context)),
              const SizedBox(width: Fx.s12),
              if (_data != null) ..._headChips(context, _data!),
              const Spacer(),
              IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
            ]),
            const SizedBox(height: Fx.s8),
            Expanded(child: _body(context)),
          ]),
        ),
      ),
    );
  }

  List<Widget> _headChips(BuildContext context, Map<String, dynamic> d) {
    final rates = (d['rates'] as Map?) ?? const {};
    final overlap = d['overlap'] == true;
    return [
      _Pill('backend finishes ${_f(rates['produced'])} pictures/s', Fx.accent),
      const SizedBox(width: 6),
      _Pill('screen shows ${_f(rates['pictures'])}/s', Fx.muted(context)),
      const SizedBox(width: 6),
      _Pill('${_f(rates['judged'])} judged/s (1 in ${d['infer_every'] ?? 3})', Fx.muted(context)),
      if ((d['playout'] as Map?)?.isNotEmpty ?? false) ...[
        const SizedBox(width: 6),
        _Pill(_bufferText(d['playout'] as Map), Fx.success),
      ],
      const SizedBox(width: 6),
      _Pill(overlap ? 'work line ON' : 'work line OFF', overlap ? Fx.success : Fx.warning),
    ];
  }

  static String _bufferText(Map b) {
    final speed = (b['speed'] as num?)?.toDouble() ?? 1.0;
    return switch (b['state']) {
      'filling' => 'buffer filling ${(((b['percent'] as num?) ?? 0) * 100).round()}%',
      'done' => 'buffer done',
      _ => 'buffer ${_f(b['ahead_s'])} s${b['live'] == true ? '' : (speed < 0.97 ? ' · slow motion ${speed.toStringAsFixed(2)}×' : ' · normal speed')}',
    };
  }

  Widget _body(BuildContext context) {
    final d = _data;
    if (d == null) {
      return Center(child: _error != null ? Text(_error!, style: Fx.body(context)) : const CircularProgressIndicator());
    }
    final system = (d['system'] as Map?) ?? const {};
    final now = (system['now'] as Map?) ?? const {};
    final history = [for (final h in (system['history'] as List? ?? const [])) (h as List)];
    final info = <String, Map>{for (final e in ((d['step_info'] as Map?) ?? const {}).entries) '${e.key}': (e.value as Map)};
    return ListView(children: [
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Last update failed: $_error', style: Fx.caption(context))),
      _statusStrip(context, now),
      const SizedBox(height: Fx.s12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _chart(context, 'CPU load (all cores)', [for (final h in history) _num(h[0])], Colors.orangeAccent, '%')),
        const SizedBox(width: Fx.s12),
        Expanded(child: _chart(context, 'GPU load', [for (final h in history) _num(h[1])], Colors.lightBlueAccent, '%')),
        const SizedBox(width: Fx.s12),
        Expanded(child: _chart(context, 'Backend: cores busy', [for (final h in history) _num(h[2])], Colors.greenAccent, '', max: _cores(now))),
      ]),
      const SizedBox(height: Fx.s12),
      Text('LAST ${_f(d['window_s'])} SECONDS: EVERY STEP, IN ITS OWN ROW', style: Fx.label(context)),
      const SizedBox(height: 6),
      _timeline(context, d, info),
      const SizedBox(height: 6),
      _legend(context, info),
      const SizedBox(height: Fx.s12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: _stepTable(context, d, info)),
        const SizedBox(width: Fx.s16),
        Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_models(context, d), _startup(context, d)])),
      ]),
    ]);
  }

  /// How the last start went: each step with the seconds since Apply and the seconds the step itself took (a slow one is amber).
  Widget _startup(BuildContext context, Map d) {
    final steps = [for (final e in (((d['startup'] as Map?) ?? const {})['steps'] as List? ?? const [])) (e as Map)];
    if (steps.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: Fx.s12),
      Text('HOW THE LAST START WENT', style: Fx.label(context)),
      const SizedBox(height: 2),
      Text('seconds since Apply · seconds the step took', style: Fx.caption(context)),
      const SizedBox(height: 4),
      for (final e in steps)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(children: [
            Expanded(child: Text('${e['step']}', style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
            Text('${_f(e['at_s'])} s', style: const TextStyle(fontSize: 12.5)),
            SizedBox(
              width: 60,
              child: Text('+${_f(e['took_s'])}', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12.5, color: _num(e['took_s']) > 3 ? Fx.warning : Fx.muted(context))),
            ),
          ]),
        ),
    ]);
  }

  // ── the status strip ──
  Widget _statusStrip(BuildContext context, Map now) {
    final cpu = (now['cpu'] as Map?) ?? const {};
    final ram = (now['ram'] as Map?) ?? const {};
    final swap = (now['swap'] as Map?) ?? const {};
    final be = (now['backend'] as Map?) ?? const {};
    final gpu = now['gpu'] as Map?;
    return Wrap(spacing: Fx.s8, runSpacing: Fx.s8, children: [
      _Stat('CPU', '${_f(cpu['percent'])}%', '${cpu['count'] ?? '?'} threads', _num(cpu['percent']) / 100, Colors.orangeAccent),
      _Stat('RAM', '${_f(ram['used_gb'])} / ${_f(ram['total_gb'])} GB', '${_f(ram['percent'])}% used', _num(ram['percent']) / 100,
          _num(ram['percent']) > 85 ? Fx.danger : Colors.amber),
      _Stat('Page file', '${_f(swap['used_gb'])} / ${_f(swap['total_gb'])} GB', '${_f(swap['percent'])}% used', _num(swap['percent']) / 100, Colors.grey),
      _Stat('Backend', '${_f(be['cpu_cores'])} cores busy', '${_f(be['rss_gb'])} GB RAM · ${be['threads'] ?? '?'} threads', _num(be['cpu_cores']) / _cores(now),
          Colors.greenAccent),
      if (gpu != null) ...[
        _Stat('GPU', '${_f(gpu['util'])}%', '${gpu['pstate'] ?? ''} · ${gpu['clock_mhz'] ?? '?'} / ${gpu['clock_max_mhz'] ?? '?'} MHz', _num(gpu['util']) / 100,
            Colors.lightBlueAccent),
        _Stat('GPU memory', '${_f(gpu['vram_used_mb'] == null ? null : _num(gpu['vram_used_mb']) / 1024)} / ${_f(gpu['vram_total_mb'] == null ? null : _num(gpu['vram_total_mb']) / 1024)} GB',
            'copy engine ${_f(gpu['mem_util'])}%', _num(gpu['vram_used_mb']) / (_num(gpu['vram_total_mb']) == 0 ? 1 : _num(gpu['vram_total_mb'])),
            Colors.lightBlueAccent),
        _Stat('GPU heat', '${gpu['temp_c'] ?? '?'} °C', '${_f(gpu['power_w'])} W of ${gpu['power_limit_w'] ?? '?'} W', _num(gpu['power_w']) / (_num(gpu['power_limit_w']) == 0 ? 1 : _num(gpu['power_limit_w'])),
            Colors.redAccent),
      ] else
        const _Stat('GPU', 'not found', 'no NVIDIA GPU or driver library', 0, Colors.grey),
    ]);
  }

  Widget _chart(BuildContext context, String title, List<double?> values, Color color, String unit, {double max = 100}) {
    final last = values.isEmpty ? null : values.last;
    return Container(
      padding: const EdgeInsets.all(Fx.s8),
      decoration: BoxDecoration(border: Border.all(color: Fx.border(context)), borderRadius: BorderRadius.circular(Fx.radiusSm)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: Fx.caption(context))),
          Text(last == null ? '–' : '${_f(last)}$unit', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        SizedBox(height: 54, width: double.infinity, child: CustomPaint(painter: _SparkPainter(values, color, max <= 0 ? 100 : max, Fx.border(context)))),
      ]),
    );
  }

  // ── the timeline ──
  Widget _timeline(BuildContext context, Map d, Map<String, Map> info) {
    final lanes = [for (final l in (d['lanes'] as List? ?? const [])) {'id': '${(l as Map)['id']}', 'label': '${l['label']}'}];
    final spans = [for (final s in (d['spans'] as List? ?? const [])) (s as Map)];
    final window = _num(d['window_s']) == 0 ? 2.5 : _num(d['window_s']);
    final height = (lanes.length + 1) * 28.0 + 18;
    return Container(
      height: height,
      decoration: BoxDecoration(border: Border.all(color: Fx.border(context)), borderRadius: BorderRadius.circular(Fx.radiusSm)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Fx.radiusSm),
        child: CustomPaint(
          size: Size.infinite,
          painter: _TimelinePainter(lanes: lanes, spans: spans, info: info, window: window, text: Fx.muted(context), line: Fx.border(context)),
        ),
      ),
    );
  }

  Widget _legend(BuildContext context, Map<String, Map> info) {
    return Wrap(spacing: 12, runSpacing: 4, children: [
      for (final e in info.entries)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 11, height: 11, decoration: BoxDecoration(color: _stepColor(e.key), borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text('${e.value['label']}${e.value['res'] == 'gpu' ? ' (GPU)' : ''}', style: Fx.caption(context)),
        ]),
    ]);
  }

  // ── tables ──
  Widget _stepTable(BuildContext context, Map d, Map<String, Map> info) {
    final steps = ((d['steps'] as Map?) ?? const {});
    final rows = <TableRow>[
      TableRow(children: [for (final h in const ['Step', 'avg ms', 'worst ms']) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(h, style: Fx.label(context)))]),
    ];
    String label(String k) => k == 'A' ? 'A: detect + track (total)' : k == 'B' ? 'B: history + rules (total)' : '${info[k]?['label'] ?? k}';
    for (final e in steps.entries) {
      final k = '${e.key}';
      final v = e.value as Map;
      final total = k == 'A' || k == 'B';
      rows.add(TableRow(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            if (!total) Container(width: 9, height: 9, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: _stepColor(k), borderRadius: BorderRadius.circular(2))) else const SizedBox(width: 15),
            Flexible(child: Text(label(k), style: TextStyle(fontSize: 12.5, fontWeight: total ? FontWeight.w700 : FontWeight.w400), overflow: TextOverflow.ellipsis)),
          ]),
        ),
        Text(_f(v['avg_ms']), style: TextStyle(fontSize: 12.5, fontWeight: total ? FontWeight.w700 : FontWeight.w400, color: _num(v['avg_ms']) > 50 ? Fx.warning : null)),
        Text(_f(v['max_ms']), style: const TextStyle(fontSize: 12.5)),
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('STEP TIMES (last ~150 pictures)', style: Fx.label(context)),
      const SizedBox(height: 4),
      Table(columnWidths: const {0: FlexColumnWidth(3), 1: FixedColumnWidth(70), 2: FixedColumnWidth(80)}, children: rows),
    ]);
  }

  Widget _models(BuildContext context, Map d) {
    final models = [for (final m in (d['models'] as List? ?? const [])) (m as Map)];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('WHERE EACH MODEL RUNS', style: Fx.label(context)),
      const SizedBox(height: 4),
      if (models.isEmpty) Text('No model loaded yet. Start monitoring.', style: Fx.caption(context)),
      for (final m in models)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text('${m['name']}', style: const TextStyle(fontSize: 12.5))),
            _Pill('${m['provider']}'.replaceAll('ExecutionProvider', ''), '${m['provider']}'.startsWith('CPU') ? Fx.danger : Fx.success),
          ]),
        ),
      const SizedBox(height: 6),
      Text('A model on CPU is about 10 times slower than on the GPU.', style: Fx.caption(context)),
    ]);
  }

  // ── small helpers ──
  static double _num(Object? v) => v is num ? v.toDouble() : 0.0;
  static String _f(Object? v) => v is num ? (v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)) : '–';
  static double _cores(Map now) => ((now['cpu'] as Map?)?['count'] as num?)?.toDouble() ?? 1.0;
}

/// One colour for each step; the same in the timeline, the legend and the table.
Color _stepColor(String step) => switch (step) {
  'wait' => const Color(0xFF8D99A6),
  'decode' => const Color(0xFFB07A4F),
  'prep' => const Color(0xFFE0883A),
  'detect' => const Color(0xFF2F6FED),
  'nms' => const Color(0xFF7FB2FF),
  'roi' => const Color(0xFF1FB5A8),
  'trackV' => const Color(0xFF8E5BE8),
  'trackP' => const Color(0xFFE35BA8),
  'history' => const Color(0xFF3FAE5A),
  'models' => const Color(0xFF1E3FA8),
  'rules' => const Color(0xFF9BC53D),
  'evidence' => const Color(0xFFE8B923),
  'overlay' => const Color(0xFF38C6E0),
  'encode' => const Color(0xFFE5533D),
  'send' => const Color(0xFFC13DD6),
  _ => const Color(0xFF999999),
};

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.16), border: Border.all(color: color), borderRadius: BorderRadius.circular(999)),
    child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.sub, this.fraction, this.color);
  final String label;
  final String value;
  final String sub;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 196,
    padding: const EdgeInsets.all(Fx.s8),
    decoration: BoxDecoration(border: Border.all(color: Fx.border(context)), borderRadius: BorderRadius.circular(Fx.radiusSm)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: Fx.label(context)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
      Text(sub, style: Fx.caption(context), overflow: TextOverflow.ellipsis),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(value: fraction.isNaN ? 0 : fraction.clamp(0.0, 1.0), minHeight: 5, color: color, backgroundColor: color.withValues(alpha: 0.15)),
      ),
    ]),
  );
}

/// A line of the last values (null = no reading), 0 at the bottom and [max] at the top.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.max, this.grid);
  final List<double?> values;
  final Color color;
  final double max;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = grid..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), gridPaint);
    }
    final points = <Offset>[];
    final n = values.length;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      points.add(Offset(n <= 1 ? size.width : size.width * i / (n - 1), size.height * (1 - (v / max).clamp(0.0, 1.0))));
    }
    if (points.length < 2) return;
    final fill = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) { fill.lineTo(p.dx, p.dy); }
    fill..lineTo(points.last.dx, size.height)..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.18));
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) { line.lineTo(p.dx, p.dy); }
    canvas.drawPath(line, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.8);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.values != values || old.color != color;
}

/// The steps of the last seconds: one row for each part of the pipeline, a block for each step that ran (its start and its length),
/// one colour for each step. The bottom row joins the GPU steps: where it is empty the GPU waited.
class _TimelinePainter extends CustomPainter {
  _TimelinePainter({required this.lanes, required this.spans, required this.info, required this.window, required this.text, required this.line});
  final List<Map<String, String>> lanes;
  final List<Map> spans;
  final Map<String, Map> info;
  final double window;
  final Color text;
  final Color line;

  static const _labelW = 150.0, _laneH = 24.0, _gap = 4.0;

  void _label(Canvas canvas, String s, Offset at, double maxWidth, Color color, {double size = 11.5, FontWeight weight = FontWeight.w400}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight)),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final trackW = size.width - _labelW - 8;
    double x(double seconds) => _labelW + (seconds / window) * trackW;
    final rowBg = Paint()..color = line.withValues(alpha: 0.28);
    final gpu = <List<double>>[];
    for (var i = 0; i <= lanes.length; i++) {
      final y = 4 + i * (_laneH + _gap);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(_labelW, y, trackW, _laneH), const Radius.circular(4)), rowBg);
      _label(canvas, i == lanes.length ? 'GPU busy' : lanes[i]['label']!, Offset(6, y + 5), _labelW - 10, text);
    }
    for (final s in spans) {
      final name = '${s['name']}';
      final meta = info[name];
      if (meta == null) continue;
      final lane = lanes.indexWhere((l) => l['id'] == meta['lane']);
      if (lane < 0) continue;
      final start = (s['start'] as num).toDouble();
      final dur = (s['dur_ms'] as num).toDouble() / 1000;
      final y = 4 + lane * (_laneH + _gap);
      final w = (dur / window * trackW).clamp(1.5, trackW);
      final rect = Rect.fromLTWH(x(start), y + 2, w, _laneH - 4);
      final color = _stepColor(name);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), Paint()..color = color.withValues(alpha: meta['res'] == 'gpu' ? 1.0 : 0.82));
      if (w > 46) {
        canvas.save();
        canvas.clipRect(rect);
        _label(canvas, '${meta['label']}', Offset(rect.left + 3, rect.top + 3), w - 6, Colors.white, size: 10.5, weight: FontWeight.w600);
        canvas.restore();
      }
      if (meta['res'] == 'gpu') gpu.add([start, start + dur]);
    }
    // GPU busy: the GPU steps joined
    gpu.sort((a, b) => a[0].compareTo(b[0]));
    final merged = <List<double>>[];
    for (final g in gpu) {
      if (merged.isNotEmpty && g[0] <= merged.last[1]) {
        if (g[1] > merged.last[1]) merged.last[1] = g[1];
      } else {
        merged.add([g[0], g[1]]);
      }
    }
    final yGpu = 4 + lanes.length * (_laneH + _gap);
    for (final m in merged) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x(m[0]), yGpu + 4, ((m[1] - m[0]) / window * trackW).clamp(1.5, trackW), _laneH - 8), const Radius.circular(3)),
          Paint()..color = const Color(0xFF2F6FED));
    }
    // time marks every half second, "now" at the right edge
    final bottom = 4 + (lanes.length + 1) * (_laneH + _gap);
    for (var t = 0.0; t <= window + 1e-6; t += 0.5) {
      canvas.drawLine(Offset(x(t), 2), Offset(x(t), bottom), Paint()..color = line.withValues(alpha: 0.5)..strokeWidth = 1);
      _label(canvas, t == window ? 'now' : '-${(window - t).toStringAsFixed(1)} s', Offset(x(t) - (t == window ? 10 : 12), bottom + 1), 40, text, size: 9.5);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) => old.spans != spans || old.window != window;
}
