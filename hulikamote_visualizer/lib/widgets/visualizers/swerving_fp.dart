import 'package:flutter/material.dart';

class SwervingFirstPrinciple extends StatefulWidget {
  @override
  _SwervingFirstPrincipleState createState() => _SwervingFirstPrincipleState();
}

class _SwervingFirstPrincipleState extends State<SwervingFirstPrinciple> {
  double lateralJerk = 0.5; // 0 to 5

  @override
  Widget build(BuildContext context) {
    bool isViolating = lateralJerk > 3.0;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _SwervingFPPainter(
                lateralJerk: lateralJerk,
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
                      Text("Core Concept: Jerk Physics", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Modern AI calculates Velocity (speed), Acceleration (change in speed), and Jerk (change in acceleration). Changing lanes smoothly is legal. Violently jerking the wheel is illegal.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Test the Physics:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                      SizedBox(height: 8),
                      Text("Slide to increase the suddenness of the lane change. Watch how the Math Engine calculates the Jerk threshold.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      Slider(
                        value: lateralJerk,
                        min: 0.1,
                        max: 5.0,
                        activeColor: Colors.blue,
                        onChanged: (val) {
                          setState(() {
                            lateralJerk = val;
                          });
                        },
                      ),
                      Text("Calculated Jerk (J): ${lateralJerk.toStringAsFixed(2)} m/s³", style: TextStyle(fontWeight: FontWeight.bold)),
                      Text("Threshold: J > 3.0", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
                          ? "VIOLATION (SWERVE)" 
                          : "LEGAL (SMOOTH CHANGE)",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isViolating ? Colors.red[900] : Colors.green[900], 
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

class _SwervingFPPainter extends CustomPainter {
  final double lateralJerk;
  final bool isViolating;

  _SwervingFPPainter({required this.lateralJerk, required this.isViolating});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint bgPaint = Paint()..color = Colors.black87..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Graph Area
    Rect graphRect = Rect.fromCenter(center: Offset(cx, cy), width: 300, height: 200);
    canvas.drawRect(graphRect, Paint()..color = Colors.grey[900]!);
    canvas.drawRect(graphRect, Paint()..color = Colors.white54..strokeWidth = 2..style = PaintingStyle.stroke);

    // Draw axes
    canvas.drawLine(Offset(graphRect.left, graphRect.center.dy), Offset(graphRect.right, graphRect.center.dy), Paint()..color = Colors.white24); // Center line (0 jerk)

    // Threshold lines
    double threshYTop = graphRect.center.dy - (graphRect.height / 2 * (3.0 / 5.0));
    double threshYBot = graphRect.center.dy + (graphRect.height / 2 * (3.0 / 5.0));
    canvas.drawLine(Offset(graphRect.left, threshYTop), Offset(graphRect.right, threshYTop), Paint()..color = Colors.redAccent.withOpacity(0.5)..strokeWidth = 1);
    canvas.drawLine(Offset(graphRect.left, threshYBot), Offset(graphRect.right, threshYBot), Paint()..color = Colors.redAccent.withOpacity(0.5)..strokeWidth = 1);

    TextPainter tpT = TextPainter(
      text: TextSpan(text: "ILLEGAL ZONE", style: TextStyle(color: Colors.redAccent, fontSize: 10)),
      textDirection: TextDirection.ltr,
    );
    tpT.layout();
    tpT.paint(canvas, Offset(graphRect.left + 5, threshYTop - 15));

    // Draw Jerk Curve
    Path curve = Path();
    curve.moveTo(graphRect.left, graphRect.center.dy);
    
    // Create a spike that matches the jerk value
    double spikeHeight = (graphRect.height / 2) * (lateralJerk / 5.0);
    
    curve.quadraticBezierTo(graphRect.left + 50, graphRect.center.dy, graphRect.left + 100, graphRect.center.dy - spikeHeight);
    curve.quadraticBezierTo(graphRect.left + 150, graphRect.center.dy - spikeHeight * 1.5, graphRect.left + 200, graphRect.center.dy + spikeHeight);
    curve.quadraticBezierTo(graphRect.left + 250, graphRect.center.dy, graphRect.right, graphRect.center.dy);

    Paint curvePaint = Paint()..color = isViolating ? Colors.redAccent : Colors.greenAccent..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawPath(curve, curvePaint);

    // Math Equation
    TextPainter tpMath = TextPainter(
      text: TextSpan(text: "J = d(Velocity)/dt", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 16)),
      textDirection: TextDirection.ltr,
    );
    tpMath.layout();
    tpMath.paint(canvas, Offset(graphRect.left + 10, graphRect.top + 10));

    // Dot on the peak
    canvas.drawCircle(Offset(graphRect.left + 150, graphRect.center.dy - spikeHeight * 1.5), 6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
