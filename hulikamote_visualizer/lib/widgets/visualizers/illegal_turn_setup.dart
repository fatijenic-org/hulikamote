import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';

class IllegalTurnSetup extends StatefulWidget {
  @override
  _IllegalTurnSetupState createState() => _IllegalTurnSetupState();
}

enum TurnScenario { leftTurn, rightTurn, uTurn, straight }

class _IllegalTurnSetupState extends State<IllegalTurnSetup> {
  TurnScenario scenario = TurnScenario.rightTurn; // Default right turn (prohibited in demo)

  double progress = 0.0; // 0.0 to 1.0 animation progress
  bool isPlaying = true;
  Timer? _animTimer;

  // Real-world intersection bounds
  final Rect intersectionRect = Rect.fromLTWH(260, 120, 180, 180);

  // Live Trajectory History
  List<Offset> centroidHistory = [];
  Offset? entryCentroid;
  double? entryAngleRad;
  double currentTurnAngleDeg = 0.0;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  void _startAnimation() {
    _animTimer?.cancel();
    _animTimer = Timer.periodic(Duration(milliseconds: 33), (timer) {
      if (!mounted) return;
      if (isPlaying) {
        setState(() {
          progress += 0.008;
          if (progress > 1.0) {
            progress = 0.0;
            centroidHistory.clear();
            entryCentroid = null;
            entryAngleRad = null;
            currentTurnAngleDeg = 0.0;
          }
          _updateTrajectory();
        });
      }
    });
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    super.dispose();
  }

  // Calculate car position along curved bezier path based on scenario
  Offset _computeCarPosition(double t) {
    Offset start = Offset(350, 440); // South approach heading North

    switch (scenario) {
      case TurnScenario.leftTurn:
        // Turns West (Left)
        Offset control = Offset(350, 210);
        Offset end = Offset(40, 210);
        return _bezier(start, control, end, t);

      case TurnScenario.rightTurn:
        // Turns East (Right)
        Offset control = Offset(350, 210);
        Offset end = Offset(660, 210);
        return _bezier(start, control, end, t);

      case TurnScenario.uTurn:
        // Makes 180 deg U-turn back South
        if (t < 0.35) {
          return Offset(330, 440 - (t / 0.35) * 200);
        } else if (t < 0.7) {
          double arcT = (t - 0.35) / 0.35;
          double uAngle = -math.pi / 2 + arcT * math.pi;
          return Offset(305 + math.cos(uAngle) * 25, 240 + math.sin(uAngle) * 25);
        } else {
          double exitT = (t - 0.7) / 0.3;
          return Offset(280, 240 + exitT * 200);
        }

      case TurnScenario.straight:
        // Goes straight North
        return Offset(350, 440 - t * 440);
    }
  }

  Offset _bezier(Offset p0, Offset p1, Offset p2, double t) {
    double u = 1 - t;
    double tt = t * t;
    double uu = u * u;
    return Offset(
      uu * p0.dx + 2 * u * t * p1.dx + tt * p2.dx,
      uu * p0.dy + 2 * u * t * p1.dy + tt * p2.dy,
    );
  }

  double _computeCarHeading(double t) {
    double dt = 0.01;
    Offset pNow = _computeCarPosition(t);
    Offset pNext = _computeCarPosition(math.min(t + dt, 1.0));
    return math.atan2(pNext.dy - pNow.dy, pNext.dx - pNow.dx);
  }

  void _updateTrajectory() {
    Offset currentPos = _computeCarPosition(progress);
    centroidHistory.add(currentPos);
    if (centroidHistory.length > 50) centroidHistory.removeAt(0);

    bool inside = intersectionRect.contains(currentPos);

    if (inside && entryCentroid == null) {
      entryCentroid = currentPos;
      entryAngleRad = _computeCarHeading(progress);
    } else if (inside && entryAngleRad != null) {
      double currentHeading = _computeCarHeading(progress);
      double diff = currentHeading - entryAngleRad!;
      diff = (diff + math.pi) % (2 * math.pi) - math.pi;
      currentTurnAngleDeg = diff * 180 / math.pi;
    }
  }

  void _selectScenario(TurnScenario s) {
    setState(() {
      scenario = s;
      progress = 0.0;
      centroidHistory.clear();
      entryCentroid = null;
      entryAngleRad = null;
      currentTurnAngleDeg = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    Offset currentPos = _computeCarPosition(progress);
    double currentHeading = _computeCarHeading(progress);
    bool insideIntersection = intersectionRect.contains(currentPos);

    bool isViolation = (scenario == TurnScenario.rightTurn || scenario == TurnScenario.uTurn) && progress > 0.45;

    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[850],
            child: ClipRect(
              child: CustomPaint(
                painter: _RealWorldTurnSetupPainter(
                  intersectionRect: intersectionRect,
                  carPos: currentPos,
                  carHeading: currentHeading,
                  centroidHistory: centroidHistory,
                  insideIntersection: insideIntersection,
                  isViolation: isViolation,
                  scenario: scenario,
                  progress: progress,
                  turnAngleDeg: currentTurnAngleDeg,
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
                      Text("Real-World Setup: AI Trajectory & Gate Pipeline", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      SizedBox(height: 10),
                      Text(
                        "Watch the real-time AI pipeline detect the vehicle, track its persistent centroid spline through the intersection gate, and compute the angular turn displacement.",
                        style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.3),
                      ),
                      Divider(height: 24),

                      Text("Select Test Maneuver:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                      SizedBox(height: 6),

                      RadioListTile<TurnScenario>(
                        dense: true,
                        title: Text("1. Right Turn (PROHIBITED RULE)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red[900])),
                        subtitle: Text("Δθ ≈ +90° -> Triggers Illegal Right Turn", style: TextStyle(fontSize: 11)),
                        value: TurnScenario.rightTurn,
                        groupValue: scenario,
                        onChanged: (val) => _selectScenario(val!),
                      ),
                      RadioListTile<TurnScenario>(
                        dense: true,
                        title: Text("2. Left Turn (PERMITTED)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green[900])),
                        subtitle: Text("Δθ ≈ -90° -> In compliance with rules", style: TextStyle(fontSize: 11)),
                        value: TurnScenario.leftTurn,
                        groupValue: scenario,
                        onChanged: (val) => _selectScenario(val!),
                      ),
                      RadioListTile<TurnScenario>(
                        dense: true,
                        title: Text("3. U-Turn (PROHIBITED RULE)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red[900])),
                        subtitle: Text("|Δθ| > 135° -> Triggers Illegal U-Turn", style: TextStyle(fontSize: 11)),
                        value: TurnScenario.uTurn,
                        groupValue: scenario,
                        onChanged: (val) => _selectScenario(val!),
                      ),
                      RadioListTile<TurnScenario>(
                        dense: true,
                        title: Text("4. Straight Through (PERMITTED)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green[900])),
                        subtitle: Text("Δθ ≈ 0° -> Safe travel across junction", style: TextStyle(fontSize: 11)),
                        value: TurnScenario.straight,
                        groupValue: scenario,
                        onChanged: (val) => _selectScenario(val!),
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
                            label: Text("Replay"),
                            onPressed: () => _selectScenario(scenario),
                          ),
                        ],
                      ),

                      Divider(height: 24),
                      Text("Live AI Pipeline Telemetry:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text("YOLOv8 Class: 'car' (Confidence: 0.94)"),
                      Text("ByteTrack ID: #104 (Persistent Centroid Track)"),
                      Text("Inside Intersection Gate: ${insideIntersection ? 'YES (Active Monitoring)' : 'NO'}"),
                      Text("Turn Curvature (Δθ): ${currentTurnAngleDeg.toStringAsFixed(1)}°", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                      Text("Centroid History Points: ${centroidHistory.length} frames"),
                    ],
                  ),
                ),
              ),
              Divider(height: 1),
              Container(
                padding: EdgeInsets.all(18),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isViolation ? Colors.red[100] : (insideIntersection ? Colors.blue[100] : Colors.green[100]),
                ),
                child: Column(
                  children: [
                    Text("AI Intersection Decision:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[800])),
                    SizedBox(height: 4),
                    Text(
                      isViolation 
                          ? "VIOLATION DETECTED!\n${scenario == TurnScenario.rightTurn ? 'NO RIGHT TURN VIOLATION' : 'ILLEGAL U-TURN VIOLATION'}"
                          : (insideIntersection ? "LEGAL MANEUVER IN PROGRESS\n(Permitted by Intersection Rule)" : "APPROACHING JUNCTION\nNo Infraction"),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isViolation ? Colors.red[900] : (insideIntersection ? Colors.blue[900] : Colors.green[900]),
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

class _RealWorldTurnSetupPainter extends CustomPainter {
  final Rect intersectionRect;
  final Offset carPos;
  final double carHeading;
  final List<Offset> centroidHistory;
  final bool insideIntersection;
  final bool isViolation;
  final TurnScenario scenario;
  final double progress;
  final double turnAngleDeg;

  _RealWorldTurnSetupPainter({
    required this.intersectionRect,
    required this.carPos,
    required this.carHeading,
    required this.centroidHistory,
    required this.insideIntersection,
    required this.isViolation,
    required this.scenario,
    required this.progress,
    required this.turnAngleDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw 4-Way Crossroad Asphalt
    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(260, 0, 180, size.height), roadPaint);
    canvas.drawRect(Rect.fromLTWH(0, 120, size.width, 180), roadPaint);

    // 2. Road Markings & Lane dividers
    Paint laneLine = Paint()..color = Colors.white60..strokeWidth = 2..style = PaintingStyle.stroke;
    _drawDashedLine(canvas, Offset(350, 300), Offset(350, size.height), laneLine);
    _drawDashedLine(canvas, Offset(350, 0), Offset(350, 120), laneLine);
    _drawDashedLine(canvas, Offset(0, 210), Offset(260, 210), laneLine);
    _drawDashedLine(canvas, Offset(440, 210), Offset(size.width, 210), laneLine);

    // Stop lines
    Paint stopLinePaint = Paint()..color = Colors.white..strokeWidth = 4;
    canvas.drawLine(Offset(260, 300), Offset(350, 300), stopLinePaint);
    canvas.drawLine(Offset(350, 120), Offset(440, 120), stopLinePaint);
    canvas.drawLine(Offset(260, 120), Offset(260, 210), stopLinePaint);
    canvas.drawLine(Offset(440, 210), Offset(440, 300), stopLinePaint);

    // 3. Draw Intersection ROI Gate
    Paint zoneFill = Paint()
      ..color = (isViolation ? Colors.red : (insideIntersection ? Colors.blue : Colors.yellow)).withOpacity(0.18)
      ..style = PaintingStyle.fill;
    Paint zoneBorder = Paint()
      ..color = isViolation ? Colors.redAccent : (insideIntersection ? Colors.blueAccent : Colors.yellowAccent)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(intersectionRect, Radius.circular(6)), zoneFill);
    canvas.drawRRect(RRect.fromRectAndRadius(intersectionRect, Radius.circular(6)), zoneBorder);

    TextPainter tpZone = TextPainter(
      text: TextSpan(
        text: "INTERSECTION GATE (Z_int)",
        style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 11, backgroundColor: Colors.black54),
      ),
      textDirection: TextDirection.ltr,
    );
    tpZone.layout();
    tpZone.paint(canvas, Offset(intersectionRect.left + 8, intersectionRect.top + 8));

    // 4. Draw Trajectory Centroid Breadcrumb Path
    if (centroidHistory.length > 1) {
      Paint trajPaint = Paint()..color = isViolation ? Colors.redAccent : Colors.cyanAccent..strokeWidth = 2.5;
      for (int i = 0; i < centroidHistory.length - 1; i++) {
        canvas.drawLine(centroidHistory[i], centroidHistory[i + 1], trajPaint);
        canvas.drawCircle(centroidHistory[i], 3, Paint()..color = Colors.yellowAccent);
      }
    }

    // 5. Draw Vehicle with YOLO Bounding Box & ByteTrack Centroid
    canvas.save();
    canvas.translate(carPos.dx, carPos.dy);
    canvas.rotate(carHeading);

    // Car Body
    Paint carPaint = Paint()..color = isViolation ? Colors.redAccent : (insideIntersection ? Colors.cyanAccent : Colors.blueAccent);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 50, height: 26), Radius.circular(5)), carPaint);

    // Windshield
    Paint glassPaint = Paint()..color = Colors.white70;
    canvas.drawRect(Rect.fromLTWH(8, -10, 10, 20), glassPaint);

    // Headlights
    Paint lightPaint = Paint()..color = Colors.yellow;
    canvas.drawCircle(Offset(24, -8), 3, lightPaint);
    canvas.drawCircle(Offset(24, 8), 3, lightPaint);

    canvas.restore();

    // YOLO Bounding box overlay
    Rect carBox = Rect.fromCenter(center: carPos, width: 56, height: 40);
    Paint bboxPaint = Paint()
      ..color = isViolation ? Colors.red : (insideIntersection ? Colors.cyanAccent : Colors.greenAccent)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(carBox, bboxPaint);

    // ByteTrack Centroid Dot
    Paint dotPaint = Paint()..color = isViolation ? Colors.red : Colors.yellowAccent;
    canvas.drawCircle(carPos, 5, dotPaint);

    // Tracking Tag
    TextPainter tpTrack = TextPainter(
      text: TextSpan(
        text: "ID #104 [car 0.94]\nΔθ: ${turnAngleDeg.toStringAsFixed(1)}°",
        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, backgroundColor: Colors.black87),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    tpTrack.layout();
    tpTrack.paint(canvas, Offset(carPos.dx - tpTrack.width / 2, carPos.dy + 24));

    // 6. Intersection Restriction Badges
    _drawSignBadge(canvas, "NO RIGHT 🚫↱", Offset(470, 70), Colors.red[800]!);
    _drawSignBadge(canvas, "NO U-TURN 🚫↷", Offset(300, 370), Colors.red[800]!);
  }

  void _drawSignBadge(Canvas canvas, String text, Offset pos, Color color) {
    TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    Paint bgPaint = Paint()..color = color;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(pos.dx - 6, pos.dy - 3, tp.width + 12, tp.height + 6), Radius.circular(4)), bgPaint);
    tp.paint(canvas, pos);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    double distance = (end - start).distance;
    double dashWidth = 15;
    double dashSpace = 15;
    double dx = (end.dx - start.dx) / distance;
    double dy = (end.dy - start.dy) / distance;
    double current = 0.0;

    while (current < distance) {
      Offset p1 = Offset(start.dx + dx * current, start.dy + dy * current);
      double next = math.min(current + dashWidth, distance);
      Offset p2 = Offset(start.dx + dx * next, start.dy + dy * next);
      canvas.drawLine(p1, p2, paint);
      current += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
