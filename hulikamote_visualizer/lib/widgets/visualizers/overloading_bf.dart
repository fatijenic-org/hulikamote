import 'package:flutter/material.dart';

class OverloadingBruteForce extends StatefulWidget {
  @override
  _OverloadingBruteForceState createState() => _OverloadingBruteForceState();
}

class _OverloadingBruteForceState extends State<OverloadingBruteForce> {
  int pedestrianCount = 0;

  @override
  Widget build(BuildContext context) {
    int riderCount = 2; // Always 2 riders on the bike
    int totalCount = riderCount + pedestrianCount;
    bool flagged = totalCount > 2;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _OverloadingBFPainter(
                pedestrianCount: pedestrianCount,
                flagged: flagged,
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
                      Text("The Brute Force Way: Global Count", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Early systems just counted the total number of 'heads' or 'people' in the frame near a motorcycle. If the count exceeded 2, it flagged overloading.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Expose the Flaw:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                      SizedBox(height: 8),
                      Text("Add pedestrians walking behind the motorcycle. The system doesn't know who is actually ON the bike, so it blindly adds them to the count.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Background Pedestrians:"),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.remove_circle, color: Colors.red),
                                onPressed: pedestrianCount > 0 ? () => setState(() => pedestrianCount--) : null,
                              ),
                              Text("$pedestrianCount", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              IconButton(
                                icon: Icon(Icons.add_circle, color: Colors.green),
                                onPressed: pedestrianCount < 3 ? () => setState(() => pedestrianCount++) : null,
                              ),
                            ],
                          )
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
                  color: flagged ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: flagged ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      "Total Heads Detected: $totalCount",
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                    SizedBox(height: 8),
                    Text(
                      flagged 
                          ? "RESULT: OVERLOADING!" 
                          : "RESULT: LEGAL (2 Riders)",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: flagged ? Colors.red[900] : Colors.green[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 16
                      ),
                    ),
                    if (flagged)
                      Text("System got confused by pedestrians.", style: TextStyle(color: Colors.red[800], fontSize: 12), textAlign: TextAlign.center),
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

class _OverloadingBFPainter extends CustomPainter {
  final int pedestrianCount;
  final bool flagged;

  _OverloadingBFPainter({required this.pedestrianCount, required this.flagged});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2 + 50; // shift down a bit

    // Background
    Paint bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw Background Pedestrians
    List<Offset> pedPositions = [
      Offset(cx - 150, cy - 80),
      Offset(cx + 150, cy - 100),
      Offset(cx - 50, cy - 120),
    ];

    Paint pedPaint = Paint()..color = Colors.purple;
    for (int i = 0; i < pedestrianCount; i++) {
      _drawPerson(canvas, pedPositions[i], pedPaint, "HEAD: ${i+3}");
    }

    // Motorcycle Body
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 50), width: 140, height: 60), Radius.circular(10)), Paint()..color = Colors.blueGrey);
    
    // Rider 1 (Driver)
    _drawPerson(canvas, Offset(cx - 30, cy - 20), Paint()..color = Colors.orange, "HEAD: 1");
    
    // Rider 2 (Passenger)
    _drawPerson(canvas, Offset(cx + 30, cy - 20), Paint()..color = Colors.deepOrange, "HEAD: 2");

    // "Global Scanner" visual
    Paint scanPaint = Paint()..color = flagged ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1)..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), scanPaint);

    TextPainter tpScan = TextPainter(
      text: TextSpan(text: "GLOBAL HEAD SCANNER ACTIVE", style: TextStyle(color: flagged ? Colors.red : Colors.green, fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 2)),
      textDirection: TextDirection.ltr,
    );
    tpScan.layout();
    tpScan.paint(canvas, Offset(20, 20));
  }

  void _drawPerson(Canvas canvas, Offset pos, Paint paint, String label) {
    // Body
    canvas.drawRect(Rect.fromCenter(center: Offset(pos.dx, pos.dy + 30), width: 40, height: 60), paint);
    // Head
    canvas.drawCircle(pos, 20, Paint()..color = Colors.brown[300]!);
    
    // Bounding Box / Tracker
    canvas.drawRect(Rect.fromCenter(center: Offset(pos.dx, pos.dy + 15), width: 50, height: 90), Paint()..color = Colors.cyan..strokeWidth = 2..style = PaintingStyle.stroke);
    
    TextPainter tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(color: Colors.cyan[900], fontWeight: FontWeight.bold, backgroundColor: Colors.white, fontSize: 10)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(pos.dx - 20, pos.dy - 35));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
