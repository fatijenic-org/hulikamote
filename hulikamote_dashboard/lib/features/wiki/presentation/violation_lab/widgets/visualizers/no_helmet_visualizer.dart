import 'package:flutter/material.dart';

class NoHelmetVisualizer extends StatefulWidget {
  @override
  _NoHelmetVisualizerState createState() => _NoHelmetVisualizerState();
}

class _NoHelmetVisualizerState extends State<NoHelmetVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _helmetState = 0; // 0 = Worn, 1 = No Helmet, 2 = On Lap

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(seconds: 4));
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _triggerState(int state) {
    setState(() {
      _helmetState = state;
    });
    _controller.forward(from: 0.0);
    _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    bool isViolating = _helmetState == 1 || _helmetState == 2;
    
    String status = "SCANNING GEOMETRY...";
    if (_controller.value > 0.3) {
      if (_helmetState == 0) status = "CLASSIFIED: VALID HELMET (IN TOP 20%)";
      else if (_helmetState == 1) status = "CLASSIFIED: NO HELMET DETECTED";
      else if (_helmetState == 2) status = "CLASSIFIED: HELMET ON LAP (IoU FAIL)";
    }

    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.grey[200],
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: _NoHelmetAIPainter(
                    progress: _controller.value,
                    helmetState: _helmetState,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            children: [
              Text("Modern AI: Geometric IoU Rule", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              SizedBox(height: 8),
              Text("To solve the 'Helmet on Lap' edge case, the AI enforces a Geometric IoU rule: The helmet's bounding box center must reside in the top 20% of the Rider's bounding box.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _helmetState == 0 ? Colors.green[800] : Colors.green),
                    onPressed: () => _triggerState(0),
                    child: Text("Wear Helmet", style: TextStyle(color: Colors.white)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _helmetState == 2 ? Colors.orange[800] : Colors.orange),
                    onPressed: () => _triggerState(2),
                    child: Text("Helmet on Lap", style: TextStyle(color: Colors.white)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _helmetState == 1 ? Colors.red[800] : Colors.red),
                    onPressed: () => _triggerState(1),
                    child: Text("No Helmet", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 32),
                decoration: BoxDecoration(
                  color: _controller.value < 0.3 ? Colors.grey[200] : (isViolating ? Colors.red[100] : Colors.green[100]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _controller.value < 0.3 ? Colors.grey : (isViolating ? Colors.red : Colors.green))
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _controller.value < 0.3 ? Colors.grey[800] : (isViolating ? Colors.red[900] : Colors.green[900])
                  ),
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}

class _NoHelmetAIPainter extends CustomPainter {
  final double progress;
  final int helmetState; // 0=Worn, 1=None, 2=On Lap

  _NoHelmetAIPainter({required this.progress, required this.helmetState});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint roadPaint = Paint()..color = Colors.grey[800]!..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roadPaint);

    double startX = size.width + 50;
    double endX = -100;
    double currentX = startX + (endX - startX) * progress;

    // Motorcycle Profile
    Rect motoRect = Rect.fromCenter(center: Offset(currentX, cy + 50), width: 140, height: 60);
    canvas.drawRRect(RRect.fromRectAndRadius(motoRect, Radius.circular(10)), Paint()..color = Colors.blueGrey);
    canvas.drawCircle(Offset(currentX - 50, cy + 80), 25, Paint()..color = Colors.black);
    canvas.drawCircle(Offset(currentX + 50, cy + 80), 25, Paint()..color = Colors.black);

    // Rider Profile (orange box represents rider)
    Rect riderBox = Rect.fromCenter(center: Offset(currentX, cy), width: 60, height: 120);
    canvas.drawRect(riderBox, Paint()..color = Colors.orange[400]!);
    
    // Head (bare head)
    Offset bareHeadPos = Offset(currentX, riderBox.top + 20);
    if (helmetState != 0) {
      canvas.drawCircle(bareHeadPos, 20, Paint()..color = Colors.brown[300]!); // bare head visible
    }

    // Helmet Pos
    Offset helmetPos;
    if (helmetState == 0) {
      helmetPos = bareHeadPos; // On head
      canvas.drawCircle(helmetPos, 22, Paint()..color = Colors.green[900]!);
    } else if (helmetState == 2) {
      helmetPos = Offset(currentX + 15, riderBox.bottom - 30); // On lap
      canvas.drawCircle(helmetPos, 22, Paint()..color = Colors.green[900]!);
    } else {
      helmetPos = Offset(-100, -100); // Hidden
    }

    if (progress > 0.1) {
      // Draw Rider Bounding Box (Blue)
      Paint riderBoxPaint = Paint()..color = Colors.blueAccent..strokeWidth = 2..style = PaintingStyle.stroke;
      canvas.drawRect(riderBox, riderBoxPaint);
      
      // Draw 20% Threshold Line
      double thresholdY = riderBox.top + (riderBox.height * 0.20);
      _drawDashedLine(canvas, Offset(riderBox.left - 20, thresholdY), Offset(riderBox.right + 20, thresholdY), Colors.yellowAccent);
      
      TextPainter tpThresh = TextPainter(
        text: TextSpan(text: "Top 20% Limit", style: TextStyle(color: Colors.yellowAccent, fontSize: 10, backgroundColor: Colors.black54)),
        textDirection: TextDirection.ltr,
      );
      tpThresh.layout();
      tpThresh.paint(canvas, Offset(riderBox.right + 25, thresholdY - 6));

      if (progress > 0.3) {
        if (helmetState == 1) {
          // No Helmet logic
          TextPainter tpFail = TextPainter(
            text: TextSpan(text: "NO HELMET DETECTED", style: TextStyle(color: Colors.redAccent, fontSize: 12, backgroundColor: Colors.black)),
            textDirection: TextDirection.ltr,
          );
          tpFail.layout();
          tpFail.paint(canvas, Offset(riderBox.left, riderBox.top - 20));
        } else {
          // Draw Helmet Bounding Box
          Rect helmetBox = Rect.fromCenter(center: helmetPos, width: 44, height: 44);
          bool isViolating = helmetState == 2;
          Paint helmetBoxPaint = Paint()..color = isViolating ? Colors.red : Colors.green..strokeWidth = 2..style = PaintingStyle.stroke;
          canvas.drawRect(helmetBox, helmetBoxPaint);
          
          // Draw center dot
          canvas.drawCircle(helmetPos, 3, Paint()..color = Colors.white);
          
          // Draw connecting line to check threshold
          canvas.drawLine(helmetPos, Offset(riderBox.left - 20, helmetPos.dy), Paint()..color = Colors.white54..strokeWidth = 1);
          
          String label = isViolating ? "IoU FAIL (LAP)" : "IoU PASS (HEAD)";
          TextPainter tpLabel = TextPainter(
            text: TextSpan(
              text: label,
              style: TextStyle(color: isViolating ? Colors.redAccent : Colors.greenAccent, fontSize: 12, backgroundColor: Colors.black)
            ),
            textDirection: TextDirection.ltr,
          );
          tpLabel.layout();
          tpLabel.paint(canvas, Offset(helmetBox.left - 10, helmetBox.top - 20));
        }
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Color color) {
    Paint paint = Paint()..color = color..strokeWidth = 1.5;
    double dashWidth = 5, dashSpace = 5, startX = p1.dx;
    while (startX < p2.dx) {
      canvas.drawLine(Offset(startX, p1.dy), Offset(startX + dashWidth, p1.dy), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
