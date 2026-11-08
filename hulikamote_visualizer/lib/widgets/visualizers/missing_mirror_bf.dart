import 'package:flutter/material.dart';

class MissingMirrorBruteForce extends StatefulWidget {
  @override
  _MissingMirrorBruteForceState createState() => _MissingMirrorBruteForceState();
}

class _MissingMirrorBruteForceState extends State<MissingMirrorBruteForce> {
  bool noisyBackground = false;

  @override
  Widget build(BuildContext context) {
    bool silhouetteMatched = !noisyBackground;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[200],
            child: CustomPaint(
              painter: _MissingMirrorBFPainter(
                noisyBackground: noisyBackground,
                silhouetteMatched: silhouetteMatched,
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
                      Text("The Brute Force Way: Shape Templates", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      Text(
                        "Early systems used Edge Detection to extract the silhouette of the motorcycle and compared it against a perfect 'template' shape of a bike with mirrors.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
                      ),
                      Divider(height: 32),
                      
                      Text("1. Expose the Flaw:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                      SizedBox(height: 8),
                      Text("When the background has trees, signs, or other vehicles, the edge detector pulls in that noise, completely ruining the silhouette shape.", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      SizedBox(height: 16),
                      
                      SwitchListTile(
                        title: Text("Add Noisy Background"),
                        value: noisyBackground,
                        onChanged: (val) {
                          setState(() {
                            noisyBackground = val;
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
                  color: silhouetteMatched ? Colors.green[100] : Colors.red[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: silhouetteMatched ? Colors.green : Colors.red, width: 2)
                ),
                child: Column(
                  children: [
                    Text(
                      "Template Match Score:",
                      style: TextStyle(color: Colors.grey[800]),
                    ),
                    Text(
                      silhouetteMatched ? "92%" : "34%",
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 24),
                    ),
                    SizedBox(height: 8),
                    Text(
                      silhouetteMatched 
                          ? "RESULT: MIRRORS PRESENT" 
                          : "RESULT: SHAPE REJECTED",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: silhouetteMatched ? Colors.green[900] : Colors.red[900], 
                        fontWeight: FontWeight.bold, 
                        fontSize: 16
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

class _MissingMirrorBFPainter extends CustomPainter {
  final bool noisyBackground;
  final bool silhouetteMatched;

  _MissingMirrorBFPainter({required this.noisyBackground, required this.silhouetteMatched});

  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2 - 50;
    double cy = size.height / 2;

    // Background
    Paint bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    if (noisyBackground) {
      // Draw noisy lines in background
      Paint noisePaint = Paint()..color = Colors.grey[400]!..strokeWidth = 3;
      for (int i = 0; i < 20; i++) {
        canvas.drawLine(Offset(cx - 150 + (i*15), cy - 100), Offset(cx - 100 + (i*15), cy + 150), noisePaint);
      }
    }

    // Motorcycle Shape (Abstract)
    Path bikePath = Path();
    bikePath.moveTo(cx, cy - 50);
    bikePath.lineTo(cx - 40, cy + 20);
    bikePath.lineTo(cx - 30, cy + 100);
    bikePath.lineTo(cx + 30, cy + 100);
    bikePath.lineTo(cx + 40, cy + 20);
    bikePath.close();

    // Mirrors
    bikePath.addOval(Rect.fromCircle(center: Offset(cx - 50, cy - 30), radius: 10)); // left
    bikePath.addOval(Rect.fromCircle(center: Offset(cx + 50, cy - 30), radius: 10)); // right

    Paint bikePaint = Paint()..color = Colors.blueGrey;
    canvas.drawPath(bikePath, bikePaint);

    // Edge Detection Overlay (Right side of screen)
    double rx = cx + 250;
    
    Path edgePath = Path();
    edgePath.moveTo(rx, cy - 50);
    edgePath.lineTo(rx - 40, cy + 20);
    edgePath.lineTo(rx - 30, cy + 100);
    edgePath.lineTo(rx + 30, cy + 100);
    edgePath.lineTo(rx + 40, cy + 20);
    edgePath.close();
    edgePath.addOval(Rect.fromCircle(center: Offset(rx - 50, cy - 30), radius: 10));
    edgePath.addOval(Rect.fromCircle(center: Offset(rx + 50, cy - 30), radius: 10));

    if (noisyBackground) {
      // Corrupt the edge shape
      edgePath.addRect(Rect.fromLTWH(rx - 80, cy - 60, 150, 150));
    }

    Paint edgePaint = Paint()..color = silhouetteMatched ? Colors.green : Colors.red..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawPath(edgePath, edgePaint);

    TextPainter tpEdge = TextPainter(
      text: TextSpan(text: "EDGE\nDETECTION\nOUTPUT", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    tpEdge.layout();
    tpEdge.paint(canvas, Offset(rx - 30, cy + 120));

    // Arrow
    canvas.drawLine(Offset(cx + 80, cy), Offset(rx - 80, cy), Paint()..color = Colors.black..strokeWidth = 4);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
