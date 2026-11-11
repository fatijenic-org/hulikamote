import 'package:flutter/material.dart';
import 'dart:async';

class NoPlateSetup extends StatefulWidget {
  @override
  _NoPlateSetupState createState() => _NoPlateSetupState();
}

class _NoPlateSetupState extends State<NoPlateSetup> {
  int pipelineStage = 0; // 0: Idle, 1: Car Found, 2: Cropped, 3: OCR Extracted

  void _runPipeline() async {
    setState(() => pipelineStage = 0);
    await Future.delayed(Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => pipelineStage = 1);
    await Future.delayed(Duration(milliseconds: 1000));
    if (!mounted) return;
    setState(() => pipelineStage = 2);
    await Future.delayed(Duration(milliseconds: 1000));
    if (!mounted) return;
    setState(() => pipelineStage = 3);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: ClipRect(
              child: CustomPaint(
                painter: _NoPlateSetupPainter(
                  pipelineStage: pipelineStage,
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
                      Text("Real-World Setup: The 2-Stage Pipeline", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Instead of scanning the whole screen at once, modern systems use two models in sequence.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Run the AI Pipeline:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 16),
                      Center(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[900],
                            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16)
                          ),
                          onPressed: pipelineStage == 0 || pipelineStage == 3 ? _runPipeline : null,
                          child: Text("RUN PIPELINE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      SizedBox(height: 32),
                      
                      _buildStageTile("Stage 1: YOLO Vehicle", 1, pipelineStage >= 1),
                      _buildStageTile("Stage 2: Crop Space", 2, pipelineStage >= 2),
                      _buildStageTile("Stage 3: OCR Extraction", 3, pipelineStage >= 3),
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
                  color: pipelineStage == 3 ? Colors.green[100] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: pipelineStage == 3 ? Colors.green : Colors.grey, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      pipelineStage == 3 
                          ? "RESULT: PLATE LOGGED" 
                          : "WAITING...",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: pipelineStage == 3 ? Colors.green[900] : Colors.grey[800], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (pipelineStage == 3)
                      Text("DB Entry: ABC-123", style: TextStyle(color: Colors.green[900], fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildStageTile(String title, int stage, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isActive ? Colors.green : Colors.grey,
          ),
          SizedBox(width: 12),
          Text(title, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.black : Colors.grey)),
        ],
      ),
    );
  }
}

class _NoPlateSetupPainter extends CustomPainter {
  final int pipelineStage;

  _NoPlateSetupPainter({required this.pipelineStage});

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
    
    if (pipelineStage >= 2) {
      carPaint.color = Colors.grey[300]!; // fade out the top part in stage 2
    }
    canvas.drawRRect(RRect.fromRectAndRadius(carBody, Radius.circular(10)), carPaint);
    
    // Rear Window
    Rect window = Rect.fromCenter(center: Offset(centerX, startY + 80), width: 100, height: 40);
    Paint glassPaint = Paint()..color = pipelineStage >= 2 ? Colors.grey[400]! : Colors.lightBlueAccent;
    canvas.drawRect(window, glassPaint);

    // Actual Plate
    Rect actualPlate = Rect.fromCenter(center: Offset(centerX, startY + 220), width: 75, height: 30);
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

    // Pipeline Overlays
    if (pipelineStage >= 1) {
      // Stage 1: YOLO Vehicle Box
      Paint vehicleBox = Paint()..color = pipelineStage >= 2 ? Colors.grey : Colors.cyan..strokeWidth = 3..style = PaintingStyle.stroke;
      canvas.drawRect(carBody.inflate(5), vehicleBox);
      
      if (pipelineStage == 1) {
        TextPainter tpYolo = TextPainter(
          text: TextSpan(text: "YOLO: Vehicle (98%)", style: TextStyle(color: Colors.cyan[900], fontWeight: FontWeight.bold, backgroundColor: Colors.white)),
          textDirection: TextDirection.ltr,
        );
        tpYolo.layout();
        tpYolo.paint(canvas, Offset(carBody.left, carBody.top - 20));
      }
    }

    if (pipelineStage >= 2) {
      // Stage 2: Crop Region
      Rect cropRect = Rect.fromLTWH(carBody.left, carBody.top + (carBody.height * 0.6), carBody.width, carBody.height * 0.4);
      Paint cropBox = Paint()..color = Colors.orange..strokeWidth = 4..style = PaintingStyle.stroke;
      canvas.drawRect(cropRect.inflate(2), cropBox);
      
      // Draw car lower part back in full color
      canvas.save();
      canvas.clipRect(cropRect);
      canvas.drawRRect(RRect.fromRectAndRadius(carBody, Radius.circular(10)), Paint()..color = Colors.blueGrey);
      canvas.drawRect(actualPlate, platePaint);
      canvas.drawRect(actualPlate, plateBorder);
      tpPlate.paint(canvas, Offset(actualPlate.center.dx - tpPlate.width/2, actualPlate.center.dy - tpPlate.height/2));
      canvas.restore();

      if (pipelineStage == 2) {
        TextPainter tpCrop = TextPainter(
          text: TextSpan(text: "CROP: Bottom 40%", style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.bold, backgroundColor: Colors.white)),
          textDirection: TextDirection.ltr,
        );
        tpCrop.layout();
        tpCrop.paint(canvas, Offset(cropRect.right + 10, cropRect.center.dy - tpCrop.height/2));
      }
    }

    if (pipelineStage == 3) {
      // Stage 3: OCR
      Paint ocrBox = Paint()..color = Colors.greenAccent..strokeWidth = 3..style = PaintingStyle.stroke;
      canvas.drawRect(actualPlate.inflate(6), ocrBox);
      
      TextPainter tpOcr = TextPainter(
        text: TextSpan(text: "OCR EXTRACT: 'ABC-123'", style: TextStyle(color: Colors.green[900], fontWeight: FontWeight.bold, backgroundColor: Colors.white, fontSize: 16)),
        textDirection: TextDirection.ltr,
      );
      tpOcr.layout();
      tpOcr.paint(canvas, Offset(actualPlate.right + 20, actualPlate.center.dy - tpOcr.height/2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
