import 'package:flutter/material.dart';

class OverloadingFirstPrinciple extends StatefulWidget {
  @override
  _OverloadingFirstPrincipleState createState() => _OverloadingFirstPrincipleState();
}

class _OverloadingFirstPrincipleState extends State<OverloadingFirstPrinciple> {
  Offset pedPos = Offset(100, 200);

  @override
  Widget build(BuildContext context) {
    Rect motoRect = Rect.fromLTWH(300, 200, 200, 150);
    Rect pedRect = Rect.fromLTWH(pedPos.dx, pedPos.dy, 80, 180);

    // Calculate IoU (Intersection over Union) with Motorcycle
    // Wait, the mathematical logic is overlap with the motorcycle box.
    // Let's do a simple overlap percentage of the pedestrian's box.
    
    Rect intersection = motoRect.intersect(pedRect);
    double overlapArea = intersection.width > 0 && intersection.height > 0 
        ? intersection.width * intersection.height 
        : 0;
    
    double pedArea = pedRect.width * pedRect.height;
    double iou = overlapArea / pedArea; // simplified to "Percentage of Person inside Moto box"

    bool isRider = iou > 0.3; // threshold 30%

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                pedPos += details.delta;
              });
            },
            child: Container(
              color: Colors.grey[200],
              child: CustomPaint(
                painter: _OverloadingFPPainter(
                  motoRect: motoRect,
                  pedRect: pedRect,
                  intersection: intersection,
                  iou: iou,
                  isRider: isRider,
                ),
                size: Size.infinite,
              ),
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
                      Text("Core Concept: IoU Association", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Modern AI uses Math to answer: 'Is this person actually ON the bike?'. It calculates the Intersection over Union (IoU) — how much their bounding box overlaps with the motorcycle's bounding box.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Test the Overlap:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                      SizedBox(height: 8),
                      Text("Drag the purple pedestrian box. Watch the Overlap Score change as you move them over the motorcycle.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      Text("Overlap Score: ${(iou * 100).toStringAsFixed(1)}%", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.orange[800])),
                      Text("Threshold: > 30% to be counted as Rider", style: TextStyle(fontSize: 12)),
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
                  color: isRider ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isRider ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      isRider 
                          ? "CLASSIFIED: RIDER" 
                          : "CLASSIFIED: PEDESTRIAN",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isRider ? Colors.red[900] : Colors.green[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (isRider)
                      Text("Will be added to Overloading count.", style: TextStyle(color: Colors.red[800], fontSize: 12), textAlign: TextAlign.center),
                    if (!isRider)
                      Text("Safely ignored by the system.", style: TextStyle(color: Colors.green[800], fontSize: 12), textAlign: TextAlign.center),
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

class _OverloadingFPPainter extends CustomPainter {
  final Rect motoRect;
  final Rect pedRect;
  final Rect intersection;
  final double iou;
  final bool isRider;

  _OverloadingFPPainter({
    required this.motoRect, 
    required this.pedRect, 
    required this.intersection, 
    required this.iou, 
    required this.isRider
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    Paint bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw Motorcycle Box
    Paint motoPaint = Paint()..color = Colors.blueGrey.withOpacity(0.2)..style = PaintingStyle.fill;
    Paint motoBorder = Paint()..color = Colors.blueGrey..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawRect(motoRect, motoPaint);
    canvas.drawRect(motoRect, motoBorder);
    
    TextPainter tpMoto = TextPainter(
      text: TextSpan(text: "MOTORCYCLE BOX", style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tpMoto.layout();
    tpMoto.paint(canvas, Offset(motoRect.left + 5, motoRect.bottom + 5));

    // Draw Intersection (Overlap)
    if (intersection.width > 0 && intersection.height > 0) {
      Paint interPaint = Paint()..color = Colors.orange.withOpacity(0.5)..style = PaintingStyle.fill;
      canvas.drawRect(intersection, interPaint);
    }

    // Draw Pedestrian Box
    Paint pedPaint = Paint()..color = Colors.purple.withOpacity(0.2)..style = PaintingStyle.fill;
    Paint pedBorder = Paint()..color = isRider ? Colors.red : Colors.green..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawRect(pedRect, pedPaint);
    canvas.drawRect(pedRect, pedBorder);

    TextPainter tpPed = TextPainter(
      text: TextSpan(text: "PERSON BOX (Drag)", style: TextStyle(color: isRider ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tpPed.layout();
    tpPed.paint(canvas, Offset(pedRect.left + 5, pedRect.top - 20));

    // IoU Label in center of ped box
    TextPainter tpIou = TextPainter(
      text: TextSpan(text: "${(iou * 100).toStringAsFixed(0)}%", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 24, backgroundColor: Colors.white70)),
      textDirection: TextDirection.ltr,
    );
    tpIou.layout();
    tpIou.paint(canvas, Offset(pedRect.center.dx - tpIou.width/2, pedRect.center.dy - tpIou.height/2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
