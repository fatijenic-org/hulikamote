import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';

class StaticCropVisualizer extends StatefulWidget {
  @override
  _StaticCropVisualizerState createState() => _StaticCropVisualizerState();
}

enum VehicleCase {
  sedanValid,       // Normal car with valid plate
  suvMissingPlate,  // Violation: Missing front plate
  motorcycleNoPlate,// Violation: Motorcycle without rear plate
  vanCustomValid,   // Delivery van with valid plate
}

class _StaticCropVisualizerState extends State<StaticCropVisualizer> {
  VehicleCase currentCase = VehicleCase.suvMissingPlate; // Default to violation to highlight logic

  int activeStage = 4; // 0: Raw Frame, 1: YOLO Detection, 2: Bumper Crop, 3: Plate Presence, 4: ANPR OCR & Verification
  bool isLiveAutoScan = true;
  Timer? _animTimer;
  double carProgress = 0.0; // 0.0 to 1.0 driving progress across screen

  // Filter mode for plate zoom preview
  int filterMode = 0; // 0: Raw RGB, 1: Grayscale & Contrast, 2: Binary / Otsu

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  void _startAnimation() {
    _animTimer?.cancel();
    _animTimer = Timer.periodic(Duration(milliseconds: 33), (timer) {
      if (!mounted) return;
      if (isLiveAutoScan) {
        setState(() {
          carProgress += 0.006;
          if (carProgress > 1.0) {
            carProgress = 0.0;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    super.dispose();
  }

  void _selectCase(VehicleCase c) {
    setState(() {
      currentCase = c;
      carProgress = 0.45; // Center car on screen for immediate inspection
    });
  }

  bool _isMissingPlate() {
    return currentCase == VehicleCase.suvMissingPlate || currentCase == VehicleCase.motorcycleNoPlate;
  }

  String _getPlateNumber() {
    switch (currentCase) {
      case VehicleCase.sedanValid:
        return "ABC 1234";
      case VehicleCase.suvMissingPlate:
        return "[NO PLATE DETECTED]";
      case VehicleCase.motorcycleNoPlate:
        return "[MISSING / COVERED]";
      case VehicleCase.vanCustomValid:
        return "NFD 7890";
    }
  }

  double _getPlateConfidence() {
    switch (currentCase) {
      case VehicleCase.sedanValid:
        return 0.96;
      case VehicleCase.suvMissingPlate:
        return 0.08;
      case VehicleCase.motorcycleNoPlate:
        return 0.14;
      case VehicleCase.vanCustomValid:
        return 0.92;
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isViolation = _isMissingPlate();
    String plateText = _getPlateNumber();
    double plateConf = _getPlateConfidence();

    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[850],
            child: ClipRect(
              child: CustomPaint(
                painter: _NoPlatePipelinePainter(
                  vehicleCase: currentCase,
                  activeStage: activeStage,
                  carProgress: carProgress,
                  plateText: plateText,
                  plateConf: plateConf,
                  isViolation: isViolation,
                  filterMode: filterMode,
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
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Modern AI: End-to-End ANPR & Plate Verification", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      SizedBox(height: 8),
                      Text(
                        "Inspect the full automated pipeline: YOLO vehicle localization -> Sub-Crop bumper ROI -> Plate Presence Verification -> ANPR Character Recognition.",
                        style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.3),
                      ),
                      Divider(height: 20),

                      Text("1. Select Test Vehicle:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                      SizedBox(height: 6),

                      RadioListTile<VehicleCase>(
                        dense: true,
                        title: Text("🚗 Sedan (Standard Plate: ABC 1234)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        subtitle: Text("Plate present & verified -> Compliant", style: TextStyle(fontSize: 11)),
                        value: VehicleCase.sedanValid,
                        groupValue: currentCase,
                        onChanged: (val) => _selectCase(val!),
                      ),
                      RadioListTile<VehicleCase>(
                        dense: true,
                        title: Text("🚙 SUV (Missing Front Plate - VIOLATION)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red[900])),
                        subtitle: Text("Bumper scan empty (P=0.08) -> Flags No Plate", style: TextStyle(fontSize: 11)),
                        value: VehicleCase.suvMissingPlate,
                        groupValue: currentCase,
                        onChanged: (val) => _selectCase(val!),
                      ),
                      RadioListTile<VehicleCase>(
                        dense: true,
                        title: Text("🏍️ Motorcycle (No Rear Plate - VIOLATION)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red[900])),
                        subtitle: Text("Fender scan fails (P=0.14) -> Flags No Plate", style: TextStyle(fontSize: 11)),
                        value: VehicleCase.motorcycleNoPlate,
                        groupValue: currentCase,
                        onChanged: (val) => _selectCase(val!),
                      ),
                      RadioListTile<VehicleCase>(
                        dense: true,
                        title: Text("🚚 Delivery Van (Plate: NFD 7890)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        subtitle: Text("Commercial plate read & verified -> Compliant", style: TextStyle(fontSize: 11)),
                        value: VehicleCase.vanCustomValid,
                        groupValue: currentCase,
                        onChanged: (val) => _selectCase(val!),
                      ),

                      Divider(height: 18),
                      Text("2. Inspect Pipeline Stage:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _buildStageButton("1. YOLO Vehicle", 1),
                          _buildStageButton("2. Bumper Crop", 2),
                          _buildStageButton("3. Plate Verify", 3),
                          _buildStageButton("4. ANPR OCR", 4),
                        ],
                      ),

                      Divider(height: 18),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800], padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                            icon: Icon(isLiveAutoScan ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 16),
                            label: Text(isLiveAutoScan ? "Pause" : "Live Auto-Scan", style: TextStyle(color: Colors.white, fontSize: 11)),
                            onPressed: () => setState(() => isLiveAutoScan = !isLiveAutoScan),
                          ),
                          SizedBox(width: 8),
                          Text("Filter Preview:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          SizedBox(width: 4),
                          DropdownButton<int>(
                            value: filterMode,
                            isDense: true,
                            underline: SizedBox(),
                            items: [
                              DropdownMenuItem(value: 0, child: Text("RGB", style: TextStyle(fontSize: 11))),
                              DropdownMenuItem(value: 1, child: Text("Grayscale", style: TextStyle(fontSize: 11))),
                              DropdownMenuItem(value: 2, child: Text("Otsu Binary", style: TextStyle(fontSize: 11))),
                            ],
                            onChanged: (val) => setState(() => filterMode = val!),
                          )
                        ],
                      ),

                      Divider(height: 18),
                      Text("ANPR Telemetry & Evidence:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text("YOLO Bounding Box: [x: 320, y: 140, w: 180, h: 110]"),
                      Text("Bumper Slice ROI: Lower 30% [y_min + 0.70h]"),
                      Text(
                        "Plate Presence Score: ${(plateConf * 100).toStringAsFixed(1)}% (Threshold: 50.0%)",
                        style: TextStyle(fontWeight: FontWeight.bold, color: isViolation ? Colors.red[900] : Colors.green[900]),
                      ),
                      Text("OCR Alphanumeric Output: $plateText", style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              Divider(height: 1),
              Container(
                padding: EdgeInsets.all(16),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isViolation ? Colors.red[100] : Colors.green[100],
                ),
                child: Column(
                  children: [
                    Text("AI Violation Enforcement Decision:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[800])),
                    SizedBox(height: 4),
                    Text(
                      isViolation 
                          ? "NO LICENSE PLATE VIOLATION!\n(Plate Presence Score < 50% -> Citation Docket Created)" 
                          : "VALID LICENSE PLATE ($plateText)\nVerified in LTO Database",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isViolation ? Colors.red[900] : Colors.green[900],
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

  Widget _buildStageButton(String label, int stage) {
    bool isSelected = activeStage == stage;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blueAccent : Colors.grey[300],
        foregroundColor: isSelected ? Colors.white : Colors.black87,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size(80, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => setState(() => activeStage = stage),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

class _NoPlatePipelinePainter extends CustomPainter {
  final VehicleCase vehicleCase;
  final int activeStage;
  final double carProgress;
  final String plateText;
  final double plateConf;
  final bool isViolation;
  final int filterMode;

  _NoPlatePipelinePainter({
    required this.vehicleCase,
    required this.activeStage,
    required this.carProgress,
    required this.plateText,
    required this.plateConf,
    required this.isViolation,
    required this.filterMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Road Background
    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    // Sidewalk curb
    Paint curbPaint = Paint()..color = Colors.grey[400]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 30, size.width, 30), curbPaint);

    // Lane divider
    Paint laneLine = Paint()..color = Colors.white70..strokeWidth = 3..style = PaintingStyle.stroke;
    double dashX = 0;
    while (dashX < size.width) {
      canvas.drawLine(Offset(dashX, 240), Offset(dashX + 25, 240), laneLine);
      dashX += 50;
    }

    // 2. Draw Moving Vehicle
    double posX = -100 + carProgress * (size.width + 200);
    Offset carPos = Offset(posX, 150);

    bool isMotorcycle = vehicleCase == VehicleCase.motorcycleNoPlate;
    double boxW = isMotorcycle ? 65 : 140;
    double boxH = isMotorcycle ? 110 : 85;

    Rect vehicleBox = Rect.fromCenter(center: carPos, width: boxW, height: boxH);

    _drawVehicleGraphic(canvas, carPos, vehicleCase);

    // 3. Stage 1: YOLO Bounding Box
    if (activeStage >= 1) {
      Paint yoloPaint = Paint()
        ..color = isViolation ? Colors.redAccent : Colors.greenAccent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawRect(vehicleBox.inflate(4), yoloPaint);

      TextPainter tpYolo = TextPainter(
        text: TextSpan(
          text: "YOLOv8: ${isMotorcycle ? 'motorcycle 0.94' : 'car 0.97'}",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10, backgroundColor: isViolation ? Colors.redAccent : Colors.greenAccent),
        ),
        textDirection: TextDirection.ltr,
      );
      tpYolo.layout();
      tpYolo.paint(canvas, Offset(vehicleBox.left - 4, vehicleBox.top - 18));
    }

    // 4. Stage 2: Bumper Slicing Sub-Crop ROI
    Rect bumperCrop = Rect.fromLTWH(
      vehicleBox.left,
      vehicleBox.top + boxH * 0.65,
      boxW,
      boxH * 0.35,
    );

    if (activeStage >= 2) {
      Paint cropPaint = Paint()
        ..color = Colors.yellowAccent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawRect(bumperCrop, cropPaint);

      TextPainter tpCrop = TextPainter(
        text: TextSpan(
          text: "Sub-Crop ROI [Lower 30%]",
          style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 9, backgroundColor: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
      );
      tpCrop.layout();
      tpCrop.paint(canvas, Offset(bumperCrop.left, bumperCrop.bottom + 4));
    }

    // 5. Stage 3 & 4: License Plate Zoom Window & OCR Overlay (Bottom Right Canvas)
    if (activeStage >= 3) {
      _drawPlateZoomWindow(canvas, size, bumperCrop);
    }
  }

  void _drawVehicleGraphic(Canvas canvas, Offset pos, VehicleCase vCase) {
    switch (vCase) {
      case VehicleCase.sedanValid:
        // Sedan car
        Paint carPaint = Paint()..color = Colors.blueAccent;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: pos, width: 130, height: 75), Radius.circular(8)), carPaint);
        // Roof
        Paint roofPaint = Paint()..color = Colors.lightBlue[100]!;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(pos.dx, pos.dy - 8), width: 65, height: 40), Radius.circular(5)), roofPaint);
        // Front Plate (White rectangle with black border)
        Paint platePaint = Paint()..color = Colors.white;
        Rect pRect = Rect.fromCenter(center: Offset(pos.dx, pos.dy + 26), width: 44, height: 16);
        canvas.drawRect(pRect, platePaint);
        canvas.drawRect(pRect, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1);
        TextPainter tp = TextPainter(text: TextSpan(text: "ABC 1234", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 7)), textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, Offset(pRect.center.dx - tp.width / 2, pRect.center.dy - tp.height / 2));
        break;

      case VehicleCase.suvMissingPlate:
        // SUV car (Missing Plate on bumper)
        Paint carPaint = Paint()..color = Colors.blueGrey[800]!;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: pos, width: 140, height: 85), Radius.circular(8)), carPaint);
        // Roof
        Paint roofPaint = Paint()..color = Colors.white70;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(pos.dx, pos.dy - 10), width: 75, height: 48), Radius.circular(5)), roofPaint);
        // Empty bumper indentation with warning dashed box
        Paint emptyPaint = Paint()..color = Colors.red.withOpacity(0.3)..style = PaintingStyle.fill;
        Rect pRectEmpty = Rect.fromCenter(center: Offset(pos.dx, pos.dy + 30), width: 48, height: 16);
        canvas.drawRect(pRectEmpty, emptyPaint);
        canvas.drawRect(pRectEmpty, Paint()..color = Colors.redAccent..style = PaintingStyle.stroke..strokeWidth = 1.5);
        TextPainter tpNo = TextPainter(text: TextSpan(text: "NO PLATE", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 7)), textDirection: TextDirection.ltr);
        tpNo.layout();
        tpNo.paint(canvas, Offset(pRectEmpty.center.dx - tpNo.width / 2, pRectEmpty.center.dy - tpNo.height / 2));
        break;

      case VehicleCase.motorcycleNoPlate:
        // Motorcycle
        Paint bikePaint = Paint()..color = Colors.red[800]!;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(pos.dx, pos.dy + 15), width: 60, height: 35), Radius.circular(5)), bikePaint);
        // Rider
        Paint riderPaint = Paint()..color = Colors.blueGrey[700]!;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(pos.dx, pos.dy - 18), width: 38, height: 40), Radius.circular(6)), riderPaint);
        // Helmet
        canvas.drawCircle(Offset(pos.dx, pos.dy - 46), 14, Paint()..color = Colors.amber);
        // Empty rear fender
        Paint emptyFender = Paint()..color = Colors.red.withOpacity(0.4)..style = PaintingStyle.fill;
        Rect fRect = Rect.fromCenter(center: Offset(pos.dx, pos.dy + 38), width: 30, height: 14);
        canvas.drawRect(fRect, emptyFender);
        canvas.drawRect(fRect, Paint()..color = Colors.redAccent..style = PaintingStyle.stroke..strokeWidth = 1);
        break;

      case VehicleCase.vanCustomValid:
        // Delivery Van
        Paint vanPaint = Paint()..color = Colors.white;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: pos, width: 145, height: 90), Radius.circular(6)), vanPaint);
        // Windows
        canvas.drawRect(Rect.fromLTWH(pos.dx - 65, pos.dy - 35, 35, 30), Paint()..color = Colors.blueGrey[900]!);
        // Plate
        Paint platePaint = Paint()..color = Colors.amberAccent;
        Rect pRect = Rect.fromCenter(center: Offset(pos.dx, pos.dy + 32), width: 46, height: 16);
        canvas.drawRect(pRect, platePaint);
        canvas.drawRect(pRect, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1);
        TextPainter tp = TextPainter(text: TextSpan(text: "NFD 7890", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 7)), textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, Offset(pRect.center.dx - tp.width / 2, pRect.center.dy - tp.height / 2));
        break;
    }
  }

  void _drawPlateZoomWindow(Canvas canvas, Size size, Rect sourceCrop) {
    double boxW = 280;
    double boxH = 135;
    double boxX = size.width - boxW - 20;
    double boxY = size.height - boxH - 20;

    Rect zoomRect = Rect.fromLTWH(boxX, boxY, boxW, boxH);

    // Zoom Window Background
    Paint zoomBg = Paint()..color = Colors.black87..style = PaintingStyle.fill;
    Paint zoomBorder = Paint()
      ..color = isViolation ? Colors.redAccent : Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(RRect.fromRectAndRadius(zoomRect, Radius.circular(8)), zoomBg);
    canvas.drawRRect(RRect.fromRectAndRadius(zoomRect, Radius.circular(8)), zoomBorder);

    // Header Title
    TextPainter tpHead = TextPainter(
      text: TextSpan(
        text: "ANPR / OCR CROP EVIDENCE INSPECTOR (4x ZOOM):",
        style: TextStyle(color: isViolation ? Colors.redAccent : Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    );
    tpHead.layout();
    tpHead.paint(canvas, Offset(boxX + 12, boxY + 10));

    // Simulated Cropped Plate Region
    Rect plateCard = Rect.fromLTWH(boxX + 15, boxY + 32, 130, 60);

    Color filterBgColor;
    if (filterMode == 0) {
      filterBgColor = isViolation ? Colors.blueGrey[900]! : (vehicleCase == VehicleCase.vanCustomValid ? Colors.amber[200]! : Colors.white);
    } else if (filterMode == 1) {
      filterBgColor = isViolation ? Colors.grey[800]! : Colors.grey[300]!;
    } else {
      filterBgColor = isViolation ? Colors.black : Colors.white;
    }

    Paint plateBgPaint = Paint()..color = filterBgColor..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(plateCard, Radius.circular(4)), plateBgPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(plateCard, Radius.circular(4)), Paint()..color = Colors.white30..style = PaintingStyle.stroke..strokeWidth = 1);

    if (isViolation) {
      // Empty bumper / missing plate
      TextPainter tpMiss = TextPainter(
        text: TextSpan(
          text: "NO PLATE\nFOUND IN ROI\nP = ${(plateConf * 100).toStringAsFixed(0)}%",
          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tpMiss.layout();
      tpMiss.paint(canvas, Offset(plateCard.center.dx - tpMiss.width / 2, plateCard.center.dy - tpMiss.height / 2));
    } else {
      // Valid Plate Text in OCR font
      TextPainter tpChars = TextPainter(
        text: TextSpan(
          text: plateText,
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 2, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      );
      tpChars.layout();
      tpChars.paint(canvas, Offset(plateCard.center.dx - tpChars.width / 2, plateCard.center.dy - tpChars.height / 2 - 4));

      TextPainter tpSub = TextPainter(
        text: TextSpan(text: "PILIPINAS", style: TextStyle(color: Colors.blue[900], fontWeight: FontWeight.bold, fontSize: 7, letterSpacing: 3)),
        textDirection: TextDirection.ltr,
      );
      tpSub.layout();
      tpSub.paint(canvas, Offset(plateCard.center.dx - tpSub.width / 2, plateCard.bottom - 14));
    }

    // Telemetry text on right of zoom box
    double textX = boxX + 155;
    double textY = boxY + 34;

    _drawTelemetryLine(canvas, "Plate Conf:", "${(plateConf * 100).toStringAsFixed(1)}%", textX, textY, isViolation ? Colors.redAccent : Colors.greenAccent);
    _drawTelemetryLine(canvas, "OCR Result:", isViolation ? "FAILED" : plateText, textX, textY + 18, Colors.white);
    _drawTelemetryLine(canvas, "LTO Query:", isViolation ? "UNKNOWN / CITATION" : "REGISTERED", textX, textY + 36, isViolation ? Colors.redAccent : Colors.greenAccent);

    // Status Banner
    TextPainter tpStatus = TextPainter(
      text: TextSpan(
        text: isViolation ? "STATUS: 🔴 CITATION ISSUED (NO PLATE)" : "STATUS: 🟢 VERIFIED & COMPLIANT",
        style: TextStyle(color: isViolation ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    );
    tpStatus.layout();
    tpStatus.paint(canvas, Offset(boxX + 12, boxY + boxH - 24));
  }

  void _drawTelemetryLine(Canvas canvas, String label, String value, double x, double y, Color valColor) {
    TextPainter tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: "$label ", style: TextStyle(color: Colors.grey[400], fontSize: 10)),
          TextSpan(text: value, style: TextStyle(color: valColor, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
