import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/models/violation_config.dart';

/// Pushes the full-screen step-by-step wizard for adding or editing a single
/// violation pipeline (one or more zones). Returns the saved [ViolationConfig],
/// or null if the user cancelled.
Future<ViolationConfig?> showViolationWizard(
  BuildContext context, {
  required String imageUrl,
  required double aspectRatio,
  required List<ViolationKind> availableKinds,
  ViolationConfig? existing,
}) {
  return Navigator.of(context).push<ViolationConfig>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ViolationWizardScreen(
        imageUrl: imageUrl,
        aspectRatio: aspectRatio,
        availableKinds: availableKinds,
        existing: existing,
      ),
    ),
  );
}

enum _Phase { typeSelect, drawRoi, drawArrow, setParams, zoneList, review }

class _ViolationWizardScreen extends StatefulWidget {
  final String imageUrl;
  final double aspectRatio;
  final List<ViolationKind> availableKinds;
  final ViolationConfig? existing;

  const _ViolationWizardScreen({
    required this.imageUrl,
    required this.aspectRatio,
    required this.availableKinds,
    this.existing,
  });

  @override
  State<_ViolationWizardScreen> createState() => _ViolationWizardScreenState();
}

class _ViolationWizardScreenState extends State<_ViolationWizardScreen> {
  ViolationKind? _kind;
  _Phase _phase = _Phase.typeSelect;
  final List<RoiZone> _zones = [];

  // Draft fields for the zone currently being drawn/edited.
  List<Offset> _draftRoi = [];
  List<Offset> _draftArrow = [];
  int _draftTimeLimit = 180;
  int _editingZoneIndex = -1; // -1 = new zone

  final TransformationController _transformCtrl = TransformationController();

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _kind = e.kind;
      _zones.addAll(e.zones.map((z) => z.copy()));
      _phase = e.kind.requiresRoi ? _Phase.zoneList : _Phase.review;
    }
  }

  Offset _normalize(BuildContext ctx, Offset local) {
    final box = ctx.findRenderObject() as RenderBox;
    return Offset(local.dx / box.size.width, local.dy / box.size.height);
  }

  void _selectType(ViolationKind kind) {
    setState(() => _kind = kind);
  }

  void _fromTypeSelectNext() {
    if (_kind == null) return;
    setState(() {
      _phase = _kind!.requiresRoi ? _Phase.drawRoi : _Phase.review;
    });
  }

  void _startNewZone() {
    setState(() {
      _draftRoi = [];
      _draftArrow = [];
      _draftTimeLimit = 180;
      _editingZoneIndex = -1;
      _phase = _Phase.drawRoi;
    });
  }

  void _editZone(int index) {
    final z = _zones[index];
    setState(() {
      _draftRoi = List.from(z.roiPoints);
      _draftArrow = List.from(z.arrowPoints);
      _draftTimeLimit = z.timeLimitSeconds;
      _editingZoneIndex = index;
      _phase = _Phase.drawRoi;
    });
  }

  void _removeZone(int index) {
    setState(() => _zones.removeAt(index));
  }

  void _fromRoiNext() {
    if (_draftRoi.length < 3) return;
    setState(() {
      if (_kind!.requiresArrow) {
        _phase = _Phase.drawArrow;
      } else if (_kind!.requiresTimeLimit) {
        _phase = _Phase.setParams;
      } else {
        _finishZone();
      }
    });
  }

  void _fromArrowNext() {
    if (_draftArrow.length < 2) return;
    setState(() {
      if (_kind!.requiresTimeLimit) {
        _phase = _Phase.setParams;
      } else {
        _finishZone();
      }
    });
  }

  void _finishZone() {
    final zone = RoiZone(
      roiPoints: _draftRoi,
      arrowPoints: _draftArrow,
      timeLimitSeconds: _draftTimeLimit,
    );
    if (_editingZoneIndex >= 0) {
      _zones[_editingZoneIndex] = zone;
    } else {
      _zones.add(zone);
    }
    _phase = _Phase.zoneList;
  }

  void _goBack() {
    switch (_phase) {
      case _Phase.typeSelect:
        Navigator.of(context).pop();
        break;
      case _Phase.drawRoi:
        setState(() {
          _phase = (_zones.isEmpty && _editingZoneIndex == -1)
              ? _Phase.typeSelect
              : _Phase.zoneList;
        });
        break;
      case _Phase.drawArrow:
        setState(() => _phase = _Phase.drawRoi);
        break;
      case _Phase.setParams:
        setState(
          () =>
              _phase = _kind!.requiresArrow ? _Phase.drawArrow : _Phase.drawRoi,
        );
        break;
      case _Phase.zoneList:
        setState(() => _phase = _Phase.typeSelect);
        break;
      case _Phase.review:
        setState(
          () =>
              _phase = _kind!.requiresRoi ? _Phase.zoneList : _Phase.typeSelect,
        );
        break;
    }
  }

  void _save() {
    final config = ViolationConfig(
      id:
          widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      kind: _kind!,
      zones: _zones,
    );
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text(
          _isEditing ? 'Edit ${_kind?.label ?? 'Violation'}' : 'Add Violation',
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(child: _buildPhaseBody()),
      bottomNavigationBar: Container(
        color: Colors.grey[900],
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SafeArea(top: false, child: _buildBottomBar()),
      ),
    );
  }

  Widget _buildBottomBar() {
    switch (_phase) {
      case _Phase.typeSelect:
        return Row(
          children: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white70),
              label: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _kind != null ? _fromTypeSelectNext : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Next'),
              style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent),
            ),
          ],
        );
      case _Phase.drawRoi:
        return Row(
          children: [
            TextButton.icon(
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              label: const Text(
                'Back',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _draftRoi.length >= 3 ? _fromRoiNext : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Next'),
              style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent),
            ),
          ],
        );
      case _Phase.drawArrow:
        return Row(
          children: [
            TextButton.icon(
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              label: const Text(
                'Back',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _draftArrow.length >= 2 ? _fromArrowNext : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Next'),
              style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent),
            ),
          ],
        );
      case _Phase.setParams:
        return Row(
          children: [
            TextButton.icon(
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              label: const Text(
                'Back',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => setState(_finishZone),
              icon: const Icon(Icons.check),
              label: const Text('Save Zone'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        );
      case _Phase.zoneList:
        return Row(
          children: [
            TextButton.icon(
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              label: const Text(
                'Back',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _startNewZone,
              icon: const Icon(Icons.add),
              label: const Text('Add Another Zone'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _zones.isNotEmpty
                  ? () => setState(() => _phase = _Phase.review)
                  : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue'),
              style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent),
            ),
          ],
        );
      case _Phase.review:
        return Row(
          children: [
            TextButton.icon(
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              label: const Text(
                'Back',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Save Violation'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        );
    }
  }

  Widget _buildPhaseBody() {
    switch (_phase) {
      case _Phase.typeSelect:
        return _buildTypeStep();
      case _Phase.drawRoi:
        return _buildCanvasStep(
          instruction:
              'Tap to draw this zone\'s polygon (minimum 3 points). One zone at a time.',
          onTapDown: (ctx, d) {
            setState(() => _draftRoi.add(_normalize(ctx, d.localPosition)));
          },
          onUndo: _draftRoi.isEmpty
              ? null
              : () => setState(() => _draftRoi.removeLast()),
          onClear: _draftRoi.isEmpty
              ? null
              : () => setState(() => _draftRoi.clear()),
          pointCountLabel: '${_draftRoi.length} point(s) plotted',
          drawArrow: false,
        );
      case _Phase.drawArrow:
        return _buildCanvasStep(
          instruction:
              'Tap to plot this zone\'s legal flow direction (minimum 2 points).',
          onTapDown: (ctx, d) {
            setState(() => _draftArrow.add(_normalize(ctx, d.localPosition)));
          },
          onUndo: _draftArrow.isEmpty
              ? null
              : () => setState(() => _draftArrow.removeLast()),
          onClear: _draftArrow.isEmpty
              ? null
              : () => setState(() => _draftArrow.clear()),
          pointCountLabel: '${_draftArrow.length} point(s) plotted',
          drawArrow: true,
        );
      case _Phase.setParams:
        return _buildParamsStep();
      case _Phase.zoneList:
        return _buildZoneListStep();
      case _Phase.review:
        return _buildReviewStep();
    }
  }

  Widget _buildTypeStep() {
    if (widget.availableKinds.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'All violation types have already been added to this session.',
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Select a violation type',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        for (final kind in widget.availableKinds)
          Card(
            color: _kind == kind
                ? Colors.blueAccent.withValues(alpha: 0.25)
                : Colors.grey[900],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: _kind == kind ? Colors.blueAccent : Colors.transparent,
                width: 2,
              ),
            ),
            child: ListTile(
              leading: Icon(kind.icon, color: Colors.white),
              title: Text(
                kind.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                kind.description,
                style: const TextStyle(color: Colors.white54),
              ),
              onTap: () => _selectType(kind),
            ),
          ),
      ],
    );
  }

  Widget _buildCanvasStep({
    required String instruction,
    required bool drawArrow,
    required void Function(BuildContext, TapDownDetails) onTapDown,
    required VoidCallback? onUndo,
    required VoidCallback? onClear,
    required String pointCountLabel,
  }) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.grey[900],
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  instruction,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                pointCountLabel,
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.undo, color: Colors.amber),
                tooltip: 'Undo last point',
                onPressed: onUndo,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                tooltip: 'Clear',
                onPressed: onClear,
              ),
            ],
          ),
        ),
        Expanded(
          child: InteractiveViewer(
            transformationController: _transformCtrl,
            panEnabled: true,
            scaleEnabled: true,
            minScale: 1.0,
            maxScale: 10.0,
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.aspectRatio,
                child: Builder(
                  builder: (ctx) => GestureDetector(
                    onTapDown: (d) => onTapDown(ctx, d),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.network(
                            widget.imageUrl,
                            fit: BoxFit.fill,
                          ),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _WizardCanvasPainter(
                              otherZones: _zones,
                              draftRoi: _draftRoi,
                              draftArrow: _draftArrow,
                              roiActive: !drawArrow,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildParamsStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Dwell time limit for this zone',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'How long a vehicle may remain inside this zone before it is flagged as illegally parked.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text(
              '$_draftTimeLimit seconds',
              style: const TextStyle(color: Colors.greenAccent, fontSize: 28),
            ),
            Slider(
              value: _draftTimeLimit.toDouble(),
              min: 30,
              max: 600,
              divisions: 19,
              label: '$_draftTimeLimit s',
              onChanged: (v) => setState(() => _draftTimeLimit = v.toInt()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneListStep() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${_kind!.label} — Zones (${_zones.length})',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Add zones one at a time — finish a zone\'s box (and arrow, if needed) before starting the next.',
          style: TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 16),
        if (_zones.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No zones yet. Tap "Add Another Zone" below to draw the first one.',
              style: TextStyle(color: Colors.white38),
              textAlign: TextAlign.center,
            ),
          )
        else
          for (int i = 0; i < _zones.length; i++)
            Card(
              color: Colors.grey[900],
              child: ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(
                  'Zone ${i + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  [
                    '${_zones[i].roiPoints.length} ROI points',
                    if (_kind!.requiresArrow)
                      '${_zones[i].arrowPoints.length} arrow points',
                    if (_kind!.requiresTimeLimit)
                      '${_zones[i].timeLimitSeconds}s limit',
                  ].join(' • '),
                  style: const TextStyle(color: Colors.white54),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.edit,
                        color: Colors.white70,
                        size: 18,
                      ),
                      onPressed: () => _editZone(i),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      onPressed: () => _removeZone(i),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildReviewStep() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Review & Save',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: Colors.grey[900],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_kind!.icon, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      _kind!.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 24),
                if (_kind!.requiresRoi)
                  _reviewRow('Zones configured', '${_zones.length}')
                else
                  _reviewRow('Zone', 'Not required for this violation'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws prior saved zones dimmed for context, plus the zone currently being
/// drawn (ROI polygon + a multi-point flow arrow polyline) in full color.
class _WizardCanvasPainter extends CustomPainter {
  final List<RoiZone> otherZones;
  final List<Offset> draftRoi;
  final List<Offset> draftArrow;
  final bool roiActive;

  _WizardCanvasPainter({
    required this.otherZones,
    required this.draftRoi,
    required this.draftArrow,
    required this.roiActive,
  });

  void _drawPolygon(
    Canvas canvas,
    Size size,
    List<Offset> points,
    Color color,
    double opacity,
  ) {
    Offset scale(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    if (points.length < 3) return;
    final path = Path()..moveTo(scale(points.first).dx, scale(points.first).dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(scale(points[i]).dx, scale(points[i]).dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: math.min(1.0, opacity * 3))
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    Offset scale(Offset p) => Offset(p.dx * size.width, p.dy * size.height);

    // Previously saved zones, dimmed for context only.
    for (final z in otherZones) {
      _drawPolygon(canvas, size, z.roiPoints, Colors.grey, 0.15);
    }

    // Active draft zone.
    _drawPolygon(
      canvas,
      size,
      draftRoi,
      roiActive ? Colors.blue : Colors.blueGrey,
      0.3,
    );
    for (final p in draftRoi) {
      canvas.drawCircle(scale(p), 4, Paint()..color = Colors.redAccent);
    }

    if (draftArrow.isNotEmpty) {
      final scaled = draftArrow.map(scale).toList();
      final linePaint = Paint()
        ..color = Colors.greenAccent
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < scaled.length - 1; i++) {
        canvas.drawLine(scaled[i], scaled[i + 1], linePaint);
      }
      for (final p in scaled) {
        canvas.drawCircle(p, 5, Paint()..color = Colors.greenAccent);
      }

      if (scaled.length >= 2) {
        final startPt = scaled[scaled.length - 2];
        final endPt = scaled.last;
        final angle = math.atan2(endPt.dy - startPt.dy, endPt.dx - startPt.dx);
        const arrowLength = 20.0;
        const arrowAngle = 28.0 * (math.pi / 180.0);

        final arrowPath = Path()
          ..moveTo(endPt.dx, endPt.dy)
          ..lineTo(
            endPt.dx - arrowLength * math.cos(angle - arrowAngle),
            endPt.dy - arrowLength * math.sin(angle - arrowAngle),
          )
          ..lineTo(
            endPt.dx - arrowLength * math.cos(angle + arrowAngle),
            endPt.dy - arrowLength * math.sin(angle + arrowAngle),
          )
          ..close();

        canvas.drawPath(arrowPath, Paint()..color = Colors.greenAccent);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
