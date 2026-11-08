import 'package:flutter/material.dart';

class NoSeatbeltFirstPrinciple extends StatefulWidget {
  @override
  _NoSeatbeltFirstPrincipleState createState() => _NoSeatbeltFirstPrincipleState();
}

class _NoSeatbeltFirstPrincipleState extends State<NoSeatbeltFirstPrinciple> {
  double cnnDepth = 1.0; // 1 to 5

  @override
  Widget build(BuildContext context) {
    bool isSeatbeltFound = cnnDepth > 3.0;
    
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _NoSeatbeltFPPainter(
                cnnDepth: cnnDepth,
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
                      Text("Core Concept: CNN Feature Extraction", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Modern Convolutional Neural Networks (CNNs) don't just look for colors. They look through multiple mathematical 'layers' to find textures, shadows, and the physical shape of a seatbelt strap, even if it's black-on-black.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Increase CNN Depth:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                      SizedBox(height: 8),
                      Text("Slide to see what deeper layers of the neural network 'see'. Notice how texture and depth emerge, revealing the hidden black seatbelt.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      Slider(
                        value: cnnDepth,
                        min: 1.0,
                        max: 5.0,
                        divisions: 4,
                        activeColor: Colors.blue,
                        onChanged: (val) {
                          setState(() {
                            cnnDepth = val;
                          });
                        },
                      ),
                      Text("Network Layer: ${cnnDepth.toInt()}", style: TextStyle(fontWeight: FontWeight.bold)),
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
                  color: isSeatbeltFound ? Colors.green[100] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isSeatbeltFound ? Colors.green : Colors.grey, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      isSeatbeltFound 
                          ? "SEATBELT RECOGNIZED" 
                          : "SEARCHING TEXTURES...",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isSeatbeltFound ? Colors.green[900] : Colors.grey[800], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (isSeatbeltFound)
                      Text("CNN successfully separated strap from shirt.", style: TextStyle(color: Colors.green[800], fontSize: 12), textAlign: TextAlign.center),
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

class _NoSeatbeltFPPainter extends CustomPainter {
  final double cnnDepth;

  _NoSeatbeltFPPainter({required this.cnnDepth});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint bgPaint = Paint()..color = Colors.black87..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Bounding Box
    Rect cropBox = Rect.fromCenter(center: Offset(cx, cy), width: 200, height: 250);
    canvas.drawRect(cropBox, Paint()..color = Colors.grey[900]!);

    // Base shirt (black)
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 50), width: 140, height: 140), Radius.circular(20)), Paint()..color = Colors.black);
    
    // Head (just an outline to focus on chest)
    canvas.drawCircle(Offset(cx, cy - 60), 40, Paint()..color = Colors.white10);

    // CNN Layers visualization
    if (cnnDepth >= 1) {
      // Layer 1: Raw pixels (everything looks black)
      canvas.drawPath(_beltPath(cx, cy), Paint()..color = Colors.black..strokeWidth = 20..style = PaintingStyle.stroke);
      _drawLabel(canvas, "L1: Raw RGB", cx - 90, cy - 110, Colors.grey);
    }
    if (cnnDepth >= 2) {
      // Layer 2: Edges (faint noise)
      canvas.drawPath(_beltPath(cx, cy), Paint()..color = Colors.white12..strokeWidth = 22..style = PaintingStyle.stroke);
      _drawLabel(canvas, "L2: Edge Filters", cx - 90, cy - 90, Colors.grey);
    }
    if (cnnDepth >= 3) {
      // Layer 3: Shadows/Depth
      canvas.drawPath(_beltPath(cx, cy).shift(Offset(2, 2)), Paint()..color = Colors.blueGrey.withOpacity(0.3)..strokeWidth = 20..style = PaintingStyle.stroke);
      _drawLabel(canvas, "L3: Shadow Maps", cx - 90, cy - 70, Colors.cyan);
    }
    if (cnnDepth >= 4) {
      // Layer 4: Texture/Fabric
      Paint texturePaint = Paint()
        ..color = Colors.greenAccent.withOpacity(0.5)
        ..strokeWidth = 20
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(_beltPath(cx, cy), texturePaint);
      
      // Draw some "weave" lines
      canvas.drawPath(_beltPath(cx, cy), Paint()..color = Colors.white..strokeWidth = 2..style = PaintingStyle.stroke..strokeDashPattern = [5, 5]);
      _drawLabel(canvas, "L4: Texture Weave", cx - 90, cy - 50, Colors.greenAccent);
    }
    if (cnnDepth >= 5) {
      // Layer 5: Object Output
      canvas.drawPath(_beltPath(cx, cy), Paint()..color = Colors.green..strokeWidth = 24..style = PaintingStyle.stroke);
      canvas.drawRect(cropBox, Paint()..color = Colors.green..strokeWidth = 4..style = PaintingStyle.stroke);
      _drawLabel(canvas, "L5: 'SEATBELT' DETECTED", cx - 90, cy - 30, Colors.green);
    }
  }

  Path _beltPath(double cx, double cy) {
    Path p = Path();
    p.moveTo(cx - 50, cy);
    p.lineTo(cx + 50, cy + 120);
    return p;
  }

  void _drawLabel(Canvas canvas, String text, double x, double y, Color color) {
    TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Helper for strokeDashPattern (not built into Flutter Paint natively, simplified)
extension DashedPath on Paint {
  set strokeDashPattern(List<double> pattern) {
    // Note: implementing true dashed path requires a custom package or complex logic.
    // In our simplified canvas, we just use a different visual style if needed, 
    // but here we just ignore the dash and use a thin line.
  }
}
