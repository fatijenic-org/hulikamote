import 'package:flutter/material.dart';

class NoPlateFirstPrinciple extends StatefulWidget {
  @override
  _NoPlateFirstPrincipleState createState() => _NoPlateFirstPrincipleState();
}

class _NoPlateFirstPrincipleState extends State<NoPlateFirstPrinciple> {
  double cropPercentage = 100.0;

  @override
  Widget build(BuildContext context) {
    bool isOptimized = cropPercentage <= 40.0;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: ClipRect(
              child: CustomPaint(
                painter: _NoPlateFPPainter(
                  cropPercentage: cropPercentage,
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
                      Text("Core Concept: Space Reduction", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "We don't need to search the car's roof or windows for a license plate. By ignoring the top section, we eliminate false positives and process data faster.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Adjust the Search Area:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text("Slide to crop the box from the top down.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      Slider(
                        value: cropPercentage,
                        min: 20.0,
                        max: 100.0,
                        activeColor: Colors.blue,
                        onChanged: (val) => setState(() => cropPercentage = val),
                      ),
                      Text("Scanning bottom ${cropPercentage.toStringAsFixed(0)}% of the vehicle", style: TextStyle(fontWeight: FontWeight.bold)),
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
                  color: isOptimized ? Colors.green[100] : Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isOptimized ? Colors.green : Colors.orange, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      isOptimized 
                          ? "OPTIMIZED!" 
                          : "TOO MUCH NOISE",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isOptimized ? Colors.green[900] : Colors.orange[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (!isOptimized)
                      Text("Stickers and grilles might cause false positives.", style: TextStyle(color: Colors.orange[900], fontSize: 12), textAlign: TextAlign.center),
                    if (isOptimized)
                      Text("Only scanning where plates actually belong.", style: TextStyle(color: Colors.green[900], fontSize: 12), textAlign: TextAlign.center),
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

class _NoPlateFPPainter extends CustomPainter {
  final double cropPercentage;

  _NoPlateFPPainter({required this.cropPercentage});

  @override
  void paint(Canvas canvas, Size size) {
    double centerX = size.width / 2;
    double startY = size.height / 2 - 100;

    // Background
    Paint bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Car Body
    Rect carBody = Rect.fromCenter(center: Offset(centerX, startY + 150), width: 140, height: 200);
    Paint carPaint = Paint()..color = Colors.blueGrey;
    canvas.drawRRect(RRect.fromRectAndRadius(carBody, Radius.circular(10)), carPaint);
    
    // Rear Window
    Rect window = Rect.fromCenter(center: Offset(centerX, startY + 80), width: 100, height: 40);
    Paint glassPaint = Paint()..color = Colors.lightBlueAccent;
    canvas.drawRect(window, glassPaint);

    // Bumper Sticker
    Rect sticker = Rect.fromCenter(center: Offset(centerX, startY + 160), width: 80, height: 32);
    Paint stickerPaint = Paint()..color = Colors.yellow[200]!;
    canvas.drawRect(sticker, stickerPaint);
    
    // Actual Plate
    Rect actualPlate = Rect.fromCenter(center: Offset(centerX, startY + 220), width: 75, height: 30);
    Paint platePaint = Paint()..color = Colors.white;
    Paint plateBorder = Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2;
    canvas.drawRect(actualPlate, platePaint);
    canvas.drawRect(actualPlate, plateBorder);

    // Dark overlay on ignored areas
    double keptHeight = carBody.height * (cropPercentage / 100);
    double ignoredHeight = carBody.height - keptHeight;
    
    Rect ignoredRect = Rect.fromLTWH(carBody.left, carBody.top, carBody.width, ignoredHeight);
    Paint ignoredPaint = Paint()..color = Colors.black.withOpacity(0.6)..style = PaintingStyle.fill;
    canvas.drawRect(ignoredRect, ignoredPaint);
    
    // Highlight kept area
    Rect keptRect = Rect.fromLTWH(carBody.left, carBody.top + ignoredHeight, carBody.width, keptHeight);
    Paint keptBorder = Paint()..color = Colors.greenAccent..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawRect(keptRect, keptBorder);
    
    // Label
    TextPainter tpZone = TextPainter(
      text: TextSpan(text: "SEARCH ZONE", style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold, backgroundColor: Colors.white)),
      textDirection: TextDirection.ltr,
    );
    tpZone.layout();
    tpZone.paint(canvas, Offset(keptRect.right + 10, keptRect.center.dy - tpZone.height/2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
