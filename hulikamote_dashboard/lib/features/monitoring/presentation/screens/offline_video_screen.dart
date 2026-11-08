import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hulikamote_dashboard/core/utils/app_toast.dart';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../../../core/constants/api_constants.dart';
import '../../domain/models/violation_config.dart';
import '../widgets/video_feed_widget.dart';
import '../widgets/alert_list_widget.dart';
import '../widgets/violation_wizard_dialog.dart';

class OfflineVideoScreen extends StatefulWidget {
  const OfflineVideoScreen({super.key});

  @override
  State<OfflineVideoScreen> createState() => _OfflineVideoScreenState();
}

class _OfflineVideoScreenState extends State<OfflineVideoScreen> {
  WebSocketChannel? _channel;
  Stream<dynamic>? _broadcastStream;

  bool _isFileImported = false;
  bool _isPlaying = false;
  double _videoPosition = 0.0;
  double _videoDuration = 60.0;
  double _aspectRatio = 16.0 / 9.0;
  double _videoWidth = 1280.0;
  double _videoHeight = 720.0;
  String _videoPath = '';
  String _frameImageUrl = '';
  String _selectedModel = 'yolov8n.onnx';
  List<String> _availableModels = const ['yolov8n.onnx'];

  // Plate detection method dropdown options
  String _plateDetectionMethod = 'Disabled';
  final List<String> _plateDetectionMethods = [
    'Disabled',
    'Smart Detection (AI Box)',
    'Direct OCR (Bumper Scan)'
  ];

  String _trackerType = 'bytetrack';

  // Each configured violation owns its own independent ROI/arrow geometry so
  // Counterflow and Illegal Parking zones never clash by sharing one polygon.
  final List<ViolationConfig> _violations = [];

  List<ViolationKind> get _kindsNotYetAdded => ViolationKind.values
      .where((k) => !_violations.any((v) => v.kind == k))
      .toList();

  Future<void> _loadAvailableModels() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/settings/models'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = List<String>.from(data['models'] ?? const []);
        if (models.isNotEmpty) {
          setState(() {
            _availableModels = models;
            if (!_availableModels.contains(_selectedModel)) {
              _selectedModel = _availableModels.first;
            }
          });
        }
      }
    } catch (_) {
      // Ignore model list load failure and fall back to default list.
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAvailableModels();
  }

  Future<void> _importFile() async {
    PlatformFile? file = await FilePicker.pickFile(type: FileType.video);
    if (file != null && file.path != null) {
      double dur = 60.0;
      double aspect = 16.0 / 9.0;
      double vw = 1280.0;
      double vh = 720.0;
      try {
        final res = await http.get(
          Uri.parse(
            '${ApiConstants.baseUrl}/settings/video/info?path=${Uri.encodeComponent(file.path!)}',
          ),
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['duration'] != null) {
            dur = (data['duration'] as num).toDouble();
          }
          if (data['aspect_ratio'] != null) {
            aspect = (data['aspect_ratio'] as num).toDouble();
          }
          if (data['width'] != null) {
            vw = (data['width'] as num).toDouble();
          }
          if (data['height'] != null) {
            vh = (data['height'] as num).toDouble();
          }
        }
      } catch (_) {}

      setState(() {
        _videoPath = file.path!;
        _videoDuration = dur;
        _aspectRatio = aspect;
        _videoWidth = vw;
        _videoHeight = vh;
        _isFileImported = true;
        _isPlaying = false;
        _videoPosition = 0.0;
        _violations.clear();
        _plateDetectionMethod = 'Disabled';
        _updateFrameImage();
      });
    }
  }

  void _updateFrameImage() {
    setState(() {
      _frameImageUrl =
          '${ApiConstants.baseUrl}/settings/video/frame?path=${Uri.encodeComponent(_videoPath)}&second=${_videoPosition.toInt()}&t=${DateTime.now().millisecondsSinceEpoch}';
    });
  }

  Future<void> _addViolation() async {
    if (_frameImageUrl.isEmpty) return;
    if (_kindsNotYetAdded.isEmpty) {
      AppToast.show(context, 'All violation types have already been added.', isError: false);
      return;
    }
    final result = await showViolationWizard(
      context,
      imageUrl: _frameImageUrl,
      aspectRatio: _aspectRatio,
      availableKinds: _kindsNotYetAdded,
    );
    if (result != null) {
      setState(() => _violations.add(result));
    }
  }

  Future<void> _editViolation(ViolationConfig cfg) async {
    final result = await showViolationWizard(
      context,
      imageUrl: _frameImageUrl,
      aspectRatio: _aspectRatio,
      availableKinds: const [],
      existing: cfg,
    );
    if (result != null) {
      setState(() {
        final idx = _violations.indexWhere((v) => v.id == cfg.id);
        if (idx != -1) _violations[idx] = result;
      });
    }
  }

  void _removeViolation(String id) {
    setState(() => _violations.removeWhere((v) => v.id == id));
  }

  Map<String, dynamic> _buildRoiPayload() {
    final List<Map<String, dynamic>> counterflowZones = [];
    final List<Map<String, dynamic>> parkingZones = [];

    for (final v in _violations) {
      if (!v.kind.requiresRoi) continue;

      for (final zone in v.zones) {
        if (zone.roiPoints.length < 3) continue;

        final coords = zone.roiPoints
            .map((p) => [
                  (p.dx * _videoWidth).toInt(),
                  (p.dy * _videoHeight).toInt(),
                ])
            .toList();

        if (v.kind == ViolationKind.counterflow) {
          // Arrow: derive a normalized (x_dir, y_dir) vector from the
          // polyline endpoints (first → last point the user drew).
          Map<String, dynamic> vectorEntry = {'x_dir': 1.0, 'y_dir': 0.0};
          if (zone.arrowPoints.length >= 2) {
            final first = zone.arrowPoints.first;
            final last = zone.arrowPoints.last;
            vectorEntry = {
              'x_dir': (last.dx - first.dx) * _videoWidth,
              'y_dir': (last.dy - first.dy) * _videoHeight,
            };
          }
          counterflowZones.add({
            'coordinates': coords,
            'legal_flow_vector': vectorEntry,
          });
        } else if (v.kind == ViolationKind.illegalParking) {
          parkingZones.add({
            'coordinates': coords,
            'time_limit': zone.timeLimitSeconds.toDouble(),
          });
        }
      }
    }

    return {
      if (counterflowZones.isNotEmpty) 'counterflow_zones': counterflowZones,
      if (parkingZones.isNotEmpty) 'illegal_parking_zones': parkingZones,
    };
  }

  Future<void> _startTracking() async {
    final bool isPlateEnabled = _plateDetectionMethod != 'Disabled';
    
    if (_violations.isEmpty && !isPlateEnabled) {
      AppToast.show(context, 'Add at least one violation pipeline or enable Plate Detection before running.', isError: true);
      return;
    }
    final incomplete = _violations.where((v) => !v.isComplete).toList();
    if (incomplete.isNotEmpty) {
      AppToast.show(context, 'Finish setup for: ${incomplete.map((v) => v.kind.label).join(", ")}', isError: true);
      return;
    }

    final List<String> activeViolations = [
      ..._violations.map((v) => v.kind.backendKey),
      if (isPlateEnabled) 'no_plate',
    ];

    String backendPlateMethod = 'smart';
    if (_plateDetectionMethod == 'Direct OCR (Bumper Scan)') {
      backendPlateMethod = 'direct_ocr';
    }

    final Map<String, dynamic> config = {
      "camera_id": "Offline_Video",
      "source_url": _videoPath,
      "source_type": "Pre-recorded Video (File)",
      "active_violations": activeViolations,
      "plate_method": backendPlateMethod,
      "tracker": _trackerType,
      // Native video dimensions so the backend can scale ROI polygon coords to
      // match the actual processed frame resolution (which may be downscaled).
      "video_native_width": _videoWidth.toInt(),
      "video_native_height": _videoHeight.toInt(),
      "regions_of_interest": _buildRoiPayload(),
    };

    try {
      // 1. Select the model first so the backend feed is using the right detector.
      await http.post(
        Uri.parse(
          '${ApiConstants.baseUrl}/settings/model?name=${Uri.encodeComponent(_selectedModel)}',
        ),
      );

      // 2. Disable mock mode in backend so real ONNX / YOLO model runs
      await http.post(
        Uri.parse('${ApiConstants.baseUrl}/settings/mock?enabled=false'),
      );

      // 3. Save camera configuration and update source
      await http.post(
        Uri.parse('${ApiConstants.baseUrl}/settings/camera-config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(config),
      );

      await http.post(
        Uri.parse(
          '${ApiConstants.baseUrl}/settings/video/source?path=${Uri.encodeComponent(_videoPath)}',
        ),
      );

      setState(() {
        _isPlaying = true;
        _channel = WebSocketChannel.connect(
          Uri.parse(ApiConstants.wsVideoFeed),
        );
        _broadcastStream = _channel!.stream.asBroadcastStream();
      });
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'Failed: $e', isError: true);
      }
    }
  }

  void _stopTracking() {
    setState(() {
      _isPlaying = false;
      _channel?.sink.close();
      _channel = null;
      _broadcastStream = null;
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              flex: 7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Video File Analysis',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: !_isFileImported
                        ? _buildEmptyState()
                        : _buildVideoArea(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isPlaying ? 'Video Detections' : 'Violation Pipeline',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _isPlaying && _broadcastStream != null
                        ? AlertListWidget(frameStream: _broadcastStream!)
                        : _buildViolationPipelinePanel(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Object Detection Model ──────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.memory, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Detection Model',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const Spacer(),
              if (_availableModels.isNotEmpty)
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedModel,
                    isDense: true,
                    items: _availableModels
                        .map(
                          (model) => DropdownMenuItem(
                            value: model,
                            child: Text(
                              model,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _isPlaying
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _selectedModel = value);
                            }
                          },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // ── Plate Detection Method ──────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.no_photography, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Plate Detection',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Select the method used to detect and read license plates.',
                child: const Icon(Icons.info_outline, size: 14, color: Colors.grey),
              ),
              const Spacer(),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _plateDetectionMethod,
                  isDense: true,
                  items: _plateDetectionMethods
                      .map(
                        (method) => DropdownMenuItem(
                          value: method,
                          child: Text(
                            method,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _isPlaying
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _plateDetectionMethod = value);
                          }
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViolationPipelinePanel() {
    if (!_isFileImported) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Import a video to begin configuring violation pipelines.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModelSelector(),
          const Divider(height: 1),
          Expanded(
            child: _violations.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No violations added yet.\nTap "Add Violation" to configure your first detection pipeline.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _violations.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final v = _violations[i];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          dense: true,
                          leading: Icon(v.kind.icon),
                          title: Text(
                            v.kind.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              Icon(
                                v.isComplete
                                    ? Icons.check_circle
                                    : Icons.warning_amber_rounded,
                                size: 14,
                                color: v.isComplete
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                v.isComplete
                                    ? 'Configured'
                                    : 'Incomplete setup',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: v.isComplete
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          onTap: _isPlaying ? null : () => _editViolation(v),
                          trailing: _isPlaying
                              ? null
                              : IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  onPressed: () => _removeViolation(v.id),
                                  tooltip: 'Remove',
                                ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isPlaying ? null : _addViolation,
                icon: const Icon(Icons.add),
                label: const Text('Add Violation'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: FilledButton.icon(
          onPressed: _importFile,
          icon: const Icon(Icons.file_open, size: 32),
          label: const Padding(
            padding: EdgeInsets.all(12.0),
            child: Text('Open Video File', style: TextStyle(fontSize: 18)),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: Colors.white24),
            ),
            child: Stack(
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: _aspectRatio,
                    child: Stack(
                      children: [
                        if (_isPlaying && _broadcastStream != null)
                          Positioned.fill(
                            child: VideoFeedWidget(stream: _broadcastStream!),
                          )
                        else if (_frameImageUrl.isNotEmpty)
                          Positioned.fill(
                            child: Image.network(
                              _frameImageUrl,
                              fit: BoxFit.fill,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Text(
                                    'Error loading frame',
                                    style: TextStyle(color: Colors.red),
                                  ),
                            ),
                          ),
                        // Keep every configured violation's ROI/arrow overlaid on the feed.
                        if (_frameImageUrl.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _MultiViolationOverlayPainter(
                                  violations: _violations,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                if (!_isPlaying)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () =>
                            setState(() => _isFileImported = false),
                        tooltip: 'Close Video',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.analytics, size: 16, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Text(
              'Tracker Algorithm',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const Spacer(),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _trackerType,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'bytetrack', child: Text('ByteTrack (Fast)')),
                  DropdownMenuItem(value: 'deepsort', child: Text('DeepSORT (Accurate)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _trackerType = val);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.camera_alt, size: 16, color: Colors.blueAccent),
            const SizedBox(width: 8),
            const Text('Scrub Frame:', style: TextStyle(color: Colors.white54)),
            Expanded(
              child: Slider(
                value: _videoPosition > _videoDuration
                    ? _videoDuration
                    : _videoPosition,
                min: 0,
                max: _videoDuration > 0 ? _videoDuration : 60.0,
                label:
                    '00:${_videoPosition.toInt().toString().padLeft(2, '0')}',
                onChanged: _isPlaying
                    ? null
                    : (val) => setState(() => _videoPosition = val),
                onChangeEnd: _isPlaying ? null : (val) => _updateFrameImage(),
              ),
            ),
          ],
        ),
        Card(
          color: Colors.grey[900],
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _violations.isEmpty
                      ? 'No violations configured yet'
                      : '${_violations.length} violation(s) configured',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                if (_isPlaying)
                  FilledButton.icon(
                    onPressed: _stopTracking,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop & Re-edit'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  )
                else
                  FilledButton.icon(
                    onPressed: _startTracking,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Run Detection'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Draws every configured violation's ROI polygon and flow arrow, read-only,
/// overlaid on the current video frame so the whole session setup is visible
/// at a glance. Supports multiple zones per violation.
class _MultiViolationOverlayPainter extends CustomPainter {
  final List<ViolationConfig> violations;

  _MultiViolationOverlayPainter({required this.violations});

  @override
  void paint(Canvas canvas, Size size) {
    Offset scale(Offset p) => Offset(p.dx * size.width, p.dy * size.height);

    for (final v in violations) {
      final zoneColor = v.kind == ViolationKind.illegalParking
          ? Colors.orange
          : Colors.blue;

      for (final zone in v.zones) {
        // Draw the ROI polygon for this zone.
        if (zone.roiPoints.length >= 3) {
          final path = Path()
            ..moveTo(scale(zone.roiPoints.first).dx, scale(zone.roiPoints.first).dy);
          for (int i = 1; i < zone.roiPoints.length; i++) {
            path.lineTo(scale(zone.roiPoints[i]).dx, scale(zone.roiPoints[i]).dy);
          }
          path.close();
          canvas.drawPath(
            path,
            Paint()
              ..color = zoneColor.withValues(alpha: 0.25)
              ..style = PaintingStyle.fill,
          );
          canvas.drawPath(
            path,
            Paint()
              ..color = zoneColor
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke,
          );
        }

        // Draw the legal-flow arrow for this zone (counterflow only).
        if (zone.arrowPoints.length >= 2) {
          final scaled = zone.arrowPoints.map(scale).toList();
          final linePaint = Paint()
            ..color = Colors.greenAccent
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round;
          for (int i = 0; i < scaled.length - 1; i++) {
            canvas.drawLine(scaled[i], scaled[i + 1], linePaint);
          }

          final startPt = scaled[scaled.length - 2];
          final endPt = scaled.last;
          final angle = math.atan2(endPt.dy - startPt.dy, endPt.dx - startPt.dx);
          const arrowLength = 16.0;
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
