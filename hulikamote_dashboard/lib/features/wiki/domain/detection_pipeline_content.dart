/// Plain-language content for the Detection Pipeline page: the nine steps every
/// frame goes through, and the 14 "recipes" that judge the 25 violations.
///
/// Every number here is read from `hulikamote_backend/engine/`. The file that
/// owns each rule is named in `source`.
library;

/// What is drawn in a step (the view maps each one to a painter).
enum DetectionFigure {
  frames,
  detector,
  zoneFilter,
  tracker,
  ledger,
  stopped,
  wrongWay,
  wrongTurn,
  crossLine,
  vehicleType,
  weaving,
  signal,
  riders,
  onboard,
  helmet,
  seatbelt,
  phone,
  mirror,
  plate,
  holdConfirm,
  marginConfirm,
  voteConfirm,
  exitConfirm,
  evidence,
  ticket,
}

/// The three ways the engine can judge a vehicle (engine/violations/base.py).
enum JudgeFamily {
  zone('Zone rules', 'Read the diary',
      'Where did the vehicle go inside an area someone drew on the video?'),
  frame('Frame checks', 'Read the picture',
      'Who is on, or around, the vehicle in the picture right now?'),
  model('Specialist checks', 'Ask a specialist',
      'A small expert model takes a closer look at one vehicle.');

  final String title;
  final String verb;
  final String question;
  const JudgeFamily(this.title, this.verb, this.question);
}

/// How a rule avoids acting on one lucky or unlucky frame.
enum ConfirmKind { hold, margin, vote, atExit }

typedef Fact = (String label, String value);

class DetectionRecipe {
  final String id;
  final JudgeFamily family;
  final String name;

  /// Violation names exactly as the dashboard's violation catalog shows them.
  final List<String> covers;
  final String source;
  final String plain;
  final List<Fact> facts;
  final String? guards;
  final String? limits;
  final DetectionFigure figure;
  final ConfirmKind confirm;
  final String confirmNote;

  /// Vote rule (engine/ledger.py `vote`), only for [ConfirmKind.vote].
  final int voteMinLooks;
  final double voteShare;

  /// Shown on the confirm figure: how long it must hold, or how clear it must be.
  final String confirmLabel;

  const DetectionRecipe({
    required this.id,
    required this.family,
    required this.name,
    required this.covers,
    required this.source,
    required this.plain,
    required this.facts,
    required this.figure,
    required this.confirm,
    required this.confirmNote,
    required this.confirmLabel,
    this.guards,
    this.limits,
    this.voteMinLooks = 3,
    this.voteShare = 0.6,
  });
}

class PipelineStep {
  final int index;
  final String numLabel;
  final String navLabel;
  final String title;
  final String source;
  final String plain;
  final List<Fact> facts;
  final String? guards;
  final String? limits;
  final DetectionFigure figure;

  const PipelineStep({
    required this.index,
    required this.numLabel,
    required this.navLabel,
    required this.title,
    required this.source,
    required this.plain,
    required this.facts,
    required this.figure,
    this.guards,
    this.limits,
  });
}

/// The nine steps for one recipe: steps 6 and 7 follow the recipe, the rest are
/// the same for every violation.
List<PipelineStep> buildSteps(DetectionRecipe r) => [
      ..._shared.sublist(0, 5),
      PipelineStep(
        index: 5,
        numLabel: '06',
        navLabel: 'Judge',
        title: '${r.family.verb}: ${r.name}',
        source: r.source,
        plain: r.plain,
        facts: r.facts,
        guards: r.guards,
        limits: r.limits,
        figure: r.figure,
      ),
      _confirmStep(r),
      ..._shared.sublist(5),
    ];

PipelineStep _confirmStep(DetectionRecipe r) {
  final (title, plain, figure) = switch (r.confirm) {
    ConfirmKind.hold => (
        'Not on a single frame',
        'Bad frames happen: a box twitches, the detector blinks. These rules '
            'only fire when the thing stays true for a stretch of time. The moment '
            'it stops being true, the stopwatch goes back to zero.',
        DetectionFigure.holdConfirm,
      ),
    ConfirmKind.margin => (
        'Clearly, not barely',
        'This rule decides in one moment, but only when the evidence is clear. '
            'A vehicle wobbling right on the margin, or a heading that twitches '
            'for a frame, never counts.',
        DetectionFigure.marginConfirm,
      ),
    ConfirmKind.vote => (
        'Ask ten times, trust the majority',
        'One wrong look from a model must not create a ticket. The engine '
            'remembers the last 10 looks and flags only when enough of them were '
            'bad, and at least a minimum number of looks has been taken. '
            'Tap the looks below to try it.',
        DetectionFigure.voteConfirm,
      ),
    ConfirmKind.atExit => (
        'Wait until it leaves',
        'Until the vehicle leaves the picture (or the video ends) it is only '
            'marked as suspected. A plate found at any moment clears the '
            'suspicion and its evidence photos are deleted. Only a suspicion '
            'that held to the end becomes a ticket.',
        DetectionFigure.exitConfirm,
      ),
  };
  return PipelineStep(
    index: 6,
    numLabel: '07',
    navLabel: 'Confirm',
    title: title,
    source: r.source,
    plain: '$plain\n\n${r.confirmNote}',
    facts: const [],
    figure: figure,
  );
}

const List<PipelineStep> _shared = [
  PipelineStep(
    index: 0,
    numLabel: '01',
    navLabel: 'Frame',
    title: 'A frame arrives',
    source: 'routers/stream.py + engine/pipeline.py',
    plain:
        'The engine works on one picture at a time, like flipping through a '
        'flipbook. Tall frames are shrunk to 720 pixels high first so the '
        'computer keeps up. The heavy detector only runs on every third frame; '
        'on the others the last boxes are simply redrawn, which costs about '
        '3 ms instead of about 90 ms.',
    facts: [
      ('Size cap', 'frames taller than 720 px are scaled down (MAX_PROCESSING_HEIGHT)'),
      ('Detector runs', 'when frame_idx % 3 == 0 (INFER_EVERY_N_FRAMES = 2)'),
      ('In-between frames', 'last boxes and zones redrawn, about 2-3 ms vs about 90 ms'),
      ('Zones', 'polygons drawn at the video’s native size are rescaled to the processed frame'),
    ],
    figure: DetectionFigure.frames,
  ),
  PipelineStep(
    index: 1,
    numLabel: '02',
    navLabel: 'Detect',
    title: 'Spot every vehicle and person',
    source: 'yolo_inference.py',
    plain:
        'One fast detector looks at the whole picture once and draws a box '
        'around anything that looks like a car, motorcycle, bus, truck or '
        'person, each with a confidence score. Guesses below the cutoff are '
        'dropped. Motorcycles get a lower bar (0.25 instead of 0.45) because '
        'from a CCTV angle they are much harder to be sure of than their '
        'riders. Drag the cutoff to see what survives.',
    facts: [
      ('Model', 'primary_anchor: YOLOv8n ONNX by default (models/active_model.txt); YOLO11 or YOLO26 files can be swapped in'),
      ('Input', 'the whole frame letterboxed into 640 × 640 with grey (114) padding'),
      ('Cutoff', '0.45 for every class, 0.25 for motorcycle'),
      ('Duplicates', 'NMS at IoU 0.50, with people in their own group so a rider’s box cannot erase the motorcycle’s'),
      ('YOLO26', 'NMS-free by design, so that step is skipped'),
    ],
    figure: DetectionFigure.detector,
  ),
  PipelineStep(
    index: 2,
    numLabel: '03',
    navLabel: 'Zones',
    title: 'Ignore everything outside the zones',
    source: 'engine/pipeline.py (_filter_to_roi)',
    plain:
        'The operator draws areas on the video: a crosswalk, a lane, a '
        'junction. Any detection outside every active area is dropped before '
        'tracking, so the engine spends its effort where a rule can apply. '
        'If no area is drawn, everything stays.',
    facts: [
      ('How', 'sv.PolygonZone.trigger() tests each box against every active zone polygon'),
      ('No zones drawn', 'nothing is filtered'),
      ('Auto flow mode', 'ten rules (counterflow, swerving, illegal turn, illegal U-turn, signal light, truck ban, tricycle on highway, illegal loading, double parking, illegal parking) use the whole frame as their zone when none is drawn'),
      ('Rules by family', '17 zone rules · 3 frame checks · 5 specialist checks = 25 violations'),
    ],
    figure: DetectionFigure.zoneFilter,
  ),
  PipelineStep(
    index: 3,
    numLabel: '04',
    navLabel: 'Track',
    title: 'Give each one a name tag',
    source: 'engine/tracker.py + yolo_inference.py',
    plain:
        'Detections are anonymous boxes, and a rule needs to know it is the '
        'same vehicle from one frame to the next. The tracker matches each new '
        'box to an existing tag, mostly by how much the boxes overlap, and '
        'keeps a tag alive for a while when its vehicle is hidden behind '
        'something.',
    facts: [
      ('Default', 'ByteTrack: matches boxes by overlap (IoU), match threshold 0.2'),
      ('Patience', 'a lost tag is kept for 60 missed rounds'),
      ('Option', 'DeepSORT also compares a 128-number appearance fingerprint from the ReID model (ckpt.t7, the one training_lab fine-tunes); max distance 0.4; a new ID locks after 3 confirmed frames'),
      ('Output', 'every box gets a track_id; people and vehicles are tracked alike'),
    ],
    figure: DetectionFigure.tracker,
  ),
  PipelineStep(
    index: 4,
    numLabel: '05',
    navLabel: 'Diary',
    title: 'Keep a diary for every vehicle',
    source: 'engine/ledger.py + engine/track_stitcher.py',
    plain:
        'Each tag gets a ledger: its recent positions, how fast it moves, which '
        'way it heads, what kind of vehicle it is, and what it is suspected '
        'of. Positions are the ground point, bottom-centre of the box, so they '
        'line up with zones drawn on the road. If the tracker hands the same '
        'car a new tag, the engine glues the two diaries back together.',
    facts: [
      ('Position', 'ground point: bottom-centre of the box, (x + w/2, y + h)'),
      ('Memory', 'last 30 positions, plus a path of 300 points (about 10 s)'),
      ('Vehicle type', 'most common class across the whole track; needs 5 looks and over 50% agreement, otherwise unknown'),
      ('Stitching', 'a new tag joins a lost diary only if all six gates pass: lost ≤ 3 s · same class · appears where it should be · box area 0.4×-2.5× · not moving backwards · colour distance ≤ 0.5'),
      ('Leaves', 'after 60 missed rounds the ledger is closed and judged one last time'),
    ],
    figure: DetectionFigure.ledger,
  ),
  PipelineStep(
    index: 7,
    numLabel: '08',
    navLabel: 'Proof',
    title: 'Keep proof, hide bystanders',
    source: 'engine/pipeline.py (_capture_evidence_frame) + engine/privacy.py',
    plain:
        'Once a vehicle is flagged, or suspected, the engine saves photos. '
        'Before anything touches the disk, people’s heads and every other '
        'vehicle’s plate are blurred. The violator’s plate stays sharp because '
        'the ticket needs it. If the blur fails, nothing is saved.',
    facts: [
      ('When', 'the first frame is always saved, then every 5th (evidence_gap)'),
      ('Blurred', 'the head of every detected person (top 30% of the box) and the plate of every vehicle except the violator’s'),
      ('Saved', 'an annotated photo with zones and reason boxes, a clean vehicle crop, and a wider clean crop for the training harvest'),
      ('Cleared suspicion', 'photos are deleted if the vehicle ends with no violation'),
    ],
    limits:
        'A person the detector misses stays visible. Faces are not searched '
        'for separately: OpenCV’s face detector found no real face in nine hits '
        'on the project’s own evidence photos.',
    figure: DetectionFigure.evidence,
  ),
  PipelineStep(
    index: 8,
    numLabel: '09',
    navLabel: 'Ticket',
    title: 'Ticket and plate reading',
    source: 'engine/ledger.py + engine/pipeline.py (_extract_plate_text) + engine/ticket_merge.py',
    plain:
        'When the vehicle leaves, pending suspicions get their final decision. '
        'If any violation held, a ticket is queued with up to 40 plate crops. '
        'Each crop is sharpened, read by OCR, and tidied by position: a '
        'Philippine plate is 3 letters then 4 digits, so an ‘8’ in a letter '
        'slot becomes ‘B’. The crops then vote on the final plate, and a human '
        'reviews it in the dashboard.',
    facts: [
      ('Ticket', 'track id, merged ids, violations, up to 40 plate crops, evidence photos'),
      ('Sharpen', 'Lanczos ×4 (default) · LapSRN ×8 · Real-ESRGAN ×4 (the GAN trained in training_lab)'),
      ('OCR', 'EasyOCR (grayscale, 36-character allow-list) or PaddleOCR (colour)'),
      ('Fix by position', 'ph_standard: slots 1-3 letters, slots 4-7 digits (O↔0, B↔8, Z↔2 …)'),
      ('Vote', 'crops vote on the plate (ticket_merge.revote); reviewers can re-read, draw a box or type it'),
    ],
    figure: DetectionFigure.ticket,
  ),
];

/// The 14 recipes, grouped by family, in the order the picker shows them.
const List<DetectionRecipe> kRecipes = [
  // ── Zone rules ───────────────────────────────────────────────────────────
  DetectionRecipe(
    id: 'stopped',
    family: JudgeFamily.zone,
    name: 'Parked where it should not be',
    covers: [
      'Illegal parking',
      'Pedestrian lane blocked',
      'Blocking the intersection',
      'Illegal loading / unloading',
      'No stopping sign',
      'Double parking',
    ],
    source: 'violations/illegal_parking.py + stopped_in_zone.py + double_parking.py',
    plain:
        'A stopwatch starts when a vehicle is inside the drawn area and has '
        'stopped moving. If it is still there when the area’s time limit runs '
        'out, it is flagged. Driving through, or waiting just outside, never '
        'starts the watch.',
    facts: [
      ('Counts as stopped', 'slower than 25 px/s; box jitter on a parked car stays below this'),
      ('Needs', 'at least 5 position updates, so a brand-new track is not judged on nothing'),
      ('Time limits', 'crosswalk 3 s · junction box 5 s · no-loading bay 8 s · no-stopping sign 5 s · no-parking zone set per zone'),
      ('Loading bay', 'only buses, tricycles and trucks are judged there by default'),
      ('Double parking', 'also needs a second vehicle stopped beside it for longer, and a third still moving through the zone'),
    ],
    guards:
        'A car crawling through traffic. A queue at a red light (double parking '
        'needs moving traffic). A car left in a loading bay: that is illegal '
        'parking instead.',
    figure: DetectionFigure.stopped,
    confirm: ConfirmKind.hold,
    confirmLabel: 'Example limit: 8 s',
    confirmNote:
        'Here the watch must run the zone’s full limit. A crosswalk allows 3 s, '
        'a no-loading bay 8 s.',
  ),
  DetectionRecipe(
    id: 'wrong_way',
    family: JudgeFamily.zone,
    name: 'Driving against the flow',
    covers: ['Counterflow', 'No entry / one way sign'],
    source: 'violations/counterflow.py + engine/flow_field.py',
    plain:
        'Each zone has an arrow for the legal direction, or in auto mode the '
        'engine learns it from the traffic itself. If a vehicle is really '
        'driving and its heading points more than 135° away from that arrow, '
        'and it keeps doing so for 1.5 seconds in a row, it is flagged.',
    facts: [
      ('Against', 'heading more than 135° off the legal arrow'),
      ('Really driving', 'at least 50 px/s, or a quarter of its width per second if that is more, over the last second'),
      ('Held for', '1.5 s in a row; one bad frame resets the clock'),
      ('Auto mode', 'legal direction learned per cell of the picture; cells not learned yet, or two-way, are never judged'),
      ('No-entry sign', 'moving along the forbidden arrow, within 45°'),
    ],
    guards: 'Parked or crawling vehicles, sideways moves, turns, and a single noisy frame.',
    figure: DetectionFigure.wrongWay,
    confirm: ConfirmKind.hold,
    confirmLabel: 'Needs 1.5 s',
    confirmNote: 'Wrong-way heading must hold for 1.5 s.',
  ),
  DetectionRecipe(
    id: 'wrong_turn',
    family: JudgeFamily.zone,
    name: 'Turning where it may not',
    covers: ['Illegal turn', 'Illegal U-turn', 'No turn sign'],
    source: 'violations/illegal_turn.py + illegal_u_turn.py + geometry.py',
    plain:
        'The engine compares the direction a vehicle was heading when it '
        'entered the zone with its heading now. A turn is a swing of at least '
        '45°. If it now points along the forbidden arrow, and was not already '
        'pointing that way on entry, it is an illegal turn.',
    facts: [
      ('Turn', 'heading swings ≥ 45° and now points within 45° of the forbidden arrow'),
      ('Not a turn', 'it already pointed that way on entry (driving straight along the arrow)'),
      ('U-turn', 'swing ≥ 150° and moved sideways ≥ 0.75 box widths, so reversing in a straight line does not count'),
      ('Heading needs', 'half a box width (at least 15 px) of travel, so a stopped car’s jitter never counts'),
    ],
    guards: 'A stopped car’s jitter, driving straight along the arrow, reversing in a line.',
    figure: DetectionFigure.wrongTurn,
    confirm: ConfirmKind.margin,
    confirmLabel: 'Heading swing ≥ 45°',
    confirmNote: 'Each turn is judged once, at the moment the swing is clear.',
  ),
  DetectionRecipe(
    id: 'cross_line',
    family: JudgeFamily.zone,
    name: 'Crossing a line it must not cross',
    covers: ['Red light', 'Crossing a solid line', 'Stop sign'],
    source: 'violations/red_light.py + crossing_solid_line.py + engine/traffic_light.py',
    plain:
        'The engine watches the vehicle’s ground point against a line the '
        'operator drew. It counts as crossed only when the vehicle ends up '
        'clearly past it, coming from the side it was first seen on. For a red '
        'light, that crossing must also happen while the light is red.',
    facts: [
      ('Clearly past', '30% of the box width, at least 10 px'),
      ('Red light', 'flagged only if crossed while the light reads red; an unknown light never tickets'),
      ('Light from camera', 'bright, saturated pixels (S ≥ 90, V ≥ 150) inside a box drawn around the light; at least 3% lit and one colour owns 60%; a new colour must be read twice in a row'),
      ('Light from timer', 'a red → green → yellow cycle, for recorded footage'),
      ('Stop sign', 'crossed without first slowing under 25 px/s for 1 s'),
      ('Solid line', 'either direction counts'),
    ],
    guards:
        'A car that crossed on green and is still in the junction when the '
        'light turns red. A car wobbling on the line. Points beyond the line’s '
        'two ends.',
    figure: DetectionFigure.crossLine,
    confirm: ConfirmKind.margin,
    confirmLabel: 'Clearly past: 30% of width',
    confirmNote: 'Judged at the moment of crossing, never from a car that only touches the line.',
  ),
  DetectionRecipe(
    id: 'vehicle_type',
    family: JudgeFamily.zone,
    name: 'The wrong kind of vehicle here',
    covers: [
      'Restricted lane',
      'Truck ban / truck lane',
      'Tricycle on a national highway',
      'Driving on the sidewalk',
      'Vehicle type banned sign',
    ],
    source: 'violations/restricted_lane.py + banned_in_zone.py',
    plain:
        'The engine first settles what kind of vehicle it is, from the most '
        'common class across the whole track, so one flickering guess cannot '
        'decide. Then it checks the zone’s list: allowed types (a bus lane) or '
        'banned types (a truck ban, the sidewalk). A banned type must stay '
        'inside for a short while before it is flagged.',
    facts: [
      ('Vehicle type', 'most common class over the track; at least 5 looks and over 50% agreement, otherwise unknown and never judged'),
      ('Banned types stay', 'truck ban 1 s · tricycle on highway 1 s · sidewalk 1.5 s, and it must be moving'),
      ('Restricted lane', 'any type not on the allowed list; an empty list closes the lane to everyone'),
      ('Tricycle', 'needs the Philippine vehicle detector; the stock COCO model never outputs it'),
    ],
    guards: 'A vehicle only clipping a corner of the zone. A car left standing on the sidewalk: that is illegal parking.',
    figure: DetectionFigure.vehicleType,
    confirm: ConfirmKind.hold,
    confirmLabel: 'Needs 1 s inside',
    confirmNote: 'The banned type must stay inside for 1 to 1.5 s.',
  ),
  DetectionRecipe(
    id: 'weaving',
    family: JudgeFamily.zone,
    name: 'Weaving side to side',
    covers: ['Swerving'],
    source: 'violations/swerving.py',
    plain:
        'The engine takes the last 6 seconds of a vehicle’s path, smooths it, '
        'and measures how far each point sits left or right of a straight line '
        'from start to end. Every time it swings back by at least half a box '
        'width, that is a reversal. Two reversals, left-right-left, means '
        'weaving.',
    facts: [
      ('Window', 'last 6 s of path, smoothed with a 5-point average'),
      ('A swing counts', 'it moves back by at least 0.5 × the median box width'),
      ('Flag', '2 or more reversals'),
      ('Must travel', 'at least 2 box widths, so a near-stationary vehicle is not judged'),
      ('Fair near and far', 'thresholds scale with box width'),
    ],
    guards: 'Box jitter, and a single lane change (only one reversal).',
    figure: DetectionFigure.weaving,
    confirm: ConfirmKind.margin,
    confirmLabel: 'Swing ≥ ½ box width',
    confirmNote: 'It is judged from a whole 6-second stretch, never one frame.',
  ),
  DetectionRecipe(
    id: 'signal',
    family: JudgeFamily.zone,
    name: 'Turning without blinking',
    covers: ['No turn signal'],
    source: 'violations/signal_light.py + engine/traffic_light.py',
    plain:
        'When a vehicle turns inside the zone, the engine looks at the last 5 '
        'seconds. Every frame it measured how much bright amber showed on the '
        'vehicle’s left and right edge. A real indicator switches on and off in '
        'a steady rhythm; amber paint or a parking light stays on. No steady '
        'blinking on either side means no signal.',
    facts: [
      ('Turn', 'heading swings ≥ 45° inside the zone; each turn is judged once'),
      ('Where it looks', 'the outer 30% of the box on each side'),
      ('Amber pixel', 'hue 8-30, saturation ≥ 120, brightness ≥ 180'),
      ('Blinking', 'at least 2 switch-ons, 0.33-2.0 s apart, with at least 6 samples over 1 s or more'),
    ],
    limits:
        'Experimental. It can over-flag: hand signals are lawful (RA 4136 s44), '
        'motorcycles are exempt (s34(f)), and a distant or tinted indicator is '
        'hard to see. It is not a headline result.',
    figure: DetectionFigure.signal,
    confirm: ConfirmKind.margin,
    confirmLabel: 'Rhythm 0.5-3 Hz',
    confirmNote: 'It needs a steady on/off rhythm, not just some amber.',
  ),

  // ── Frame checks ─────────────────────────────────────────────────────────
  DetectionRecipe(
    id: 'riders',
    family: JudgeFamily.frame,
    name: 'Too many people on a motorcycle',
    covers: ['Overloading'],
    source: 'violations/overloading.py + geometry.py (rider_boxes)',
    plain:
        'For every motorcycle on screen the engine picks out the people '
        'sitting on it, then counts them. Someone counts as a rider if their '
        'feet fall within the motorcycle’s width around its lower body and at '
        'least 30% of them overlaps the bike. More than the allowed number '
        '(default 2) becomes a bad look.',
    facts: [
      ('Rider', 'feet inside the bike’s width, near its lower body, at least 30% of the person over the bike'),
      ('Allowed', 'max_riders, default 2: the driver and one passenger'),
      ('Runs', 'every detection round; no specialist model needed'),
    ],
    guards: 'A pedestrian walking past, and one wrong frame.',
    figure: DetectionFigure.riders,
    confirm: ConfirmKind.vote,
    confirmLabel: 'More than 2 riders',
    confirmNote: 'Overloading rule: bad in at least 60% of the last 10 looks, minimum 5 looks.',
    voteMinLooks: 5,
    voteShare: 0.6,
  ),
  DetectionRecipe(
    id: 'onboard',
    family: JudgeFamily.frame,
    name: 'Riding on a vehicle, not beside it',
    covers: ['Passengers in a pickup bed', 'Riding on the roof / hanging on'],
    source: 'violations/pickup_passengers.py + riding_outside.py + onboard.py',
    plain:
        'Two things must both be true: the person is in the right place on the '
        'vehicle (the open back of a truck, a roof, hanging off an edge) and '
        'the person moves with the vehicle. A pedestrian beside a moving '
        'truck, or someone loading a parked pickup, fails the second test.',
    facts: [
      ('Pickup bed', 'person in the trailing 40% of the vehicle along its travel direction, feet on the body, mostly over it'),
      ('Roof', 'feet in the top 30%, head at or above the roofline'),
      ('Hanging on', 'straddles the left or right edge: 25-75% over the body, feet in the lower 60%'),
      ('Moves with it', 'same direction and similar distance over the last 8 updates'),
      ('Allowed in the bed', 'bed_passengers_allowed, default 0'),
    ],
    guards: 'Pedestrians beside the vehicle, people boarding a stopped bus, and motorcycle riders (the motorcycle claims them first).',
    limits: 'Needs a front, rear or side view at moderate height. An overhead view cannot tell the cab from the bed, and someone on the rear step seen from straight behind is hidden.',
    figure: DetectionFigure.onboard,
    confirm: ConfirmKind.vote,
    confirmLabel: 'Someone on board',
    confirmNote: 'Bad in at least 60% of the last 10 looks, minimum 5 looks.',
    voteMinLooks: 5,
    voteShare: 0.6,
  ),

  // ── Specialist checks ────────────────────────────────────────────────────
  DetectionRecipe(
    id: 'helmet',
    family: JudgeFamily.model,
    name: 'Rider without a helmet',
    covers: ['No helmet'],
    source: 'violations/no_helmet.py + engine/specialist_jobs.py (HelmetJob)',
    plain:
        'The helmet specialist does not look at the head alone. The engine '
        'crops the motorcycle together with its riders, because the motorcycle '
        'box often cuts off the heads, and the model labels each whole rider '
        'as with or without a helmet. If any rider is bare, that look is bad. '
        'A look that finds no rider does not vote.',
    facts: [
      ('Crop', 'motorcycle box and riders merged into one box, letterboxed to 320 × 320'),
      ('Classes', '0 rider_with_helmet · 1 rider_without_helmet'),
      ('Sure enough', 'confidence ≥ 0.40 to decide (CHECK_CONF)'),
      ('Evidence marks', 'bare rider boxed red, helmeted rider green'),
    ],
    guards: 'A helmet carried on the lap does not fool it: the model judges the whole rider, not whether a helmet is in view.',
    figure: DetectionFigure.helmet,
    confirm: ConfirmKind.vote,
    confirmLabel: 'Any rider bare',
    confirmNote: 'No-helmet rule: bad in at least 60% of the last 10 looks, minimum 3 looks.',
    voteMinLooks: 3,
    voteShare: 0.6,
  ),
  DetectionRecipe(
    id: 'seatbelt',
    family: JudgeFamily.model,
    name: 'Driver without a seatbelt',
    covers: ['No seatbelt'],
    source: 'violations/no_seatbelt.py + cabin.py',
    plain:
        'The cabin specialist looks at the whole vehicle for a windshield. '
        'Before judging anything, a safety gate asks: can we actually see in? '
        'A tinted window, or no clear window at all, means no look is cast. '
        'With a clear window, no seatbelt seen is a bad look.',
    facts: [
      ('Safety gate', 'tinted window seen → skip · no clear window seen → skip'),
      ('Classes', 'clear_window · tinted_window · seatbelt · driver_phone · side_mirror'),
      ('Motorcycles', 'never judged for seatbelts'),
      ('Evidence marks', 'windshield boxed red unless a seatbelt is seen'),
    ],
    guards: 'Tinted windshields: the engine cannot see in, so it never tickets.',
    figure: DetectionFigure.seatbelt,
    confirm: ConfirmKind.vote,
    confirmLabel: 'No seatbelt seen',
    confirmNote: 'Seatbelt rule is stricter: bad in at least 80% of the looks, minimum 4 looks.',
    voteMinLooks: 4,
    voteShare: 0.8,
  ),
  DetectionRecipe(
    id: 'phone',
    family: JudgeFamily.model,
    name: 'Driver on a phone',
    covers: ['Phone use'],
    source: 'violations/distracted_driving.py + cabin.py',
    plain:
        'Same cabin specialist and same safety gate as the seatbelt check. '
        'When the window is clear, a driver_phone detection is a bad look and '
        'the phone is boxed red. This one is an extra: it is not on the '
        'thesis violation list.',
    facts: [
      ('Safety gate', 'tinted window seen → skip · no clear window seen → skip'),
      ('Bad look', 'a driver_phone box inside the vehicle'),
      ('Motorcycles', 'never judged'),
    ],
    guards: 'Tinted windshields, and any look where the cabin cannot be seen.',
    figure: DetectionFigure.phone,
    confirm: ConfirmKind.vote,
    confirmLabel: 'Phone seen',
    confirmNote: 'Bad in at least 60% of the last 10 looks, minimum 3 looks.',
    voteMinLooks: 3,
    voteShare: 0.6,
  ),
  DetectionRecipe(
    id: 'mirror',
    family: JudgeFamily.model,
    name: 'Motorcycle missing a mirror',
    covers: ['Missing side mirror'],
    source: 'violations/missing_side_mirror.py + geometry.py (front_or_rear_view)',
    plain:
        'The cabin specialist counts mirrors on a motorcycle, but only when '
        'the camera sees its front or rear (it moves mostly up or down the '
        'picture). From the side one mirror is always hidden, so those looks '
        'are skipped. Fewer than 2 mirrors is a bad look.',
    facts: [
      ('Counted when', 'front or rear view only'),
      ('Bad look', 'fewer than 2 mirrors'),
      ('Basis', 'LTO AO AHS-2008-015'),
    ],
    limits: 'The cabin model has no motorcycle-mirror training data yet, so this check cannot work until mirror photos are labelled.',
    figure: DetectionFigure.mirror,
    confirm: ConfirmKind.vote,
    confirmLabel: 'Fewer than 2 mirrors',
    confirmNote: 'Bad in at least 80% of the looks, minimum 5 looks.',
    voteMinLooks: 5,
    voteShare: 0.8,
  ),
  DetectionRecipe(
    id: 'plate',
    family: JudgeFamily.model,
    name: 'No licence plate at all',
    covers: ['No plate'],
    source: 'violations/no_plate.py + engine/specialist_jobs.py (PlateJob)',
    plain:
        'Every vehicle gets plate looks, whether or not no_plate is switched '
        'on, because every ticket should carry a plate number. A look counts '
        'only if it was fair: vehicle type settled, box at least 60 px wide, '
        'and a motorcycle showing its rear. After 6 fair looks with no plate '
        'ever found, the suspicion is pending. The decision waits until the '
        'vehicle leaves.',
    facts: [
      ('Search area', 'the whole vehicle: the model was trained on whole-vehicle crops'),
      ('Find confidence', '≥ 0.10 (SEARCH_CONF): finding a plate only needs a box'),
      ('Fair look', 'class settled · at least 60 px wide · a motorcycle must be moving up the picture (rear view)'),
      ('Pending after', '6 fair looks and zero plates found'),
    ],
    guards: 'Far-away vehicles, motorcycles seen from the front (Philippine motorcycles carry a rear plate only), and a single missed look.',
    figure: DetectionFigure.plate,
    confirm: ConfirmKind.atExit,
    confirmLabel: 'Decided when it leaves',
    confirmNote: 'The evidence photos of a cleared suspicion are deleted by the ledger.',
  ),
];

List<DetectionRecipe> recipesIn(JudgeFamily f) =>
    [for (final r in kRecipes) if (r.family == f) r];

DetectionRecipe recipeById(String id) =>
    kRecipes.firstWhere((r) => r.id == id);
