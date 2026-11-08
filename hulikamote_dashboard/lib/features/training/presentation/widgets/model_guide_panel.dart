import 'package:flutter/material.dart';

class _Step {
  final String title, body;
  const _Step(this.title, this.body);
}

class _Guide {
  final String what, why, usedIn;
  final List<_Step> steps;
  final List<String> goodResult, problems;
  const _Guide({required this.what, required this.why, required this.usedIn, required this.steps, required this.goodResult, required this.problems});
}

// One shared tail so every guide ends the same way.
const _deployStep = _Step('Switch to it on the Models page',
    'Training only adds a new version; nothing goes live by itself. On the Models page compare its score with the live one and press Use this. '
    'A detector applies from the next analysis; the car matcher needs a backend restart. '
    '(The plate reader and the enhancer still put themselves to work after training: restart the backend to load them.)');

const _yoloZipStep = _Step('Prepare a labeled dataset (ZIP)',
    'You need photos with boxes drawn on the things to find, saved in YOLO format. Make the ZIP contain two folders: "images" (the photos) '
    'and "labels" (one .txt file per photo, same name). Tools like Roboflow or CVAT can label photos and export in "YOLO" format. '
    'Public datasets from Roboflow Universe or Kaggle also work.');

const Map<String, _Guide> _guides = {
  'plate_specialist': _Guide(
    usedIn: 'After the main detector finds a vehicle, this model scans the lower part of that vehicle every few frames and cuts out a photo of the plate. Those plate photos are saved for each car, linked to the evidence frame taken at the same moment, and later handed to the Plate Reader (OCR). If this model misses or boxes the wrong spot, the reader has nothing good to read.',
    what: 'Finds the license plate on a car so it can be cropped and read.',
    why: 'If the plate box is wrong or missing, the plate reader never gets a good picture. Better boxes = better plate reads.',
    steps: [
      _yoloZipStep,
      _Step('Upload it here', 'Press Train new version, then "Replace dataset with a ZIP...". This REPLACES the current plate data, so keep a copy of the old one if you want it.'),
      _Step('Check the data card', 'It should say "Ready" (300+ images is recommended). Orange means it works but may be weak.'),
      _Step('Choose how long', 'Pick Quick to test that everything works, then Balanced or Thorough for the real run. Leave Advanced alone unless you know what it does.'),
      _Step('Press Start training', 'Watch the progress bar. This can take a long time on a large dataset. You can leave the screen on; do not close the app.'),
      _Step('Read the result', 'Open the version on the Models page. Look at the score (mAP50): closer to 1.0 is better. Compare with the previous run before trusting the new one.'),
      _deployStep,
    ],
    goodResult: ['mAP50 above about 0.7 is usable; above 0.85 is strong.', 'The new version scores higher than the live one on the Models page.'],
    problems: ['Training stops at once: the ZIP is missing images/ or labels/ folders, or the labels are not YOLO format.', 'Score is low: add more varied photos (night, rain, blur, different angles) and train again.'],
  ),
  'helmet_specialist': _Guide(
    usedIn: 'When the main detector finds a motorcycle, this model checks the rider on that crop. Its answers are collected over several frames and voted on before a No Helmet violation is added to the car\'s ticket, so one bad frame does not create a ticket.',
    what: 'Looks at motorcycle crops and finds riders with or without a helmet.',
    why: 'This decides the No Helmet violation. It needs many examples of both helmeted and bare-headed riders.',
    steps: [
      _yoloZipStep,
      _Step('Use the right classes', 'Label two things: rider with helmet, and rider without helmet. Keep the names the same across the whole dataset.'),
      _Step('Upload it here', 'Train new version, then "Replace dataset with a ZIP...". Public helmet datasets from Roboflow Universe or Kaggle are a good way to start (your roadmap suggests this).'),
      _Step('Check the data card', 'Aim for 300+ images with a fair mix of both classes.'),
      _Step('Train', 'Start with Quick to confirm it runs, then Balanced.'),
      _Step('Read the result', 'Models page: check the score, then test it on a real video in the Forensic Analyzer.'),
      _deployStep,
    ],
    goodResult: ['mAP50 above about 0.7.', 'On a real video it rarely mixes up helmets and caps.'],
    problems: ['It calls everything "helmet": your data has far more helmet photos than bare-head photos. Balance the two.', 'Zero images shown: nothing has been uploaded yet.'],
  ),
  'cabin_specialist': _Guide(
    usedIn: 'When the main detector finds a car, this model looks through the windshield crop for seatbelt, phone, window type and side mirrors. Those results decide the Seatbelt, Distracted Driving and Missing Side Mirror violations.',
    what: 'Looks inside car windshields for seatbelts, phones and clear or tinted windows.',
    why: 'This supports the Seatbelt and Distracted Driving checks.',
    steps: [
      _yoloZipStep,
      _Step('Label what matters', 'Classes used by the system: clear window, tinted window, seatbelt, driver phone, side mirror.'),
      _Step('Upload it here', 'Train new version, then "Replace dataset with a ZIP...".'),
      _Step('Check the data card', 'Aim for 300+ images, including tinted windows and phone-in-hand cases.'),
      _Step('Train', 'Quick first to test, then Balanced.'),
      _Step('Read the result', 'Models page: check the score (mAP50).'),
      _deployStep,
    ],
    goodResult: ['mAP50 above about 0.7.'],
    problems: ['Phone is missed: add more examples of phones held at different heights and angles.'],
  ),
  'primary_anchor': _Guide(
    usedIn: 'This is Stage 1 (Detection) and runs on the video constantly. Its boxes go to DeepSORT for tracking and are tested against your drawn zones (counterflow, illegal parking, restricted lane). The plate, helmet and cabin models only run on the vehicles it finds.',
    what: 'The main detector that finds every car, motorcycle, bus and truck.',
    why: 'Everything else depends on it. The standard pretrained version is already good, so you usually do NOT need to train it.',
    steps: [
      _Step('Decide if you really need it', 'Only train this if the system keeps missing local vehicles (for example jeepneys or tricycles) that the standard model does not know.'),
      _yoloZipStep,
      _Step('Upload it here', 'Train new version, then "Replace dataset with a ZIP...". Include the vehicle types you are missing.'),
      _Step('Check the data card', 'This model needs more data: 500+ images recommended.'),
      _Step('Train and read the result', 'Use Balanced or Thorough. Compare the score on the Models page with the live model before pressing Use this.'),
      _deployStep,
    ],
    goodResult: ['Your local vehicle types are detected reliably.', 'Standard vehicles (car, bus, truck) are not detected worse than before.'],
    problems: ['Standard vehicles got worse: the new dataset was too narrow. Include normal cars and buses too.'],
  ),
  'plate_ocr': _Guide(
    usedIn: 'This is Stage 3 (Recognition). After the video ends, every saved plate photo is read, the readings vote, and the winner becomes the ticket\'s plate. The plate you see on the evidence frames, and the "Plate:" label, come from here. Your confirm / wrong / correct clicks under each plate crop are what train it.',
    what: 'Reads the letters and numbers on a plate photo.',
    why: 'Even with a perfect plate box, wrong letters mean the wrong driver. This teaches the reader your local plate fonts and spacing.',
    steps: [
      _Step('Gather data while you review', 'Run a video in the Forensic Analyzer and open a ticket\'s evidence. Under each plate crop there are buttons: confirm it is right, mark it wrong (not a plate), or type the correct plate. Every click is saved automatically.'),
      _Step('Be accurate', 'Wrong corrections teach the wrong thing. Only click when you are sure.'),
      _Step('Collect enough', 'Aim for 200+ crops. Include hard ones: night, blur, dirty or angled plates.'),
      _Step('Check the data card', 'It counts the plate crops saved so far. No upload is needed; this model reads that folder by itself.'),
      _Step('Pick the engine and train', 'EasyOCR is the standard choice. Start with Quick to test, then Balanced.'),
      _Step('Check the result', 'Run the same video again in the Forensic Analyzer and compare the plate reads with before.'),
      _deployStep,
    ],
    goodResult: ['More plates read correctly on a video it has not trained on.', 'Fewer "unidentified" plates.'],
    problems: ['Error about no data: no corrections have been saved yet. Review some tickets first.', 'Results got worse: too few or mistaken corrections. Collect more and retrain.'],
  ),
  'reid': _Guide(
    usedIn: 'This is inside Stage 2 (Tracking). For every car box, DeepSORT asks this model for a "fingerprint" and compares fingerprints between frames to decide: same car or a new one. When the fingerprints are weak you get the problems you fix by hand: one car with two tickets (merge) or two cars in one ticket (separate). Your merge / separate answers are exactly the examples it learns from.',
    what: 'Tells whether two photos show the SAME car. DeepSORT uses this to keep one ID per car.',
    why: 'The current version was trained on people, so it mixes up cars. Training it on your own review decisions reduces duplicate tickets.',
    steps: [
      _Step('Gather data while you review', 'In the Forensic Analyzer open an analysis, go to Harvest and open Same car?. Open a car, press D on the photos that show a different car, press Done. When the cars that look wrong are done, press "Rest are fine" for all the others. (Merge / Separate on a ticket also save cars.) Each car is saved as a folder of clean photos.'),
      _Step('Be accurate', 'A wrong merge or split teaches wrong things. Only decide when you can see it clearly.'),
      _Step('Collect enough', 'It needs at least 5 cars with 2+ photos to run at all, and 8+ to be tested for replacing your model (fewer cannot be tested on cars it has not seen). 30+ cars is recommended, and more is much better.'),
      _Step('Check the data card', 'It shows how many cars have 2 or more photos.'),
      _Step('Train', 'Quick to test, then Balanced. No upload needed.'),
      _Step('Read the result', 'A quarter of your cars are kept out of the training. The result shows how often the right car is found, before and after, on those cars it never saw. The page marks it as passed only if it is clearly better there. Nothing goes live until you press Use this.'),
      _deployStep,
    ],
    goodResult: ['"After" is higher than "before" and the version is marked Passed the check.', 'Fewer duplicate tickets for the same car in your next analysis.'],
    problems: ['Did not pass the check: it was not better. Collect more cars from different videos and try again.', 'Error about needing 5 cars: keep reviewing tickets (merge / separate) first.'],
  ),
  'plate_enhancer': _Guide(
    usedIn: 'It sits between the Plate Detector and the Plate Reader. Each plate photo is enlarged and sharpened first (that is the "Enhanced" image under each crop in the evidence dialog), and the reader reads the sharpened version.',
    what: 'Sharpens blurry plate photos before they are read (Real-ESRGAN).',
    why: 'Clearer plates give the reader a better chance. This is advanced and experimental.',
    steps: [
      _Step('Know what it uses', 'It builds blurry/sharp training pairs from the Plate Detector\'s dataset, so that dataset must exist first (3,000+ plate images is ideal).'),
      _Step('Check the data card', 'It shows the plate dataset size it will use.'),
      _Step('Train', 'It installs extra packages the first time and can fail on newer PyTorch versions. If it fails, open the training log.'),
      _Step('Check the result', 'It exports an ONNX model. Compare a few plates before and after in the Forensic Analyzer.'),
      _deployStep,
    ],
    goodResult: ['Plates look sharper and the reads improve.'],
    problems: ['Fails with a package or torchvision error: this is the known compatibility problem. Ask a developer to check the log.'],
  ),
};

/// Plain-language, end-to-end guide for one model: gather data, train, check, deploy.
class ModelGuidePanel extends StatelessWidget {
  final String modelKey;
  const ModelGuidePanel({super.key, required this.modelKey});

  @override
  Widget build(BuildContext context) {
    final g = _guides[modelKey];
    if (g == null) return const Text('No guide for this model yet.');
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('What it does', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(g.what),
            const SizedBox(height: 10),
            const Text('Why it matters', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(g.why),
            const SizedBox(height: 10),
            const Text('Where it is used in the system', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(g.usedIn),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Text('Step by step', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      for (var i = 0; i < g.steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.steps[i].title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(g.steps[i].body, style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          ]),
        ),
      const SizedBox(height: 8),
      _bullets(context, 'What a good result looks like', Icons.check_circle, Colors.green, g.goodResult),
      const SizedBox(height: 8),
      _bullets(context, 'If something goes wrong', Icons.help, Colors.orange, g.problems),
    ]);
  }

  Widget _bullets(BuildContext context, String title, IconData icon, Color color, List<String> items) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 6),
          for (final t in items) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('-  $t')),
        ]),
      ),
    );
  }
}
