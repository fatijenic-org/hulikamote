import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';

class IllegalTurnVisualizer extends StatefulWidget {
  @override
  _IllegalTurnVisualizerState createState() => _IllegalTurnVisualizerState();
}

enum AdminTurnMode { adjustPolygon, configureRules, driveCar }

class _IllegalTurnVisualizerState extends State<IllegalTurnVisualizer> {
  AdminTurnMode currentMode = AdminTurnMode.driveCar;

  // Intersection Polygon ROI vertices
  List<Offset> polygonPoints = [
    Offset(260, 120),
    Offset(440, 120),
    Offset(440, 300),
    Offset(260, 300),
  ];

  int? draggedPointIndex;

  // History stack for Undo/Redo
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

  // Configured Turn Rules for Intersection
  bool prohibitLeftTurn = true;
  bool prohibitRightTurn = false;
  bool prohibitUTurn = true;
  bool mustTurnOnly = false; // Prohibits going straight

  // Car State & Physics
  Offset carPos = Offset(350, 420); // Spawns from South heading North
  double carAngle = -math.pi / 2; // Heading North (-90 deg)
  double targetAngle = -math.pi / 2;
  double carSpeed = 0.0;
  
  // Joystick Interaction States
  bool isJoystickActive = false;
  Offset? canvasJoyOrigin;
  Offset? canvasJoyCurrent;
  Offset panelJoyKnob = Offset.zero;
  final double maxJoyRadius = 50.0;

  // Tracking Trajectory & Turn Analysis
  List<Offset> trajectory = [];
  Offset? entryPoint;
  double? entryAngle;
  double accumulatedTurnAngle = 0.0;
  bool enteredIntersection = false;
  String currentManeuver = "STRAIGHT";
  bool isViolation = false;
  String violationReason = "";

  Timer? _gameLoopTimer;

  @override
  void initState() {
    super.initState();
    // 30 FPS Physics Loop
    _gameLoopTimer = Timer.periodic(Duration(milliseconds: 33), (timer) {
      if (!mounted) return;
      _updatePhysics();
    });
  }

  @override
  void dispose() {
    _gameLoopTimer?.cancel();
    super.dispose();
  }

  double _lerpAngle(double current, double target, double t) {
    double diff = (target - current + math.pi) % (2 * math.pi) - math.pi;
    return current + diff * t;
  }

  void _updatePhysics() {
    setState(() {
      if (isJoystickActive) {
        // Smoothly steer car towards joystick pull angle
        carAngle = _lerpAngle(carAngle, targetAngle, 0.28);
      } else {
        // Friction deceleration when joystick released
        carSpeed *= 0.85;
        if (carSpeed.abs() < 0.05) carSpeed = 0.0;
      }

      // Move car
      if (carSpeed > 0.01) {
        double newX = carPos.dx + math.cos(carAngle) * carSpeed;
        double newY = carPos.dy + math.sin(carAngle) * carSpeed;
        carPos = Offset(newX, newY);

        // Record Trajectory
        trajectory.add(carPos);
        if (trajectory.length > 50) {
          trajectory.removeAt(0);
        }
      }

      // Intersection Analysis
      bool inside = _isPointInPolygon(carPos, polygonPoints);

      if (inside && !enteredIntersection) {
        enteredIntersection = true;
        entryPoint = carPos;
        entryAngle = carAngle;
        accumulatedTurnAngle = 0.0;
      } else if (inside && enteredIntersection && entryAngle != null) {
        double angleDiff = carAngle - entryAngle!;
        angleDiff = (angleDiff + math.pi) % (2 * math.pi) - math.pi;
        accumulatedTurnAngle = angleDiff * 180 / math.pi;

        // Classify maneuver
        if (accumulatedTurnAngle < -45 && accumulatedTurnAngle >= -135) {
          currentManeuver = "LEFT TURN";
        } else if (accumulatedTurnAngle > 45 && accumulatedTurnAngle <= 135) {
          currentManeuver = "RIGHT TURN";
        } else if (accumulatedTurnAngle.abs() > 135) {
          currentManeuver = "U-TURN";
        } else {
          currentManeuver = "STRAIGHT";
        }

        // Check against rules
        if (currentManeuver == "LEFT TURN" && prohibitLeftTurn) {
          isViolation = true;
          violationReason = "NO LEFT TURN VIOLATION";
        } else if (currentManeuver == "RIGHT TURN" && prohibitRightTurn) {
          isViolation = true;
          violationReason = "NO RIGHT TURN VIOLATION";
        } else if (currentManeuver == "U-TURN" && prohibitUTurn) {
          isViolation = true;
          violationReason = "ILLEGAL U-TURN VIOLATION";
        } else if (currentManeuver == "STRAIGHT" && mustTurnOnly) {
          isViolation = true;
          violationReason = "MUST TURN ONLY (Straight Prohibited)";
        } else {
          isViolation = false;
          violationReason = "";
        }
      } else if (!inside && enteredIntersection) {
        enteredIntersection = false;
      }
    });
  }

  void _resetCar(String approach) {
    setState(() {
      trajectory.clear();
      enteredIntersection = false;
      entryPoint = null;
      entryAngle = null;
      accumulatedTurnAngle = 0.0;
      currentManeuver = "STRAIGHT";
      isViolation = false;
      violationReason = "";
      carSpeed = 0.0;
      isJoystickActive = false;
      canvasJoyOrigin = null;
      canvasJoyCurrent = null;
      panelJoyKnob = Offset.zero;

      switch (approach) {
        case "South":
          carPos = Offset(350, 420);
          carAngle = -math.pi / 2; // North
          targetAngle = -math.pi / 2;
          break;
        case "North":
          carPos = Offset(350, 20);
          carAngle = math.pi / 2; // South
          targetAngle = math.pi / 2;
          break;
        case "West":
          carPos = Offset(50, 210);
          carAngle = 0; // East
          targetAngle = 0;
          break;
        case "East":
          carPos = Offset(650, 210);
          carAngle = math.pi; // West
          targetAngle = math.pi;
          break;
      }
    });
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

  // Canvas gestures for ROI editing and direct Joystick pulling
  void _handlePanDown(DragDownDetails details) {
    RenderBox box = context.findRenderObject() as RenderBox;
    Offset localPos = box.globalToLocal(details.globalPosition);

    if (localPos.dx > MediaQuery.of(context).size.width * 0.6) return;

    if (currentMode == AdminTurnMode.adjustPolygon) {
      for (int i = 0; i < polygonPoints.length; i++) {
        if ((polygonPoints[i] - localPos).distance < 25) {
          _saveState();
          setState(() {
            draggedPointIndex = i;
          });
          return;
        }
      }
      _saveState();
      setState(() {
        polygonPoints.add(localPos);
        draggedPointIndex = polygonPoints.length - 1;
      });
    } else if (currentMode == AdminTurnMode.driveCar) {
      // Direct on-canvas Joystick pull!
      setState(() {
        isJoystickActive = true;
        canvasJoyOrigin = localPos;
        canvasJoyCurrent = localPos;
      });
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    RenderBox box = context.findRenderObject() as RenderBox;
    Offset localPos = box.globalToLocal(details.globalPosition);

    if (localPos.dx > MediaQuery.of(context).size.width * 0.6) return;

    if (currentMode == AdminTurnMode.adjustPolygon && draggedPointIndex != null) {
      setState(() {
        polygonPoints[draggedPointIndex!] = localPos;
      });
    } else if (currentMode == AdminTurnMode.driveCar && canvasJoyOrigin != null) {
      setState(() {
        canvasJoyCurrent = localPos;
        Offset diff = canvasJoyCurrent! - canvasJoyOrigin!;
        double dist = diff.distance;
        double maxPull = 90.0;
        double throttle = (dist / maxPull).clamp(0.0, 1.0);

        if (dist > 5.0) {
          targetAngle = math.atan2(diff.dy, diff.dx);
          carSpeed = throttle * 6.0; // Max speed: 6.0 px/frame (~60 km/h)
        } else {
          carSpeed = 0.0;
        }
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      draggedPointIndex = null;
      if (currentMode == AdminTurnMode.driveCar) {
        isJoystickActive = false;
        canvasJoyOrigin = null;
        canvasJoyCurrent = null;
      }
    });
  }

  // Right-Panel Virtual Joystick Handlers
  void _handlePanelJoyUpdate(Offset localOffset, Size size) {
    Offset center = Offset(size.width / 2, size.height / 2);
    Offset diff = localOffset - center;
    double dist = diff.distance;
    double clampedDist = math.min(dist, maxJoyRadius);
    double angle = math.atan2(diff.dy, diff.dx);

    Offset knob = Offset(
      math.cos(angle) * clampedDist,
      math.sin(angle) * clampedDist,
    );

    double throttle = (clampedDist / maxJoyRadius).clamp(0.0, 1.0);

    setState(() {
      isJoystickActive = true;
      panelJoyKnob = knob;
      targetAngle = angle;
      carSpeed = throttle * 6.0;
    });
  }

  void _handlePanelJoyEnd() {
    setState(() {
      isJoystickActive = false;
      panelJoyKnob = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool inside = _isPointInPolygon(carPos, polygonPoints);
    double displaySpeedKmH = (carSpeed / 6.0) * 60.0;

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
              draggedPointIndex = null;
              isJoystickActive = false;
              canvasJoyOrigin = null;
              canvasJoyCurrent = null;
            }),
            child: Container(
              color: Colors.grey[850],
              child: ClipRect(
                child: CustomPaint(
                  painter: _IntersectionPainter(
                    polygonPoints: polygonPoints,
                    carPos: carPos,
                    carAngle: carAngle,
                    trajectory: trajectory,
                    inside: inside,
                    isViolation: isViolation,
                    mode: currentMode,
                    prohibitLeftTurn: prohibitLeftTurn,
                    prohibitRightTurn: prohibitRightTurn,
                    prohibitUTurn: prohibitUTurn,
                    canvasJoyOrigin: canvasJoyOrigin,
                    canvasJoyCurrent: canvasJoyCurrent,
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
                      Text("Modern AI: Dynamic Intersection & Joystick", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      SizedBox(height: 8),
                      Text(
                        "Click and pull the joystick in any direction—the vehicle steers toward your cursor, and speed scales dynamically the further you pull!",
                        style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.3),
                      ),
                      Divider(height: 20),

                      // Mode Switcher Tabs
                      Text("Configuration Modes:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          _buildModeChip("🛠️ 1. ROI", AdminTurnMode.adjustPolygon),
                          SizedBox(width: 4),
                          _buildModeChip("📜 2. Rules", AdminTurnMode.configureRules),
                          SizedBox(width: 4),
                          _buildModeChip("🕹️ 3. Drive", AdminTurnMode.driveCar),
                        ],
                      ),
                      SizedBox(height: 12),

                      // MODE 1: ROI Polygon Editor
                      if (currentMode == AdminTurnMode.adjustPolygon) ...[
                        Row(
                          children: [
                            Text("Adjust ROI Polygon", style: TextStyle(fontWeight: FontWeight.bold)),
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
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 20),
                              color: Colors.red,
                              onPressed: () {
                                _saveState();
                                setState(() => polygonPoints.clear());
                              },
                              tooltip: 'Clear',
                            )
                          ],
                        ),
                        Text("Drag yellow corners or tap to add intersection vertices.", style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      ],

                      // MODE 2: Rules Configuration
                      if (currentMode == AdminTurnMode.configureRules) ...[
                        Text("Configure Intersection Rules:", style: TextStyle(fontWeight: FontWeight.bold)),
                        CheckboxListTile(
                          dense: true,
                          title: Text("🚫 Prohibit Left Turn (No Left Turn)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          value: prohibitLeftTurn,
                          activeColor: Colors.redAccent,
                          onChanged: (val) => setState(() => prohibitLeftTurn = val!),
                        ),
                        CheckboxListTile(
                          dense: true,
                          title: Text("🚫 Prohibit Right Turn (No Right Turn)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          value: prohibitRightTurn,
                          activeColor: Colors.redAccent,
                          onChanged: (val) => setState(() => prohibitRightTurn = val!),
                        ),
                        CheckboxListTile(
                          dense: true,
                          title: Text("🚫 Prohibit U-Turn (No U-Turn)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          value: prohibitUTurn,
                          activeColor: Colors.redAccent,
                          onChanged: (val) => setState(() => prohibitUTurn = val!),
                        ),
                        CheckboxListTile(
                          dense: true,
                          title: Text("↪️ Must Turn Only (No Straight)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          value: mustTurnOnly,
                          activeColor: Colors.orangeAccent,
                          onChanged: (val) => setState(() => mustTurnOnly = val!),
                        ),
                      ],

                      // MODE 3: Virtual Analog Joystick
                      if (currentMode == AdminTurnMode.driveCar) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Quick Spawn Approach:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                            Wrap(
                              spacing: 4,
                              children: [
                                _buildSpawnBtn("South", "South"),
                                _buildSpawnBtn("North", "North"),
                                _buildSpawnBtn("West", "West"),
                                _buildSpawnBtn("East", "East"),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 12),

                        // Analog Joystick Widget
                        Center(
                          child: Column(
                            children: [
                              Text("Analog Joystick (Pull & Aim):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              SizedBox(height: 8),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  double joySize = 130;
                                  return GestureDetector(
                                    onPanStart: (d) => _handlePanelJoyUpdate(d.localPosition, Size(joySize, joySize)),
                                    onPanUpdate: (d) => _handlePanelJoyUpdate(d.localPosition, Size(joySize, joySize)),
                                    onPanEnd: (_) => _handlePanelJoyEnd(),
                                    onPanCancel: () => _handlePanelJoyEnd(),
                                    child: Container(
                                      width: joySize,
                                      height: joySize,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: RadialGradient(
                                          colors: [Colors.grey[300]!, Colors.blueGrey[200]!],
                                        ),
                                        border: Border.all(color: Colors.blueGrey[400]!, width: 3),
                                        boxShadow: [
                                          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
                                        ],
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // Crosshairs
                                          CustomPaint(
                                            size: Size(joySize, joySize),
                                            painter: _JoystickCrosshairPainter(),
                                          ),
                                          // Knob
                                          Transform.translate(
                                            offset: panelJoyKnob,
                                            child: Container(
                                              width: 46,
                                              height: 46,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [Colors.blueAccent, Colors.blue[900]!],
                                                ),
                                                boxShadow: [
                                                  BoxShadow(color: Colors.blueAccent.withOpacity(0.4), blurRadius: 8, spreadRadius: 1),
                                                ],
                                              ),
                                              child: Icon(Icons.navigation, color: Colors.white, size: 22),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              SizedBox(height: 6),
                              Text("💡 Tip: You can also click & pull directly on the canvas road!", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            ],
                          ),
                        ),
                      ],

                      Divider(height: 20),
                      Text("Real-Time Telemetry & Vector:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Live Speed: ${displaySpeedKmH.toStringAsFixed(0)} km/h", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                          Text("Throttle: ${((carSpeed / 6.0) * 100).toStringAsFixed(0)}%"),
                        ],
                      ),
                      SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: (carSpeed / 6.0).clamp(0.0, 1.0),
                        backgroundColor: Colors.grey[300],
                        color: Colors.blueAccent,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      SizedBox(height: 6),
                      Text("Inside Intersection: ${inside ? 'YES (Active Tracking)' : 'NO (Approach)'}"),
                      Text("Turn Angle (Δθ): ${accumulatedTurnAngle.toStringAsFixed(1)}°"),
                      Text("Detected Maneuver: $currentManeuver", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                    ],
                  ),
                ),
              ),
              Divider(height: 1),
              Container(
                padding: EdgeInsets.all(16),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isViolation ? Colors.red[100] : (inside ? Colors.blue[100] : Colors.green[100]),
                ),
                child: Column(
                  children: [
                    Text("AI Intersection Enforcement Decision:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[800])),
                    SizedBox(height: 4),
                    Text(
                      isViolation 
                          ? "VIOLATION DETECTED!\n$violationReason"
                          : (inside ? "LEGAL MANEUVER ($currentManeuver)\nIn Compliance with Rules" : "APPROACHING / SAFE\nNo Infraction Detected"),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isViolation ? Colors.red[900] : (inside ? Colors.blue[900] : Colors.green[900]),
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

  Widget _buildModeChip(String title, AdminTurnMode mode) {
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
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : Colors.grey[800],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpawnBtn(String label, String approach) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: Size(45, 26),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Colors.blueGrey[800],
      ),
      onPressed: () => _resetCar(approach),
      child: Text(label, style: TextStyle(fontSize: 10, color: Colors.white)),
    );
  }
}

class _JoystickCrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Paint linePaint = Paint()..color = Colors.blueGrey[300]!..strokeWidth = 1.5;
    Offset center = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(Offset(center.dx, 10), Offset(center.dx, size.height - 10), linePaint);
    canvas.drawLine(Offset(10, center.dy), Offset(size.width - 10, center.dy), linePaint);
    canvas.drawCircle(center, 30, Paint()..color = Colors.blueGrey[300]!..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _IntersectionPainter extends CustomPainter {
  final List<Offset> polygonPoints;
  final Offset carPos;
  final double carAngle;
  final List<Offset> trajectory;
  final bool inside;
  final bool isViolation;
  final AdminTurnMode mode;
  final bool prohibitLeftTurn;
  final bool prohibitRightTurn;
  final bool prohibitUTurn;
  final Offset? canvasJoyOrigin;
  final Offset? canvasJoyCurrent;

  _IntersectionPainter({
    required this.polygonPoints,
    required this.carPos,
    required this.carAngle,
    required this.trajectory,
    required this.inside,
    required this.isViolation,
    required this.mode,
    required this.prohibitLeftTurn,
    required this.prohibitRightTurn,
    required this.prohibitUTurn,
    this.canvasJoyOrigin,
    this.canvasJoyCurrent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw 4-Way Crossroad Asphalt
    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(260, 0, 180, size.height), roadPaint);
    canvas.drawRect(Rect.fromLTWH(0, 120, size.width, 180), roadPaint);

    // 2. Road Markings & Lane dividers
    Paint laneLine = Paint()..color = Colors.white60..strokeWidth = 2..style = PaintingStyle.stroke;
    _drawDashedLine(canvas, Offset(350, 300), Offset(350, size.height), laneLine);
    _drawDashedLine(canvas, Offset(350, 0), Offset(350, 120), laneLine);
    _drawDashedLine(canvas, Offset(0, 210), Offset(260, 210), laneLine);
    _drawDashedLine(canvas, Offset(440, 210), Offset(size.width, 210), laneLine);

    // Stop lines
    Paint stopLinePaint = Paint()..color = Colors.white..strokeWidth = 4;
    canvas.drawLine(Offset(260, 300), Offset(350, 300), stopLinePaint);
    canvas.drawLine(Offset(350, 120), Offset(440, 120), stopLinePaint);
    canvas.drawLine(Offset(260, 120), Offset(260, 210), stopLinePaint);
    canvas.drawLine(Offset(440, 210), Offset(440, 300), stopLinePaint);

    // 3. Draw Intersection Polygon ROI
    if (polygonPoints.isNotEmpty) {
      Path path = Path();
      path.moveTo(polygonPoints[0].dx, polygonPoints[0].dy);
      for (int i = 1; i < polygonPoints.length; i++) {
        path.lineTo(polygonPoints[i].dx, polygonPoints[i].dy);
      }
      path.close();

      Paint zoneFill = Paint()
        ..color = (isViolation ? Colors.red : (inside ? Colors.blue : Colors.yellow)).withOpacity(0.2)
        ..style = PaintingStyle.fill;
      Paint zoneBorder = Paint()
        ..color = isViolation ? Colors.redAccent : (inside ? Colors.blueAccent : Colors.yellowAccent)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, zoneFill);
      canvas.drawPath(path, zoneBorder);

      // Draw ROI Vertices handles
      if (mode == AdminTurnMode.adjustPolygon) {
        Paint handlePaint = Paint()..color = Colors.yellowAccent;
        for (Offset p in polygonPoints) {
          canvas.drawCircle(p, 8, handlePaint);
          canvas.drawCircle(p, 8, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2);
        }
      }

      TextPainter tpTag = TextPainter(
        text: TextSpan(
          text: "INTERSECTION ROI (Z_int)",
          style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 11, backgroundColor: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      );
      tpTag.layout();
      tpTag.paint(canvas, Offset(polygonPoints[0].dx + 6, polygonPoints[0].dy + 6));
    }

    // 4. Draw Trajectory Breadcrumbs
    if (trajectory.length > 1) {
      Paint trajPaint = Paint()..color = isViolation ? Colors.redAccent : Colors.cyanAccent..strokeWidth = 2.5;
      for (int i = 0; i < trajectory.length - 1; i++) {
        canvas.drawLine(trajectory[i], trajectory[i + 1], trajPaint);
      }
    }

    // 5. Draw Vehicle
    canvas.save();
    canvas.translate(carPos.dx, carPos.dy);
    canvas.rotate(carAngle);

    // Car Body
    Paint carPaint = Paint()..color = isViolation ? Colors.redAccent : (inside ? Colors.cyanAccent : Colors.blueAccent);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 50, height: 26), Radius.circular(5)), carPaint);

    // Windshield
    Paint glassPaint = Paint()..color = Colors.white70;
    canvas.drawRect(Rect.fromLTWH(8, -10, 10, 20), glassPaint);

    // Headlights
    Paint lightPaint = Paint()..color = Colors.yellow;
    canvas.drawCircle(Offset(24, -8), 3, lightPaint);
    canvas.drawCircle(Offset(24, 8), 3, lightPaint);

    // Heading Arrow
    Paint arrowPaint = Paint()..color = Colors.orangeAccent..strokeWidth = 3;
    _drawArrow(canvas, Offset.zero, Offset(35, 0), arrowPaint);

    canvas.restore();

    // 6. Draw On-Canvas Dynamic Joystick / Cursor Pull
    if (canvasJoyOrigin != null && canvasJoyCurrent != null) {
      // Base circle
      Paint joyBase = Paint()..color = Colors.blueAccent.withOpacity(0.25)..style = PaintingStyle.fill;
      Paint joyBaseBorder = Paint()..color = Colors.blueAccent.withOpacity(0.7)..style = PaintingStyle.stroke..strokeWidth = 2;
      canvas.drawCircle(canvasJoyOrigin!, 40, joyBase);
      canvas.drawCircle(canvasJoyOrigin!, 40, joyBaseBorder);

      // Connecting pull vector line
      Paint joyLine = Paint()..color = Colors.orangeAccent..strokeWidth = 3..strokeCap = StrokeCap.round;
      canvas.drawLine(canvasJoyOrigin!, canvasJoyCurrent!, joyLine);

      // Handle at cursor position
      Paint joyKnob = Paint()..color = Colors.orangeAccent..style = PaintingStyle.fill;
      canvas.drawCircle(canvasJoyCurrent!, 14, joyKnob);
      canvas.drawCircle(canvasJoyCurrent!, 14, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
    }

    // 7. Restriction Signs Over Road
    if (prohibitLeftTurn) {
      _drawSignBadge(canvas, "NO LEFT 🚫↰", Offset(140, 70), Colors.red[800]!);
    }
    if (prohibitRightTurn) {
      _drawSignBadge(canvas, "NO RIGHT 🚫↱", Offset(480, 70), Colors.red[800]!);
    }
    if (prohibitUTurn) {
      _drawSignBadge(canvas, "NO U-TURN 🚫↷", Offset(300, 370), Colors.red[800]!);
    }
  }

  void _drawSignBadge(Canvas canvas, String text, Offset pos, Color color) {
    TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    Paint bgPaint = Paint()..color = color;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(pos.dx - 6, pos.dy - 3, tp.width + 12, tp.height + 6), Radius.circular(4)), bgPaint);
    tp.paint(canvas, pos);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    double distance = (end - start).distance;
    double dashWidth = 15;
    double dashSpace = 15;
    double dx = (end.dx - start.dx) / distance;
    double dy = (end.dy - start.dy) / distance;
    double current = 0.0;

    while (current < distance) {
      Offset p1 = Offset(start.dx + dx * current, start.dy + dy * current);
      double next = math.min(current + dashWidth, distance);
      Offset p2 = Offset(start.dx + dx * next, start.dy + dy * next);
      canvas.drawLine(p1, p2, paint);
      current += dashWidth + dashSpace;
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    double dX = end.dx - start.dx;
    double dY = end.dy - start.dy;
    double a = math.atan2(dY, dX);
    double arrowLength = 10;
    Offset p1 = Offset(end.dx - arrowLength * math.cos(a - math.pi / 6), end.dy - arrowLength * math.sin(a - math.pi / 6));
    Offset p2 = Offset(end.dx - arrowLength * math.cos(a + math.pi / 6), end.dy - arrowLength * math.sin(a + math.pi / 6));
    canvas.drawLine(end, p1, paint);
    canvas.drawLine(end, p2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
