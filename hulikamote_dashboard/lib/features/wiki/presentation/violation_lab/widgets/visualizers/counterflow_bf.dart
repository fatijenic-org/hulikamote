import 'package:flutter/material.dart';
import 'dart:async';

class CounterflowBruteForce extends StatefulWidget {
  @override
  _CounterflowBruteForceState createState() => _CounterflowBruteForceState();
}

class _CounterflowBruteForceState extends State<CounterflowBruteForce> {
  double carX = 100.0;
  bool moveLeftToRight = true;
  bool isReversing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 30 FPS Animation Loop
    _timer = Timer.periodic(Duration(milliseconds: 33), (timer) {
      if (!mounted) return;
      setState(() {
        double speed = 4.0;
        if (moveLeftToRight) {
          carX += speed;
          if (carX > 1000) carX = -100;
        } else {
          carX -= speed;
          if (carX < -100) carX = 1000;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The brute force system determines direction strictly by which way the car is physically facing.
    // If it's facing Right -> it thinks it's going Right.
    bool facingRight = moveLeftToRight ? !isReversing : isReversing;
    
    // Legal flow is Left-to-Right. 
    // The Old System flags it if it is FACING left.
    bool systemFlagsViolation = !facingRight;

    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: ClipRect(
              child: CustomPaint(
                painter: _BruteForcePainter(
                  carX: carX, 
                  facingRight: facingRight
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        // CONTROLS AREA
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
                      Text("The Brute Force Way: Shape Guessing", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Old systems do not track movement. They look at a frozen image and guess direction based on where the windshield is facing.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Actual Movement:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: moveLeftToRight ? Colors.blue : Colors.grey[300]),
                              onPressed: () => setState(() => moveLeftToRight = true),
                              child: Text("Left ➔ Right", style: TextStyle(color: moveLeftToRight ? Colors.white : Colors.black)),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: !moveLeftToRight ? Colors.blue : Colors.grey[300]),
                              onPressed: () => setState(() => moveLeftToRight = false),
                              child: Text("Right ⬅ Left", style: TextStyle(color: !moveLeftToRight ? Colors.white : Colors.black)),
                            ),
                          ),
                        ],
                      ),
                      
                      SizedBox(height: 24),
                      Text("2. Expose the Flaw:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Switch(
                            value: isReversing,
                            activeColor: Colors.red,
                            onChanged: (val) => setState(() => isReversing = val),
                          ),
                          Expanded(child: Text("Car is driving in REVERSE", style: TextStyle(fontWeight: FontWeight.bold))),
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
                  color: systemFlagsViolation ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: systemFlagsViolation ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      "Orientation Detected:\n${facingRight ? 'FACING RIGHT' : 'FACING LEFT'}",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800]),
                    ),
                    SizedBox(height: 8),
                    Text(
                      systemFlagsViolation 
                          ? "RESULT: COUNTERFLOW" 
                          : "RESULT: SAFE",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: systemFlagsViolation ? Colors.red[900] : Colors.green[900], 
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
}

class _BruteForcePainter extends CustomPainter {
  final double carX;
  final bool facingRight;

  _BruteForcePainter({required this.carX, required this.facingRight});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw Road
    Paint roadPaint = Paint()..color = Colors.grey[700]!..style = PaintingStyle.fill;
    Paint linePaint = Paint()..color = Colors.white..strokeWidth = 4..style = PaintingStyle.stroke;
    
    Rect roadRect = Rect.fromCenter(center: Offset(size.width/2, size.height/2), width: size.width, height: 200);
    canvas.drawRect(roadRect, roadPaint);
    
    double startX = 0;
    while(startX < size.width) {
      canvas.drawLine(Offset(startX, size.height/2), Offset(startX + 20, size.height/2), linePaint);
      startX += 40;
    }

    // Draw Rule Text
    TextPainter tpRule = TextPainter(
      text: TextSpan(text: "Hardcoded Legal Direction:", style: TextStyle(color: Colors.blue[900], fontWeight: FontWeight.bold, fontSize: 18)),
      textDirection: TextDirection.ltr,
    );
    tpRule.layout();
    tpRule.paint(canvas, Offset(20, 20));

    // Draw Hardcoded ROI Arrow
    Paint refPaint = Paint()..color = Colors.blueAccent.withOpacity(0.5)..strokeWidth = 10;
    _drawArrow(canvas, Offset(20, 60), Offset(200, 60), refPaint);

    // Draw Actual Car
    canvas.save();
    canvas.translate(carX, size.height/2 + 50);
    
    // Flip canvas horizontally if facing left
    if (!facingRight) {
      canvas.scale(-1.0, 1.0);
    }
    
    // Car Body
    Paint carPaint = Paint()..color = Colors.blueGrey;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 100, height: 40), Radius.circular(8)), carPaint);
    
    // Windshield (indicates front of car)
    Paint glassPaint = Paint()..color = Colors.lightBlueAccent;
    canvas.drawRect(Rect.fromLTWH(20, -20, 15, 40), glassPaint);
    
    // Headlights
    Paint lightPaint = Paint()..color = Colors.yellow;
    canvas.drawCircle(Offset(50, -10), 5, lightPaint);
    canvas.drawCircle(Offset(50, 10), 5, lightPaint);

    canvas.restore();

    // Draw Brute Force Scanner Overlay (Locks onto car to "analyze" it)
    Paint scannerBorder = Paint()..color = Colors.orange..strokeWidth = 2..style = PaintingStyle.stroke;
    Rect scannerRect = Rect.fromCenter(center: Offset(carX, size.height/2 + 50), width: 120, height: 60);
    canvas.drawRect(scannerRect, scannerBorder);
    
    // Draw crosshair guessing orientation
    Paint crosshair = Paint()..color = Colors.red..strokeWidth = 2;
    double crossX = facingRight ? carX + 30 : carX - 30; // Points to windshield
    canvas.drawCircle(Offset(crossX, size.height/2 + 50), 15, scannerBorder);
    canvas.drawLine(Offset(crossX - 20, size.height/2 + 50), Offset(crossX + 20, size.height/2 + 50), crosshair);
    canvas.drawLine(Offset(crossX, size.height/2 + 30), Offset(crossX, size.height/2 + 70), crosshair);
    
    // Label
    TextPainter tpScan = TextPainter(
      text: TextSpan(
        text: "Analyzing Shape:\nWindshield found on ${facingRight ? 'RIGHT' : 'LEFT'}", 
        style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.bold, backgroundColor: Colors.white)
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    tpScan.layout();
    tpScan.paint(canvas, Offset(carX - tpScan.width/2, size.height/2 - 20));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    double dX = end.dx - start.dx;
    double dY = end.dy - start.dy;
    double angle = 0.0; // Hardcoded right for brute force
    double arrowLength = 20;
    
    Offset p1 = Offset(end.dx - arrowLength * 0.866, end.dy - arrowLength * 0.5); // cos(30), sin(30)
    Offset p2 = Offset(end.dx - arrowLength * 0.866, end.dy + arrowLength * 0.5);
    
    canvas.drawLine(end, p1, paint);
    canvas.drawLine(end, p2, paint);
  }
}
