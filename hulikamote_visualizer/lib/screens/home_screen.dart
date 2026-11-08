import 'package:flutter/material.dart';
import '../models/violation_model.dart';
import '../data/violation_data.dart';
import '../widgets/math_text.dart';
import '../widgets/visualizers/counterflow_bf.dart';
import '../widgets/visualizers/counterflow_fp.dart';
import '../widgets/visualizers/counterflow_setup.dart';
import '../widgets/visualizers/counterflow_visualizer.dart';
import '../widgets/visualizers/illegal_parking_bf.dart';
import '../widgets/visualizers/illegal_parking_fp.dart';
import '../widgets/visualizers/illegal_parking_setup.dart';
import '../widgets/visualizers/illegal_turn_bf.dart';
import '../widgets/visualizers/illegal_turn_fp.dart';
import '../widgets/visualizers/illegal_turn_setup.dart';
import '../widgets/visualizers/illegal_turn_visualizer.dart';
import '../widgets/visualizers/missing_mirror_bf.dart';
import '../widgets/visualizers/missing_mirror_fp.dart';
import '../widgets/visualizers/missing_mirror_setup.dart';
import '../widgets/visualizers/missing_mirror_visualizer.dart';
import '../widgets/visualizers/no_helmet_bf.dart';
import '../widgets/visualizers/no_helmet_fp.dart';
import '../widgets/visualizers/no_helmet_setup.dart';
import '../widgets/visualizers/no_helmet_visualizer.dart';
import '../widgets/visualizers/no_plate_bf.dart';
import '../widgets/visualizers/no_plate_fp.dart';
import '../widgets/visualizers/no_plate_setup.dart';
import '../widgets/visualizers/no_seatbelt_bf.dart';
import '../widgets/visualizers/no_seatbelt_fp.dart';
import '../widgets/visualizers/no_seatbelt_setup.dart';
import '../widgets/visualizers/no_seatbelt_visualizer.dart';
import '../widgets/visualizers/overloading_bf.dart';
import '../widgets/visualizers/overloading_fp.dart';
import '../widgets/visualizers/overloading_setup.dart';
import '../widgets/visualizers/overloading_visualizer.dart';
import '../widgets/visualizers/pedestrian_bf.dart';
import '../widgets/visualizers/pedestrian_fp.dart';
import '../widgets/visualizers/pedestrian_setup.dart';
import '../widgets/visualizers/pedestrian_visualizer.dart';
import '../widgets/visualizers/red_light_bf.dart';
import '../widgets/visualizers/red_light_fp.dart';
import '../widgets/visualizers/red_light_setup.dart';
import '../widgets/visualizers/red_light_visualizer.dart';
import '../widgets/visualizers/swerving_bf.dart';
import '../widgets/visualizers/swerving_fp.dart';
import '../widgets/visualizers/swerving_setup.dart';
import '../widgets/visualizers/swerving_visualizer.dart';
import '../widgets/visualizers/distracted_driving_bf.dart';
import '../widgets/visualizers/distracted_driving_fp.dart';
import '../widgets/visualizers/distracted_driving_setup.dart';
import '../widgets/visualizers/distracted_driving_visualizer.dart';
import '../widgets/visualizers/overspeeding_bf.dart';
import '../widgets/visualizers/overspeeding_fp.dart';
import '../widgets/visualizers/overspeeding_setup.dart';
import '../widgets/visualizers/overspeeding_visualizer.dart';
import '../widgets/visualizers/zone_visualizer.dart';
import '../widgets/visualizers/static_crop_visualizer.dart';
import '../widgets/visualizers/code_math_visualizer.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ViolationModel? selectedViolation;
  int currentPhase = 0; // Defaults to Raw Code & Math

  @override
  void initState() {
    super.initState();
    selectedViolation = violationsData.first;
  }

  Widget _buildTabButton(String text, int phase) {
    bool isSelected = currentPhase == phase;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => currentPhase = phase),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blueGrey[900] : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : Colors.grey[700],
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisualizer(VisualizerType type) {
    if (currentPhase == 0 && selectedViolation != null) {
      return CodeMathVisualizer(violation: selectedViolation!);
    }

    if (type == VisualizerType.counterflow) {
      if (currentPhase == 1) return CounterflowBruteForce();
      if (currentPhase == 2) return CounterflowFirstPrinciple();
      if (currentPhase == 3) return CounterflowSetup();
      if (currentPhase == 4) return CounterflowVisualizer();
    }

    if (type == VisualizerType.zoneOverlap) {
      if (currentPhase == 1) return IllegalParkingBruteForce();
      if (currentPhase == 2) return IllegalParkingFirstPrinciple();
      if (currentPhase == 3) return IllegalParkingSetup();
      if (currentPhase == 4) return ZoneVisualizer();
    }

    if (type == VisualizerType.staticCrop) {
      if (currentPhase == 1) return NoPlateBruteForce();
      if (currentPhase == 2) return NoPlateFirstPrinciple();
      if (currentPhase == 3) return NoPlateSetup();
      if (currentPhase == 4) return StaticCropVisualizer();
    }

    if (type == VisualizerType.illegalTurn) {
      if (currentPhase == 1) return IllegalTurnBruteForce();
      if (currentPhase == 2) return IllegalTurnFirstPrinciple();
      if (currentPhase == 3) return IllegalTurnSetup();
      if (currentPhase == 4) return IllegalTurnVisualizer();
    }

    if (type == VisualizerType.noHelmet) {
      if (currentPhase == 1) return NoHelmetBruteForce();
      if (currentPhase == 2) return NoHelmetFirstPrinciple();
      if (currentPhase == 3) return NoHelmetSetup();
      if (currentPhase == 4) return NoHelmetVisualizer();
    }

    if (type == VisualizerType.missingSideMirror) {
      if (currentPhase == 1) return MissingMirrorBruteForce();
      if (currentPhase == 2) return MissingMirrorFirstPrinciple();
      if (currentPhase == 3) return MissingMirrorSetup();
      if (currentPhase == 4) return MissingMirrorVisualizer();
    }

    if (type == VisualizerType.overloading) {
      if (currentPhase == 1) return OverloadingBruteForce();
      if (currentPhase == 2) return OverloadingFirstPrinciple();
      if (currentPhase == 3) return OverloadingSetup();
      if (currentPhase == 4) return OverloadingVisualizer();
    }

    if (type == VisualizerType.redLightRunning) {
      if (currentPhase == 1) return RedLightBruteForce();
      if (currentPhase == 2) return RedLightFirstPrinciple();
      if (currentPhase == 3) return RedLightSetup();
      if (currentPhase == 4) return RedLightVisualizer();
    }

    if (type == VisualizerType.noSeatbelt) {
      if (currentPhase == 1) return NoSeatbeltBruteForce();
      if (currentPhase == 2) return NoSeatbeltFirstPrinciple();
      if (currentPhase == 3) return NoSeatbeltSetup();
      if (currentPhase == 4) return NoSeatbeltVisualizer();
    }

    if (type == VisualizerType.pedestrianObstruction) {
      if (currentPhase == 1) return PedestrianBruteForce();
      if (currentPhase == 2) return PedestrianFirstPrinciple();
      if (currentPhase == 3) return PedestrianSetup();
      if (currentPhase == 4) return PedestrianVisualizer();
    }

    if (type == VisualizerType.distractedDriving) {
      if (currentPhase == 1) return DistractedDrivingBf();
      if (currentPhase == 2) return DistractedDrivingFp();
      if (currentPhase == 3) return DistractedDrivingSetup();
      if (currentPhase == 4) return DistractedDrivingVisualizer();
    }

    if (type == VisualizerType.swerving) {
      if (currentPhase == 1) return SwervingBruteForce();
      if (currentPhase == 2) return SwervingFirstPrinciple();
      if (currentPhase == 3) return SwervingSetup();
      if (currentPhase == 4) return SwervingVisualizer();
    }

    if (type == VisualizerType.overspeeding) {
      if (currentPhase == 1) return OverspeedingBf();
      if (currentPhase == 2) return OverspeedingFp();
      if (currentPhase == 3) return OverspeedingSetup();
      if (currentPhase == 4) return OverspeedingVisualizer();
    }

    if (currentPhase != 4) {
      return Center(
        child: Text("5-Step Educational Journey for this violation is coming soon.\nPlease click any violation on the left to see the complete pipeline!", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      );
    }

    switch (type) {
      case VisualizerType.swerving:
      case VisualizerType.none:
      default:
        return Center(
          child: Text(
            "Visualizer for this logic coming soon.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Traffic Violation Logic & Physics'),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
      ),
      body: Row(
        children: [
          // SIDEBAR (Master)
          SizedBox(
            width: 300,
            child: Material(
              color: Colors.grey[100],
              child: ListView.builder(
              itemCount: violationsData.length,
              itemBuilder: (context, index) {
                final v = violationsData[index];
                return ListTile(
                  title: Text(v.title, style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(v.category),
                  selected: selectedViolation == v,
                  selectedTileColor: Colors.blue[100],
                  onTap: () {
                    setState(() {
                      selectedViolation = v;
                    });
                  },
                );
              },
            ),
          ),
        ),
          
          // MAIN CONTENT (Detail)
          Expanded(
            child: selectedViolation == null
                ? Center(child: Text("Select a violation"))
                : Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(selectedViolation!.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text(selectedViolation!.definition, style: TextStyle(fontSize: 16, color: Colors.grey[700])),
                          SizedBox(height: 24),
                          
                          // 5-STEP JOURNEY TOGGLE
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                _buildTabButton("💻 1. Raw Code & Math", 0),
                                _buildTabButton("🔴 2. Naive Sim", 1),
                                _buildTabButton("🧠 3. Core Concept", 2),
                                _buildTabButton("⚙️ 4. Real-World Setup", 3),
                                _buildTabButton("🟢 5. Modern AI", 4),
                              ],
                            ),
                          ),
                          SizedBox(height: 16),
                          
                          // VISUALIZER
                          Container(
                            height: 550,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _buildVisualizer(selectedViolation!.visualizerType),
                          ),
                          SizedBox(height: 24),

                          // COMPARISON
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildInfoCard(
                                  "🔴 Brute Force", 
                                  selectedViolation!.bruteForce, 
                                  Colors.red[50]!, 
                                  Colors.red[900]!
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: _buildInfoCard(
                                  "🟢 Optimized Industry Logic", 
                                  selectedViolation!.optimizedLogic, 
                                  Colors.green[50]!, 
                                  Colors.green[900]!
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 24),

                          // MATH & TOOLS
                          Text("Mathematical Formula", style: Theme.of(context).textTheme.titleLarge),
                          SizedBox(height: 8),
                          MathText(latexCode: selectedViolation!.mathLatex),
                          SizedBox(height: 24),

                          Text("Recommended Free Tools", style: Theme.of(context).textTheme.titleLarge),
                          SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: selectedViolation!.tools.map((t) => Chip(label: Text(t))).toList(),
                          )
                        ],
                      ),
                    ),
                  ),
          )
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String content, Color bgColor, Color textColor) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.3))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
          SizedBox(height: 8),
          Text(content, style: TextStyle(height: 1.5, fontSize: 15)),
        ],
      ),
    );
  }
}
