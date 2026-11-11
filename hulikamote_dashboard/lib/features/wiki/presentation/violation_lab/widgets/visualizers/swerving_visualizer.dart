import 'package:flutter/material.dart';
import 'dart:math' as math;

class SwervingVisualizer extends StatefulWidget {
  @override
  _SwervingVisualizerState createState() => _SwervingVisualizerState();
}

class _SwervingVisualizerState extends State<SwervingVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isSwerving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(seconds: 4));
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _triggerCar(bool swerve) {
    setState(() {
      _isSwerving = swerve;
    });
    _controller.forward(from: 0.0);
    _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    bool isViolating = _isSwerving && _controller.value > 0.4 && _controller.value < 0.8;
    
    String status = "MONITORING TRAJECTORY...";
    if (_controller.value > 0.4 && _controller.value < 0.8) {
      status = _isSwerving ? "VIOLATION: HIGH JERK SWERVE DETECTED" : "LEGAL: LOW JERK LANE CHANGE";
    }

    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.grey[200],
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: _SwervingAIPainter(
                    progress: _controller.value,
                    isSwerving: _isSwerving,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            children: [
              Text("Modern AI Tracking", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              SizedBox(height: 8),
              Text("ByteTrack continually drops centroid memory nodes. The AI calculates the exact physical 'Jerk' force. If the force exceeds the safe threshold, it is mathematically classified as a Swerve.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () => _triggerCar(false),
                    child: Text("Smooth Lane Change", style: TextStyle(color: Colors.white)),
                  ),
                  SizedBox(width: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => _triggerCar(true),
                    child: Text("Sudden Swerve", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 32),
                decoration: BoxDecoration(
                  color: (_controller.value < 0.4 || _controller.value > 0.8) ? Colors.grey[200] : (isViolating ? Colors.red[100] : Colors.green[100]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (_controller.value < 0.4 || _controller.value > 0.8) ? Colors.grey : (isViolating ? Colors.red : Colors.green))
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: (_controller.value < 0.4 || _controller.value > 0.8) ? Colors.grey[800] : (isViolating ? Colors.red[900] : Colors.green[900])
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

class _SwervingAIPainter extends CustomPainter {
  final double progress;
  final bool isSwerving;

  _SwervingAIPainter({required this.progress, required this.isSwerving});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    // Lane Lines
    Paint linePaint = Paint()..color = Colors.white..strokeWidth = 2;
    for(int i=-2; i<15; i++) {
      double lineY = (i * 100.0) + (progress * 500) % 100;
      canvas.drawLine(Offset(cx, lineY), Offset(cx, lineY + 50), linePaint);
    }

    // Car Path logic
    double startY = size.height + 100;
    double endY = -100;
    double currentY = startY + (endY - startY) * progress;
    double currentX = cx - 60; // Start in left lane

    if (progress > 0.2) {
      if (isSwerving) {
        // Sudden snap
        if (progress > 0.4 && progress < 0.5) {
          double t = (progress - 0.4) / 0.1;
          currentX = (cx - 60) + (120 * t);
        } else if (progress >= 0.5) {
          currentX = cx + 60;
        }
      } else {
        // Smooth transition
        if (progress > 0.3 && progress < 0.7) {
          double t = (progress - 0.3) / 0.4;
          // Sine ease in out
          double ease = (1 - math.cos(t * 3.14159)) / 2; // (1-cos(pi*t))/2
          currentX = (cx - 60) + (120 * ease);
        } else if (progress >= 0.7) {
          currentX = cx + 60;
        }
      }
    }

    Rect carRect = Rect.fromCenter(center: Offset(currentX, currentY), width: 60, height: 100);
    
    // Draw trail
    Path trailPath = Path();
    trailPath.moveTo(cx - 60, startY);
    
    int maxPts = (progress * 40).toInt();
    for (int i=0; i<=maxPts; i++) {
      double ptP = i / 40.0;
      double py = startY + (endY - startY) * ptP;
      double px = cx - 60;
      
      if (ptP > 0.2) {
        if (isSwerving) {
          if (ptP > 0.4 && ptP < 0.5) {
            double t = (ptP - 0.4) / 0.1;
            px = (cx - 60) + (120 * t);
          } else if (ptP >= 0.5) {
            px = cx + 60;
          }
        } else {
          if (ptP > 0.3 && ptP < 0.7) {
            double t = (ptP - 0.3) / 0.4;
            double ease = (1 - math.cos(t * 3.14159)) / 2;
            px = (cx - 60) + (120 * ease);
          } else if (ptP >= 0.7) {
            px = cx + 60;
          }
        }
      }
      trailPath.lineTo(px, py);
    }

    bool isViolating = isSwerving && progress > 0.4;
    Paint trailStyle = Paint()
      ..color = isViolating ? Colors.redAccent : Colors.cyanAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    canvas.drawPath(trailPath, trailStyle);

    // Draw Car
    canvas.drawRRect(RRect.fromRectAndRadius(carRect, Radius.circular(10)), Paint()..color = Colors.blueGrey);
    canvas.drawRect(carRect, Paint()..color = isViolating ? Colors.red : Colors.cyan..strokeWidth = 2..style = PaintingStyle.stroke);
    
    // HUD
    if (progress > 0.2 && progress < 0.8) {
      double jerkVal = isSwerving ? (progress > 0.4 && progress < 0.5 ? 8.5 : 0.0) : (progress > 0.3 && progress < 0.7 ? 1.2 : 0.0);
      
      TextPainter tpHud = TextPainter(
        text: TextSpan(
          text: "Jerk: ${jerkVal.toStringAsFixed(1)} m/s³\n${jerkVal > 3.0 ? 'VIOLATION' : 'OK'}",
          style: TextStyle(color: isViolating ? Colors.redAccent : Colors.cyanAccent, fontWeight: FontWeight.bold, backgroundColor: Colors.black54)
        ),
        textDirection: TextDirection.ltr,
      );
      tpHud.layout();
      tpHud.paint(canvas, Offset(carRect.right + 10, carRect.top));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
