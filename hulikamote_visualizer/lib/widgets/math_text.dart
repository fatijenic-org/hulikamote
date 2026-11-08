import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class MathText extends StatelessWidget {
  final String latexCode;

  const MathText({Key? key, required this.latexCode}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!)
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Math.tex(
          latexCode,
          textStyle: TextStyle(fontSize: 22, color: Colors.black87),
        ),
      ),
    );
  }
}
