import 'package:flutter/material.dart';

class OverloadingVisualizer extends StatefulWidget {
  @override
  _OverloadingVisualizerState createState() => _OverloadingVisualizerState();
}

class _OverloadingVisualizerState extends State<OverloadingVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _scenario = 0; // 0=2 Riders, 1=3 Riders, 2=Background Crowd, 3=Foreground Pedestrian

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
    int countedRiders = (_scenario == 1) ? 3 : 2;
    bool isViolating = countedRiders > 2 && _controller.value > 0.3;
    
    String status = "SCANNING POSTURE & OVERLAP...";
    if (_controller.value > 0.3) {
      status = isViolating ? "VIOLATION: OVERLOADING ($countedRiders Riders)" : "LEGAL: $countedRiders Riders";
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
                  painter: _OverloadingAIPainter(
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
              Text("Modern AI: 80% Overlap & Posture Logic", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              SizedBox(height: 8),
              Text("To prevent false tickets from background crowds, the AI enforces a Strict 80% Overlap Rule and Posture Classification (Sitting vs Standing).", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _scenario == 0 ? Colors.green[800] : Colors.green),
                    onPressed: () => _triggerScenario(0),
                    child: Text("2 Riders", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _scenario == 1 ? Colors.red[800] : Colors.red),
                    onPressed: () => _triggerScenario(1),
                    child: Text("3 Riders", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _scenario == 2 ? Colors.orange[800] : Colors.orange),
                    onPressed: () => _triggerScenario(2),
                    child: Text("Background Crowd", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _scenario == 3 ? Colors.purple[800] : Colors.purple),
                    onPressed: () => _triggerScenario(3),
                    child: Text("Foreground Walker", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 32),
                decoration: BoxDecoration(
                  color: _controller.value < 0.3 ? Colors.grey[200] : (isViolating ? Colors.red[100] : Colors.green[100]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _controller.value < 0.3 ? Colors.grey : (isViolating ? Colors.red : Colors.green))
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _controller.value < 0.3 ? Colors.grey[800] : (isViolating ? Colors.red[900] : Colors.green[900])
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

class _OverloadingAIPainter extends CustomPainter {
  final double progress;
  final int scenario;

  _OverloadingAIPainter({required this.progress, required this.scenario});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    double startX = size.width + 100;
    double endX = -200;
    double currentX = startX + (endX - startX) * progress;

    // Draw Background Pedestrians (Scenario 2)
    if (scenario == 2) {
      _drawPerson(canvas, Offset(cx - 80, cy - 60), isSitting: false, overlapPercent: 15, showBox: progress > 0.3);
      _drawPerson(canvas, Offset(cx + 80, cy - 70), isSitting: false, overlapPercent: 0, showBox: progress > 0.3);
    }

    // Motorcycle Profile
    Rect motoRect = Rect.fromCenter(center: Offset(currentX, cy + 40), width: 150, height: 60);
    canvas.drawRRect(RRect.fromRectAndRadius(motoRect, Radius.circular(10)), Paint()..color = Colors.blueGrey);
    canvas.drawCircle(Offset(currentX - 50, cy + 70), 25, Paint()..color = Colors.black);
    canvas.drawCircle(Offset(currentX + 50, cy + 70), 25, Paint()..color = Colors.black);

    // Moto Bounding Box
    Rect motoBBox = Rect.fromCenter(center: Offset(currentX, cy + 20), width: 170, height: 140);
    if (progress > 0.1) {
      canvas.drawRect(motoBBox, Paint()..color = Colors.cyan..strokeWidth = 2..style = PaintingStyle.stroke);
      TextPainter tpMoto = TextPainter(
        text: TextSpan(text: "MOTORCYCLE BOX", style: TextStyle(color: Colors.cyanAccent, fontSize: 10, backgroundColor: Colors.black)),
        textDirection: TextDirection.ltr,
      );
      tpMoto.layout();
      tpMoto.paint(canvas, Offset(motoBBox.left, motoBBox.bottom + 5));
    }

    // Riders (Sitting, 100% overlap)
    int ridersToDraw = (scenario == 1) ? 3 : 2;
    double rStartX = currentX - 40;
    for (int i = 0; i < ridersToDraw; i++) {
      _drawPerson(canvas, Offset(rStartX + (i * 35), cy - 10), isSitting: true, overlapPercent: 100, showBox: progress > 0.3);
    }

    // Draw Foreground Pedestrian (Scenario 3 - Standing right in front of the bike, heavy overlap)
    if (scenario == 3) {
      _drawPerson(canvas, Offset(currentX + 60, cy + 20), isSitting: false, overlapPercent: 90, showBox: progress > 0.3);
    }
  }

  void _drawPerson(Canvas canvas, Offset pos, {required bool isSitting, required int overlapPercent, required bool showBox}) {
    // Posture affects the body drawing
    double bodyHeight = isSitting ? 40 : 60;
    double bodyWidth = isSitting ? 30 : 20;
    
    // Draw body
    canvas.drawRect(Rect.fromCenter(center: Offset(pos.dx, pos.dy + (bodyHeight/2) - 10), width: bodyWidth, height: bodyHeight), Paint()..color = isSitting ? Colors.orange : Colors.purple);
    // Draw head
    canvas.drawCircle(Offset(pos.dx, pos.dy - 20), 12, Paint()..color = Colors.brown[300]!);

    if (showBox) {
      Rect pBox = Rect.fromCenter(center: Offset(pos.dx, pos.dy + (bodyHeight/2) - 15), width: bodyWidth + 10, height: bodyHeight + 30);
      
      bool isCounted = isSitting && overlapPercent >= 80;
      Color boxColor = isCounted ? Colors.redAccent : Colors.greenAccent;
      canvas.drawRect(pBox, Paint()..color = boxColor..strokeWidth = 2..style = PaintingStyle.stroke);
      
      String postureStr = isSitting ? "Sitting" : "Standing";
      String overlapStr = "Ov:$overlapPercent%";
      String actionStr = isCounted ? "COUNTED" : "IGNORED";

      String fullLabel = "$postureStr | $overlapStr\n$actionStr";
      
      TextPainter tp = TextPainter(
        text: TextSpan(text: fullLabel, style: TextStyle(color: boxColor, fontSize: 8, backgroundColor: Colors.black)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(pBox.left - 10, pBox.top - 20));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
