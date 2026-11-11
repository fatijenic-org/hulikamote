import 'package:flutter/material.dart';

class IllegalParkingBruteForce extends StatefulWidget {
  @override
  _IllegalParkingBruteForceState createState() => _IllegalParkingBruteForceState();
}

class _IllegalParkingBruteForceState extends State<IllegalParkingBruteForce> {
  double cameraShiftX = 0;
  double cameraShiftY = 0;
  bool isLegallyParked = true; // True = parked outside the yellow lines. False = parked inside.

  @override
  Widget build(BuildContext context) {
    // Car physical position on the road
    double carRoadX = isLegallyParked ? 400 : 250;
    double carRoadY = 200;

    // Car screen position after camera shift
    double carScreenX = carRoadX + cameraShiftX;
    double carScreenY = carRoadY + cameraShiftY;
    
    // Fixed screen grid zone (The cardboard stencil)
    Rect fixedGridZone = Rect.fromLTWH(180, 150, 140, 100);
    
    // Check if car's center is inside the fixed screen grid
    bool systemFlagsViolation = fixedGridZone.contains(Offset(carScreenX, carScreenY));

    return Row(
      children: [
        // CANVAS AREA
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: ClipRect(
              child: CustomPaint(
                painter: _BruteForcePainter(
                  cameraShiftX: cameraShiftX,
                  cameraShiftY: cameraShiftY,
                  isLegallyParked: isLegallyParked,
                  fixedGridZone: fixedGridZone,
                ),
                size: Size.infinite,
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
                      Text("The Brute Force Way: Fixed Coordinates", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Old systems define a 'No Parking' zone by hardcoding pixel coordinates on the screen. Like taping a cardboard stencil to your monitor.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Actual Situation:", style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: isLegallyParked ? Colors.green : Colors.grey[300]),
                              onPressed: () => setState(() => isLegallyParked = true),
                              child: Text("Legally Parked", style: TextStyle(color: isLegallyParked ? Colors.white : Colors.black, fontSize: 12)),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: !isLegallyParked ? Colors.red : Colors.grey[300]),
                              onPressed: () => setState(() => isLegallyParked = false),
                              child: Text("Illegally Parked", style: TextStyle(color: !isLegallyParked ? Colors.white : Colors.black, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                      
                      SizedBox(height: 24),
                      Text("2. Expose the Flaw (Move Camera):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                      SizedBox(height: 8),
                      Text("If the pole shakes in the wind, the physical road moves on screen, but the fixed stencil does not.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      Text("Camera Pan X (Horizontal):"),
                      Slider(
                        value: cameraShiftX,
                        min: -150,
                        max: 150,
                        activeColor: Colors.orange,
                        onChanged: (val) => setState(() => cameraShiftX = val),
                      ),
                      Text("Camera Pan Y (Vertical):"),
                      Slider(
                        value: cameraShiftY,
                        min: -150,
                        max: 150,
                        activeColor: Colors.orange,
                        onChanged: (val) => setState(() => cameraShiftY = val),
                      ),
                      Center(
                        child: TextButton(
                          onPressed: () => setState(() {
                            cameraShiftX = 0;
                            cameraShiftY = 0;
                          }),
                          child: Text("Reset Camera"),
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
                  color: systemFlagsViolation ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: systemFlagsViolation ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      systemFlagsViolation 
                          ? "RESULT: VIOLATION LOGGED" 
                          : "RESULT: NO VIOLATION",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: systemFlagsViolation ? Colors.red[900] : Colors.green[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 18
                      ),
                    ),
                    if (systemFlagsViolation && isLegallyParked)
                      Text("(FALSE POSITIVE!)", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    if (!systemFlagsViolation && !isLegallyParked)
                      Text("(MISSED VIOLATION!)", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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

class _BruteForcePainter extends CustomPainter {
  final double cameraShiftX;
  final double cameraShiftY;
  final bool isLegallyParked;
  final Rect fixedGridZone;

  _BruteForcePainter({
    required this.cameraShiftX,
    required this.cameraShiftY,
    required this.isLegallyParked,
    required this.fixedGridZone,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Physical World (moves with camera)
    canvas.save();
    canvas.translate(cameraShiftX, cameraShiftY);

    // Draw Road Background
    Paint roadPaint = Paint()..color = Colors.grey[700]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(-500, -500, size.width + 1000, size.height + 1000), roadPaint);

    // Draw Sidewalk
    Paint curbPaint = Paint()..color = Colors.grey[400]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(-500, 50, size.width + 1000, 40), curbPaint);

    // Draw Real painted No Parking Zone (Yellow)
    Rect realZone = Rect.fromLTWH(180, 150, 140, 100);
    Paint realZonePaint = Paint()..color = Colors.yellow.withOpacity(0.4)..style = PaintingStyle.fill;
    Paint realZoneBorder = Paint()..color = Colors.yellow..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawRect(realZone, realZonePaint);
    canvas.drawRect(realZone, realZoneBorder);

    TextPainter tpRealZone = TextPainter(
      text: TextSpan(text: "Painted Road Zone", style: TextStyle(color: Colors.yellow[200], fontSize: 12)),
      textDirection: TextDirection.ltr,
    );
    tpRealZone.layout();
    tpRealZone.paint(canvas, Offset(realZone.left + 5, realZone.bottom - 20));

    // Draw Car
    double carRoadX = isLegallyParked ? 400 : 250;
    double carRoadY = 200;
    
    Paint carPaint = Paint()..color = Colors.blueGrey;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(carRoadX, carRoadY), width: 60, height: 30), Radius.circular(4)), carPaint);

    canvas.restore();

    // 2. Draw Fixed Screen Elements (does NOT move with camera)
    Paint stencilBorder = Paint()..color = Colors.orange..strokeWidth = 4..style = PaintingStyle.stroke;
    canvas.drawRect(fixedGridZone, stencilBorder);

    // Diagonal hatch pattern inside fixed grid
    Paint hatchPaint = Paint()..color = Colors.orange.withOpacity(0.3)..strokeWidth = 2;
    for (double i = fixedGridZone.left; i < fixedGridZone.right + fixedGridZone.height; i += 15) {
      canvas.drawLine(
        Offset(i, fixedGridZone.top),
        Offset(i - fixedGridZone.height, fixedGridZone.bottom),
        hatchPaint
      );
    }

    TextPainter tpStencil = TextPainter(
      text: TextSpan(text: "FIXED SCREEN GRID\n(The Stencil)", style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.bold, backgroundColor: Colors.white)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    tpStencil.layout();
    tpStencil.paint(canvas, Offset(fixedGridZone.left + 10, fixedGridZone.top - 35));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
