import 'package:flutter/material.dart';

class SwervingBruteForce extends StatefulWidget {
  @override
  _SwervingBruteForceState createState() => _SwervingBruteForceState();
}

class _SwervingBruteForceState extends State<SwervingBruteForce> with SingleTickerProviderStateMixin {
  bool cameraShake = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: 100));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool systemThinksSwerving = cameraShake;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                double shakeOffset = cameraShake ? (_controller.value * 10 - 5) : 0;
                return CustomPaint(
                  painter: _SwervingBFPainter(
                    shakeOffset: shakeOffset,
                    systemThinksSwerving: systemThinksSwerving,
                  ),
                  size: Size.infinite,
                );
              },
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
                      Text("The Brute Force Way: Absolute X-Position", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Early algorithms simply checked if a car's X-coordinate changed too much between frames. If X jumped, it flagged swerving.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Expose the Flaw:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                      SizedBox(height: 8),
                      Text("The car is driving perfectly straight. But turn on 'Windy Day'. The slight camera shake changes the absolute X-coordinates of everything in the frame.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      SwitchListTile(
                        title: Text("Windy Day (Camera Shake)"),
                        value: cameraShake,
                        onChanged: (val) {
                          setState(() {
                            cameraShake = val;
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
                  color: systemThinksSwerving ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: systemThinksSwerving ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      systemThinksSwerving 
                          ? "VIOLATION! (SWERVING)" 
                          : "LEGAL: STRAIGHT LINE",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: systemThinksSwerving ? Colors.red[900] : Colors.green[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (systemThinksSwerving)
                      Text("FALSE POSITIVE! Camera shook, car didn't.", style: TextStyle(color: Colors.red[800], fontSize: 12), textAlign: TextAlign.center),
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

class _SwervingBFPainter extends CustomPainter {
  final double shakeOffset;
  final bool systemThinksSwerving;

  _SwervingBFPainter({required this.shakeOffset, required this.systemThinksSwerving});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2 + shakeOffset;
    double cy = size.height / 2;

    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    // Lane lines
    Paint linePaint = Paint()..color = Colors.white..strokeWidth = 2;
    for (int i=0; i<10; i++) {
      canvas.drawLine(Offset(cx - 60 + shakeOffset, i * 100.0), Offset(cx - 60 + shakeOffset, i * 100.0 + 50), linePaint);
      canvas.drawLine(Offset(cx + 60 + shakeOffset, i * 100.0), Offset(cx + 60 + shakeOffset, i * 100.0 + 50), linePaint);
    }

    // Car (stays relative to road, so it shakes with it)
    Rect carRect = Rect.fromCenter(center: Offset(cx, cy), width: 60, height: 100);
    canvas.drawRRect(RRect.fromRectAndRadius(carRect, Radius.circular(10)), Paint()..color = Colors.blueGrey);
    
    // Dumb X-Tracker (Fixed to screen space, not shaking!)
    double trackerX = size.width / 2; 
    
    // The tracker measures the difference between trackerX and the car's current CX.
    canvas.drawLine(Offset(trackerX, cy), Offset(cx, cy), Paint()..color = systemThinksSwerving ? Colors.red : Colors.green..strokeWidth = 3);
    
    // X Coordinate HUD
    TextPainter tpX = TextPainter(
      text: TextSpan(text: "X: ${cx.toStringAsFixed(1)}", style: TextStyle(color: systemThinksSwerving ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 18, backgroundColor: Colors.black)),
      textDirection: TextDirection.ltr,
    );
    tpX.layout();
    tpX.paint(canvas, Offset(cx + 40, cy));

    if (systemThinksSwerving) {
      TextPainter tpErr = TextPainter(
        text: TextSpan(text: "ΔX > THRESHOLD\nSWERVE DETECTED!", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, backgroundColor: Colors.black)),
        textDirection: TextDirection.ltr,
      );
      tpErr.layout();
      tpErr.paint(canvas, Offset(cx + 40, cy + 30));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
