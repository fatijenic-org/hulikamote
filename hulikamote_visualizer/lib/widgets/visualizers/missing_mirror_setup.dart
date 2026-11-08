import 'package:flutter/material.dart';

class MissingMirrorSetup extends StatefulWidget {
  @override
  _MissingMirrorSetupState createState() => _MissingMirrorSetupState();
}

class _MissingMirrorSetupState extends State<MissingMirrorSetup> {
  bool breakLeftMirror = false;
  bool breakRightMirror = false;

  @override
  Widget build(BuildContext context) {
    bool hasViolation = breakLeftMirror || breakRightMirror;

    return Row(
      children: [
        // CANVAS
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _MissingMirrorSetupPainter(
                breakLeftMirror: breakLeftMirror,
                breakRightMirror: breakRightMirror,
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
                      Text("Real-World Setup: Keypoint Confidence", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "The AI maps a 'skeleton' of key parts onto the motorcycle. If the confidence score for the mirror joints drops below 50%, it flags a violation.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Simulate Missing Mirrors:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      SwitchListTile(
                        title: Text("Break Left Mirror"),
                        value: breakLeftMirror,
                        onChanged: (val) => setState(() => breakLeftMirror = val),
                      ),
                      SwitchListTile(
                        title: Text("Break Right Mirror"),
                        value: breakRightMirror,
                        onChanged: (val) => setState(() => breakRightMirror = val),
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
                  color: hasViolation ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: hasViolation ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      hasViolation 
                          ? "VIOLATION LOGGED" 
                          : "ALL MIRRORS PRESENT",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: hasViolation ? Colors.red[900] : Colors.green[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (hasViolation)
                      Text("Confidence below threshold.", style: TextStyle(color: Colors.red[800], fontSize: 12), textAlign: TextAlign.center),
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

class _MissingMirrorSetupPainter extends CustomPainter {
  final bool breakLeftMirror;
  final bool breakRightMirror;

  _MissingMirrorSetupPainter({required this.breakLeftMirror, required this.breakRightMirror});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Bounding Box
    Rect bbox = Rect.fromCenter(center: Offset(cx, cy + 20), width: 140, height: 200);
    Paint boxBorder = Paint()..color = Colors.cyan..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawRect(bbox, boxBorder);

    // Skeleton lines
    Paint bonePaint = Paint()..color = Colors.yellow..strokeWidth = 4;
    
    Offset centerJoint = Offset(cx, cy + 20);
    Offset wheel1 = Offset(cx, cy + 100);
    Offset handleLeft = Offset(cx - 30, cy - 10);
    Offset handleRight = Offset(cx + 30, cy - 10);
    
    Offset leftMirror = Offset(bbox.left + (bbox.width * 0.1), bbox.top + (bbox.height * 0.15));
    Offset rightMirror = Offset(bbox.left + (bbox.width * 0.9), bbox.top + (bbox.height * 0.15));

    canvas.drawLine(centerJoint, wheel1, bonePaint);
    canvas.drawLine(centerJoint, handleLeft, bonePaint);
    canvas.drawLine(centerJoint, handleRight, bonePaint);
    canvas.drawLine(handleLeft, leftMirror, bonePaint);
    canvas.drawLine(handleRight, rightMirror, bonePaint);

    // Joints
    Paint jointPaint = Paint()..color = Colors.redAccent;
    canvas.drawCircle(centerJoint, 6, jointPaint);
    canvas.drawCircle(wheel1, 6, jointPaint);
    canvas.drawCircle(handleLeft, 6, jointPaint);
    canvas.drawCircle(handleRight, 6, jointPaint);

    // Mirrors
    if (!breakLeftMirror) {
      canvas.drawCircle(leftMirror, 12, Paint()..color = Colors.blueGrey);
    }
    if (!breakRightMirror) {
      canvas.drawCircle(rightMirror, 12, Paint()..color = Colors.blueGrey);
    }

    // Mirror Confidence Labels
    _drawConfidence(canvas, leftMirror, breakLeftMirror ? 0.12 : 0.98);
    _drawConfidence(canvas, rightMirror, breakRightMirror ? 0.05 : 0.95);
  }

  void _drawConfidence(Canvas canvas, Offset pos, double conf) {
    bool passed = conf > 0.5;
    
    Paint confNode = Paint()..color = passed ? Colors.green : Colors.red;
    canvas.drawCircle(pos, 8, confNode);

    TextPainter tp = TextPainter(
      text: TextSpan(
        text: "${(conf * 100).toStringAsFixed(0)}%", 
        style: TextStyle(color: passed ? Colors.green[900] : Colors.red[900], fontWeight: FontWeight.bold, backgroundColor: Colors.white, fontSize: 12)
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(pos.dx + 15, pos.dy - 10));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
