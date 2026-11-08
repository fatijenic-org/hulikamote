import 'package:flutter/material.dart';
import 'dart:async';

class NoPlateBruteForce extends StatefulWidget {
  @override
  _NoPlateBruteForceState createState() => _NoPlateBruteForceState();
}

class _NoPlateBruteForceState extends State<NoPlateBruteForce> {
  double scannerY = 0;
  Timer? _timer;
  bool addBumperSticker = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(milliseconds: 50), (timer) {
      if (!mounted) return;
      setState(() {
        scannerY += 5;
        if (scannerY > 300) scannerY = 0;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 160 is roughly where the sticker is, 240 is where the plate is
    bool scanningSticker = addBumperSticker && (scannerY > 150 && scannerY < 180);
    bool scanningPlate = scannerY > 230 && scannerY < 260;
    
    bool falsePositive = scanningSticker;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: ClipRect(
              child: CustomPaint(
                painter: _NoPlateBFPainter(
                  scannerY: scannerY,
                  addBumperSticker: addBumperSticker,
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
                      Text("The Brute Force Way: Shape Guessing", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Older systems scanned the entire image looking for any rectangle with a 2.5 Width-to-Height ratio (the standard shape of a license plate).",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Expose the Flaw:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                      SizedBox(height: 8),
                      Text("Because it searches the whole car blindly, it gets confused by other rectangular shapes like grilles or stickers.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Switch(
                            value: addBumperSticker,
                            activeColor: Colors.orange,
                            onChanged: (val) => setState(() => addBumperSticker = val),
                          ),
                          Expanded(child: Text("Add Rectangular Bumper Sticker", style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
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
                  color: falsePositive ? Colors.red[100] : (scanningPlate ? Colors.green[100] : Colors.white),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: falsePositive ? Colors.red : (scanningPlate ? Colors.green : Colors.grey), width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      falsePositive 
                          ? "RESULT: FALSE POSITIVE!" 
                          : (scanningPlate ? "RESULT: PLATE FOUND" : "SCANNING..."),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: falsePositive ? Colors.red[900] : (scanningPlate ? Colors.green[900] : Colors.grey[800]), 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (falsePositive)
                      Text("System read the sticker as a plate!", style: TextStyle(color: Colors.red, fontSize: 12)),
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

class _NoPlateBFPainter extends CustomPainter {
  final double scannerY;
  final bool addBumperSticker;

  _NoPlateBFPainter({required this.scannerY, required this.addBumperSticker});

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

    // Sticker (The False Positive Trap)
    if (addBumperSticker) {
      Rect sticker = Rect.fromCenter(center: Offset(centerX, startY + 160), width: 80, height: 32); // Ratio 2.5
      Paint stickerPaint = Paint()..color = Colors.yellow[200]!;
      canvas.drawRect(sticker, stickerPaint);
      
      TextPainter tpSticker = TextPainter(
        text: TextSpan(text: "I <3 DOGS", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      tpSticker.layout();
      tpSticker.paint(canvas, Offset(sticker.center.dx - tpSticker.width/2, sticker.center.dy - tpSticker.height/2));
    }

    // Actual Plate
    Rect actualPlate = Rect.fromCenter(center: Offset(centerX, startY + 220), width: 75, height: 30); // Ratio 2.5
    Paint platePaint = Paint()..color = Colors.white;
    Paint plateBorder = Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2;
    canvas.drawRect(actualPlate, platePaint);
    canvas.drawRect(actualPlate, plateBorder);
    
    TextPainter tpPlate = TextPainter(
      text: TextSpan(text: "ABC-123", style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tpPlate.layout();
    tpPlate.paint(canvas, Offset(actualPlate.center.dx - tpPlate.width/2, actualPlate.center.dy - tpPlate.height/2));

    // Scanner Line
    double currentScanY = startY + scannerY - 20; // -20 offset to align
    Paint scanLine = Paint()..color = Colors.red..strokeWidth = 3;
    Paint scanArea = Paint()..color = Colors.red.withOpacity(0.2)..style = PaintingStyle.fill;
    
    canvas.drawLine(Offset(centerX - 100, currentScanY), Offset(centerX + 100, currentScanY), scanLine);
    canvas.drawRect(Rect.fromLTWH(centerX - 100, currentScanY - 30, 200, 30), scanArea);

    // Highlight what the scanner is looking at
    bool isSticker = addBumperSticker && (scannerY > 150 && scannerY < 180);
    bool isPlate = scannerY > 230 && scannerY < 260;

    if (isSticker || isPlate) {
      Paint detectBox = Paint()..color = isSticker ? Colors.red : Colors.green..strokeWidth = 4..style = PaintingStyle.stroke;
      Rect boxTarget = isSticker ? Rect.fromCenter(center: Offset(centerX, startY + 160), width: 80, height: 32) : actualPlate;
      canvas.drawRect(boxTarget.inflate(4), detectBox);
      
      TextPainter tpDet = TextPainter(
        text: TextSpan(
          text: isSticker ? "RECTANGLE FOUND\n(Ratio: 2.5)" : "RECTANGLE FOUND\n(Ratio: 2.5)", 
          style: TextStyle(color: isSticker ? Colors.red[900] : Colors.green[900], fontWeight: FontWeight.bold, backgroundColor: Colors.white)
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tpDet.layout();
      tpDet.paint(canvas, Offset(boxTarget.right + 10, boxTarget.center.dy - tpDet.height/2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
