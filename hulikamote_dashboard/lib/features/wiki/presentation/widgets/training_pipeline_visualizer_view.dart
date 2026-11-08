import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TrainingPipelineVisualizerView extends StatefulWidget {
  const TrainingPipelineVisualizerView({super.key});

  @override
  State<TrainingPipelineVisualizerView> createState() =>
      _TrainingPipelineVisualizerViewState();
}

enum _PipelineKind { yolo, ocr, reid, sr }

class _ModelSpec {
  final String id;
  final String label;
  final _PipelineKind kind;
  final String pipelineGroupLabel;
  final String architecture;
  final String artifact;
  final int imgsz;
  final int epochs;
  final double targetMap;
  final String targetMetricLabel;
  final String inputSpec;
  final String classesSpec;
  final String outputDir;
  final String sampleSourceName;
  final String sampleMappedClass;
  final String sampleDroppedClass;
  final String sampleBoxCoords;
  final String cropRuleDesc;

  String get classMapSummary => classesSpec;

  const _ModelSpec({
    required this.id,
    required this.label,
    required this.kind,
    required this.pipelineGroupLabel,
    required this.architecture,
    required this.artifact,
    required this.imgsz,
    required this.epochs,
    required this.targetMap,
    required this.targetMetricLabel,
    required this.inputSpec,
    required this.classesSpec,
    required this.outputDir,
    required this.sampleSourceName,
    required this.sampleMappedClass,
    required this.sampleDroppedClass,
    required this.sampleBoxCoords,
    required this.cropRuleDesc,
  });
}

enum _MicroCanvasType {
  yoloIngest,
  yoloSheet,
  yoloCurate,
  yoloSplit,
  yoloAugment,
  yoloArch,
  yoloLoss,
  yoloVal,
  yoloExport,
  ocrHarvest,
  ocrDict,
  ocrTps,
  ocrCtc,
  ocrExport,
  reidHarvest,
  reidSplit,
  reidTrain,
  reidGate,
  reidDeploy,
  srGate,
  srPairs,
  srRrdb,
  srLoss,
  srExport,
}

class _StageSpec {
  final int index;
  final String numLabel;
  final String navLabel;
  final String title;
  final String scriptPath;
  final String summary;
  final List<(String, String)> specs;
  final String command;
  final _MicroCanvasType canvasType;

  const _StageSpec({
    required this.index,
    required this.numLabel,
    required this.navLabel,
    required this.title,
    required this.scriptPath,
    required this.summary,
    required this.specs,
    required this.command,
    required this.canvasType,
  });
}

class _TrainingPipelineVisualizerViewState
    extends State<TrainingPipelineVisualizerView>
    with TickerProviderStateMixin {
  static const Color _kSignalBlue = Color(0xFF3B82F6);
  static const Color _kSemanticPass = Color(0xFF10B981);

  int _activeStage = 0;
  String _selectedModelId = 'helmet_specialist';
  bool _isAutoPlaying = false;
  bool _singleStageFocusMode = false;
  double _playbackSpeed = 1.0;

  // Interactive micro-controls inside stage figures
  bool _quarantineProtected = true;
  int _selectedAugMode = 0; // 0: Mosaic (4-Way), 1: Flip (x' = 1-x), 2: Rain & Low Light
  int _selectedFpnScale = 0; // 0: P3 (80x80), 1: P4 (40x40), 2: P5 (20x20)
  int _selectedOcrEngine = 0; // 0: EasyOCR (TPS-ResNet-BiLSTM-CTC), 1: PaddleOCR (SVTR_LCNet)
  double _manualEpochScrub = -1.0;

  late final AnimationController _continuousController;
  late final ScrollController _scrollController;
  List<GlobalKey> _stageKeys = List.generate(9, (_) => GlobalKey());

  static const List<_ModelSpec> _models = [
    _ModelSpec(
      id: 'helmet_specialist',
      label: 'Helmet Specialist',
      kind: _PipelineKind.yolo,
      pipelineGroupLabel: 'Pipeline 1 of 4: YOLOv8 Detection Lab',
      architecture: 'YOLOv8n Crop Detector',
      artifact: 'helmet_specialist.onnx',
      imgsz: 320,
      epochs: 150,
      targetMap: 0.85,
      targetMetricLabel: 'mAP@0.50 >= 0.85',
      inputSpec: '320×320 motorcycle-rider crop',
      classesSpec: '0: rider_with_helmet, 1: rider_without_helmet',
      outputDir: 'Helmet Detectors',
      sampleSourceName: 'martinez_helmet__00412.jpg',
      sampleMappedClass: 'Full-Faced → 0: rider_with_helmet',
      sampleDroppedClass: 'Invalid / BikeWithRider → dropped',
      sampleBoxCoords: '0 0.485 0.520 0.360 0.720',
      cropRuleDesc: 'crop_to: motorcycle-rider (+10% margin)',
    ),
    _ModelSpec(
      id: 'plate_specialist',
      label: 'Plate Specialist',
      kind: _PipelineKind.yolo,
      pipelineGroupLabel: 'Pipeline 1 of 4: YOLOv8 Detection Lab',
      architecture: 'YOLOv8n Crop Detector',
      artifact: 'plate_specialist.onnx',
      imgsz: 320,
      epochs: 100,
      targetMap: 0.90,
      targetMetricLabel: 'mAP@0.50 >= 0.90',
      inputSpec: '320×320 vehicle crop',
      classesSpec: '0: license_plate',
      outputDir: 'Plate Models',
      sampleSourceName: 'oi_plates__01842.jpg',
      sampleMappedClass: 'Vehicle registration plate → 0: license_plate',
      sampleDroppedClass: 'Car / Wheel → unmapped (dropped)',
      sampleBoxCoords: '0 0.512 0.740 0.240 0.085',
      cropRuleDesc: 'crop_to: vehicle (+10% margin)',
    ),
    _ModelSpec(
      id: 'cabin_specialist',
      label: 'Cabin Specialist',
      kind: _PipelineKind.yolo,
      pipelineGroupLabel: 'Pipeline 1 of 4: YOLOv8 Detection Lab',
      architecture: 'YOLOv8n Crop Detector',
      artifact: 'cabin_specialist.onnx',
      imgsz: 320,
      epochs: 150,
      targetMap: 0.80,
      targetMetricLabel: 'mAP@0.50 >= 0.80',
      inputSpec: '320×320 windshield & moto crop',
      classesSpec: '0: clear_window, 1: tinted_window, 2: seatbelt, 3: driver_phone, 4: side_mirror',
      outputDir: 'Cabin Models',
      sampleSourceName: 'menna_cabin__00219.jpg',
      sampleMappedClass: 'seat-belt → 2: seatbelt | using_mobile → 3: driver_phone',
      sampleDroppedClass: 'un seat-belt → unmapped (absence = violation)',
      sampleBoxCoords: '2 0.440 0.510 0.290 0.480',
      cropRuleDesc: 'Windshield & motorcycle frame crop (320×320)',
    ),
    _ModelSpec(
      id: 'primary_anchor',
      label: 'Primary Anchor',
      kind: _PipelineKind.yolo,
      pipelineGroupLabel: 'Pipeline 1 of 4: YOLOv8 Detection Lab',
      architecture: 'YOLOv8n Full-Frame Detector',
      artifact: 'yolov8n.onnx',
      imgsz: 640,
      epochs: 50,
      targetMap: 0.80,
      targetMetricLabel: 'mAP@0.50 >= 0.80',
      inputSpec: '640×640 full CCTV frame',
      classesSpec: '0: motorcycle, 1: car, 2: bus, 3: truck',
      outputDir: 'Vehicle Detectors',
      sampleSourceName: 'coco_ph_traffic__00914.jpg',
      sampleMappedClass: 'Motorbike → 0: motorcycle | Car → 1: car',
      sampleDroppedClass: 'Pedestrian / Traffic light → dropped',
      sampleBoxCoords: '0 0.485 0.520 0.180 0.340',
      cropRuleDesc: 'Full 640×640 frame (no sub-crop; feeds all specialists)',
    ),
    _ModelSpec(
      id: 'plate_ocr',
      label: 'Plate OCR',
      kind: _PipelineKind.ocr,
      pipelineGroupLabel: 'Pipeline 2 of 4: Sequence OCR Fine-Tuner',
      architecture: 'EasyOCR (CRNN) / PaddleOCR (SVTR)',
      artifact: 'easyocr_custom_rec.pth',
      imgsz: 100,
      epochs: 30,
      targetMap: 0.92,
      targetMetricLabel: 'Char Acc >= 92%',
      inputSpec: '32×100 (EasyOCR) / 3×32×320 (PaddleOCR)',
      classesSpec: '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ (36 chars)',
      outputDir: 'hulikamote_backend/models',
      sampleSourceName: 'datasets/plate_ocr/images/train/*.jpg',
      sampleMappedClass: '0 ABC1234 → image_path\\tABC1234',
      sampleDroppedClass: 'Empty string (false-positive background) → skipped',
      sampleBoxCoords: '36-char CTC sequence alignment',
      cropRuleDesc: 'Tight plate crops from Forensic Pop Quiz',
    ),
    _ModelSpec(
      id: 'reid',
      label: 'Vehicle ReID',
      kind: _PipelineKind.reid,
      pipelineGroupLabel: 'Pipeline 3 of 4: DeepSORT Appearance Metric Lab',
      architecture: 'DeepSORT 192×96 Metric CNN',
      artifact: 'ckpt.t7',
      imgsz: 192,
      epochs: 30,
      targetMap: 0.02,
      targetMetricLabel: 'Unseen Rank-1 Gain >= +2%',
      inputSpec: '192×96 (H×W) vehicle tracklet crops',
      classesSpec: '128-D L2-normalized cosine embedding',
      outputDir: 'engine/deep_sort/deep/checkpoint',
      sampleSourceName: 'datasets/reid/images/<task>/<identity>/*.jpg',
      sampleMappedClass: 'Folder of >= 2 time-ordered photos → 1 car identity',
      sampleDroppedClass: 'Identities with only 1 photo → skipped',
      sampleBoxCoords: 'spread(files, MAX_PHOTOS=40)',
      cropRuleDesc: '75% train cars / 25% unseen holdout cars',
    ),
    _ModelSpec(
      id: 'plate_enhancer',
      label: 'Plate Enhancer (SR)',
      kind: _PipelineKind.sr,
      pipelineGroupLabel: 'Pipeline 4 of 4: Real-ESRGAN Super-Resolution Lab',
      architecture: 'RRDBNet (6-block ×4 GAN)',
      artifact: 'realesrgan.onnx',
      imgsz: 128,
      epochs: 200,
      targetMap: 40.0,
      targetMetricLabel: 'Laplacian >= 40.0 & ×4 PSNR',
      inputSpec: '32px LR → 128px HR paired plate crops',
      classesSpec: 'RGB ×4 super-resolution reconstruction',
      outputDir: 'hulikamote_backend/models',
      sampleSourceName: 'datasets/sr_plates/clean/{train,val,test}/*.jpg',
      sampleMappedClass: 'Sharp plate crop (Var >= 40.0) → 128px HR / 32px LR',
      sampleDroppedClass: 'Blurry (< 40.0) or non-plate aspect → rejected',
      sampleBoxCoords: 'HR 128×32 (Lanczos4) / LR 32×8 (Bicubic)',
      cropRuleDesc: 'Cut from plate_specialist boxes (+4% margin)',
    ),
  ];

  _ModelSpec get _currentModel =>
      _models.firstWhere((m) => m.id == _selectedModelId, orElse: () => _models.first);

  List<_StageSpec> _buildStages(_ModelSpec m) {
    switch (m.kind) {
      case _PipelineKind.yolo:
        return _buildYoloStages(m);
      case _PipelineKind.ocr:
        return _buildOcrStages(m);
      case _PipelineKind.reid:
        return _buildReidStages(m);
      case _PipelineKind.sr:
        return _buildSrStages(m);
    }
  }

  List<_StageSpec> _buildYoloStages(_ModelSpec m) {
    return [
      _StageSpec(
        index: 0,
        numLabel: '01',
        navLabel: '1. Ingest & Remap',
        title: 'Multi-source ingestion, polygon normalization, and crop slicing (${m.label})',
        scriptPath: 'training_lab/scripts/fetch_datasets.py',
        summary:
            'Public datasets arrive with foreign class names, polygon vertices, and uncropped street views. For ${m.label}, fetch_datasets.py downloads sources from datasets_manifest.yaml, converts polygons into normalized boxes, maps foreign labels to [${m.classesSpec}], and applies ${m.cropRuleDesc}.',
        specs: [
          ('Target model', '${m.id} (${m.architecture})'),
          ('Output directory', 'datasets/${m.id}/images/{train,val,test}'),
          ('Class remapping', m.sampleMappedClass),
          ('Dropped classes', m.sampleDroppedClass),
          ('Geometry rule', m.cropRuleDesc),
        ],
        command: 'python training_lab/scripts/fetch_datasets.py --model ${m.id}',
        canvasType: _MicroCanvasType.yoloIngest,
      ),
      _StageSpec(
        index: 1,
        numLabel: '02',
        navLabel: '2. Contact Sheet Audit',
        title: 'Tiled contact sheet generation and human visual verification',
        scriptPath: 'training_lab/data.py sheet',
        summary:
            'Dataset titles can be misleading: a public set named "ph_plates" proved to be Vietnamese, and another contained watermarked stock photos. Before trusting or merging a source into ${m.id}, data.py sheet renders a seeded contact grid with drawn bounding boxes so annotation rules are verified by eye.',
        specs: [
          ('Staged input', 'datasets/_downloads/<source_id>'),
          ('Rendered sheet', 'datasets/_sheets/${m.id}_all.png'),
          ('Trust tiers', 'Tier A (DOI / peer-reviewed), Tier B (named open source), Tier C (excluded)'),
          ('Model audit rule', m.id == 'helmet_specialist'
              ? 'Whole rider must be boxed (top 20% head check); head-only boxes rejected'
              : m.id == 'plate_specialist'
                  ? 'Boxes must tightly hug plate borders so EasyOCR receives clean crops'
                  : m.id == 'cabin_specialist'
                      ? 'tinted_window vs clear_window verified on windshield enforcement views'
                      : 'Full-frame vehicle boxes verified across day, night, and highway cameras'),
        ],
        command: 'python training_lab/data.py sheet --model ${m.id} --seed 0',
        canvasType: _MicroCanvasType.yoloSheet,
      ),
      _StageSpec(
        index: 2,
        numLabel: '03',
        navLabel: '3. Curate & dHash',
        title: 'Automated curation, 256-bit perceptual dHash deduplication, and quarantine',
        scriptPath: 'training_lab/data_tools/curate.py',
        summary:
            'Near-duplicate video frames shared between train and validation inflate test accuracy through memorization. curate.py computes a 256-bit perceptual difference hash (dHash) for every image in ${m.id}, groups them across 22 locality-sensitive bands of 12 bits, and quarantines any train twin within 16 Hamming bits of val/test.',
        specs: [
          ('Canonical layout', 'datasets/${m.id}/images/{train,val,test} + labels/{train,val,test}'),
          ('Quarantine path', 'datasets/_quarantine/${m.id}/<reason>/ (never deletes files)'),
          ('Image checks', '< 32px side or corrupt → quarantined; > 1280px or EXIF-rotated → upright RGB JPEG'),
          ('Perceptual dHash', '256-bit hash, 22 LSH bands × 12 bits, twin threshold <= 16 Hamming bits'),
          ('Protection rule', 'Forensic captures prefixed with harvest__* are never moved or re-encoded'),
        ],
        command: 'python training_lab/data.py curate --model ${m.id} --apply',
        canvasType: _MicroCanvasType.yoloCurate,
      ),
      _StageSpec(
        index: 3,
        numLabel: '04',
        navLabel: '4. Split & SR Gate',
        title: 'Deterministic dataset partitioning and Laplacian sharpness filtering',
        scriptPath: 'training_lab/scripts/split_dataset.py + data_tools/sr.py',
        summary:
            'Raw annotations in datasets/${m.id}/raw/ are deterministically shuffled (seed=42) into 80% train and 20% validation sets. When curating plate_specialist, data.py sr-build also runs a Laplacian variance sharpness gate to extract crystal-clear plates for the super-resolution enhancer.',
        specs: [
          ('Split ratio', '80% train / 20% val deterministic shuffle (random.seed(42))'),
          ('Already-split sets', 'Preserves existing train/val/test splits from fetch_datasets.py'),
          ('Laplacian SR gate', 'Var(∇²I) >= 40.0 at normalized 128px width (feeds datasets/sr_plates/clean)'),
          ('Crop geometry gate', 'Minimum 128×32px, aspect ratio 1.6 <= w/h <= 6.5, gray_hash Hamming > 8'),
        ],
        command: 'python training_lab/scripts/split_dataset.py --model ${m.id} --ratio 0.8',
        canvasType: _MicroCanvasType.yoloSplit,
      ),
      _StageSpec(
        index: 4,
        numLabel: '05',
        navLabel: '5. Augmentation Studio',
        title: 'Offline synthetic expansion and online 4-way Mosaic transformation',
        scriptPath: 'training_lab/scripts/augment.py + configs/training_config.yaml',
        summary:
            'Street cameras operate through monsoon downpours, night glare, motion blur, and tilted mounts. Small datasets for ${m.label} are expanded offline in augment.py with exact horizontal coordinate inversion (cx\' = 1.0 - cx), while Ultralytics applies online 4-tile Mosaic stitching and HSV color shifts at ${m.imgsz}×${m.imgsz}.',
        specs: [
          ('Input split', 'datasets/${m.id}/images/train + labels/train'),
          ('Output tensor', 'Augmented mini-batch [16, 3, ${m.imgsz}, ${m.imgsz}]'),
          ('Offline transforms', 'Brightness ×[0.4, 1.4], GaussianBlur k∈{3,5}, sensor noise [0,30], flip cx\' = 1 - cx'),
          ('Online transforms', 'mosaic: 1.0, hsv_h: 0.015, hsv_s: 0.70, hsv_v: 0.40, degrees: ±5°, scale: 0.50'),
        ],
        command: 'python training_lab/scripts/augment.py --model ${m.id} --count 500',
        canvasType: _MicroCanvasType.yoloAugment,
      ),
      _StageSpec(
        index: 5,
        numLabel: '06',
        navLabel: '6. Neural Forward Pass',
        title: 'Multi-scale feature pyramid extraction and decoupled detection heads',
        scriptPath: 'training_lab/scripts/train.py',
        summary:
            'Rather than running one massive detector across 4K video, Huli-Kamote cascades specialists. For ${m.label} (${m.imgsz}×${m.imgsz}), CSPDarknet C2f blocks extract spatial features, PANet fuses top-down semantics with bottom-up localization across P3/P4/P5, and an anchor-free decoupled head predicts boxes separately from [${m.classesSpec}].',
        specs: [
          ('Base weights', 'yolov8n.pt fine-tuned for ${m.epochs} epochs at imgsz=${m.imgsz}'),
          ('Input tensor', '[16, 3, ${m.imgsz}, ${m.imgsz}] (${m.inputSpec})'),
          ('Feature pyramid', 'P3 (small objects), P4 (medium objects), P5 (large objects)'),
          ('Decoupled head', 'Box branch: 4 × reg_max DFL bins | Class branch: ${m.classesSpec}'),
        ],
        command: 'python training_lab/scripts/train.py --model ${m.id} --epochs ${m.epochs} --imgsz ${m.imgsz}',
        canvasType: _MicroCanvasType.yoloArch,
      ),
      _StageSpec(
        index: 6,
        numLabel: '07',
        navLabel: '7. Loss & Convergence',
        title: 'Composite loss backpropagation, slope diagnostics, and detached execution',
        scriptPath: 'training_lab/scripts/run_state.py + lab_core.py',
        summary:
            'Every batch of ${m.label} minimizes a weighted sum of Complete-IoU box loss, Distribution Focal edge loss, and Binary Cross-Entropy class loss over ${m.epochs} epochs. Training runs in a detached OS process group so closing the dashboard never stops it; Pause/Resume restarts cleanly from weights/last.pt.',
        specs: [
          ('Composite loss', 'L_total = 7.5 · L_CIoU + 0.5 · L_BCE + 1.5 · L_DFL'),
          ('CIoU formulation', '1 - IoU + ρ²(b, b_gt) / c² + αv (center distance + aspect ratio penalty)'),
          ('Slope diagnostics', '6-epoch linear regression trend() detects plateau (< 0.002) or val divergence'),
          ('Detached state', 'runs/${m.id}/train/weights/last.pt saved every epoch (patience = 30)'),
        ],
        command: 'hulikamote_backend/venv/Scripts/python.exe training_lab/lab_tui.py',
        canvasType: _MicroCanvasType.yoloLoss,
      ),
      _StageSpec(
        index: 7,
        numLabel: '08',
        navLabel: '8. Validation Gate',
        title: 'Target mAP@0.50 benchmark gate and precision-recall diagnostics',
        scriptPath: 'training_lab/scripts/validate.py + data.py report',
        summary:
            'Checkpoints for ${m.label} must clear ${m.targetMetricLabel} on the held-out validation split before export. validate.py computes mAP@0.50 and mAP@0.50:0.95, while lab_core.py diagnoses precision-recall gaps (flagging missed hard examples vs. false alarms) and data.py report updates DATASET_CARD.md.',
        specs: [
          ('Model gate', '${m.id} requires mAP@0.50 >= ${m.targetMap.toStringAsFixed(2)}'),
          ('PR diagnostics', 'Flags (Recall < Precision - 0.15) as missed hard examples; inverse as false alarms'),
          ('Checkpoint tested', 'training_lab/runs/${m.id}/train/weights/best.pt'),
          ('Audit output', 'datasets/${m.id}/DATASET_CARD.md and datasets/CATALOG.md'),
        ],
        command: 'python training_lab/scripts/validate.py --model ${m.id}',
        canvasType: _MicroCanvasType.yoloVal,
      ),
      _StageSpec(
        index: 8,
        numLabel: '09',
        navLabel: '9. ONNX & Manifest Swap',
        title: 'Static ONNX graph simplification, atomic manifest swap, and release sync',
        scriptPath: 'training_lab/scripts/export_onnx.py + engine/model_hub.py',
        summary:
            'PyTorch checkpoints carry optimizer states and training hooks. export_onnx.py traces ${m.id}/weights/best.pt at fixed ${m.imgsz}×${m.imgsz} resolution, fuses Conv2d and BatchNorm layers (simplify=True), copies the dated binary into hulikamote_backend/models/${m.outputDir}/, and updates model_manifest.json atomically. Training no longer runs this step: it starts when you press Use this on the Models page.',
        specs: [
          ('Triggered by', '"Use this" on the Models page (engine/model_hub.py), never by training itself'),
          ('Source weights', 'training_lab/runs/${m.id}/<run>/weights/best.pt'),
          ('Deployed binary', 'hulikamote_backend/models/${m.outputDir}/${m.id}_<run>_<YYYYMMDD>.onnx'),
          ('Export flags', 'format="onnx", imgsz=${m.imgsz}, dynamic=False, simplify=True'),
          ('Manifest key', 'active_models["${m.id}"] updated in models/model_manifest.json'),
        ],
        command: 'python training_lab/scripts/export_onnx.py --model ${m.id}',
        canvasType: _MicroCanvasType.yoloExport,
      ),
    ];
  }

  List<_StageSpec> _buildOcrStages(_ModelSpec m) {
    return [
      _StageSpec(
        index: 0,
        numLabel: '01',
        navLabel: '1. Pop Quiz Harvest',
        title: 'Forensic Analyzer Pop Quiz harvesting of verified license plate crops',
        scriptPath: 'training_lab/scripts/train_ocr.py (load_pairs)',
        summary:
            'Unlike YOLO detectors that pull public datasets, the Plate OCR pipeline learns directly from human review in the Dashboard Inbox and Forensic Analyzer. Clicking True Positive, False Positive, or typing a corrected plate number saves the tight plate crop and its ground-truth text into datasets/plate_ocr/.',
        specs: [
          ('Image directory', 'training_lab/datasets/plate_ocr/images/train/*.jpg'),
          ('Label directory', 'training_lab/datasets/plate_ocr/labels/train/*.txt'),
          ('Label format', '"0 PLATE_TEXT" (class prefix 0 stripped by load_pairs())'),
          ('Minimum volume', '20+ plate crops required to unlock training (200+ recommended)'),
        ],
        command: 'python training_lab/scripts/train_ocr.py --engine easyocr --epochs 30 --batch 8',
        canvasType: _MicroCanvasType.ocrHarvest,
      ),
      _StageSpec(
        index: 1,
        numLabel: '02',
        navLabel: '2. Filter & Character Dict',
        title: 'Positive/negative pair separation and 36-character dictionary generation',
        scriptPath: 'training_lab/scripts/train_ocr.py (validate_dataset)',
        summary:
            'validate_dataset() scans all harvested pairs, separates positive labeled plates from empty false-positive background crops, and writes engine-specific ground-truth manifests: gt_label.txt for EasyOCR or rec_gt_train.txt + ph_plate_chars.txt (36 alphanumeric characters) for PaddleOCR.',
        specs: [
          ('Positive filter', 'Keeps pairs with non-empty text for recognition training'),
          ('Character set', '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ (36 characters, ignore_space=True)'),
          ('EasyOCR manifest', 'runs/easyocr_finetune/gt_label.txt (resolved_path\\tTEXT)'),
          ('PaddleOCR manifest', 'runs/paddleocr_finetune/rec_gt_train.txt + ph_plate_chars.txt'),
        ],
        command: 'python training_lab/scripts/train_ocr.py --engine paddleocr --epochs 30 --batch 8',
        canvasType: _MicroCanvasType.ocrDict,
      ),
      _StageSpec(
        index: 2,
        numLabel: '03',
        navLabel: '3. TPS Spatial Rectification',
        title: 'Thin-Plate Spline (TPS) perspective un-warping and strip normalization',
        scriptPath: 'training_lab/scripts/train_ocr.py (Transformation: TPS / RecResizeImg)',
        summary:
            'License plates captured from elevated CCTV angles are perspective-skewed and tilted. EasyOCR applies a Thin-Plate Spline (TPS) transformation with 20 fiducial control points to rectify the angled plate into a flat 32×100 grayscale strip, while PaddleOCR applies RecAug and resizes to 3×32×320.',
        specs: [
          ('EasyOCR input', '1-channel grayscale 32×100 strip, TPS with 20 fiducial points'),
          ('PaddleOCR input', '3-channel BGR 3×32×320 strip with RecAug distortion robustness'),
          ('Max text length', 'max_text_length: 10 characters'),
          ('Seed & workers', 'manualSeed: 1111, data_filtering_off: True'),
        ],
        command: '# Configured automatically in runs/easyocr_finetune/config.json',
        canvasType: _MicroCanvasType.ocrTps,
      ),
      _StageSpec(
        index: 3,
        numLabel: '04',
        navLabel: '4. Sequence Model & CTC Loss',
        title: 'CRNN / SVTR sequence modeling and Connectionist Temporal Classification (CTC)',
        scriptPath: 'training_lab/scripts/train_ocr.py (train_easyocr / train_paddleocr)',
        summary:
            'Instead of boxing individual letters, the OCR networkslices the rectified plate horizontally into vertical feature columns. EasyOCR runs ResNet → BiLSTM → CTC loss, while PaddleOCR runs MobileNetV1Enhance → MultiHead (SVTR transformer neck + 2D SAR attention head) with Cosine Adam warmup.',
        specs: [
          ('EasyOCR stack', 'Transformation: TPS → FeatureExtraction: ResNet (512c) → BiLSTM (256h) → CTC'),
          ('PaddleOCR stack', 'MobileNetV1Enhance (0.5x) → MultiHead: CTCHead (SVTR d=64) + SARHead (512d)'),
          ('Loss function', 'CTCLoss (aligns unsegmented character sequences) + SARLoss (Paddle MultiLoss)'),
          ('Optimizer', 'Adam (lr=1e-4 EasyOCR / lr=1e-3 Cosine with 5-epoch warmup PaddleOCR)'),
        ],
        command: 'python -m paddleocr.tools.train -c training_lab/runs/paddleocr_finetune/rec_ph_plate.yml',
        canvasType: _MicroCanvasType.ocrCtc,
      ),
      _StageSpec(
        index: 4,
        numLabel: '05',
        navLabel: '5. OCR Export & Hot-Swap',
        title: 'Inference graph conversion and backend model hot-swap',
        scriptPath: 'training_lab/scripts/export_ocr.py + routers/training.py',
        summary:
            'Once training finishes, export_ocr.py converts the checkpoint into a deployable artifact and copies it into hulikamote_backend/models/. EasyOCR deploys easyocr_custom_rec.pth directly, while PaddleOCR runs paddleocr.tools.export_model to freeze the static inference graph.',
        specs: [
          ('EasyOCR target', 'hulikamote_backend/models/easyocr_custom_rec.pth'),
          ('PaddleOCR target', 'hulikamote_backend/models/paddleocr_rec_inference/'),
          ('Export command', 'python -m paddleocr.tools.export_model -c rec_ph_plate.yml'),
          ('Studio pipeline', 'routers/training.py runs [1/2] train_ocr.py then [2/2] export_ocr.py'),
        ],
        command: 'python training_lab/scripts/export_ocr.py --engine easyocr --weights training_lab/runs/easyocr_finetune/best.pth',
        canvasType: _MicroCanvasType.ocrExport,
      ),
    ];
  }

  List<_StageSpec> _buildReidStages(_ModelSpec m) {
    return [
      _StageSpec(
        index: 0,
        numLabel: '01',
        navLabel: '1. Identity Tracklets',
        title: 'Forensic merge/separate harvesting and even time-spread sampling',
        scriptPath: 'training_lab/scripts/train_reid.py (collect_identities + spread)',
        summary:
            'The DeepSORT vehicle ReID model learns from human merge/separate decisions in the Forensic Analyzer and "Same car?" answers in the Harvest tab. Each physical vehicle gets a folder of time-ordered crops. spread() caps each vehicle at 40 evenly spaced frames so a car parked for 50 frames never drowns out a car seen for 8.',
        specs: [
          ('Dataset layout', 'datasets/reid/images/<task>/<identity>/*.jpg (time-ordered by filename)'),
          ('Identity gate', 'Only folders with >= 2 photos teach appearance continuity'),
          ('Volume thresholds', 'MIN_IDENTITIES = 5 to train | MIN_TO_VERIFY = 8 to deploy | 30+ recommended'),
          ('Frame balancing', 'spread(files, MAX_PHOTOS=40) samples evenly across the tracklet'),
        ],
        command: 'python training_lab/scripts/train_reid.py --epochs 12',
        canvasType: _MicroCanvasType.reidHarvest,
      ),
      _StageSpec(
        index: 1,
        numLabel: '02',
        navLabel: '2. Unseen-Car Split (75/25)',
        title: 'Whole-vehicle holdout partitioning and temporal query/gallery probing',
        scriptPath: 'training_lab/scripts/train_reid.py (split_cars + probe_items)',
        summary:
            'Testing on held-out frames of the same cars the model trained on is a false test—a model that merely memorizes license plates or stickers would pass. split_cars() holds out 25% of entire physical vehicles that are never seen during training. probe_items() uses each unseen car\'s earlier frames as queries and its later frames as gallery answers.',
        specs: [
          ('Holdout share', 'HOLDOUT_SHARE = 0.25 (25% of physical vehicles held out for testing)'),
          ('Temporal probe', 'First half of unseen car\'s frames → queries (up to 8); second half → gallery'),
          ('Leak prevention', 'Zero overlap between training vehicle identities and test vehicle identities'),
          ('Baseline check', 'Evaluates live ckpt.t7 on the unseen cars before training begins'),
        ],
        command: '# Executed automatically inside train_reid.py when cars >= MIN_TO_VERIFY (8)',
        canvasType: _MicroCanvasType.reidSplit,
      ),
      _StageSpec(
        index: 2,
        numLabel: '03',
        navLabel: '3. Metric CNN Fine-Tuning',
        title: 'DeepSORT 192×96 backbone transfer with dual learning rates and RandomErasing',
        scriptPath: 'training_lab/scripts/train_reid.py (make_net + fit)',
        summary:
            'make_net() loads the live DeepSORT checkpoint (engine/deep_sort/deep/model.py), keeps the pretrained convolutional body, and attaches a fresh classifier.4 layer sized to the training cars. Images are resized to 192×96, augmented with RandomErasing (simulating traffic occlusion), and optimized with differential learning rates.',
        specs: [
          ('Input transform', 'Resize(192, 96) → RandomHorizontalFlip → ColorJitter(0.3) → RandomErasing(p=0.3)'),
          ('Dual learning rate', 'Adam: LR_BODY = 1e-4 (pretrained backbone) | LR_HEAD = 1e-3 (fresh classifier.4)'),
          ('Loss function', 'nn.CrossEntropyLoss(label_smoothing=0.1) prevents overconfident logits'),
          ('Embedding mode', 'net.reid = True outputs L2-normalized 128-D appearance feature vectors'),
        ],
        command: 'python training_lab/scripts/train_reid.py --epochs 12 --batch 32',
        canvasType: _MicroCanvasType.reidTrain,
      ),
      _StageSpec(
        index: 3,
        numLabel: '04',
        navLabel: '4. Honest Verification Gate',
        title: 'Cosine similarity matrix evaluation and +2% Rank-1 deployment gate',
        scriptPath: 'training_lab/scripts/train_reid.py (scores + decide)',
        summary:
            'At the final epoch (no cherry-picking the best test epoch), scores() embeds all unseen queries and gallery photos, computes the cosine similarity matrix sims = qf @ gf.T, and measures Rank-1 accuracy and mAP. decide() blocks deployment unless Rank-1 beats the live model by >= +2 points AND mAP does not decrease.',
        specs: [
          ('Similarity matrix', 'sims = qf @ gf.T (cosine similarity between L2-normalized embeddings)'),
          ('Rank-1 metric', 'Fraction of queries whose top-1 closest gallery photo is the exact same car'),
          ('Hard gain gate', 'after_rank1 >= before_rank1 + 0.02 (MIN_GAIN = +2 percentage points)'),
          ('Order stability', 'after_map >= before_map (ensures non-top-1 gallery ranking did not degrade)'),
        ],
        command: 'python training_lab/scripts/reid_ab.py',
        canvasType: _MicroCanvasType.reidGate,
      ),
      _StageSpec(
        index: 4,
        numLabel: '05',
        navLabel: '5. Full Retrain & Head Graft',
        title: '100% vehicle retrain, original classifier graft, and backup rotation',
        scriptPath: 'training_lab/scripts/train_reid.py (--deploy)',
        summary:
            'Once the unseen-car check passes, train_reid.py trains a fresh model on 100% of collected cars for the same number of epochs. To ensure DeepSORT loads the new file with zero code changes, it grafts the fine-tuned convolutional body onto the original classifier.* tensors, backs up ckpt_original.t7, and replaces ckpt.t7.',
        specs: [
          ('Final training', 'Retrains on all 100% vehicle identities for full data utilization'),
          ('Shape compatibility', 'Keeps fine-tuned body + restores original classifier.* weights for DeepSORT'),
          ('Safety backups', 'Saves ckpt_original.t7 (first run) + timestamped ckpt_backup_<time>.t7'),
          ('Live target', 'hulikamote_backend/engine/deep_sort/deep/checkpoint/ckpt.t7 + metrics.json'),
        ],
        command: 'python training_lab/scripts/train_reid.py --epochs 12 --deploy',
        canvasType: _MicroCanvasType.reidDeploy,
      ),
    ];
  }

  List<_StageSpec> _buildSrStages(_ModelSpec m) {
    return [
      _StageSpec(
        index: 0,
        numLabel: '01',
        navLabel: '1. Sharpness & Aspect Gate',
        title: 'Laplacian variance sharpness filtering and gray_hash deduplication',
        scriptPath: 'training_lab/data_tools/sr.py (data.py sr-build)',
        summary:
            'To teach a super-resolution GAN how to reconstruct clear characters from blurry plates, its ground-truth targets must be genuinely sharp. sr.py cuts license plate boxes (+4% margin) from plate_specialist, scales them to a standard 128px width, and rejects any crop that fails size, aspect ratio, Laplacian sharpness, or perceptual hash deduplication.',
        specs: [
          ('Source dataset', 'training_lab/datasets/plate_specialist/images/{train,val,test}'),
          ('Dimension & aspect', 'min_w >= 128px, min_h >= 32px, plate aspect ratio 1.6 <= w/h <= 6.5'),
          ('Sharpness gate', 'Var(cv2.Laplacian(gray_128w, CV_64F)) >= 40.0 (sorted sharpest first)'),
          ('Deduplication', '16×16 gray_hash rejects near-repeats within Hamming distance <= 8'),
        ],
        command: 'python training_lab/data.py sr-build',
        canvasType: _MicroCanvasType.srGate,
      ),
      _StageSpec(
        index: 1,
        numLabel: '02',
        navLabel: '2. HR / LR Pair Synthesis',
        title: 'High-resolution Lanczos4 normalization and ×4 Bicubic downsampling',
        scriptPath: 'training_lab/scripts/train_realesrgan.py (build_image_pairs)',
        summary:
            'build_image_pairs() takes up to 2,000 sharp plate crops, rounds dimensions to multiples of scale=4 (width=128px), resizes the clean ground truth with Lanczos4 interpolation into datasets/sr_plates/hr/, and downsamples ×4 with Bicubic interpolation into datasets/sr_plates/lr/ (32px width).',
        specs: [
          ('High-res (HR) tile', 'datasets/sr_plates/hr/plate_*.png (width=128px, INTER_LANCZOS4)'),
          ('Low-res (LR) tile', 'datasets/sr_plates/lr/plate_*.png (width=32px, ×4 downsampled INTER_CUBIC)'),
          ('Scale factor', 'SCALE = 4 (reconstructs 4×4 pixels for every 1 input pixel)'),
          ('Minimum pool', 'Requires >= 50 valid HR/LR pairs to launch BasicSR training'),
        ],
        command: 'python training_lab/scripts/train_realesrgan.py --epochs 200',
        canvasType: _MicroCanvasType.srPairs,
      ),
      _StageSpec(
        index: 2,
        numLabel: '03',
        navLabel: '3. 6-Block RRDB Architecture',
        title: 'Lightweight Residual-in-Residual Dense Block (RRDBNet) and VGG Discriminator',
        scriptPath: 'training_lab/scripts/train_realesrgan.py (write_basicsr_config)',
        summary:
            'Standard ESRGAN uses 23 RRDB blocks, which is too heavy for real-time edge CCTV pipelines and 6GB GPUs. write_basicsr_config() generates a custom BasicSR YAML specifying a 6-block RRDBNet generator (32 features, 16 growth channels, ×4 upsampling) paired with a VGGStyleDiscriminator.',
        specs: [
          ('Generator (net_g)', 'RRDBNet: num_in_ch=3, num_out_ch=3, num_feat=32, num_block=6, num_grow_ch=16'),
          ('Discriminator (net_d)', 'VGGStyleDiscriminator: num_in_ch=3, num_feat=32 (adversarial realism)'),
          ('VRAM footprint', 'Tailored for 6GB VRAM (RTX 3050) with batch_size_per_gpu=8, gt_size=128'),
          ('Config path', 'training_lab/configs/realesrgan_train.yml'),
        ],
        command: 'python -m basicsr.train -opt training_lab/configs/realesrgan_train.yml',
        canvasType: _MicroCanvasType.srRrdb,
      ),
      _StageSpec(
        index: 3,
        numLabel: '04',
        navLabel: '4. Perceptual + GAN Loss',
        title: 'Composite Pixel L1, VGG-19 conv5_4 perceptual, and Vanilla GAN optimization',
        scriptPath: 'training_lab/configs/realesrgan_train.yml (train)',
        summary:
            'Training with pixel L1 loss alone produces blurry, over-smoothed characters. The ESRGAN trainer combines Pixel L1 loss (weight 0.01), VGG-19 conv5_4 Perceptual feature loss (weight 1.0 for crisp character strokes), and Vanilla GAN adversarial loss (weight 0.005), evaluating PSNR every 1,000 iterations.',
        specs: [
          ('Pixel loss', 'L1Loss (weight = 1e-2) maintains color and luminance fidelity'),
          ('Perceptual loss', 'VGG-19 conv5_4 feature L1 (weight = 1.0) recovers sharp alphanumeric edges'),
          ('Adversarial loss', 'Vanilla GANLoss (weight = 5e-3) against VGGStyleDiscriminator'),
          ('LR schedule', 'Adam (lr=1e-4, betas=[0.9, 0.99]) + MultiStepLR (γ=0.5 at 50% and 75% iters)'),
        ],
        command: '# Monitored via BasicSR logger every 100 iterations; checkpoints saved every 5,000 iters',
        canvasType: _MicroCanvasType.srLoss,
      ),
      _StageSpec(
        index: 4,
        numLabel: '05',
        navLabel: '5. EMA ONNX Deployment',
        title: 'Exponential Moving Average (params_ema) extraction and dynamic-axis ONNX export',
        scriptPath: 'training_lab/scripts/train_realesrgan.py (export_to_onnx)',
        summary:
            'export_to_onnx() locates the latest net_g_*.pth checkpoint, loads the smoothed Exponential Moving Average weights (params_ema) into RRDBNet, traces the graph with dynamic height and width axes (opset 11, dummy input 1×3×80×320), and writes hulikamote_backend/models/realesrgan.onnx.',
        specs: [
          ('Source weights', 'training_lab/runs/realesrgan/models/net_g_<latest>.pth (params_ema)'),
          ('Dynamic ONNX', 'opset_version=11, dynamic_axes on height (dim 2) and width (dim 3)'),
          ('Deployed binary', 'hulikamote_backend/models/realesrgan.onnx'),
          ('Skip-train flag', 'Use --export-only to re-export the latest checkpoint without retraining'),
        ],
        command: 'python training_lab/scripts/train_realesrgan.py --export-only',
        canvasType: _MicroCanvasType.srExport,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _continuousController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void dispose() {
    _continuousController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _selectModel(String id) {
    setState(() {
      _selectedModelId = id;
      _activeStage = 0;
      final count = _buildStages(_currentModel).length;
      _stageKeys = List.generate(count, (_) => GlobalKey());
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _selectStage(int index, {bool scrollIntoView = true}) {
    final stages = _buildStages(_currentModel);
    setState(() {
      _activeStage = index.clamp(0, stages.length - 1);
    });
    if (scrollIntoView && _activeStage < _stageKeys.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _stageKeys[_activeStage].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 420),
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
      _scheduleNextAutoStep();
    }
  }

  void _scheduleNextAutoStep() {
    if (!_isAutoPlaying || !mounted) return;
    final delayMs = (3800 / _playbackSpeed).round();
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!_isAutoPlaying || !mounted) return;
      final stages = _buildStages(_currentModel);
      final next = (_activeStage + 1) % stages.length;
      _selectStage(next, scrollIntoView: true);
      _scheduleNextAutoStep();
    });
  }

  String _firstSentence(String text) {
    final dot = text.indexOf('. ');
    if (dot != -1 && dot < 150) return text.substring(0, dot + 1);
    return text;
  }

  void _showMacroMapDialog({
    required _ModelSpec model,
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
            constraints: const BoxConstraints(maxWidth: 960, maxHeight: 620),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Training Lab Architecture — 4 Coded Pipelines, 7 Trainable Models',
                            style: GoogleFonts.lexend(
                              fontSize: 15,
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
                    _buildTrainingLabMacroMap(
                      model: model,
                      surface: surface,
                      surfaceSubtle: surfaceSubtle,
                      border: border,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      onSelectInDialog: (mId) {
                        Navigator.of(ctx).pop();
                        _selectModel(mId);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showStageDetailsDialog({
    required _StageSpec stage,
    required Color surface,
    required Color surfaceSubtle,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
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
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _kSignalBlue.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'STAGE ${stage.numLabel}',
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
                            stage.title,
                            style: GoogleFonts.lexend(
                              fontSize: 15,
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
                    const SizedBox(height: 10),
                    _buildStageProseAndSpecs(
                      stage: stage,
                      border: border,
                      surfaceSubtle: surfaceSubtle,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      textMuted: textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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
    final stages = _buildStages(model);
    if (_stageKeys.length != stages.length) {
      _stageKeys = List.generate(stages.length, (_) => GlobalKey());
    }
    final displayedStages = _singleStageFocusMode
        ? [stages[_activeStage.clamp(0, stages.length - 1)]]
        : stages;

    return Container(
      color: bgCanvas,
      child: Column(
        children: [
          // ═══════════════════════════════════════════════════════════════════
          // COMPACT STICKY INSTRUMENT HEADER (7 MODELS ACROSS 4 PIPELINES)
          // ═══════════════════════════════════════════════════════════════════
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: surface,
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Title, 7 Model Tabs (4 Pipelines), and Transport
                Row(
                  children: [
                    Text(
                      'Training Pipeline Visualizer',
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
                    InkWell(
                      onTap: () => setState(() => _singleStageFocusMode = !_singleStageFocusMode),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _singleStageFocusMode ? _kSignalBlue.withOpacity(0.14) : surfaceSubtle,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: _singleStageFocusMode ? _kSignalBlue : border),
                        ),
                        child: Text(
                          _singleStageFocusMode ? 'View: 1-by-1 Focus' : 'View: Scroll All',
                          style: GoogleFonts.lexend(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: _singleStageFocusMode ? textPrimary : textSecondary,
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
                            onTap: () => _selectStage((_activeStage - 1).clamp(0, stages.length - 1)),
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
                            onTap: () => _selectStage((_activeStage + 1).clamp(0, stages.length - 1)),
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

                // Second Row: Active Pipeline Track & Stage Buttons
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: stages.map((st) {
                          final isCurrent = _activeStage == st.index;
                          return InkWell(
                            onTap: () => _selectStage(st.index, scrollIntoView: true),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isCurrent ? _kSignalBlue.withOpacity(0.14) : surfaceSubtle,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isCurrent ? _kSignalBlue : border,
                                ),
                              ),
                              child: Text(
                                st.navLabel,
                                style: GoogleFonts.lexend(
                                  fontSize: 11,
                                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                                  color: isCurrent ? textPrimary : textSecondary,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        '${model.pipelineGroupLabel}  |  ${model.artifact}  |  ${model.targetMetricLabel}',
                        style: GoogleFonts.firaCode(
                          fontSize: 10.5,
                          color: textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Continuous Macro Signal Line
                SizedBox(
                  height: 6,
                  width: double.infinity,
                  child: AnimatedBuilder(
                    animation: _continuousController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _MacroSignalTrackPainter(
                          progress: _continuousController.value,
                          activeStage: _activeStage,
                          totalStages: stages.length,
                          isDark: isDark,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ═══════════════════════════════════════════════════════════════════
          // CALM, VISUAL-FIRST SCROLL BODY (DEEP SPECS IN ON-DEMAND DIALOGS)
          // ═══════════════════════════════════════════════════════════════════
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1060),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Slim Active Model Banner + On-Demand 4-Pipeline Architecture Dialog Button
                      _buildSlimModelBanner(
                        model: model,
                        surface: surface,
                        surfaceSubtle: surfaceSubtle,
                        border: border,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                      const SizedBox(height: 18),

                      ...displayedStages.map((stage) {
                        return Container(
                          key: _stageKeys[stage.index],
                          child: _buildStageLedgerSection(
                            context: context,
                            stage: stage,
                            model: model,
                            isLast: _singleStageFocusMode || stage.index == stages.length - 1,
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

  Widget _buildSlimModelBanner({
    required _ModelSpec model,
    required Color surface,
    required Color surfaceSubtle,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _kSignalBlue.withOpacity(0.14),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _kSignalBlue.withOpacity(0.5)),
            ),
            child: Text(
              model.id,
              style: GoogleFonts.firaCode(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: _kSignalBlue,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${model.architecture}  ·  ${model.classMapSummary}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.lexend(
                fontSize: 12,
                color: textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: () => _showMacroMapDialog(
              model: model,
              surface: surface,
              surfaceSubtle: surfaceSubtle,
              border: border,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _kSignalBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kSignalBlue),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_tree_outlined, size: 14, color: _kSignalBlue),
                  const SizedBox(width: 6),
                  Text(
                    '4-Pipeline Architecture Map',
                    style: GoogleFonts.lexend(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Macro Overview Map of the 4 Distinct Training Lab Pipelines (Inside Dialog) ──
  Widget _buildTrainingLabMacroMap({
    required _ModelSpec model,
    required Color surface,
    required Color surfaceSubtle,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    ValueChanged<String>? onSelectInDialog,
  }) {
    final families = [
      (
        kind: _PipelineKind.yolo,
        title: '1. YOLOv8 Detection Pipeline (9 stages)',
        scripts: 'fetch_datasets.py → data.py curate → split → augment → train.py → validate → export_onnx.py',
        models: ['primary_anchor', 'helmet_specialist', 'plate_specialist', 'cabin_specialist'],
      ),
      (
        kind: _PipelineKind.ocr,
        title: '2. Plate OCR Pipeline (5 stages)',
        scripts: 'Forensic Pop Quiz → train_ocr.py (TPS + ResNet/SVTR + BiLSTM + CTC) → export_ocr.py',
        models: ['plate_ocr'],
      ),
      (
        kind: _PipelineKind.reid,
        title: '3. Vehicle ReID Pipeline (5 stages)',
        scripts: 'Forensic Merge/Separate → 75/25 Unseen Car Split → train_reid.py (+2% Rank-1 Gate) → ckpt.t7',
        models: ['reid'],
      ),
      (
        kind: _PipelineKind.sr,
        title: '4. Plate Super-Resolution Pipeline (5 stages)',
        scripts: 'data.py sr-build (Laplacian >= 40) → train_realesrgan.py (6-RRDB ×4 GAN) → realesrgan.onnx',
        models: ['plate_enhancer'],
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Select any model below to switch pipelines:',
                  style: GoogleFonts.lexend(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              Text(
                'hulikamote_backend/routers/training.py + training_lab/',
                style: GoogleFonts.firaCode(fontSize: 10.5, color: textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: families.map((fam) {
              final isCurrentFamily = model.kind == fam.kind;
              return Container(
                width: 295,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isCurrentFamily ? _kSignalBlue.withOpacity(0.06) : surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isCurrentFamily ? _kSignalBlue : border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fam.title,
                      style: GoogleFonts.lexend(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isCurrentFamily ? _kSignalBlue : textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fam.scripts,
                      style: GoogleFonts.firaCode(
                        fontSize: 9.8,
                        height: 1.35,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: fam.models.map((mId) {
                        final mSpec = _models.firstWhere((x) => x.id == mId);
                        final isSel = _selectedModelId == mId;
                        return InkWell(
                          onTap: () => (onSelectInDialog ?? _selectModel)(mId),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSel ? _kSignalBlue : surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: isSel ? _kSignalBlue : border),
                            ),
                            child: Text(
                              mSpec.id,
                              style: GoogleFonts.firaCode(
                                fontSize: 9.5,
                                fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                                color: isSel ? Colors.white : textSecondary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStageLedgerSection({
    required BuildContext context,
    required _StageSpec stage,
    required _ModelSpec model,
    required bool isLast,
    required bool isDark,
    required Color surface,
    required Color surfaceSubtle,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
  }) {
    final isFocused = _activeStage == stage.index;

    return GestureDetector(
      onTap: () => _selectStage(stage.index, scrollIntoView: false),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          if (!isLast)
            Positioned(
              left: 6,
              top: 28,
              bottom: 0,
              width: 16,
              child: AnimatedBuilder(
                animation: _continuousController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _SpineSignalLinePainter(
                      progress: _continuousController.value,
                      isFocused: isFocused,
                      borderColor: border,
                    ),
                  );
                },
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isFocused ? _kSignalBlue : surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isFocused ? _kSignalBlue : border,
                    ),
                  ),
                  child: Text(
                    stage.numLabel,
                    style: GoogleFonts.firaCode(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isFocused ? Colors.white : textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isFocused ? _kSignalBlue.withOpacity(0.65) : border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              stage.title,
                              style: GoogleFonts.lexend(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.25,
                                color: textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          InkWell(
                            key: ValueKey('stage-details-${stage.index}'),
                            onTap: () => _showStageDetailsDialog(
                              stage: stage,
                              surface: surface,
                              surfaceSubtle: surfaceSubtle,
                              border: border,
                              textPrimary: textPrimary,
                              textSecondary: textSecondary,
                              textMuted: textMuted,
                            ),
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: surfaceSubtle,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.info_outline_rounded, size: 13, color: _kSignalBlue),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Details, Specs & CLI',
                                    style: GoogleFonts.lexend(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _firstSentence(stage.summary),
                        style: GoogleFonts.lexend(
                          fontSize: 12.5,
                          height: 1.45,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildStageMicroFigure(
                        stage: stage,
                        model: model,
                        border: border,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStageProseAndSpecs({
    required _StageSpec stage,
    required Color border,
    required Color surfaceSubtle,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          stage.title,
          style: GoogleFonts.lexend(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.25,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          stage.scriptPath,
          style: GoogleFonts.firaCode(
            fontSize: 11,
            color: _kSignalBlue,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          stage.summary,
          style: GoogleFonts.lexend(
            fontSize: 12.5,
            height: 1.52,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: border)),
          ),
          child: Column(
            children: stage.specs.map((row) {
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: border)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 128,
                      child: Text(
                        row.$1,
                        style: GoogleFonts.lexend(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.$2,
                        style: GoogleFonts.firaCode(
                          fontSize: 11,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: surfaceSubtle,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: border),
          ),
          child: SelectableText(
            '\$ ${stage.command}',
            style: GoogleFonts.firaCode(
              fontSize: 10.5,
              color: textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStageMicroFigure({
    required _StageSpec stage,
    required _ModelSpec model,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFigureToolbar(stage, model, border),
        const SizedBox(height: 8),
        Container(
          height: 242,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF080B10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: AnimatedBuilder(
              animation: _continuousController,
              builder: (context, _) {
                final t = (_continuousController.value * _playbackSpeed) % 1.0;
                return _buildMicroCanvasPainter(stage.canvasType, t, model);
              },
            ),
          ),
        ),
        if (stage.canvasType == _MicroCanvasType.yoloLoss) ...[
          const SizedBox(height: 8),
          _buildStage7EpochScrubber(textSecondary),
        ],
      ],
    );
  }

  Widget _buildFigureToolbar(_StageSpec stage, _ModelSpec model, Color border) {
    switch (stage.canvasType) {
      case _MicroCanvasType.yoloIngest:
        return Row(
          children: [
            Expanded(
              child: Text(
                'Sample Frame #1042, Highway Cam 04 (${model.label} crop & remap)',
                style: GoogleFonts.lexend(fontSize: 11.5, fontWeight: FontWeight.w500, color: const Color(0xFFCBD5E1)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '[class_id, cx, cy, w, h]',
              style: GoogleFonts.firaCode(fontSize: 10.5, color: const Color(0xFF94A3B8)),
            ),
          ],
        );
      case _MicroCanvasType.yoloCurate:
        return Row(
          children: [
            Expanded(
              child: Text(
                '256-bit dHash LSH comparison and split-leak quarantine (${model.id})',
                style: GoogleFonts.lexend(fontSize: 11.5, fontWeight: FontWeight.w500, color: const Color(0xFFCBD5E1)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            InkWell(
              onTap: () => setState(() => _quarantineProtected = !_quarantineProtected),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _quarantineProtected ? _kSemanticPass.withOpacity(0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _quarantineProtected ? _kSemanticPass : border),
                ),
                child: Text(
                  _quarantineProtected ? 'harvest__* lock: enabled' : 'harvest__* lock: disabled',
                  style: GoogleFonts.firaCode(
                    fontSize: 10,
                    color: _quarantineProtected ? _kSemanticPass : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ),
          ],
        );
      case _MicroCanvasType.yoloAugment:
        final modes = ['Mosaic (4-Way)', 'Flip (x\' = 1-x)', 'Rain & Low Light'];
        return Row(
          children: [
            Expanded(
              child: Text(
                'Select Augmentation Mode:',
                style: GoogleFonts.lexend(fontSize: 11.5, fontWeight: FontWeight.w500, color: const Color(0xFFCBD5E1)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...modes.asMap().entries.map((e) {
              final sel = _selectedAugMode == e.key;
              return Padding(
                padding: const EdgeInsets.only(left: 4),
                child: InkWell(
                  onTap: () => setState(() => _selectedAugMode = e.key),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: sel ? _kSignalBlue.withOpacity(0.16) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: sel ? _kSignalBlue : border),
                    ),
                    child: Text(
                      e.value,
                      style: GoogleFonts.lexend(
                        fontSize: 10,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                        color: sel ? Colors.white : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      case _MicroCanvasType.yoloArch:
        final scales = ['P3 (80×80)', 'P4 (40×40)', 'P5 (20×20)'];
        return Row(
          children: [
            Expanded(
              child: Text(
                'Netron-Style Multi-Scale Feature Pyramid (CSPDarknet Backbone)',
                style: GoogleFonts.lexend(fontSize: 11.5, fontWeight: FontWeight.w500, color: const Color(0xFFCBD5E1)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...scales.asMap().entries.map((e) {
              final sel = _selectedFpnScale == e.key;
              return Padding(
                padding: const EdgeInsets.only(left: 4),
                child: InkWell(
                  onTap: () => setState(() => _selectedFpnScale = e.key),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: sel ? _kSignalBlue.withOpacity(0.16) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: sel ? _kSignalBlue : border),
                    ),
                    child: Text(
                      e.value,
                      style: GoogleFonts.firaCode(
                        fontSize: 10,
                        color: sel ? Colors.white : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      case _MicroCanvasType.yoloLoss:
        return Row(
          children: [
            Expanded(
              child: Text(
                'Interactive CIoU Loss Alignment Simulator (${model.label})',
                style: GoogleFonts.lexend(fontSize: 11.5, fontWeight: FontWeight.w500, color: const Color(0xFFCBD5E1)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_manualEpochScrub >= 0)
              InkWell(
                onTap: () => setState(() => _manualEpochScrub = -1.0),
                child: Text(
                  'Reset to live loop',
                  style: GoogleFonts.firaCode(fontSize: 10, color: _kSignalBlue),
                ),
              ),
          ],
        );
      case _MicroCanvasType.yoloExport:
        return Row(
          children: [
            Expanded(
              child: Text(
                'Production Evaluation & Quantization Pipeline (Deployment Artifacts Lineage)',
                style: GoogleFonts.lexend(fontSize: 11.5, fontWeight: FontWeight.w500, color: const Color(0xFFCBD5E1)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              model.artifact,
              style: GoogleFonts.firaCode(fontSize: 10.5, color: const Color(0xFF94A3B8)),
            ),
          ],
        );
      case _MicroCanvasType.ocrCtc:
        final engines = ['EasyOCR (CRNN+CTC)', 'PaddleOCR (SVTR+SAR)'];
        return Row(
          children: [
            Expanded(
              child: Text(
                'Sequence recognition architecture:',
                style: GoogleFonts.lexend(fontSize: 11.5, fontWeight: FontWeight.w500, color: const Color(0xFFCBD5E1)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...engines.asMap().entries.map((e) {
              final sel = _selectedOcrEngine == e.key;
              return Padding(
                padding: const EdgeInsets.only(left: 4),
                child: InkWell(
                  onTap: () => setState(() => _selectedOcrEngine = e.key),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: sel ? _kSignalBlue.withOpacity(0.16) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: sel ? _kSignalBlue : border),
                    ),
                    child: Text(
                      e.value,
                      style: GoogleFonts.firaCode(
                        fontSize: 10,
                        color: sel ? Colors.white : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      default:
        return Row(
          children: [
            Expanded(
              child: Text(
                stage.title,
                style: GoogleFonts.lexend(fontSize: 11.5, fontWeight: FontWeight.w500, color: const Color(0xFFCBD5E1)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              model.id,
              style: GoogleFonts.firaCode(fontSize: 10.5, color: const Color(0xFF94A3B8)),
            ),
          ],
        );
    }
  }

  Widget _buildStage7EpochScrubber(Color textSecondary) {
    final effT = _manualEpochScrub >= 0 ? _manualEpochScrub : _continuousController.value;
    final iou = (0.18 + effT * 0.76).clamp(0.10, 0.96);
    final totalLoss = (1.85 * math.exp(-2.6 * effT) + 0.08).clamp(0.05, 2.0);

    return Row(
      children: [
        Text(
          'Scrub epoch:',
          style: GoogleFonts.firaCode(fontSize: 10.5, color: textSecondary),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: effT.clamp(0.0, 1.0),
              activeColor: _kSignalBlue,
              onChanged: (v) => setState(() => _manualEpochScrub = v),
            ),
          ),
        ),
        Flexible(
          child: Text(
            'IoU Overlap: ${(iou * 100).toStringAsFixed(1)}%  |  Total CIoU Loss: ${totalLoss.toStringAsFixed(3)}',
            style: GoogleFonts.firaCode(
              fontSize: 10.5,
              color: _kSemanticPass,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMicroCanvasPainter(_MicroCanvasType type, double t, _ModelSpec model) {
    switch (type) {
      case _MicroCanvasType.yoloIngest:
        return CustomPaint(painter: _Stage01IngestCropPainter(progress: t, model: model));
      case _MicroCanvasType.yoloSheet:
        return CustomPaint(painter: _Stage02ContactSheetPainter(progress: t, model: model));
      case _MicroCanvasType.yoloCurate:
        return CustomPaint(
          painter: _Stage03CurateDhashPainter(
            progress: t,
            shieldOn: _quarantineProtected,
            modelId: model.id,
          ),
        );
      case _MicroCanvasType.yoloSplit:
        return CustomPaint(painter: _Stage04SplitSharpnessPainter(progress: t, modelId: model.id));
      case _MicroCanvasType.yoloAugment:
        return CustomPaint(
          painter: _Stage05AugmentationPainter(
            progress: t,
            mode: _selectedAugMode,
            imgsz: model.imgsz,
          ),
        );
      case _MicroCanvasType.yoloArch:
        return CustomPaint(
          painter: _Stage06ArchitectureFpnPainter(
            progress: t,
            selectedScale: _selectedFpnScale,
            model: model,
          ),
        );
      case _MicroCanvasType.yoloLoss:
        final effT = _manualEpochScrub >= 0 ? _manualEpochScrub : t;
        return CustomPaint(
          painter: _Stage07LossConvergencePainter(
            progress: effT,
            maxEpochs: model.epochs,
          ),
        );
      case _MicroCanvasType.yoloVal:
        return CustomPaint(
          painter: _Stage08ValidationHoldoutPainter(
            progress: t,
            targetMap: model.targetMap,
            modelId: model.id,
          ),
        );
      case _MicroCanvasType.yoloExport:
        return CustomPaint(
          painter: _Stage09OnnxExportPainter(
            progress: t,
            artifact: model.artifact,
            imgsz: model.imgsz,
            outputDir: model.outputDir,
          ),
        );
      case _MicroCanvasType.ocrHarvest:
      case _MicroCanvasType.ocrDict:
      case _MicroCanvasType.ocrTps:
      case _MicroCanvasType.ocrCtc:
      case _MicroCanvasType.ocrExport:
        return CustomPaint(
          painter: _OcrPipelineMicroPainter(
            progress: t,
            type: type,
            engineIndex: _selectedOcrEngine,
          ),
        );
      case _MicroCanvasType.reidHarvest:
      case _MicroCanvasType.reidSplit:
      case _MicroCanvasType.reidTrain:
      case _MicroCanvasType.reidGate:
      case _MicroCanvasType.reidDeploy:
        return CustomPaint(
          painter: _ReidPipelineMicroPainter(
            progress: t,
            type: type,
          ),
        );
      case _MicroCanvasType.srGate:
      case _MicroCanvasType.srPairs:
      case _MicroCanvasType.srRrdb:
      case _MicroCanvasType.srLoss:
      case _MicroCanvasType.srExport:
        return CustomPaint(
          painter: _SrPipelineMicroPainter(
            progress: t,
            type: type,
          ),
        );
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TECHNICAL PAINTERS (ALL 4 PIPELINES & 7 MODELS)
// ═════════════════════════════════════════════════════════════════════════════

const Color _pBlue = Color(0xFF3B82F6);
const Color _pPass = Color(0xFF10B981);
const Color _pWarn = Color(0xFFF59E0B);
const Color _pDrop = Color(0xFFEF4444);
const Color _pSurface = Color(0xFF11161F);
const Color _pBorder = Color(0xFF1E2634);
const Color _pTextPrimary = Color(0xFFF1F5F9);
const Color _pTextMuted = Color(0xFF94A3B8);

class _MacroSignalTrackPainter extends CustomPainter {
  final double progress;
  final int activeStage;
  final int totalStages;
  final bool isDark;

  _MacroSignalTrackPainter({
    required this.progress,
    required this.activeStage,
    required this.totalStages,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final trackColor = isDark ? const Color(0xFF1E2634) : const Color(0xFFCBD5E1);
    canvas.drawLine(
      Offset(0, cy),
      Offset(size.width, cy),
      Paint()
        ..color = trackColor
        ..strokeWidth = 1.5,
    );

    final activeFraction = (activeStage + 1) / math.max(1, totalStages);
    canvas.drawLine(
      Offset(0, cy),
      Offset(size.width * activeFraction, cy),
      Paint()
        ..color = _pBlue.withOpacity(0.55)
        ..strokeWidth = 2.0,
    );

    for (int i = 0; i < 3; i++) {
      final px = ((progress + i / 3.0) % 1.0) * size.width;
      canvas.drawCircle(Offset(px, cy), 2.5, Paint()..color = _pBlue);
    }
  }

  @override
  bool shouldRepaint(covariant _MacroSignalTrackPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeStage != activeStage ||
      oldDelegate.totalStages != totalStages;
}

class _SpineSignalLinePainter extends CustomPainter {
  final double progress;
  final bool isFocused;
  final Color borderColor;

  _SpineSignalLinePainter({
    required this.progress,
    required this.isFocused,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height),
      Paint()
        ..color = isFocused ? _pBlue.withOpacity(0.45) : borderColor
        ..strokeWidth = 1.2,
    );

    final py = ((progress * 2.0) % 1.0) * size.height;
    canvas.drawCircle(
      Offset(cx, py),
      2.8,
      Paint()..color = isFocused ? _pBlue : _pTextMuted.withOpacity(0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _SpineSignalLinePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isFocused != isFocused;
}

// ── YOLO Stage 01: Model-Aware Polygon to Box & Crop Window ──────────────────
class _Stage01IngestCropPainter extends CustomPainter {
  final double progress;
  final _ModelSpec model;

  _Stage01IngestCropPainter({required this.progress, required this.model});

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    final leftW = size.width * 0.54;
    final frameRect = Rect.fromLTWH(12, 12, leftW - 20, size.height - 24);
    canvas.drawRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(6)), Paint()..color = _pSurface);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, const Radius.circular(6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = _pBorder,
    );

    final cx = frameRect.center.dx;
    final cy = frameRect.center.dy + 6;
    final targetRect = model.id == 'plate_specialist'
        ? Rect.fromCenter(center: Offset(cx, cy + 28), width: 88, height: 34)
        : model.id == 'cabin_specialist'
            ? Rect.fromCenter(center: Offset(cx, cy), width: 108, height: 76)
            : Rect.fromCenter(center: Offset(cx, cy), width: 68, height: 114);

    // Morph between source polygon and normalized bounding box
    final morph = (math.sin(progress * 2 * math.pi) * 0.5 + 0.5);
    final polyPoints = [
      Offset(targetRect.left - 8 * (1 - morph), targetRect.top + 10 * (1 - morph)),
      Offset(targetRect.center.dx, targetRect.top - 6 * (1 - morph)),
      Offset(targetRect.right + 10 * (1 - morph), targetRect.top + 14 * (1 - morph)),
      Offset(targetRect.right + 4 * (1 - morph), targetRect.bottom - 6 * (1 - morph)),
      Offset(targetRect.left - 6 * (1 - morph), targetRect.bottom),
    ];
    canvas.drawPath(
      Path()..addPolygon(polyPoints, true),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = _pWarn.withOpacity(1.0 - morph * 0.65),
    );

    canvas.drawRect(
      targetRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _pPass,
    );

    final marginRect = model.id == 'primary_anchor' ? frameRect.deflate(6) : targetRect.inflate(10);
    canvas.drawRect(
      marginRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = _pBlue.withOpacity(0.8),
    );
    _drawLabel(canvas, model.cropRuleDesc, Offset(frameRect.left + 8, frameRect.top + 8), _pBlue, 9.2, maxWidth: frameRect.width - 16);

    final scanY = frameRect.top + progress * frameRect.height;
    canvas.drawLine(
      Offset(frameRect.left, scanY),
      Offset(frameRect.right, scanY),
      Paint()
        ..color = _pBlue.withOpacity(0.65)
        ..strokeWidth = 1.2,
    );

    final rightX = leftW + 8;
    final rightW = size.width - rightX - 12;

    final cropCard = Rect.fromLTWH(rightX, 12, rightW, 98);
    canvas.drawRRect(RRect.fromRectAndRadius(cropCard, const Radius.circular(6)), Paint()..color = _pSurface);
    canvas.drawRRect(RRect.fromRectAndRadius(cropCard, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pBorder);
    _drawLabel(canvas, 'Target tensor (${model.imgsz}×${model.imgsz})', Offset(rightX + 10, 20), _pTextPrimary, 10.5, weight: FontWeight.w600, maxWidth: rightW - 20);
    _drawLabel(canvas, model.sampleBoxCoords, Offset(rightX + 10, 42), _pPass, 10.0, maxWidth: rightW - 20);
    _drawLabel(canvas, model.sampleSourceName, Offset(rightX + 10, 62), _pTextMuted, 9.5, maxWidth: rightW - 20);
    _drawLabel(canvas, 'datasets/${model.id}/data.yaml', Offset(rightX + 10, 82), _pBlue, 9.5, maxWidth: rightW - 20);

    final mapCard = Rect.fromLTWH(rightX, 120, rightW, size.height - 132);
    canvas.drawRRect(RRect.fromRectAndRadius(mapCard, const Radius.circular(6)), Paint()..color = _pSurface);
    canvas.drawRRect(RRect.fromRectAndRadius(mapCard, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pBorder);
    _drawLabel(canvas, 'Manifest class remapping (${model.id})', Offset(rightX + 10, 128), _pTextPrimary, 10.0, weight: FontWeight.w600, maxWidth: rightW - 20);
    _drawLabel(canvas, model.sampleMappedClass, Offset(rightX + 10, 150), _pPass, 9.2, maxWidth: rightW - 20);
    _drawLabel(canvas, model.classesSpec, Offset(rightX + 10, 170), _pWarn, 9.2, maxWidth: rightW - 20);
    _drawLabel(canvas, model.sampleDroppedClass, Offset(rightX + 10, 190), _pDrop, 9.2, maxWidth: rightW - 20);
  }

  @override
  bool shouldRepaint(covariant _Stage01IngestCropPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.model.id != model.id;
}

// ── YOLO Stage 02: Contact Sheet Audit ───────────────────────────────────────
class _Stage02ContactSheetPainter extends CustomPainter {
  final double progress;
  final _ModelSpec model;

  _Stage02ContactSheetPainter({required this.progress, required this.model});

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    const cols = 4;
    const rows = 2;
    const pad = 10.0;
    final cellW = (size.width - pad * (cols + 1)) / cols;
    final cellH = (size.height - pad * (rows + 1)) / rows;
    final activeIdx = ((progress * cols * rows).floor()) % (cols * rows);

    final samples = model.id == 'plate_specialist'
        ? [
            ('oi_plates_01', 'Tier A: tight plate', _pPass, true),
            ('roboflow_14', 'Tier B: rear plate', _pPass, true),
            ('ph_plates_08', 'Rejected: VN plate', _pDrop, false),
            ('harvest__042', 'Forensic verified', _pBlue, true),
            ('colorum_204', 'Loose bumper box', _pWarn, false),
            ('oi_plates_88', 'Tier A: front plate', _pPass, true),
            ('zen_plate_41', 'Tier A: angled crop', _pPass, true),
            ('harvest__105', 'Forensic night cam', _pBlue, true),
          ]
        : model.id == 'cabin_specialist'
            ? [
                ('menna_01', 'Tier B: seatbelt', _pPass, true),
                ('menna_14', 'Tier B: driver_phone', _pPass, true),
                ('stock_08', 'Rejected: watermark', _pDrop, false),
                ('harvest__019', 'Forensic side_mirror', _pBlue, true),
                ('tint_204', 'tinted_window gate', _pWarn, true),
                ('tpnew_88', 'Tier B: clear_window', _pPass, true),
                ('mirror_41', 'Tier B: moto mirror', _pPass, true),
                ('harvest__055', 'Forensic cabin crop', _pBlue, true),
              ]
            : [
                ('edgevision_01', 'Tier A: full target', _pPass, true),
                ('martinez_14', 'Tier B: Manila CCTV', _pPass, true),
                ('flashys_08', 'Tier C: watermark', _pDrop, false),
                ('harvest__092', 'Forensic verified', _pBlue, true),
                ('mapua_204', '15×26px tiny box', _pWarn, false),
                ('edgevision_88', 'Tier A: verified', _pPass, true),
                ('naratip_41', 'Tier B: valid crop', _pPass, true),
                ('harvest__105', 'Forensic night cam', _pBlue, true),
              ];

    for (int i = 0; i < samples.length; i++) {
      final r = i ~/ cols;
      final c = i % cols;
      final x = pad + c * (cellW + pad);
      final y = pad + r * (cellH + pad);
      final rect = Rect.fromLTWH(x, y, cellW, cellH);
      final item = samples[i];
      final isCurrent = i == activeIdx;

      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), Paint()..color = _pSurface);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isCurrent ? 1.6 : 1.0
          ..color = isCurrent ? _pBlue : _pBorder,
      );

      final boxRect = item.$4
          ? Rect.fromCenter(center: rect.center, width: cellW * 0.40, height: cellH * 0.50)
          : Rect.fromCenter(center: Offset(rect.center.dx, rect.top + 30), width: 16, height: 16);

      canvas.drawRect(
        boxRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = item.$3,
      );

      _drawLabel(canvas, item.$1, Offset(x + 6, y + 6), _pTextPrimary, 9.5, weight: FontWeight.w600, maxWidth: cellW - 12);
      _drawLabel(canvas, item.$2, Offset(x + 6, y + cellH - 18), item.$3, 9.0, maxWidth: cellW - 12);
    }
  }

  @override
  bool shouldRepaint(covariant _Stage02ContactSheetPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.model.id != model.id;
}

// ── YOLO Stage 03: 256-Bit dHash & Quarantine ────────────────────────────────
class _Stage03CurateDhashPainter extends CustomPainter {
  final double progress;
  final bool shieldOn;
  final String modelId;

  _Stage03CurateDhashPainter({
    required this.progress,
    required this.shieldOn,
    required this.modelId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    const gridN = 8;
    const cell = 13.0;
    const leftX = 16.0;
    const topY = 32.0;

    _drawLabel(canvas, 'val/sample_041.jpg (kept)', const Offset(leftX, 10), _pPass, 10.0, weight: FontWeight.w600);
    _drawLabel(canvas, 'train/sample_041_copy.jpg', const Offset(leftX + 132, 10), _pDrop, 10.0, weight: FontWeight.w600);

    for (int r = 0; r < gridN; r++) {
      for (int c = 0; c < gridN; c++) {
        final bitA = ((r * 7 + c * 13) % 3 == 0);
        final isDiff = (r == 2 && c == 5) || (r == 5 && c == 1) || (r == 6 && c == 6);
        final bitB = isDiff ? !bitA : bitA;

        canvas.drawRect(
          Rect.fromLTWH(leftX + c * cell, topY + r * cell, cell - 1.5, cell - 1.5),
          Paint()..color = bitA ? _pPass.withOpacity(0.85) : _pBorder,
        );
        canvas.drawRect(
          Rect.fromLTWH(leftX + 132 + c * cell, topY + r * cell, cell - 1.5, cell - 1.5),
          Paint()..color = isDiff ? _pDrop : (bitB ? _pBlue.withOpacity(0.85) : _pBorder),
        );
      }
    }

    _drawLabel(canvas, '22 LSH bands × 12 bits  |  Hamming distance = 3 <= 16', const Offset(leftX, 146), _pWarn, 9.5);
    _drawLabel(canvas, 'Split priority: test (0) > val (1) > train (2)', const Offset(leftX, 166), _pTextMuted, 9.5);

    final rightX = 270.0;
    final rightW = size.width - rightX - 14;
    if (rightW > 80) {
      final qRect = Rect.fromLTWH(rightX, 20, rightW, 92);
      canvas.drawRRect(RRect.fromRectAndRadius(qRect, const Radius.circular(6)), Paint()..color = _pSurface);
      canvas.drawRRect(RRect.fromRectAndRadius(qRect, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pBorder);
      _drawLabel(canvas, 'datasets/_quarantine/$modelId/', Offset(rightX + 10, 28), _pDrop, 10.0, weight: FontWeight.w600, maxWidth: rightW - 20);
      _drawLabel(canvas, 'split_leak/ (train twin moved)', Offset(rightX + 10, 48), _pTextMuted, 9.5, maxWidth: rightW - 20);
      _drawLabel(canvas, 'tiny_image/ (< 32px minimum side)', Offset(rightX + 10, 66), _pTextMuted, 9.5, maxWidth: rightW - 20);
      _drawLabel(canvas, 'no_boxes/ (out-of-frame clipped)', Offset(rightX + 10, 84), _pTextMuted, 9.5, maxWidth: rightW - 20);

      final sRect = Rect.fromLTWH(rightX, 124, rightW, 78);
      canvas.drawRRect(RRect.fromRectAndRadius(sRect, const Radius.circular(6)), Paint()..color = _pSurface);
      canvas.drawRRect(
        RRect.fromRectAndRadius(sRect, const Radius.circular(6)),
        Paint()..style = PaintingStyle.stroke..color = shieldOn ? _pPass.withOpacity(0.6) : _pBorder,
      );
      _drawLabel(
        canvas,
        shieldOn ? 'harvest__*.jpg protection active' : 'harvest__*.jpg protection paused',
        Offset(rightX + 10, 134),
        shieldOn ? _pPass : _pTextMuted,
        10.0,
        weight: FontWeight.w600,
        maxWidth: rightW - 20,
      );
      _drawLabel(
        canvas,
        'Reviewed CCTV captures are never deleted or re-encoded.',
        Offset(rightX + 10, 156),
        _pTextMuted,
        9.2,
        maxWidth: rightW - 20,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Stage03CurateDhashPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.shieldOn != shieldOn || oldDelegate.modelId != modelId;
}

// ── YOLO Stage 04: Deterministic Split & Laplacian SR Gate ───────────────────
class _Stage04SplitSharpnessPainter extends CustomPainter {
  final double progress;
  final String modelId;

  _Stage04SplitSharpnessPainter({required this.progress, required this.modelId});

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    final leftW = size.width * 0.46;
    _drawLabel(canvas, 'datasets/$modelId split (seed=42)', const Offset(14, 12), _pTextPrimary, 10.5, weight: FontWeight.w600);

    final splits = [
      ('Train split (80%)', 0.80, _pBlue, 42.0),
      ('Validation split (15%)', 0.15, _pPass, 102.0),
      ('Test holdout (5%)', 0.05, _pWarn, 162.0),
    ];

    for (final s in splits) {
      final y = s.$4;
      final barW = leftW - 28;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(14, y + 18, barW, 14), const Radius.circular(3)), Paint()..color = _pBorder);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(14, y + 18, barW * s.$2, 14), const Radius.circular(3)), Paint()..color = s.$3);
      _drawLabel(canvas, s.$1, Offset(14, y), _pTextMuted, 9.8);
    }

    final rx = leftW + 14;
    final rw = size.width - rx - 14;
    _drawLabel(canvas, 'sr.py Laplacian sharpness gate', Offset(rx, 12), _pTextPrimary, 10.5, weight: FontWeight.w600, maxWidth: rw);

    final sharpCard = Rect.fromLTWH(rx, 36, rw, 84);
    canvas.drawRRect(RRect.fromRectAndRadius(sharpCard, const Radius.circular(6)), Paint()..color = _pSurface);
    canvas.drawRRect(RRect.fromRectAndRadius(sharpCard, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pBorder);
    _drawLabel(canvas, 'ABC 1234', Offset(rx + 12, 46), _pTextPrimary, 14, weight: FontWeight.w700);
    _drawLabel(canvas, 'Var(∇²I) = 68.4 >= 40.0 (kept for HR)', Offset(rx + 12, 70), _pPass, 9.5, maxWidth: rw - 24);
    _drawLabel(canvas, '142×38px  |  aspect 3.7 in [1.6, 6.5]', Offset(rx + 12, 90), _pTextMuted, 9.2, maxWidth: rw - 24);

    final blurCard = Rect.fromLTWH(rx, 132, rw, 84);
    canvas.drawRRect(RRect.fromRectAndRadius(blurCard, const Radius.circular(6)), Paint()..color = _pSurface);
    canvas.drawRRect(RRect.fromRectAndRadius(blurCard, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pBorder);
    _drawLabel(canvas, 'A B C  1 2 3 4', Offset(rx + 12, 142), Colors.white24, 14, weight: FontWeight.w700);
    _drawLabel(canvas, 'Var(∇²I) = 18.2 < 40.0 (rejected)', Offset(rx + 12, 166), _pDrop, 9.5, maxWidth: rw - 24);
    _drawLabel(canvas, 'Excluded so blurry crops never become ground truth', Offset(rx + 12, 186), _pTextMuted, 9.2, maxWidth: rw - 24);
  }

  @override
  bool shouldRepaint(covariant _Stage04SplitSharpnessPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.modelId != modelId;
}

// ── YOLO Stage 05: Mosaic, Flip Coordinate Inversion & Rain/HSV ─────────────
class _Stage05AugmentationPainter extends CustomPainter {
  final double progress;
  final int mode;
  final int imgsz;

  _Stage05AugmentationPainter({
    required this.progress,
    required this.mode,
    required this.imgsz,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    final leftW = size.width * 0.52;
    final tileRect = Rect.fromLTWH(12, 12, leftW - 20, size.height - 24);

    if (mode == 0) {
      final splitX = tileRect.left + tileRect.width * (0.46 + 0.08 * math.sin(progress * 2 * math.pi));
      final splitY = tileRect.top + tileRect.height * (0.46 + 0.08 * math.cos(progress * 2 * math.pi));

      final quads = [
        (Rect.fromLTRB(tileRect.left, tileRect.top, splitX - 2, splitY - 2), 'Patch 1 (0.5x)'),
        (Rect.fromLTRB(splitX + 2, tileRect.top, tileRect.right, splitY - 2), 'Patch 2 (0.7x)'),
        (Rect.fromLTRB(tileRect.left, splitY + 2, splitX - 2, tileRect.bottom), 'Patch 3 (0.6x)'),
        (Rect.fromLTRB(splitX + 2, splitY + 2, tileRect.right, tileRect.bottom), 'Patch 4 (0.8x)'),
      ];
      for (final q in quads) {
        canvas.drawRRect(RRect.fromRectAndRadius(q.$1, const Radius.circular(5)), Paint()..color = _pSurface);
        canvas.drawRRect(RRect.fromRectAndRadius(q.$1, const Radius.circular(5)), Paint()..style = PaintingStyle.stroke..color = _pBlue.withOpacity(0.55));
        _drawLabel(canvas, q.$2, Offset(q.$1.left + 6, q.$1.top + 6), _pTextPrimary, 9.2);
      }
    } else if (mode == 1) {
      final isFlipped = progress >= 0.5;
      const rawX = 0.32;
      final dispX = isFlipped ? (1.0 - rawX) : rawX;
      canvas.drawRRect(RRect.fromRectAndRadius(tileRect, const Radius.circular(6)), Paint()..color = _pSurface);
      canvas.drawLine(Offset(tileRect.center.dx, tileRect.top + 8), Offset(tileRect.center.dx, tileRect.bottom - 8), Paint()..color = _pBorder);

      final boxCx = tileRect.left + dispX * tileRect.width;
      final boxRect = Rect.fromCenter(center: Offset(boxCx, tileRect.center.dy), width: 60, height: 92);
      canvas.drawRect(boxRect, Paint()..color = _pBlue.withOpacity(0.18));
      canvas.drawRect(boxRect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = _pBlue);
      _drawLabel(
        canvas,
        isFlipped ? 'Flipped: cx\' = 1.0 - 0.320 = 0.680' : 'Original: cx = 0.320',
        Offset(tileRect.left + 10, tileRect.bottom - 20),
        _pPass,
        9.8,
      );
    } else {
      final shift = (math.sin(progress * 2 * math.pi) * 0.5 + 0.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(tileRect, const Radius.circular(6)),
        Paint()..color = Color.lerp(const Color(0xFF0B111E), const Color(0xFF1A162B), shift)!,
      );
      final rainPaint = Paint()..color = _pBlue.withOpacity(0.4)..strokeWidth = 1.2;
      final rand = math.Random(99);
      for (int i = 0; i < 40; i++) {
        final rx = tileRect.left + rand.nextDouble() * tileRect.width;
        final ry = tileRect.top + ((rand.nextDouble() + progress) % 1.0) * tileRect.height;
        canvas.drawLine(Offset(rx, ry), Offset(rx - 4, ry + 13), rainPaint);
      }
    }

    final rx = leftW + 10;
    final rw = size.width - rx - 12;
    _drawLabel(canvas, 'Transform parameters', Offset(rx, 14), _pTextPrimary, 10.5, weight: FontWeight.w600, maxWidth: rw);
    _drawLabel(canvas, 'mosaic: 1.0 (4-patch grid)', Offset(rx, 38), _pTextMuted, 9.5, maxWidth: rw);
    _drawLabel(canvas, 'fliplr: 0.5 (cx\' = 1.0 - cx)', Offset(rx, 58), _pPass, 9.5, maxWidth: rw);
    _drawLabel(canvas, 'hsv_h: 0.015, hsv_s: 0.7, hsv_v: 0.4', Offset(rx, 78), _pTextMuted, 9.5, maxWidth: rw);
    _drawLabel(canvas, 'degrees: ±5.0°, translate: ±10%', Offset(rx, 98), _pTextMuted, 9.5, maxWidth: rw);
    _drawLabel(canvas, 'GaussianBlur k∈{3,5}, noise [0,30]', Offset(rx, 118), _pTextMuted, 9.5, maxWidth: rw);
    _drawLabel(canvas, 'Batch shape: [16, 3, $imgsz, $imgsz]', Offset(rx, 148), _pBlue, 9.8, weight: FontWeight.w600, maxWidth: rw);
  }

  @override
  bool shouldRepaint(covariant _Stage05AugmentationPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.mode != mode || oldDelegate.imgsz != imgsz;
}

// ── YOLO Stage 06: Multi-Scale Feature Pyramid & Decoupled Head ─────────────
class _Stage06ArchitectureFpnPainter extends CustomPainter {
  final double progress;
  final int selectedScale;
  final _ModelSpec model;

  _Stage06ArchitectureFpnPainter({
    required this.progress,
    required this.selectedScale,
    required this.model,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    final blocks = [
      ('Input', '${model.imgsz}×${model.imgsz}×3', 16.0),
      ('CSPDarknet Backbone', 'C2f stages', 128.0),
      ('PANet Neck', 'Bi-directional FPN', 256.0),
    ];

    for (int i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final rect = Rect.fromLTWH(b.$3, 56, 98, 106);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), Paint()..color = _pSurface);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pBorder);
      _drawLabel(canvas, b.$1, Offset(rect.left + 8, rect.top + 28), _pTextPrimary, 9.8, weight: FontWeight.w600, maxWidth: 82);
      _drawLabel(canvas, b.$2, Offset(rect.left + 8, rect.top + 50), _pTextMuted, 9.0, maxWidth: 82);

      if (i < blocks.length - 1) {
        final x1 = rect.right;
        final x2 = blocks[i + 1].$3;
        canvas.drawLine(Offset(x1, 109), Offset(x2, 109), Paint()..color = _pBorder..strokeWidth = 1.5);
        final px = x1 + (x2 - x1) * ((progress * 2 + i * 0.3) % 1.0);
        canvas.drawCircle(Offset(px, 109), 3.0, Paint()..color = _pBlue);
      }
    }

    final g3 = model.imgsz ~/ 8;
    final g4 = model.imgsz ~/ 16;
    final g5 = model.imgsz ~/ 32;
    final heads = [
      ('P3 head ($g3×$g3)', 'Fine grid for ${model.label}', 22.0),
      ('P4 head ($g4×$g4)', 'Medium receptive field', 92.0),
      ('P5 head ($g5×$g5)', 'Large receptive field', 162.0),
    ];

    const headX = 376.0;
    final headW = math.max(110.0, size.width - headX - 14);
    for (int i = 0; i < heads.length; i++) {
      final h = heads[i];
      final isSel = selectedScale == i;
      final rect = Rect.fromLTWH(headX, h.$3, headW, 54);

      canvas.drawLine(const Offset(354, 109), Offset(headX, rect.center.dy), Paint()..color = isSel ? _pBlue : _pBorder..strokeWidth = 1.3);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), Paint()..color = _pSurface);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..style = PaintingStyle.stroke..strokeWidth = isSel ? 1.5 : 1.0..color = isSel ? _pBlue : _pBorder,
      );
      _drawLabel(canvas, h.$1, Offset(rect.left + 10, rect.top + 8), isSel ? _pBlue : _pTextPrimary, 9.8, weight: FontWeight.w600, maxWidth: headW - 20);
      _drawLabel(canvas, '${h.$2} → [${model.classesSpec}]', Offset(rect.left + 10, rect.top + 28), _pTextMuted, 9.0, maxWidth: headW - 20);
    }
  }

  @override
  bool shouldRepaint(covariant _Stage06ArchitectureFpnPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.selectedScale != selectedScale || oldDelegate.model.id != model.id;
}

// ── YOLO Stage 07: CIoU Convergence & Loss Curve ─────────────────────────────
class _Stage07LossConvergencePainter extends CustomPainter {
  final double progress;
  final int maxEpochs;

  _Stage07LossConvergencePainter({
    required this.progress,
    required this.maxEpochs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    final leftW = size.width * 0.44;
    final gtRect = Rect.fromLTWH(32, 46, 90, 110);
    canvas.drawRect(gtRect, Paint()..color = _pPass.withOpacity(0.12));
    canvas.drawRect(gtRect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = _pPass);
    _drawLabel(canvas, 'Ground truth', Offset(gtRect.left, gtRect.top - 15), _pPass, 9.5);

    final dx = (1.0 - progress) * 56.0;
    final dy = (1.0 - progress) * 32.0;
    final predRect = gtRect.shift(Offset(dx, dy));
    canvas.drawRect(predRect, Paint()..color = _pBlue.withOpacity(0.12));
    canvas.drawRect(predRect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = _pBlue);

    canvas.drawLine(gtRect.center, predRect.center, Paint()..color = _pWarn..strokeWidth = 1.4);
    _drawLabel(
      canvas,
      'Epoch ${(progress * maxEpochs).round()} / $maxEpochs',
      const Offset(32, 184),
      _pTextPrimary,
      10.0,
      weight: FontWeight.w600,
    );

    final chartRect = Rect.fromLTWH(leftW + 10, 22, size.width - leftW - 22, size.height - 42);
    canvas.drawRRect(RRect.fromRectAndRadius(chartRect, const Radius.circular(6)), Paint()..color = _pSurface);
    canvas.drawRRect(RRect.fromRectAndRadius(chartRect, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pBorder);

    final trainPath = Path();
    final valPath = Path();
    const steps = 40;
    final activeSteps = math.max(2, (progress * steps).round());

    for (int i = 0; i <= activeSteps; i++) {
      final u = i / steps;
      final x = chartRect.left + 12 + u * (chartRect.width - 24);
      final ty = chartRect.top + 26 + (1.0 - math.exp(-3.0 * u)) * (chartRect.height - 46);
      final vy = chartRect.top + 32 + (1.0 - math.exp(-2.5 * u)) * (chartRect.height - 54);
      if (i == 0) {
        trainPath.moveTo(x, ty);
        valPath.moveTo(x, vy);
      } else {
        trainPath.lineTo(x, ty);
        valPath.lineTo(x, vy);
      }
    }

    canvas.drawPath(trainPath, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.8..color = _pBlue);
    canvas.drawPath(valPath, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.8..color = _pPass);

    _drawLabel(
      canvas,
      'train/box_loss (blue) vs val/box_loss (green)  |  last.pt saved',
      Offset(chartRect.left + 10, chartRect.top + 7),
      _pTextMuted,
      9.2,
      maxWidth: chartRect.width - 20,
    );
  }

  @override
  bool shouldRepaint(covariant _Stage07LossConvergencePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.maxEpochs != maxEpochs;
}

// ── YOLO Stage 08: Benchmark Gate ────────────────────────────────────────────
class _Stage08ValidationHoldoutPainter extends CustomPainter {
  final double progress;
  final double targetMap;
  final String modelId;

  _Stage08ValidationHoldoutPainter({
    required this.progress,
    required this.targetMap,
    required this.modelId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    final leftW = size.width * 0.48;
    _drawLabel(canvas, 'validate.py gate ($modelId)', const Offset(14, 12), _pTextPrimary, 10.5, weight: FontWeight.w600);

    final achieved = (targetMap + 0.04).clamp(0.0, 0.98);
    final barW = leftW - 28;

    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(14, 44, barW, 20), const Radius.circular(4)), Paint()..color = _pBorder);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(14, 44, barW * achieved, 20), const Radius.circular(4)), Paint()..color = _pPass);

    final gateX = 14 + barW * targetMap;
    canvas.drawLine(Offset(gateX, 36), Offset(gateX, 72), Paint()..color = _pWarn..strokeWidth = 2.0);
    _drawLabel(
      canvas,
      'mAP @ 0.50: ${(achieved * 100).toStringAsFixed(1)}% >= target ${(targetMap * 100).toStringAsFixed(0)}% (passed)',
      const Offset(14, 80),
      _pPass,
      9.8,
      weight: FontWeight.w600,
    );
    _drawLabel(canvas, 'Precision: 0.91  |  Recall: 0.88  |  |P - R| = 0.03 < 0.15', const Offset(14, 102), _pTextMuted, 9.2);
    _drawLabel(canvas, 'data.py report updates datasets/$modelId/DATASET_CARD.md', const Offset(14, 124), _pBlue, 9.2);

    final rx = leftW + 14;
    final rw = size.width - rx - 14;
    final card = Rect.fromLTWH(rx, 14, rw, size.height - 28);
    canvas.drawRRect(RRect.fromRectAndRadius(card, const Radius.circular(6)), Paint()..color = _pSurface);
    canvas.drawRRect(RRect.fromRectAndRadius(card, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pBorder);
    _drawLabel(canvas, 'lab_core.py automated verdict rules', Offset(rx + 10, 22), _pTextPrimary, 10.0, weight: FontWeight.w600, maxWidth: rw - 20);
    _drawLabel(canvas, '1. mAP@0.50 >= target → Ready for export_onnx.py', Offset(rx + 10, 48), _pPass, 9.2, maxWidth: rw - 20);
    _drawLabel(canvas, '2. |trend(mAP50, 6)| < 0.002 → Score flattened (early stop)', Offset(rx + 10, 70), _pTextMuted, 9.2, maxWidth: rw - 20);
    _drawLabel(canvas, '3. Recall < Precision - 0.15 → Add small/blurry examples', Offset(rx + 10, 92), _pWarn, 9.2, maxWidth: rw - 20);
    _drawLabel(canvas, '4. Precision < Recall - 0.15 → Add negative look-alikes', Offset(rx + 10, 114), _pWarn, 9.2, maxWidth: rw - 20);
  }

  @override
  bool shouldRepaint(covariant _Stage08ValidationHoldoutPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.targetMap != targetMap || oldDelegate.modelId != modelId;
}

// ── YOLO Stage 09: ONNX Simplification & Manifest Swap ──────────────────────
class _Stage09OnnxExportPainter extends CustomPainter {
  final double progress;
  final String artifact;
  final int imgsz;
  final String outputDir;

  _Stage09OnnxExportPainter({
    required this.progress,
    required this.artifact,
    required this.imgsz,
    required this.outputDir,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    final steps = [
      ('1. PyTorch checkpoint', 'runs/.../weights/best.pt', '14.2 MB (FP32 + optimizer)'),
      ('2. ONNX graph simplify', 'Conv2d + BatchNorm + SiLU fused (${imgsz}px)', '6.1 MB static shape'),
      ('3. Atomic manifest swap', 'models/$outputDir/$artifact', 'model_manifest.json updated'),
      ('4. Release registry', 'published_manifest.json', 'GitHub release tag synced'),
    ];

    final cardH = (size.height - 24) / steps.length;
    final activeIdx = ((progress * steps.length).floor()) % steps.length;

    for (int i = 0; i < steps.length; i++) {
      final s = steps[i];
      final y = 8.0 + i * cardH;
      final rect = Rect.fromLTWH(14, y, size.width - 28, cardH - 6);
      final isCur = i == activeIdx;

      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), Paint()..color = _pSurface);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()..style = PaintingStyle.stroke..strokeWidth = isCur ? 1.5 : 1.0..color = isCur ? _pBlue : _pBorder,
      );

      _drawLabel(canvas, s.$1, Offset(24, y + 8), isCur ? _pBlue : _pTextPrimary, 10.0, weight: FontWeight.w600);
      _drawLabel(canvas, s.$2, Offset(24, y + 25), _pTextMuted, 9.5);
      _drawLabel(canvas, s.$3, Offset(size.width - 210, y + 16), _pPass, 9.5, maxWidth: 190);
    }
  }

  @override
  bool shouldRepaint(covariant _Stage09OnnxExportPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.artifact != artifact || oldDelegate.imgsz != imgsz;
}

// ── PIPELINE 2 PAINTER: PLATE OCR (TPS + CRNN/SVTR + CTC) ────────────────────
class _OcrPipelineMicroPainter extends CustomPainter {
  final double progress;
  final _MicroCanvasType type;
  final int engineIndex;

  _OcrPipelineMicroPainter({
    required this.progress,
    required this.type,
    required this.engineIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    if (type == _MicroCanvasType.ocrHarvest || type == _MicroCanvasType.ocrDict) {
      // Pop Quiz plate crop + gt_label.txt / 36-char dictionary
      final plateRect = Rect.fromLTWH(20, 32, 200, 64);
      canvas.drawRRect(RRect.fromRectAndRadius(plateRect, const Radius.circular(6)), Paint()..color = _pSurface);
      canvas.drawRRect(RRect.fromRectAndRadius(plateRect, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pPass);
      _drawLabel(canvas, 'N C R  4 8 2 1', const Offset(42, 50), _pTextPrimary, 16, weight: FontWeight.w700);
      _drawLabel(canvas, 'Raw label: "0 NCR4821" → stripped: "NCR4821"', const Offset(20, 110), _pPass, 9.8);
      _drawLabel(canvas, 'Empty label (false positive) → filtered out of recognition', const Offset(20, 132), _pDrop, 9.5);
      _drawLabel(canvas, 'Vocab (36): 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ', const Offset(20, 160), _pBlue, 9.5);
    } else if (type == _MicroCanvasType.ocrTps) {
      // Thin-Plate Spline 20-fiducial point rectification
      final leftBox = Rect.fromLTWH(24, 48, 190, 74);
      canvas.drawRRect(RRect.fromRectAndRadius(leftBox, const Radius.circular(6)), Paint()..color = _pSurface);
      // Draw 20 fiducial control dots along top and bottom curves
      for (int i = 0; i < 10; i++) {
        final fx = leftBox.left + 14 + i * 18.0;
        final fyTop = leftBox.top + 12 + math.sin(i * 0.5 + progress * 2 * math.pi) * 4;
        final fyBot = leftBox.bottom - 12 + math.sin(i * 0.5 + progress * 2 * math.pi) * 4;
        canvas.drawCircle(Offset(fx, fyTop), 2.5, Paint()..color = _pWarn);
        canvas.drawCircle(Offset(fx, fyBot), 2.5, Paint()..color = _pWarn);
      }
      _drawLabel(canvas, 'Tilted crop (20 TPS fiducial points)', const Offset(24, 24), _pWarn, 9.8);

      final rightBox = Rect.fromLTWH(250, 56, size.width - 270, 56);
      canvas.drawRRect(RRect.fromRectAndRadius(rightBox, const Radius.circular(6)), Paint()..color = _pSurface);
      canvas.drawRRect(RRect.fromRectAndRadius(rightBox, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pPass);
      _drawLabel(canvas, 'Rectified strip (32×100 / 3×32×320)', const Offset(250, 24), _pPass, 9.8);
      _drawLabel(canvas, 'N C R 4 8 2 1', Offset(rightBox.left + 20, rightBox.top + 16), _pTextPrimary, 15, weight: FontWeight.w700);
    } else {
      // Sequence CRNN / SVTR + CTC alignment columns
      final isEasy = engineIndex == 0;
      _drawLabel(
        canvas,
        isEasy
            ? 'EasyOCR: TPS → ResNet (512c) → BiLSTM (256h) → CTC decode'
            : 'PaddleOCR: MobileNetV1Enhance → SVTR (CTCHead) + SARHead',
        const Offset(16, 14),
        _pBlue,
        10.2,
        weight: FontWeight.w600,
      );

      final tokens = ['N', '-', 'C', 'C', '-', 'R', '-', '4', '8', '2', '1'];
      final colW = (size.width - 32) / tokens.length;
      final activeCol = ((progress * tokens.length).floor()) % tokens.length;

      for (int i = 0; i < tokens.length; i++) {
        final x = 16 + i * colW;
        final r = Rect.fromLTWH(x + 2, 46, colW - 4, 96);
        final isCur = i == activeCol;
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = _pSurface);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()..style = PaintingStyle.stroke..color = isCur ? _pBlue : _pBorder,
        );
        _drawLabel(
          canvas,
          tokens[i],
          Offset(x + colW * 0.32, 84),
          tokens[i] == '-' ? _pTextMuted : _pPass,
          12,
          weight: FontWeight.w700,
        );
      }
      _drawLabel(
        canvas,
        'CTC Collapse (merge repeats, drop blank "-"):  "N-CC-R-4821" → "NCR4821"',
        const Offset(16, 162),
        _pPass,
        10.0,
        weight: FontWeight.w600,
      );
      _drawLabel(
        canvas,
        'Deployed to: hulikamote_backend/models/${isEasy ? "easyocr_custom_rec.pth" : "paddleocr_rec_inference/"}',
        const Offset(16, 186),
        _pTextMuted,
        9.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OcrPipelineMicroPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.type != type || oldDelegate.engineIndex != engineIndex;
}

// ── PIPELINE 3 PAINTER: VEHICLE REID (UNSEEN CAR HOLDOUT & COSINE MATRIX) ───
class _ReidPipelineMicroPainter extends CustomPainter {
  final double progress;
  final _MicroCanvasType type;

  _ReidPipelineMicroPainter({required this.progress, required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    final leftW = size.width * 0.48;
    _drawLabel(canvas, '75% train cars / 25% unseen holdout cars', const Offset(14, 12), _pTextPrimary, 10.2, weight: FontWeight.w600);

    // Draw 4x4 cosine similarity matrix (qf @ gf.T) on unseen cars
    const n = 4;
    const cell = 34.0;
    const startX = 18.0;
    const startY = 42.0;

    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        final isDiag = r == c;
        final rect = Rect.fromLTWH(startX + c * (cell + 4), startY + r * (cell + 4), cell, cell);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          Paint()..color = isDiag ? _pPass.withOpacity(0.28) : _pSurface,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          Paint()..style = PaintingStyle.stroke..color = isDiag ? _pPass : _pBorder,
        );
        final sim = isDiag ? (0.86 + 0.05 * math.sin(progress * 2 * math.pi)) : 0.21;
        _drawLabel(canvas, sim.toStringAsFixed(2), Offset(rect.left + 6, rect.top + 10), isDiag ? _pPass : _pTextMuted, 9.2);
      }
    }
    _drawLabel(canvas, 'sims = qf @ gf.T (128-D cosine)', const Offset(18, 198), _pBlue, 9.5);

    final rx = leftW + 10;
    final rw = size.width - rx - 14;
    final card = Rect.fromLTWH(rx, 14, rw, size.height - 28);
    canvas.drawRRect(RRect.fromRectAndRadius(card, const Radius.circular(6)), Paint()..color = _pSurface);
    canvas.drawRRect(RRect.fromRectAndRadius(card, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pBorder);

    _drawLabel(canvas, 'train_reid.py pipeline mechanics', Offset(rx + 10, 22), _pTextPrimary, 10.2, weight: FontWeight.w600, maxWidth: rw - 20);
    _drawLabel(canvas, '1. Input: 192×96 crop, spread(MAX_PHOTOS=40)', Offset(rx + 10, 48), _pTextMuted, 9.3, maxWidth: rw - 20);
    _drawLabel(canvas, '2. Dual Adam LR: body=1e-4, classifier.4=1e-3', Offset(rx + 10, 70), _pBlue, 9.3, maxWidth: rw - 20);
    _drawLabel(canvas, '3. Unseen gate: cars >= 8, Rank-1 gain >= +2%', Offset(rx + 10, 92), _pPass, 9.3, maxWidth: rw - 20);
    _drawLabel(canvas, '4. Final pass: retrains on 100% of cars', Offset(rx + 10, 114), _pPass, 9.3, maxWidth: rw - 20);
    _drawLabel(canvas, '5. Grafts original classifier.* → ckpt.t7', Offset(rx + 10, 136), _pWarn, 9.3, maxWidth: rw - 20);
  }

  @override
  bool shouldRepaint(covariant _ReidPipelineMicroPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.type != type;
}

// ── PIPELINE 4 PAINTER: REAL-ESRGAN SUPER-RESOLUTION (6-RRDB ×4) ─────────────
class _SrPipelineMicroPainter extends CustomPainter {
  final double progress;
  final _MicroCanvasType type;

  _SrPipelineMicroPainter({required this.progress, required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    // Show 32px LR input → 6-Block RRDBNet Generator → 128px HR output
    final lrBox = Rect.fromLTWH(16, 52, 92, 92);
    canvas.drawRRect(RRect.fromRectAndRadius(lrBox, const Radius.circular(6)), Paint()..color = _pSurface);
    canvas.drawRRect(RRect.fromRectAndRadius(lrBox, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pWarn);
    _drawLabel(canvas, 'LR (32px)', Offset(lrBox.left + 8, lrBox.top + 8), _pWarn, 9.5, weight: FontWeight.w600);
    _drawLabel(canvas, 'Bicubic ÷4', Offset(lrBox.left + 8, lrBox.top + 32), _pTextMuted, 9.0);
    _drawLabel(canvas, 'A B C 1 2 3', Offset(lrBox.left + 8, lrBox.top + 56), Colors.white24, 10.5, weight: FontWeight.w700);

    final rrdbBox = Rect.fromLTWH(132, 42, 136, 112);
    canvas.drawRRect(RRect.fromRectAndRadius(rrdbBox, const Radius.circular(6)), Paint()..color = _pSurface);
    canvas.drawRRect(RRect.fromRectAndRadius(rrdbBox, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pBlue);
    _drawLabel(canvas, 'RRDBNet (6 blocks)', Offset(rrdbBox.left + 10, rrdbBox.top + 12), _pBlue, 9.8, weight: FontWeight.w600);
    _drawLabel(canvas, 'num_feat=32, grow=16', Offset(rrdbBox.left + 10, rrdbBox.top + 34), _pTextMuted, 9.0);
    _drawLabel(canvas, 'L1 (1e-2) + VGG (1.0)', Offset(rrdbBox.left + 10, rrdbBox.top + 56), _pPass, 9.0);
    _drawLabel(canvas, '+ GANLoss (5e-3)', Offset(rrdbBox.left + 10, rrdbBox.top + 76), _pPass, 9.0);

    final hrX = 292.0;
    final hrW = math.max(110.0, size.width - hrX - 16);
    final hrBox = Rect.fromLTWH(hrX, 42, hrW, 112);
    canvas.drawRRect(RRect.fromRectAndRadius(hrBox, const Radius.circular(6)), Paint()..color = _pSurface);
    canvas.drawRRect(RRect.fromRectAndRadius(hrBox, const Radius.circular(6)), Paint()..style = PaintingStyle.stroke..color = _pPass);
    _drawLabel(canvas, 'HR ×4 Output (128px)', Offset(hrBox.left + 10, hrBox.top + 12), _pPass, 9.8, weight: FontWeight.w600, maxWidth: hrW - 20);
    _drawLabel(canvas, 'ABC 1234', Offset(hrBox.left + 10, hrBox.top + 38), _pTextPrimary, 15, weight: FontWeight.w700, maxWidth: hrW - 20);
    _drawLabel(canvas, 'params_ema → realesrgan.onnx', Offset(hrBox.left + 10, hrBox.top + 68), _pBlue, 9.2, maxWidth: hrW - 20);
    _drawLabel(canvas, 'Dynamic H×W axes (opset 11)', Offset(hrBox.left + 10, hrBox.top + 88), _pTextMuted, 9.0, maxWidth: hrW - 20);
  }

  @override
  bool shouldRepaint(covariant _SrPipelineMicroPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.type != type;
}

void _drawGrid(Canvas canvas, Size size) {
  final p = Paint()
    ..color = const Color(0x09FFFFFF)
    ..strokeWidth = 1.0;
  for (double x = 0; x < size.width; x += 24) {
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
  }
  for (double y = 0; y < size.height; y += 24) {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
  }
}

void _drawLabel(
  Canvas canvas,
  String text,
  Offset pos,
  Color color,
  double fontSize, {
  FontWeight weight = FontWeight.w500,
  double? maxWidth,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: GoogleFonts.lexend(
        fontSize: fontSize,
        fontWeight: weight,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth ?? double.infinity);
  tp.paint(canvas, pos);
}
