import 'package:flutter/material.dart';

class RedLightFirstPrinciple extends StatefulWidget {
  @override
  _RedLightFirstPrincipleState createState() => _RedLightFirstPrincipleState();
}

class _RedLightFirstPrincipleState extends State<RedLightFirstPrinciple> {
  int lightState = 2; // 0: Red, 1: Yellow, 2: Green

  @override
  Widget build(BuildContext context) {
    String stateName = "GREEN";
    Color stateColor = Colors.green;
    
    if (lightState == 0) {
      stateName = "RED";
      stateColor = Colors.red;
    } else if (lightState == 1) {
      stateName = "YELLOW";
      stateColor = Colors.yellow[700]!;
    }

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _RedLightFPPainter(
                lightState: lightState,
              ),
              size: Size.infinite,
            ),
          ),
        ),
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
                      Text("Core Concept: Model Classification", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Modern systems use a dedicated YOLO classifier to look at the actual shape and pattern of the traffic light to determine its state, completely ignoring random red pixels.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Change the Light:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                      SizedBox(height: 8),
                      Text("Toggle the traffic light below. Notice how the AI 'sees' the state.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildLightBtn("RED", 0, Colors.red),
                          _buildLightBtn("YELLOW", 1, Colors.yellow[700]!),
                          _buildLightBtn("GREEN", 2, Colors.green),
                        ],
                      ),
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
                  color: stateColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: stateColor, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      "CLASSIFIED STATE:",
                      style: TextStyle(color: Colors.grey[800]),
                    ),
                    Text(
                      stateName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: stateColor, 
                        fontWeight: FontWeight.bold, 
                        fontSize: 24
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

  Widget _buildLightBtn(String label, int state, Color color) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: lightState == state ? color : Colors.grey[300],
        foregroundColor: lightState == state ? Colors.white : Colors.black87,
      ),
      onPressed: () {
        setState(() {
          lightState = state;
        });
      },
      child: Text(label),
    );
  }
}

class _RedLightFPPainter extends CustomPainter {
  final int lightState;

  _RedLightFPPainter({required this.lightState});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Traffic Light Box
    Rect lightBox = Rect.fromCenter(center: Offset(cx, cy), width: 80, height: 200);
    canvas.drawRect(lightBox, Paint()..color = Colors.black);

    // Lights
    canvas.drawCircle(Offset(cx, cy - 60), 20, Paint()..color = lightState == 0 ? Colors.redAccent : Colors.red[900]!);
    canvas.drawCircle(Offset(cx, cy), 20, Paint()..color = lightState == 1 ? Colors.yellowAccent : Colors.yellow[900]!);
    canvas.drawCircle(Offset(cx, cy + 60), 20, Paint()..color = lightState == 2 ? Colors.greenAccent : Colors.green[900]!);

    if (lightState == 0) {
      canvas.drawCircle(Offset(cx, cy - 60), 10, Paint()..color = Colors.white);
    } else if (lightState == 1) {
      canvas.drawCircle(Offset(cx, cy), 10, Paint()..color = Colors.white);
    } else {
      canvas.drawCircle(Offset(cx, cy + 60), 10, Paint()..color = Colors.white);
    }

    // YOLO BBox
    Paint yoloPaint = Paint()..color = Colors.cyan..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawRect(lightBox.inflate(10), yoloPaint);

    // Dynamic Label
    String label = lightState == 0 ? "STATE: RED (98%)" : (lightState == 1 ? "STATE: YELLOW (95%)" : "STATE: GREEN (99%)");
    Color labelCol = lightState == 0 ? Colors.red : (lightState == 1 ? Colors.yellow[800]! : Colors.green);

    TextPainter tpYolo = TextPainter(
      text: TextSpan(text: label, style: TextStyle(color: labelCol, fontWeight: FontWeight.bold, backgroundColor: Colors.black, fontSize: 16)),
      textDirection: TextDirection.ltr,
    );
    tpYolo.layout();
    tpYolo.paint(canvas, Offset(lightBox.right + 20, lightBox.top + 20));

    // Abstract mathematical node visualization
    Paint nodePaint = Paint()..color = Colors.blueGrey..strokeWidth = 1;
    for (int i = 0; i < 5; i++) {
      canvas.drawLine(Offset(lightBox.right + 20, lightBox.top + 50 + (i * 20)), Offset(lightBox.right + 80, lightBox.top + 80), nodePaint);
    }
    canvas.drawCircle(Offset(lightBox.right + 80, lightBox.top + 80), 15, Paint()..color = Colors.cyan);
    TextPainter tpMath = TextPainter(
      text: TextSpan(text: "argMax()", style: TextStyle(color: Colors.cyan[900], fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tpMath.layout();
    tpMath.paint(canvas, Offset(lightBox.right + 100, lightBox.top + 75));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
