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

/// Violation Physics: the 13 violation lessons from the standalone visualizer app,
/// each with five steps (code & math, naive simulation, core concept, setup, modern AI).
///
/// The page around the lesson follows the dashboard theme. The simulation stage itself
/// is drawn on a light canvas (the lessons hard-code light colors), so it sits in its own
/// light theme island.
class ViolationLabScreen extends StatefulWidget {
  const ViolationLabScreen({super.key});

  @override
  State<ViolationLabScreen> createState() => _ViolationLabScreenState();
}

class _ViolationLabScreenState extends State<ViolationLabScreen> {
  static const _steps = [
    '1. Code & Math',
    '2. Naive Simulation',
    '3. Core Concept',
    '4. Real-World Setup',
    '5. Modern AI',
  ];

  ViolationModel? selectedViolation;
  int currentPhase = 0;

  @override
  void initState() {
    super.initState();
    selectedViolation = violationsData.first;
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
    final scheme = Theme.of(context).colorScheme;
    final v = selectedViolation!;
    return Row(
      children: [
        SizedBox(
          width: 260,
          child: Container(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: scheme.outlineVariant)),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: violationsData.length,
              itemBuilder: (context, index) {
                final item = violationsData[index];
                return ListTile(
                  dense: true,
                  title: Text(item.title),
                  subtitle: Text(item.category),
                  selected: item == v,
                  selectedTileColor: scheme.primary.withValues(alpha: 0.12),
                  onTap: () => setState(() => selectedViolation = item),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(v.definition, style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    for (var i = 0; i < _steps.length; i++)
                      _StepTab(
                        label: _steps[i],
                        isSelected: currentPhase == i,
                        onTap: () => setState(() => currentPhase = i),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 550,
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Theme(
                    data: ThemeData(brightness: Brightness.light, primarySwatch: Colors.blueGrey),
                    child: Material(color: Colors.white, child: _buildVisualizer(v.visualizerType)),
                  ),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(builder: (context, c) {
                  final cards = [
                    _InfoCard(title: 'Brute force', content: v.bruteForce),
                    _InfoCard(title: 'Optimized industry logic', content: v.optimizedLogic),
                  ];
                  return c.maxWidth < 700
                      ? Column(children: [cards[0], const SizedBox(height: 12), cards[1]])
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])],
                        );
                }),
                const SizedBox(height: 20),
                Text('Formula', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                MathText(latexCode: v.mathLatex),
                const SizedBox(height: 20),
                Text('Free tools', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: v.tools.map((t) => Chip(label: Text(t))).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _StepTab({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: isSelected ? scheme.primary : scheme.outlineVariant, width: isSelected ? 2 : 1),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String content;

  const _InfoCard({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(content, style: TextStyle(height: 1.5, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
