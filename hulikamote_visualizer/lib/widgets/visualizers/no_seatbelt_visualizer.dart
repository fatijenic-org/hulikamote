import 'package:flutter/material.dart';

class NoSeatbeltVisualizer extends StatefulWidget {
  @override
  _NoSeatbeltVisualizerState createState() => _NoSeatbeltVisualizerState();
}

class _NoSeatbeltVisualizerState extends State<NoSeatbeltVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _scenario = 0; // 0 = Clear+Belt, 1 = Clear+NoBelt, 2 = Tinted

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

  void _triggerScenario(int scenario) {
    setState(() {
      _scenario = scenario;
    });
    _controller.forward(from: 0.0);
    _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    bool isViolating = _scenario == 1 && _controller.value > 0.4;
    bool isTinted = _scenario == 2;
    
    String status = "SCANNING WINDSHIELD CLASSIFICATION...";
    if (_controller.value > 0.4) {
      if (isTinted) {
        status = "SAFETY OVERRIDE: TINTED WINDOW (Check Aborted)";
      } else {
        status = (_scenario == 0) ? "LEGAL: SEATBELT DETECTED" : "VIOLATION: NO SEATBELT";
      }
    }

    Color statusColor = Colors.grey[800]!;
    Color statusBg = Colors.grey[200]!;
    if (_controller.value > 0.4) {
      if (isTinted) {
        statusColor = Colors.orange[900]!;
        statusBg = Colors.orange[100]!;
      } else if (isViolating) {
        statusColor = Colors.red[900]!;
        statusBg = Colors.red[100]!;
      } else {
        statusColor = Colors.green[900]!;
        statusBg = Colors.green[100]!;
      }
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
                  painter: _NoSeatbeltAIPainter(
                    progress: _controller.value,
                    scenario: _scenario,
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
              Text("Modern AI: Safety Override Gate", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              SizedBox(height: 8),
              Text("Before checking for a seatbelt, YOLO classifies the windshield as 'clear_window' or 'tinted_window'. If heavily tinted, the check is aborted to prevent false positive tickets.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _scenario == 0 ? Colors.green[800] : Colors.green),
                    onPressed: () => _triggerScenario(0),
                    child: Text("Clear + Belt Worn", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _scenario == 1 ? Colors.red[800] : Colors.red),
                    onPressed: () => _triggerScenario(1),
                    child: Text("Clear + No Belt", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _scenario == 2 ? Colors.orange[800] : Colors.orange),
                    onPressed: () => _triggerScenario(2),
                    child: Text("Tinted Window", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 32),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor)
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}

class _NoSeatbeltAIPainter extends CustomPainter {
  final double progress;
  final int scenario;

  _NoSeatbeltAIPainter({required this.progress, required this.scenario});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint roadPaint = Paint()..color = Colors.grey[700]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    double startY = -150;
    double endY = size.height + 150;
    double currentY = startY + (endY - startY) * progress;

    // Draw Car driving down
    Rect carRect = Rect.fromCenter(center: Offset(cx, currentY), width: 140, height: 220);
    canvas.drawRRect(RRect.fromRectAndRadius(carRect, Radius.circular(20)), Paint()..color = Colors.blueGrey);
    
    // Windshield
    bool isTinted = scenario == 2;
    Rect glassRect = Rect.fromCenter(center: Offset(cx, currentY + 30), width: 120, height: 60);
    canvas.drawRect(glassRect, Paint()..color = isTinted ? Colors.black87 : Colors.lightBlue[100]!);

    if (!isTinted) {
      // Occupants (Top down view through windshield)
      // Driver (Left)
      canvas.drawCircle(Offset(cx - 30, currentY + 30), 15, Paint()..color = Colors.brown[300]!); // Head
      canvas.drawRect(Rect.fromCenter(center: Offset(cx - 30, currentY + 50), width: 40, height: 30), Paint()..color = Colors.orange); // Shoulders
      
      if (scenario == 0) { // Has Belt
        canvas.drawLine(Offset(cx - 50, currentY + 35), Offset(cx - 15, currentY + 65), Paint()..color = Colors.black..strokeWidth = 4);
      }
    }

    if (progress > 0.2 && progress < 0.8) {
      // Draw BBox
      Color boxColor = isTinted ? Colors.orange : Colors.cyan;
      canvas.drawRect(glassRect.inflate(5), Paint()..color = boxColor..strokeWidth = 3..style = PaintingStyle.stroke);
      
      // HUD Line
      canvas.drawLine(Offset(glassRect.right + 5, glassRect.top), Offset(size.width - 150, 50), Paint()..color = boxColor..strokeWidth = 1);
      
      // HUD Crop Panel
      Rect hudRect = Rect.fromLTWH(size.width - 150, 50, 130, 130);
      canvas.drawRect(hudRect, Paint()..color = Colors.black87);
      canvas.drawRect(hudRect, Paint()..color = boxColor..strokeWidth = 2..style = PaintingStyle.stroke);

      if (progress > 0.4) {
        if (isTinted) {
          TextPainter tpTint = TextPainter(
            text: TextSpan(
              text: "CLASS: TINTED\n\nCHECK ABORTED", 
              style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
          );
          tpTint.layout();
          tpTint.paint(canvas, Offset(hudRect.left + 15, hudRect.top + 40));
        } else {
          bool isViolating = scenario == 1;
          Paint resultPaint = Paint()..color = isViolating ? Colors.red : Colors.green;
          
          // Draw the extracted person inside HUD
          canvas.drawCircle(Offset(hudRect.left + 65, hudRect.top + 40), 20, Paint()..color = Colors.brown[300]!);
          canvas.drawRect(Rect.fromCenter(center: Offset(hudRect.left + 65, hudRect.top + 80), width: 50, height: 40), Paint()..color = Colors.orange);
          if (scenario == 0) {
            canvas.drawLine(Offset(hudRect.left + 40, hudRect.top + 60), Offset(hudRect.left + 85, hudRect.top + 100), Paint()..color = Colors.black..strokeWidth = 6);
          }

          // Draw CNN Scanner overlay
          canvas.drawRect(hudRect.inflate(-10), resultPaint..style = PaintingStyle.stroke..strokeWidth = 3);
          
          TextPainter tpHud = TextPainter(
            text: TextSpan(
              text: isViolating ? "NO SEATBELT\n99.8%" : "SEATBELT OK\n98.5%", 
              style: TextStyle(color: isViolating ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold)
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
          );
          tpHud.layout();
          tpHud.paint(canvas, Offset(hudRect.left + 25, hudRect.bottom - 40));
        }
      } else {
        TextPainter tpWait = TextPainter(
          text: TextSpan(text: "CLASSIFYING...", style: TextStyle(color: Colors.cyanAccent, fontSize: 12)),
          textDirection: TextDirection.ltr,
        );
        tpWait.layout();
        tpWait.paint(canvas, Offset(hudRect.left + 25, hudRect.top + 50));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
