import 'package:flutter/material.dart';

import 'home_page.dart';

void main() => runApp(const CameraApp());

class CameraApp extends StatelessWidget {
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HULI-KAMOTE Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F8CFF), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0B1220),
      ),
      home: const HomePage(),
    );
  }
}
