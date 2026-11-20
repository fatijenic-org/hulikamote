import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hulikamote_dashboard/core/utils/app_toast.dart';

import 'package:flutter/services.dart';
import '../../domain/models/detection.dart';
import 'zoomable_image.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/services/api_service.dart';
import '../../../violations/domain/models/violation.dart';
import '../screens/live_tickets_screen.dart';

class AlertListWidget extends StatefulWidget {
  final Stream<dynamic>? frameStream;
  const AlertListWidget({super.key, this.frameStream});

  @override
  State<AlertListWidget> createState() => _AlertListWidgetState();
}

class _AlertListWidgetState extends State<AlertListWidget> {
  final List<_Alert> _items = [];
  final Set<String> _seenKeys = {};
  final _api = ApiService();
  static const int _maxAlerts = 30;
  static const int _ingestIntervalMs = 350;
  int _lastIngestMs = 0;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _listenStream();
  }

  @override
  void didUpdateWidget(covariant AlertListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frameStream != widget.frameStream) {
      _listenStream();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listenStream() {
    _sub?.cancel();
    if (widget.frameStream != null) {
      _sub = widget.frameStream!.listen((data) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - _lastIngestMs < _ingestIntervalMs) {
          return;
        }
        _lastIngestMs = nowMs;

        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          final rawDetections = json['detections'] as List? ?? const [];
          
          // JSON Overlay sends ALL cars so the video widget can draw green boxes.
          // We must filter to ONLY actual violators for the alert sidebar.
          // When the backend saw this picture (its own clock, like the tickets' time): where the evidence of the alert starts.
          final seenAt = DateTime.tryParse('${json['timestamp'] ?? ''}');
          final violatorDetections = rawDetections.where((d) {
            final map = d as Map<String, dynamic>;
            return (map['is_violator'] as bool?) == true;
          }).toList();

          if (violatorDetections.isNotEmpty) {
            setState(() {
              // Ingest at most two detections per sampling window to avoid UI churn.
              final takeCount = violatorDetections.length > 2
                  ? 2
                  : violatorDetections.length;
              for (int i = 0; i < takeCount; i++) {
                final d = Detection.fromJson(
                  violatorDetections[i] as Map<String, dynamic>,
                );
                // Same vehicle keeps re-triggering while it stays in the ROI;
                // log it once per track+violation instead of every frame.
                // We use tracking ID + classification to deduplicate.
                final key = '${d.trackId}_${d.cls}';
                
                if (d.trackId == null || _seenKeys.contains(key)) {
                  continue;
                }
                _seenKeys.add(key);
                _items.insert(0, _Alert(detection: d, time: DateTime.now(), seenAt: seenAt));
              }
              if (_items.length > _maxAlerts) {
                _items.removeRange(_maxAlerts, _items.length);
              }
            });
          }
        } catch (_) {}
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Live Alerts (${_items.length})',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: const ValueKey('review-live-tickets'),
                  tooltip: 'Review the live tickets: read plates, set photos aside, merge',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.fact_check_outlined, size: 20),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveTicketsScreen())),
                ),
                if (_items.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      _items.clear();
                      _seenKeys.clear();
                    }),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text(
                      'No detections yet',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final a = _items[i];
                      final d = a.detection;
                      final ago = _elapsed(a.time);
                      return ListTile(
                        dense: true,
                        onTap: d.trackId == null
                            ? null
                            : () => _openTicket(context, d.trackId!, a.seenAt ?? a.time),
                        onLongPress: d.trackId == null
                            ? null
                            : () => _showEvidenceDialog(context, d.trackId!, a.seenAt ?? a.time),     // the quick look, as before
                        leading: const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                          size: 20,
                        ),
                        title: Text(
                          d.cls.replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${(d.confidence * 100).toStringAsFixed(0)}% confidence'
                              '${d.trackId != null ? ' • Vehicle #${d.trackId}' : ''}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            if (d.userName != null)
                              Text(
                                d.userName == 'SCANNING...' ? 'Scanning Plate...' : 'Violator: ${d.userName}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: d.userName == 'SCANNING...' ? Colors.orange.shade800 : Colors.blueGrey.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                        trailing: Text(
                          ago,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _elapsed(DateTime t) {
    final diff = DateTime.now().difference(t).inSeconds;
    if (diff < 60) return '${diff}s ago';
    return '${diff ~/ 60}m ago';
  }

  /// A tapped alert opens its ticket in the live review (plate reading, photos, merge). The ticket is made when the vehicle leaves
  /// the picture, so a vehicle that is still in view has none yet.
  Future<void> _openTicket(BuildContext context, int trackId, DateTime since) async {
    final navigator = Navigator.of(context);
    Violation? ticket;
    try {
      // Only a ticket made after the alert first showed is this vehicle's (the number alone also fits the tickets of older runs).
      ticket = await _api.fetchViolationByTrackId(trackId, since: since.subtract(const Duration(seconds: 1)));
    } catch (_) {
      ticket = null;
    }
    if (ticket == null) {
      return;
    }
    navigator.push(MaterialPageRoute(builder: (_) => LiveTicketsScreen(focusDbId: ticket!.id)));
  }

  void _showEvidenceDialog(BuildContext context, int trackId, DateTime since) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Vehicle #$trackId — Evidence'),
        content: SizedBox(
          width: 800,
          height: 540,
          child: FutureBuilder<Violation?>(
            // Only a ticket made after the alert first showed is this vehicle's (the number alone also fits the tickets of older runs).
            future: _api.fetchViolationByTrackId(trackId, since: since.subtract(const Duration(seconds: 1))),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final violation = snapshot.data;
              if (snapshot.hasError || violation == null) {
                return const Center(
                  child: Text(
                    'Evidence not available yet — the vehicle may still be\n'
                    'in view. Tickets are finalized once it leaves the frame.',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              if (violation.evidencePaths.isEmpty) {
                return const Center(
                  child: Text(
                    'No evidence frames were captured for this ticket.',
                  ),
                );
              }
              return _EvidenceViewer(violation: violation);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _EvidenceViewer extends StatefulWidget {
  final Violation violation;
  const _EvidenceViewer({required this.violation});

  @override
  State<_EvidenceViewer> createState() => _EvidenceViewerState();
}

class _EvidenceViewerState extends State<_EvidenceViewer> {
  late int _currentIndex = 0;
  bool _isExtracting = false;
  String? _plateText;
  
  @override
  void initState() {
    super.initState();
    _plateText = widget.violation.userName;
  }

  void _previous() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  void _next() {
    if (_currentIndex < widget.violation.evidencePaths.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  void _openFullScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenEvidenceViewer(
          paths: widget.violation.evidencePaths,
          initialIndex: _currentIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paths = widget.violation.evidencePaths;
    final url = '${ApiConstants.baseUrl}/${paths[_currentIndex]}';
    
    // Check if plate needs extraction
    final bool needsExtraction = _plateText == null || _plateText == 'unidentified';
    
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              _currentIndex > 0) {
            _previous();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
              _currentIndex < paths.length - 1) {
            _next();
            return KeyEventResult.handled;
          } else if (event.character?.toLowerCase() == 'f') {
            _openFullScreen();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ZoomableImage(key: ValueKey(url), url: url, onFullScreen: _openFullScreen),
              ),
            ),
          ),
          
          // OCR Extraction Section
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Detected Plate:', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Text(
                        _plateText?.toUpperCase() ?? 'UNIDENTIFIED',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: needsExtraction ? Colors.grey : Colors.blue.shade800,
                        ),
                      ),
                    ],
                  ),
                  if (needsExtraction)
                    ElevatedButton.icon(
                      onPressed: _isExtracting ? null : () async {
                        setState(() => _isExtracting = true);
                        try {
                          final result = await ApiService().extractPlate(widget.violation.id);
                          setState(() {
                            _plateText = result ?? 'no_plate_found';
                          });
                        } catch (e) {
                          AppToast.show(context, 'OCR failed: $e', isError: true);
                        } finally {
                          setState(() => _isExtracting = false);
                        }
                      },
                      icon: _isExtracting 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.document_scanner),
                      label: Text(_isExtracting ? 'Scanning...' : 'Extract Plate Number'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(top: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: _currentIndex > 0 ? _previous : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Previous'),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Frame ${_currentIndex + 1} / ${paths.length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'Wheel or + / - to zoom, drag to move • F for full view • ← → to navigate',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _currentIndex < paths.length - 1
                      ? _next
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Next'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullScreenEvidenceViewer extends StatefulWidget {
  final List<String> paths;
  final int initialIndex;

  const _FullScreenEvidenceViewer({
    required this.paths,
    required this.initialIndex,
  });

  @override
  State<_FullScreenEvidenceViewer> createState() =>
      _FullScreenEvidenceViewerState();
}

class _FullScreenEvidenceViewerState extends State<_FullScreenEvidenceViewer> {
  late int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _previous() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  void _next() {
    if (_currentIndex < widget.paths.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = '${ApiConstants.baseUrl}/${widget.paths[_currentIndex]}';
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              _currentIndex > 0) {
            _previous();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
              _currentIndex < widget.paths.length - 1) {
            _next();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black87,
          foregroundColor: Colors.white,
          title: Text('Frame ${_currentIndex + 1} / ${widget.paths.length}'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ZoomableImage(key: ValueKey(url), url: url),
            ),
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton.filled(
                    onPressed: _currentIndex > 0 ? _previous : null,
                    icon: const Icon(Icons.arrow_back, size: 24),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Frame ${_currentIndex + 1} / ${widget.paths.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '← → to navigate • ESC to close',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  IconButton.filled(
                    onPressed: _currentIndex < widget.paths.length - 1
                        ? _next
                        : null,
                    icon: const Icon(Icons.arrow_forward, size: 24),
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

class _Alert {
  final Detection detection;
  final DateTime time;
  final DateTime? seenAt; // the backend's time of the picture that first showed it
  const _Alert({required this.detection, required this.time, this.seenAt});
}
