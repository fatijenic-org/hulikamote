import 'package:flutter/material.dart';

class MissingMirrorFirstPrinciple extends StatefulWidget {
  @override
  _MissingMirrorFirstPrincipleState createState() => _MissingMirrorFirstPrincipleState();
}

class _MissingMirrorFirstPrincipleState extends State<MissingMirrorFirstPrinciple> {
  bool checkLeft = true;
  bool checkRight = true;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _MissingMirrorFPPainter(
                checkLeft: checkLeft,
                checkRight: checkRight,
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
                      Text("Core Concept: Keypoint Targets", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Instead of checking the whole shape, modern AI calculates exactly where the mirrors should be mathematically relative to the motorcycle's bounding box.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Mathematical Coordinates:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                      SizedBox(height: 8),
                      Text("Left Expected: (X + 10%, Y + 15%)\nRight Expected: (X + 90%, Y + 15%)", style: TextStyle(fontFamily: 'monospace', fontSize: 13)),
                      SizedBox(height: 16),
                      
                      Text("2. Target Isolation:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text("Toggle the specific regions the AI focuses on to scan for mirrors.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SwitchListTile(
                        title: Text("Scan Left Target"),
                        value: checkLeft,
                        onChanged: (val) => setState(() => checkLeft = val),
                      ),
                      SwitchListTile(
                        title: Text("Scan Right Target"),
                        value: checkRight,
                        onChanged: (val) => setState(() => checkRight = val),
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
                  color: (checkLeft && checkRight) ? Colors.green[100] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (checkLeft && checkRight) ? Colors.green : Colors.grey, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      (checkLeft && checkRight)
                          ? "BOTH TARGETS SCANNED" 
                          : "INCOMPLETE SCAN",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: (checkLeft && checkRight) ? Colors.green[900] : Colors.grey[800], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 16
                      ),
                    ),
                    if (checkLeft && checkRight)
                      Text("AI ignores background noise entirely.", style: TextStyle(color: Colors.green[800], fontSize: 12), textAlign: TextAlign.center),
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

class _MissingMirrorFPPainter extends CustomPainter {
  final bool checkLeft;
  final bool checkRight;

  _MissingMirrorFPPainter({required this.checkLeft, required this.checkRight});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    // Background
    Paint bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Bounding Box
    Rect bbox = Rect.fromCenter(center: Offset(cx, cy + 20), width: 140, height: 200);
    Paint boxPaint = Paint()..color = Colors.cyan.withOpacity(0.2)..style = PaintingStyle.fill;
    Paint boxBorder = Paint()..color = Colors.cyan..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawRect(bbox, boxPaint);
    canvas.drawRect(bbox, boxBorder);
    
    TextPainter tpBox = TextPainter(
      text: TextSpan(text: "Bounding Box (X, Y, W, H)", style: TextStyle(color: Colors.cyan[900], fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tpBox.layout();
    tpBox.paint(canvas, Offset(bbox.left, bbox.bottom + 5));

    // Motorcycle Shape (Abstract)
    Path bikePath = Path();
    bikePath.moveTo(cx, cy - 30);
    bikePath.lineTo(cx - 30, cy + 20);
    bikePath.lineTo(cx - 20, cy + 100);
    bikePath.lineTo(cx + 20, cy + 100);
    bikePath.lineTo(cx + 30, cy + 20);
    bikePath.close();

    // Mirrors
    Offset leftMirror = Offset(bbox.left + (bbox.width * 0.1), bbox.top + (bbox.height * 0.15));
    Offset rightMirror = Offset(bbox.left + (bbox.width * 0.9), bbox.top + (bbox.height * 0.15));

    bikePath.addOval(Rect.fromCircle(center: leftMirror, radius: 10));
    bikePath.addOval(Rect.fromCircle(center: rightMirror, radius: 10));

    Paint bikePaint = Paint()..color = Colors.blueGrey;
    canvas.drawPath(bikePath, bikePaint);

    // Expected Targets
    Paint targetPaint = Paint()..color = Colors.red..strokeWidth = 3..style = PaintingStyle.stroke;
    
    if (checkLeft) {
      canvas.drawCircle(leftMirror, 20, targetPaint);
      canvas.drawLine(Offset(leftMirror.dx, leftMirror.dy - 30), Offset(leftMirror.dx, leftMirror.dy + 30), targetPaint);
      canvas.drawLine(Offset(leftMirror.dx - 30, leftMirror.dy), Offset(leftMirror.dx + 30, leftMirror.dy), targetPaint);
    }
    
    if (checkRight) {
      canvas.drawCircle(rightMirror, 20, targetPaint);
      canvas.drawLine(Offset(rightMirror.dx, rightMirror.dy - 30), Offset(rightMirror.dx, rightMirror.dy + 30), targetPaint);
      canvas.drawLine(Offset(rightMirror.dx - 30, rightMirror.dy), Offset(rightMirror.dx + 30, rightMirror.dy), targetPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
