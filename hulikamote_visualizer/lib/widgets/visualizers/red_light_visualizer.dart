import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';

class RedLightVisualizer extends StatefulWidget {
  @override
  _RedLightVisualizerState createState() => _RedLightVisualizerState();
}

enum RedLightAdminMode { setupTrafficLightROI, setupGroundROI, liveSimulation }
enum LightColor { green, yellow, red }

class _RedLightVisualizerState extends State<RedLightVisualizer> {
  RedLightAdminMode currentMode = RedLightAdminMode.liveSimulation;

  // Physical location of the traffic signal head on canvas
  final Rect physicalLightHousing = Rect.fromCenter(center: Offset(455, 80), width: 42, height: 90);

  // 1. Traffic Light Optical ROI Bounding Box (Enforcer can move it)
  Rect lightRoiRect = Rect.fromLTWH(420, 25, 75, 110);
  int? draggedLightHandle; // 0: TopLeft, 1: BottomRight, 2: Move entire box

  // 2. Ground Stop-Line Polygon ROI (Enforcer can drag corners)
  List<Offset> groundRoiPoints = [
    Offset(120, 200),
    Offset(400, 200),
    Offset(420, 340),
    Offset(90, 340),
  ];
  int? draggedGroundPointIndex;

  // History Stack for Ground ROI
  List<List<Offset>> _undoStack = [];
  List<List<Offset>> _redoStack = [];

  void _saveGroundState() {
    _undoStack.add(List.from(groundRoiPoints));
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isNotEmpty) {
      _redoStack.add(List.from(groundRoiPoints));
      setState(() {
        groundRoiPoints = _undoStack.removeLast();
      });
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      _undoStack.add(List.from(groundRoiPoints));
      setState(() {
        groundRoiPoints = _redoStack.removeLast();
      });
    }
  }

  // 3. Traffic Light Automatic Cycle State
  LightColor physicalLightState = LightColor.red;
  bool autoCycleLights = true;
  int lightTimerTicks = 0;

  // 4. Automated Vehicle Traffic Simulation
  double car1X = -60.0;  // Compliant car (Lane 1)
  double car1Speed = 3.5;
  bool car1Stopped = false;

  double car2X = -280.0; // Violator car (Lane 2)
  double car2Speed = 4.2;

  // Violation Capture Docket
  bool hasCapturedCitation = false;
  String citationDetails = "";
  Timer? _simTimer;

  @override
  void initState() {
    super.initState();
    _startSimulationLoop();
  }

  void _startSimulationLoop() {
    _simTimer?.cancel();
    _simTimer = Timer.periodic(Duration(milliseconds: 33), (timer) {
      if (!mounted) return;
      _updateSimulation();
    });
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }

  bool _isLightRoiAligned() {
    return lightRoiRect.overlaps(physicalLightHousing);
  }

  LightColor? _getDetectedLightState() {
    if (!_isLightRoiAligned()) return null; // ROI missed the traffic light!
    return physicalLightState;
  }

  void _updateSimulation() {
    setState(() {
      // 1. Light Cycle Timer (Every 30 ticks ~= 1s)
      if (autoCycleLights) {
        lightTimerTicks++;
        if (physicalLightState == LightColor.green && lightTimerTicks > 120) { // 4s Green
          physicalLightState = LightColor.yellow;
          lightTimerTicks = 0;
        } else if (physicalLightState == LightColor.yellow && lightTimerTicks > 60) { // 2s Yellow
          physicalLightState = LightColor.red;
          lightTimerTicks = 0;
        } else if (physicalLightState == LightColor.red && lightTimerTicks > 150) { // 5s Red
          physicalLightState = LightColor.green;
          lightTimerTicks = 0;
          hasCapturedCitation = false;
          car1Stopped = false;
        }
      }

      LightColor? detectedLight = _getDetectedLightState();

      // 2. Stop line threshold (derived directly from current ground ROI min X)
      double stopLineX = groundRoiPoints.map((p) => p.dx).reduce(math.min);

      // 3. Car 1 (Compliant driver in Lane 1)
      if (detectedLight == LightColor.red && car1X >= stopLineX - 85 && car1X < stopLineX) {
        // Safe stop before the ground stop line
        car1Speed = 0.0;
        car1Stopped = true;
      } else {
        car1Speed = 3.5;
        car1Stopped = false;
        car1X += car1Speed;
        if (car1X > 900) car1X = -80;
      }

      // 4. Car 2 (Violator driver in Lane 2)
      car2X += car2Speed;
      if (car2X > 900) {
        car2X = -250;
      }

      // 5. Check if Car 2 is actively inside ground ROI
      Offset car2Centroid = Offset(car2X, 305);
      bool car2InsideGround = _isPointInPolygon(car2Centroid, groundRoiPoints);

      if (detectedLight == LightColor.red && car2InsideGround) {
        hasCapturedCitation = true;
        citationDetails = "RED LIGHT VIOLATION LOGGED\nCentroid (${car2Centroid.dx.toStringAsFixed(0)}, ${car2Centroid.dy.toStringAsFixed(0)}) in Z_stop while Z_light == RED";
      }
    });
  }

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

    if (currentMode == RedLightAdminMode.setupTrafficLightROI) {
      if ((localPos - lightRoiRect.topLeft).distance < 20) {
        draggedLightHandle = 0;
      } else if ((localPos - lightRoiRect.bottomRight).distance < 20) {
        draggedLightHandle = 1;
      } else if (lightRoiRect.contains(localPos)) {
        draggedLightHandle = 2; // Move entire box
      }
    } else if (currentMode == RedLightAdminMode.setupGroundROI) {
      for (int i = 0; i < groundRoiPoints.length; i++) {
        if ((groundRoiPoints[i] - localPos).distance < 25) {
          _saveGroundState();
          setState(() {
            draggedGroundPointIndex = i;
          });
          return;
        }
      }
      _saveGroundState();
      setState(() {
        groundRoiPoints.add(localPos);
        draggedGroundPointIndex = groundRoiPoints.length - 1;
      });
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    RenderBox box = context.findRenderObject() as RenderBox;
    Offset localPos = box.globalToLocal(details.globalPosition);

    if (localPos.dx > MediaQuery.of(context).size.width * 0.6) return;

    if (currentMode == RedLightAdminMode.setupTrafficLightROI) {
      setState(() {
        if (draggedLightHandle == 0) {
          lightRoiRect = Rect.fromPoints(localPos, lightRoiRect.bottomRight);
        } else if (draggedLightHandle == 1) {
          lightRoiRect = Rect.fromPoints(lightRoiRect.topLeft, localPos);
        } else if (draggedLightHandle == 2) {
          lightRoiRect = lightRoiRect.shift(details.delta);
        }
      });
    } else if (currentMode == RedLightAdminMode.setupGroundROI && draggedGroundPointIndex != null) {
      setState(() {
        groundRoiPoints[draggedGroundPointIndex!] = localPos;
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      draggedLightHandle = null;
      draggedGroundPointIndex = null;
    });
  }

  void _setLightManual(LightColor c) {
    setState(() {
      autoCycleLights = false;
      physicalLightState = c;
      if (c != LightColor.red) hasCapturedCitation = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isLightAligned = _isLightRoiAligned();
    LightColor? detectedLight = _getDetectedLightState();

    Offset car2Centroid = Offset(car2X, 305);
    bool car2InsideGround = _isPointInPolygon(car2Centroid, groundRoiPoints);

    // Active violation occurs ONLY when all conditions are strictly met:
    // 1. Light ROI is aligned on the signal
    // 2. Light is actively RED
    // 3. Car is actively INSIDE the ground ROI polygon
    bool isViolatingLive = isLightAligned && (detectedLight == LightColor.red) && car2InsideGround;

    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: GestureDetector(
            onPanDown: _handlePanDown,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            onPanCancel: () => setState(() {
              draggedLightHandle = null;
              draggedGroundPointIndex = null;
            }),
            child: Container(
              color: Colors.grey[850],
              child: ClipRect(
                child: CustomPaint(
                  painter: _RedLightEnforcerPainter(
                    physicalLightHousing: physicalLightHousing,
                    lightRoiRect: lightRoiRect,
                    isLightAligned: isLightAligned,
                    groundRoiPoints: groundRoiPoints,
                    physicalLightState: physicalLightState,
                    detectedLight: detectedLight,
                    car1X: car1X,
                    car1Stopped: car1Stopped,
                    car2X: car2X,
                    car2InsideGround: car2InsideGround,
                    isViolatingLive: isViolatingLive,
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
                      Text("Modern AI: Dual-ROI Calibration", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      SizedBox(height: 8),
                      Text(
                        "Dual-ROI architecture ensures zero false alarms: violations only trigger when the vehicle is strictly inside the ground polygon AND the optical ROI confirms red.",
                        style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.3),
                      ),
                      Divider(height: 20),

                      // Configuration Modes
                      Text("Camera Setup Modes:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          _buildModeChip("🚦 1. Light ROI", RedLightAdminMode.setupTrafficLightROI),
                          SizedBox(width: 4),
                          _buildModeChip("🛑 2. Ground ROI", RedLightAdminMode.setupGroundROI),
                          SizedBox(width: 4),
                          _buildModeChip("🚗 3. Live Sim", RedLightAdminMode.liveSimulation),
                        ],
                      ),
                      SizedBox(height: 12),

                      // MODE 1: Traffic Light ROI
                      if (currentMode == RedLightAdminMode.setupTrafficLightROI) ...[
                        Text("1. Calibrate Traffic Light Optical ROI (Z_light)", style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text(
                          isLightAligned 
                              ? "✅ LOCKED ON: Traffic light is inside the ROI." 
                              : "⚠️ ROI NOT ALIGNED: Drag the box over the overhead traffic light pole!", 
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isLightAligned ? Colors.green[800] : Colors.red[800]),
                        ),
                        SizedBox(height: 10),
                        Text("ROI Dimensions: ${lightRoiRect.width.toStringAsFixed(0)} x ${lightRoiRect.height.toStringAsFixed(0)} px", style: TextStyle(fontSize: 12, fontFamily: 'monospace')),
                      ],

                      // MODE 2: Ground Stop Line ROI
                      if (currentMode == RedLightAdminMode.setupGroundROI) ...[
                        Row(
                          children: [
                            Text("2. Calibrate Ground Stop ROI (Z_stop)", style: TextStyle(fontWeight: FontWeight.bold)),
                            Spacer(),
                            IconButton(
                              icon: Icon(Icons.undo, size: 20),
                              color: _undoStack.isNotEmpty ? Colors.blue : Colors.grey,
                              onPressed: _undoStack.isNotEmpty ? _undo : null,
                              tooltip: 'Undo',
                            ),
                            IconButton(
                              icon: Icon(Icons.redo, size: 20),
                              color: _redoStack.isNotEmpty ? Colors.blue : Colors.grey,
                              onPressed: _redoStack.isNotEmpty ? _redo : null,
                              tooltip: 'Redo',
                            ),
                          ],
                        ),
                        Text("Drag yellow corner handles to match physical road stop lines. Vehicles outside this polygon will NEVER be flagged.", style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      ],

                      // MODE 3: Live Simulation & Controls
                      if (currentMode == RedLightAdminMode.liveSimulation) ...[
                        Text("Traffic Signal Controls:", style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: physicalLightState == LightColor.green ? Colors.green : Colors.grey[300],
                                  foregroundColor: physicalLightState == LightColor.green ? Colors.white : Colors.black87,
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: () => _setLightManual(LightColor.green),
                                child: Text("GREEN 🟢", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            SizedBox(width: 4),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: physicalLightState == LightColor.yellow ? Colors.amber[700] : Colors.grey[300],
                                  foregroundColor: physicalLightState == LightColor.yellow ? Colors.white : Colors.black87,
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: () => _setLightManual(LightColor.yellow),
                                child: Text("YELLOW 🟡", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            SizedBox(width: 4),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: physicalLightState == LightColor.red ? Colors.red : Colors.grey[300],
                                  foregroundColor: physicalLightState == LightColor.red ? Colors.white : Colors.black87,
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: () => _setLightManual(LightColor.red),
                                child: Text("RED 🔴", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        SwitchListTile(
                          dense: true,
                          title: Text("Auto-Cycle Lights (Green -> Yellow -> Red)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          value: autoCycleLights,
                          activeColor: Colors.blueAccent,
                          onChanged: (val) => setState(() => autoCycleLights = val),
                        ),
                      ],

                      Divider(height: 20),
                      Text("Live Calibration & Telemetry:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text(
                        "Light Optical ROI: ${isLightAligned ? 'LOCKED ON (${_getLightName(detectedLight!)})' : 'DISCONNECTED / NO SIGNAL'}",
                        style: TextStyle(fontWeight: FontWeight.bold, color: isLightAligned ? _getLightColor(detectedLight!) : Colors.red[800]),
                      ),
                      Text("Car 2 Inside Ground ROI: ${car2InsideGround ? 'YES (Inside Z_stop)' : 'NO (Outside Polygon)'}", style: TextStyle(fontWeight: FontWeight.bold, color: car2InsideGround ? Colors.orange[900] : Colors.grey[700])),
                      Text("Car 1 (Blue Sedan): ${car1Stopped ? 'Safely Stopped' : 'Moving'}"),
                      Divider(height: 16),

                      Text("Strict Boolean Logic Gate:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      SizedBox(height: 4),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey[300]!)),
                        child: Text(
                          "Condition 1: Z_light aligned? -> ${isLightAligned ? 'YES' : 'NO'}\nCondition 2: Z_light == RED? -> ${detectedLight == LightColor.red ? 'YES' : 'NO'}\nCondition 3: Car inside Z_stop? -> ${car2InsideGround ? 'YES' : 'NO'}\nLive Violation: ${isViolatingLive ? 'ACTIVE VIOLATION' : 'SAFE / NO INFRACTION'}",
                          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: isViolatingLive ? Colors.red[900] : Colors.green[900], fontWeight: FontWeight.bold),
                        ),
                      )
                    ],
                  ),
                ),
              ),
              Divider(height: 1),
              Container(
                padding: EdgeInsets.all(16),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isViolatingLive ? Colors.red[100] : (hasCapturedCitation ? Colors.amber[100] : Colors.green[100]),
                ),
                child: Column(
                  children: [
                    Text("AI Violation Enforcement Decision:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[800])),
                    SizedBox(height: 4),
                    Text(
                      !isLightAligned
                          ? "⚠️ OPTICAL ROI NOT ALIGNED\nEnforcement Paused Until Aligned"
                          : (isViolatingLive
                              ? "🔴 ACTIVE RED LIGHT VIOLATION!\n(Vehicle Currently Inside Ground ROI on RED)"
                              : (hasCapturedCitation 
                                  ? "CITATION DOCKET CAPTURED\n(Vehicle Crossed Stop Line on Red Signal)"
                                  : (detectedLight == LightColor.red ? "🔴 RED SIGNAL ACTIVE (Compliant)" : "🟢 GREEN SIGNAL (Legal Flow)"))),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isViolatingLive ? Colors.red[900] : (hasCapturedCitation ? Colors.amber[900] : Colors.green[900]),
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

  Widget _buildModeChip(String title, RedLightAdminMode mode) {
    bool isSelected = currentMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => currentMode = mode),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blueGrey[900] : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isSelected ? Colors.blueGrey[900]! : Colors.grey[300]!),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : Colors.grey[800],
            ),
          ),
        ),
      ),
    );
  }

  String _getLightName(LightColor c) {
    switch (c) {
      case LightColor.green:
        return "GREEN 🟢";
      case LightColor.yellow:
        return "YELLOW 🟡";
      case LightColor.red:
        return "RED 🔴";
    }
  }

  Color _getLightColor(LightColor c) {
    switch (c) {
      case LightColor.green:
        return Colors.green[800]!;
      case LightColor.yellow:
        return Colors.amber[800]!;
      case LightColor.red:
        return Colors.red[800]!;
    }
  }
}

class _RedLightEnforcerPainter extends CustomPainter {
  final Rect physicalLightHousing;
  final Rect lightRoiRect;
  final bool isLightAligned;
  final List<Offset> groundRoiPoints;
  final LightColor physicalLightState;
  final LightColor? detectedLight;
  final double car1X;
  final bool car1Stopped;
  final double car2X;
  final bool car2InsideGround;
  final bool isViolatingLive;
  final RedLightAdminMode mode;

  _RedLightEnforcerPainter({
    required this.physicalLightHousing,
    required this.lightRoiRect,
    required this.isLightAligned,
    required this.groundRoiPoints,
    required this.physicalLightState,
    required this.detectedLight,
    required this.car1X,
    required this.car1Stopped,
    required this.car2X,
    required this.car2InsideGround,
    required this.isViolatingLive,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Road Background
    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 180, size.width, 180), roadPaint);

    // Sidewalk curb
    Paint curbPaint = Paint()..color = Colors.grey[400]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 160, size.width, 20), curbPaint);

    // Lane divider
    Paint laneLine = Paint()..color = Colors.white60..strokeWidth = 3..style = PaintingStyle.stroke;
    double dashX = 0;
    while (dashX < size.width) {
      canvas.drawLine(Offset(dashX, 270), Offset(dashX + 25, 270), laneLine);
      dashX += 50;
    }

    // 2. Physical Stop Line on Road
    Paint stopLinePaint = Paint()..color = Colors.white..strokeWidth = 6;
    double stopX = groundRoiPoints.map((p) => p.dx).reduce(math.min);
    canvas.drawLine(Offset(stopX, 180), Offset(stopX, 360), stopLinePaint);

    TextPainter tpStop = TextPainter(
      text: TextSpan(text: "STOP LINE", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 9)),
      textDirection: TextDirection.ltr,
    );
    tpStop.layout();
    tpStop.paint(canvas, Offset(stopX - tpStop.width - 6, 190));

    // 3. Ground Violation ROI Polygon (Z_stop)
    if (groundRoiPoints.isNotEmpty) {
      Path groundPath = Path();
      groundPath.moveTo(groundRoiPoints[0].dx, groundRoiPoints[0].dy);
      for (int i = 1; i < groundRoiPoints.length; i++) {
        groundPath.lineTo(groundRoiPoints[i].dx, groundRoiPoints[i].dy);
      }
      groundPath.close();

      Paint groundFill = Paint()
        ..color = (isViolatingLive ? Colors.red : (detectedLight == LightColor.red ? Colors.amber : Colors.green)).withOpacity(0.18)
        ..style = PaintingStyle.fill;
      Paint groundBorder = Paint()
        ..color = isViolatingLive ? Colors.redAccent : (car2InsideGround ? Colors.orangeAccent : Colors.yellowAccent)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(groundPath, groundFill);
      canvas.drawPath(groundPath, groundBorder);

      // Draw ground handles if editing ground ROI
      if (mode == RedLightAdminMode.setupGroundROI) {
        Paint handlePaint = Paint()..color = Colors.yellowAccent;
        for (Offset p in groundRoiPoints) {
          canvas.drawCircle(p, 7, handlePaint);
          canvas.drawCircle(p, 7, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2);
        }
      }

      TextPainter tpGroundTag = TextPainter(
        text: TextSpan(
          text: "GROUND STOP ROI (Z_stop)",
          style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 10, backgroundColor: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      );
      tpGroundTag.layout();
      tpGroundTag.paint(canvas, Offset(groundRoiPoints[0].dx + 8, groundRoiPoints[0].dy + 8));
    }

    // 4. Physical Overhead Traffic Signal Pole & Housing
    _drawPhysicalTrafficLight(canvas);

    // 5. Traffic Light ROI (Z_light) Bounding Box
    Paint lightRoiBorder = Paint()
      ..color = isLightAligned ? Colors.cyanAccent : Colors.redAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(lightRoiRect, lightRoiBorder);

    if (mode == RedLightAdminMode.setupTrafficLightROI) {
      canvas.drawCircle(lightRoiRect.topLeft, 6, Paint()..color = isLightAligned ? Colors.cyanAccent : Colors.redAccent);
      canvas.drawCircle(lightRoiRect.bottomRight, 6, Paint()..color = isLightAligned ? Colors.cyanAccent : Colors.redAccent);
    }

    TextPainter tpLightTag = TextPainter(
      text: TextSpan(
        text: isLightAligned 
            ? "Z_light: [LOCKED: ${_getLightLabel(detectedLight!)}]" 
            : "Z_light: [⚠️ NOT ALIGNED - NO SIGNAL]",
        style: TextStyle(color: isLightAligned ? Colors.cyanAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10, backgroundColor: Colors.black87),
      ),
      textDirection: TextDirection.ltr,
    );
    tpLightTag.layout();
    tpLightTag.paint(canvas, Offset(lightRoiRect.left - 10, lightRoiRect.bottom + 4));

    // 6. Draw Simulated Vehicles
    // Car 1: Compliant Blue Sedan (Lane 1)
    _drawCar(canvas, Offset(car1X, 225), Colors.blueAccent, "Car #1 [Compliant]", car1Stopped, false);

    // Car 2: Violator Red SUV (Lane 2)
    _drawCar(canvas, Offset(car2X, 315), Colors.redAccent, "Car #2 [Red Light Runner]", false, isViolatingLive);

    // 7. Live Violation Snapshot Reticle if active
    if (isViolatingLive) {
      Offset car2Centroid = Offset(car2X, 315);
      Paint flashReticle = Paint()
        ..color = Colors.red
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(car2Centroid, 30, flashReticle);
      canvas.drawLine(Offset(car2Centroid.dx - 38, car2Centroid.dy), Offset(car2Centroid.dx + 38, car2Centroid.dy), flashReticle);
      canvas.drawLine(Offset(car2Centroid.dx, car2Centroid.dy - 38), Offset(car2Centroid.dx, car2Centroid.dy + 38), flashReticle);

      TextPainter tpViolation = TextPainter(
        text: TextSpan(
          text: "🔴 ACTIVE VIOLATION IN Z_stop!",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, backgroundColor: Colors.red[900]),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tpViolation.layout();
      tpViolation.paint(canvas, Offset(car2Centroid.dx - tpViolation.width / 2, car2Centroid.dy - 60));
    }
  }

  void _drawPhysicalTrafficLight(Canvas canvas) {
    Offset poleBase = Offset(450, 160);
    // Mast arm gantry
    Paint polePaint = Paint()..color = Colors.grey[400]!..strokeWidth = 6;
    canvas.drawLine(poleBase, Offset(450, 20), polePaint);
    canvas.drawLine(Offset(450, 40), Offset(400, 40), polePaint);

    // Traffic Signal Box Housing
    Offset boxCenter = Offset(455, 80);
    Rect housing = physicalLightHousing;
    Paint housePaint = Paint()..color = Colors.black87;
    canvas.drawRRect(RRect.fromRectAndRadius(housing, Radius.circular(6)), housePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(housing, Radius.circular(6)), Paint()..color = Colors.yellow[700]!..style = PaintingStyle.stroke..strokeWidth = 2);

    // Signal Bulbs (Red, Yellow, Green)
    double redY = boxCenter.dy - 26;
    double yellowY = boxCenter.dy;
    double greenY = boxCenter.dy + 26;

    // Red Bulb
    Paint redBulb = Paint()..color = physicalLightState == LightColor.red ? Colors.redAccent : Colors.red[900]!.withOpacity(0.4);
    canvas.drawCircle(Offset(boxCenter.dx, redY), 10, redBulb);
    if (physicalLightState == LightColor.red) {
      canvas.drawCircle(Offset(boxCenter.dx, redY), 14, Paint()..color = Colors.red.withOpacity(0.35));
    }

    // Yellow Bulb
    Paint yellowBulb = Paint()..color = physicalLightState == LightColor.yellow ? Colors.amberAccent : Colors.amber[900]!.withOpacity(0.4);
    canvas.drawCircle(Offset(boxCenter.dx, yellowY), 10, yellowBulb);
    if (physicalLightState == LightColor.yellow) {
      canvas.drawCircle(Offset(boxCenter.dx, yellowY), 14, Paint()..color = Colors.amber.withOpacity(0.35));
    }

    // Green Bulb
    Paint greenBulb = Paint()..color = physicalLightState == LightColor.green ? Colors.greenAccent : Colors.green[900]!.withOpacity(0.4);
    canvas.drawCircle(Offset(boxCenter.dx, greenY), 10, greenBulb);
    if (physicalLightState == LightColor.green) {
      canvas.drawCircle(Offset(boxCenter.dx, greenY), 14, Paint()..color = Colors.green.withOpacity(0.35));
    }
  }

  void _drawCar(Canvas canvas, Offset pos, Color color, String label, bool isStopped, bool isViolating) {
    Rect carBox = Rect.fromCenter(center: pos, width: 75, height: 38);

    // Car Body
    Paint carPaint = Paint()..color = isViolating ? Colors.red : color;
    canvas.drawRRect(RRect.fromRectAndRadius(carBox, Radius.circular(6)), carPaint);

    // Roof
    Paint roofPaint = Paint()..color = Colors.white70;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: pos, width: 38, height: 26), Radius.circular(4)), roofPaint);

    // Headlights
    Paint lightPaint = Paint()..color = Colors.yellow;
    canvas.drawCircle(Offset(pos.dx + 36, pos.dy - 10), 3, lightPaint);
    canvas.drawCircle(Offset(pos.dx + 36, pos.dy + 10), 3, lightPaint);

    // Centroid Dot
    Paint dotPaint = Paint()..color = isStopped ? Colors.greenAccent : (isViolating ? Colors.yellowAccent : Colors.white);
    canvas.drawCircle(pos, 4, dotPaint);

    // Bounding Box
    Paint bbox = Paint()
      ..color = isViolating ? Colors.redAccent : color.withOpacity(0.7)
      ..strokeWidth = isViolating ? 2.5 : 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(carBox.inflate(2), bbox);

    TextPainter tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, backgroundColor: Colors.black87)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - 26));
  }

  String _getLightLabel(LightColor c) {
    switch (c) {
      case LightColor.green:
        return "GREEN";
      case LightColor.yellow:
        return "YELLOW";
      case LightColor.red:
        return "RED";
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
