import 'package:flutter/material.dart';

class RedLightSetup extends StatefulWidget {
  @override
  _RedLightSetupState createState() => _RedLightSetupState();
}

class _RedLightSetupState extends State<RedLightSetup> {
  int pipelineStage = 0; // 0: Classify Light, 1: Map Stop Line, 2: Monitor Centroid

  void _advancePipeline() {
    setState(() {
      pipelineStage = (pipelineStage + 1) % 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // CANVAS
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _RedLightSetupPainter(
                pipelineStage: pipelineStage,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        // CONTROLS
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
                      Text("Real-World Setup: 3-Stage Logic", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "How the AI connects the traffic light state to the vehicle's position.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Center(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[900],
                            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16)
                          ),
                          onPressed: _advancePipeline,
                          child: Text(pipelineStage == 2 ? "RESET" : "NEXT STEP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      SizedBox(height: 32),
                      
                      _buildStageTile("Stage 1: Lock Light State (RED)", 0, pipelineStage >= 0),
                      _buildStageTile("Stage 2: Map Stop Line / Intersection", 1, pipelineStage >= 1),
                      _buildStageTile("Stage 3: Track Car Centroid Crossing", 2, pipelineStage >= 2),
                    ],
                  ),
                ),
              ),
              
              Divider(height: 32),
              Text("System Conclusion:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: pipelineStage == 2 ? Colors.red[100] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: pipelineStage == 2 ? Colors.red : Colors.grey, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      pipelineStage == 2 
                          ? "RESULT: VIOLATION LOGGED" 
                          : "WAITING FOR EVENT...",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: pipelineStage == 2 ? Colors.red[900] : Colors.grey[800], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (pipelineStage == 2)
                      Text("(State == RED) AND (Centroid Crossed)", style: TextStyle(color: Colors.red[800], fontSize: 12), textAlign: TextAlign.center),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildStageTile(String title, int stage, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isActive ? Colors.green : Colors.grey,
          ),
          SizedBox(width: 12),
          Text(title, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.black : Colors.grey)),
        ],
      ),
    );
  }
}

class _RedLightSetupPainter extends CustomPainter {
  final int pipelineStage;

  _RedLightSetupPainter({required this.pipelineStage});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint roadPaint = Paint()..color = Colors.grey[700]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    Paint linePaint = Paint()..color = Colors.white..strokeWidth = 2;
    canvas.drawLine(Offset(cx - 50, 0), Offset(cx - 50, size.height), linePaint);
    canvas.drawLine(Offset(cx + 50, 0), Offset(cx + 50, size.height), linePaint);

    // Stop Line
    double stopY = cy + 50;
    canvas.drawLine(Offset(cx - 50, stopY), Offset(cx + 50, stopY), Paint()..color = Colors.white..strokeWidth = 10);

    // Traffic Light
    Rect lightBox = Rect.fromLTWH(cx + 100, cy - 150, 40, 100);
    canvas.drawRect(lightBox, Paint()..color = Colors.black);
    canvas.drawCircle(Offset(cx + 120, cy - 130), 10, Paint()..color = Colors.redAccent); // Red
    canvas.drawCircle(Offset(cx + 120, cy - 100), 10, Paint()..color = Colors.yellow[900]!);
    canvas.drawCircle(Offset(cx + 120, cy - 70), 10, Paint()..color = Colors.green[900]!);

    if (pipelineStage >= 0) {
      canvas.drawRect(lightBox.inflate(5), Paint()..color = Colors.cyan..strokeWidth = 2..style = PaintingStyle.stroke);
      TextPainter tpLight = TextPainter(
        text: TextSpan(text: "STATE: RED", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, backgroundColor: Colors.black)),
        textDirection: TextDirection.ltr,
      );
      tpLight.layout();
      tpLight.paint(canvas, Offset(lightBox.right + 10, lightBox.top));
    }

    if (pipelineStage >= 1) {
      // Map Intersection Zone (past stop line)
      Rect interRect = Rect.fromLTWH(cx - 50, 0, 100, stopY - 5);
      canvas.drawRect(interRect, Paint()..color = Colors.red.withOpacity(0.2)..style = PaintingStyle.fill);
      
      TextPainter tpZone = TextPainter(
        text: TextSpan(text: "INTERSECTION\n(RESTRICTED)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tpZone.layout();
      tpZone.paint(canvas, Offset(cx - 45, cy - 50));
    }

    if (pipelineStage >= 2) {
      // Car crosses
      Rect carRect = Rect.fromCenter(center: Offset(cx, stopY - 30), width: 60, height: 100);
      canvas.drawRect(carRect, Paint()..color = Colors.blueGrey);
      
      // Centroid
      canvas.drawCircle(carRect.center, 8, Paint()..color = Colors.cyanAccent);
      
      // Line from Centroid to Stop Line
      canvas.drawLine(carRect.center, Offset(cx, stopY), Paint()..color = Colors.yellow..strokeWidth = 2);

      TextPainter tpMath = TextPainter(
        text: TextSpan(text: "y_t < y_stop\nCROSSED!", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, backgroundColor: Colors.black54)),
        textDirection: TextDirection.ltr,
      );
      tpMath.layout();
      tpMath.paint(canvas, Offset(carRect.right + 10, carRect.center.dy));
    } else {
      // Car waits
      Rect carRect = Rect.fromCenter(center: Offset(cx, stopY + 80), width: 60, height: 100);
      canvas.drawRect(carRect, Paint()..color = Colors.blueGrey);
      canvas.drawCircle(carRect.center, 8, Paint()..color = Colors.cyanAccent);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
