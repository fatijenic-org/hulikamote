import 'package:flutter/material.dart';

class MissingMirrorVisualizer extends StatefulWidget {
  @override
  _MissingMirrorVisualizerState createState() => _MissingMirrorVisualizerState();
}

class _MissingMirrorVisualizerState extends State<MissingMirrorVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _mirrorsMissing = false;

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

  void _triggerRider(bool missing) {
    setState(() {
      _mirrorsMissing = missing;
    });
    _controller.forward(from: 0.0);
    _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    bool isViolating = _mirrorsMissing && _controller.value > 0.5;
    
    String status = "TRACKING & CROPPING...";
    if (_controller.value > 0.5) {
      status = _mirrorsMissing ? "VIOLATION: MISSING SIDE MIRROR" : "LEGAL: MIRRORS INTACT";
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
                  painter: _MissingMirrorAIPainter(
                    progress: _controller.value,
                    mirrorsMissing: _mirrorsMissing,
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
              Text("Modern AI: Sub-Crop & Counting Logic", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              SizedBox(height: 8),
              Text("The system tracks the motorcycle, sub-crops it, and runs a secondary YOLO model. If Count(Mirror) < 2 inside the frame, it flags a violation.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () => _triggerRider(false),
                    child: Text("Mirrors Intact", style: TextStyle(color: Colors.white)),
                  ),
                  SizedBox(width: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => _triggerRider(true),
                    child: Text("Mirrors Missing", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 32),
                decoration: BoxDecoration(
                  color: _controller.value < 0.5 ? Colors.grey[200] : (isViolating ? Colors.red[100] : Colors.green[100]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _controller.value < 0.5 ? Colors.grey : (isViolating ? Colors.red : Colors.green))
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _controller.value < 0.5 ? Colors.grey[800] : (isViolating ? Colors.red[900] : Colors.green[900])
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

class _MissingMirrorAIPainter extends CustomPainter {
  final double progress;
  final bool mirrorsMissing;

  _MissingMirrorAIPainter({required this.progress, required this.mirrorsMissing});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    double startY = -150;
    double endY = size.height + 150;
    double currentY = startY + (endY - startY) * progress;

    // Scale logic
    double scale = 0.5 + (progress * 1.5);
    if (scale > 2.5) return;

    canvas.save();
    canvas.translate(cx, currentY);
    canvas.scale(scale);

    // Motorcycle Front
    Paint motoPaint = Paint()..color = Colors.blueGrey;
    canvas.drawRect(Rect.fromCenter(center: Offset(0, 0), width: 60, height: 80), motoPaint);
    canvas.drawCircle(Offset(0, 40), 20, Paint()..color = Colors.black); // wheel
    
    // Handlebars
    canvas.drawRect(Rect.fromCenter(center: Offset(0, -40), width: 80, height: 6), Paint()..color = Colors.black);

    // Mirrors
    if (!mirrorsMissing) {
      canvas.drawCircle(Offset(-40, -55), 8, Paint()..color = Colors.grey[300]!);
      canvas.drawCircle(Offset(40, -55), 8, Paint()..color = Colors.grey[300]!);
    }

    // Moto BBox
    Rect motoBox = Rect.fromCenter(center: Offset(0, 0), width: 100, height: 110);
    if (progress > 0.1) {
      canvas.drawRect(motoBox, Paint()..color = Colors.cyan..strokeWidth = 2 / scale..style = PaintingStyle.stroke);
    }

    // Secondary Check Phase
    if (progress > 0.4) {
      // Isolate sub-crop in HUD (we draw HUD unscaled, so we restore first)
      canvas.restore();
      
      Rect hudRect = Rect.fromLTWH(size.width - 160, 50, 140, 140);
      canvas.drawRect(hudRect, Paint()..color = Colors.black87);
      canvas.drawRect(hudRect, Paint()..color = Colors.cyan..strokeWidth = 2..style = PaintingStyle.stroke);
      
      // Connecting lines
      canvas.drawLine(Offset(cx + (50 * scale), currentY - (55 * scale)), Offset(hudRect.left, hudRect.top), Paint()..color = Colors.cyan..strokeWidth = 1);
      canvas.drawLine(Offset(cx + (50 * scale), currentY + (55 * scale)), Offset(hudRect.left, hudRect.bottom), Paint()..color = Colors.cyan..strokeWidth = 1);

      if (progress > 0.5) {
        // Draw the extracted mirrors inside HUD
        canvas.drawRect(Rect.fromCenter(center: Offset(hudRect.left + 70, hudRect.top + 70), width: 80, height: 6), Paint()..color = Colors.grey[600]!);
        
        int count = 0;
        if (!mirrorsMissing) {
          canvas.drawCircle(Offset(hudRect.left + 30, hudRect.top + 50), 15, Paint()..color = Colors.grey[300]!);
          canvas.drawCircle(Offset(hudRect.left + 110, hudRect.top + 50), 15, Paint()..color = Colors.grey[300]!);
          
          // Draw AI boxes around mirrors
          canvas.drawRect(Rect.fromCenter(center: Offset(hudRect.left + 30, hudRect.top + 50), width: 35, height: 35), Paint()..color = Colors.green..strokeWidth = 2..style = PaintingStyle.stroke);
          canvas.drawRect(Rect.fromCenter(center: Offset(hudRect.left + 110, hudRect.top + 50), width: 35, height: 35), Paint()..color = Colors.green..strokeWidth = 2..style = PaintingStyle.stroke);
          count = 2;
        }

        bool isViolating = count < 2;
        TextPainter tpCount = TextPainter(
          text: TextSpan(
            text: "Count(Mirror) = $count\n${isViolating ? 'VIOLATION' : 'PASS'}", 
            style: TextStyle(color: isViolating ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold)
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        tpCount.layout();
        tpCount.paint(canvas, Offset(hudRect.left + 10, hudRect.bottom - 40));
        
        // Flash main bounding box red/green
        canvas.save();
        canvas.translate(cx, currentY);
        canvas.scale(scale);
        canvas.drawRect(motoBox, Paint()..color = isViolating ? Colors.red : Colors.green..strokeWidth = 4 / scale..style = PaintingStyle.stroke);
        canvas.restore();
      } else {
        TextPainter tpWait = TextPainter(
          text: TextSpan(text: "SUB-CROPPING...", style: TextStyle(color: Colors.cyanAccent, fontSize: 12)),
          textDirection: TextDirection.ltr,
        );
        tpWait.layout();
        tpWait.paint(canvas, Offset(hudRect.left + 25, hudRect.top + 60));
      }
    } else {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
