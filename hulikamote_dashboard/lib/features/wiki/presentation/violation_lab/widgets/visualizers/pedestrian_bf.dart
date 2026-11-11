import 'package:flutter/material.dart';

class PedestrianBruteForce extends StatefulWidget {
  @override
  _PedestrianBruteForceState createState() => _PedestrianBruteForceState();
}

class _PedestrianBruteForceState extends State<PedestrianBruteForce> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

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

  @override
  Widget build(BuildContext context) {
    bool inBox = _controller.value > 0.4 && _controller.value < 0.6;
    bool dumbViolation = inBox; // Triggers if it just touches the box

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: _PedestrianBFPainter(
                    progress: _controller.value,
                    inBox: inBox,
                  ),
                  size: Size.infinite,
                );
              },
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
                      Text("The Brute Force Way: Dumb Triggers", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Early systems just drew a motion detection box over the pedestrian lane. If a car touched the box, it flagged a violation.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Expose the Flaw:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                      SizedBox(height: 8),
                      Text("The traffic light is GREEN. The car is legally driving through the intersection. But watch what the 'dumb box' does when the car passes over the pedestrian lane.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
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
                  color: dumbViolation ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: dumbViolation ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      dumbViolation 
                          ? "VIOLATION! (CAR IN ZONE)" 
                          : "ALL CLEAR",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: dumbViolation ? Colors.red[900] : Colors.green[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (dumbViolation)
                      Text("FALSE POSITIVE! The car is just driving through a green light.", style: TextStyle(color: Colors.red[800], fontSize: 12), textAlign: TextAlign.center),
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

class _PedestrianBFPainter extends CustomPainter {
  final double progress;
  final bool inBox;

  _PedestrianBFPainter({required this.progress, required this.inBox});

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

    // Dumb Box Trigger
    Rect scanBox = Rect.fromCenter(center: Offset(cx, pedY + 30), width: 220, height: 80);
    canvas.drawRect(scanBox, Paint()..color = inBox ? Colors.red : Colors.yellow..strokeWidth = 3..style = PaintingStyle.stroke);
    
    TextPainter tpScan = TextPainter(
      text: TextSpan(text: "MOTION TRIGGER BOX", style: TextStyle(color: inBox ? Colors.red : Colors.yellow, fontWeight: FontWeight.bold, backgroundColor: Colors.black)),
      textDirection: TextDirection.ltr,
    );
    tpScan.layout();
    tpScan.paint(canvas, Offset(scanBox.left, scanBox.top - 20));

    // Green Light
    canvas.drawCircle(Offset(cx + 150, cy - 100), 20, Paint()..color = Colors.greenAccent);
    TextPainter tpLight = TextPainter(
      text: TextSpan(text: "LIGHT: GREEN", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tpLight.layout();
    tpLight.paint(canvas, Offset(cx + 120, cy - 140));

    // Car Animation
    double startY = size.height + 100;
    double endY = -100;
    double currentY = startY + (endY - startY) * progress;

    Rect carRect = Rect.fromCenter(center: Offset(cx, currentY), width: 60, height: 100);
    canvas.drawRRect(RRect.fromRectAndRadius(carRect, Radius.circular(10)), Paint()..color = Colors.blueAccent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
