import 'package:flutter/material.dart';

class SwervingSetup extends StatefulWidget {
  @override
  _SwervingSetupState createState() => _SwervingSetupState();
}

class _SwervingSetupState extends State<SwervingSetup> {
  int pipelineStage = 0;

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
              painter: _SwervingSetupPainter(
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
                      Text("Real-World Setup: ByteTrack History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "The AI maintains a rolling memory of the car's centroid over the last 15 frames to build a trajectory path.",
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
                      
                      _buildStageTile("1. YOLO Output (Current Frame)", 0, pipelineStage >= 0),
                      _buildStageTile("2. ByteTrack History Trail", 1, pipelineStage >= 1),
                      _buildStageTile("3. Trajectory Physics Calculation", 2, pipelineStage >= 2),
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
                  color: pipelineStage == 2 ? Colors.green[100] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: pipelineStage == 2 ? Colors.green : Colors.grey, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      pipelineStage == 2 
                          ? "TRAJECTORY IS SMOOTH" 
                          : "GATHERING DATA...",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: pipelineStage == 2 ? Colors.green[900] : Colors.grey[800], 
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

class _SwervingSetupPainter extends CustomPainter {
  final int pipelineStage;

  _SwervingSetupPainter({required this.pipelineStage});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    // Lane Lines
    Paint linePaint = Paint()..color = Colors.white..strokeWidth = 2;
    for(int i=0; i<10; i++) {
      canvas.drawLine(Offset(cx, i * 100.0), Offset(cx, i * 100.0 + 50), linePaint);
    }

    // Car Box (Current frame)
    Rect carRect = Rect.fromCenter(center: Offset(cx + 60, cy - 100), width: 60, height: 100);

    // Path points (Memory)
    List<Offset> points = [
      Offset(cx - 60, cy + 200),
      Offset(cx - 55, cy + 150),
      Offset(cx - 40, cy + 100),
      Offset(cx - 20, cy + 50),
      Offset(cx, cy),
      Offset(cx + 25, cy - 50),
      Offset(cx + 60, cy - 100), // current
    ];

    if (pipelineStage >= 0) {
      // 1. Current Frame
      canvas.drawRRect(RRect.fromRectAndRadius(carRect, Radius.circular(10)), Paint()..color = Colors.blueGrey);
      canvas.drawRect(carRect, Paint()..color = Colors.cyan..strokeWidth = 2..style = PaintingStyle.stroke);
      canvas.drawCircle(carRect.center, 5, Paint()..color = Colors.cyanAccent);
      
      TextPainter tpBox = TextPainter(
        text: TextSpan(text: "Frame: N", style: TextStyle(color: Colors.cyanAccent, backgroundColor: Colors.black)),
        textDirection: TextDirection.ltr,
      );
      tpBox.layout();
      tpBox.paint(canvas, Offset(carRect.right + 10, carRect.center.dy));
    }

    if (pipelineStage >= 1) {
      // 2. History Trail
      Paint pointPaint = Paint()..color = Colors.orangeAccent;
      for (int i=0; i<points.length-1; i++) {
        canvas.drawCircle(points[i], 4, pointPaint);
        
        TextPainter tpNum = TextPainter(
          text: TextSpan(text: "N-${points.length - 1 - i}", style: TextStyle(color: Colors.orangeAccent, fontSize: 10)),
          textDirection: TextDirection.ltr,
        );
        tpNum.layout();
        tpNum.paint(canvas, Offset(points[i].dx + 10, points[i].dy - 5));
      }
    }

    if (pipelineStage >= 2) {
      // 3. Trajectory Physics
      Path tPath = Path();
      tPath.moveTo(points[0].dx, points[0].dy);
      for(int i=1; i<points.length; i++) {
        tPath.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(tPath, Paint()..color = Colors.yellowAccent..strokeWidth = 2..style = PaintingStyle.stroke);

      TextPainter tpMath = TextPainter(
        text: TextSpan(text: "Velocity: 15 km/h (Lateral)\nJerk: 1.2 m/s³\nResult: Smooth (OK)", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, backgroundColor: Colors.black87)),
        textDirection: TextDirection.ltr,
      );
      tpMath.layout();
      tpMath.paint(canvas, Offset(cx + 100, cy - 50));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
