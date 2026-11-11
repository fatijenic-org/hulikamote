import 'package:flutter/material.dart';
import 'dart:math' as math;

class NoHelmetFirstPrinciple extends StatefulWidget {
  @override
  _NoHelmetFirstPrincipleState createState() => _NoHelmetFirstPrincipleState();
}

class _NoHelmetFirstPrincipleState extends State<NoHelmetFirstPrinciple> {
  int activeTab = 0; // 0: Crop Concept, 1: 2-Stage Cascade Architecture

  // Tab 1: Crop State
  double cropPercentage = 100.0;

  // Tab 2: Cascade Pipeline Stepper State
  int cascadeStage = 0; // 0: Raw Frame, 1: YOLO Rider Detection, 2: Head Sub-Crop, 3: ResNet Binary Classifier

  @override
  Widget build(BuildContext context) {
    bool isOptimized = cropPercentage <= 30.0;

    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[850],
            child: ClipRect(
              child: CustomPaint(
                painter: _NoHelmetFPPainter(
                  activeTab: activeTab,
                  cropPercentage: cropPercentage,
                  cascadeStage: cascadeStage,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        // CONTROLS AREA
        Container(
          width: 380,
          color: Colors.blueGrey[50],
          child: Column(
            children: [
              // Tab Selector
              Container(
                margin: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _buildTabButton("1. Crop Concept", 0),
                    _buildTabButton("2. 2-Stage Cascade", 1),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  child: activeTab == 0 ? _buildCropControls(isOptimized) : _buildCascadeControls(),
                ),
              ),

              // Bottom Decision Box
              Divider(height: 1),
              Container(
                padding: EdgeInsets.all(16),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: activeTab == 0
                      ? (isOptimized ? Colors.green[100] : Colors.orange[100])
                      : (cascadeStage == 3 ? Colors.red[100] : Colors.blue[100]),
                ),
                child: Column(
                  children: [
                    Text(
                      activeTab == 0 ? "Search Space Status:" : "Pipeline Output:",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[800]),
                    ),
                    SizedBox(height: 4),
                    Text(
                      activeTab == 0
                          ? (isOptimized ? "OPTIMIZED (Targeted Head Slice)" : "TOO MUCH NOISE (Scanning Torso & Bike)")
                          : _getCascadeStatusText(cascadeStage),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: activeTab == 0
                            ? (isOptimized ? Colors.green[900] : Colors.orange[900])
                            : (cascadeStage == 3 ? Colors.red[900] : Colors.blue[900]),
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

  Widget _buildTabButton(String label, int index) {
    bool isSelected = activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => activeTab = index),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blueGrey[900] : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCropControls(bool isOptimized) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Core Concept: Head Region Isolation", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        SizedBox(height: 12),
        Text(
          "We never feed the whole motorcycle or jacket to the classifier. By slicing the top 25% of the bounding box, we eliminate 75% of background noise.",
          style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.3),
        ),
        Divider(height: 24),

        Text("Adjust Crop Percentage:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
        SizedBox(height: 6),
        Text("Slide to adjust the search window from the bottom up:", style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        SizedBox(height: 12),

        Slider(
          value: cropPercentage,
          min: 20.0,
          max: 100.0,
          activeColor: isOptimized ? Colors.green : Colors.orange,
          onChanged: (val) => setState(() => cropPercentage = val),
        ),
        Center(
          child: Text(
            "Scanning top ${cropPercentage.toStringAsFixed(0)}% of rider",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isOptimized ? Colors.green[900] : Colors.orange[900]),
          ),
        ),
        SizedBox(height: 16),

        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Why Top 25% Crop Matters:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              SizedBox(height: 6),
              Text("• Prevents jackets, backpacks & side mirrors from confusing the model.", style: TextStyle(fontSize: 12)),
              Text("• Standardizes image dimensions for the downstream CNN.", style: TextStyle(fontSize: 12)),
              Text("• 4x faster inference speed on edge devices.", style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCascadeControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("2-Stage Cascade Architecture", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        SizedBox(height: 10),
        Text(
          "A single neural network cannot do everything. Production systems decouple detection (where is the rider?) from classification (wearing helmet?).",
          style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.3),
        ),
        Divider(height: 20),

        _buildStageRadio(0, "1. Camera Input", "Raw 1080p frame with complex traffic background"),
        _buildStageRadio(1, "2. Stage 1: YOLOv8 Detector", "Fast bounding box localization of rider & motorcycle"),
        _buildStageRadio(2, "3. Dynamic Head Slicing", "Mathematical ROI extraction: [y_min : y_min + 0.25*h]"),
        _buildStageRadio(3, "4. Stage 2: ResNet Classifier", "High-precision binary output: P(helmet) = 0.12 -> Violation"),
      ],
    );
  }

  Widget _buildStageRadio(int stage, String title, String subtitle) {
    bool isSelected = cascadeStage == stage;
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue[50] : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isSelected ? Colors.blueAccent : Colors.grey[300]!),
      ),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? Colors.blue[900] : Colors.black87)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        leading: Radio<int>(
          value: stage,
          groupValue: cascadeStage,
          activeColor: Colors.blueAccent,
          onChanged: (val) => setState(() => cascadeStage = val!),
        ),
        onTap: () => setState(() => cascadeStage = stage),
      ),
    );
  }

  String _getCascadeStatusText(int stage) {
    switch (stage) {
      case 0:
        return "Camera Feed Ingested (No Models Executing)";
      case 1:
        return "YOLOv8: Localized 'motorcyclist' bounding box";
      case 2:
        return "ROI Crop: Extracted 64x64 Head Patch";
      case 3:
        return "ResNet50: P(helmet) = 0.12 -> NO HELMET VIOLATION";
      default:
        return "";
    }
  }
}

class _NoHelmetFPPainter extends CustomPainter {
  final int activeTab;
  final double cropPercentage;
  final int cascadeStage;

  _NoHelmetFPPainter({
    required this.activeTab,
    required this.cropPercentage,
    required this.cascadeStage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Offset center = Offset(size.width * 0.45, size.height * 0.5);

    if (activeTab == 0) {
      _paintCropConcept(canvas, size, center);
    } else {
      _paintCascadeArchitecture(canvas, size, center);
    }
  }

  void _paintCropConcept(Canvas canvas, Size size, Offset center) {
    // Rider & Motorcycle schematic
    _drawMotorcyclist(canvas, center);

    // Full Rider Box
    double boxW = 100;
    double boxH = 180;
    Rect fullBox = Rect.fromCenter(center: Offset(center.dx, center.dy + 10), width: boxW, height: boxH);

    // Active scan box based on slider percentage
    double activeH = boxH * (cropPercentage / 100.0);
    Rect activeScanBox = Rect.fromLTWH(fullBox.left, fullBox.top, boxW, activeH);

    bool isOptimized = cropPercentage <= 30.0;

    // Dimmed unselected area
    Paint dimPaint = Paint()..color = Colors.black45..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(fullBox.left, fullBox.top + activeH, boxW, boxH - activeH), dimPaint);

    // Bounding box border
    Paint scanBorder = Paint()
      ..color = isOptimized ? Colors.greenAccent : Colors.orangeAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(activeScanBox, scanBorder);

    // Crop Label
    TextPainter tp = TextPainter(
      text: TextSpan(
        text: "Active Scan: ${cropPercentage.toStringAsFixed(0)}% Height\n${isOptimized ? 'Targeting Head Region' : 'Scanning Full Body'}",
        style: TextStyle(color: isOptimized ? Colors.greenAccent : Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 11, backgroundColor: Colors.black87),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    tp.layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, fullBox.bottom + 15));
  }

  void _paintCascadeArchitecture(Canvas canvas, Size size, Offset center) {
    // Draw motorcyclist
    _drawMotorcyclist(canvas, center);

    double boxW = 100;
    double boxH = 180;
    Rect riderBox = Rect.fromCenter(center: Offset(center.dx, center.dy + 10), width: boxW, height: boxH);
    Rect headBox = Rect.fromLTWH(riderBox.left, riderBox.top, boxW, 45);

    // Stage 1: YOLO Bounding Box
    if (cascadeStage >= 1) {
      Paint yoloPaint = Paint()..color = Colors.blueAccent..strokeWidth = 2..style = PaintingStyle.stroke;
      canvas.drawRect(riderBox, yoloPaint);

      TextPainter tpYolo = TextPainter(
        text: TextSpan(text: "Stage 1: YOLOv8 [motorcyclist 0.95]", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10, backgroundColor: Colors.blueAccent)),
        textDirection: TextDirection.ltr,
      );
      tpYolo.layout();
      tpYolo.paint(canvas, Offset(riderBox.left, riderBox.top - 16));
    }

    // Stage 2: Head Sub-Crop
    if (cascadeStage >= 2) {
      Paint headPaint = Paint()..color = Colors.yellowAccent..strokeWidth = 2.5..style = PaintingStyle.stroke;
      canvas.drawRect(headBox, headPaint);

      // Slicing bracket indicator
      TextPainter tpH = TextPainter(
        text: TextSpan(text: "Stage 2: Head Crop ROI [y : y + 0.25h]", style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 10, backgroundColor: Colors.black87)),
        textDirection: TextDirection.ltr,
      );
      tpH.layout();
      tpH.paint(canvas, Offset(headBox.right + 8, headBox.top + 12));
    }

    // Stage 3: ResNet Binary Classifier
    if (cascadeStage >= 3) {
      Offset cnnCenter = Offset(center.dx + 160, center.dy - 30);
      Paint cnnBox = Paint()..color = Colors.redAccent.withOpacity(0.2)..style = PaintingStyle.fill;
      Paint cnnBorder = Paint()..color = Colors.redAccent..strokeWidth = 2..style = PaintingStyle.stroke;
      Rect cnnRect = Rect.fromCenter(center: cnnCenter, width: 130, height: 90);
      canvas.drawRRect(RRect.fromRectAndRadius(cnnRect, Radius.circular(8)), cnnBox);
      canvas.drawRRect(RRect.fromRectAndRadius(cnnRect, Radius.circular(8)), cnnBorder);

      // Connecting arrow from head crop to CNN
      Paint arrowPaint = Paint()..color = Colors.yellowAccent..strokeWidth = 2;
      _drawArrow(canvas, Offset(headBox.right, headBox.center.dy), Offset(cnnRect.left, cnnRect.center.dy), arrowPaint);

      TextPainter tpCNN = TextPainter(
        text: TextSpan(
          text: "Stage 3: ResNet-50\nP(helmet) = 0.12\nP(no_helmet) = 0.88\nVIOLATION",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tpCNN.layout();
      tpCNN.paint(canvas, Offset(cnnCenter.dx - tpCNN.width / 2, cnnCenter.dy - tpCNN.height / 2));
    }
  }

  void _drawMotorcyclist(Canvas canvas, Offset center) {
    // Head (Hair / No helmet)
    Paint headPaint = Paint()..color = Colors.orange[200]!;
    canvas.drawCircle(Offset(center.dx, center.dy - 60), 16, headPaint);

    // Black Hair
    Paint hairPaint = Paint()..color = Colors.black87;
    canvas.drawArc(Rect.fromCircle(center: Offset(center.dx, center.dy - 64), radius: 17), math.pi, math.pi, true, hairPaint);

    // Jacket / Torso
    Paint torsoPaint = Paint()..color = Colors.blueGrey[800]!;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx, center.dy - 20), width: 50, height: 50), Radius.circular(8)), torsoPaint);

    // Motorcycle Body
    Paint bikePaint = Paint()..color = Colors.red[800]!;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx, center.dy + 35), width: 85, height: 35), Radius.circular(6)), bikePaint);

    // Wheels
    Paint wheelPaint = Paint()..color = Colors.black87;
    canvas.drawCircle(Offset(center.dx - 35, center.dy + 65), 18, wheelPaint);
    canvas.drawCircle(Offset(center.dx + 35, center.dy + 65), 18, wheelPaint);
    canvas.drawCircle(Offset(center.dx - 35, center.dy + 65), 7, Paint()..color = Colors.grey[400]!);
    canvas.drawCircle(Offset(center.dx + 35, center.dy + 65), 7, Paint()..color = Colors.grey[400]!);
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    double dX = end.dx - start.dx;
    double dY = end.dy - start.dy;
    double a = math.atan2(dY, dX);
    double arrowLength = 10;
    Offset p1 = Offset(end.dx - arrowLength * math.cos(a - math.pi / 6), end.dy - arrowLength * math.sin(a - math.pi / 6));
    Offset p2 = Offset(end.dx - arrowLength * math.cos(a + math.pi / 6), end.dy - arrowLength * math.sin(a + math.pi / 6));
    canvas.drawLine(end, p1, paint);
    canvas.drawLine(end, p2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
