import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';

class NoHelmetSetup extends StatefulWidget {
  @override
  _NoHelmetSetupState createState() => _NoHelmetSetupState();
}

enum HelmetScenario { noHelmet, wearsHelmet, transientGlare }

class _NoHelmetSetupState extends State<NoHelmetSetup> {
  HelmetScenario scenario = HelmetScenario.noHelmet;

  double bikeX = 80.0;
  bool isPlaying = true;
  Timer? _timer;

  // Multi-frame Temporal Buffer (Last 10 frames of head crop classification)
  List<double> frameScores = []; // P(helmet) per frame [0.0 - 1.0]
  final int maxBufferFrames = 10;
  final double violationThreshold = 0.35; // If avg P(helmet) < 0.35 -> Violation

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  void _startAnimation() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: 60), (timer) {
      if (!mounted) return;
      if (isPlaying) {
        setState(() {
          bikeX += 5.0;
          if (bikeX > 850) {
            bikeX = -50.0;
            frameScores.clear();
          }

          // Generate frame classification score based on scenario & noise
          double score = _generateFrameScore();
          frameScores.add(score);
          if (frameScores.length > maxBufferFrames) {
            frameScores.removeAt(0); // Sliding window
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double _generateFrameScore() {
    double noise = (math.Random().nextDouble() - 0.5) * 0.08;
    switch (scenario) {
      case HelmetScenario.noHelmet:
        // Consistently low helmet probability (bare head)
        return (0.10 + noise).clamp(0.02, 0.25);

      case HelmetScenario.wearsHelmet:
        // Consistently high helmet probability (full helmet)
        return (0.94 + noise).clamp(0.85, 0.99);

      case HelmetScenario.transientGlare:
        // Transient 1-frame sun reflection/glare glitch when bikeX is near 400
        if (bikeX > 380 && bikeX < 440) {
          return 0.18; // Glitch frame!
        } else {
          return (0.93 + noise).clamp(0.85, 0.99);
        }
    }
  }

  void _setScenario(HelmetScenario s) {
    setState(() {
      scenario = s;
      bikeX = 80.0;
      frameScores.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    double avgConfidence = frameScores.isEmpty ? 0.0 : frameScores.reduce((a, b) => a + b) / frameScores.length;
    int violationVotes = frameScores.where((s) => s < violationThreshold).length;
    bool hasBuffer = frameScores.length >= 8;
    bool isViolation = hasBuffer && avgConfidence < violationThreshold && violationVotes >= 8;

    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[850],
            child: ClipRect(
              child: CustomPaint(
                painter: _MultiFrameHelmetPainter(
                  bikeX: bikeX,
                  scenario: scenario,
                  frameScores: frameScores,
                  avgConfidence: avgConfidence,
                  isViolation: isViolation,
                  hasBuffer: hasBuffer,
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
                      Text("Real-World Setup: Multi-Frame Temporal Buffer", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      SizedBox(height: 10),
                      Text(
                        "Single-frame classifiers fail due to sun glares or motion blur. Real-world systems run a Multi-Frame Temporal Queue with majority voting across 10 consecutive frames.",
                        style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.3),
                      ),
                      Divider(height: 24),

                      Text("Test Camera Scenarios:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                      SizedBox(height: 6),

                      RadioListTile<HelmetScenario>(
                        dense: true,
                        title: Text("1. Rider Without Helmet", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red[900])),
                        subtitle: Text("10/10 frames fail -> Confirmed Violation", style: TextStyle(fontSize: 11)),
                        value: HelmetScenario.noHelmet,
                        groupValue: scenario,
                        onChanged: (val) => _setScenario(val!),
                      ),
                      RadioListTile<HelmetScenario>(
                        dense: true,
                        title: Text("2. Rider With Full Helmet", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green[900])),
                        subtitle: Text("10/10 frames pass -> Confirmed Safe", style: TextStyle(fontSize: 11)),
                        value: HelmetScenario.wearsHelmet,
                        groupValue: scenario,
                        onChanged: (val) => _setScenario(val!),
                      ),
                      RadioListTile<HelmetScenario>(
                        dense: true,
                        title: Text("3. Optical Glare (1-Frame Glitch)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange[900])),
                        subtitle: Text("1 glitched frame filtered by temporal voting -> Safe!", style: TextStyle(fontSize: 11)),
                        value: HelmetScenario.transientGlare,
                        groupValue: scenario,
                        onChanged: (val) => _setScenario(val!),
                      ),

                      Divider(height: 20),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
                            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 18),
                            label: Text(isPlaying ? "Pause" : "Play", style: TextStyle(color: Colors.white)),
                            onPressed: () => setState(() => isPlaying = !isPlaying),
                          ),
                          SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: Icon(Icons.refresh, size: 18),
                            label: Text("Reset"),
                            onPressed: () => _setScenario(scenario),
                          ),
                        ],
                      ),

                      Divider(height: 24),
                      Text("Temporal Queue Telemetry:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text("Track ID: #58 [Motorcycle + Rider]"),
                      Text("Temporal Window: ${frameScores.length} / $maxBufferFrames frames"),
                      Text("Violation Votes: $violationVotes / ${frameScores.length} (Req: 8/10)"),
                      SizedBox(height: 10),

                      Text("Smoothed Helmet Probability (P_avg):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: avgConfidence,
                        backgroundColor: Colors.grey[300],
                        color: avgConfidence < violationThreshold ? Colors.red : Colors.green,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "${(avgConfidence * 100).toStringAsFixed(1)}% Helmet Probability (Threshold: 35.0%)",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: avgConfidence < violationThreshold ? Colors.red[900] : Colors.green[900]),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1),
              Container(
                padding: EdgeInsets.all(18),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: !hasBuffer 
                      ? Colors.grey[300] 
                      : (isViolation ? Colors.red[100] : Colors.green[100]),
                ),
                child: Column(
                  children: [
                    Text("AI Enforcement Decision:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[800])),
                    SizedBox(height: 4),
                    Text(
                      !hasBuffer
                          ? "GATHERING TEMPORAL FRAMES..."
                          : (isViolation 
                              ? "CONFIRMED NO HELMET VIOLATION\n(Majority Vote: $violationVotes/10 Frames Failed)" 
                              : "CONFIRMED COMPLIANT (SAFE)\n(Noise & Glares Filtered Out)"),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: !hasBuffer 
                            ? Colors.grey[800] 
                            : (isViolation ? Colors.red[900] : Colors.green[900]),
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

class _MultiFrameHelmetPainter extends CustomPainter {
  final double bikeX;
  final HelmetScenario scenario;
  final List<double> frameScores;
  final double avgConfidence;
  final bool isViolation;
  final bool hasBuffer;

  _MultiFrameHelmetPainter({
    required this.bikeX,
    required this.scenario,
    required this.frameScores,
    required this.avgConfidence,
    required this.isViolation,
    required this.hasBuffer,
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
      canvas.drawLine(Offset(dashX, 230), Offset(dashX + 25, 230), laneLine);
      dashX += 50;
    }

    // 2. Draw Moving Motorcycle & Rider
    Offset riderCenter = Offset(bikeX, 140);
    bool wearsHelmetVisual = scenario == HelmetScenario.wearsHelmet || scenario == HelmetScenario.transientGlare;

    _drawMovingRider(canvas, riderCenter, wearsHelmetVisual);

    // 3. YOLO Bounding Box & ByteTrack ID
    Rect riderBox = Rect.fromCenter(center: Offset(riderCenter.dx, riderCenter.dy - 5), width: 90, height: 130);
    Rect headCropBox = Rect.fromLTWH(riderBox.left, riderBox.top, riderBox.width, 35);

    // YOLO Box
    Paint bboxPaint = Paint()
      ..color = isViolation ? Colors.redAccent : Colors.cyanAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(riderBox, bboxPaint);

    // Head Sub-Crop Box (Yellow)
    Paint headCropBorder = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(headCropBox, headCropBorder);

    // Tracking Tag
    TextPainter tpTrack = TextPainter(
      text: TextSpan(
        text: "Track ID #58 [motorcyclist]\nHead Crop [y:y+0.25h]",
        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, backgroundColor: Colors.black87),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    tpTrack.layout();
    tpTrack.paint(canvas, Offset(riderBox.left, riderBox.top - 28));

    // 4. Draw Multi-Frame Filmstrip (Bottom of Canvas)
    _drawTemporalFilmstrip(canvas, size);
  }

  void _drawTemporalFilmstrip(Canvas canvas, Size size) {
    double barY = size.height - 110;
    double barH = 95;
    double barW = size.width - 40;

    // Background panel for filmstrip
    Paint panelBg = Paint()..color = Colors.black87..style = PaintingStyle.fill;
    Paint panelBorder = Paint()..color = Colors.blueGrey[700]!..style = PaintingStyle.stroke..strokeWidth = 1.5;
    Rect panelRect = Rect.fromLTWH(20, barY, barW, barH);
    canvas.drawRRect(RRect.fromRectAndRadius(panelRect, Radius.circular(8)), panelBg);
    canvas.drawRRect(RRect.fromRectAndRadius(panelRect, Radius.circular(8)), panelBorder);

    // Filmstrip Title
    TextPainter tpTitle = TextPainter(
      text: TextSpan(
        text: "SLIDING WINDOW TEMPORAL QUEUE (Last 10 Consecutive Head Crops):",
        style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    );
    tpTitle.layout();
    tpTitle.paint(canvas, Offset(30, barY + 8));

    // Draw individual frame cards
    double cardW = (barW - 30) / 10;
    for (int i = 0; i < 10; i++) {
      double cardX = 30 + i * cardW;
      double cardY = barY + 28;
      Rect cardRect = Rect.fromLTWH(cardX, cardY, cardW - 6, 60);

      bool hasData = i < frameScores.length;
      double score = hasData ? frameScores[i] : 0.0;
      bool isPass = score >= 0.35;

      Paint cardBg = Paint()
        ..color = hasData 
            ? (isPass ? Colors.green[900]!.withOpacity(0.6) : Colors.red[900]!.withOpacity(0.6))
            : Colors.grey[850]!
        ..style = PaintingStyle.fill;
      Paint cardBorder = Paint()
        ..color = hasData ? (isPass ? Colors.greenAccent : Colors.redAccent) : Colors.grey[700]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawRRect(RRect.fromRectAndRadius(cardRect, Radius.circular(4)), cardBg);
      canvas.drawRRect(RRect.fromRectAndRadius(cardRect, Radius.circular(4)), cardBorder);

      if (hasData) {
        TextPainter tpF = TextPainter(
          text: TextSpan(
            text: "F${i + 1}\n${(score * 100).toStringAsFixed(0)}%",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        tpF.layout();
        tpF.paint(canvas, Offset(cardRect.center.dx - tpF.width / 2, cardRect.center.dy - tpF.height / 2));
      } else {
        TextPainter tpEmpty = TextPainter(
          text: TextSpan(text: "F${i + 1}\n--", style: TextStyle(color: Colors.grey[500], fontSize: 9)),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        tpEmpty.layout();
        tpEmpty.paint(canvas, Offset(cardRect.center.dx - tpEmpty.width / 2, cardRect.center.dy - tpEmpty.height / 2));
      }
    }
  }

  void _drawMovingRider(Canvas canvas, Offset center, bool wearsHelmet) {
    if (wearsHelmet) {
      // Full White/Yellow Safety Helmet
      Paint helmetPaint = Paint()..color = Colors.amberAccent;
      canvas.drawCircle(Offset(center.dx, center.dy - 48), 16, helmetPaint);
      // Helmet Visor
      Paint visorPaint = Paint()..color = Colors.black87;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(center.dx + 4, center.dy - 52, 11, 10), Radius.circular(2)), visorPaint);
    } else {
      // Bare Head (Hair)
      Paint headPaint = Paint()..color = Colors.orange[200]!;
      canvas.drawCircle(Offset(center.dx, center.dy - 48), 15, headPaint);
      Paint hairPaint = Paint()..color = Colors.black87;
      canvas.drawArc(Rect.fromCircle(center: Offset(center.dx, center.dy - 51), radius: 15), math.pi, math.pi, true, hairPaint);
    }

    // Jacket / Torso
    Paint torsoPaint = Paint()..color = Colors.blueGrey[700]!;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx, center.dy - 15), width: 45, height: 42), Radius.circular(6)), torsoPaint);

    // Motorcycle Body
    Paint bikePaint = Paint()..color = Colors.red[800]!;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx, center.dy + 25), width: 75, height: 26), Radius.circular(5)), bikePaint);

    // Wheels
    Paint wheelPaint = Paint()..color = Colors.black87;
    canvas.drawCircle(Offset(center.dx - 30, center.dy + 45), 14, wheelPaint);
    canvas.drawCircle(Offset(center.dx + 30, center.dy + 45), 14, wheelPaint);
    canvas.drawCircle(Offset(center.dx - 30, center.dy + 45), 5, Paint()..color = Colors.grey[400]!);
    canvas.drawCircle(Offset(center.dx + 30, center.dy + 45), 5, Paint()..color = Colors.grey[400]!);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
