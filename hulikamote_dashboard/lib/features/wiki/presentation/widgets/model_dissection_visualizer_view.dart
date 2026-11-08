import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ═════════════════════════════════════════════════════════════════════════════
// MODEL ANATOMY & DISSECTION VISUALIZER (LOW-COGNITIVE-LOAD EDITION)
// Progressive disclosure:
// • Default view shows ONLY the visual animation + a short layman takeaway.
// • Every technical detail (Deep Layer Specs, Tensor Math, Code Paths, Full
//   Layman Story, and Macro System Cascade) is preserved 100% and shown on
//   demand via Hover Popovers or Click Dialogs.
// ═════════════════════════════════════════════════════════════════════════════

enum _DissectFamily {
  yoloFull,
  yoloCrop,
  reidTracker,
  ocrReader,
  srEnhancer,
}

enum _BlockCanvasKind {
  yoloLetterbox,
  yoloBackbone,
  yoloNeckPanet,
  yoloDecoupledHead,
  yoloNmsUnbox,
  reidPatchStem,
  reidResBlocks,
  reidUnitSphere,
  reidKalmanHungarian,
  ocrTpsUnwarp,
  ocrFeatureSlices,
  ocrSequenceBilstm,
  ocrCtcDecode,
  srShallowExtract,
  srRrdbBlocks,
  srPixelShuffle4x,
  srLapSrnPyramid,
}

class _DissectModelSpec {
  final String id;
  final String label;
  final String roleTag;
  final _DissectFamily family;
  final String filePath;
  final String engineFile;
  final String inputShape;
  final String outputShape;
  final String cadence;
  final String shortSummary;
  final String laymanAnalogy;
  final String macroRole;
  final List<String> classesOrOutputs;

  const _DissectModelSpec({
    required this.id,
    required this.label,
    required this.roleTag,
    required this.family,
    required this.filePath,
    required this.engineFile,
    required this.inputShape,
    required this.outputShape,
    required this.cadence,
    required this.shortSummary,
    required this.laymanAnalogy,
    required this.macroRole,
    required this.classesOrOutputs,
  });
}

class _DissectBlockSpec {
  final int index;
  final String numLabel;
  final String navLabel;
  final String title;
  final String shortDigest;
  final String codeLocation;
  final String laymanExplanation;
  final String microMechanics;
  final String tensorIn;
  final String tensorOut;
  final List<(String, String)> layerSpecs;
  final _BlockCanvasKind canvasKind;

  const _DissectBlockSpec({
    required this.index,
    required this.numLabel,
    required this.navLabel,
    required this.title,
    required this.shortDigest,
    required this.codeLocation,
    required this.laymanExplanation,
    required this.microMechanics,
    required this.tensorIn,
    required this.tensorOut,
    required this.layerSpecs,
    required this.canvasKind,
  });
}

class ModelDissectionVisualizerView extends StatefulWidget {
  const ModelDissectionVisualizerView({super.key});

  @override
  State<ModelDissectionVisualizerView> createState() =>
      _ModelDissectionVisualizerViewState();
}

class _ModelDissectionVisualizerViewState
    extends State<ModelDissectionVisualizerView>
    with TickerProviderStateMixin {
  static const Color _kSignalBlue = Color(0xFF3B82F6);
  static const Color _kSemanticPass = Color(0xFF10B981);

  String _selectedModelId = 'primary_anchor';
  int _activeBlock = 0;
  bool _isAutoPlaying = false;
  double _playbackSpeed = 1.0;

  // View breakdown mode: true = Single Focused Block (calmest), false = All Blocks Scroll
  bool _singleBlockFocusMode = true;

  // Interactive micro toggles inside block canvases
  int _selectedFpnScale = 0; // 0: P3 (small), 1: P4 (medium), 2: P5 (large)
  bool _showLetterboxFix = true; // True: RGB + 114 pad (85%), False: stretched BGR (7%)
  int _selectedOcrArch = 0; // 0: EasyOCR CRNN, 1: PaddleOCR SVTR
  int _selectedSrArch = 0; // 0: Real-ESRGAN 6-RRDB x4, 1: LapSRN Pyramid x8

  late final AnimationController _pulseController;
  late final ScrollController _scrollController;
  List<GlobalKey> _blockKeys = List.generate(5, (_) => GlobalKey());

  static const List<_DissectModelSpec> _models = [
    _DissectModelSpec(
      id: 'primary_anchor',
      label: 'Primary Anchor (YOLOv8n)',
      roleTag: 'Stage 1 · Full-Frame Scout',
      family: _DissectFamily.yoloFull,
      filePath: 'models/Vehicle Detectors/yolov8n.onnx',
      engineFile: 'hulikamote_backend/yolo_inference.py',
      inputShape: '[1, 3, 640, 640] RGB',
      outputShape: '[1, 84, 8400] → NMS boxes',
      cadence: 'Every inferred frame (~10–15 FPS)',
      shortSummary:
          'Wide-angle overpass spotter: scans the whole 640×640 street scene to circle every vehicle and person so specialists know where to zoom in.',
      laymanAnalogy:
          'Think of Primary Anchor as the wide-angle spotter standing on an overpass. It does not squint to read tiny license plate letters or check seatbelts—its only job is to quickly circle every car, motorcycle, bus, truck, and person in the 4K street scene so the specialist models know exactly where to zoom in.',
      macroRole:
          'Receives the raw CCTV frame, resizes it to 640×640, and outputs bounding boxes for vehicles and riders. Motorcycle confidence is lowered to 0.25 (vs 0.45 default) so distant bikes are never missed.',
      classesOrOutputs: [
        '0: person (paired with motorcycles via rider_boxes)',
        '1: bicycle',
        '2: car (CONF >= 0.45)',
        '3: motorcycle (CONF >= 0.25 CCTV override)',
        '5: bus',
        '7: truck',
      ],
    ),
    _DissectModelSpec(
      id: 'helmet_specialist',
      label: 'Helmet Specialist',
      roleTag: 'Stage 2A · Rider Safety Magnifier',
      family: _DissectFamily.yoloCrop,
      filePath: 'models/Helmet Detectors/helmet_specialist.onnx',
      engineFile: 'engine/specialist_jobs.py (HelmetJob)',
      inputShape: '[1, 3, 320, 320] Letterboxed RGB',
      outputShape: '[1, 6, 2100] → 2 classes',
      cadence: 'Every 5th frame on motorcycles',
      shortSummary:
          'Glues the motorcycle + rider boxes together, pads with neutral grey (114) to keep helmet proportions round, and checks for a helmet.',
      laymanAnalogy:
          'If you only cut out the metal motorcycle, you chop off the rider\'s head! HelmetJob first glues the motorcycle box and all overlapping person boxes together into one tall crop, pads the sides with neutral grey (114) so the helmet isn\'t squashed into an oval, and checks if the rider is wearing a helmet.',
      macroRole:
          'Triggered by HelmetJob whenever "no_helmet" is active and Primary Anchor sees a motorcycle. Combines bike + rider boxes via rider_boxes(), runs 320×320 inference at CHECK_CONF=0.40, and maps detections back to full-frame coordinates.',
      classesOrOutputs: [
        '0: rider_with_helmet (Safe — compliant)',
        '1: rider_without_helmet (Triggers no_helmet violation judge)',
      ],
    ),
    _DissectModelSpec(
      id: 'plate_specialist',
      label: 'Plate Specialist',
      roleTag: 'Stage 2B · License Plate Finder',
      family: _DissectFamily.yoloCrop,
      filePath: 'models/Plate Models/plate_specialist.onnx',
      engineFile: 'engine/specialist_jobs.py (PlateJob)',
      inputShape: '[1, 3, 320, 320] Letterboxed RGB',
      outputShape: '[1, 5, 2100] → 1 class (plate)',
      cadence: 'Every 5th frame on ALL vehicles',
      shortSummary:
          'Scans the whole vehicle crop at a forgiving 0.10 threshold, cutting out up to 40 tight plate snapshots (+10% margin) for OCR voting.',
      laymanAnalogy:
          'A magnifying glass that scans the entire vehicle body—not just the bottom bumper, because angled CCTV cameras put half of all motorcycle and truck plates higher up. It uses a very forgiving threshold (0.10) so even blurry or mud-splattered plates get cut out (+10% margin) and saved into a 40-photo ballot box for the OCR reader.',
      macroRole:
          'Runs on every vehicle regardless of violation type so every ticket gets a plate number. Extracts a tight crop (+10% margin) plus an anonymized vehicle context image and stores up to MAX_PLATE_CROPS=40 per vehicle track.',
      classesOrOutputs: [
        '0: license_plate (Searched at SEARCH_CONF = 0.10)',
      ],
    ),
    _DissectModelSpec(
      id: 'cabin_specialist',
      label: 'Cabin Specialist',
      roleTag: 'Stage 2C · Windshield & Mirror Inspector',
      family: _DissectFamily.yoloCrop,
      filePath: 'models/Cabin Models/cabin_specialist.onnx',
      engineFile: 'engine/specialist_jobs.py (CabinJob)',
      inputShape: '[1, 3, 320, 320] Letterboxed RGB',
      outputShape: '[1, 9, 2100] → 5 cabin classes',
      cadence: 'Every 5th frame when cabin rules active',
      shortSummary:
          'One 320×320 look serves three traffic laws at once: checks windshield tint, seatbelts, driver phones, and motorcycle side mirrors.',
      laymanAnalogy:
          'One single look inside the vehicle serves three different traffic laws at once. Instead of running three separate models for seatbelts, cellphones, and side mirrors, Cabin Specialist takes one 320×320 snapshot of the vehicle and spots all five interior/exterior clues simultaneously—including whether the windshield is too darkly tinted to see inside.',
      macroRole:
          'Shared across no_seatbelt, distracted_driving, and missing_side_mirror judges. If tinted_window is detected without a clear_window, the seatbelt judge knows the cabin is occluded rather than falsely accusing the driver.',
      classesOrOutputs: [
        '0: clear_window (Interior visible — enables seatbelt check)',
        '1: tinted_window (Heavy tint — prevents false seatbelt tickets)',
        '2: seatbelt (Presence = compliant; absence in clear window = violation)',
        '3: driver_phone (Triggers distracted_driving)',
        '4: side_mirror (Checked on motorcycles for missing_side_mirror)',
      ],
    ),
    _DissectModelSpec(
      id: 'reid_deepsort',
      label: 'Vehicle ReID (DeepSORT Net)',
      roleTag: 'Stage 1B · Visual Fingerprint & Tracker',
      family: _DissectFamily.reidTracker,
      filePath: 'engine/deep_sort/deep/checkpoint/ckpt.t7',
      engineFile: 'engine/deep_sort/deep/model.py + tracker.py',
      inputShape: '[B, 3, 192, 96] RGB crop',
      outputShape: '[B, 512] L2 unit vector',
      cadence: 'Every frame on every detected vehicle',
      shortSummary:
          'Turns each vehicle into a 512-number visual fingerprint + Kalman physics trajectory so cars keep their exact Track ID even after occlusion.',
      laymanAnalogy:
          'When a jeepney passes behind a bus for two seconds, how does the system know it\'s the same jeepney when it reappears—and not issue a second ticket? DeepSORT combines a physics predictor (Kalman Filter guessing where the car moved) with a 512-number "visual fingerprint" (paint color, roof rack, decals, silhouette) so the vehicle keeps its exact Track ID.',
      macroRole:
          'Converts each vehicle crop into a 512-D unit embedding vector and matches detections across frames using Cosine Distance (max_dist=0.40) + Kalman Mahalanobis gate + IoU fallback (lost_track_buffer=90 frames).',
      classesOrOutputs: [
        '512-D L2-Normalized Appearance Vector (when net.reid = True)',
        'Track ID assignment (n_init = 3 confirmed frames, max_age = 90)',
      ],
    ),
    _DissectModelSpec(
      id: 'plate_enhancer',
      label: 'Plate Enhancer (Real-ESRGAN / LapSRN)',
      roleTag: 'Stage 3A · Neural Super-Resolution Upscaler',
      family: _DissectFamily.srEnhancer,
      filePath: 'models/GAN Enhancers/realesrgan.onnx + LapSRN_x8.pb',
      engineFile: 'engine/pipeline.py (_apply_realesrgan / _apply_super_resolution)',
      inputShape: '[1, 3, H, W] float32 RGB',
      outputShape: '[1, 3, 4H, 4W] / [8H, 8W]',
      cadence: 'Pass 2 / Forensic Reread before OCR',
      shortSummary:
          'Reconstructs crisp alphanumeric character strokes from blurry 32px plate crops using a 6-block RRDB GAN (×4) or LapSRN pyramid (×8).',
      laymanAnalogy:
          'Standard photo zooming (Bicubic/Lanczos) just stretches blurry grey squares into bigger blurry grey squares. Real-ESRGAN has studied thousands of sharp Philippine license plates—so when it sees a tiny 32-pixel smudge, its 6 dense residual blocks reconstruct crisp diagonal strokes on "A", "4", "8", and "B" before handing the plate to the OCR reader.',
      macroRole:
          'Upscales low-resolution plate crops by 4× (Real-ESRGAN 6-block RRDBNet) or 8× (LapSRN Laplacian Pyramid) prior to character recognition, falling back gracefully to Lanczos4 if ONNX is absent.',
      classesOrOutputs: [
        'Real-ESRGAN: ×4 RGB super-resolved plate (6 RRDB blocks, 32 feat, 16 grow)',
        'LapSRN: ×8 progressive pyramid upscaled plate (LapSRN_x8.pb)',
      ],
    ),
    _DissectModelSpec(
      id: 'plate_ocr',
      label: 'Plate OCR (EasyOCR CRNN / Paddle SVTR)',
      roleTag: 'Stage 3B · Sequence Alphanumeric Reader',
      family: _DissectFamily.ocrReader,
      filePath: 'models/easyocr_custom_rec.pth + paddleocr_rec_inference/',
      engineFile: 'engine/pipeline.py (_extract_plate_text)',
      inputShape: '[1, 1, 32, 100] / [1, 3, 32, 320]',
      outputShape: '36-char string + syntax vote',
      cadence: 'Pass 2 multi-crop voting & Pop Quiz',
      shortSummary:
          'Un-warps tilted plates flat (TPS), scans vertical slices left-to-right like a barcode, repairs look-alike characters, and votes across 40 crops.',
      laymanAnalogy:
          'Instead of trying to draw a tiny box around each individual letter on a tilted plate, Plate OCR first flattens the angled plate like ironing a crooked sticker (TPS), slices it from left to right like a barcode scanner, and reads the whole character sequence at once—then applies Philippine plate syntax rules (turning "O" into "0" in the number slots).',
      macroRole:
          'Reads up to 40 enhanced plate crops per vehicle track, restricts output to 36 alphanumeric characters, repairs look-alike characters by position (ph_standard LLL-DDDD), and votes across frames in ticket_merge.py.',
      classesOrOutputs: [
        '36-char vocabulary: 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        'Positional syntax repair: ph_standard (0..2 → letters, 3..6 → digits)',
      ],
    ),
  ];

  _DissectModelSpec get _currentModel =>
      _models.firstWhere((m) => m.id == _selectedModelId, orElse: () => _models.first);

  List<_DissectBlockSpec> _buildBlocksForModel(_DissectModelSpec m) {
    switch (m.family) {
      case _DissectFamily.yoloFull:
      case _DissectFamily.yoloCrop:
        final isFull = m.family == _DissectFamily.yoloFull;
        final sz = isFull ? 640 : 320;
        final grids = isFull ? '8400 (80² + 40² + 20²)' : '2100 (40² + 20² + 10²)';
        final cCount = m.id == 'primary_anchor'
            ? 80
            : m.id == 'helmet_specialist'
                ? 2
                : m.id == 'plate_specialist'
                    ? 1
                    : 5;
        return [
          _DissectBlockSpec(
            index: 0,
            numLabel: 'B1',
            navLabel: '1. Input & Letterbox',
            title: isFull
                ? 'Full-Frame 640×640 RGB Normalization & Motorcycle Cutoff'
                : 'Aspect-Preserving Grey Letterbox (PAD=114) & BGR→RGB Swap',
            shortDigest: isFull
                ? 'Resizes the street frame into a 640×640 square, swaps BGR→RGB, and scales pixels to 0..1.'
                : 'Shrinks the crop without stretching and fills borders with neutral grey (114)—boosting plate recall from 7% to 85%.',
            codeLocation: isFull
                ? 'yolo_inference.py (preprocess)'
                : 'engine/specialists.py :: letterbox(crop, size=320)',
            laymanExplanation: isFull
                ? 'A neural network can only digest a fixed grid of numbers between 0 and 1. We shrink the 1080p/4K street video into a 640×640 square, flip OpenCV\'s Blue-Green-Red color order into Red-Green-Blue, and divide pixel brightness by 255.'
                : 'Imagine squashing a tall motorcycle rider into a square frame—their round helmet gets flattened into a pancake, confusing the AI! Instead, letterbox() shrinks the crop until its longest side hits 320px and fills the leftover margins with neutral grey (114). Fixing stretched BGR to letterboxed RGB jumped plate accuracy from 7% to 85%!',
            microMechanics: isFull
                ? 'scale = min(640/w, 640/h); pad with 114; BGR→RGB; float32 / 255.0 → contiguous NCHW tensor [1, 3, 640, 640].'
                : 'scale = min(320/w, 320/h); pad_x = (320 - new_w)//2; pad_y = (320 - new_h)//2; canvas filled with 114; rgb = canvas[:,:,::-1]; blob = rgb.transpose(2,0,1)[None] / 255.0.',
            tensorIn: isFull ? 'BGR Frame [H, W, 3]' : 'Crop [crop_h, crop_w, 3]',
            tensorOut: 'Blob [1, 3, $sz, $sz]',
            layerSpecs: [
              ('Scale factor', 'scale = min($sz / w, $sz / h) (preserves aspect ratio)'),
              ('Padding constant', 'PAD_VALUE = 114 (Ultralytics neutral grey border)'),
              ('Channel order', 'BGR → RGB reversal (canvas[:, :, ::-1])'),
              ('Measured impact', isFull
                  ? 'CLASS_CONFIDENCE["motorcycle"] = 0.25 (vs 0.45 default)'
                  : '7% recall (stretched BGR) → 85% recall (letterboxed RGB)'),
            ],
            canvasKind: _BlockCanvasKind.yoloLetterbox,
          ),
          _DissectBlockSpec(
            index: 1,
            numLabel: 'B2',
            navLabel: '2. CSPDarknet Backbone',
            title: 'Stem Stride-2 Downsampling, C2f Bottlenecks, and SPPF Pooling',
            shortDigest:
                'Extracts visual features from simple edges up to full vehicle parts while C2f shortcut highways keep gradients strong.',
            codeLocation: 'ultralytics/nn/modules/block.py (Conv, C2f, SPPF)',
            laymanExplanation:
                'The Backbone is the visual cortex. Early layers act like edge detectors—spotting simple lines, curves, and metallic reflections. Deeper C2f blocks combine those edges into tires, windshields, helmets, and rectangular plates. At each stage the image grid shrinks by half while the number of "feature channels" doubles. Notice how C2f splits the signal in two: one half takes a shortcut highway so gradients never vanish!',
            microMechanics:
                'Conv(3→16, k=3, s=2) → C2f(32) → C2f(64, P3) → C2f(128, P4) → C2f(256) → SPPF(k=5×3 serial max-pools, P5). SiLU activation (x · σ(x)) fused with BatchNorm during ONNX export.',
            tensorIn: '[1, 3, $sz, $sz]',
            tensorOut: 'P3 (/8), P4 (/16), P5 (/32)',
            layerSpecs: [
              ('Conv + SiLU stem', '3×3 stride-2 convolutions replace legacy 6×6 focus layer'),
              ('C2f Cross-Stage block', '1×1 Conv split → Bottleneck cascade + direct residual highway → Concat'),
              ('SPPF (Spatial Pyramid)', '3 sequential 5×5 MaxPool2d layers (= 5×5, 9×9, 13×13 receptive fields)'),
              ('ONNX fusion', 'Conv2d + BatchNorm2d algebraically merged into single weight/bias'),
            ],
            canvasKind: _BlockCanvasKind.yoloBackbone,
          ),
          _DissectBlockSpec(
            index: 2,
            numLabel: 'B3',
            navLabel: '3. PANet Multi-Scale Neck',
            title: 'Top-Down Semantic Upsampling + Bottom-Up Localization Fusion',
            shortDigest:
                'Two-way elevator merging deep "what is it?" context (P5) with sharp "where are the edges?" grids (P3) across 3 object sizes.',
            codeLocation: 'YOLOv8 Neck (Upsample + Concat + C2f across P3/P4/P5)',
            laymanExplanation:
                'Deep layers (P5) understand WHAT an object is ("that\'s a motorcycle"), but because the grid is coarse (${sz ~/ 32}×${sz ~/ 32}), they are blurry on exact edges. Shallow layers (P3, ${sz ~/ 8}×${sz ~/ 8}) know EXACTLY where sharp edges sit, but lack context. PANet acts like a two-way elevator: it sends deep "what" knowledge up to the sharp grid, and sends sharp "where" coordinates back down.',
            microMechanics:
                'Top-down pathway: P5 upsampled 2× + Concat(P4) → C2f → upsampled 2× + Concat(P3) → P3_out. Bottom-up pathway: P3_out stride-2 Conv + Concat(P4) → P4_out → stride-2 Conv + Concat(P5) → P5_out.',
            tensorIn: 'Backbone P3, P4, P5',
            tensorOut: '$grids fused cells',
            layerSpecs: [
              ('P3 High-Res Grid (/8)', '${sz ~/ 8}×${sz ~/ 8} cells — catches tiny plates, side mirrors, phones'),
              ('P4 Mid-Res Grid (/16)', '${sz ~/ 16}×${sz ~/ 16} cells — catches helmets, seatbelts, motorcycles'),
              ('P5 Coarse Grid (/32)', '${sz ~/ 32}×${sz ~/ 32} cells — catches full cars, buses, trucks, windshields'),
              ('Total candidate cells', '$grids anchor-free prediction points'),
            ],
            canvasKind: _BlockCanvasKind.yoloNeckPanet,
          ),
          _DissectBlockSpec(
            index: 3,
            numLabel: 'B4',
            navLabel: '4. Decoupled Anchor-Free Head',
            title: 'Separate Box Regression (DFL 16-bin) and Sigmoid Class Branches',
            shortDigest:
                'Splits each grid cell into two independent tracks: one measures L/T/R/B edge distances, the other scores class probabilities.',
            codeLocation: 'ultralytics/nn/modules/head.py (Detect)',
            laymanExplanation:
                'Older detectors forced one single layer to answer both "What is this?" and "Where are its four edges?" at the same time—which caused tug-of-war errors. YOLOv8 splits every grid cell into two specialized tracks: a Box Track that measures distance from the cell center to the Left, Top, Right, and Bottom edges, and a Class Track that scores what object it is.',
            microMechanics:
                'For each of the $grids cells: Box branch predicts 4 × 16 Distribution Focal Loss (DFL) softmax bins projected to (cx, cy, w, h); Class branch applies independent Sigmoid σ(z) over $cCount target classes.',
            tensorIn: 'P3, P4, P5 feature maps',
            tensorOut: '[1, ${4 + cCount}, ${isFull ? 8400 : 2100}]',
            layerSpecs: [
              ('Box regression branch', 'Conv(64) → Conv(4 × reg_max=16) → Softmax integral → [cx, cy, bw, bh]'),
              ('Classification branch', 'Conv($cCount) → Sigmoid probabilities for ${m.label}'),
              ('Anchor-free design', 'No predefined anchor box templates; predicts ltrb distances directly'),
              ('Output transpose', 'output.T → [${isFull ? 8400 : 2100}, ${4 + cCount}] in specialists.py'),
            ],
            canvasKind: _BlockCanvasKind.yoloDecoupledHead,
          ),
          _DissectBlockSpec(
            index: 4,
            numLabel: 'B5',
            navLabel: '5. Un-Letterbox & NMS Filter',
            title: 'Confidence Gate, Coordinate Un-Padding, and Non-Maximum Suppression',
            shortDigest:
                'Deletes overlapping duplicate boxes (IoU > 0.45), strips the 114 grey padding, and maps coordinates back to the 4K CCTV frame.',
            codeLocation: 'engine/specialists.py :: detect() + nms() + _to_frame()',
            laymanExplanation:
                'Out of ${isFull ? "8,400" : "2,100"} grid cells, 99% are empty asphalt! First we throw away any box below our confidence cutoff. Next, because 5 neighboring cells might all shout "I found the same helmet!", Non-Maximum Suppression (NMS) keeps the highest-scoring box and deletes any overlapping twin (>45% overlap). Finally, we subtract the grey letterbox padding and add the vehicle\'s position so the box lands on the exact pixel of the full CCTV video.',
            microMechanics:
                'keep = confidences >= conf; x1 = ((cx - bw/2 - pad_x) / scale).clip(0, crop_w); per-class greedy NMS at IoU <= 0.45; _to_frame() adds origin (vx, vy) to map crop pixels back to 1080p/4K frame.',
            tensorIn: '[${isFull ? 8400 : 2100}, ${4 + cCount}] candidates',
            tensorOut: 'Kept boxes [x, y, w, h]',
            layerSpecs: [
              ('Confidence threshold', m.id == 'plate_specialist'
                  ? 'SEARCH_CONF = 0.10 (forgiving so no plate is missed)'
                  : isFull
                      ? 'CONF = 0.45 (0.25 for motorcycle)'
                      : 'CHECK_CONF = 0.40 (strict for violation evidence)'),
              ('Un-letterbox math', 'x = ((cx - bw/2 - pad_x) / scale).clip(0, crop_w)'),
              ('Per-class NMS', 'NMS_IOU = 0.45 drops overlapping duplicate boxes of same class'),
              ('Frame projection', '_to_frame() shifts [lx, ly, lw, lh] by vehicle origin (px1, py1)'),
            ],
            canvasKind: _BlockCanvasKind.yoloNmsUnbox,
          ),
        ];

      case _DissectFamily.reidTracker:
        return [
          _DissectBlockSpec(
            index: 0,
            numLabel: 'B1',
            navLabel: '1. 192×96 Crop & Stem',
            title: 'Center-Aligned Vehicle Patch Extraction & 64-Channel Stem',
            shortDigest:
                'Cuts a 192×96 portrait of each vehicle and runs 64 3×3 filters to capture base paint color, lighting, and body contours.',
            codeLocation: 'engine/deep_sort/deep/model.py (self.conv)',
            laymanExplanation:
                'Every time Primary Anchor spots a vehicle, DeepSORT cuts out a tall 192×96 portrait of that vehicle. The opening "Stem" layer scans the portrait with 64 tiny 3×3 filters to capture base paint color, shadow boundaries, and body contours, then halves the grid size to 96×48.',
            microMechanics:
                'RGB crop resized to 192×96, normalized by ImageNet mean/std → Conv2d(3, 64, k=3, s=1, p=1) → BatchNorm2d(64) → ReLU → MaxPool2d(k=3, s=2, p=1).',
            tensorIn: 'RGB Crop [B, 3, 192, 96]',
            tensorOut: 'Stem [B, 64, 96, 48]',
            layerSpecs: [
              ('Input aspect ratio', '192×96 (H×W) portrait tailored for vehicles & riders'),
              ('Stem convolution', 'Conv2d(3 → 64, kernel=3×3, stride=1, padding=1) + BN + ReLU'),
              ('Spatial pooling', 'MaxPool2d(kernel=3×3, stride=2, padding=1) → 96×48'),
              ('Center conversion', 'tracker.py converts xyxy → center (cx, cy, w, h) before cropping'),
            ],
            canvasKind: _BlockCanvasKind.reidPatchStem,
          ),
          _DissectBlockSpec(
            index: 1,
            numLabel: 'B2',
            navLabel: '2. 4-Stage Residual Body',
            title: '8 BasicBlocks Across layer1 (64c) → layer2 (128c) → layer3 (256c) → layer4 (512c)',
            shortDigest:
                'Condenses the vehicle portrait through 4 residual stages until 512 distinct appearance traits sit on a compact 12×6 grid.',
            codeLocation: 'engine/deep_sort/deep/model.py (BasicBlock + make_layers)',
            laymanExplanation:
                'How does the network tell two white sedans apart? It passes the image through 4 stages of Residual Blocks (BasicBlock). Stage 1 sees bumper trim and headlights (64 channels); Stage 2 sees window shapes and roof racks (128 channels); Stage 3 sees dents, decals, and wheel rims (256 channels); Stage 4 condenses the entire car\'s visual identity into 512 distinct traits on a compact 12×6 grid.',
            microMechanics:
                'Each stage has 2 BasicBlocks. Stages 2, 3, 4 downsample via stride=2 in conv1 and a 1×1 stride-2 projection shortcut: F.relu(x_shortcut + bn2(conv2(relu(bn1(conv1(x)))))).',
            tensorIn: '[B, 64, 96, 48]',
            tensorOut: '[B, 512, 12, 6]',
            layerSpecs: [
              ('layer1 (2 blocks)', '64 → 64 channels, stride=1, grid stays 96×48'),
              ('layer2 (2 blocks)', '64 → 128 channels, stride=2 downsample, grid 48×24'),
              ('layer3 (2 blocks)', '128 → 256 channels, stride=2 downsample, grid 24×12'),
              ('layer4 (2 blocks)', '256 → 512 channels, stride=2 downsample, grid 12×6'),
            ],
            canvasKind: _BlockCanvasKind.reidResBlocks,
          ),
          _DissectBlockSpec(
            index: 2,
            numLabel: 'B3',
            navLabel: '3. 512-D Unit Hypersphere',
            title: 'AdaptiveAvgPool2d(1) & L2 Unit Normalization vs. Training Classifier',
            shortDigest:
                'Pools the 12×6 grid into a 512-number visual DNA vector and normalizes its length to 1.0 so car matching is a fast dot product.',
            codeLocation: 'engine/deep_sort/deep/model.py (forward: self.reid branch)',
            laymanExplanation:
                'To compare a car across frames in microseconds, we can\'t compare bulky 12×6 grids. AdaptiveAvgPool2d averages each of the 512 channels into a single number—creating a 512-number list (the car\'s visual DNA). Finally, L2 Normalization scales that list so its length is exactly 1.0. Why? Because when two vectors sit on a radius-1 sphere, checking if two photos are the same car is just a single dot product (`qf @ gf.T`)!',
            microMechanics:
                'x = AdaptiveAvgPool2d(1)(x).view(B, 512). When self.reid=True (inference): x = x / ||x||_2. When self.reid=False (training): Linear(512→256) → BN → ReLU → Dropout → Linear(256→num_classes).',
            tensorIn: '[B, 512, 12, 6]',
            tensorOut: '[B, 512] (||v||₂ = 1.0)',
            layerSpecs: [
              ('Global pooling', 'nn.AdaptiveAvgPool2d(1) works at any input resolution'),
              ('Inference exit (reid=True)', 'x.div(x.norm(p=2, dim=1, keepdim=True)) → 512-D unit vector'),
              ('Training exit (reid=False)', 'Linear(512, 256) → BN1d → ReLU → Dropout → Linear(256, N_cars)'),
              ('Head graft trick', 'train_reid.py grafts original classifier.* back into ckpt.t7 on deploy'),
            ],
            canvasKind: _BlockCanvasKind.reidUnitSphere,
          ),
          _DissectBlockSpec(
            index: 3,
            numLabel: 'B4',
            navLabel: '4. Kalman + Hungarian Match',
            title: '8-State Kalman Motion Prediction, Cosine Distance Gate, and Track Buffer',
            shortDigest:
                'Pairs the 512-D visual fingerprint with an 8-state Kalman physics predictor, remembering hidden vehicles for up to 90 frames.',
            codeLocation: 'engine/tracker.py (DeepSortStrategy) + sort/tracker.py',
            laymanExplanation:
                'What if two identical-looking white taxis cross paths? Visual fingerprint alone might swap them! DeepSORT pairs the 512-D visual fingerprint with an 8-variable Kalman Physics Filter that tracks each car\'s speed and direction. The Hungarian Algorithm then solves a matching puzzle: pairing new boxes to existing tracks using both visual similarity (max_dist=0.40) and predicted position, remembering occluded cars for up to 90 frames.',
            microMechanics:
                'Kalman state [cx, cy, aspect, h, vx, vy, va, vh] predicts next box; Matching Cascade computes Cosine distance (1 - q·g <= 0.40) gated by Mahalanobis distance; unmatched detections fall back to IoU matching (max_iou_distance=0.70).',
            tensorIn: '512-D + [cx, cy, w, h]',
            tensorOut: '[x1, y1, x2, y2, track_id]',
            layerSpecs: [
              ('Cosine threshold', 'max_dist = 0.40 (survives camera angle & lighting changes)'),
              ('Occlusion memory', 'max_age = 90 frames (~3s buffer before a hidden track expires)'),
              ('Confirmation gate', 'n_init = 3 consecutive frames required to lock a permanent ID'),
              ('Gallery budget', 'nn_budget = 100 recent appearance vectors stored per active vehicle'),
            ],
            canvasKind: _BlockCanvasKind.reidKalmanHungarian,
          ),
        ];

      case _DissectFamily.srEnhancer:
        return [
          _DissectBlockSpec(
            index: 0,
            numLabel: 'B1',
            navLabel: '1. Shallow Feature Extraction',
            title: 'Unconditional RGB Normalization & conv_first (3 → 32 Channels)',
            shortDigest:
                'Converts the blurry plate crop into 32 shallow feature maps while saving a global skip copy (F₀) to preserve base colors.',
            codeLocation: 'engine/pipeline.py (_apply_realesrgan) + train_realesrgan.py',
            laymanExplanation:
                'When a motorcycle speeds past a distant camera, its license plate crop might only be 28 pixels wide—a blocky mosaic where "B" and "8" look identical. First, we convert the tiny crop to float32 RGB in [0, 1] and pass it through conv_first, which expands the 3 color channels into 32 shallow feature maps while keeping a long skip-connection copy so the original plate colors are never lost.',
            microMechanics:
                'rgb = cvtColor(BGR2RGB).astype(float32)/255.0 → NCHW [1, 3, H, W] → conv_first: Conv2d(3, 32, k=3, s=1, p=1) menghasilkan F_0.',
            tensorIn: 'LR Plate [1, 3, H, W]',
            tensorOut: 'Shallow F₀ [1, 32, H, W]',
            layerSpecs: [
              ('Trigger policy', 'Unconditional in _extract_plate_text() when enhancement="realesrgan"'),
              ('First convolution', 'conv_first: Conv2d(in=3, out=32, kernel=3×3, padding=1)'),
              ('Global skip anchor', 'F₀ is saved to add back after all 6 RRDB blocks finish'),
              ('Dynamic dimensions', 'ONNX exported with dynamic H (dim 2) and W (dim 3) axes'),
            ],
            canvasKind: _BlockCanvasKind.srShallowExtract,
          ),
          _DissectBlockSpec(
            index: 1,
            numLabel: 'B2',
            navLabel: '2. 6-Block RRDB Trunk',
            title: 'Residual-in-Residual Dense Blocks (num_block=6, num_feat=32, num_grow_ch=16)',
            shortDigest:
                '6 dense residual blocks (sized for 6GB VRAM) hallucinate crisp character strokes and edges without BatchNorm blur.',
            codeLocation: 'training_lab/scripts/train_realesrgan.py (write_basicsr_config)',
            laymanExplanation:
                'This is the brain of Real-ESRGAN. Standard ESRGAN uses 23 massive blocks that choke a 6GB laptop GPU. Huli-Kamote uses a custom 6-block RRDBNet. Inside each RRDB sit 3 Dense Blocks where every layer feeds its output to ALL subsequent layers—allowing the network to piece together faint character strokes, stamped plate borders, and screw holes without BatchNorm artifacts.',
            microMechanics:
                '6 × RRDB(num_feat=32, num_grow_ch=16). Each RRDB contains 3 ResidualDenseBlocks (5 × Conv3×3 + LeakyReLU(0.2) with dense concatenation) scaled by residual factor β=0.2, followed by conv_body(32→32) + F_0.',
            tensorIn: 'F₀ [1, 32, H, W]',
            tensorOut: 'F_body [1, 32, H, W]',
            layerSpecs: [
              ('Trunk depth', 'num_block = 6 RRDB blocks (30% of stock size, real-time on 6GB VRAM)'),
              ('Dense growth', 'num_grow_ch = 16 channels added per internal dense convolution'),
              ('No BatchNorm', 'BatchNorm is omitted so contrast/sharpness never gets washed out'),
              ('Residual scaling', 'β = 0.2 stabilizes deep feature accumulation across all 6 blocks'),
            ],
            canvasKind: _BlockCanvasKind.srRrdbBlocks,
          ),
          _DissectBlockSpec(
            index: 2,
            numLabel: 'B3',
            navLabel: '3. Two-Stage ×4 Upsampler',
            title: 'Nearest-Neighbor 2× + Conv3×3 + LeakyReLU (×2 Stages = ×4 Resolution)',
            shortDigest:
                'Expands the plate canvas in two 2× steps (4× width & height = 16× total pixels) with learned convolutions for sharp strokes.',
            codeLocation: 'RRDBNet (upconv1, upconv2, conv_hr, conv_last)',
            laymanExplanation:
                'Now that the 6 RRDB blocks have figured out where every crisp letter edge should be, the network expands the canvas in two gentle 2× steps (2× then 2× = 4× total width and height—16× more pixels!). Each step doubles the pixel grid and runs a learned 3×3 convolution to paint sharp strokes instead of blocky stairs, finishing with conv_last back to 3 RGB channels.',
            microMechanics:
                'upconv1: Interpolate(scale=2, mode="nearest") → Conv3×3(32→32) → LeakyReLU → upconv2: Interpolate(scale=2) → Conv3×3(32→32) → LeakyReLU → conv_hr(32→32) → conv_last(32→3) → clip(0,1) × 255.',
            tensorIn: '[1, 32, H, W]',
            tensorOut: 'HR Plate [1, 3, 4H, 4W]',
            layerSpecs: [
              ('Stage 1 upsample', 'H×W → 2H×2W + learned Conv2d(32, 32, 3×3) + LeakyReLU(0.2)'),
              ('Stage 2 upsample', '2H×2W → 4H×4W + learned Conv2d(32, 32, 3×3) + LeakyReLU(0.2)'),
              ('Reconstruction head', 'conv_hr(32→32) + conv_last(32→3 RGB) + np.clip(0, 1)'),
              ('EMA weights', 'Uses smoothed params_ema from training for artifact-free edges'),
            ],
            canvasKind: _BlockCanvasKind.srPixelShuffle4x,
          ),
          _DissectBlockSpec(
            index: 3,
            numLabel: 'B4',
            navLabel: '4. LapSRN ×8 Pyramid Alternative',
            title: 'Progressive Laplacian Pyramid Super-Resolution (2× → 4× → 8×) & Lanczos Fallback',
            shortDigest:
                'Optional 3-stage Laplacian Pyramid (×2 → ×4 → ×8) for extreme magnification, plus Lanczos-4 mathematical fallback.',
            codeLocation: 'engine/pipeline.py :: _apply_super_resolution() (models/LapSRN_x8.pb)',
            laymanExplanation:
                'Alongside Real-ESRGAN, Huli-Kamote also includes LapSRN_x8.pb—a Laplacian Pyramid network that upscales tiny distant plates by 8× in three progressive steps (2×, 4×, 8×). At each level, a feature branch predicts the missing high-frequency edge details (residuals) and adds them onto an upsampled image branch. If neither neural enhancer is selected, the pipeline falls back to mathematical 4× Lanczos-4 interpolation.',
            microMechanics:
                'cv2.dnn_superres.DnnSuperResImpl_create() loads LapSRN_x8.pb ("lapsrn", scale=8). Three log2(8)=3 pyramid levels of transposed convolutions + residual detail addition.',
            tensorIn: 'Tiny Crop [H, W, 3]',
            tensorOut: 'LapSRN [8H, 8W, 3]',
            layerSpecs: [
              ('LapSRN binary', 'hulikamote_backend/models/LapSRN_x8.pb (OpenCV dnn_superres)'),
              ('Pyramid levels', '3 progressive stages: ×2 → ×4 → ×8 spatial resolution'),
              ('Graceful fallback', 'cv2.resize(crop, (w*4, h*4), interpolation=cv2.INTER_LANCZOS4)'),
              ('Forensic storage', 'plate_reread.py saves both image_raw and image_sr for side-by-side audit'),
            ],
            canvasKind: _BlockCanvasKind.srLapSrnPyramid,
          ),
        ];

      case _DissectFamily.ocrReader:
        return [
          _DissectBlockSpec(
            index: 0,
            numLabel: 'B1',
            navLabel: '1. TPS Spatial Un-Warping',
            title: '20-Point Thin-Plate Spline (TPS) Perspective Rectification & Strip Resize',
            shortDigest:
                'Finds 20 fiducial points along the top and bottom of an angled CCTV plate and "irons" the trapezoid flat into a horizontal strip.',
            codeLocation: 'training_lab/scripts/train_ocr.py (Transformation: TPS / RecResizeImg)',
            laymanExplanation:
                'CCTV cameras look down from poles at steep angles, making rectangular license plates look like slanted trapezoids. Before trying to read the letters, the Transformation stage locates 20 control dots along the top and bottom edges of the plate and mathematically "irons" the trapezoid flat into a clean horizontal strip (32×100 grayscale for EasyOCR, or 32×320 color for PaddleOCR).',
            microMechanics:
                'Localization Network predicts 20 (x,y) fiducial coordinates → Grid Generator computes Thin-Plate Spline warp field → Bilinear Sampler rectifies image into [1, 1, 32, 100] (EasyOCR) or [1, 3, 32, 320] (PaddleOCR).',
            tensorIn: 'Skewed Plate Crop',
            tensorOut: 'Flat Strip [1, C, 32, W]',
            layerSpecs: [
              ('EasyOCR TPS stage', '20 fiducial control points → 1-channel grayscale 32×100 strip'),
              ('PaddleOCR strip', '3-channel BGR 3×32×320 strip (keeps green/white/yellow plate cues)'),
              ('Allowlist filter', 'allowlist="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" (36 chars)'),
              ('Why grayscale vs BGR', 'pipeline.py feeds gray to EasyOCR and color BGR to PaddleOCR'),
            ],
            canvasKind: _BlockCanvasKind.ocrTpsUnwarp,
          ),
          _DissectBlockSpec(
            index: 1,
            numLabel: 'B2',
            navLabel: '2. Vertical Column Slicing',
            title: 'ResNet (512c) / MobileNetV1Enhance Feature Extractor Collapsed to Height=1',
            shortDigest:
                'Collapses the 32px height down to 1px while keeping horizontal slices—scanning the plate left-to-right like a barcode.',
            codeLocation: 'train_ocr.py (FeatureExtraction: ResNet / MobileNetV1Enhance)',
            laymanExplanation:
                'How do you read a license plate without drawing a box around each letter? You slice it like a loaf of bread! The CNN backbone squashes the 32-pixel height all the way down to 1 pixel high, while keeping ~25 to 80 horizontal steps from left to right. Each vertical slice is a 512-number column describing what stroke sits at that exact horizontal spot on the plate.',
            microMechanics:
                'Asymmetric pooling (stride 2×1 in deeper layers) collapses H: 32 → 16 → 8 → 4 → 2 → 1 while preserving horizontal width T, outputting sequence tensor [B, T, 512].',
            tensorIn: 'Strip [1, C, 32, W]',
            tensorOut: 'Slices [1, T, 512]',
            layerSpecs: [
              ('EasyOCR backbone', 'ResNet FeatureExtractor → output_channel = 512, height collapsed to 1'),
              ('PaddleOCR backbone', 'MobileNetV1Enhance (scale=0.5) lightweight depthwise separable CNN'),
              ('Asymmetric stride', 'MaxPool kernels (2×1) shrink height to 1 without merging adjacent letters'),
              ('Receptive field', 'Each vertical slice T_i sees a narrow horizontal window of the plate'),
            ],
            canvasKind: _BlockCanvasKind.ocrFeatureSlices,
          ),
          _DissectBlockSpec(
            index: 2,
            numLabel: 'B3',
            navLabel: '3. BiLSTM / SVTR Sequence',
            title: '2-Layer Bidirectional LSTM (256h) vs. SVTR Transformer + SAR 2D Attention',
            shortDigest:
                'Connects neighboring slices left-to-right and right-to-left so look-alike strokes ("I", "1", "N", "M") share context.',
            codeLocation: 'train_ocr.py (SequenceModeling: BiLSTM / MultiHead SVTR+SAR)',
            laymanExplanation:
                'A single vertical slice of the letter "N" looks just like the letter "I"! To tell them apart, each slice needs to know what sits to its left and right. EasyOCR runs a Bidirectional LSTM that reads the slices Left-to-Right AND Right-to-Left simultaneously. PaddleOCR goes even further: it combines an SVTR Transformer neck with a 2D Show-Attend-and-Read (SAR) attention head.',
            microMechanics:
                'EasyOCR: 2-layer BiLSTM(input=512, hidden=256) → Linear(512→256). PaddleOCR: SequenceEncoder(SVTR, dims=64, depth=2, num_heads=8) + SARHead(enc_bi_rnn + 2D attention decoder).',
            tensorIn: 'Visual Slices [1, T, 512]',
            tensorOut: 'Logits [1, T, 37]',
            layerSpecs: [
              ('EasyOCR BiLSTM', 'Forward LSTM + Backward LSTM (hidden_size=256) captures stroke context'),
              ('PaddleOCR SVTR neck', '2-layer Local/Global self-attention mixer (dims=64, 8 heads)'),
              ('PaddleOCR MultiHead', 'Dual branch: CTCHead (fast greedy decode) + SARHead (2D attention)'),
              ('Vocabulary size', '36 alphanumeric characters + 1 CTC Blank token (∅) = 37 logits/slice'),
            ],
            canvasKind: _BlockCanvasKind.ocrSequenceBilstm,
          ),
          _DissectBlockSpec(
            index: 3,
            numLabel: 'B4',
            navLabel: '4. CTC Collapse & Syntax Vote',
            title: 'CTC Blank/Repeat Collapse, Positional LLL-DDDD Repair, and Multi-Crop Ballot',
            shortDigest:
                'Merges repeated slice letters, drops blanks (∅), fixes look-alike digits/letters by slot, and votes across 40 frames.',
            codeLocation: 'engine/pipeline.py (_extract_plate_text) + engine/ticket_merge.py (revote)',
            laymanExplanation:
                'Because a wide letter like "W" spans 4 vertical slices, the network might output "N-N-∅-B-B-C-∅-1-2-3-4". Connectionist Temporal Classification (CTC) merges repeated letters and drops the blank (∅) separators to produce "NBC1234". Finally, Huli-Kamote applies Philippine plate syntax rules (if slot 4 is the letter "O", fix it to digit "0") and holds an election across up to 40 frames so one glare frame never ruins the ticket!',
            microMechanics:
                'CTC argmax per slice → collapse repeats → strip ∅ → ph_standard positional map (slots 0..2: dict_int_to_char; slots 3..6: dict_char_to_int) → ticket_merge.revote() confidence-weighted majority vote.',
            tensorIn: '[T, 37] × up to 40 crops',
            tensorOut: 'Voted Plate (e.g. "NBC1234")',
            layerSpecs: [
              ('CTC decoding rule', '"N-N-∅-B-B-C-1-2-3-4" → collapse repeats → drop ∅ → "NBC1234"'),
              ('ph_standard slots 0–2', 'Letters enforced: 0→O, 1→I, 3→J, 4→A, 5→S, 6→G, 8→B, 2→Z, 7→T'),
              ('ph_standard slots 3–6', 'Digits enforced: O/Q/D/U→0, I→1, Z→2, J→3, A/L→4, S/F→5, G→6, T/Y→7, B→8'),
              ('Pass 2 multi-crop vote', 'ticket_merge.py aggregates up to 40 crops to elect the final plate'),
            ],
            canvasKind: _BlockCanvasKind.ocrCtcDecode,
          ),
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _selectModel(String id) {
    setState(() {
      _selectedModelId = id;
      _activeBlock = 0;
      final blocks = _buildBlocksForModel(_currentModel);
      _blockKeys = List.generate(blocks.length, (_) => GlobalKey());
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _selectBlock(int index, {bool scrollIntoView = true}) {
    final blocks = _buildBlocksForModel(_currentModel);
    setState(() {
      _activeBlock = index.clamp(0, blocks.length - 1);
    });
    if (!_singleBlockFocusMode && scrollIntoView && _activeBlock < _blockKeys.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _blockKeys[_activeBlock].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            alignment: 0.06,
          );
        }
      });
    }
  }

  void _toggleAutoPlay() {
    setState(() {
      _isAutoPlaying = !_isAutoPlaying;
    });
    if (_isAutoPlaying) {
      _scheduleNextAutoBlock();
    }
  }

  void _scheduleNextAutoBlock() {
    if (!_isAutoPlaying || !mounted) return;
    final delayMs = (3800 / _playbackSpeed).round();
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!_isAutoPlaying || !mounted) return;
      final blocks = _buildBlocksForModel(_currentModel);
      final next = (_activeBlock + 1) % blocks.length;
      _selectBlock(next, scrollIntoView: true);
      _scheduleNextAutoBlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgCanvas = isDark ? const Color(0xFF0A0D12) : const Color(0xFFF8FAFC);
    final surface = isDark ? const Color(0xFF0F141C) : Colors.white;
    final surfaceSubtle = isDark ? const Color(0xFF151C28) : const Color(0xFFF1F5F9);
    final border = isDark ? const Color(0xFF1E2634) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final textMuted = isDark ? const Color(0xFF64748B) : const Color(0xFF64748B);

    final model = _currentModel;
    final blocks = _buildBlocksForModel(model);
    if (_blockKeys.length != blocks.length) {
      _blockKeys = List.generate(blocks.length, (_) => GlobalKey());
    }

    final visibleBlocks = _singleBlockFocusMode
        ? [blocks[_activeBlock.clamp(0, blocks.length - 1)]]
        : blocks;

    return Container(
      color: bgCanvas,
      child: Column(
        children: [
          // ── Sticky Top Instrument Bar ────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: surface,
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Model Anatomy Dissector',
                      style: GoogleFonts.lexend(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 14, color: border),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: _models.map((m) {
                          final isSel = m.id == _selectedModelId;
                          return InkWell(
                            onTap: () => _selectModel(m.id),
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSel ? _kSignalBlue.withOpacity(0.14) : Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: isSel ? _kSignalBlue : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                m.label,
                                style: GoogleFonts.lexend(
                                  fontSize: 11,
                                  fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                                  color: isSel ? textPrimary : textSecondary,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // View Mode Switch: Focus 1 Block vs Scroll All
                    InkWell(
                      onTap: () => setState(() => _singleBlockFocusMode = !_singleBlockFocusMode),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: surfaceSubtle,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: border),
                        ),
                        child: Text(
                          _singleBlockFocusMode ? 'View: 1-by-1 Focus' : 'View: Scroll All',
                          style: GoogleFonts.lexend(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Transport Controls
                    Container(
                      decoration: BoxDecoration(
                        color: surfaceSubtle,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => _selectBlock((_activeBlock - 1).clamp(0, blocks.length - 1)),
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(
                                'Prev',
                                style: GoogleFonts.lexend(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                          ),
                          Container(width: 1, height: 18, color: border),
                          InkWell(
                            onTap: _toggleAutoPlay,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              color: _isAutoPlaying
                                  ? _kSemanticPass.withOpacity(0.16)
                                  : _kSignalBlue.withOpacity(0.12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isAutoPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    size: 13,
                                    color: _isAutoPlaying ? _kSemanticPass : _kSignalBlue,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isAutoPlaying ? 'Pause' : 'Auto-play',
                                    style: GoogleFonts.lexend(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _isAutoPlaying ? _kSemanticPass : _kSignalBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(width: 1, height: 18, color: border),
                          InkWell(
                            onTap: () => _selectBlock((_activeBlock + 1).clamp(0, blocks.length - 1)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(
                                'Next',
                                style: GoogleFonts.lexend(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                          ),
                          Container(width: 1, height: 18, color: border),
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (_playbackSpeed == 1.0) {
                                  _playbackSpeed = 1.5;
                                } else if (_playbackSpeed == 1.5) {
                                  _playbackSpeed = 0.6;
                                } else {
                                  _playbackSpeed = 1.0;
                                }
                              });
                            },
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                              child: Text(
                                '${_playbackSpeed}x',
                                style: GoogleFonts.firaCode(
                                  fontSize: 10.5,
                                  color: textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Second Row: Block Stepper Pills + On-Demand Macro Cascade Toggle
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: blocks.map((b) {
                          final isCur = _activeBlock == b.index;
                          return InkWell(
                            onTap: () => _selectBlock(b.index, scrollIntoView: true),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: isCur ? _kSignalBlue.withOpacity(0.15) : surfaceSubtle,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isCur ? _kSignalBlue : border,
                                ),
                              ),
                              child: Text(
                                b.navLabel,
                                style: GoogleFonts.lexend(
                                  fontSize: 11,
                                  fontWeight: isCur ? FontWeight.w600 : FontWeight.w400,
                                  color: isCur ? textPrimary : textSecondary,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: () => _showMacroCascadeDialog(
                        model: model,
                        isDark: isDark,
                        surface: surface,
                        surfaceSubtle: surfaceSubtle,
                        border: border,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: surfaceSubtle,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: border),
                        ),
                        child: Text(
                          'Show Macro System Map (7 Models)',
                          style: GoogleFonts.lexend(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Calm, Minimal Body with On-Demand Hover/Click Popovers ───────
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Compact 1-Line Model Summary Banner + Click-to-Open Dialog Chips
                      _buildCompactModelBanner(
                        model: model,
                        isDark: isDark,
                        surface: surface,
                        surfaceSubtle: surfaceSubtle,
                        border: border,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                        textMuted: textMuted,
                      ),
                      const SizedBox(height: 16),

                      // Focused Block Card(s)
                      ...visibleBlocks.map((block) {
                        return Container(
                          key: _blockKeys[block.index],
                          child: _buildMinimalBlockCard(
                            block: block,
                            model: model,
                            totalBlocks: blocks.length,
                            isDark: isDark,
                            surface: surface,
                            surfaceSubtle: surfaceSubtle,
                            border: border,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                            textMuted: textMuted,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Slim Model Banner (Minimal Default + Hover/Click Popovers) ─────────────
  Widget _buildCompactModelBanner({
    required _DissectModelSpec model,
    required bool isDark,
    required Color surface,
    required Color surfaceSubtle,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kSignalBlue.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _kSignalBlue.withOpacity(0.5)),
                ),
                child: Text(
                  model.roleTag,
                  style: GoogleFonts.firaCode(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: _kSignalBlue,
                  ),
                ),
              ),
              Text(
                model.label,
                style: GoogleFonts.lexend(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              Text(
                '•  ${model.inputShape} → ${model.outputShape}',
                style: GoogleFonts.firaCode(
                  fontSize: 11,
                  color: textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  model.shortSummary,
                  style: GoogleFonts.lexend(
                    fontSize: 12.5,
                    height: 1.4,
                    color: textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _HoverDetailPopoverButton(
                    label: 'Layman Analogy',
                    dialogTitle: '${model.label} — Plain-English Analogy',
                    isDark: isDark,
                    surface: surface,
                    surfaceSubtle: surfaceSubtle,
                    border: border,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    popoverBuilder: () => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          model.laymanAnalogy,
                          style: GoogleFonts.lexend(
                            fontSize: 12.5,
                            height: 1.5,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Runtime Cascade Role:',
                          style: GoogleFonts.lexend(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: _kSignalBlue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          model.macroRole,
                          style: GoogleFonts.lexend(
                            fontSize: 12,
                            height: 1.45,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _HoverDetailPopoverButton(
                    label: 'Model Specs & Classes (${model.classesOrOutputs.length})',
                    dialogTitle: '${model.label} — Technical Contract & Classes',
                    isDark: isDark,
                    surface: surface,
                    surfaceSubtle: surfaceSubtle,
                    border: border,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    popoverBuilder: () => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSpecLine('Weights Path', model.filePath, textMuted, textPrimary),
                        _buildSpecLine('Engine File', model.engineFile, textMuted, textPrimary),
                        _buildSpecLine('Input Tensor', model.inputShape, textMuted, textPrimary),
                        _buildSpecLine('Output Tensor', model.outputShape, textMuted, textPrimary),
                        _buildSpecLine('Fire Cadence', model.cadence, textMuted, textPrimary),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: model.classesOrOutputs.map((cls) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: surfaceSubtle,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: border),
                              ),
                              child: Text(
                                cls,
                                style: GoogleFonts.firaCode(
                                  fontSize: 10.5,
                                  color: textPrimary,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Minimal Block Card: Big Animation + 1-Line Summary + Hover Popovers ────
  Widget _buildMinimalBlockCard({
    required _DissectBlockSpec block,
    required _DissectModelSpec model,
    required int totalBlocks,
    required bool isDark,
    required Color surface,
    required Color surfaceSubtle,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
  }) {
    final isFocused = _activeBlock == block.index;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isFocused ? _kSignalBlue.withOpacity(0.75) : border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Block Step Number + Title + Tensor In/Out Pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kSignalBlue.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${block.numLabel} of B$totalBlocks',
                  style: GoogleFonts.firaCode(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _kSignalBlue,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  block.title,
                  style: GoogleFonts.lexend(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: surfaceSubtle,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    '${block.tensorIn}  →  ${block.tensorOut}',
                    style: GoogleFonts.firaCode(
                      fontSize: 10.5,
                      color: _kSignalBlue,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Concise 1-Sentence Digest (Zero wall-of-text!)
          Text(
            block.shortDigest,
            style: GoogleFonts.lexend(
              fontSize: 13,
              height: 1.45,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 14),

          // Interactive Micro Controls (when applicable to this block)
          _buildBlockControls(
            block: block,
            surfaceSubtle: surfaceSubtle,
            border: border,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),

          // Main Visual Canvas (Front and center!)
          Container(
            height: 270,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0A0D12) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border),
            ),
            clipBehavior: Clip.antiAlias,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _DissectBlockFigurePainter(
                    kind: block.canvasKind,
                    model: model,
                    progress: _pulseController.value,
                    isDark: isDark,
                    fpnScale: _selectedFpnScale,
                    showLetterboxFix: _showLetterboxFix,
                    ocrArch: _selectedOcrArch,
                    srArch: _selectedSrArch,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Bottom Footer: On-Demand Hover / Click Detail Pills + Step Navigation
          Row(
            children: [
              Text(
                'Click for details:',
                style: GoogleFonts.lexend(
                  fontSize: 11,
                  color: textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _HoverDetailPopoverButton(
                      label: 'Full Layman Story',
                      dialogTitle: '${block.navLabel} — Plain-English Explanation',
                      isDark: isDark,
                      surface: surface,
                      surfaceSubtle: surfaceSubtle,
                      border: border,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      popoverBuilder: () => Text(
                        block.laymanExplanation,
                        style: GoogleFonts.lexend(
                          fontSize: 12.5,
                          height: 1.55,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    _HoverDetailPopoverButton(
                      label: 'Layer Specs (${block.layerSpecs.length})',
                      dialogTitle: '${block.navLabel} — Internal Layer Specifications',
                      isDark: isDark,
                      surface: surface,
                      surfaceSubtle: surfaceSubtle,
                      border: border,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      popoverBuilder: () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSpecLine('Tensor In', block.tensorIn, textMuted, textPrimary),
                          _buildSpecLine('Tensor Out', block.tensorOut, textMuted, _kSignalBlue),
                          const Divider(height: 14),
                          ...block.layerSpecs.map(
                            (sp) => _buildSpecLine(sp.$1, sp.$2, textMuted, textPrimary),
                          ),
                        ],
                      ),
                    ),
                    _HoverDetailPopoverButton(
                      label: 'Code & Math',
                      dialogTitle: '${block.navLabel} — Source Code & Tensor Math',
                      isDark: isDark,
                      surface: surface,
                      surfaceSubtle: surfaceSubtle,
                      border: border,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      popoverBuilder: () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSpecLine('Source File', block.codeLocation, textMuted, _kSignalBlue),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: surfaceSubtle,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: border),
                            ),
                            child: Text(
                              block.microMechanics,
                              style: GoogleFonts.firaCode(
                                fontSize: 11,
                                height: 1.45,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_singleBlockFocusMode) ...[
                const SizedBox(width: 8),
                Text(
                  'Block ${block.index + 1} of $totalBlocks',
                  style: GoogleFonts.firaCode(
                    fontSize: 10.5,
                    color: textMuted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Macro Cascade Dialog (Shown on demand in a modal dialog) ───────────────
  void _showMacroCascadeDialog({
    required _DissectModelSpec model,
    required bool isDark,
    required Color surface,
    required Color surfaceSubtle,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Macro System Cascade — How All 7 Models Connect on a Single CCTV Frame (engine/pipeline.py)',
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: Icon(Icons.close_rounded, size: 18, color: textSecondary),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 128,
                    width: double.infinity,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _MacroCascadeDiagramPainter(
                            selectedModelId: _selectedModelId,
                            progress: _pulseController.value,
                            isDark: isDark,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpecLine(String k, String v, Color textMuted, Color textPrimary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              k,
              style: GoogleFonts.lexend(
                fontSize: 11,
                color: textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: GoogleFonts.firaCode(
                fontSize: 11,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockControls({
    required _DissectBlockSpec block,
    required Color surfaceSubtle,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    if (block.canvasKind == _BlockCanvasKind.yoloLetterbox) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Input Mode:',
              style: GoogleFonts.lexend(fontSize: 11, color: textSecondary),
            ),
            _buildSmallPill(
              label: 'Letterbox RGB + 114 Pad (85% Recall)',
              selected: _showLetterboxFix,
              onTap: () => setState(() => _showLetterboxFix = true),
              surfaceSubtle: surfaceSubtle,
              border: border,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            _buildSmallPill(
              label: 'Stretched BGR Bug (7% Recall)',
              selected: !_showLetterboxFix,
              onTap: () => setState(() => _showLetterboxFix = false),
              surfaceSubtle: surfaceSubtle,
              border: border,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
          ],
        ),
      );
    }
    if (block.canvasKind == _BlockCanvasKind.yoloNeckPanet) {
      final scales = ['P3 (/8 Small)', 'P4 (/16 Medium)', 'P5 (/32 Large)'];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Inspect Pyramid Scale:',
              style: GoogleFonts.lexend(fontSize: 11, color: textSecondary),
            ),
            ...List.generate(scales.length, (i) {
              return _buildSmallPill(
                label: scales[i],
                selected: _selectedFpnScale == i,
                onTap: () => setState(() => _selectedFpnScale = i),
                surfaceSubtle: surfaceSubtle,
                border: border,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              );
            }),
          ],
        ),
      );
    }
    if (block.canvasKind == _BlockCanvasKind.ocrSequenceBilstm) {
      final archs = ['EasyOCR (ResNet+BiLSTM+CTC)', 'PaddleOCR (SVTR+SAR)'];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'OCR Architecture:',
              style: GoogleFonts.lexend(fontSize: 11, color: textSecondary),
            ),
            ...List.generate(archs.length, (i) {
              return _buildSmallPill(
                label: archs[i],
                selected: _selectedOcrArch == i,
                onTap: () => setState(() => _selectedOcrArch = i),
                surfaceSubtle: surfaceSubtle,
                border: border,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              );
            }),
          ],
        ),
      );
    }
    if (block.canvasKind == _BlockCanvasKind.srLapSrnPyramid) {
      final srs = ['Real-ESRGAN ×4', 'LapSRN Pyramid ×8'];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Upscaler Mode:',
              style: GoogleFonts.lexend(fontSize: 11, color: textSecondary),
            ),
            ...List.generate(srs.length, (i) {
              return _buildSmallPill(
                label: srs[i],
                selected: _selectedSrArch == i,
                onTap: () => setState(() => _selectedSrArch = i),
                surfaceSubtle: surfaceSubtle,
                border: border,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              );
            }),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSmallPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color surfaceSubtle,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? _kSignalBlue.withOpacity(0.15) : surfaceSubtle,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? _kSignalBlue : border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.lexend(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? textPrimary : textSecondary,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ON-DEMAND HOVER POPOVER + CLICK DIALOG CHIP
// Shows a floating card immediately when the mouse hovers over the chip, or
// pins it open in a clean modal dialog when clicked.
// ═════════════════════════════════════════════════════════════════════════════

class _HoverDetailPopoverButton extends StatefulWidget {
  final String label;
  final String dialogTitle;
  final bool isDark;
  final Color surface;
  final Color surfaceSubtle;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Widget Function() popoverBuilder;

  const _HoverDetailPopoverButton({
    required this.label,
    required this.dialogTitle,
    required this.isDark,
    required this.surface,
    required this.surfaceSubtle,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.popoverBuilder,
  });

  @override
  State<_HoverDetailPopoverButton> createState() =>
      _HoverDetailPopoverButtonState();
}

class _HoverDetailPopoverButtonState extends State<_HoverDetailPopoverButton> {
  bool _isHovered = false;

  void _openPinnedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: widget.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: widget.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.dialogTitle,
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: widget.textPrimary,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: Text(
                          'Close ×',
                          style: GoogleFonts.lexend(
                            fontSize: 12,
                            color: widget.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  widget.popoverBuilder(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _openPinnedDialog,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovered
                ? const Color(0xFF3B82F6).withOpacity(0.14)
                : widget.surfaceSubtle,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: _isHovered ? const Color(0xFF3B82F6) : widget.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 12,
                color: _isHovered ? const Color(0xFF3B82F6) : widget.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: GoogleFonts.lexend(
                  fontSize: 11,
                  fontWeight: _isHovered ? FontWeight.w600 : FontWeight.w500,
                  color: _isHovered ? widget.textPrimary : widget.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PAINTER 1: MACRO SYSTEM CASCADE DIAGRAM (ALL 7 MODELS IN PIPELINE.PY)
// ═════════════════════════════════════════════════════════════════════════════

class _MacroCascadeDiagramPainter extends CustomPainter {
  final String selectedModelId;
  final double progress;
  final bool isDark;

  const _MacroCascadeDiagramPainter({
    required this.selectedModelId,
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final borderCol = isDark ? const Color(0xFF263244) : const Color(0xFFCBD5E1);
    final boxFill = isDark ? const Color(0xFF131A26) : const Color(0xFFF1F5F9);
    final textCol = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final mutedCol = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const blue = Color(0xFF3B82F6);
    const green = Color(0xFF10B981);
    const amber = Color(0xFFF59E0B);

    final w = size.width;
    final h = size.height;

    final nodes = <String, (Rect, String, String)>{
      'primary_anchor': (
        Rect.fromLTWH(w * 0.02, h * 0.14, w * 0.19, h * 0.34),
        '1A. Primary Anchor',
        '640×640 Full Frame',
      ),
      'reid_deepsort': (
        Rect.fromLTWH(w * 0.02, h * 0.56, w * 0.19, h * 0.34),
        '1B. DeepSORT ReID',
        '192×96 → 512-D Track',
      ),
      'helmet_specialist': (
        Rect.fromLTWH(w * 0.30, h * 0.06, w * 0.21, h * 0.26),
        '2A. Helmet Specialist',
        '320×320 Bike+Rider',
      ),
      'plate_specialist': (
        Rect.fromLTWH(w * 0.30, h * 0.37, w * 0.21, h * 0.26),
        '2B. Plate Specialist',
        '320×320 Vehicle Crop',
      ),
      'cabin_specialist': (
        Rect.fromLTWH(w * 0.30, h * 0.68, w * 0.21, h * 0.26),
        '2C. Cabin Specialist',
        '320×320 5-Class Look',
      ),
      'plate_enhancer': (
        Rect.fromLTWH(w * 0.60, h * 0.37, w * 0.18, h * 0.26),
        '3A. Plate Enhancer',
        '6-RRDB ×4 / LapSRN ×8',
      ),
      'plate_ocr': (
        Rect.fromLTWH(w * 0.81, h * 0.37, w * 0.17, h * 0.26),
        '3B. Plate OCR',
        'TPS + BiLSTM/SVTR',
      ),
    };

    final edges = <(String, String)>[
      ('primary_anchor', 'reid_deepsort'),
      ('primary_anchor', 'helmet_specialist'),
      ('primary_anchor', 'plate_specialist'),
      ('primary_anchor', 'cabin_specialist'),
      ('plate_specialist', 'plate_enhancer'),
      ('plate_enhancer', 'plate_ocr'),
    ];

    final linePaint = Paint()
      ..color = borderCol
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    for (final e in edges) {
      final r1 = nodes[e.$1]!.$1;
      final r2 = nodes[e.$2]!.$1;
      final p1 = e.$1 == 'primary_anchor' && e.$2 == 'reid_deepsort'
          ? Offset(r1.center.dx, r1.bottom)
          : Offset(r1.right, r1.center.dy);
      final p2 = e.$1 == 'primary_anchor' && e.$2 == 'reid_deepsort'
          ? Offset(r2.center.dx, r2.top)
          : Offset(r2.left, r2.center.dy);

      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(
          (p1.dx + p2.dx) / 2,
          p1.dy,
          (p1.dx + p2.dx) / 2,
          p2.dy,
          p2.dx,
          p2.dy,
        );
      canvas.drawPath(path, linePaint);

      final t = (progress * 1.6) % 1.0;
      final pulseX = p1.dx + (p2.dx - p1.dx) * t;
      final pulseY = p1.dy + (p2.dy - p1.dy) * t;
      final isHighlighted = selectedModelId == e.$1 || selectedModelId == e.$2;
      canvas.drawCircle(
        Offset(pulseX, pulseY),
        isHighlighted ? 3.5 : 2.3,
        Paint()..color = isHighlighted ? blue : green.withOpacity(0.75),
      );
    }

    nodes.forEach((id, data) {
      final rect = data.$1;
      final isSel = id == selectedModelId;
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(5));
      canvas.drawRRect(
        rrect,
        Paint()..color = isSel ? blue.withOpacity(0.16) : boxFill,
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isSel ? blue : borderCol
          ..strokeWidth = isSel ? 1.6 : 1.0
          ..style = PaintingStyle.stroke,
      );

      _drawLabel(
        canvas,
        data.$2,
        Offset(rect.left + 8, rect.top + 5),
        isSel ? blue : textCol,
        10.5,
        bold: true,
        maxWidth: rect.width - 14,
      );
      _drawLabel(
        canvas,
        data.$3,
        Offset(rect.left + 8, rect.top + 18),
        mutedCol,
        9.5,
        mono: true,
        maxWidth: rect.width - 14,
      );
    });

    final ticketRect = Rect.fromLTWH(w * 0.60, h * 0.06, w * 0.38, h * 0.24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(ticketRect, const Radius.circular(5)),
      Paint()..color = amber.withOpacity(0.08),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(ticketRect, const Radius.circular(5)),
      Paint()
        ..color = amber.withOpacity(0.45)
        ..style = PaintingStyle.stroke,
    );
    _drawLabel(
      canvas,
      'Every 5th Inference Frame (SPECIALIST_INTERVAL = 5)',
      Offset(ticketRect.left + 10, ticketRect.top + 6),
      amber,
      10,
      bold: true,
      maxWidth: ticketRect.width - 16,
    );
    _drawLabel(
      canvas,
      'Specialists run only on cropped vehicle boxes → 10× faster than full-frame',
      Offset(ticketRect.left + 10, ticketRect.top + 19),
      mutedCol,
      9.5,
      maxWidth: ticketRect.width - 16,
    );
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset pos,
    Color color,
    double fontSize, {
    bool bold = false,
    bool mono = false,
    double maxWidth = 220,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: mono
            ? GoogleFonts.firaCode(
                fontSize: fontSize,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                color: color,
              )
            : GoogleFonts.lexend(
                fontSize: fontSize,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _MacroCascadeDiagramPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.selectedModelId != selectedModelId ||
        oldDelegate.isDark != isDark;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PAINTER 2: ANIMATED MICRO-DISSECTION FIGURES FOR EVERY BLOCK
// ═════════════════════════════════════════════════════════════════════════════

class _DissectBlockFigurePainter extends CustomPainter {
  final _BlockCanvasKind kind;
  final _DissectModelSpec model;
  final double progress;
  final bool isDark;
  final int fpnScale;
  final bool showLetterboxFix;
  final int ocrArch;
  final int srArch;

  const _DissectBlockFigurePainter({
    required this.kind,
    required this.model,
    required this.progress,
    required this.isDark,
    required this.fpnScale,
    required this.showLetterboxFix,
    required this.ocrArch,
    required this.srArch,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final border = isDark ? const Color(0xFF263244) : const Color(0xFFCBD5E1);
    final fill = isDark ? const Color(0xFF131A26) : const Color(0xFFF1F5F9);
    final text = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const blue = Color(0xFF3B82F6);
    const green = Color(0xFF10B981);
    const amber = Color(0xFFF59E0B);
    const red = Color(0xFFEF4444);

    final gridPaint = Paint()
      ..color = border.withOpacity(0.25)
      ..strokeWidth = 0.5;
    for (double x = 24; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 24; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    switch (kind) {
      case _BlockCanvasKind.yoloLetterbox:
        _paintYoloLetterbox(canvas, size, fill, border, text, muted, blue, green, red);
        break;
      case _BlockCanvasKind.yoloBackbone:
        _paintYoloBackbone(canvas, size, fill, border, text, muted, blue, green, amber);
        break;
      case _BlockCanvasKind.yoloNeckPanet:
        _paintYoloNeckPanet(canvas, size, fill, border, text, muted, blue, green, amber);
        break;
      case _BlockCanvasKind.yoloDecoupledHead:
        _paintYoloDecoupledHead(canvas, size, fill, border, text, muted, blue, green, amber);
        break;
      case _BlockCanvasKind.yoloNmsUnbox:
        _paintYoloNmsUnbox(canvas, size, fill, border, text, muted, blue, green, red);
        break;
      case _BlockCanvasKind.reidPatchStem:
      case _BlockCanvasKind.reidResBlocks:
        _paintReidStages(canvas, size, fill, border, text, muted, blue, green, amber);
        break;
      case _BlockCanvasKind.reidUnitSphere:
        _paintReidSphere(canvas, size, fill, border, text, muted, blue, green, amber);
        break;
      case _BlockCanvasKind.reidKalmanHungarian:
        _paintReidKalman(canvas, size, fill, border, text, muted, blue, green, amber);
        break;
      case _BlockCanvasKind.srShallowExtract:
      case _BlockCanvasKind.srRrdbBlocks:
        _paintSrRrdb(canvas, size, fill, border, text, muted, blue, green, amber);
        break;
      case _BlockCanvasKind.srPixelShuffle4x:
      case _BlockCanvasKind.srLapSrnPyramid:
        _paintSrUpsample(canvas, size, fill, border, text, muted, blue, green, amber);
        break;
      case _BlockCanvasKind.ocrTpsUnwarp:
        _paintOcrTps(canvas, size, fill, border, text, muted, blue, green, amber);
        break;
      case _BlockCanvasKind.ocrFeatureSlices:
      case _BlockCanvasKind.ocrSequenceBilstm:
        _paintOcrSequence(canvas, size, fill, border, text, muted, blue, green, amber);
        break;
      case _BlockCanvasKind.ocrCtcDecode:
        _paintOcrCtc(canvas, size, fill, border, text, muted, blue, green, amber);
        break;
    }
  }

  void _paintYoloLetterbox(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color red,
  ) {
    final w = size.width;
    final h = size.height;
    final sz = model.family == _DissectFamily.yoloFull ? 640 : 320;

    final srcRect = Rect.fromLTWH(w * 0.05, h * 0.16, w * 0.22, h * 0.68);
    _drawBox(canvas, srcRect, fill, border);
    _drawText(canvas, '1. Raw Crop (BGR)', Offset(srcRect.left + 8, srcRect.top + 6), text, 10.5, bold: true);
    _drawText(canvas, 'Tall aspect (e.g. 140×280)', Offset(srcRect.left + 8, srcRect.top + 20), muted, 9.5, mono: true);

    final riderCenter = Offset(srcRect.center.dx, srcRect.center.dy + 10);
    canvas.drawCircle(Offset(riderCenter.dx, riderCenter.dy - 32), 16, Paint()..color = blue.withOpacity(0.28));
    canvas.drawCircle(
      Offset(riderCenter.dx, riderCenter.dy - 32),
      16,
      Paint()
        ..color = blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(riderCenter.dx, riderCenter.dy + 12), width: 38, height: 52),
        const Radius.circular(6),
      ),
      Paint()..color = blue.withOpacity(0.18),
    );

    _drawArrow(canvas, Offset(srcRect.right + 10, h * 0.5), Offset(w * 0.37, h * 0.5), blue);

    final sqSide = math.min(w * 0.28, h * 0.68);
    final sqRect = Rect.fromCenter(center: Offset(w * 0.52, h * 0.50), width: sqSide, height: sqSide);
    if (showLetterboxFix) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(sqRect, const Radius.circular(5)),
        Paint()..color = const Color(0xFF727272).withOpacity(0.45),
      );
      final innerW = sqSide * 0.52;
      final innerRect = Rect.fromCenter(center: sqRect.center, width: innerW, height: sqSide);
      canvas.drawRect(innerRect, Paint()..color = fill);
      canvas.drawCircle(Offset(sqRect.center.dx, sqRect.center.dy - 24), 15, Paint()..color = green.withOpacity(0.3));
      canvas.drawCircle(
        Offset(sqRect.center.dx, sqRect.center.dy - 24),
        15,
        Paint()
          ..color = green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      _drawText(canvas, 'PAD=114', Offset(sqRect.left + 4, sqRect.center.dy - 6), text, 8.5, mono: true);
      _drawText(canvas, 'PAD=114', Offset(sqRect.right - 42, sqRect.center.dy - 6), text, 8.5, mono: true);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(sqRect, const Radius.circular(5)), Paint()..color = fill);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(sqRect.center.dx, sqRect.center.dy - 24), width: 64, height: 24),
        Paint()..color = red.withOpacity(0.3),
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(sqRect.center.dx, sqRect.center.dy - 24), width: 64, height: 24),
        Paint()
          ..color = red
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(sqRect, const Radius.circular(5)),
      Paint()
        ..color = showLetterboxFix ? green : red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    _drawText(
      canvas,
      showLetterboxFix ? '2. Letterboxed $sz×$sz RGB' : '2. Stretched $sz×$sz BGR',
      Offset(sqRect.left, sqRect.top - 18),
      showLetterboxFix ? green : red,
      10,
      bold: true,
    );

    final rightRect = Rect.fromLTWH(w * 0.70, h * 0.16, w * 0.26, h * 0.68);
    _drawBox(canvas, rightRect, fill, border);
    _drawText(canvas, '3. Tensor [1, 3, $sz, $sz]', Offset(rightRect.left + 8, rightRect.top + 6), text, 10, bold: true, mono: true);
    _drawText(
      canvas,
      showLetterboxFix
          ? '• RGB order matched\n• Aspect ratio intact\n• float32 ∈ [0.0, 1.0]\n• Plate Recall: 85%'
          : '• Red/Blue swapped!\n• Geometry warped!\n• No NMS filtering\n• Plate Recall: 7%',
      Offset(rightRect.left + 8, rightRect.top + 28),
      showLetterboxFix ? green : red,
      10,
      mono: true,
    );
  }

  void _paintYoloBackbone(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color amber,
  ) {
    final w = size.width;
    final h = size.height;
    final sz = model.family == _DissectFamily.yoloFull ? 640 : 320;
    final stages = [
      ('Stem', '${sz ~/ 2}²', '16c', 0.68),
      ('C2f-1', '${sz ~/ 4}²', '32c', 0.56),
      ('C2f-2 (P3)', '${sz ~/ 8}²', '64c', 0.45),
      ('C2f-3 (P4)', '${sz ~/ 16}²', '128c', 0.35),
      ('SPPF (P5)', '${sz ~/ 32}²', '256c', 0.25),
    ];

    final startX = w * 0.04;
    final stepX = (w * 0.52) / stages.length;

    for (int i = 0; i < stages.length; i++) {
      final st = stages[i];
      final boxH = h * st.$4;
      final boxW = stepX * 0.72;
      final rect = Rect.fromCenter(
        center: Offset(startX + i * stepX + boxW / 2, h * 0.52),
        width: boxW,
        height: boxH,
      );
      final isPulse = ((progress * stages.length).floor() % stages.length) == i;
      _drawBox(canvas, rect, isPulse ? blue.withOpacity(0.18) : fill, isPulse ? blue : border);
      _drawText(canvas, st.$1, Offset(rect.left + 4, rect.top - 16), text, 9.5, bold: true);
      _drawText(canvas, st.$2, Offset(rect.left + 5, rect.center.dy - 10), blue, 9.5, mono: true, bold: true);
      _drawText(canvas, st.$3, Offset(rect.left + 5, rect.center.dy + 4), muted, 9, mono: true);
      if (i < stages.length - 1) {
        _drawArrow(
          canvas,
          Offset(rect.right + 2, h * 0.52),
          Offset(startX + (i + 1) * stepX - 2, h * 0.52),
          muted,
        );
      }
    }

    final c2fRect = Rect.fromLTWH(w * 0.58, h * 0.12, w * 0.39, h * 0.78);
    _drawBox(canvas, c2fRect, fill, border);
    _drawText(
      canvas,
      'Inside Each C2f Block (Gradient Highway)',
      Offset(c2fRect.left + 10, c2fRect.top + 8),
      text,
      10.5,
      bold: true,
    );

    final splitRect = Rect.fromLTWH(c2fRect.left + 12, c2fRect.top + 38, 56, 36);
    final hwRect = Rect.fromLTWH(c2fRect.left + 90, c2fRect.top + 30, 95, 24);
    final bnRect = Rect.fromLTWH(c2fRect.left + 90, c2fRect.top + 66, 95, 28);
    final catRect = Rect.fromLTWH(c2fRect.right - 72, c2fRect.top + 42, 60, 40);

    _drawBox(canvas, splitRect, fill, blue);
    _drawText(canvas, '1×1 Split', Offset(splitRect.left + 5, splitRect.top + 11), text, 9, mono: true);

    _drawBox(canvas, hwRect, green.withOpacity(0.14), green);
    _drawText(canvas, 'Direct Highway', Offset(hwRect.left + 6, hwRect.top + 5), green, 9, bold: true);

    _drawBox(canvas, bnRect, amber.withOpacity(0.14), amber);
    _drawText(canvas, '3×3 Bottlenecks', Offset(bnRect.left + 6, bnRect.top + 7), amber, 9, bold: true);

    _drawBox(canvas, catRect, blue.withOpacity(0.16), blue);
    _drawText(canvas, 'Concat\n+ 1×1', Offset(catRect.left + 8, catRect.top + 6), text, 9, mono: true);

    _drawArrow(canvas, Offset(splitRect.right, splitRect.top + 10), Offset(hwRect.left, hwRect.center.dy), green);
    _drawArrow(canvas, Offset(splitRect.right, splitRect.bottom - 8), Offset(bnRect.left, bnRect.center.dy), amber);
    _drawArrow(canvas, Offset(hwRect.right, hwRect.center.dy), Offset(catRect.left, catRect.top + 12), green);
    _drawArrow(canvas, Offset(bnRect.right, bnRect.center.dy), Offset(catRect.left, catRect.bottom - 12), amber);

    _drawText(
      canvas,
      'Half the channels bypass heavy convolutions completely so early edge features never vanish.',
      Offset(c2fRect.left + 12, c2fRect.bottom - 38),
      muted,
      9.5,
      maxWidth: c2fRect.width - 24,
    );
  }

  void _paintYoloNeckPanet(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color amber,
  ) {
    final w = size.width;
    final h = size.height;
    final sz = model.family == _DissectFamily.yoloFull ? 640 : 320;
    final scales = [
      ('P3 High-Res (/8)', '${sz ~/ 8}×${sz ~/ 8} grid', 'Small targets: Plates, Mirrors, Phones', green),
      ('P4 Mid-Res (/16)', '${sz ~/ 16}×${sz ~/ 16} grid', 'Medium targets: Helmets, Seatbelts, Bikes', blue),
      ('P5 Coarse (/32)', '${sz ~/ 32}×${sz ~/ 32} grid', 'Large targets: Cars, Buses, Trucks, Cabins', amber),
    ];

    for (int i = 0; i < 3; i++) {
      final isSel = fpnScale == i;
      final rowY = h * 0.14 + i * (h * 0.27);
      final rowRect = Rect.fromLTWH(w * 0.04, rowY, w * 0.54, h * 0.22);
      final col = scales[i].$4;
      _drawBox(canvas, rowRect, isSel ? col.withOpacity(0.15) : fill, isSel ? col : border);
      _drawText(canvas, scales[i].$1, Offset(rowRect.left + 10, rowRect.top + 6), col, 10.5, bold: true);
      _drawText(canvas, scales[i].$2, Offset(rowRect.left + 150, rowRect.top + 6), text, 10, mono: true);
      _drawText(canvas, scales[i].$3, Offset(rowRect.left + 10, rowRect.top + 23), muted, 9.5);
    }

    final gridRect = Rect.fromLTWH(w * 0.62, h * 0.14, w * 0.34, h * 0.76);
    _drawBox(canvas, gridRect, fill, scales[fpnScale].$4);
    final divisions = fpnScale == 0 ? 12 : (fpnScale == 1 ? 7 : 4);
    final cellW = (gridRect.width - 24) / divisions;
    final cellH = (gridRect.height - 46) / divisions;
    final gridArea = Rect.fromLTWH(gridRect.left + 12, gridRect.top + 32, gridRect.width - 24, gridRect.height - 46);

    final gPaint = Paint()
      ..color = scales[fpnScale].$4.withOpacity(0.45)
      ..strokeWidth = 1.0;
    for (int r = 0; r <= divisions; r++) {
      final y = gridArea.top + r * cellH;
      canvas.drawLine(Offset(gridArea.left, y), Offset(gridArea.right, y), gPaint);
    }
    for (int c = 0; c <= divisions; c++) {
      final x = gridArea.left + c * cellW;
      canvas.drawLine(Offset(x, gridArea.top), Offset(x, gridArea.bottom), gPaint);
    }

    final activeR = (divisions ~/ 2);
    final activeC = (divisions ~/ 2);
    final activeCell = Rect.fromLTWH(
      gridArea.left + activeC * cellW,
      gridArea.top + activeR * cellH,
      cellW,
      cellH,
    );
    canvas.drawRect(activeCell, Paint()..color = scales[fpnScale].$4.withOpacity(0.38));
    _drawText(
      canvas,
      'Active Scale: ${scales[fpnScale].$2}',
      Offset(gridRect.left + 12, gridRect.top + 8),
      scales[fpnScale].$4,
      10.5,
      bold: true,
      mono: true,
    );
  }

  void _paintYoloDecoupledHead(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color amber,
  ) {
    final w = size.width;
    final h = size.height;

    final inRect = Rect.fromLTWH(w * 0.04, h * 0.34, w * 0.18, h * 0.32);
    _drawBox(canvas, inRect, fill, border);
    _drawText(canvas, 'Neck Cell\nFeature', Offset(inRect.left + 10, inRect.top + 16), text, 10.5, bold: true);

    final boxBranch = Rect.fromLTWH(w * 0.30, h * 0.12, w * 0.34, h * 0.34);
    final clsBranch = Rect.fromLTWH(w * 0.30, h * 0.54, w * 0.34, h * 0.34);

    _drawArrow(canvas, Offset(inRect.right, inRect.top + 16), Offset(boxBranch.left, boxBranch.center.dy), blue);
    _drawArrow(canvas, Offset(inRect.right, inRect.bottom - 16), Offset(clsBranch.left, clsBranch.center.dy), green);

    _drawBox(canvas, boxBranch, blue.withOpacity(0.10), blue);
    _drawText(canvas, 'Branch A: Box Regression (DFL)', Offset(boxBranch.left + 8, boxBranch.top + 6), blue, 10, bold: true);
    _drawText(
      canvas,
      'Predicts 16-bin distribution for\nLeft, Top, Right, Bottom edges\n→ [cx, cy, bw, bh]',
      Offset(boxBranch.left + 8, boxBranch.top + 22),
      text,
      9.5,
      mono: true,
    );

    _drawBox(canvas, clsBranch, green.withOpacity(0.10), green);
    _drawText(canvas, 'Branch B: Class Probabilities', Offset(clsBranch.left + 8, clsBranch.top + 6), green, 10, bold: true);
    _drawText(
      canvas,
      'Independent Sigmoid σ(z) per class\n${model.classesOrOutputs.first}',
      Offset(clsBranch.left + 8, clsBranch.top + 24),
      text,
      9.5,
      mono: true,
      maxWidth: clsBranch.width - 16,
    );

    final outRect = Rect.fromLTWH(w * 0.70, h * 0.14, w * 0.26, h * 0.72);
    _drawBox(canvas, outRect, fill, border);
    _drawText(canvas, 'Anchor-Free Center→Edge', Offset(outRect.left + 8, outRect.top + 6), text, 10, bold: true);
    final center = Offset(outRect.center.dx, outRect.center.dy + 8);
    final predBox = Rect.fromCenter(center: center, width: outRect.width * 0.62, height: outRect.height * 0.52);
    canvas.drawRect(
      predBox,
      Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(center, 3.5, Paint()..color = amber);
    _drawArrow(canvas, center, Offset(predBox.left, center.dy), blue);
    _drawArrow(canvas, center, Offset(predBox.right, center.dy), blue);
    _drawArrow(canvas, center, Offset(center.dx, predBox.top), blue);
    _drawArrow(canvas, center, Offset(center.dx, predBox.bottom), blue);
  }

  void _paintYoloNmsUnbox(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color red,
  ) {
    final w = size.width;
    final h = size.height;

    final leftRect = Rect.fromLTWH(w * 0.04, h * 0.14, w * 0.40, h * 0.72);
    _drawBox(canvas, leftRect, fill, border);
    _drawText(canvas, 'Before NMS: Overlapping Candidates', Offset(leftRect.left + 10, leftRect.top + 8), text, 10.5, bold: true);

    final base = Rect.fromCenter(center: Offset(leftRect.center.dx, leftRect.center.dy + 10), width: 88, height: 64);
    for (final shift in [const Offset(-10, -6), const Offset(8, 7), const Offset(-5, 9)]) {
      canvas.drawRect(
        base.shift(shift),
        Paint()
          ..color = red.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    canvas.drawRect(
      base,
      Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    _drawText(canvas, 'conf=0.91 (Keep)', Offset(base.left, base.top - 14), green, 9.5, mono: true, bold: true);
    _drawText(canvas, 'IoU > 0.45 → Dropped', Offset(base.left, base.bottom + 4), red, 9, mono: true);

    _drawArrow(canvas, Offset(leftRect.right + 8, h * 0.5), Offset(w * 0.54, h * 0.5), blue);

    final rightRect = Rect.fromLTWH(w * 0.56, h * 0.14, w * 0.40, h * 0.72);
    _drawBox(canvas, rightRect, fill, green);
    _drawText(canvas, 'After NMS + _to_frame() Projection', Offset(rightRect.left + 10, rightRect.top + 8), green, 10.5, bold: true);
    final cleanBox = Rect.fromCenter(center: Offset(rightRect.center.dx, rightRect.center.dy + 4), width: 92, height: 64);
    canvas.drawRect(cleanBox, Paint()..color = green.withOpacity(0.16));
    canvas.drawRect(
      cleanBox,
      Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    _drawText(
      canvas,
      'x = (cx - bw/2 - pad_x) / scale + origin_x',
      Offset(rightRect.left + 10, rightRect.bottom - 22),
      muted,
      9,
      mono: true,
      maxWidth: rightRect.width - 16,
    );
  }

  void _paintReidStages(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color amber,
  ) {
    final w = size.width;
    final h = size.height;
    final stages = [
      ('Input', '192×96', '3c', 0.74),
      ('Stem', '96×48', '64c', 0.62),
      ('layer1', '96×48', '64c', 0.58),
      ('layer2', '48×24', '128c', 0.48),
      ('layer3', '24×12', '256c', 0.38),
      ('layer4', '12×6', '512c', 0.28),
    ];
    final startX = w * 0.04;
    final stepX = (w * 0.92) / stages.length;

    for (int i = 0; i < stages.length; i++) {
      final st = stages[i];
      final bh = h * st.$4;
      final bw = stepX * 0.74;
      final r = Rect.fromCenter(
        center: Offset(startX + i * stepX + bw / 2, h * 0.52),
        width: bw,
        height: bh,
      );
      final active = ((progress * stages.length).floor() % stages.length) == i;
      _drawBox(canvas, r, active ? blue.withOpacity(0.18) : fill, active ? blue : border);
      _drawText(canvas, st.$1, Offset(r.left + 4, r.top - 16), text, 9.5, bold: true);
      _drawText(canvas, st.$2, Offset(r.left + 5, r.center.dy - 10), blue, 9.5, mono: true, bold: true);
      _drawText(canvas, st.$3, Offset(r.left + 5, r.center.dy + 4), green, 9.5, mono: true);
      if (i < stages.length - 1) {
        _drawArrow(canvas, Offset(r.right + 2, h * 0.52), Offset(startX + (i + 1) * stepX - 2, h * 0.52), muted);
      }
    }
  }

  void _paintReidSphere(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color amber,
  ) {
    final w = size.width;
    final h = size.height;

    final leftRect = Rect.fromLTWH(w * 0.04, h * 0.16, w * 0.36, h * 0.68);
    _drawBox(canvas, leftRect, fill, border);
    _drawText(canvas, 'AdaptiveAvgPool2d(1)', Offset(leftRect.left + 10, leftRect.top + 8), text, 10.5, bold: true, mono: true);
    _drawText(
      canvas,
      '[B, 512, 12, 6] → [B, 512]\n\nL2 Normalize:\nv_unit = v / ||v||₂\nLength is always 1.000',
      Offset(leftRect.left + 10, leftRect.top + 30),
      muted,
      10,
      mono: true,
    );

    final center = Offset(w * 0.70, h * 0.52);
    final radius = math.min(w * 0.22, h * 0.36);
    canvas.drawCircle(center, radius, Paint()..color = blue.withOpacity(0.08));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = blue.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    final pQuery = Offset(center.dx + radius * math.cos(-0.65), center.dy + radius * math.sin(-0.65));
    final pSame = Offset(center.dx + radius * math.cos(-0.42), center.dy + radius * math.sin(-0.42));
    final pDiff = Offset(center.dx + radius * math.cos(0.85), center.dy + radius * math.sin(0.85));

    _drawArrow(canvas, center, pQuery, blue);
    _drawArrow(canvas, center, pSame, green);
    _drawArrow(canvas, center, pDiff, amber);

    _drawText(canvas, 'Car #14 (Frame 1)', Offset(pQuery.dx + 6, pQuery.dy - 10), blue, 9.5, bold: true);
    _drawText(canvas, 'Car #14 (Frame 8) dist=0.08 ✓', Offset(pSame.dx + 6, pSame.dy + 2), green, 9.5, mono: true, bold: true);
    _drawText(canvas, 'Other Car dist=0.78 ✗', Offset(pDiff.dx + 6, pDiff.dy), amber, 9.5, mono: true);
  }

  void _paintReidKalman(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color amber,
  ) {
    final w = size.width;
    final h = size.height;

    final trackY = h * 0.50;
    final x1 = w * 0.10;
    final xOcc = w * 0.46;
    final x2 = w * 0.82;

    canvas.drawLine(
      Offset(x1, trackY),
      Offset(x2, trackY),
      Paint()
        ..color = green.withOpacity(0.6)
        ..strokeWidth = 2.0,
    );

    final b1 = Rect.fromCenter(center: Offset(x1, trackY), width: 72, height: 50);
    _drawBox(canvas, b1, green.withOpacity(0.16), green);
    _drawText(canvas, 'Track #7\nt = 0.0s', Offset(b1.left + 8, b1.top + 10), green, 9.5, mono: true, bold: true);

    final occ = Rect.fromCenter(center: Offset(xOcc, trackY), width: 110, height: 68);
    _drawBox(canvas, occ, amber.withOpacity(0.14), amber);
    _drawText(canvas, 'Bus Occlusion\nKalman Predicts\n(Buffer <= 90f)', Offset(occ.left + 8, occ.top + 10), amber, 9.5, mono: true);

    final b2 = Rect.fromCenter(center: Offset(x2, trackY), width: 84, height: 50);
    _drawBox(canvas, b2, green.withOpacity(0.18), green);
    _drawText(canvas, 'Same Track #7!\ncos_dist=0.14', Offset(b2.left + 6, b2.top + 10), green, 9.5, mono: true, bold: true);
  }

  void _paintSrRrdb(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color amber,
  ) {
    final w = size.width;
    final h = size.height;

    final startX = w * 0.05;
    final blockW = (w * 0.88) / 8;
    final labels = ['conv_first\n3→32c', 'RRDB 1', 'RRDB 2', 'RRDB 3', 'RRDB 4', 'RRDB 5', 'RRDB 6', 'Sum + F₀\n32c'];

    final skipY = h * 0.18;
    canvas.drawLine(
      Offset(startX + blockW * 0.5, skipY),
      Offset(startX + blockW * 7.5, skipY),
      Paint()
        ..color = green
        ..strokeWidth = 1.6,
    );
    _drawText(canvas, 'Global Residual Skip Highway (F₀ preserved across all 6 RRDB blocks)', Offset(w * 0.20, skipY - 15), green, 9.5, bold: true);

    for (int i = 0; i < 8; i++) {
      final bx = startX + i * blockW;
      final r = Rect.fromLTWH(bx + 3, h * 0.36, blockW - 6, h * 0.44);
      final isRrdb = i >= 1 && i <= 6;
      final isPulse = ((progress * 8).floor() % 8) == i;
      _drawBox(
        canvas,
        r,
        isPulse ? blue.withOpacity(0.22) : (isRrdb ? fill : green.withOpacity(0.12)),
        isPulse ? blue : (isRrdb ? border : green),
      );
      _drawText(canvas, labels[i], Offset(r.left + 4, r.top + 14), text, 9, mono: true, bold: isRrdb);
    }
  }

  void _paintSrUpsample(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color amber,
  ) {
    final w = size.width;
    final h = size.height;
    final isLapSrn = srArch == 1;

    final steps = isLapSrn
        ? [
            ('1. LR Input', '16×8 px', 0.24, amber),
            ('2. Pyramid ×2', '32×16 px', 0.38, blue),
            ('3. Pyramid ×4', '64×32 px', 0.54, blue),
            ('4. LapSRN ×8', '128×64 px', 0.72, green),
          ]
        : [
            ('1. LR Input', '32×8 px', 0.28, amber),
            ('2. upconv1 (×2)', '64×16 px', 0.48, blue),
            ('3. upconv2 (×4)', '128×32 px', 0.68, green),
            ('4. Crisp RGB Plate', 'ABC 1234', 0.72, green),
          ];

    final stepW = (w * 0.90) / steps.length;
    for (int i = 0; i < steps.length; i++) {
      final st = steps[i];
      final bh = h * st.$3;
      final r = Rect.fromCenter(
        center: Offset(w * 0.05 + i * stepW + stepW / 2, h * 0.54),
        width: stepW * 0.80,
        height: bh,
      );
      _drawBox(canvas, r, st.$4.withOpacity(0.12), st.$4);
      _drawText(canvas, st.$1, Offset(r.left + 6, r.top + 6), st.$4, 9.5, bold: true);
      _drawText(canvas, st.$2, Offset(r.left + 6, r.center.dy), text, 10.5, mono: true, bold: true);
    }
  }

  void _paintOcrTps(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color amber,
  ) {
    final w = size.width;
    final h = size.height;

    final leftBox = Rect.fromLTWH(w * 0.05, h * 0.16, w * 0.38, h * 0.68);
    _drawBox(canvas, leftBox, fill, border);
    _drawText(canvas, '1. Skewed CCTV Plate + 20 Fiducial Points', Offset(leftBox.left + 8, leftBox.top + 6), text, 10, bold: true);

    final path = Path()
      ..moveTo(leftBox.left + 22, leftBox.top + 62)
      ..lineTo(leftBox.right - 18, leftBox.top + 38)
      ..lineTo(leftBox.right - 26, leftBox.bottom - 26)
      ..lineTo(leftBox.left + 16, leftBox.bottom - 14)
      ..close();
    canvas.drawPath(path, Paint()..color = amber.withOpacity(0.16));
    canvas.drawPath(
      path,
      Paint()
        ..color = amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (int i = 0; i < 6; i++) {
      final t = i / 5.0;
      final topPt = Offset(
        (leftBox.left + 22) + ((leftBox.right - 18) - (leftBox.left + 22)) * t,
        (leftBox.top + 62) + ((leftBox.top + 38) - (leftBox.top + 62)) * t,
      );
      final botPt = Offset(
        (leftBox.left + 16) + ((leftBox.right - 26) - (leftBox.left + 16)) * t,
        (leftBox.bottom - 14) + ((leftBox.bottom - 26) - (leftBox.bottom - 14)) * t,
      );
      canvas.drawCircle(topPt, 3, Paint()..color = blue);
      canvas.drawCircle(botPt, 3, Paint()..color = blue);
    }

    _drawArrow(canvas, Offset(leftBox.right + 8, h * 0.5), Offset(w * 0.54, h * 0.5), blue);

    final rightBox = Rect.fromLTWH(w * 0.56, h * 0.16, w * 0.39, h * 0.68);
    _drawBox(canvas, rightBox, fill, green);
    _drawText(canvas, '2. TPS Un-Warped Strip (32×100 / 32×320)', Offset(rightBox.left + 8, rightBox.top + 6), green, 10, bold: true);
    final flatPlate = Rect.fromCenter(center: Offset(rightBox.center.dx, rightBox.center.dy + 8), width: rightBox.width * 0.82, height: 48);
    _drawBox(canvas, flatPlate, green.withOpacity(0.14), green);
    _drawText(canvas, 'N B C  1 2 3 4', Offset(flatPlate.left + 18, flatPlate.top + 12), text, 15, mono: true, bold: true);
  }

  void _paintOcrSequence(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color amber,
  ) {
    final w = size.width;
    final h = size.height;

    final stripRect = Rect.fromLTWH(w * 0.06, h * 0.14, w * 0.88, h * 0.28);
    _drawBox(canvas, stripRect, fill, border);
    _drawText(canvas, 'N   B   C     1   2   3   4', Offset(stripRect.left + 28, stripRect.top + 14), text, 16, mono: true, bold: true);

    const slices = 14;
    final sliceW = stripRect.width / slices;
    final activeSlice = (progress * slices).floor() % slices;
    for (int i = 0; i < slices; i++) {
      final sx = stripRect.left + i * sliceW;
      final r = Rect.fromLTWH(sx, stripRect.top, sliceW, stripRect.height);
      if (i == activeSlice) {
        canvas.drawRect(r, Paint()..color = blue.withOpacity(0.28));
      }
      canvas.drawLine(Offset(sx, stripRect.top), Offset(sx, stripRect.bottom), Paint()..color = border);
    }

    final seqRect = Rect.fromLTWH(w * 0.06, h * 0.52, w * 0.88, h * 0.34);
    _drawBox(canvas, seqRect, blue.withOpacity(0.10), blue);
    _drawText(
      canvas,
      ocrArch == 0
          ? 'EasyOCR Sequence Stack: ResNet (512c) → 2-Layer BiLSTM (Forward ⇄ Backward, 256h) → 37 CTC Logits/Slice'
          : 'PaddleOCR Sequence Stack: MobileNetV1Enhance → SVTR Global Self-Attention (8 heads) + SAR 2D Decoder',
      Offset(seqRect.left + 12, seqRect.top + 10),
      blue,
      10,
      bold: true,
      maxWidth: seqRect.width - 24,
    );
    _drawText(
      canvas,
      'Each vertical column T_i shares context with neighboring columns so "I", "1", "N", and "M" are never confused.',
      Offset(seqRect.left + 12, seqRect.top + 34),
      muted,
      10,
      maxWidth: seqRect.width - 24,
    );
  }

  void _paintOcrCtc(
    Canvas canvas,
    Size size,
    Color fill,
    Color border,
    Color text,
    Color muted,
    Color blue,
    Color green,
    Color amber,
  ) {
    final w = size.width;
    final h = size.height;

    final r1 = Rect.fromLTWH(w * 0.05, h * 0.10, w * 0.90, h * 0.24);
    final r2 = Rect.fromLTWH(w * 0.05, h * 0.40, w * 0.90, h * 0.24);
    final r3 = Rect.fromLTWH(w * 0.05, h * 0.70, w * 0.90, h * 0.24);

    _drawBox(canvas, r1, fill, border);
    _drawText(canvas, '1. Raw Per-Slice CTC Tokens:', Offset(r1.left + 10, r1.top + 6), muted, 9.5);
    _drawText(canvas, '[ N | N | ∅ | B | B | C | ∅ | 1 | 2 | 3 | A ]', Offset(r1.left + 10, r1.top + 22), text, 11, mono: true, bold: true);

    _drawBox(canvas, r2, blue.withOpacity(0.10), blue);
    _drawText(canvas, '2. CTC Repeat Merge + Blank (∅) Removal:', Offset(r2.left + 10, r2.top + 6), blue, 9.5, bold: true);
    _drawText(canvas, '"NBC123A"  (Slot 6 has letter "A" in a digit position!)', Offset(r2.left + 10, r2.top + 22), text, 11, mono: true);

    _drawBox(canvas, r3, green.withOpacity(0.14), green);
    _drawText(canvas, '3. ph_standard Positional Syntax Repair + 40-Crop Vote:', Offset(r3.left + 10, r3.top + 6), green, 9.5, bold: true);
    _drawText(canvas, '"NBC1234"  (dict_char_to_int["A"] → "4" at index 6 · Final Ticket Plate)', Offset(r3.left + 10, r3.top + 22), green, 11, mono: true, bold: true);
  }

  void _drawBox(Canvas canvas, Rect rect, Color fill, Color border) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(rrect, Paint()..color = fill);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = border
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, to, paint);
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    const head = 5.5;
    final p1 = Offset(to.dx - head * math.cos(angle - 0.5), to.dy - head * math.sin(angle - 0.5));
    final p2 = Offset(to.dx - head * math.cos(angle + 0.5), to.dy - head * math.sin(angle + 0.5));
    canvas.drawLine(to, p1, paint);
    canvas.drawLine(to, p2, paint);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset pos,
    Color color,
    double size, {
    bool bold = false,
    bool mono = false,
    double maxWidth = 340,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: mono
            ? GoogleFonts.firaCode(
                fontSize: size,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                color: color,
              )
            : GoogleFonts.lexend(
                fontSize: size,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _DissectBlockFigurePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.kind != kind ||
        oldDelegate.model.id != model.id ||
        oldDelegate.fpnScale != fpnScale ||
        oldDelegate.showLetterboxFix != showLetterboxFix ||
        oldDelegate.ocrArch != ocrArch ||
        oldDelegate.srArch != srArch ||
        oldDelegate.isDark != isDark;
  }
}
