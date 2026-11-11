import 'package:flutter/material.dart';

class RedLightBruteForce extends StatefulWidget {
  @override
  _RedLightBruteForceState createState() => _RedLightBruteForceState();
}

class _RedLightBruteForceState extends State<RedLightBruteForce> {
  bool busInWay = false;

  @override
  Widget build(BuildContext context) {
    bool systemThinksRed = busInWay;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _RedLightBFPainter(
                busInWay: busInWay,
                systemThinksRed: systemThinksRed,
              ),
              size: Size.infinite,
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
                      Text("The Brute Force Way: Pixel Counters", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Early systems just drew a box where the traffic light usually is and counted how many 'red pixels' it saw. If red > threshold, it assumed the light was red.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Expose the Flaw:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                      SizedBox(height: 8),
                      Text("The light is currently GREEN. Toggle a large bus driving in front of the camera. The bus's red brake lights fill the scanning box, tricking the system.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      SwitchListTile(
                        title: Text("Bus Blocks Camera"),
                        value: busInWay,
                        onChanged: (val) {
                          setState(() {
                            busInWay = val;
                          });
                        },
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
                  color: systemThinksRed ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: systemThinksRed ? Colors.red : Colors.green, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      "Red Pixel Count: ${systemThinksRed ? '85%' : '2%'}",
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                    SizedBox(height: 8),
                    Text(
                      systemThinksRed 
                          ? "LIGHT IS RED!" 
                          : "LIGHT IS GREEN",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: systemThinksRed ? Colors.red[900] : Colors.green[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 16
                      ),
                    ),
                    if (systemThinksRed)
                      Text("System got confused by the bus brake lights.", style: TextStyle(color: Colors.red[800], fontSize: 12), textAlign: TextAlign.center),
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

class _RedLightBFPainter extends CustomPainter {
  final bool busInWay;
  final bool systemThinksRed;

  _RedLightBFPainter({required this.busInWay, required this.systemThinksRed});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2;
    double cy = size.height / 2;

    Paint bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Traffic Light Pole
    canvas.drawRect(Rect.fromLTWH(cx + 100, cy - 100, 10, 200), Paint()..color = Colors.grey[800]!);
    // Traffic Light Box
    canvas.drawRect(Rect.fromLTWH(cx + 85, cy - 180, 40, 100), Paint()..color = Colors.black);
    // Lights (Green is ON)
    canvas.drawCircle(Offset(cx + 105, cy - 160), 10, Paint()..color = Colors.red[900]!); // off
    canvas.drawCircle(Offset(cx + 105, cy - 130), 10, Paint()..color = Colors.yellow[900]!); // off
    canvas.drawCircle(Offset(cx + 105, cy - 100), 10, Paint()..color = Colors.greenAccent); // ON

    // Dumb Pixel Scanner Area
    Rect scanBox = Rect.fromLTWH(cx + 70, cy - 200, 70, 140);
    canvas.drawRect(scanBox, Paint()..color = Colors.orange..strokeWidth = 3..style = PaintingStyle.stroke);
    
    TextPainter tpScan = TextPainter(
      text: TextSpan(text: "STATIC PIXEL\nSCANNER", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, backgroundColor: Colors.white, fontSize: 10)),
      textDirection: TextDirection.ltr,
    );
    tpScan.layout();
    tpScan.paint(canvas, Offset(scanBox.left - 80, scanBox.top));

    // Bus
    if (busInWay) {
      Rect busRect = Rect.fromLTWH(cx - 50, cy - 150, 180, 250);
      canvas.drawRect(busRect, Paint()..color = Colors.blue[800]!);
      
      // Bus Windows
      canvas.drawRect(Rect.fromLTWH(cx - 30, cy - 130, 40, 40), Paint()..color = Colors.lightBlueAccent);
      canvas.drawRect(Rect.fromLTWH(cx + 30, cy - 130, 40, 40), Paint()..color = Colors.lightBlueAccent);

      // Bus Brake Lights (right inside the scanner)
      canvas.drawRect(Rect.fromLTWH(cx + 90, cy - 160, 30, 40), Paint()..color = Colors.redAccent); // Top brake
      canvas.drawRect(Rect.fromLTWH(cx + 90, cy - 50, 30, 20), Paint()..color = Colors.redAccent); // bottom brake
      
      TextPainter tpBus = TextPainter(
        text: TextSpan(text: "BUS BRAKE LIGHTS", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, backgroundColor: Colors.black)),
        textDirection: TextDirection.ltr,
      );
      tpBus.layout();
      tpBus.paint(canvas, Offset(cx + 130, cy - 150));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
