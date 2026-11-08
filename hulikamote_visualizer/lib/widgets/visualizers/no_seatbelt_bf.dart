import 'package:flutter/material.dart';

class NoSeatbeltBruteForce extends StatefulWidget {
  @override
  _NoSeatbeltBruteForceState createState() => _NoSeatbeltBruteForceState();
}

class _NoSeatbeltBruteForceState extends State<NoSeatbeltBruteForce> {
  bool isBlackShirt = false;

  @override
  Widget build(BuildContext context) {
    bool systemSeesSeatbelt = !isBlackShirt; // Dumb system needs contrast

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _NoSeatbeltBFPainter(
                isBlackShirt: isBlackShirt,
                systemSeesSeatbelt: systemSeesSeatbelt,
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
                      Text("The Brute Force Way: Contrast Lines", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Early systems just applied Edge Detection. They literally just looked for a dark, diagonal line crossing the driver's chest.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Expose the Flaw:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                      SizedBox(height: 8),
                      Text("The driver is wearing a black seatbelt. Change the driver's shirt to Black. Because the seatbelt blends in, the dumb Edge Detector can no longer find the 'diagonal line'.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      SwitchListTile(
                        title: Text("Wear Black Shirt"),
                        value: isBlackShirt,
                        onChanged: (val) {
                          setState(() {
                            isBlackShirt = val;
                          });
                        },
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
                  color: systemSeesSeatbelt ? Colors.green[100] : Colors.red[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: systemSeesSeatbelt ? Colors.green : Colors.red, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      systemSeesSeatbelt 
                          ? "LEGAL: SEATBELT FOUND" 
                          : "VIOLATION: NO SEATBELT",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: systemSeesSeatbelt ? Colors.green[900] : Colors.red[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (!systemSeesSeatbelt)
                      Text("FALSE POSITIVE! The driver is wearing it, but it lacks contrast.", style: TextStyle(color: Colors.red[800], fontSize: 12), textAlign: TextAlign.center),
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

class _NoSeatbeltBFPainter extends CustomPainter {
  final bool isBlackShirt;
  final bool systemSeesSeatbelt;

  _NoSeatbeltBFPainter({required this.isBlackShirt, required this.systemSeesSeatbelt});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Car Windshield Frame
    canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: 300, height: 200), Paint()..color = Colors.grey[800]!);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: 280, height: 180), Paint()..color = Colors.lightBlue[50]!); // glass

    // Driver Body
    Paint shirtPaint = Paint()..color = isBlackShirt ? Colors.black87 : Colors.white;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx - 50, cy + 40), width: 100, height: 100), Radius.circular(20)), shirtPaint);
    
    // Driver Head
    canvas.drawCircle(Offset(cx - 50, cy - 40), 30, Paint()..color = Colors.orange[200]!);

    // Real Seatbelt (always there)
    Path beltPath = Path();
    beltPath.moveTo(cx - 90, cy - 10);
    beltPath.lineTo(cx - 10, cy + 90);
    canvas.drawPath(beltPath, Paint()..color = Colors.black..strokeWidth = 15..style = PaintingStyle.stroke);

    // AI Edge Detector Scanner Overlay
    Rect scanBox = Rect.fromCenter(center: Offset(cx - 50, cy + 40), width: 120, height: 120);
    canvas.drawRect(scanBox, Paint()..color = Colors.yellow..strokeWidth = 3..style = PaintingStyle.stroke);
    
    TextPainter tpScan = TextPainter(
      text: TextSpan(text: "EDGE DETECTOR", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, backgroundColor: Colors.black)),
      textDirection: TextDirection.ltr,
    );
    tpScan.layout();
    tpScan.paint(canvas, Offset(scanBox.left, scanBox.top - 20));

    // Extracted Edges view (Right side)
    Rect edgeBox = Rect.fromCenter(center: Offset(cx + 100, cy + 40), width: 80, height: 80);
    canvas.drawRect(edgeBox, Paint()..color = Colors.black);
    
    if (systemSeesSeatbelt) {
      // Draw the extracted line
      canvas.drawLine(Offset(edgeBox.left + 10, edgeBox.top + 10), Offset(edgeBox.right - 10, edgeBox.bottom - 10), Paint()..color = Colors.white..strokeWidth = 3);
      
      TextPainter tpEdge = TextPainter(
        text: TextSpan(text: "LINE FOUND!", style: TextStyle(color: Colors.greenAccent, fontSize: 10)),
        textDirection: TextDirection.ltr,
      );
      tpEdge.layout();
      tpEdge.paint(canvas, Offset(edgeBox.left, edgeBox.bottom + 5));
    } else {
      // Nothing
      TextPainter tpEdge = TextPainter(
        text: TextSpan(text: "BLANK (NO LINE)", style: TextStyle(color: Colors.redAccent, fontSize: 10)),
        textDirection: TextDirection.ltr,
      );
      tpEdge.layout();
      tpEdge.paint(canvas, Offset(edgeBox.left, edgeBox.bottom + 5));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
