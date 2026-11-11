import 'package:flutter/material.dart';

class NoSeatbeltSetup extends StatefulWidget {
  @override
  _NoSeatbeltSetupState createState() => _NoSeatbeltSetupState();
}

class _NoSeatbeltSetupState extends State<NoSeatbeltSetup> {
  int pipelineStage = 0;

  void _advancePipeline() {
    setState(() {
      pipelineStage = (pipelineStage + 1) % 4;
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
              painter: _NoSeatbeltSetupPainter(
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
                      Text("Real-World Setup: Sub-Cropping", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Running a heavy CNN on a full 4K frame is too slow. The AI uses a funnel approach to isolate the driver's chest.",
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
                          child: Text(pipelineStage == 3 ? "RESET" : "NEXT STEP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      SizedBox(height: 32),
                      
                      _buildStageTile("1. YOLO: Find Vehicle", 0, pipelineStage >= 0),
                      _buildStageTile("2. Math: Extract Windshield", 1, pipelineStage >= 1),
                      _buildStageTile("3. YOLO: Find Person", 2, pipelineStage >= 2),
                      _buildStageTile("4. CNN: Classify Seatbelt", 3, pipelineStage >= 3),
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
                  color: pipelineStage == 3 ? Colors.green[100] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: pipelineStage == 3 ? Colors.green : Colors.grey, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      pipelineStage == 3 
                          ? "COMPLIANCE VERIFIED" 
                          : "PROCESSING...",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: pipelineStage == 3 ? Colors.green[900] : Colors.grey[800], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
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

class _NoSeatbeltSetupPainter extends CustomPainter {
  final int pipelineStage;

  _NoSeatbeltSetupPainter({required this.pipelineStage});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint bgPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Car Structure
    Rect carRect = Rect.fromCenter(center: Offset(cx, cy), width: 300, height: 200);
    canvas.drawRRect(RRect.fromRectAndRadius(carRect, Radius.circular(20)), Paint()..color = Colors.blueGrey);
    
    // Windshield
    Rect glassRect = Rect.fromCenter(center: Offset(cx, cy - 30), width: 260, height: 100);
    canvas.drawRect(glassRect, Paint()..color = Colors.lightBlue[100]!);

    // Occupants
    // Driver (Left side, since LHD usually)
    Rect driverRect = Rect.fromCenter(center: Offset(cx - 60, cy - 20), width: 60, height: 80);
    canvas.drawRect(driverRect, Paint()..color = Colors.orange); // body
    canvas.drawCircle(Offset(cx - 60, cy - 60), 20, Paint()..color = Colors.brown[300]!); // head
    // Belt
    canvas.drawLine(Offset(cx - 80, cy - 50), Offset(cx - 40, cy + 20), Paint()..color = Colors.black..strokeWidth = 6);

    // Pipeline Overlays
    if (pipelineStage >= 0) {
      // 1. Car BBox
      canvas.drawRect(carRect.inflate(10), Paint()..color = Colors.cyan..strokeWidth = 3..style = PaintingStyle.stroke);
      _drawLabel(canvas, "B_car", carRect.left - 10, carRect.top - 20, Colors.cyan);
    }

    if (pipelineStage >= 1) {
      // 2. Windshield Crop
      canvas.drawRect(glassRect.inflate(5), Paint()..color = Colors.purpleAccent..strokeWidth = 3..style = PaintingStyle.stroke);
      _drawLabel(canvas, "B_windshield = B_car(upper_half)", glassRect.left, glassRect.top - 20, Colors.purpleAccent);
    }

    if (pipelineStage >= 2) {
      // 3. Person Box
      Rect personBox = Rect.fromCenter(center: Offset(cx - 60, cy - 30), width: 70, height: 100);
      canvas.drawRect(personBox, Paint()..color = Colors.orangeAccent..strokeWidth = 3..style = PaintingStyle.stroke);
      _drawLabel(canvas, "P_occupant", personBox.left, personBox.top - 20, Colors.orangeAccent);
    }

    if (pipelineStage >= 3) {
      // 4. CNN Output
      TextPainter tpCNN = TextPainter(
        text: TextSpan(text: "CNN(P_occupant)\nSEATBELT: 99%", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, backgroundColor: Colors.black, fontSize: 14)),
        textDirection: TextDirection.ltr,
      );
      tpCNN.layout();
      tpCNN.paint(canvas, Offset(cx - 100, cy + 30));
    }
  }

  void _drawLabel(Canvas canvas, String text, double x, double y, Color color) {
    TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontWeight: FontWeight.bold, backgroundColor: Colors.black)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
