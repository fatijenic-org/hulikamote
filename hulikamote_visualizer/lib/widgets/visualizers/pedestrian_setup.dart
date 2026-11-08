import 'package:flutter/material.dart';

class PedestrianSetup extends StatefulWidget {
  @override
  _PedestrianSetupState createState() => _PedestrianSetupState();
}

class _PedestrianSetupState extends State<PedestrianSetup> {
  double overlap = 0.0; // 0 to 1

  @override
  Widget build(BuildContext context) {
    bool isTriggered = overlap > 0.2; // 20% threshold

    return Row(
      children: [
        // CANVAS
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _PedestrianSetupPainter(
                overlap: overlap,
                isTriggered: isTriggered,
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
                      Text("Real-World Setup: Polygon Mapping", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Admins manually draw a Polygon mapping the exact physical bounds of the zebra crossing in the camera view.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Simulate Car Position:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text("Slide to move the car forward. The system calculates the Intersection over Union (IoU) of the car box inside the polygon.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      Slider(
                        value: overlap,
                        min: 0.0,
                        max: 1.0,
                        activeColor: Colors.blue,
                        onChanged: (val) {
                          setState(() {
                            overlap = val;
                          });
                        },
                      ),
                      Text("Overlap: ${(overlap * 100).toStringAsFixed(1)}%", style: TextStyle(fontWeight: FontWeight.bold)),
                      Text("Threshold: 20.0%", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
                  color: isTriggered ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isTriggered ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      isTriggered 
                          ? "IoU OVER THRESHOLD" 
                          : "CAR IS BEHIND LINE",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isTriggered ? Colors.red[900] : Colors.green[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (isTriggered)
                      Text("If light is RED and speed is 0, this will trigger a violation.", style: TextStyle(color: Colors.red[800], fontSize: 12), textAlign: TextAlign.center),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}

class _PedestrianSetupPainter extends CustomPainter {
  final double overlap;
  final bool isTriggered;

  _PedestrianSetupPainter({required this.overlap, required this.isTriggered});

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

    // Polygon drawn by Admin
    Rect polyRect = Rect.fromCenter(center: Offset(cx, pedY + 30), width: 220, height: 80);
    canvas.drawRect(polyRect, Paint()..color = Colors.purple.withOpacity(0.3)..style = PaintingStyle.fill);
    canvas.drawRect(polyRect, Paint()..color = Colors.purple..strokeWidth = 2..style = PaintingStyle.stroke);
    
    TextPainter tpPoly = TextPainter(
      text: TextSpan(text: "Z_ped (Polygon)", style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tpPoly.layout();
    tpPoly.paint(canvas, Offset(polyRect.right + 5, polyRect.center.dy));

    // Car Position based on overlap
    // overlap 0 = car is at stopY + 80 (bottom of rect touches top of poly)
    // overlap 1 = car is completely inside or past
    double startY = pedY + 80;
    double currentY = startY - (100 * overlap); // move up

    Rect carRect = Rect.fromCenter(center: Offset(cx, currentY), width: 60, height: 100);
    
    // Draw Car
    canvas.drawRRect(RRect.fromRectAndRadius(carRect, Radius.circular(10)), Paint()..color = Colors.blueGrey);
    
    // Car BBox
    canvas.drawRect(carRect, Paint()..color = isTriggered ? Colors.red : Colors.cyan..strokeWidth = 3..style = PaintingStyle.stroke);
    TextPainter tpCar = TextPainter(
      text: TextSpan(text: "B_car", style: TextStyle(color: isTriggered ? Colors.redAccent : Colors.cyanAccent, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tpCar.layout();
    tpCar.paint(canvas, Offset(carRect.left - 40, carRect.top));

    // Intersection highlight
    Rect intersect = polyRect.intersect(carRect);
    if (intersect.width > 0 && intersect.height > 0) {
      canvas.drawRect(intersect, Paint()..color = Colors.orangeAccent.withOpacity(0.5)..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
