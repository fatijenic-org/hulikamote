import '../domain/reference_models.dart';

// Where the code lives (repository-relative). The code itself is read from these files when a slice opens.
const _viol = 'hulikamote_backend/engine/violations/';
const _eng = 'hulikamote_backend/engine/';
const _rout = 'hulikamote_backend/routers/';
const _lab = 'training_lab/';
const _dash = 'hulikamote_dashboard/lib/features/';

const _vio = ReferenceCategory.violations;
const _pip = ReferenceCategory.pipelines;
const _tra = ReferenceCategory.training;
const _fea = ReferenceCategory.features;

/// Everything the Code Reference says, in the order it is learned: small building blocks first, then what they
/// make when mixed, up to the whole picture. Keep each slice short: a question, one or two sentences, a recipe.
class ReferenceData {
  ReferenceData._();

  static List<Slice> inCategory(ReferenceCategory c) => [for (final s in all) if (s.category == c) s];

  static Slice? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  static const List<Slice> all = [
    // ═══ VIOLATIONS ═════════════════════════════════════════════════════════
    // ── Building blocks ──
    Slice(
      id: 'v_path', category: _vio, group: 'Building blocks',
      title: 'Every vehicle leaves a trail', short: 'its trail',
      says: 'The tracker gives each vehicle an ID. We keep its recent positions: the point where its tyres touch '
          'the road, and when. Every rule below is built from this trail.',
      code: [CodeAnchor('${_eng}ledger.py', 'def update_position(')],
    ),
    Slice(
      id: 'v_zone', category: _vio, group: 'Building blocks',
      title: 'Is it inside the zone?', short: 'inside a zone',
      says: 'The operator draws a shape on the picture. A rule only looks at a vehicle while its ground point is inside the shape.',
      code: [CodeAnchor('${_viol}geometry.py', 'def point_in_polygon(')],
    ),
    Slice(
      id: 'v_heading', category: _vio, group: 'Building blocks',
      title: 'Which way is it going?', short: 'its heading',
      says: 'Look back until the car has really moved (half its width, at least 15 px), then draw an arrow from there to here. '
          'A parked car only jitters, so it gets no arrow.',
      code: [CodeAnchor('${_viol}geometry.py', 'def heading(')],
    ),
    Slice(
      id: 'v_still', category: _vio, group: 'Building blocks',
      title: 'Has it stood still too long?', short: 'standing still',
      says: 'Slower than 25 px/s counts as stopped. Every rule keeps its own stopwatch, so one car can be timed by several rules at once.',
      code: [CodeAnchor('${_viol}geometry.py', 'def stopped_too_long(')],
    ),
    Slice(
      id: 'v_line', category: _vio, group: 'Building blocks',
      title: 'Did it cross the line?', short: 'crossing a line',
      says: 'Remember which side the car started on. It counts only when the car ends up clearly on the other side, '
          'so a car wobbling on the line does not.',
      code: [CodeAnchor('${_viol}geometry.py', 'def crossed_line(')],
    ),
    Slice(
      id: 'v_turn', category: _vio, group: 'Building blocks',
      title: 'Did it turn?', short: 'turning',
      says: 'Compare the heading when the car entered the zone with its heading now. A swing of 45 degrees or more, '
          'toward the banned direction, is a turn.',
      code: [CodeAnchor('${_viol}geometry.py', 'def turned_into(')],
    ),
    Slice(
      id: 'v_rider', category: _vio, group: 'Building blocks',
      title: 'Is this person riding it?', short: 'riding it',
      says: 'A rider has their feet on the vehicle. For trucks and buses the person must also move with it: '
          'a pedestrian walking past does neither.',
      code: [
        CodeAnchor('${_viol}geometry.py', 'def rider_boxes(', label: 'Feet on it'),
        CodeAnchor('${_viol}onboard.py', 'def moves_with(', label: 'Moves with it'),
      ],
    ),
    Slice(
      id: 'v_vote', category: _vio, group: 'Building blocks',
      title: 'Never trust one frame', short: 'most looks agree',
      says: 'One wrong frame must not ticket an innocent driver. These checks flag only when most of the last ten looks agree.',
      code: [CodeAnchor('${_eng}ledger.py', 'def vote(')],
    ),

    // ── Put two together ──
    Slice(
      id: 'r_parking', category: _vio, group: 'Put two together',
      title: 'Illegal parking', short: 'illegal parking', recipe: ['v_zone', 'v_still'],
      says: 'Still inside a no-parking zone for longer than its time limit.',
      code: [CodeAnchor('${_viol}illegal_parking.py', 'def evaluate(')],
    ),
    Slice(
      id: 'r_pedestrian', category: _vio, group: 'Put two together',
      title: 'Pedestrian lane blocked', short: 'pedestrian lane', recipe: ['v_zone', 'v_still'],
      says: 'The same recipe as parking, set to 3 seconds on a crosswalk. Only the zone and the limit change.',
      code: [CodeAnchor('${_viol}pedestrian_lane.py', 'class PedestrianLane')],
    ),
    Slice(
      id: 'r_blocking', category: _vio, group: 'Put two together',
      title: 'Blocking the intersection', short: 'blocking a junction', recipe: ['v_zone', 'v_still'],
      says: 'Once more the same recipe: standing still inside the junction box for longer than 5 seconds.',
      code: [CodeAnchor('${_viol}blocking_intersection.py', 'class BlockingIntersection')],
    ),
    Slice(
      id: 'r_counterflow', category: _vio, group: 'Put two together',
      title: 'Counterflow', short: 'counterflow', recipe: ['v_zone', 'v_heading'],
      says: 'Inside the zone, heading against the legal-flow arrow the operator drew.',
      code: [CodeAnchor('${_viol}counterflow.py', 'def evaluate(')],
    ),
    Slice(
      id: 'r_autoflow', category: _vio, group: 'Put two together',
      title: 'Counterflow with no drawing', short: 'automatic counterflow', recipe: ['v_heading', 'p_flow'],
      makes: 'Automatic counterflow',
      says: 'No arrow needed: the legal direction is learned from the traffic itself. Heading against it for 1.5 seconds in a row is wrong-way.',
      code: [CodeAnchor('${_viol}counterflow.py', 'def _evaluate_learned(')],
    ),
    Slice(
      id: 'r_turn', category: _vio, group: 'Put two together',
      title: 'Illegal turn', short: 'illegal turn', recipe: ['v_zone', 'v_turn'],
      says: 'Turning, inside the zone, toward the direction the operator marked as banned.',
      code: [CodeAnchor('${_viol}illegal_turn.py', 'def evaluate(')],
    ),
    Slice(
      id: 'r_uturn', category: _vio, group: 'Put two together',
      title: 'Illegal U-turn', short: 'illegal U-turn', recipe: ['v_zone', 'v_turn'],
      says: 'A turn of 150 degrees or more that also moved sideways. A car that only reverses in a straight line is not a U-turn.',
      code: [CodeAnchor('${_viol}illegal_u_turn.py', 'def evaluate(')],
    ),
    Slice(
      id: 'r_red', category: _vio, group: 'Put two together',
      title: 'Red light', short: 'red light', recipe: ['v_zone', 'v_line'],
      says: 'Crossing the stop line while the light is red. The light is read from the camera or simulated with a timer, '
          'and judged only at the moment of crossing.',
      code: [CodeAnchor('${_viol}red_light.py', 'def evaluate(')],
    ),
    Slice(
      id: 'r_solid', category: _vio, group: 'Put two together',
      title: 'Crossing a solid line', short: 'solid line', recipe: ['v_line'],
      says: 'Driving over a line that must not be crossed, in either direction.',
      code: [CodeAnchor('${_viol}crossing_solid_line.py', 'def evaluate(')],
    ),
    Slice(
      id: 'r_signs', category: _vio, group: 'Put two together',
      title: 'Disregarding signs', short: 'signs', recipe: ['v_heading', 'v_turn', 'v_still', 'v_line'],
      says: 'One zone per sign. No entry uses the heading, no turn uses the turn, no stopping uses the stopwatch, '
          'a stop sign uses the line.',
      code: [CodeAnchor('${_viol}disregarding_signs.py', 'def evaluate(')],
    ),
    Slice(
      id: 'r_swerving', category: _vio, group: 'Put two together',
      title: 'Swerving', short: 'swerving', recipe: ['v_path'],
      says: 'Over six seconds, measure how far the car drifts sideways from a straight line. '
          'Two swings of half a car width or more, left then right, is weaving.',
      code: [CodeAnchor('${_viol}swerving.py', 'def count_swings(')],
    ),
    Slice(
      id: 'r_signal', category: _vio, group: 'Put two together',
      title: 'No turn signal (experimental)', short: 'turn signal', recipe: ['v_turn'],
      says: 'A turn with no blinking amber light on either side in the five seconds before it. It can over-flag, '
          'so it is not a headline result.',
      code: [CodeAnchor('${_viol}signal_light.py', 'def evaluate(')],
    ),
    Slice(
      id: 'r_restricted', category: _vio, group: 'Put two together',
      title: 'Restricted lane', short: 'restricted lane', recipe: ['v_zone'],
      says: 'A vehicle type that is not allowed in the lane, judged by the class it has had for most of its track.',
      code: [CodeAnchor('${_viol}restricted_lane.py', 'def evaluate(')],
    ),
    Slice(
      id: 'r_loading', category: _vio, group: 'Put two together',
      title: 'Illegal loading / unloading', short: 'illegal loading', recipe: ['v_zone', 'v_still'],
      says: 'The parking recipe again, for the vehicles that load in the road (bus, jeepney, tricycle, truck): '
          'standing still inside the no-loading zone for longer than 8 seconds.',
      code: [CodeAnchor('${_viol}illegal_loading.py', 'class IllegalLoading')],
    ),
    Slice(
      id: 'r_truckban', category: _vio, group: 'Put two together',
      title: 'Truck ban / truck lane', short: 'truck ban', recipe: ['v_zone'],
      says: 'The mirror of the restricted lane: here the banned type (a truck) is listed, and it must stay inside the zone for a second.',
      code: [
        CodeAnchor('${_viol}truck_ban.py', 'class TruckBan', label: 'The rule'),
        CodeAnchor('${_viol}banned_in_zone.py', 'def evaluate(', label: 'Shared check'),
      ],
    ),
    Slice(
      id: 'r_tricycle', category: _vio, group: 'Put two together',
      title: 'Tricycle on a national highway', short: 'tricycle on highway', recipe: ['v_zone'],
      says: 'The same banned-type check, for tricycles inside the highway zone. It needs the vehicle model that knows "tricycle".',
      code: [CodeAnchor('${_viol}tricycle_on_highway.py', 'class TricycleOnHighway')],
    ),
    Slice(
      id: 'r_sidewalk', category: _vio, group: 'Put two together',
      title: 'Driving on the sidewalk', short: 'sidewalk', recipe: ['v_zone', 'v_path'],
      says: 'Any vehicle type, but it must be moving: 1.5 seconds inside the sidewalk zone. A parked car is parking, not driving.',
      code: [CodeAnchor('${_viol}sidewalk_driving.py', 'class SidewalkDriving')],
    ),
    Slice(
      id: 'r_double', category: _vio, group: 'Put two together',
      title: 'Double parking', short: 'double parking', recipe: ['v_zone', 'v_still', 'v_heading'],
      says: 'Stopped in the lane beside another stopped vehicle that got there first, while a third vehicle drives past. '
          'The passing traffic is what tells it from a queue at a red light.',
      code: [CodeAnchor('${_viol}double_parking.py', 'def evaluate(')],
    ),

    // ── People and models ──
    Slice(
      id: 'm_overloading', category: _vio, group: 'People and models',
      title: 'Overloading', short: 'overloading', recipe: ['v_rider', 'v_vote'],
      says: 'More riders on a motorcycle than allowed (two by default), in most of the last ten looks.',
      code: [CodeAnchor('${_viol}overloading.py', 'def check_frame(')],
    ),
    Slice(
      id: 'm_pickup', category: _vio, group: 'People and models',
      title: 'Passengers in a pickup bed', short: 'pickup passengers', recipe: ['v_rider', 'v_vote'],
      says: 'People on a moving truck, in its back part along the direction of travel, and moving with it. '
          'Cab occupants sit in the front part, so they do not count.',
      code: [
        CodeAnchor('${_viol}pickup_passengers.py', 'def check_frame(', label: 'The rule'),
        CodeAnchor('${_viol}onboard.py', 'def in_trailing_body(', label: 'Where the back is'),
      ],
    ),
    Slice(
      id: 'm_outside', category: _vio, group: 'People and models',
      title: 'Riding on the roof or hanging on', short: 'riding outside', recipe: ['v_rider', 'v_vote'],
      says: 'People standing on the roof, or hanging off the side, of a moving bus, jeepney or truck.',
      code: [
        CodeAnchor('${_viol}riding_outside.py', 'def check_frame(', label: 'The rule'),
        CodeAnchor('${_viol}onboard.py', 'def outside_position(', label: 'Roof or side'),
      ],
    ),
    Slice(
      id: 'm_helmet', category: _vio, group: 'People and models',
      title: 'No helmet', short: 'no helmet', recipe: ['p_looks', 'v_vote'],
      says: 'The helmet model looks at the motorcycle together with its riders. A rider without a helmet is a bad look; most looks must agree.',
      code: [CodeAnchor('${_viol}no_helmet.py', 'def judge(')],
    ),
    Slice(
      id: 'm_seatbelt', category: _vio, group: 'People and models',
      title: 'No seatbelt', short: 'no seatbelt', recipe: ['p_looks', 'v_vote'],
      says: 'The cabin model looks inside the car. A tinted window means no judgement at all; with a clear window, no seatbelt seen is a bad look.',
      code: [CodeAnchor('${_viol}no_seatbelt.py', 'def judge(')],
    ),
    Slice(
      id: 'm_phone', category: _vio, group: 'People and models',
      title: 'Phone use', short: 'phone use', recipe: ['p_looks', 'v_vote'],
      says: 'The same cabin look, asking this time for a phone in the driver\'s hand. It is an extra, not on the thesis list.',
      code: [CodeAnchor('${_viol}distracted_driving.py', 'def judge(')],
    ),
    Slice(
      id: 'm_mirror', category: _vio, group: 'People and models',
      title: 'Missing side mirror', short: 'side mirror', recipe: ['p_looks', 'v_vote'],
      says: 'Counts the mirrors on a motorcycle seen from the front or rear. It cannot work yet: the cabin model has no mirror training data.',
      code: [CodeAnchor('${_viol}missing_side_mirror.py', 'def judge(')],
    ),
    Slice(
      id: 'm_plate', category: _vio, group: 'People and models',
      title: 'No plate', short: 'no plate', recipe: ['p_looks'],
      says: 'Judged over the whole time the vehicle is on screen. A missing plate is only a suspicion until the vehicle leaves; '
          'a plate seen later clears it.',
      code: [
        CodeAnchor('${_viol}no_plate.py', 'def record_look(', label: 'Counting looks'),
        CodeAnchor('${_viol}no_plate.py', 'def decide_end(', label: 'Deciding at the end'),
      ],
    ),

    // ═══ PIPELINES ══════════════════════════════════════════════════════════
    // ── From camera to ID ──
    Slice(
      id: 'p_frame', category: _pip, group: 'From camera to ID',
      title: 'Get the newest frame', short: 'a frame',
      says: 'Recorded video is read in order. A live camera is read by a background thread that keeps only the newest frame, '
          'so delay cannot pile up.',
      code: [CodeAnchor('${_eng}camera_source.py', 'def read(self, timeout')],
    ),
    Slice(
      id: 'p_detect', category: _pip, group: 'From camera to ID',
      title: 'Find the vehicles', short: 'detections',
      says: 'One model finds cars, trucks, buses, motorcycles and people in the picture, and duplicate boxes are removed.',
      code: [CodeAnchor('hulikamote_backend/yolo_inference.py', 'def infer(self, frame')],
    ),
    Slice(
      id: 'p_input', category: _pip, group: 'From camera to ID',
      title: 'Feed the models like in training', short: 'RGB + letterbox',
      says: 'The picture is resized without stretching and turned from BGR to RGB. Fed the old way, the plate model found 7% of plates '
          'in test photos; fed this way it finds 83%.',
      code: [CodeAnchor('${_eng}specialists.py', 'def letterbox(')],
    ),
    Slice(
      id: 'p_track', category: _pip, group: 'From camera to ID',
      title: 'Give each vehicle an ID', short: 'an ID',
      says: 'Detections become tracks. The ledger keeps each vehicle\'s trail and class, and decides when a vehicle has left.',
      code: [CodeAnchor('${_eng}ledger.py', 'def update(self, detections')],
    ),
    Slice(
      id: 'p_stitch', category: _pip, group: 'From camera to ID',
      title: 'Glue broken IDs back together', short: 'stitched IDs',
      says: 'When a tracker loses a car and gives it a new ID, its colour signature and position show it is the same car, '
          'so it still gets one ticket.',
      code: [CodeAnchor('${_eng}track_stitcher.py', 'def match_births(')],
    ),

    // ── A closer look and the rules ──
    Slice(
      id: 'p_flow', category: _pip, group: 'A closer look and the rules',
      title: 'Learn which way traffic goes', short: 'learned flow',
      says: 'Each moving vehicle votes for its direction in a cell of a 16 by 9 grid. When one direction owns 70% of a cell\'s votes, '
          'going the other way is wrong.',
      code: [
        CodeAnchor('${_eng}flow_field.py', 'def verdict(', label: 'Judging'),
        CodeAnchor('${_eng}flow_field.py', 'def observe(', label: 'Voting'),
      ],
    ),
    Slice(
      id: 'p_looks', category: _pip, group: 'A closer look and the rules',
      title: 'Take a closer look', short: 'a closer look',
      says: 'Every few frames the helmet, plate and cabin models each look at a vehicle once, and the violations that depend on that look judge it.',
      code: [
        CodeAnchor('${_eng}pipeline.py', 'def _run_specialists(', label: 'Who looks when'),
        CodeAnchor('${_eng}specialist_jobs.py', 'class PlateJob', label: 'One look'),
      ],
    ),
    Slice(
      id: 'p_judge', category: _pip, group: 'A closer look and the rules',
      title: 'Judge the rules', short: 'the rules',
      says: 'Zone rules run on every tracked vehicle, then the checks that look at the whole picture, such as riders on a motorcycle.',
      code: [CodeAnchor('${_eng}pipeline.py', 'def _judge(')],
    ),
    Slice(
      id: 'p_proof', category: _pip, group: 'A closer look and the rules',
      title: 'Keep the proof', short: 'evidence photos',
      says: 'Once a vehicle is flagged, photos are saved as it goes, with boxes showing the reason drawn on them.',
      code: [CodeAnchor('${_eng}pipeline.py', 'def _capture_evidence_frame(')],
    ),
    Slice(
      id: 'p_ticket', category: _pip, group: 'A closer look and the rules',
      title: 'Decide when it leaves', short: 'a ticket',
      says: 'Suspicions that held to the end become violations. Photos taken for a cleared suspicion are deleted. What remains becomes a ticket.',
      code: [
        CodeAnchor('${_eng}ledger.py', 'def decide_end_of_track(', label: 'Deciding'),
        CodeAnchor('${_eng}ledger.py', 'def _finalize_ticket(', label: 'The ticket'),
      ],
    ),

    // ── The whole loop ──
    Slice(
      id: 'p_whole', category: _pip, group: 'The whole loop',
      title: 'One frame, start to finish', short: 'one frame',
      says: 'In order: detect, track, take a closer look, judge, keep the proof.',
      code: [CodeAnchor('${_eng}pipeline.py', 'def process_frame(')],
    ),
    Slice(
      id: 'p_live', category: _pip, group: 'The whole loop',
      title: 'Live: the camera sets the pace', short: 'live',
      says: 'The live monitor takes the newest frame, runs the same loop, and reports the camera\'s state: live, connecting or offline.',
      code: [CodeAnchor('${_rout}stream.py', 'async def _real_loop(')],
    ),
    Slice(
      id: 'p_recorded', category: _pip, group: 'The whole loop',
      title: 'Recorded: learn first, then judge', short: 'recorded',
      says: 'A recorded clip can be pre-scanned to learn the traffic flow, then analysed frame by frame so nothing is skipped.',
      code: [
        CodeAnchor('${_rout}forensic.py', 'def forensic_processing_task(', label: 'The analysis'),
        CodeAnchor('${_eng}flow_prescan.py', 'def prescan_flow(', label: 'The pre-scan'),
      ],
    ),

    // ═══ TRAINING ═══════════════════════════════════════════════════════════
    // ── Get the data ──
    Slice(
      id: 't_fetch', category: _tra, group: 'Get the data',
      title: 'Collect public photos', short: 'a dataset',
      says: 'Public labelled sets are downloaded, their classes renamed to ours and merged into one dataset. '
          'A photo found in both train and validation is moved into train.',
      code: [
        CodeAnchor('${_lab}scripts/fetch_datasets.py', 'def merge(', label: 'Merging'),
        CodeAnchor('${_lab}scripts/fetch_datasets.py', 'def remove_leaks(', label: 'No leaks'),
      ],
    ),
    Slice(
      id: 't_split', category: _tra, group: 'Get the data',
      title: 'Train, validation and test', short: 'a split',
      says: 'Photos are split three ways, so a model is graded on pictures it never saw while learning.',
      code: [CodeAnchor('${_lab}scripts/split_dataset.py', 'def split(')],
    ),

    // ── Train and deploy ──
    Slice(
      id: 't_train', category: _tra, group: 'Train and deploy',
      title: 'Train a model', short: 'a trained model', recipe: ['t_fetch', 't_split'],
      says: 'Ultralytics trains a YOLO model on the dataset. The saved epoch is the one with the best 0.1 × mAP50 + 0.9 × mAP50-95.',
      code: [CodeAnchor('${_lab}scripts/train.py', 'def train(')],
    ),
    Slice(
      id: 't_pause', category: _tra, group: 'Train and deploy',
      title: 'Pause and continue', short: 'pause / continue',
      says: 'Pausing stops the training process; continuing resumes from the last finished epoch. A finished run cannot be resumed.',
      code: [
        CodeAnchor('${_lab}scripts/run_state.py', 'def pause(', label: 'Pause'),
        CodeAnchor('${_lab}scripts/run_state.py', 'def resume_command(', label: 'Continue'),
      ],
    ),
    Slice(
      id: 't_export', category: _tra, group: 'Train and deploy',
      title: 'Export and deploy', short: 'an ONNX file', recipe: ['t_train'],
      says: 'Training only adds a version. When you press Use this on the Models page, that run is exported to ONNX, copied into the models folder for its job and made the active one.',
      code: [
        CodeAnchor('${_eng}model_hub.py', 'def _use_yolo(', label: 'Use this'),
        CodeAnchor('${_lab}scripts/export_onnx.py', 'def export(', label: 'Export'),
      ],
    ),
    Slice(
      id: 't_catalog', category: _tra, group: 'Train and deploy',
      title: 'One active model per job', short: 'the active model', recipe: ['t_export'],
      says: 'Vehicles, helmet, plate and cabin each have one active model. Switching is "Use this" on the Models page.',
      code: [CodeAnchor('${_eng}model_catalog.py', 'def activate(')],
    ),
    Slice(
      id: 't_hub', category: _tra, group: 'Train and deploy',
      title: 'Every version of every model', short: 'the versions list', recipe: ['t_train'],
      says: 'The Models page lists, for each job, the live model and every training run and model file with its scores. '
          'Per-type scores for a detector run are computed on demand on its test photos.',
      code: [
        CodeAnchor('${_eng}model_hub.py', 'def hub(', label: 'The list'),
        CodeAnchor('${_lab}scripts/check_per_class.py', 'def check(', label: 'Per type'),
      ],
    ),

    // ── Improve with your own footage ──
    Slice(
      id: 't_harvest', category: _tra, group: 'Improve with your own footage',
      title: 'Learn from your own footage', short: 'harvested photos', recipe: ['t_catalog'],
      says: 'Review decisions become training pictures. A person checks every picture before it is accepted, '
          'and a dataset is never touched while its model is training.',
      code: [
        CodeAnchor('${_lab}harvest_tool/collect.py', 'def collect(', label: 'Collect'),
        CodeAnchor('${_lab}harvest_tool/accept.py', 'def accept(', label: 'Accept'),
      ],
    ),

    // ═══ FEATURES ═══════════════════════════════════════════════════════════
    // ── Watching ──
    Slice(
      id: 'f_live', category: _fea, group: 'Watching',
      title: 'Watch a camera live', short: 'live monitor',
      says: 'Start Monitoring opens a connection to the backend. The backend reads the camera, runs the loop and sends boxes for the dashboard to draw.',
      code: [
        CodeAnchor('${_dash}monitoring/presentation/screens/live_monitoring_screen.dart', 'void _startMonitoring(', label: 'Dashboard'),
        CodeAnchor('${_rout}stream.py', 'async def video_feed(', label: 'Backend'),
      ],
    ),
    Slice(
      id: 'f_camera', category: _fea, group: 'Watching',
      title: 'Choose the camera', short: 'camera input',
      says: 'A real CCTV, a phone and another laptop are all just an address. The dialog tests it, can save it, and makes it the source.',
      code: [
        CodeAnchor('${_dash}monitoring/presentation/widgets/camera_input_dialog.dart', 'Future<void> _use(', label: 'Dashboard'),
        CodeAnchor('${_rout}settings.py', 'async def set_video_source(', label: 'Backend'),
      ],
    ),

    // ── Analysing a recording ──
    Slice(
      id: 'f_wizard', category: _fea, group: 'Analysing a recording',
      title: 'Set up an analysis', short: 'the wizard',
      says: 'The wizard collects the video, the violations, their zones and the options, then sends them as one config.',
      code: [
        CodeAnchor('${_dash}forensic/presentation/widgets/analysis_wizard.dart', 'void _start(', label: 'Dashboard'),
        CodeAnchor('${_rout}forensic.py', 'async def upload_forensic_video(', label: 'Backend'),
      ],
    ),
    Slice(
      id: 'f_zones', category: _fea, group: 'Analysing a recording',
      title: 'Draw a zone', short: 'a drawn zone',
      says: 'The zone editor saves your drawing. On the backend, each violation turns the wizard\'s settings into the zone it needs.',
      code: [
        CodeAnchor('${_dash}forensic/presentation/widgets/zone_editor.dart', 'void _save(', label: 'Dashboard'),
        CodeAnchor('${_viol}base.py', 'def from_wizard(', label: 'Backend'),
      ],
    ),
    Slice(
      id: 'f_review', category: _fea, group: 'Analysing a recording',
      title: 'Review the tickets', short: 'review',
      says: 'Each ticket is confirmed or marked as a false alarm.',
      code: [CodeAnchor('${_dash}forensic/domain/review_controller.dart', 'Future<bool> decide(')],
    ),
    Slice(
      id: 'f_plate', category: _fea, group: 'Analysing a recording',
      title: 'Fix a plate', short: 'a corrected plate',
      says: 'If the reader got the plate wrong, type the right one. The ticket keeps both the reader\'s guess and your correction.',
      code: [
        CodeAnchor('${_dash}forensic/domain/review_controller.dart', 'Future<bool> setPlate(', label: 'Dashboard'),
        CodeAnchor('${_rout}forensic.py', 'async def set_ticket_plate(', label: 'Backend'),
      ],
    ),

    // ── Models ──
    Slice(
      id: 'f_models', category: _fea, group: 'Models',
      title: 'Switch the active model', short: 'models tab',
      says: 'Pick a version for a job, press Use this, and the backend uses it from the next analysis on.',
      code: [
        CodeAnchor('${_dash}models_hub/presentation/screens/models_hub_screen.dart', 'Future<void> _use(', label: 'Dashboard'),
        CodeAnchor('${_rout}model.py', 'def use_hub_version(', label: 'Backend'),
      ],
    ),
    Slice(
      id: 'f_train', category: _fea, group: 'Models',
      title: 'Start a training', short: 'training studio',
      says: 'Pick a model and a preset and the backend starts the training. Trainings started here stop if the backend restarts; '
          'those started from the terminal Training Lab do not.',
      code: [
        CodeAnchor('${_dash}training/presentation/screens/training_studio_screen.dart', 'Future<void> _start(', label: 'Dashboard'),
        CodeAnchor('${_rout}training.py', 'async def start_training(', label: 'Backend'),
      ],
    ),
  ];
}
