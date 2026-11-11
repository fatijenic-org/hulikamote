import 'package:flutter/material.dart';

class NoHelmetBruteForce extends StatefulWidget {
  @override
  _NoHelmetBruteForceState createState() => _NoHelmetBruteForceState();
}

class _NoHelmetBruteForceState extends State<NoHelmetBruteForce> {
  bool wearsHat = false; // The trap
  bool bald = false;

  @override
  Widget build(BuildContext context) {
    // The "Color/Texture Matcher" logic
    bool flagsHelmet = false;
    
    if (wearsHat) {
      // Hat looks dark and solid, old system might think it's a helmet
      flagsHelmet = true; 
    }
    if (bald) {
      // Bald head is shiny, old system might think it's a white helmet
      flagsHelmet = true;
    }

    bool falsePositive = flagsHelmet && (wearsHat || bald);

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _NoHelmetBFPainter(
                wearsHat: wearsHat,
                bald: bald,
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
                      Text("The Brute Force Way: Color Matching", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Older systems tried to detect helmets by looking for large, solid blocks of color (like black or white) near the top of the rider.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Expose the Flaw:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                      SizedBox(height: 8),
                      Text("Toggle these options to see how simple color matching gets tricked by everyday items or appearances.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      SwitchListTile(
                        title: Text("Wear Black Cap"),
                        value: wearsHat,
                        onChanged: (val) {
                          setState(() {
                            wearsHat = val;
                            if (val) bald = false; // mutually exclusive for visual simplicity
                          });
                        },
                      ),
                      SwitchListTile(
                        title: Text("Shiny Bald Head"),
                        value: bald,
                        onChanged: (val) {
                          setState(() {
                            bald = val;
                            if (val) wearsHat = false;
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
                  color: falsePositive ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: falsePositive ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      flagsHelmet 
                          ? "DETECTED: HELMET" 
                          : "DETECTED: NO HELMET",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: falsePositive ? Colors.red[900] : Colors.green[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (falsePositive)
                      Text("System was tricked by the shape/color!", style: TextStyle(color: Colors.red[800], fontSize: 12), textAlign: TextAlign.center),
                    if (!falsePositive && !flagsHelmet)
                      Text("Correctly flagged as violation.", style: TextStyle(color: Colors.green[800], fontSize: 12), textAlign: TextAlign.center),
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

class _NoHelmetBFPainter extends CustomPainter {
  final bool wearsHat;
  final bool bald;

  _NoHelmetBFPainter({required this.wearsHat, required this.bald});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    // Background
    Paint bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Motorcycle Body
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 100), width: 80, height: 150), Radius.circular(10)), Paint()..color = Colors.blueGrey);
    
    // Rider Body
    canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy + 30), width: 60, height: 100), Paint()..color = Colors.deepOrange);

    // Rider Head
    Paint headPaint = Paint()..color = Colors.brown[300]!;
    if (bald) headPaint.color = Colors.orange[100]!;
    canvas.drawCircle(Offset(cx, cy - 50), 25, headPaint);

    if (!bald && !wearsHat) {
      // Normal hair
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy - 55), radius: 25), 3.14, 3.14, true, Paint()..color = Colors.black);
    }

    if (wearsHat) {
      // Hat
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy - 55), radius: 25), 3.14, 3.14, true, Paint()..color = Colors.black87);
      canvas.drawRect(Rect.fromLTWH(cx + 10, cy - 55, 30, 5), Paint()..color = Colors.black87); // visor
    }

    // Color Scanner Overlay
    Paint scannerPaint = Paint()..color = Colors.greenAccent.withOpacity(0.4)..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy - 60), width: 80, height: 40), scannerPaint);
    
    TextPainter tpScan = TextPainter(
      text: TextSpan(text: "COLOR SCAN", style: TextStyle(color: Colors.green[900], fontWeight: FontWeight.bold, fontSize: 10)),
      textDirection: TextDirection.ltr,
    );
    tpScan.layout();
    tpScan.paint(canvas, Offset(cx + 45, cy - 65));
    
    // Highlight if tricked
    if (wearsHat || bald) {
      Paint trickLine = Paint()..color = Colors.red..strokeWidth = 2;
      canvas.drawLine(Offset(cx, cy - 80), Offset(cx + 80, cy - 120), trickLine);
      
      TextPainter tpTrick = TextPainter(
        text: TextSpan(text: bald ? "Looks like white helmet" : "Looks like black helmet", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, backgroundColor: Colors.white)),
        textDirection: TextDirection.ltr,
      );
      tpTrick.layout();
      tpTrick.paint(canvas, Offset(cx + 85, cy - 125));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
