import 'package:flutter/material.dart';
import 'dart:math' as math;

class IllegalParkingFirstPrinciple extends StatefulWidget {
  @override
  _IllegalParkingFirstPrincipleState createState() => _IllegalParkingFirstPrincipleState();
}

class _IllegalParkingFirstPrincipleState extends State<IllegalParkingFirstPrinciple> {
  Offset carPos = Offset(100, 200);
  final Rect zoneRect = Rect.fromLTWH(200, 100, 200, 150);
  final double carW = 100;
  final double carH = 50;

  @override
  Widget build(BuildContext context) {
    Rect carRect = Rect.fromCenter(center: carPos, width: carW, height: carH);
    
    Rect overlapRect = carRect.intersect(zoneRect);
    bool hasOverlap = overlapRect.width > 0 && overlapRect.height > 0;
    double overlapArea = hasOverlap ? overlapRect.width * overlapRect.height : 0;
    double carArea = carW * carH;
    double overlapPercentage = (overlapArea / carArea) * 100;

    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                carPos += details.delta;
              });
            },
            child: Container(
              color: Colors.white,
              child: ClipRect(
                child: CustomPaint(
                  painter: _FPPainter(
                    carRect: carRect,
                    zoneRect: zoneRect,
                    overlapRect: overlapRect,
                    hasOverlap: hasOverlap,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
        // CONTROLS AREA
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
                      Text("Core Concept: The Overlap Area", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Instead of relying on fixed screen coordinates, modern logic draws a 'Virtual Zone' and tracks the vehicle's shape.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      SizedBox(height: 16),
                      Text(
                        "Drag the blue car into the yellow zone to see how the system calculates the exact area of overlap.",
                        style: TextStyle(fontSize: 14, color: Colors.blue[800], fontWeight: FontWeight.bold),
                      ),
                      Divider(height: 32),
                      
                      Text("Intersection over Union (IoU):", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text("Car Total Area: ${carArea.toStringAsFixed(0)} px²"),
                      Text("Zone Total Area: ${(zoneRect.width * zoneRect.height).toStringAsFixed(0)} px²"),
                      SizedBox(height: 16),
                      Text("Overlap Area Calculation:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800])),
                      Text(
                        hasOverlap 
                            ? "${overlapRect.width.toStringAsFixed(1)} x ${overlapRect.height.toStringAsFixed(1)} = ${overlapArea.toStringAsFixed(0)} px²"
                            : "0 x 0 = 0 px²", 
                        style: TextStyle(fontSize: 16, fontFamily: 'monospace')
                      ),
                      
                      SizedBox(height: 24),
                      Center(
                        child: Container(
                          padding: EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: hasOverlap ? Colors.red : Colors.green, width: 4),
                          ),
                          child: Column(
                            children: [
                              Text(
                                "${overlapPercentage.toStringAsFixed(1)}%",
                                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: hasOverlap ? Colors.red : Colors.green),
                              ),
                              Text("Inside Zone", style: TextStyle(color: Colors.grey[600]))
                            ],
                          ),
                        ),
                      )
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
                  color: hasOverlap ? Colors.orange[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: hasOverlap ? Colors.orange : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      hasOverlap 
                          ? "RESULT: CAR IN ZONE" 
                          : "RESULT: SAFE",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: hasOverlap ? Colors.orange[900] : Colors.green[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (hasOverlap)
                      Text("(Timer would start now)", style: TextStyle(color: Colors.orange[900], fontSize: 12)),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Opacity(
                opacity: 0.4,
                child: Text("IoU = Area of Overlap / Area of Union", style: TextStyle(fontSize: 10)),
              )
            ],
          ),
        )
      ],
    );
  }
}

class _FPPainter extends CustomPainter {
  final Rect carRect;
  final Rect zoneRect;
  final Rect overlapRect;
  final bool hasOverlap;

  _FPPainter({
    required this.carRect,
    required this.zoneRect,
    required this.overlapRect,
    required this.hasOverlap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid background for "Concept" feel
    Paint gridPaint = Paint()..color = Colors.grey[200]!..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }

    // Draw Zone
    Paint zonePaint = Paint()..color = Colors.yellow.withOpacity(0.3)..style = PaintingStyle.fill;
    Paint zoneBorder = Paint()..color = Colors.yellow[700]!..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawRect(zoneRect, zonePaint);
    canvas.drawRect(zoneRect, zoneBorder);
    
    TextPainter tpZone = TextPainter(
      text: TextSpan(text: "VIRTUAL ZONE", style: TextStyle(color: Colors.yellow[800], fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tpZone.layout();
    tpZone.paint(canvas, Offset(zoneRect.left + 5, zoneRect.top + 5));

    // Draw Car
    Paint carPaint = Paint()..color = Colors.blueAccent.withOpacity(0.6)..style = PaintingStyle.fill;
    Paint carBorder = Paint()..color = Colors.blue[900]!..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawRect(carRect, carPaint);
    canvas.drawRect(carRect, carBorder);
    
    // Draw Overlap
    if (hasOverlap) {
      Paint overlapPaint = Paint()..color = Colors.red.withOpacity(0.8)..style = PaintingStyle.fill;
      canvas.drawRect(overlapRect, overlapPaint);
      
      // Label Overlap
      TextPainter tpOverlap = TextPainter(
        text: TextSpan(text: "OVERLAP AREA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tpOverlap.layout();
      canvas.save();
      canvas.translate(overlapRect.center.dx, overlapRect.center.dy);
      // Only draw text if it fits roughly
      if (overlapRect.width > 60 && overlapRect.height > 20) {
        tpOverlap.paint(canvas, Offset(-tpOverlap.width/2, -tpOverlap.height/2));
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
