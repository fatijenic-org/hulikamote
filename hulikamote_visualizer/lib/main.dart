import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(HuliKamoteVisualizerApp());
}

class HuliKamoteVisualizerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Huli Kamote - Logic Visualizer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        fontFamily: 'Segoe UI',
      ),
      home: HomeScreen(),
    );
  }
}
