import 'package:flutter/material.dart';

class PedestrianFirstPrinciple extends StatefulWidget {
  @override
  _PedestrianFirstPrincipleState createState() => _PedestrianFirstPrincipleState();
}

class _PedestrianFirstPrincipleState extends State<PedestrianFirstPrinciple> {
  bool isRedLight = true;
  bool isOverlapping = true;
  bool isSpeedZero = true;

  @override
  Widget build(BuildContext context) {
    bool isViolating = isRedLight && isOverlapping && isSpeedZero;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _PedestrianFPPainter(
                isRedLight: isRedLight,
                isOverlapping: isOverlapping,
                isSpeedZero: isSpeedZero,
                isViolating: isViolating,
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
                      Text("Core Concept: AND Logic Gate", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Modern AI doesn't rely on a single trigger. It acts like a boolean logic gate, requiring 3 specific conditions to be met simultaneously.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Toggle the Variables:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                      SizedBox(height: 8),
                      Text("Change the conditions below to see how the mathematical formula strictly prevents false positives.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      SwitchListTile(
                        title: Text("1. Light is RED", style: TextStyle(fontWeight: FontWeight.bold, color: isRedLight ? Colors.red : Colors.grey)),
                        value: isRedLight,
                        onChanged: (val) => setState(() => isRedLight = val),
                      ),
                      SwitchListTile(
                        title: Text("2. Car is in Crosswalk", style: TextStyle(fontWeight: FontWeight.bold, color: isOverlapping ? Colors.orange : Colors.grey)),
                        value: isOverlapping,
                        onChanged: (val) => setState(() => isOverlapping = val),
                      ),
                      SwitchListTile(
                        title: Text("3. Speed == 0 (Stopped)", style: TextStyle(fontWeight: FontWeight.bold, color: isSpeedZero ? Colors.blue : Colors.grey)),
                        value: isSpeedZero,
                        onChanged: (val) => setState(() => isSpeedZero = val),
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
                  color: isViolating ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isViolating ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      isViolating 
                          ? "VIOLATION LOGGED" 
                          : "LEGAL STATE",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isViolating ? Colors.red[900] : Colors.green[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (!isViolating)
                      Text("Not all conditions met.", style: TextStyle(color: Colors.green[800], fontSize: 12), textAlign: TextAlign.center),
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

class _PedestrianFPPainter extends CustomPainter {
  final bool isRedLight;
  final bool isOverlapping;
  final bool isSpeedZero;
  final bool isViolating;

  _PedestrianFPPainter({
    required this.isRedLight,
    required this.isOverlapping,
    required this.isSpeedZero,
    required this.isViolating,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint bgPaint = Paint()..color = Colors.black87..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Logic Gate Visualization
    double startY = cy - 80;
    
    _drawNode(canvas, cx - 120, startY, "Light == Red", isRedLight, Colors.redAccent);
    _drawNode(canvas, cx, startY, "IoU > 0", isOverlapping, Colors.orangeAccent);
    _drawNode(canvas, cx + 120, startY, "Speed == 0", isSpeedZero, Colors.lightBlueAccent);

    // Wires
    Paint wirePaint = Paint()..color = Colors.white54..strokeWidth = 2;
    canvas.drawLine(Offset(cx - 120, startY + 20), Offset(cx, cy + 30), wirePaint);
    canvas.drawLine(Offset(cx, startY + 20), Offset(cx, cy + 30), wirePaint);
    canvas.drawLine(Offset(cx + 120, startY + 20), Offset(cx, cy + 30), wirePaint);

    // AND Gate
    Rect gateRect = Rect.fromCenter(center: Offset(cx, cy + 50), width: 100, height: 40);
    canvas.drawRect(gateRect, Paint()..color = isViolating ? Colors.red : Colors.grey[800]!);
    canvas.drawRect(gateRect, Paint()..color = Colors.white..strokeWidth = 2..style = PaintingStyle.stroke);
    
    TextPainter tpGate = TextPainter(
      text: TextSpan(text: "AND GATE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      textDirection: TextDirection.ltr,
    );
    tpGate.layout();
    tpGate.paint(canvas, Offset(gateRect.center.dx - tpGate.width/2, gateRect.center.dy - tpGate.height/2));

    // Output Wire
    canvas.drawLine(Offset(cx, cy + 70), Offset(cx, cy + 120), wirePaint);
    
    // Output Result
    TextPainter tpOut = TextPainter(
      text: TextSpan(
        text: isViolating ? "TRUE (VIOLATION)" : "FALSE (LEGAL)", 
        style: TextStyle(color: isViolating ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 20)
      ),
      textDirection: TextDirection.ltr,
    );
    tpOut.layout();
    tpOut.paint(canvas, Offset(cx - tpOut.width/2, cy + 130));
  }

  void _drawNode(Canvas canvas, double x, double y, String text, bool state, Color activeColor) {
    canvas.drawCircle(Offset(x, y), 20, Paint()..color = state ? activeColor : Colors.grey[800]!);
    canvas.drawCircle(Offset(x, y), 20, Paint()..color = Colors.white..strokeWidth = 2..style = PaintingStyle.stroke);
    
    TextPainter tp = TextPainter(
      text: TextSpan(
        text: text + "\n" + (state ? "TRUE" : "FALSE"), 
        style: TextStyle(color: state ? activeColor : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x - tp.width/2, y - 45));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
