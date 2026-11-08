enum VisualizerType {
  counterflow,
  zoneOverlap,
  swerving,
  staticCrop,
  illegalTurn,
  noHelmet,
  missingSideMirror,
  overloading,
  redLightRunning,
  noSeatbelt,
  pedestrianObstruction,
  distractedDriving,
  overspeeding,
  none,
}

class ViolationVisualizerModel {
  final String id;
  final String title;
  final String category;
  final String definition;
  final String bruteForce;
  final String optimizedLogic;
  final String mathLatex;
  final List<String> tools;
  final VisualizerType visualizerType;

  const ViolationVisualizerModel({
    required this.id,
    required this.title,
    required this.category,
    required this.definition,
    required this.bruteForce,
    required this.optimizedLogic,
    required this.mathLatex,
    required this.tools,
    this.visualizerType = VisualizerType.none,
  });
}
