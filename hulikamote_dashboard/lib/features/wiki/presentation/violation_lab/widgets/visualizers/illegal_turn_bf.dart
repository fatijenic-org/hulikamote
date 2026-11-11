import 'package:flutter/material.dart';

class IllegalTurnBruteForce extends StatefulWidget {
  @override
  _IllegalTurnBruteForceState createState() => _IllegalTurnBruteForceState();
}

class _IllegalTurnBruteForceState extends State<IllegalTurnBruteForce> {
  Offset carPos = Offset(100, 300);
  bool hitGateA = false;
  bool hitGateB = false;

  @override
  Widget build(BuildContext context) {
    Rect gateA = Rect.fromLTWH(200, 250, 100, 100);
    Rect gateB = Rect.fromLTWH(200, 100, 100, 100);

    bool inA = gateA.contains(carPos);
    bool inB = gateB.contains(carPos);

    if (inA) hitGateA = true;
    if (inB) hitGateB = true;

    bool systemFlagsTurn = hitGateA && hitGateB;

    return Row(
      children: [
        // CANVAS
        Expanded(
          flex: 2,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                carPos += details.delta;
              });
            },
            child: Container(
              color: Colors.grey[200],
              child: CustomPaint(
                painter: _IllegalTurnBFPainter(
                  carPos: carPos,
                  gateA: gateA,
                  gateB: gateB,
                  hitA: hitGateA,
                  hitB: hitGateB,
                ),
                size: Size.infinite,
              ),
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
                      Text("The Brute Force Way: Fixed Gates", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Older systems relied on 'tripwires' or gates. If a car touched Gate A and then touched Gate B, the system assumed it made a turn.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Expose the Flaw:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                      SizedBox(height: 8),
                      Text("Drag the car diagonally across both gates without actually turning. The system gets easily confused because it doesn't understand the car's actual steering angle.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      Center(
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              carPos = Offset(100, 300);
                              hitGateA = false;
                              hitGateB = false;
                            });
                          },
                          child: Text("Reset Gates"),
                        ),
                      )
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
                  color: systemFlagsTurn ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: systemFlagsTurn ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      hitGateA ? "Hit Gate A: YES" : "Hit Gate A: NO",
                      style: TextStyle(color: hitGateA ? Colors.orange[900] : Colors.grey),
                    ),
                    Text(
                      hitGateB ? "Hit Gate B: YES" : "Hit Gate B: NO",
                      style: TextStyle(color: hitGateB ? Colors.orange[900] : Colors.grey),
                    ),
                    SizedBox(height: 12),
                    Text(
                      systemFlagsTurn 
                          ? "RESULT: TURN DETECTED" 
                          : "RESULT: NO TURN",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: systemFlagsTurn ? Colors.red[900] : Colors.green[900], 
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

class _IllegalTurnBFPainter extends CustomPainter {
  final Offset carPos;
  final Rect gateA;
  final Rect gateB;
  final bool hitA;
  final bool hitB;

  _IllegalTurnBFPainter({
    required this.carPos,
    required this.gateA,
    required this.gateB,
    required this.hitA,
    required this.hitB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Road Background
    Paint roadPaint = Paint()..color = Colors.grey[700]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    // Intersection markings
    Paint linePaint = Paint()..color = Colors.white..strokeWidth = 4;
    canvas.drawLine(Offset(180, 0), Offset(180, size.height), linePaint);
    canvas.drawLine(Offset(320, 0), Offset(320, size.height), linePaint);
    canvas.drawLine(Offset(0, 240), Offset(180, 240), linePaint);
    canvas.drawLine(Offset(320, 240), Offset(size.width, 240), linePaint);

    // Gates
    Paint gateAPaint = Paint()..color = hitA ? Colors.orange.withOpacity(0.5) : Colors.orange.withOpacity(0.2)..style = PaintingStyle.fill;
    Paint gateBBorder = Paint()..color = Colors.orange..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawRect(gateA, gateAPaint);
    canvas.drawRect(gateA, gateBBorder);
    
    Paint gateBPaint = Paint()..color = hitB ? Colors.red.withOpacity(0.5) : Colors.red.withOpacity(0.2)..style = PaintingStyle.fill;
    Paint gateBBorder2 = Paint()..color = Colors.red..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawRect(gateB, gateBPaint);
    canvas.drawRect(gateB, gateBBorder2);

    // Labels
    TextPainter tpA = TextPainter(
      text: TextSpan(text: "ENTRY GATE A", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tpA.layout();
    tpA.paint(canvas, Offset(gateA.left + 5, gateA.top + 5));

    TextPainter tpB = TextPainter(
      text: TextSpan(text: "EXIT GATE B", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tpB.layout();
    tpB.paint(canvas, Offset(gateB.left + 5, gateB.top + 5));

    // Car
    Paint carPaint = Paint()..color = Colors.blueAccent;
    canvas.drawCircle(carPos, 20, carPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
