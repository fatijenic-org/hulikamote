import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'dart:ui';

class CounterflowFirstPrinciple extends StatefulWidget {
  @override
  _CounterflowFirstPrincipleState createState() => _CounterflowFirstPrincipleState();
}

class _CounterflowFirstPrincipleState extends State<CounterflowFirstPrinciple> {
  // Tab State
  int _activeTab = 0; // 0: Vector Math, 1: Frame-by-Frame

  // Math State
  double angle = 0.0;

  // Frame State
  bool inTopLane = true;
  int currentStep = 0; // 0 to 10
  bool isAutoPlay = false;
  Timer? _autoPlayTimer;

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    super.dispose();
  }

  void _nextStep() {
    setState(() {
      if (currentStep < 10) {
        currentStep++;
      } else {
        currentStep = 0; 
      }
    });
  }

  void _toggleAutoPlay(bool value) {
    setState(() {
      isAutoPlay = value;
      if (isAutoPlay) {
        _autoPlayTimer = Timer.periodic(Duration(milliseconds: 1000), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          _nextStep();
        });
      } else {
        _autoPlayTimer?.cancel();
        _autoPlayTimer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: Container(
            color: _activeTab == 0 ? Colors.white : Colors.grey[800],
            child: ClipRect(
              child: CustomPaint(
                painter: _activeTab == 0 
                  ? _AgreementPainter(angle: angle)
                  : _SetupPainter(step: currentStep, inTopLane: inTopLane),
                size: Size.infinite,
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
              // TABS
              Container(
                margin: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8)
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _activeTab = 0),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _activeTab == 0 ? Colors.blue : Colors.transparent,
                            borderRadius: BorderRadius.circular(8)
                          ),
                          child: Text("1. Vector Math", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: _activeTab == 0 ? Colors.white : Colors.black)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _activeTab = 1),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _activeTab == 1 ? Colors.blue : Colors.transparent,
                            borderRadius: BorderRadius.circular(8)
                          ),
                          child: Text("2. Frame Tracker", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: _activeTab == 1 ? Colors.white : Colors.black)),
                        ),
                      ),
                    )
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(24),
                  child: _activeTab == 0 ? _buildMathControls() : _buildFrameControls(),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildMathControls() {
    double ax = 1.0, ay = 0.0;
    double bx = cos(angle), by = sin(angle);
    double dotProduct = (ax * bx) + (ay * by);
    int agreement = (dotProduct * 100).toInt();

    String stateMessage;
    Color stateColor;
    IconData stateIcon;
    
    if (agreement > 10) {
      stateMessage = "SAFE\n(Moving with traffic)";
      stateColor = Colors.green;
      stateIcon = Icons.thumb_up;
    } else if (agreement < -10) {
      stateMessage = "VIOLATION\n(Fighting the flow)";
      stateColor = Colors.red;
      stateIcon = Icons.warning_amber_rounded;
    } else {
      stateMessage = "SIDEWAYS\n(Drifting across lanes)";
      stateColor = Colors.orange;
      stateIcon = Icons.swap_horiz;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("The Core Concept: The Agreement Meter", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        SizedBox(height: 16),
        Text("Instead of rigid stencils, modern AI just uses two compass needles.\n\nIt simply asks: Are these needles agreeing, or fighting each other?", style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4)),
        SizedBox(height: 24),
        Text("Turn the car's steering wheel:", style: TextStyle(fontWeight: FontWeight.bold)),
        Slider(
          value: angle,
          min: -pi,
          max: pi,
          onChanged: (val) => setState(() => angle = val),
        ),
        SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              Text("Alignment Score", style: TextStyle(fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.bold)),
              Text("${agreement > 0 ? '+' : ''}$agreement%", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 48, color: stateColor)),
            ],
          ),
        ),
        SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: stateColor, borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              Icon(stateIcon, color: Colors.white, size: 32),
              SizedBox(height: 8),
              Text(stateMessage, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFrameControls() {
    bool isViolation = !inTopLane;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Frame-by-Frame Application", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        SizedBox(height: 16),
        Text("Watch YOLO and DeepSORT work together across 3 consecutive frames to extract the directional vector you saw in the Math Tab.", style: TextStyle(color: Colors.grey[700], fontSize: 14)),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: inTopLane ? Colors.blue : Colors.grey[300]),
                onPressed: () { setState(() { inTopLane = true; currentStep = 0; }); },
                child: Text("Top Lane", style: TextStyle(color: inTopLane ? Colors.white : Colors.black)),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: !inTopLane ? Colors.blue : Colors.grey[300]),
                onPressed: () { setState(() { inTopLane = false; currentStep = 0; }); },
                child: Text("Bottom Lane", style: TextStyle(color: !inTopLane ? Colors.white : Colors.black)),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: Icon(Icons.skip_next),
                label: Text("Next Step"),
                onPressed: _nextStep,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(Icons.refresh),
                label: Text("Reset"),
                onPressed: () => setState(() => currentStep = 0),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Switch(
              value: isAutoPlay,
              activeColor: Colors.blue,
              onChanged: _toggleAutoPlay,
            ),
            Text("Auto-Play Animation", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        Divider(height: 32),
        Text("Behind the scenes pipeline:", style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        _buildStepIndicator(0, 1, "Frame 1: YOLO detects Bounding Box"),
        _buildStepIndicator(2, 3, "Frame 2: YOLO updates Box"),
        _buildStepIndicator(4, 5, "Python calculates Centroids (X,Y)"),
        _buildStepIndicator(6, 7, "DeepSORT draws Vector Line"),
        _buildStepIndicator(8, 9, "Dot Product (Math) calculates Violation"),
        SizedBox(height: 16),
        if (currentStep >= 9)
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(color: isViolation ? Colors.red[100] : Colors.green[100], borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Icon(isViolation ? Icons.warning : Icons.check_circle, color: isViolation ? Colors.red : Colors.green),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isViolation ? "VECTOR MISMATCH!\nViolation Flagged" : "VECTORS AGREE!\nSafe",
                    style: TextStyle(fontWeight: FontWeight.bold, color: isViolation ? Colors.red[900] : Colors.green[900]),
                  ),
                )
              ],
            ),
          )
      ],
    );
  }

  Widget _buildStepIndicator(int minStep, int maxStep, String text) {
    bool active = currentStep >= minStep;
    bool processing = currentStep >= minStep && currentStep <= maxStep;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            active ? (processing ? Icons.hourglass_bottom : Icons.check_circle) : Icons.circle_outlined,
            color: active ? (processing ? Colors.orange : Colors.green) : Colors.grey,
            size: 20,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: active ? Colors.black87 : Colors.grey,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgreementPainter extends CustomPainter {
  final double angle;
  _AgreementPainter({required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    Offset center = Offset(size.width / 2, size.height / 2);
    Paint bgPaint = Paint()..color = Colors.grey[200]!..style = PaintingStyle.fill;
    canvas.drawCircle(center, 150, bgPaint);
    
    Paint gridPaint = Paint()..color = Colors.grey[300]!..strokeWidth = 2;
    canvas.drawLine(Offset(center.dx - 150, center.dy), Offset(center.dx + 150, center.dy), gridPaint);
    canvas.drawLine(Offset(center.dx, center.dy - 150), Offset(center.dx, center.dy + 150), gridPaint);
    
    Paint refPaint = Paint()..color = Colors.blue..strokeWidth = 8..strokeCap = StrokeCap.round;
    _drawArrow(canvas, center, Offset(center.dx + 120, center.dy), refPaint);
    
    Paint vehPaint = Paint()..color = Colors.orange..strokeWidth = 8..strokeCap = StrokeCap.round;
    Offset endVeh = Offset(center.dx + cos(angle) * 120, center.dy + sin(angle) * 120);
    _drawArrow(canvas, center, endVeh, vehPaint);
    
    TextPainter tp1 = TextPainter(text: TextSpan(text: "Legal Flow", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr);
    tp1.layout();
    tp1.paint(canvas, Offset(center.dx + 40, center.dy - 25));
    
    TextPainter tp2 = TextPainter(text: TextSpan(text: "Vehicle", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr);
    tp2.layout();
    tp2.paint(canvas, Offset(endVeh.dx + 10, endVeh.dy + 10));
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    double dX = end.dx - start.dx;
    double dY = end.dy - start.dy;
    double a = atan2(dY, dX);
    double arrowLength = 20;
    Offset p1 = Offset(end.dx - arrowLength * cos(a - pi/6), end.dy - arrowLength * sin(a - pi/6));
    Offset p2 = Offset(end.dx - arrowLength * cos(a + pi/6), end.dy - arrowLength * sin(a + pi/6));
    canvas.drawLine(end, p1, paint);
    canvas.drawLine(end, p2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _SetupPainter extends CustomPainter {
  final int step;
  final bool inTopLane;

  _SetupPainter({required this.step, required this.inTopLane});

  @override
  void paint(Canvas canvas, Size size) {
    Paint roadPaint = Paint()..color = Colors.grey[700]!..style = PaintingStyle.fill;
    Paint linePaint = Paint()..color = Colors.white..strokeWidth = 4..style = PaintingStyle.stroke;
    
    Rect roadRect = Rect.fromCenter(center: Offset(size.width/2, size.height/2), width: size.width, height: 200);
    canvas.drawRect(roadRect, roadPaint);
    
    double dashX = 0;
    while(dashX < size.width) {
      canvas.drawLine(Offset(dashX, size.height/2), Offset(dashX + 20, size.height/2), linePaint);
      dashX += 40;
    }

    // Top lane legal flow: Right
    // Bottom lane legal flow: Left
    Paint refPaintTop = Paint()..color = Colors.blue.withOpacity(0.5)..strokeWidth = 6;
    _drawArrow(canvas, Offset(20, size.height/2 - 50), Offset(100, size.height/2 - 50), refPaintTop);
    
    Paint refPaintBottom = Paint()..color = Colors.blue.withOpacity(0.5)..strokeWidth = 6;
    _drawArrow(canvas, Offset(size.width - 20, size.height/2 + 50), Offset(size.width - 100, size.height/2 + 50), refPaintBottom);

    double laneY = inTopLane ? size.height/2 - 50 : size.height/2 + 50;
    
    Offset carPosFrame1 = Offset(size.width/2 - 50, laneY);
    Offset carPosFrame2 = Offset(size.width/2 + 50, laneY);

    Paint bboxPaint = Paint()..color = Colors.greenAccent..strokeWidth = 2..style = PaintingStyle.stroke;
    Paint textBg = Paint()..color = Colors.black54;

    if (step >= 1) {
      canvas.drawRect(Rect.fromCenter(center: carPosFrame1, width: 80, height: 40), bboxPaint);
      _drawLabel(canvas, "F1", carPosFrame1, textBg);
    }

    if (step >= 3) {
      canvas.drawRect(Rect.fromCenter(center: carPosFrame2, width: 80, height: 40), bboxPaint);
      _drawLabel(canvas, "F2", carPosFrame2, textBg);
    }

    Paint pointPaint = Paint()..color = Colors.yellow..strokeWidth = 6..strokeCap = StrokeCap.round;
    if (step >= 5) {
      canvas.drawPoints(PointMode.points, [carPosFrame1], pointPaint);
      _drawLabel(canvas, "(x1,y1)", Offset(carPosFrame1.dx, carPosFrame1.dy + 30), textBg);
      
      canvas.drawPoints(PointMode.points, [carPosFrame2], pointPaint);
      _drawLabel(canvas, "(x2,y2)", Offset(carPosFrame2.dx, carPosFrame2.dy + 30), textBg);
    }

    if (step >= 7) {
      Paint vectorPaint = Paint()..color = Colors.orange..strokeWidth = 4;
      _drawArrow(canvas, carPosFrame1, carPosFrame2, vectorPaint);
    }

    if (step >= 9) {
      bool isViolation = !inTopLane; 
      Paint highlightPaint = Paint()..color = isViolation ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3)..style = PaintingStyle.fill;
      canvas.drawRect(roadRect, highlightPaint);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Paint bgPaint) {
    TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    canvas.drawRect(Rect.fromLTWH(pos.dx - tp.width/2 - 2, pos.dy - tp.height/2 - 2, tp.width + 4, tp.height + 4), bgPaint);
    tp.paint(canvas, Offset(pos.dx - tp.width/2, pos.dy - tp.height/2));
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    double dX = end.dx - start.dx;
    double dY = end.dy - start.dy;
    double a = atan2(dY, dX);
    double arrowLength = 15;
    Offset p1 = Offset(end.dx - arrowLength * cos(a - pi/6), end.dy - arrowLength * sin(a - pi/6));
    Offset p2 = Offset(end.dx - arrowLength * cos(a + pi/6), end.dy - arrowLength * sin(a + pi/6));
    canvas.drawLine(end, p1, paint);
    canvas.drawLine(end, p2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
