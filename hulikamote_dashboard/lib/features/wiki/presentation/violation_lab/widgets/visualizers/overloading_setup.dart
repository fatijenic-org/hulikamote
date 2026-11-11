import 'package:flutter/material.dart';
import 'dart:math';

class OverloadingSetup extends StatefulWidget {
  @override
  _OverloadingSetupState createState() => _OverloadingSetupState();
}

class _OverloadingSetupState extends State<OverloadingSetup> {
  int riders = 2;

  @override
  Widget build(BuildContext context) {
    bool isOverloaded = riders > 2;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _OverloadingSetupPainter(
                riders: riders,
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
                      Text("Real-World Setup: Multi-Class YOLO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "The system detects the motorcycle class and the person class simultaneously, then filters out people not overlapping the bike.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Simulate Loading:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text("Add or remove passengers to see how the system aggregates the IoU counts.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Number of Riders:"),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.remove_circle, color: Colors.blue),
                                onPressed: riders > 1 ? () => setState(() => riders--) : null,
                              ),
                              Text("$riders", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              IconButton(
                                icon: Icon(Icons.add_circle, color: Colors.blue),
                                onPressed: riders < 5 ? () => setState(() => riders++) : null,
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
                  color: isOverloaded ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isOverloaded ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      "Valid Riders Count: $riders",
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                    SizedBox(height: 8),
                    Text(
                      isOverloaded 
                          ? "RESULT: OVERLOADING (Violation)" 
                          : "RESULT: LEGAL",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isOverloaded ? Colors.red[900] : Colors.green[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 16
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

class _OverloadingSetupPainter extends CustomPainter {
  final int riders;

  _OverloadingSetupPainter({required this.riders});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Motorcycle
    Rect motoRect = Rect.fromCenter(center: Offset(cx, cy + 50), width: 220, height: 100);
    canvas.drawRRect(RRect.fromRectAndRadius(motoRect, Radius.circular(10)), Paint()..color = Colors.blueGrey.withOpacity(0.5));
    
    // Moto Bbox
    canvas.drawRect(motoRect.inflate(10), Paint()..color = Colors.cyan..strokeWidth = 3..style = PaintingStyle.stroke);
    TextPainter tpMoto = TextPainter(
      text: TextSpan(text: "YOLO: Motorcycle (99%)", style: TextStyle(color: Colors.cyan[900], fontWeight: FontWeight.bold, backgroundColor: Colors.white)),
      textDirection: TextDirection.ltr,
    );
    tpMoto.layout();
    tpMoto.paint(canvas, Offset(motoRect.left - 10, motoRect.bottom + 15));

    // Pedestrian in background
    _drawPerson(canvas, Offset(cx - 200, cy - 80), false);

    // Riders
    double startX = cx - 60;
    for (int i = 0; i < riders; i++) {
      _drawPerson(canvas, Offset(startX + (i * 40), cy - 20), true);
    }
  }

  void _drawPerson(Canvas canvas, Offset pos, bool isRider) {
    // Body & Head
    canvas.drawRect(Rect.fromCenter(center: Offset(pos.dx, pos.dy + 30), width: 30, height: 60), Paint()..color = Colors.deepOrange);
    canvas.drawCircle(pos, 15, Paint()..color = Colors.brown[300]!);

    // Bbox
    Rect pBox = Rect.fromCenter(center: Offset(pos.dx, pos.dy + 15), width: 40, height: 90);
    canvas.drawRect(pBox, Paint()..color = isRider ? Colors.redAccent : Colors.green..strokeWidth = 2..style = PaintingStyle.stroke);
    
    String label = isRider ? "YOLO: Person\nIoU: >30%" : "YOLO: Person\nIoU: 0%";
    TextPainter tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(color: isRider ? Colors.red[900] : Colors.green[900], fontWeight: FontWeight.bold, backgroundColor: Colors.white, fontSize: 10)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(pBox.left - 10, pBox.top - 25));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
