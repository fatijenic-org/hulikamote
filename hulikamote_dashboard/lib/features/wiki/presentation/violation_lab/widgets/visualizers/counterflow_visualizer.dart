import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';

class CounterflowVisualizer extends StatefulWidget {
  @override
  _CounterflowVisualizerState createState() => _CounterflowVisualizerState();
}

enum AdminMode { drawROI, setDirection, drive }

class _CounterflowVisualizerState extends State<CounterflowVisualizer> {
  // Car State
  double vehicleAngle = 0.0;
  Offset carPos = Offset(100, 150);
  double speed = 4.0;
  Timer? _timer;

  // ROI State
  AdminMode currentMode = AdminMode.drawROI;
  List<Offset> roiPoints = [];
  int? _draggingRoiIndex;
  Offset? flowStart;
  Offset? flowEnd;
  double flowAngle = 0.0;

  // Undo/Redo State
  List<List<Offset>> _undoStack = [];
  List<List<Offset>> _redoStack = [];

  void _saveState() {
    _undoStack.add(List.from(roiPoints));
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isNotEmpty) {
      _redoStack.add(List.from(roiPoints));
      setState(() {
        roiPoints = _undoStack.removeLast();
      });
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      _undoStack.add(List.from(roiPoints));
      setState(() {
        roiPoints = _redoStack.removeLast();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Default initial setup to show something immediately
    roiPoints = [
      Offset(150, 100),
      Offset(600, 100),
      Offset(600, 250),
      Offset(150, 250)
    ];
    flowStart = Offset(250, 175);
    flowEnd = Offset(450, 175);
    flowAngle = 0.0;

    _timer = Timer.periodic(Duration(milliseconds: 33), (timer) {
      if (!mounted) return;
      if (currentMode == AdminMode.drive) {
        setState(() {
          double newX = carPos.dx + (cos(vehicleAngle) * speed);
          double newY = carPos.dy + (sin(vehicleAngle) * speed);
          
          // Using a 1000px bounds just for wrapping logic
          if (newX > 1000) newX = -50;
          if (newX < -50) newX = 1000;
          if (newY > 600) newY = -50;
          if (newY < -50) newY = 600;
          
          carPos = Offset(newX, newY);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool _isPointInPolygon(Offset point, List<Offset> polygon) {
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
    
    // We only want to intercept taps on the canvas side.
    if (localPos.dx > MediaQuery.of(context).size.width * 0.6) return;

    if (currentMode == AdminMode.drawROI) {
      // Find closest point within 30px
      for (int i = 0; i < roiPoints.length; i++) {
        if ((roiPoints[i] - localPos).distance < 30) {
          _saveState();
          setState(() {
            _draggingRoiIndex = i;
          });
          return;
        }
      }
      // If we clicked far from existing points, add a new one
      _saveState();
      setState(() {
        roiPoints.add(localPos);
        _draggingRoiIndex = roiPoints.length - 1;
      });
    } else if (currentMode == AdminMode.setDirection) {
      setState(() {
        flowStart = localPos;
        flowEnd = localPos;
      });
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    RenderBox box = context.findRenderObject() as RenderBox;
    Offset localPos = box.globalToLocal(details.globalPosition);

    if (localPos.dx > MediaQuery.of(context).size.width * 0.6) return;

    if (currentMode == AdminMode.drawROI && _draggingRoiIndex != null) {
      setState(() {
        roiPoints[_draggingRoiIndex!] = localPos;
      });
    } else if (currentMode == AdminMode.setDirection) {
      setState(() {
        flowEnd = localPos;
        flowAngle = atan2(flowEnd!.dy - flowStart!.dy, flowEnd!.dx - flowStart!.dx);
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      _draggingRoiIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 1. Is car in ROI?
    bool insideROI = _isPointInPolygon(carPos, roiPoints);
    
    // 2. Dot Product Math
    double refX = cos(flowAngle);
    double refY = sin(flowAngle);
    double vehX = cos(vehicleAngle);
    double vehY = sin(vehicleAngle);
    
    double dotProduct = (vehX * refX) + (vehY * refY);
    double angleDiff = acos(dotProduct.clamp(-1.0, 1.0)) * (180 / pi);
    double roundedAngleDiff = double.parse(angleDiff.toStringAsFixed(1));
    
    double displayVehicleAngle = (vehicleAngle * 180 / pi) % 360;
    if (displayVehicleAngle < 0) displayVehicleAngle += 360;

    double displayFlowAngle = (flowAngle * 180 / pi) % 360;
    if (displayFlowAngle < 0) displayFlowAngle += 360;

    double counterflowPercentage = (roundedAngleDiff / 180.0) * 100.0;
    
    bool isViolation = insideROI && roundedAngleDiff > 90.0;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: GestureDetector(
            onPanDown: _handlePanDown,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            onPanCancel: () => setState(() => _draggingRoiIndex = null),
            child: Container(
              color: Colors.grey[200],
              child: ClipRect(
                child: CustomPaint(
                  painter: _CounterflowPainter(
                    vehicleAngle: vehicleAngle, 
                    carPos: carPos,
                    roiPoints: roiPoints,
                    flowStart: flowStart,
                    flowEnd: flowEnd,
                    isViolation: isViolation,
                    insideROI: insideROI,
                    mode: currentMode
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
        Container(
          width: 380,
          padding: EdgeInsets.all(24),
          color: Colors.blueGrey[50],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Modern AI: Dynamic Setup", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text("Instead of hardcoding 'right is safe', Modern AI allows the admin to draw custom ROIs and set directional vectors dynamically per lane.", style: TextStyle(fontSize: 14)),
                      Divider(height: 32),

                      // Admin Modes
                      Text("1. Setup Region of Interest (ROI)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<AdminMode>(
                              title: Text("Adjust ROI Polygon", style: TextStyle(fontSize: 14)),
                              subtitle: Text("Drag or tap outside to add", style: TextStyle(fontSize: 12)),
                              value: AdminMode.drawROI,
                              groupValue: currentMode,
                              onChanged: (val) {
                                setState(() {
                                  currentMode = val!;
                                });
                              },
                            ),
                          ),
                          if (currentMode == AdminMode.drawROI) ...[
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
                                setState(() => roiPoints.clear());
                              },
                              tooltip: 'Clear',
                            )
                          ]
                        ],
                      ),

                      Text("2. Set Legal Flow Vector", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                      RadioListTile<AdminMode>(
                        title: Text("Draw Direction Arrow", style: TextStyle(fontSize: 14)),
                        subtitle: Text("Click and drag on canvas", style: TextStyle(fontSize: 12)),
                        value: AdminMode.setDirection,
                        groupValue: currentMode,
                        onChanged: (val) {
                          setState(() {
                            currentMode = val!;
                          });
                        },
                      ),

                      Text("3. Test AI Simulation", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800])),
                      RadioListTile<AdminMode>(
                        title: Text("Drive Vehicle", style: TextStyle(fontSize: 14)),
                        subtitle: Text("Test if logic holds up", style: TextStyle(fontSize: 12)),
                        value: AdminMode.drive,
                        groupValue: currentMode,
                        onChanged: (val) {
                          setState(() {
                            currentMode = val!;
                          });
                        },
                      ),

                      if (currentMode == AdminMode.drive) ...[
                        SizedBox(height: 16),
                        Text("Steer Vehicle:", style: TextStyle(fontWeight: FontWeight.bold)),
                        Slider(
                          value: vehicleAngle,
                          min: 0,
                          max: 2 * pi,
                          activeColor: Colors.orange,
                          onChanged: (val) {
                            setState(() {
                              vehicleAngle = val;
                            });
                          },
                        ),
                      ],
                      
                      Divider(height: 32),
                      Text("Real-Time Math Engine:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text("Car Angle: ${displayVehicleAngle.toStringAsFixed(1)}°"),
                      Text("Legal Flow: ${displayFlowAngle.toStringAsFixed(1)}°"),
                      Text("Difference (θ): ${roundedAngleDiff.toStringAsFixed(1)}°"),
                      Text(
                        "Counterflow Match: ${counterflowPercentage.toStringAsFixed(1)}%",
                        style: TextStyle(
                          color: counterflowPercentage > 50 ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold
                        ),
                      ),
                      Text("Inside ROI: ${insideROI ? 'YES' : 'NO'}"),
                    ],
                  ),
                ),
              ),
              Divider(height: 32),
              Text("System Conclusion:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: !insideROI ? Colors.grey[300] : (isViolation ? Colors.red[100] : Colors.green[100]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: !insideROI ? Colors.grey : (isViolation ? Colors.red : Colors.green), width: 2),
                ),
                child: Text(
                  !insideROI ? "CAR OUTSIDE ROI" : (isViolation ? "VIOLATION\n(Counterflow)" : "SAFE\n(Correct Flow)"),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: !insideROI ? Colors.grey[800] : (isViolation ? Colors.red[900] : Colors.green[900]), 
                    fontWeight: FontWeight.bold, 
                    fontSize: 18
                  ),
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}

class _CounterflowPainter extends CustomPainter {
  final double vehicleAngle;
  final Offset carPos;
  final List<Offset> roiPoints;
  final Offset? flowStart;
  final Offset? flowEnd;
  final bool isViolation;
  final bool insideROI;
  final AdminMode mode;

  _CounterflowPainter({
    required this.vehicleAngle, 
    required this.carPos,
    required this.roiPoints,
    required this.flowStart,
    required this.flowEnd,
    required this.isViolation,
    required this.insideROI,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Paint roadPaint = Paint()..color = Colors.grey[700]!..style = PaintingStyle.fill;
    Paint linePaint = Paint()..color = Colors.white..strokeWidth = 4..style = PaintingStyle.stroke;
    
    // Draw Road Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);
    
    // Draw ROI Polygon
    if (roiPoints.isNotEmpty) {
      Path roiPath = Path();
      roiPath.moveTo(roiPoints[0].dx, roiPoints[0].dy);
      for (int i=1; i<roiPoints.length; i++) {
        roiPath.lineTo(roiPoints[i].dx, roiPoints[i].dy);
      }
      roiPath.close();

      Paint roiFill = Paint()
        ..color = (mode == AdminMode.drawROI) ? Colors.blueAccent.withOpacity(0.5) : Colors.greenAccent.withOpacity(0.2)
        ..style = PaintingStyle.fill;
      canvas.drawPath(roiPath, roiFill);

      Paint roiStroke = Paint()
        ..color = (mode == AdminMode.drawROI) ? Colors.blue : Colors.greenAccent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(roiPath, roiStroke);
      
      // Draw points if editing
      if (mode == AdminMode.drawROI) {
        for (var p in roiPoints) {
          canvas.drawCircle(p, 5, Paint()..color = Colors.white);
        }
      }
    }

    // Draw Flow Arrow
    if (flowStart != null && flowEnd != null && (flowStart!.dx != flowEnd!.dx || flowStart!.dy != flowEnd!.dy)) {
      Paint refPaint = Paint()..color = (mode == AdminMode.setDirection) ? Colors.yellowAccent : Colors.white54..strokeWidth = 6;
      _drawArrow(canvas, flowStart!, flowEnd!, refPaint);
      
      TextPainter tp = TextPainter(
        text: TextSpan(text: "Legal Flow", style: TextStyle(color: refPaint.color, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(flowStart!.dx, flowStart!.dy - 20));
    }

    // Draw Vehicle
    canvas.save();
    canvas.translate(carPos.dx, carPos.dy);
    canvas.rotate(vehicleAngle);
    
    // Bounding Box
    Paint bboxPaint = Paint()
      ..color = !insideROI ? Colors.grey : (isViolation ? Colors.red : Colors.green)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 60, height: 30), bboxPaint);
    
    // Vehicle vector
    Paint vehPaint = Paint()..color = !insideROI ? Colors.grey : (isViolation ? Colors.redAccent : Colors.greenAccent)..strokeWidth = 4;
    _drawArrow(canvas, Offset.zero, Offset(80, 0), vehPaint);
    
    // Simple car shape inside bbox
    Paint carPaint = Paint()..color = Colors.orange;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 40, height: 20), Radius.circular(4)), carPaint);
    
    canvas.restore();
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    double dX = end.dx - start.dx;
    double dY = end.dy - start.dy;
    double angle = atan2(dY, dX);
    double arrowLength = 15;
    
    Offset p1 = Offset(end.dx - arrowLength * cos(angle - pi/6), end.dy - arrowLength * sin(angle - pi/6));
    Offset p2 = Offset(end.dx - arrowLength * cos(angle + pi/6), end.dy - arrowLength * sin(angle + pi/6));
    
    canvas.drawLine(end, p1, paint);
    canvas.drawLine(end, p2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
