import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';

class CounterflowSetup extends StatefulWidget {
  @override
  _CounterflowSetupState createState() => _CounterflowSetupState();
}

class _CounterflowSetupState extends State<CounterflowSetup> {
  // Car Simulation State
  double carBaseX = 50.0;
  bool isMovingRight = true;
  bool isJitterEnabled = true;
  bool showBuffer = true;
  
  // Real-World Centroid Buffer
  List<Offset> centroidHistory = [];
  final int maxBufferFrames = 30; // 1 second of memory at 30fps
  
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(milliseconds: 33), (timer) {
      if (!mounted) return;
      
      setState(() {
        // Move car
        double speed = isMovingRight ? 3.0 : -3.0;
        carBaseX += speed;
        
        // Wrap around
        if (carBaseX > 900) {
          carBaseX = -100;
          centroidHistory.clear();
        }
        if (carBaseX < -100) {
          carBaseX = 900;
          centroidHistory.clear();
        }
        
        // Add artificial YOLO jitter
        double jitterX = isJitterEnabled ? (Random().nextDouble() - 0.5) * 15 : 0;
        double jitterY = isJitterEnabled ? (Random().nextDouble() - 0.5) * 15 : 0;
        
        Offset currentCentroid = Offset(carBaseX + jitterX, 200 + jitterY);
        
        // Add to history
        centroidHistory.add(currentCentroid);
        if (centroidHistory.length > maxBufferFrames) {
          centroidHistory.removeAt(0); // Drop oldest node
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    
    // Macro Vector Calculation
    double macroAngle = 0.0;
    bool hasStableVector = false;
    if (centroidHistory.length >= 10) {
      Offset oldest = centroidHistory.first;
      Offset newest = centroidHistory.last;
      macroAngle = atan2(newest.dy - oldest.dy, newest.dx - oldest.dx);
      hasStableVector = true;
    }
    
    // Violation Math
    double refAngle = 0.0; // Top lane legal flow is Right
    double angleDiff = (macroAngle * 180 / pi) - (refAngle * 180 / pi);
    // Normalize to -180 to 180
    angleDiff = (angleDiff + 180) % 360 - 180;
    
    bool isViolation = hasStableVector && angleDiff.abs() > 90;

    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[800],
            child: ClipRect(
              child: CustomPaint(
                painter: _BufferPainter(
                  carBaseX: carBaseX,
                  centroidHistory: centroidHistory,
                  showBuffer: showBuffer,
                  hasStableVector: hasStableVector,
                  macroAngle: macroAngle,
                ),
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
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Real-World Setup: Centroid History Buffer", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text("DeepSORT does not calculate vectors from 1 frame to the next. YOLO bounding boxes jitter constantly.", style: TextStyle(color: Colors.grey[700], fontSize: 14)),
                      SizedBox(height: 8),
                      Text("Instead, the system stores the last 30 frames in a memory deque and calculates the 'Macro Vector' to smooth out all noise.", style: TextStyle(color: Colors.grey[700], fontSize: 14, fontWeight: FontWeight.bold)),
                      Divider(height: 32),
                      
                      Text("Simulate Driving:", style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: isMovingRight ? Colors.blue : Colors.grey[300]),
                              onPressed: () { setState(() { isMovingRight = true; centroidHistory.clear(); }); },
                              child: Text("Drive Right", style: TextStyle(color: isMovingRight ? Colors.white : Colors.black)),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: !isMovingRight ? Colors.blue : Colors.grey[300]),
                              onPressed: () { setState(() { isMovingRight = false; centroidHistory.clear(); }); },
                              child: Text("Drive Left", style: TextStyle(color: !isMovingRight ? Colors.white : Colors.black)),
                            ),
                          ),
                        ],
                      ),
                      
                      SizedBox(height: 16),
                      SwitchListTile(
                        title: Text("Simulate YOLO Jitter", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text("Add pixel noise to bounding box", style: TextStyle(fontSize: 12)),
                        value: isJitterEnabled,
                        activeColor: Colors.orange,
                        onChanged: (val) => setState(() => isJitterEnabled = val),
                      ),
                      SwitchListTile(
                        title: Text("Show Memory Buffer", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text("Visualize the last 30 nodes", style: TextStyle(fontSize: 12)),
                        value: showBuffer,
                        activeColor: Colors.blue,
                        onChanged: (val) => setState(() => showBuffer = val),
                      ),

                      Divider(height: 32),
                      Text("Buffer Diagnostics:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text("Stored Frames: ${centroidHistory.length} / $maxBufferFrames"),
                      Text("Macro Angle: ${hasStableVector ? (macroAngle * 180 / pi).toStringAsFixed(1) : 'Calculating...'}°"),
                    ],
                  ),
                ),
              ),
              Divider(height: 1),
              Container(
                padding: EdgeInsets.all(24),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: !hasStableVector ? Colors.grey[300] : (isViolation ? Colors.red[100] : Colors.green[100])
                ),
                child: Column(
                  children: [
                    Text("Macro-Vector Result:", style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(
                      !hasStableVector ? "GATHERING MEMORY..." : (isViolation ? "COUNTERFLOW\n(100% Match)" : "SAFE\n(0% Match)"),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: !hasStableVector ? Colors.grey[800] : (isViolation ? Colors.red[900] : Colors.green[900])
                      ),
                    )
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

class _BufferPainter extends CustomPainter {
  final double carBaseX;
  final List<Offset> centroidHistory;
  final bool showBuffer;
  final bool hasStableVector;
  final double macroAngle;

  _BufferPainter({
    required this.carBaseX,
    required this.centroidHistory,
    required this.showBuffer,
    required this.hasStableVector,
    required this.macroAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Road Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.grey[800]!);
    
    // Draw Legal Flow Indicator
    Paint refPaint = Paint()..color = Colors.blue.withOpacity(0.5)..strokeWidth = 6;
    _drawArrow(canvas, Offset(20, 20), Offset(150, 20), refPaint);
    TextPainter tpRule = TextPainter(
      text: TextSpan(text: "Legal Flow", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tpRule.layout();
    tpRule.paint(canvas, Offset(30, 30));

    if (centroidHistory.isEmpty) return;

    Offset currentCentroid = centroidHistory.last;

    // Draw YOLO Bounding Box with Jitter
    Paint bboxPaint = Paint()..color = Colors.greenAccent..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromCenter(center: currentCentroid, width: 100, height: 50), bboxPaint);
    
    // Draw memory buffer trail
    if (showBuffer && centroidHistory.length > 1) {
      Paint trailPaint = Paint()..color = Colors.yellow..strokeWidth = 2;
      for (int i = 0; i < centroidHistory.length - 1; i++) {
        canvas.drawLine(centroidHistory[i], centroidHistory[i+1], trailPaint);
        canvas.drawCircle(centroidHistory[i], 3, Paint()..color = Colors.orange);
      }
      canvas.drawCircle(currentCentroid, 5, Paint()..color = Colors.redAccent); // Current head
    }

    // Draw Macro Vector (The smoothed out line)
    if (hasStableVector) {
      Offset oldest = centroidHistory.first;
      Offset newest = centroidHistory.last;
      
      Paint macroPaint = Paint()..color = Colors.cyanAccent..strokeWidth = 5..strokeCap = StrokeCap.round;
      _drawArrow(canvas, oldest, newest, macroPaint);
      
      TextPainter tpV = TextPainter(
        text: TextSpan(text: "Smoothed Macro Vector", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, backgroundColor: Colors.black54)),
        textDirection: TextDirection.ltr,
      );
      tpV.layout();
      tpV.paint(canvas, Offset((oldest.dx + newest.dx)/2 - 50, (oldest.dy + newest.dy)/2 - 30));
    }
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
