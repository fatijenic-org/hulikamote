import 'package:flutter/material.dart';
import 'dart:math' as math;

class IllegalTurnFirstPrinciple extends StatefulWidget {
  @override
  _IllegalTurnFirstPrincipleState createState() => _IllegalTurnFirstPrincipleState();
}

class _IllegalTurnFirstPrincipleState extends State<IllegalTurnFirstPrinciple> {
  int activeTab = 0; // 0: Vector Math, 1: AI Roles & Pipeline

  // Vector Math State
  Offset entryPoint = Offset(100, 300);
  Offset exitPoint = Offset(400, 100);

  // AI Pipeline Stepper State
  int pipelineStage = 0; // 0: Raw Frame, 1: YOLO Box, 2: ByteTrack Centroid, 3: Trajectory Path, 4: Vector Angle

  @override
  Widget build(BuildContext context) {
    Offset center = Offset(250, 200);

    // Vector entry & exit
    double entryDx = center.dx - entryPoint.dx;
    double entryDy = center.dy - entryPoint.dy;
    double exitDx = exitPoint.dx - center.dx;
    double exitDy = exitPoint.dy - center.dy;

    double entryAngle = math.atan2(entryDy, entryDx);
    double exitAngle = math.atan2(exitDy, exitDx);

    double turnAngle = (exitAngle - entryAngle) * (180 / math.pi);
    if (turnAngle > 180) turnAngle -= 360;
    if (turnAngle < -180) turnAngle += 360;

    String turnType = "Straight";
    bool isIllegal = false;

    if (turnAngle.abs() < 30) {
      turnType = "Straight";
    } else if (turnAngle >= 30 && turnAngle < 120) {
      turnType = "Right Turn";
      isIllegal = true; // Right turn prohibited in demo rule
    } else if (turnAngle <= -30 && turnAngle > -120) {
      turnType = "Left Turn";
    } else {
      turnType = "U-Turn";
      isIllegal = true;
    }

    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: GestureDetector(
            onPanUpdate: (details) {
              if (activeTab == 0) {
                setState(() {
                  exitPoint += details.delta;
                });
              }
            },
            child: Container(
              color: Colors.grey[850],
              child: ClipRect(
                child: CustomPaint(
                  painter: _IllegalTurnFPPainter(
                    activeTab: activeTab,
                    entryPoint: entryPoint,
                    exitPoint: exitPoint,
                    center: center,
                    turnAngle: turnAngle,
                    turnType: turnType,
                    isIllegal: isIllegal,
                    pipelineStage: pipelineStage,
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
              // Tab Switcher
              Container(
                margin: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _buildTabButton("1. Path & Angle Math", 0),
                    _buildTabButton("2. AI Architecture", 1),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: activeTab == 0 ? _buildMathControls(entryAngle, exitAngle, turnAngle, turnType, isIllegal) : _buildAIPipelineControls(),
                ),
              ),

              // Bottom Decision Box
              Divider(height: 1),
              Container(
                padding: EdgeInsets.all(16),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: activeTab == 0 
                      ? (isIllegal ? Colors.red[100] : Colors.green[100])
                      : Colors.blue[100],
                ),
                child: Column(
                  children: [
                    Text(
                      activeTab == 0 ? "Mathematical Maneuver:" : "Active AI Component:", 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[800]),
                    ),
                    SizedBox(height: 4),
                    Text(
                      activeTab == 0 
                          ? "$turnType (${turnAngle.toStringAsFixed(1)}°)\n${isIllegal ? 'VIOLATION (Prohibited)' : 'LEGAL MANEUVER'}"
                          : _getStageSummary(pipelineStage),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: activeTab == 0 
                            ? (isIllegal ? Colors.red[900] : Colors.green[900])
                            : Colors.blue[900],
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

  Widget _buildTabButton(String label, int index) {
    bool isSelected = activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => activeTab = index),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blueGrey[900] : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMathControls(double entryAngle, double exitAngle, double turnAngle, String turnType, bool isIllegal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Core Concept: The Vector Angle of Steering", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        SizedBox(height: 12),
        Text(
          "Instead of rigid tripwires, modern AI captures the car's path as continuous vector coordinates, then computes the turning curvature with arctan2.",
          style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.3),
        ),
        Divider(height: 24),

        Text("1. Interactive Path Vector:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
        SizedBox(height: 6),
        Text("Drag the orange/green Exit Node on the canvas to see how the mathematical turning angle changes in real time.", style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        SizedBox(height: 16),

        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Vector Math Breakdown:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              SizedBox(height: 6),
              Text("Entry Vector Angle: ${(entryAngle * 180 / math.pi).toStringAsFixed(1)}°"),
              Text("Exit Vector Angle: ${(exitAngle * 180 / math.pi).toStringAsFixed(1)}°"),
              Divider(height: 16),
              Text("Turn Angle Δθ = θ_exit - θ_entry:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              Text("${turnAngle.toStringAsFixed(1)}°", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: isIllegal ? Colors.red : Colors.green[800])),
            ],
          ),
        ),
        SizedBox(height: 14),

        Text("Configured Rule in this Demo:\n• Straight: Allowed\n• Left Turn: Allowed\n• Right Turn: PROHIBITED (Violation)\n• U-Turn: PROHIBITED (Violation)", style: TextStyle(fontSize: 12, color: Colors.grey[800])),
      ],
    );
  }

  Widget _buildAIPipelineControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Who Does What: The AI Pipeline", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        SizedBox(height: 10),
        Text("How does the computer actually extract the car's path from raw video frames? Step through the 5-layer AI architecture below:", style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.3)),
        Divider(height: 20),

        _buildStageRadio(0, "1. Raw Video Frame", "Camera sends RGB pixel frames (30 FPS)"),
        _buildStageRadio(1, "2. YOLOv8 Object Detection", "Extracts bounding box [x, y, w, h] and class 'car'"),
        _buildStageRadio(2, "3. ByteTrack Tracker", "Assigns persistent Track ID & bottom centroid (cx, cy)"),
        _buildStageRadio(3, "4. Path Trajectory Buffer", "Stores past centroid sequence: T = {(x1,y1), ..., (xt,yt)}"),
        _buildStageRadio(4, "5. Trigonometry Math Engine", "Computes Δθ = atan2(v_out) - atan2(v_in) & compares to rules"),
      ],
    );
  }

  Widget _buildStageRadio(int stage, String title, String subtitle) {
    bool isSelected = pipelineStage == stage;
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue[50] : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isSelected ? Colors.blueAccent : Colors.grey[300]!),
      ),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? Colors.blue[900] : Colors.black87)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        leading: Radio<int>(
          value: stage,
          groupValue: pipelineStage,
          activeColor: Colors.blueAccent,
          onChanged: (val) => setState(() => pipelineStage = val!),
        ),
        onTap: () => setState(() => pipelineStage = stage),
      ),
    );
  }

  String _getStageSummary(int stage) {
    switch (stage) {
      case 0:
        return "Raw Camera Feed (No AI Active)";
      case 1:
        return "YOLOv8: Bounding Box Detection (Conf: 0.94)";
      case 2:
        return "ByteTrack: Multi-Object Tracking (ID: #104)";
      case 3:
        return "Centroid Path Buffer (30 Frames History)";
      case 4:
        return "Vector Trigonometry: Angle & Rule Checker";
      default:
        return "";
    }
  }
}

class _IllegalTurnFPPainter extends CustomPainter {
  final int activeTab;
  final Offset entryPoint;
  final Offset exitPoint;
  final Offset center;
  final double turnAngle;
  final String turnType;
  final bool isIllegal;
  final int pipelineStage;

  _IllegalTurnFPPainter({
    required this.activeTab,
    required this.entryPoint,
    required this.exitPoint,
    required this.center,
    required this.turnAngle,
    required this.turnType,
    required this.isIllegal,
    required this.pipelineStage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (activeTab == 0) {
      _paintVectorMath(canvas, size);
    } else {
      _paintAIPipeline(canvas, size);
    }
  }

  void _paintVectorMath(Canvas canvas, Size size) {
    // Road cross intersection
    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(center.dx - 80, 0, 160, size.height), roadPaint);
    canvas.drawRect(Rect.fromLTWH(0, center.dy - 80, size.width, 160), roadPaint);

    // Center Intersection Box
    Paint centerBox = Paint()..color = Colors.yellow.withOpacity(0.15)..style = PaintingStyle.fill;
    Paint centerBorder = Paint()..color = Colors.yellowAccent.withOpacity(0.5)..strokeWidth = 2..style = PaintingStyle.stroke;
    Rect boxRect = Rect.fromCenter(center: center, width: 160, height: 160);
    canvas.drawRect(boxRect, centerBox);
    canvas.drawRect(boxRect, centerBorder);

    // Entry Vector (Blue)
    Paint entryPaint = Paint()..color = Colors.blueAccent..strokeWidth = 5..strokeCap = StrokeCap.round;
    _drawArrow(canvas, entryPoint, center, entryPaint);
    _drawNodeLabel(canvas, "Entry Vector (v_in)", entryPoint, Colors.blueAccent);

    // Exit Vector (Orange / Red / Green based on turn)
    Paint exitPaint = Paint()..color = isIllegal ? Colors.redAccent : Colors.greenAccent..strokeWidth = 5..strokeCap = StrokeCap.round;
    _drawArrow(canvas, center, exitPoint, exitPaint);
    _drawNodeLabel(canvas, "Exit Vector (v_out)", exitPoint, isIllegal ? Colors.redAccent : Colors.greenAccent);

    // Arc indicating turn angle
    Paint arcPaint = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    double entryAngle = math.atan2(center.dy - entryPoint.dy, center.dx - entryPoint.dx);
    double exitAngle = math.atan2(exitPoint.dy - center.dy, exitPoint.dx - center.dx);
    double sweep = (exitAngle - entryAngle);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 45),
      entryAngle,
      sweep,
      false,
      arcPaint,
    );

    // Angle badge in center
    TextPainter tp = TextPainter(
      text: TextSpan(
        text: "Δθ = ${turnAngle.toStringAsFixed(1)}°\n$turnType",
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, backgroundColor: Colors.black87),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    tp.layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - 35));
  }

  void _paintAIPipeline(Canvas canvas, Size size) {
    // Road background
    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    Offset carPos = Offset(size.width * 0.45, size.height * 0.45);
    Rect carBox = Rect.fromCenter(center: carPos, width: 90, height: 48);

    // 1. Raw Frame: Draw vehicle
    Paint carPaint = Paint()..color = Colors.blueAccent;
    canvas.drawRRect(RRect.fromRectAndRadius(carBox, Radius.circular(6)), carPaint);

    Paint roofPaint = Paint()..color = Colors.white70;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: carPos, width: 45, height: 30), Radius.circular(4)), roofPaint);

    // 2. YOLOv8: Bounding Box
    if (pipelineStage >= 1) {
      Paint bboxPaint = Paint()..color = Colors.greenAccent..strokeWidth = 2.5..style = PaintingStyle.stroke;
      canvas.drawRect(carBox.inflate(4), bboxPaint);

      TextPainter tpYolo = TextPainter(
        text: TextSpan(
          text: "YOLOv8: car 0.94",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11, backgroundColor: Colors.greenAccent),
        ),
        textDirection: TextDirection.ltr,
      );
      tpYolo.layout();
      tpYolo.paint(canvas, Offset(carBox.left - 4, carBox.top - 18));
    }

    // 3. ByteTrack: Centroid & ID
    if (pipelineStage >= 2) {
      Paint dotPaint = Paint()..color = Colors.redAccent;
      canvas.drawCircle(carPos, 6, dotPaint);
      canvas.drawCircle(carPos, 6, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);

      TextPainter tpTrack = TextPainter(
        text: TextSpan(
          text: "ByteTrack ID #104\nCentroid (${carPos.dx.toStringAsFixed(0)}, ${carPos.dy.toStringAsFixed(0)})",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, backgroundColor: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tpTrack.layout();
      tpTrack.paint(canvas, Offset(carPos.dx - tpTrack.width / 2, carPos.dy + carBox.height / 2 + 6));
    }

    // 4. Trajectory Path Buffer
    if (pipelineStage >= 3) {
      List<Offset> mockTrail = [
        Offset(carPos.dx - 120, carPos.dy + 80),
        Offset(carPos.dx - 80, carPos.dy + 60),
        Offset(carPos.dx - 40, carPos.dy + 30),
        carPos,
      ];

      Paint trailLine = Paint()..color = Colors.cyanAccent..strokeWidth = 3;
      for (int i = 0; i < mockTrail.length - 1; i++) {
        canvas.drawLine(mockTrail[i], mockTrail[i + 1], trailLine);
        canvas.drawCircle(mockTrail[i], 4, Paint()..color = Colors.yellowAccent);
      }

      TextPainter tpBuf = TextPainter(
        text: TextSpan(
          text: "Centroid Path History (Queue Buffer)",
          style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11, backgroundColor: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
      );
      tpBuf.layout();
      tpBuf.paint(canvas, Offset(mockTrail[0].dx - 30, mockTrail[0].dy + 15));
    }

    // 5. Vector Angle Math
    if (pipelineStage >= 4) {
      Offset vIn = Offset(carPos.dx - 100, carPos.dy + 60);
      Offset vOut = Offset(carPos.dx + 80, carPos.dy - 60);

      Paint vPaint = Paint()..color = Colors.orangeAccent..strokeWidth = 4..strokeCap = StrokeCap.round;
      _drawArrow(canvas, vIn, carPos, vPaint);
      _drawArrow(canvas, carPos, vOut, vPaint);

      TextPainter tpMath = TextPainter(
        text: TextSpan(
          text: "Trig Engine: Δθ = atan2(v_out) - atan2(v_in) = -88.5° (Left Turn)",
          style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12, backgroundColor: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
      );
      tpMath.layout();
      tpMath.paint(canvas, Offset(20, 20));
    }
  }

  void _drawNodeLabel(Canvas canvas, String label, Offset pos, Color color) {
    TextPainter tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11, backgroundColor: Colors.black87)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    canvas.drawCircle(pos, 8, Paint()..color = color);
    canvas.drawCircle(pos, 8, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy + 12));
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    double dX = end.dx - start.dx;
    double dY = end.dy - start.dy;
    double a = math.atan2(dY, dX);
    double arrowLength = 14;
    Offset p1 = Offset(end.dx - arrowLength * math.cos(a - math.pi / 6), end.dy - arrowLength * math.sin(a - math.pi / 6));
    Offset p2 = Offset(end.dx - arrowLength * math.cos(a + math.pi / 6), end.dy - arrowLength * math.sin(a + math.pi / 6));
    canvas.drawLine(end, p1, paint);
    canvas.drawLine(end, p2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
