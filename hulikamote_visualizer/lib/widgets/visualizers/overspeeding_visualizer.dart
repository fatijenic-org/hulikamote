import 'package:flutter/material.dart';

class OverspeedingVisualizer extends StatefulWidget {
  @override
  _OverspeedingVisualizerState createState() => _OverspeedingVisualizerState();
}

class _OverspeedingVisualizerState extends State<OverspeedingVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isSpeeding = false;
  final double speedLimit = 60.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(seconds: 3));
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _triggerCar(bool speeding) {
    setState(() {
      _isSpeeding = speeding;
    });
    // Speeding car completes animation faster
    _controller.duration = Duration(milliseconds: speeding ? 1200 : 2500);
    _controller.forward(from: 0.0);
    _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    double currentSpeed = _isSpeeding ? 85.5 : 42.0;
    bool isViolating = currentSpeed > speedLimit;
    
    String status = isViolating ? "VIOLATION: ${currentSpeed} KPH (LIMIT: $speedLimit)" : "LEGAL: ${currentSpeed} KPH";

    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.grey[200],
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: _OverspeedingAIPainter(
                    progress: _controller.value,
                    isSpeeding: _isSpeeding,
                    currentSpeed: currentSpeed,
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
              Text("Modern AI: Perspective Transformation", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              SizedBox(height: 8),
              Text("Because 2D cameras distort distance, the AI uses a Homography Matrix to warp the camera feed into a perfect top-down 3D map. It then calculates real-world meters per second.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () => _triggerCar(false),
                    child: Text("Safe Speed (42 kph)", style: TextStyle(color: Colors.white)),
                  ),
                  SizedBox(width: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => _triggerCar(true),
                    child: Text("Over-speeding (85 kph)", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 32),
                decoration: BoxDecoration(
                  color: isViolating ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isViolating ? Colors.red : Colors.green)
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isViolating ? Colors.red[900] : Colors.green[900]
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

class _OverspeedingAIPainter extends CustomPainter {
  final double progress;
  final bool isSpeeding;
  final double currentSpeed;

  _OverspeedingAIPainter({required this.progress, required this.isSpeeding, required this.currentSpeed});

  @override
  void paint(Canvas canvas, Size size) {
    double halfW = size.width / 2;
    double h = size.height;

    // LEFT PANEL: 2D Camera View (Perspective Distorted)
    canvas.drawRect(Rect.fromLTWH(0, 0, halfW, h), Paint()..color = Colors.grey[800]!);
    
    // Draw distorted road
    Path roadPath = Path();
    roadPath.moveTo(halfW / 2 - 20, 50);
    roadPath.lineTo(halfW / 2 + 20, 50);
    roadPath.lineTo(halfW - 50, h);
    roadPath.lineTo(50, h);
    roadPath.close();
    canvas.drawPath(roadPath, Paint()..color = Colors.grey[700]!);

    // Car on 2D view (gets bigger as it moves down)
    double startY2D = 50;
    double endY2D = h;
    double y2D = startY2D + (endY2D - startY2D) * progress;
    double carScale2D = 0.2 + (1.5 * progress); // Grows
    
    canvas.save();
    canvas.translate(halfW / 2, y2D);
    canvas.scale(carScale2D);
    canvas.drawRect(Rect.fromCenter(center: Offset(0, 0), width: 30, height: 40), Paint()..color = Colors.blueGrey);
    canvas.restore();
    
    TextPainter tp2D = TextPainter(text: TextSpan(text: "Camera View\n(Distorted)", style: TextStyle(color: Colors.white, fontSize: 14)), textDirection: TextDirection.ltr, textAlign: TextAlign.center);
    tp2D.layout();
    tp2D.paint(canvas, Offset(20, 20));


    // RIGHT PANEL: Top-Down Birds-Eye (Perspective Transformed)
    canvas.drawRect(Rect.fromLTWH(halfW, 0, halfW, h), Paint()..color = Colors.black87);
    
    // Grid lines for Top-Down
    Paint gridPaint = Paint()..color = Colors.green[900]!..strokeWidth = 1;
    for (int i = 0; i < 20; i++) {
      canvas.drawLine(Offset(halfW, i * 40.0), Offset(size.width, i * 40.0), gridPaint);
      canvas.drawLine(Offset(halfW + (i * 40.0), 0), Offset(halfW + (i * 40.0), h), gridPaint);
    }
    
    // Draw straight road
    canvas.drawRect(Rect.fromLTWH(halfW + 100, 0, 100, h), Paint()..color = Colors.grey[800]!);
    
    // Car on 3D view (constant size)
    double startY3D = 0;
    double endY3D = h;
    double y3D = startY3D + (endY3D - startY3D) * progress;
    
    Rect carRect3D = Rect.fromCenter(center: Offset(halfW + 150, y3D), width: 40, height: 80);
    canvas.drawRect(carRect3D, Paint()..color = Colors.cyan);
    
    // Trajectory vector
    canvas.drawLine(Offset(halfW + 150, 0), Offset(halfW + 150, y3D), Paint()..color = Colors.cyanAccent..strokeWidth = 2);
    
    TextPainter tp3D = TextPainter(text: TextSpan(text: "Top-Down Map\n(Real-World Scale)", style: TextStyle(color: Colors.cyanAccent, fontSize: 14)), textDirection: TextDirection.ltr, textAlign: TextAlign.center);
    tp3D.layout();
    tp3D.paint(canvas, Offset(halfW + 20, 20));

    // Math calculation HUD
    if (progress > 0.2) {
      double distMeters = progress * 120.0; // Assume full screen is 120m
      double timeSecs = progress * (isSpeeding ? 1.2 : 2.5); // Fast or slow
      double calculatedSpeed = (distMeters / timeSecs) * 3.6; // Should closely match currentSpeed
      
      bool isViolating = currentSpeed > 60.0;
      
      TextPainter tpMath = TextPainter(
        text: TextSpan(
          text: "Δd: ${distMeters.toStringAsFixed(1)} m\nΔt: ${timeSecs.toStringAsFixed(1)} s\nSpeed: ${calculatedSpeed.toStringAsFixed(1)} kph",
          style: TextStyle(color: isViolating ? Colors.redAccent : Colors.greenAccent, fontSize: 12, backgroundColor: Colors.black87)
        ),
        textDirection: TextDirection.ltr,
      );
      tpMath.layout();
      tpMath.paint(canvas, Offset(carRect3D.right + 10, carRect3D.top));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
