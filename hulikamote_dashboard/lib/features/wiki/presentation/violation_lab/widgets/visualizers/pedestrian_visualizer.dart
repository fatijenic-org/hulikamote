import 'package:flutter/material.dart';

class PedestrianVisualizer extends StatefulWidget {
  @override
  _PedestrianVisualizerState createState() => _PedestrianVisualizerState();
}

class _PedestrianVisualizerState extends State<PedestrianVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _scenario = 0; // 0 = Red/Before Line, 1 = Red/On Lane, 2 = Green/On Lane (Traffic Jam)

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
    bool isStopped = _controller.value > 0.5;
    bool isViolating = isStopped && _scenario == 1; // Only Red + On Lane is a violation
    
    String status = "TRACKING...";
    if (isStopped) {
      if (_scenario == 0) status = "LEGAL: STOPPED BEHIND LINE";
      else if (_scenario == 1) status = "VIOLATION: STOPPED ON LANE (RED LIGHT)";
      else if (_scenario == 2) status = "LEGAL: STOPPED ON LANE (GREEN LIGHT / TRAFFIC)";
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
                  painter: _PedestrianAIPainter(
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
              Text("Modern AI: Conjunction Logic", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              SizedBox(height: 8),
              Text("The system isolates the pedestrian polygon. It continuously calculates the car's speed and IoU overlap. It flags a violation ONLY if Speed reaches 0 inside the polygon AND the Traffic Light is RED.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _scenario == 0 ? Colors.green[800] : Colors.green),
                    onPressed: () => _triggerScenario(0),
                    child: Text("Stop Before (Red)", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _scenario == 1 ? Colors.red[800] : Colors.red),
                    onPressed: () => _triggerScenario(1),
                    child: Text("Stop On Lane (Red)", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _scenario == 2 ? Colors.orange[800] : Colors.orange),
                    onPressed: () => _triggerScenario(2),
                    child: Text("Stop On Lane (Green)", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 32),
                decoration: BoxDecoration(
                  color: !isStopped ? Colors.grey[200] : (isViolating ? Colors.red[100] : Colors.green[100]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: !isStopped ? Colors.grey : (isViolating ? Colors.red : Colors.green))
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: !isStopped ? Colors.grey[800] : (isViolating ? Colors.red[900] : Colors.green[900]),
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

class _PedestrianAIPainter extends CustomPainter {
  final double progress;
  final int scenario;

  _PedestrianAIPainter({required this.progress, required this.scenario});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    // Zebra Crossing
    double pedY = cy + 50;
    for (int i = 0; i < 7; i++) {
      canvas.drawRect(Rect.fromLTWH(cx - 100 + (i * 30), pedY, 20, 60), Paint()..color = Colors.white);
    }

    // Polygon
    Rect polyRect = Rect.fromCenter(center: Offset(cx, pedY + 30), width: 220, height: 80);
    canvas.drawRect(polyRect, Paint()..color = Colors.purple.withOpacity(0.2)..style = PaintingStyle.fill);
    
    // Poly Label
    TextPainter tpPoly = TextPainter(
      text: TextSpan(text: "Z_{ped}", style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, backgroundColor: Colors.black)),
      textDirection: TextDirection.ltr,
    );
    tpPoly.layout();
    tpPoly.paint(canvas, Offset(polyRect.left + 5, polyRect.bottom - 20));

    // Traffic Light
    bool isRedLight = scenario != 2;
    canvas.drawCircle(Offset(cx + 150, cy - 100), 20, Paint()..color = isRedLight ? Colors.redAccent : Colors.greenAccent);
    TextPainter tpLight = TextPainter(
      text: TextSpan(text: isRedLight ? "LIGHT: RED" : "LIGHT: GREEN", style: TextStyle(color: isRedLight ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold, backgroundColor: Colors.black)),
      textDirection: TextDirection.ltr,
    );
    tpLight.layout();
    tpLight.paint(canvas, Offset(cx + 120, cy - 140));

    // Car Anim
    double startY = size.height + 100;
    bool stopBefore = scenario == 0;
    double endY = stopBefore ? pedY + 90 : pedY; // obey stops before polygon. disobey stops in middle of polygon
    
    double currentY;
    double speed;
    if (progress < 0.5) {
      double t = progress / 0.5;
      currentY = startY + (endY - startY) * t;
      speed = 40 * (1 - t); // decelerating
    } else {
      currentY = endY;
      speed = 0.0;
    }

    Rect carRect = Rect.fromCenter(center: Offset(cx, currentY), width: 60, height: 100);
    bool isStopped = progress >= 0.5;
    bool isViolating = isStopped && scenario == 1;

    Paint carBorder = Paint()..color = isViolating ? Colors.red : Colors.cyan..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(carRect, Radius.circular(10)), Paint()..color = Colors.blueGrey);
    canvas.drawRect(carRect, carBorder);

    // Math HUD near car
    String overlapStr = !stopBefore && isStopped ? '60%' : '0%';
    TextPainter tpHud = TextPainter(
      text: TextSpan(
        text: "Speed: ${speed.toStringAsFixed(1)} km/h\nIoU: $overlapStr",
        style: TextStyle(color: isViolating ? Colors.redAccent : Colors.cyanAccent, fontWeight: FontWeight.bold, backgroundColor: Colors.black54)
      ),
      textDirection: TextDirection.ltr,
    );
    tpHud.layout();
    tpHud.paint(canvas, Offset(carRect.right + 10, carRect.top));

    if (isStopped && !stopBefore) {
      String logicText = isViolating ? "VIOLATION" : "LEGAL (TRAFFIC JAM)";
      TextPainter tpLogic = TextPainter(
        text: TextSpan(
          text: logicText,
          style: TextStyle(color: isViolating ? Colors.red : Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14, backgroundColor: Colors.black)
        ),
        textDirection: TextDirection.ltr,
      );
      tpLogic.layout();
      tpLogic.paint(canvas, Offset(carRect.right + 10, carRect.bottom - 20));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
