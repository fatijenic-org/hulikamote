import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';

class IllegalParkingSetup extends StatefulWidget {
  @override
  _IllegalParkingSetupState createState() => _IllegalParkingSetupState();
}

enum ParkingScenario { flowing, temporaryStop, illegalPark }

class _IllegalParkingSetupState extends State<IllegalParkingSetup> {
  ParkingScenario scenario = ParkingScenario.illegalPark;
  
  // Simulation State
  double carX = 50.0;
  double carSpeed = 0.0;
  int stationaryFrames = 0;
  final int thresholdFrames = 150; // 5.0 seconds at 30 FPS
  
  // Zone bounds on canvas
  final Rect zoneRect = Rect.fromLTWH(200, 100, 300, 120);
  final double carW = 90;
  final double carH = 45;
  
  Timer? _timer;
  int simStep = 0;

  @override
  void initState() {
    super.initState();
    _startSimulation();
  }

  void _startSimulation() {
    _timer?.cancel();
    stationaryFrames = 0;
    simStep = 0;
    carX = 50.0;

    _timer = Timer.periodic(Duration(milliseconds: 33), (timer) {
      if (!mounted) return;
      setState(() {
        simStep++;
        
        switch (scenario) {
          case ParkingScenario.flowing:
            // Continuous moving car
            carSpeed = 4.0;
            carX += carSpeed;
            if (carX > 850) carX = -50;
            stationaryFrames = 0;
            break;

          case ParkingScenario.temporaryStop:
            // Car moves into zone, stops for 2s (60 frames), then moves away
            if (simStep < 60) {
              carSpeed = 3.5;
              carX += carSpeed;
            } else if (simStep < 120) {
              carSpeed = 0.0; // stopped in stop-and-go traffic
              stationaryFrames++;
            } else if (simStep < 220) {
              carSpeed = 3.5;
              carX += carSpeed;
              stationaryFrames = 0; // reset once moving!
            } else {
              simStep = 0;
              carX = -50;
              stationaryFrames = 0;
            }
            break;

          case ParkingScenario.illegalPark:
            // Car pulls into zone and stays parked
            if (carX < 320) {
              carSpeed = 3.0;
              carX += carSpeed;
            } else {
              carSpeed = 0.0; // Parked!
              if (stationaryFrames < thresholdFrames + 30) {
                stationaryFrames++;
              }
            }
            break;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _setScenario(ParkingScenario s) {
    setState(() {
      scenario = s;
      _startSimulation();
    });
  }

  @override
  Widget build(BuildContext context) {
    Rect carRect = Rect.fromCenter(center: Offset(carX, 160), width: carW, height: carH);
    bool insideZone = zoneRect.overlaps(carRect);
    bool isStationary = carSpeed < 0.5 && insideZone;
    bool isViolation = stationaryFrames >= thresholdFrames;
    double stationarySeconds = stationaryFrames / 30.0;

    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[850],
            child: ClipRect(
              child: CustomPaint(
                painter: _ParkingSetupPainter(
                  carX: carX,
                  carSpeed: carSpeed,
                  zoneRect: zoneRect,
                  insideZone: insideZone,
                  isStationary: isStationary,
                  isViolation: isViolation,
                  stationaryFrames: stationaryFrames,
                  thresholdFrames: thresholdFrames,
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
                      Text("Real-World Setup: Stationary Frame Accumulator", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "In production LTO systems, simply touching a zone does NOT trigger a ticket. The AI pairs ByteTrack velocity (v ≈ 0) with a continuous Frame Accumulator.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 28),

                      Text("Test Traffic Scenarios:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                      SizedBox(height: 8),

                      RadioListTile<ParkingScenario>(
                        title: Text("1. Flowing Traffic (Moving)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        subtitle: Text("Speed > 0 -> Accumulator stays 0 (Safe)", style: TextStyle(fontSize: 12)),
                        value: ParkingScenario.flowing,
                        groupValue: scenario,
                        onChanged: (val) => _setScenario(val!),
                      ),
                      RadioListTile<ParkingScenario>(
                        title: Text("2. Stop-and-Go Traffic (Temporary)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        subtitle: Text("Stops for 2.0s < 5.0s -> Resets safely", style: TextStyle(fontSize: 12)),
                        value: ParkingScenario.temporaryStop,
                        groupValue: scenario,
                        onChanged: (val) => _setScenario(val!),
                      ),
                      RadioListTile<ParkingScenario>(
                        title: Text("3. Illegal Parking (Stationary)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        subtitle: Text("Parked >= 5.0s (150 frames) -> Violation", style: TextStyle(fontSize: 12)),
                        value: ParkingScenario.illegalPark,
                        groupValue: scenario,
                        onChanged: (val) => _setScenario(val!),
                      ),

                      Divider(height: 28),
                      Text("Telemetry & Frame Buffer:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text("Vehicle Speed: ${carSpeed > 0 ? (carSpeed * 10).toStringAsFixed(0) : '0'} km/h"),
                      Text("Inside Zone: ${insideZone ? 'YES' : 'NO'}"),
                      Text("Velocity Filter: ${isStationary ? 'STATIONARY (v ≈ 0)' : 'MOVING (v > 0)'}"),
                      SizedBox(height: 12),
                      
                      Text("Stationary Duration: ${stationarySeconds.toStringAsFixed(1)}s / 5.0s"),
                      SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: (stationaryFrames / thresholdFrames).clamp(0.0, 1.0),
                        backgroundColor: Colors.grey[300],
                        color: isViolation ? Colors.red : (isStationary ? Colors.orange : Colors.green),
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      SizedBox(height: 4),
                      Text("Accumulated Frames: $stationaryFrames / $thresholdFrames frames", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ),
              Divider(height: 1),
              Container(
                padding: EdgeInsets.all(20),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isViolation ? Colors.red[100] : (isStationary ? Colors.orange[100] : Colors.green[100]),
                ),
                child: Column(
                  children: [
                    Text("AI Enforcement Decision:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey[800])),
                    SizedBox(height: 6),
                    Text(
                      isViolation 
                          ? "ILLEGAL PARKING VIOLATION\n(Threshold Exceeded -> Ticket Generated)" 
                          : (isStationary ? "ACCUMULATING TIME...\n(Grace Period Active)" : "SAFE / FLOWING TRAFFIC\n(No Accumulation)"),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isViolation ? Colors.red[900] : (isStationary ? Colors.orange[900] : Colors.green[900]),
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

class _ParkingSetupPainter extends CustomPainter {
  final double carX;
  final double carSpeed;
  final Rect zoneRect;
  final bool insideZone;
  final bool isStationary;
  final bool isViolation;
  final int stationaryFrames;
  final int thresholdFrames;

  _ParkingSetupPainter({
    required this.carX,
    required this.carSpeed,
    required this.zoneRect,
    required this.insideZone,
    required this.isStationary,
    required this.isViolation,
    required this.stationaryFrames,
    required this.thresholdFrames,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Road background
    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    // Sidewalk curb
    Paint curbPaint = Paint()..color = Colors.grey[400]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 40, size.width, 30), curbPaint);

    // Red curb marking (No Parking zone marking on curb)
    Paint redCurbPaint = Paint()..color = Colors.redAccent..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(zoneRect.left, 65, zoneRect.width, 5), redCurbPaint);

    // Lane divider
    Paint laneLine = Paint()..color = Colors.white70..strokeWidth = 3..style = PaintingStyle.stroke;
    double dashX = 0;
    while (dashX < size.width) {
      canvas.drawLine(Offset(dashX, 240), Offset(dashX + 25, 240), laneLine);
      dashX += 50;
    }

    // No Parking Zone Polygon overlay
    Paint zoneFill = Paint()..color = Colors.yellow.withOpacity(0.18)..style = PaintingStyle.fill;
    Paint zoneStroke = Paint()..color = Colors.yellowAccent..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(zoneRect, Radius.circular(6)), zoneFill);
    canvas.drawRRect(RRect.fromRectAndRadius(zoneRect, Radius.circular(6)), zoneStroke);

    // Zone Label
    TextPainter tpZone = TextPainter(
      text: TextSpan(
        text: "NO PARKING ZONE (Z_park)", 
        style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 13, backgroundColor: Colors.black54),
      ),
      textDirection: TextDirection.ltr,
    );
    tpZone.layout();
    tpZone.paint(canvas, Offset(zoneRect.left + 10, zoneRect.top + 8));

    // Draw Vehicle
    Offset carCenter = Offset(carX, 160);
    Rect carBox = Rect.fromCenter(center: carCenter, width: 90, height: 45);

    // Car Body
    Paint carPaint = Paint()..color = isViolation ? Colors.redAccent : Colors.blueAccent;
    canvas.drawRRect(RRect.fromRectAndRadius(carBox, Radius.circular(8)), carPaint);

    // Windshield & Roof
    Paint roofPaint = Paint()..color = Colors.lightBlue[100]!;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: carCenter, width: 45, height: 30), Radius.circular(4)), roofPaint);

    // Bounding Box from YOLO
    Paint bboxPaint = Paint()
      ..color = isViolation ? Colors.red : (isStationary ? Colors.orangeAccent : Colors.greenAccent)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(carBox.inflate(4), bboxPaint);

    // Centroid Dot
    Paint dotPaint = Paint()..color = isViolation ? Colors.red : (isStationary ? Colors.orange : Colors.greenAccent);
    canvas.drawCircle(carCenter, 5, dotPaint);

    // Centroid Tag
    TextPainter tpTag = TextPainter(
      text: TextSpan(
        text: "ByteTrack Centroid\nSpeed: ${carSpeed > 0 ? (carSpeed * 10).toStringAsFixed(0) : '0'} km/h",
        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, backgroundColor: Colors.black87),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    tpTag.layout();
    tpTag.paint(canvas, Offset(carCenter.dx - tpTag.width / 2, carCenter.dy + 30));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
