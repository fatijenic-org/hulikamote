import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';

class ZoneVisualizer extends StatefulWidget {
  @override
  _ZoneVisualizerState createState() => _ZoneVisualizerState();
}

enum AdminZoneMode { adjustPolygon, testVehicle }

class _ZoneVisualizerState extends State<ZoneVisualizer> {
  AdminZoneMode currentMode = AdminZoneMode.adjustPolygon;

  // Polygon ROI vertices
  List<Offset> polygonPoints = [
    Offset(150, 100),
    Offset(480, 100),
    Offset(520, 280),
    Offset(120, 280),
  ];

  int? draggedPointIndex;

  // History for Undo/Redo
  List<List<Offset>> _undoStack = [];
  List<List<Offset>> _redoStack = [];

  void _saveState() {
    _undoStack.add(List.from(polygonPoints));
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isNotEmpty) {
      _redoStack.add(List.from(polygonPoints));
      setState(() {
        polygonPoints = _undoStack.removeLast();
      });
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      _undoStack.add(List.from(polygonPoints));
      setState(() {
        polygonPoints = _redoStack.removeLast();
      });
    }
  }

  // Car State
  Offset carPos = Offset(550, 190);
  final double carW = 80;
  final double carH = 40;

  // Grace Period & Timer
  double gracePeriodLimit = 5.0; // seconds
  double timeStationary = 0.0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      bool isInside = _isPointInPolygon(carPos, polygonPoints);
      setState(() {
        if (isInside) {
          timeStationary += 0.1;
        } else {
          timeStationary = 0.0;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // PNPoly point-in-polygon algorithm
  bool _isPointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if (((polygon[i].dy > point.dy) != (polygon[j].dy > point.dy)) &&
          (point.dx < (polygon[j].dx - polygon[i].dx) * (point.dy - polygon[i].dy) / (polygon[j].dy - polygon[i].dy) + polygon[i].dx)) {
        inside = !inside;
      }
    }
    return inside;
  }

  void _handlePanDown(DragDownDetails details) {
    RenderBox box = context.findRenderObject() as RenderBox;
    Offset localPos = box.globalToLocal(details.globalPosition);

    if (localPos.dx > MediaQuery.of(context).size.width * 0.6) return;

    if (currentMode == AdminZoneMode.adjustPolygon) {
      // Check if clicking existing point within 25px
      for (int i = 0; i < polygonPoints.length; i++) {
        if ((polygonPoints[i] - localPos).distance < 25) {
          _saveState();
          setState(() {
            draggedPointIndex = i;
          });
          return;
        }
      }
      // Clicked outside -> Add new polygon vertex!
      _saveState();
      setState(() {
        polygonPoints.add(localPos);
        draggedPointIndex = polygonPoints.length - 1;
      });
    } else {
      // Test vehicle mode: pick up car
      setState(() {
        carPos = localPos;
        timeStationary = 0.0;
      });
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    RenderBox box = context.findRenderObject() as RenderBox;
    Offset localPos = box.globalToLocal(details.globalPosition);

    if (localPos.dx > MediaQuery.of(context).size.width * 0.6) return;

    if (currentMode == AdminZoneMode.adjustPolygon && draggedPointIndex != null) {
      setState(() {
        polygonPoints[draggedPointIndex!] = localPos;
      });
    } else if (currentMode == AdminZoneMode.testVehicle) {
      setState(() {
        carPos = localPos;
        timeStationary = 0.0; // Reset while actively moving
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      draggedPointIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isInside = _isPointInPolygon(carPos, polygonPoints);
    bool isViolation = isInside && timeStationary >= gracePeriodLimit;

    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: GestureDetector(
            onPanDown: _handlePanDown,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            onPanCancel: () => setState(() => draggedPointIndex = null),
            child: Container(
              color: Colors.grey[850],
              child: ClipRect(
                child: CustomPaint(
                  painter: _ModernZonePainter(
                    polygonPoints: polygonPoints,
                    carPos: carPos,
                    carW: carW,
                    carH: carH,
                    isInside: isInside,
                    isViolation: isViolation,
                    mode: currentMode,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
        // CONTROLS AREA
        Container(
          width: 380,
          color: Colors.blueGrey[50],
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Modern AI: Dynamic Zone & Grace Timer", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 12),
                      Text(
                        "Operators can define arbitrary polygon zones on any camera angle. The AI runs PNPoly ray-casting with an intelligent grace period timer.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 28),

                      Text("1. Region of Interest (ROI) Setup", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<AdminZoneMode>(
                              title: Text("Adjust ROI Polygon", style: TextStyle(fontSize: 14)),
                              subtitle: Text("Drag points or tap to add", style: TextStyle(fontSize: 12)),
                              value: AdminZoneMode.adjustPolygon,
                              groupValue: currentMode,
                              onChanged: (val) => setState(() => currentMode = val!),
                            ),
                          ),
                          if (currentMode == AdminZoneMode.adjustPolygon) ...[
                            IconButton(
                              icon: Icon(Icons.undo),
                              color: _undoStack.isNotEmpty ? Colors.blue : Colors.grey,
                              onPressed: _undoStack.isNotEmpty ? _undo : null,
                              tooltip: 'Undo',
                            ),
                            IconButton(
                              icon: Icon(Icons.redo),
                              color: _redoStack.isNotEmpty ? Colors.blue : Colors.grey,
                              onPressed: _redoStack.isNotEmpty ? _redo : null,
                              tooltip: 'Redo',
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline),
                              color: Colors.red,
                              onPressed: () {
                                _saveState();
                                setState(() => polygonPoints.clear());
                              },
                              tooltip: 'Clear',
                            )
                          ]
                        ],
                      ),

                      Text("2. Test Vehicle Positioning", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[900])),
                      RadioListTile<AdminZoneMode>(
                        title: Text("Drag Car Around", style: TextStyle(fontSize: 14)),
                        subtitle: Text("Leave car inside zone to trigger timer", style: TextStyle(fontSize: 12)),
                        value: AdminZoneMode.testVehicle,
                        groupValue: currentMode,
                        onChanged: (val) => setState(() => currentMode = val!),
                      ),

                      Divider(height: 24),
                      Text("Grace Period Threshold: ${gracePeriodLimit.toStringAsFixed(0)}s", style: TextStyle(fontWeight: FontWeight.bold)),
                      Slider(
                        value: gracePeriodLimit,
                        min: 2.0,
                        max: 15.0,
                        divisions: 13,
                        label: "${gracePeriodLimit.toStringAsFixed(0)}s",
                        activeColor: Colors.blueAccent,
                        onChanged: (val) => setState(() => gracePeriodLimit = val),
                      ),

                      Divider(height: 24),
                      Text("Live Diagnostics:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text("Car Centroid: (${carPos.dx.toStringAsFixed(0)}, ${carPos.dy.toStringAsFixed(0)})"),
                      Text("Inside Polygon: ${isInside ? 'YES' : 'NO'}"),
                      Text("Vertices in ROI: ${polygonPoints.length}"),
                      SizedBox(height: 12),

                      Text("Stationary Duration:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: (timeStationary / gracePeriodLimit).clamp(0.0, 1.0),
                        backgroundColor: Colors.grey[300],
                        color: isViolation ? Colors.red : (isInside ? Colors.orange : Colors.green),
                        minHeight: 12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      SizedBox(height: 6),
                      Text(
                        "${timeStationary.toStringAsFixed(1)}s / ${gracePeriodLimit.toStringAsFixed(0)}s",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isViolation ? Colors.red : Colors.grey[800]),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1),
              Container(
                padding: EdgeInsets.all(20),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isViolation ? Colors.red[100] : (isInside ? Colors.orange[100] : Colors.green[100]),
                ),
                child: Column(
                  children: [
                    Text("AI Enforcement Decision:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey[800])),
                    SizedBox(height: 6),
                    Text(
                      isViolation 
                          ? "VIOLATION (Illegal Parking)\nCitation Generated & Sent to LTO" 
                          : (isInside ? "WARNING (Stationary in Zone)\nGrace Period Expiring..." : "SAFE\n(Outside Zone or Moving)"),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isViolation ? Colors.red[900] : (isInside ? Colors.orange[900] : Colors.green[900]),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}

class _ModernZonePainter extends CustomPainter {
  final List<Offset> polygonPoints;
  final Offset carPos;
  final double carW;
  final double carH;
  final bool isInside;
  final bool isViolation;
  final AdminZoneMode mode;

  _ModernZonePainter({
    required this.polygonPoints,
    required this.carPos,
    required this.carW,
    required this.carH,
    required this.isInside,
    required this.isViolation,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Road background
    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    // Sidewalk curb
    Paint curbPaint = Paint()..color = Colors.grey[400]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 30, size.width, 35), curbPaint);

    // Lane markings
    Paint laneLine = Paint()..color = Colors.white60..strokeWidth = 3..style = PaintingStyle.stroke;
    double dashX = 0;
    while (dashX < size.width) {
      canvas.drawLine(Offset(dashX, 220), Offset(dashX + 25, 220), laneLine);
      dashX += 50;
    }

    // Draw Polygon ROI
    if (polygonPoints.isNotEmpty) {
      Path path = Path();
      path.moveTo(polygonPoints[0].dx, polygonPoints[0].dy);
      for (int i = 1; i < polygonPoints.length; i++) {
        path.lineTo(polygonPoints[i].dx, polygonPoints[i].dy);
      }
      path.close();

      Paint zoneFill = Paint()
        ..color = (isViolation ? Colors.red : Colors.yellow).withOpacity(0.2)
        ..style = PaintingStyle.fill;
      Paint zoneBorder = Paint()
        ..color = isViolation ? Colors.redAccent : Colors.yellowAccent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, zoneFill);
      canvas.drawPath(path, zoneBorder);

      // Draw ROI Vertices & handles
      if (mode == AdminZoneMode.adjustPolygon) {
        Paint handlePaint = Paint()..color = Colors.yellowAccent;
        for (Offset p in polygonPoints) {
          canvas.drawCircle(p, 8, handlePaint);
          canvas.drawCircle(p, 8, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2);
        }
      }

      // Zone label
      Offset labelPos = polygonPoints[0];
      TextPainter tpZone = TextPainter(
        text: TextSpan(
          text: "CUSTOM NO PARKING ROI",
          style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 12, backgroundColor: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      );
      tpZone.layout();
      tpZone.paint(canvas, Offset(labelPos.dx + 5, labelPos.dy + 5));
    }

    // Draw Car
    Rect carBox = Rect.fromCenter(center: carPos, width: carW, height: carH);
    Paint carPaint = Paint()..color = isViolation ? Colors.redAccent : (isInside ? Colors.orangeAccent : Colors.blueAccent);
    canvas.drawRRect(RRect.fromRectAndRadius(carBox, Radius.circular(6)), carPaint);

    // Car windshield
    Paint roofPaint = Paint()..color = Colors.white70;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: carPos, width: carW * 0.5, height: carH * 0.6), Radius.circular(3)), roofPaint);

    // Bounding box
    Paint bboxPaint = Paint()
      ..color = isViolation ? Colors.red : (isInside ? Colors.orange : Colors.greenAccent)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(carBox.inflate(3), bboxPaint);

    // Centroid dot
    Paint dotPaint = Paint()..color = isViolation ? Colors.red : (isInside ? Colors.orange : Colors.greenAccent);
    canvas.drawCircle(carPos, 5, dotPaint);

    TextPainter tpCentroid = TextPainter(
      text: TextSpan(
        text: "Centroid (${carPos.dx.toStringAsFixed(0)}, ${carPos.dy.toStringAsFixed(0)})",
        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, backgroundColor: Colors.black87),
      ),
      textDirection: TextDirection.ltr,
    );
    tpCentroid.layout();
    tpCentroid.paint(canvas, Offset(carPos.dx - tpCentroid.width / 2, carPos.dy + carH / 2 + 6));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
