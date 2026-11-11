import 'package:flutter/material.dart';
import '../../models/violation_model.dart';
import '../math_text.dart';

class CodeStepData {
  final String title;
  final String codeSnippet;
  final String laymanExplanation;
  final String? latexMath;
  final String mathAnalogy;
  final String failureMode;
  final String aiOptimizationFix;

  const CodeStepData({
    required this.title,
    required this.codeSnippet,
    required this.laymanExplanation,
    this.latexMath,
    required this.mathAnalogy,
    required this.failureMode,
    required this.aiOptimizationFix,
  });
}

class CodeMathVisualizer extends StatefulWidget {
  final ViolationModel violation;

  const CodeMathVisualizer({Key? key, required this.violation}) : super(key: key);

  @override
  _CodeMathVisualizerState createState() => _CodeMathVisualizerState();
}

class _CodeMathVisualizerState extends State<CodeMathVisualizer> {
  int _currentStep = 0;

  List<CodeStepData> _getStepsForViolation(String id) {
    switch (id) {
      case 'm1': // Counterflow
        return const [
          CodeStepData(
            title: '1. Detect Current Vehicles in Frame',
            codeSnippet: '''# Grab every vehicle detected in the current video frame
for curr_car in current_frame_detections:
    best_match = None
    min_pixel_distance = 999999.0''',
            laymanExplanation:
                'We look at the video frame right now and grab every detected vehicle. For each car, we prepare to search for where it was in the previous frame.',
            latexMath: r'D_t = \{ c_1, c_2, \dots, c_N \}, \quad c_i = (x_i, y_i, w_i, h_i)',
            mathAnalogy:
                'The Snapshot List: We take a polaroid of the road right now and mark the center (x, y) coordinates of every vehicle on asphalt.',
            failureMode:
                'Computational Complexity: Running this frame-by-frame on raw bounding boxes without spatial indexing requires processing every single noisy bounding box.',
            aiOptimizationFix:
                'YOLOv8 Class Filtering + Confidence Threshold: Filters out low-confidence ghosts (conf < 0.4) before any tracking loop even runs.',
          ),
          CodeStepData(
            title: '2. Exhaustive Pairwise Matching (The Keychain Test)',
            codeSnippet: '''    # O(N * M) Exhaustive Search: compare against EVERY previous car
    for prev_car in previous_frame_detections:
        # Measure physical distance on screen
        dist = sqrt((curr_car.x - prev_car.x)**2 + (curr_car.y - prev_car.y)**2)
        if dist < min_pixel_distance and dist < MAX_TRAVEL_THRESHOLD:
            min_pixel_distance = dist
            best_match = prev_car''',
            laymanExplanation:
                'Trying every key in a keychain: To figure out which car moved where, we literally test every single car in frame (t) against every single car in frame (t-1).',
            latexMath: r'd(c_t, c_{t-1}) = \sqrt{(x_t - x_{t-1})^2 + (y_t - y_{t-1})^2}',
            mathAnalogy:
                'The Ruler Test: You put a physical ruler between last second\'s car and this second\'s car. If it\'s within 30 pixels, you assume they\'re the same vehicle.',
            failureMode:
                'O(N × M) Combinatorial Explosion & ID Swaps: If 2 motorcycles cross paths or pass closely, the naive ruler matches the wrong car! Their identities swap instantly.',
            aiOptimizationFix:
                'ByteTrack (Kalman Filter + Hungarian Algorithm): Uses speed momentum and predicted bounding box IoU instead of naive point distance, completely preventing ID swaps.',
          ),
          CodeStepData(
            title: '3. Instantaneous Velocity Vector',
            codeSnippet: '''    # Calculate frame-to-frame movement arrow
    if best_match is not None:
        delta_x = curr_car.x - best_match.x
        delta_y = curr_car.y - best_match.y
        velocity_vector = (delta_x, delta_y)''',
            laymanExplanation:
                'We draw an arrow from where the car was 33 milliseconds ago to where it is right now. The length of the arrow is its instant speed, and its angle is where it is heading.',
            latexMath: r'\vec{V} = \begin{pmatrix} \Delta x \\ \Delta y \end{pmatrix} = \begin{pmatrix} x_t - x_{t-1} \\ y_t - y_{t-1} \end{pmatrix}',
            mathAnalogy:
                'The Direction Arrow: Subtract the old coordinates from the new coordinates. If it shifted +15 pixels to the right, the arrow points right.',
            failureMode:
                'Sensor Jitter & Wind Shake: If camera vibrates by just 2 pixels, or YOLO bounding box flickers, delta_x jumps backwards for 1 frame! This triggers a false violation.',
            aiOptimizationFix:
                'Temporal Active Ledger: A rolling history buffer (minimum 4 to 15 frames) with a minimum 6px magnitude threshold filters out all micro-jitters.',
          ),
          CodeStepData(
            title: '4. Region of Interest (PNPoly Ray-Casting)',
            codeSnippet: '''        # Jordan Curve Theorem: Count ray crossings with road polygon
        inside_zone = False
        j = len(polygon_vertices) - 1
        for i in range(len(polygon_vertices)):
            if ((polygon_vertices[i].y > curr_car.y) != (polygon_vertices[j].y > curr_car.y)) and \\
               (curr_car.x < (polygon_vertices[j].x - polygon_vertices[i].x) * (curr_car.y - polygon_vertices[i].y) / \\
               (polygon_vertices[j].y - polygon_vertices[i].y) + polygon_vertices[i].x):
                inside_zone = not inside_zone
            j = i''',
            laymanExplanation:
                'The Laser Pointer & Fence Rule: To check if a car is inside the monitored road boundary, shoot an imaginary laser beam straight to infinity. If it crosses an ODD number of fence lines, you are inside. Even number means outside.',
            latexMath: r'\text{Inside} \iff \sum_{k=1}^{E} \text{Intersect}(\text{Ray}(c_t), \text{Edge}_k) \equiv 1 \pmod 2',
            mathAnalogy:
                'The Fence Crossing: Walk straight out of a fenced park. If you hop 1 fence, you were inside. If you hop 2 fences, you started outside and just passed through.',
            failureMode:
                'Exhaustive Edge Checking O(E): Every single vehicle on every single frame tests every polygon segment, wasting CPU cycles on cars far away from the road.',
            aiOptimizationFix:
                'Spatial Bounding Box (AABB) Pre-gating + cv2.pointPolygonTest: First checks min/max box in O(1); only runs polygon math if candidate is actually within bounds.',
          ),
          CodeStepData(
            title: '5. Dot Product (Walking Against Traffic)',
            codeSnippet: '''        if inside_zone:
            # Vector Dot Product between Vehicle Arrow and Legal Road Flow
            # legal_flow = (rx, ry)
            dot_product = (delta_x * rx) + (delta_y * ry)

            # If dot product is negative, angle is > 90 degrees (Opposing flow!)
            if dot_product < 0.0:
                flag_violation(curr_car, "COUNTERFLOW")''',
            laymanExplanation:
                'Walking Against the Wind: Imagine the legal road flow is a steady wind. If you drive with the wind, the score is positive (+). If you turn around and face directly into oncoming traffic, the score becomes negative (-).',
            latexMath: r'\vec{V} \cdot \vec{R} = V_x R_x + V_y R_y = |\vec{V}||\vec{R}|\cos(\theta) < 0 \implies \theta > 90^\circ',
            mathAnalogy:
                'The Scorecard: We multiply horizontal movements together, vertical movements together, and add them up. Positive = Legal, Negative = Kamote Counterflow!',
            failureMode:
                'Instantaneous False Flags: U-turns or lane changes momentarily point sideways or backward for a split second, causing instant unfair tickets.',
            aiOptimizationFix:
                'Multi-frame Sustained Violation Ledger: Requires continuous opposing dot product over consecutive frames before logging a legal violation.',
          ),
        ];

      case 'm2': // Illegal Parking
        return const [
          CodeStepData(
            title: '1. Frame-to-Frame Stationary Check',
            codeSnippet: '''# Brute Force: Compare position from previous frame
displacement = sqrt((curr_car.x - prev_car.x)**2 + (curr_car.y - prev_car.y)**2)
if displacement < 5.0: # Less than 5 pixels moved
    stationary_frame_count += 1
else:
    stationary_frame_count = 0''',
            laymanExplanation:
                'The Stillness Check: If the vehicle moved less than 5 pixels since the last frame, add 1 to the parked timer. If it moves even slightly, reset to zero.',
            latexMath: r'd = \sqrt{\Delta x^2 + \Delta y^2} < \epsilon \implies \text{Stationary}',
            mathAnalogy:
                'The Red Light, Green Light game: If the car flinches by even a few pixels, the counter resets back to start.',
            failureMode:
                'Bounding Box Flutter: YOLO bounding boxes naturally bounce by 3-7 pixels each frame due to lighting/shadows. The counter constantly resets to zero, missing actual parked cars!',
            aiOptimizationFix:
                'Temporal Window Averaging: Accumulates centroid variance over a 150-frame rolling window rather than a fragile frame-to-frame reset.',
          ),
          CodeStepData(
            title: '2. Check No-Parking Zone & Threshold',
            codeSnippet: '''# If stationary inside restricted zone for > 300 frames (10 seconds)
if stationary_frame_count > 300 and check_pnpoly(curr_car.x, curr_car.y, no_parking_polygon):
    flag_violation(curr_car, "ILLEGAL_PARKING")''',
            laymanExplanation:
                'If the car stays still inside the red painted box for more than 10 seconds, issue an illegal parking citation.',
            latexMath: r'T_{\text{stopped}} \ge T_{\text{threshold}} \land C_t \in \mathcal{P}_{\text{no\_parking}}',
            mathAnalogy:
                'The Parking Meter: A timer ticks up while inside the red zone. If it exceeds 10 seconds, the meter alarms.',
            failureMode:
                'Traffic Jam False Positives: Vehicles stuck in normal stop-and-go traffic inside the zone get falsely ticketed!',
            aiOptimizationFix:
                'Contextual Traffic Gating: Verifies traffic light state and road speed before ticketing stationary vehicles.',
          ),
        ];

      case 'm3': // Illegal Turn
        return const [
          CodeStepData(
            title: '1. Intersection Trajectory Capture',
            codeSnippet: '''# Brute Force: Sample position before entry and at exit
entry_pt = (car.x_at_entry, car.y_at_entry)
exit_pt  = (car.x_at_exit, car.y_at_exit)
v_entry = (entry_pt[0] - car.x_prev, entry_pt[1] - car.y_prev)
v_exit  = (exit_pt[0] - entry_pt[0], exit_pt[1] - entry_pt[1])''',
            laymanExplanation:
                'Mark where the car entered the crossroads and where it left. Draw an incoming arrow and an outgoing arrow.',
            latexMath: r'\vec{V}_{\text{in}} = P_{\text{entry}} - P_{\text{prev}}, \quad \vec{V}_{\text{out}} = P_{\text{exit}} - P_{\text{entry}}',
            mathAnalogy:
                'The Road Compass: Taking your bearing before entering an intersection and checking your compass heading as you drive out.',
            failureMode:
                'Rigid Tripwire Failure: If a driver weaves slightly to avoid a pothole near the line, the entry/exit points skew, calculating completely incorrect turn angles.',
            aiOptimizationFix:
                'ByteTrack Smoothed Polynomial Spline: Fits a continuous bezier trajectory curve across the entire intersection instead of 2 discrete snapshot points.',
          ),
          CodeStepData(
            title: '2. Angle Difference vs Prohibited Maneuver',
            codeSnippet: '''# Compute turn angle using arctangent
angle_in  = atan2(v_entry[1], v_entry[0])
angle_out = atan2(v_exit[1], v_exit[0])
turn_angle = (angle_out - angle_in) * 180.0 / pi

# Naive check: If turned left (> 45 deg) where only straight is allowed
if turn_angle > 45.0 and zone_rule == "NO_LEFT_TURN":
    flag_violation(car, "ILLEGAL_TURN")''',
            laymanExplanation:
                'Measure the angle between the two arrows. If the angle bends more than 45 degrees left on a straight-only street, flag an illegal turn.',
            latexMath: r'\theta_{\text{turn}} = \text{atan2}(V_{y}^{\text{out}}, V_{x}^{\text{out}}) - \text{atan2}(V_{y}^{\text{in}}, V_{x}^{\text{in}})',
            mathAnalogy:
                'The Protractor Check: Placing a school protractor over the road map to measure if the vehicle bent its path too sharply.',
            failureMode:
                'Angle Discontinuity & Jitter: atan2 jumps from +180 to -180 degrees at boundaries; lane-change drift can trigger the 45-degree threshold.',
            aiOptimizationFix:
                'Contextual Vector Gating: Directional corridor fields verify whether the vehicle actually merged into a prohibited exit lane.',
          ),
        ];

      case 'm4': // No Helmet
        return const [
          CodeStepData(
            title: '1. Crop Top Head Region of Rider',
            codeSnippet: '''# Naive Assumption: Top 20% of motorcycle bounding box is rider head
head_x1 = moto.x1
head_y1 = moto.y1
head_x2 = moto.x2
head_y2 = moto.y1 + int(0.20 * (moto.y2 - moto.y1))
head_crop = frame[head_y1:head_y2, head_x1:head_x2]''',
            laymanExplanation:
                'Cut out a rectangular strip across the top 20% of the motorcycle box, assuming that is where the driver head must be.',
            latexMath: r'Z_{\text{head}} = [x_{\text{moto}}, y_{\text{moto}}, w_{\text{moto}}, 0.20 \times h_{\text{moto}}]',
            mathAnalogy:
                'The Cookie Cutter: Punching a rigid rectangle out of the photo right above the handlebars and hoping a head is inside.',
            failureMode:
                'Perspective & Stature Mismatch: Taller riders or motorcycles viewed from a low angle have their heads cut in half or completely outside the top 20% box.',
            aiOptimizationFix:
                'Composite Multi-Class Detection: YOLO identifies separate "person" and "motorcycle" classes, isolating the exact rider body box regardless of viewpoint.',
          ),
          CodeStepData(
            title: '2. Pixel Color & Texture Heuristic',
            codeSnippet: '''# Classical Vision: Skin tone vs helmet color thresholding
hsv = rgb_to_hsv(head_crop)
skin_pixels = count_range(hsv, lower_skin=[0, 20, 70], upper_skin=[20, 255, 255])
total_head_pixels = head_crop.shape[0] * head_crop.shape[1]

# If skin/hair pixels dominate top crop -> No Helmet
if (skin_pixels / total_head_pixels) > 0.35:
    flag_violation(moto, "NO_HELMET")''',
            laymanExplanation:
                'Count skin-colored pixels on the head crop. If more than 35% matches skin or dark hair tones instead of smooth plastic paint, flag as bareheaded.',
            latexMath: r'\text{Ratio} = \frac{\sum_{(u,v)} \mathbb{I}(H(u,v) \in \text{Skin})}{\text{Area}(Z_{\text{head}})} > 0.35',
            mathAnalogy:
                'Color Swatch Comparison: Holding a skin-colored swatch against the photo. If it matches skin color, you assume no helmet is worn.',
            failureMode:
                'Skin Tone Bias & Shadows: Black or tan helmets match hair and skin palettes; streetlights, shadows, and caps cause massive false violations.',
            aiOptimizationFix:
                'Hierarchical Helmet Specialist ONNX: High-resolution sub-crop classifier explicitly trained to differentiate helmets, caps, bandanas, and bare heads.',
          ),
        ];

      case 'm5': // Missing Side Mirror
        return const [
          CodeStepData(
            title: '1. Handlebar Region Isolation',
            codeSnippet: '''# Heuristic: Mirrors sit on left & right upper corners of handlebars
left_mirror_roi  = moto_crop[0:int(0.3*h), 0:int(0.25*w)]
right_mirror_roi = moto_crop[0:int(0.3*h), int(0.75*w):w]''',
            laymanExplanation:
                'Chop out the top-left and top-right corners of the motorcycle box where side mirrors are supposed to stick out.',
            latexMath: r'R_{\text{left}} = [0, 0, 0.25W, 0.30H], \quad R_{\text{right}} = [0.75W, 0, 0.25W, 0.30H]',
            mathAnalogy:
                'The Corner Peeking: Putting blinders on and staring only at the top corners of the handlebars looking for circular protrusions.',
            failureMode:
                'Angle & Occlusion Vulnerability: Whenever a motorcycle turns or banks, one handlebar swings forward and the other hides behind the rider body.',
            aiOptimizationFix:
                'Pose-Aware Multi-View Inspection: Normalizes the vehicle orientation before inspecting mirror anchor geometry.',
          ),
          CodeStepData(
            title: '2. Circular Edge & Contour Counting',
            codeSnippet: '''# Canny Edge Detection + Hough Circles
left_circles  = hough_circles(canny(left_mirror_roi), min_radius=5, max_radius=20)
right_circles = hough_circles(canny(right_mirror_roi), min_radius=5, max_radius=20)

mirrors_found = (1 if len(left_circles) > 0 else 0) + (1 if len(right_circles) > 0 else 0)
if mirrors_found < 2:
    flag_violation(moto, "MISSING_SIDE_MIRROR")''',
            laymanExplanation:
                'Use geometric circle detectors (Hough transform) on both corners. If fewer than 2 round shapes are detected, issue a ticket.',
            latexMath: r'N_{\text{circ}} = \sum_{k \in \{L, R\}} \mathbb{I}(\text{HoughCircles}(R_k) \neq \emptyset) < 2',
            mathAnalogy:
                'Tracing with a Compass: Trying to draw perfect circles over edges in the corners. If you cannot find two round circles, ticket the driver.',
            failureMode:
                'Custom Mirror Shapes: Modern bar-end or rectangular aerodynamic mirrors produce zero Hough circles; street clutter creates false circle ghosts.',
            aiOptimizationFix:
                'Specialist Mirror Detection Network: Deep feature detector trained on varied aftermarket mirror designs across multiple angles.',
          ),
        ];

      case 'm6': // Overloading
        return const [
          CodeStepData(
            title: '1. Unfiltered Head & Face Counting',
            codeSnippet: '''# Scan the frame around the motorcycle for human faces
all_faces = detect_faces_in_box(frame, moto.bounding_box)
rider_count = len(all_faces)''',
            laymanExplanation:
                'Count how many faces appear within the motorcycle box boundary.',
            latexMath: r'N_{\text{faces}} = |\{ f_k \mid f_k \in B_{\text{moto}} \}|',
            mathAnalogy:
                'Headcount at the Door: Counting how many heads you see through a small window without checking if they are standing behind it.',
            failureMode:
                'Crowd Overlap: In heavy traffic or near crosswalks, pedestrians walking right behind or alongside the motorcycle get counted as riders!',
            aiOptimizationFix:
                'Semantic Body-Chassis IoU: Requires at least 80% of the rider body polygon to be contained within the motorcycle silhouette with seated posture.',
          ),
          CodeStepData(
            title: '2. Capacity Threshold Comparison',
            codeSnippet: '''# Hard legal capacity for motorcycles is 2 persons
if rider_count > 2:
    flag_violation(moto, "OVERLOADING")''',
            laymanExplanation:
                'If the headcount exceeds 2, immediately generate an overloading violation ticket.',
            latexMath: r'N_{\text{riders}} > 2 \implies \text{Flag}(\text{Overloading})',
            mathAnalogy:
                'The Bouncer Counter: Clicking the mechanical tally counter. If it reaches 3, the alarm goes off.',
            failureMode:
                'Backpacks & Cargo Bags: Round backpacks and helmets strapped to the luggage rack get falsely detected as additional passengers.',
            aiOptimizationFix:
                'Temporal Multi-Frame Verification: Confirms persistent rider keypoints across multiple seconds before penalizing the vehicle.',
          ),
        ];

      case 'c1': // No Plate Number
        return const [
          CodeStepData(
            title: '1. Crop Fixed Bumper Region',
            codeSnippet: '''# Plate assumed in bottom 30% center of vehicle
bx1 = car.x1 + int(0.25 * car.width)
by1 = car.y1 + int(0.70 * car.height)
bx2 = car.x1 + int(0.75 * car.width)
by2 = car.y2
bumper_crop = frame[by1:by2, bx1:bx2]''',
            laymanExplanation:
                'Cut a rectangular window out of the bottom-center of the vehicle box where the bumper and license plate typically sit.',
            latexMath: r'Z_{\text{bumper}} = [x + 0.25w, y + 0.70h, 0.50w, 0.30h]',
            mathAnalogy:
                'The Mailbox Slot: Looking exclusively through a fixed slot in the bumper hoping the license plate is directly behind it.',
            failureMode:
                'Off-center Mounts & Perspectives: Angled camera views or vehicles with side-mounted plates have their plates completely outside this static crop.',
            aiOptimizationFix:
                'Dynamic Bumper Slicing: Crops the full lower 40% chassis and passes it to an anchor-free plate localization neural network.',
          ),
          CodeStepData(
            title: '2. Edge Density & High-Contrast Clustering',
            codeSnippet: '''# Look for high-contrast rectangular text pattern
edges = sobel_edge_detector(grayscale(bumper_crop))
contrast_clusters = find_rectangular_contours(edges, aspect_ratio=(2.0, 3.5))

# If no plate-shaped high-contrast rectangle found:
if len(contrast_clusters) == 0:
    flag_violation(car, "NO_PLATE")''',
            laymanExplanation:
                'Look for a cluster of sharp, high-contrast black-and-white lines that looks like letters on a white metal plate.',
            latexMath: r'\text{PlateFound} \iff \exists R \in \text{Contours} : \text{Aspect}(R) \in [2.0, 3.5] \land \text{Edges}(R) > \tau',
            mathAnalogy:
                'The Barcode Scanner: Searching for alternating dark and bright zebra stripes on the metal surface.',
            failureMode:
                'Dirt, Grilles & Shadows: Radiator grilles produce hundreds of fake edge clusters, while a dirty or shaded plate produces zero edges.',
            aiOptimizationFix:
                'Specialist Plate Detection ONNX + Consecutive Miss Ledger: Requires 2+ consecutive specialist misses before raising a true No-Plate ticket.',
          ),
        ];

      case 'c2': // Red Light Running
        return const [
          CodeStepData(
            title: '1. Traffic Light Color Pixel Counting',
            codeSnippet: '''# Crop static traffic light box and count red pixels
light_crop = frame[tl_y1:tl_y2, tl_x1:tl_x2]
red_mask = (light_crop[:,:,2] > 200) & (light_crop[:,:,0] < 100)
is_red = (count_nonzero(red_mask) > 50)''',
            laymanExplanation:
                'Stare at a fixed box in the sky where the traffic light is. If you count more than 50 bright red pixels, declare the light RED.',
            latexMath: r'L_{\text{red}} \iff \sum_{(u,v) \in Z_{\text{light}}} \mathbb{I}(R(u,v) > 200 \land B(u,v) < 100) > 50',
            mathAnalogy:
                'The Peep Hole: Looking through a cardboard cutout at the traffic signal bulb to see if red light shines through.',
            failureMode:
                'Direct Sunlight Glare: Sunset or direct sunlight washes out the bulb, causing bloom or making a green lens appear red to naive thresholding.',
            aiOptimizationFix:
                'Dual-State YOLO Traffic Light Detector: Reads optical signal state with deep semantic context instead of fragile RGB pixel counts.',
          ),
          CodeStepData(
            title: '2. Static Stopline Intersection Tripwire',
            codeSnippet: '''# Check if vehicle bounding box intersects virtual stopline
if is_red:
    for car in frame_detections:
        if line_intersects_box(stop_line_coords, car.bbox):
            flag_violation(car, "RED_LIGHT_RUNNING")''',
            laymanExplanation:
                'If the signal is red, draw an invisible line on the asphalt. The instant any car rectangle touches that line, issue a red-light ticket.',
            latexMath: r'\text{Violation} \iff L_{\text{red}} \land (B_{\text{car}} \cap L_{\text{stop\_line}} \neq \emptyset)',
            mathAnalogy:
                'The Tripwire Laser: A laser beam stretching across the intersection that triggers the alarm if anything breaks the beam.',
            failureMode:
                'Shadows & Grace Period: Vehicle shadows crossing the line trigger false tickets; cars trapped lawfully mid-intersection during yellow get caught.',
            aiOptimizationFix:
                'Wheel-Contact Point Tracking with Yellow Grace Period: Tracks the bottom tire patch velocity vector across the stopline plane over time.',
          ),
        ];

      case 'c3': // No Seatbelt
        return const [
          CodeStepData(
            title: '1. Windshield Driver Torso Crop',
            codeSnippet: '''# Assume driver torso is in top-left quadrant of car body
torso_x1 = car.x1 + int(0.10 * car.width)
torso_y1 = car.y1 + int(0.15 * car.height)
torso_x2 = car.x1 + int(0.50 * car.width)
torso_y2 = car.y1 + int(0.55 * car.height)
torso_crop = frame[torso_y1:torso_y2, torso_x1:torso_x2]''',
            laymanExplanation:
                'Cut out the top-left area behind the windshield where the driver chest and shoulders should be.',
            latexMath: r'Z_{\text{torso}} = [x + 0.10w, y + 0.15h, 0.40w, 0.40h]',
            mathAnalogy:
                'Looking Through the Window: Peeking through the driver side of the windshield with a fixed square magnifier.',
            failureMode:
                'Window Glare & Tint: Heavily tinted glass or sky reflections turn the windshield into a mirror, hiding the driver completely.',
            aiOptimizationFix:
                'Window Tint Override Gate: First classifies window transparency; if tinted or glare-occluded, gracefully aborts instead of ticketing.',
          ),
          CodeStepData(
            title: '2. Hough Line Transform for Diagonal Strap',
            codeSnippet: '''# Look for a 45-degree dark diagonal line across chest
edges = canny(grayscale(torso_crop))
lines = hough_lines_probabilistic(edges, min_length=40)
has_diagonal_strap = False

for (x1, y1, x2, y2) in lines:
    angle = abs(atan2(y2 - y1, x2 - x1) * 180.0 / pi)
    if 30.0 <= angle <= 60.0:  # Typical seatbelt angle
        has_diagonal_strap = True
        break

if not has_diagonal_strap:
    flag_violation(car, "NO_SEATBELT")''',
            laymanExplanation:
                'Search for a sharp diagonal line tilted between 30 and 60 degrees across the chest. If no diagonal line is found, flag as unbelted.',
            latexMath: r'\text{Belt} \iff \exists (P_1, P_2) : \left| \text{atan2}(\Delta y, \Delta x) \right| \in [30^\circ, 60^\circ]',
            mathAnalogy:
                'The Diagonal Ruler: Searching the driver chest for a dark sash running from shoulder to hip.',
            failureMode:
                'Black Shirts & Patterns: Dark clothing completely blends with black seatbelts, while striped or V-neck shirts create fake seatbelt lines.',
            aiOptimizationFix:
                'Deep Cabin Specialist Classifier: Neural network trained on multi-spectral cabin lighting to identify genuine buckle and strap textures.',
          ),
        ];

      case 'c4': // Crosswalk Obstruction
        return const [
          CodeStepData(
            title: '1. Pedestrian Crosswalk Box Overlap',
            codeSnippet: '''# Compute raw bounding box Intersection over Union with crosswalk
intersection_area = compute_overlap(car.bbox, crosswalk_polygon)
car_area = car.width * car.height
overlap_ratio = intersection_area / car_area''',
            laymanExplanation:
                'Measure how much of the car box physically sits on top of the painted zebra crosswalk box.',
            latexMath: r'\text{Overlap} = \frac{\text{Area}(B_{\text{car}} \cap Z_{\text{crosswalk}})}{\text{Area}(B_{\text{car}})}',
            mathAnalogy:
                'The Foot-in-the-Door Test: Measuring what percentage of the car footprint is stepping onto the pedestrian crosswalk.',
            failureMode:
                'Legal Driving Overlap: Cars lawfully driving across the zebra lane on green have 100% overlap, causing instant false tickets.',
            aiOptimizationFix:
                'Multi-Modal Traffic & Velocity Conjunction: Requires vehicle speed to stay near 0 km/h specifically while the traffic signal is RED.',
          ),
          CodeStepData(
            title: '2. Stopped State on Zebra Lane',
            codeSnippet: '''# If vehicle is stopped (> 5 sec) on crosswalk while red
if overlap_ratio > 0.25 and car.speed < 1.0 and light_is_red:
    flag_violation(car, "CROSSWALK_OBSTRUCTION")''',
            laymanExplanation:
                'If more than 25% of the car covers the crosswalk, speed is 0, and the light is red, flag as obstructing pedestrians.',
            latexMath: r'(\text{Overlap} > 0.25) \land (V \approx 0) \land (L == \text{Red}) \implies \text{Flag}',
            mathAnalogy:
                'The Blocked Crosswalk Ticket: Issuing a citation only when a car parks its nose directly across the walkway, forcing walkers into traffic.',
            failureMode:
                'Stop-and-Go Creep: Vehicles slowly inching forward to see past blind corners get penalized unfairly.',
            aiOptimizationFix:
                'Pedestrian Proximity Threat Field: Evaluates if actual pedestrians are actively being deflected or blocked by the stopped chassis.',
          ),
        ];

      case 'c5': // Distracted Driving
        return const [
          CodeStepData(
            title: '1. Driver Head & Hand Region Search',
            codeSnippet: '''# Isolate head and steering wheel area
driver_area = car_crop[int(0.15*h):int(0.60*h), int(0.15*w):int(0.55*w)]''',
            laymanExplanation:
                'Crop the cabin area between the driver head, ears, and steering wheel.',
            latexMath: r'Z_{\text{cabin}} = [x + 0.15w, y + 0.15h, 0.40w, 0.45h]',
            mathAnalogy:
                'The Cockpit View: Framing the steering wheel and the driver upper body inside a camera viewfinder.',
            failureMode:
                'Window Obstructions: Windshield wipers, rearview mirror pendants, and phone dash mounts crowd the area.',
            aiOptimizationFix:
                'Body Pose Keypoint Estimation: Tracks wrist and elbow vectors relative to the head and ears to confirm holding posture.',
          ),
          CodeStepData(
            title: '2. Phone-Sized Black Rectangle Match',
            codeSnippet: '''# Template match for typical black smartphone rectangle
phone_template = load_image("phone_template.png")
match_score = match_template(driver_area, phone_template, method=TM_CCOEFF_NORMED)

if match_score > 0.70:
    flag_violation(car, "DISTRACTED_DRIVING")''',
            laymanExplanation:
                'Slide a template photo of a black smartphone across the driver area. If pixel correlation exceeds 70%, claim the driver is on their phone.',
            latexMath: r'R(x,y) = \frac{\sum (T - \bar{T})(I - \bar{I})}{\sqrt{\sum(T-\bar{T})^2 \sum(I-\bar{I})^2}} > 0.70',
            mathAnalogy:
                'The Cookie Mold: Stamping a phone-shaped cookie mold across the image looking for an identical silhouette.',
            failureMode:
                'Wallet & Dashboard False Positives: Wallets, sunglasses, dark dashboard vents, and scratching one ear all trigger template matches.',
            aiOptimizationFix:
                'Cabin Specialist Object Detector: High-resolution object detection model specifically trained on real phones in hand vs dash mounts.',
          ),
        ];

      case 'e1': // Swerving
        return const [
          CodeStepData(
            title: '1. Frame-to-Frame X-Centroid Difference',
            codeSnippet: '''# Brute Force: Monitor lateral displacement per frame
delta_x = abs(curr_car.centroid_x - prev_car.centroid_x)
lateral_speed = delta_x / dt''',
            laymanExplanation:
                'Check how far sideways (left or right) the car shifted between two consecutive frames.',
            latexMath: r'V_{\text{lat}} = \frac{|\Delta x|}{\Delta t} = \frac{|x_t - x_{t-1}|}{\Delta t}',
            mathAnalogy:
                'The Sideways Ruler: Measuring how many inches the car slid left or right in a split second.',
            failureMode:
                'Normal Lane Changes: Smooth, legal lane changes produce high lateral movement, falsely triggering swerving alerts.',
            aiOptimizationFix:
                'Road-Aligned Coordinate Projection: Transforms pixel space into road-relative coordinates to distinguish lane changes from erratic swerves.',
          ),
          CodeStepData(
            title: '2. Lateral Jerk (Third Derivative) Spike',
            codeSnippet: '''# Calculate rate of change of lateral acceleration
lateral_accel = (lateral_speed - prev_lateral_speed) / dt
lateral_jerk  = abs(lateral_accel - prev_lateral_accel) / dt

# If violent zig-zag motion detected:
if lateral_jerk > JERK_THRESHOLD:
    flag_violation(curr_car, "SWERVING")''',
            laymanExplanation:
                'Calculate the suddenness of the swerve (jerk). If the car violently snaps left and right like a zigzag, flag as dangerous swerving.',
            latexMath: r'J_{\text{lat}} = \frac{d^3 x}{dt^3} \approx \frac{\Delta a_{\text{lat}}}{\Delta t} > J_{\text{threshold}}',
            mathAnalogy:
                'The Seismograph: A needle recording violent tremors. Gentle steering shows smooth waves; sudden erratic jerks spike off the chart.',
            failureMode:
                'Camera Vibration & Bounding Box Noise: Wind gusts shaking the pole cause phantom acceleration spikes on perfectly straight cars.',
            aiOptimizationFix:
                'Savitzky-Golay Trajectory Smoothing: Filters high-frequency tracking noise to isolate genuine physical vehicle dynamics.',
          ),
        ];

      case 'e2': // Over-speeding
        return const [
          CodeStepData(
            title: '1. 2D Pixel Distance Travelled',
            codeSnippet: '''# Calculate raw distance in screen pixels
pixel_dist = sqrt((curr_car.x - prev_car.x)**2 + (curr_car.y - prev_car.y)**2)
pixels_per_sec = pixel_dist / frame_time''',
            laymanExplanation:
                'Measure how many pixels on the screen the car moved in one second.',
            latexMath: r'd_{\text{px}} = \sqrt{(x_2 - x_1)^2 + (y_2 - y_1)^2}, \quad V_{\text{px}} = \frac{d_{\text{px}}}{\Delta t}',
            mathAnalogy:
                'The TV Screen Ruler: Measuring with a plastic ruler on your monitor how fast a car moves across the screen.',
            failureMode:
                'Perspective Distortion: Cars near the camera move 200 pixels/sec at 30 km/h; cars far away move only 20 pixels/sec at 100 km/h!',
            aiOptimizationFix:
                'Homography Matrix (3x3 Bird\'s-Eye Transform): Flattens perspective into a calibrated real-world meter grid.',
          ),
          CodeStepData(
            title: '2. Fixed Pixels-to-Meters Ratio & Speed Threshold',
            codeSnippet: '''# Naive: Multiply by static global ratio (e.g., 0.05 meters per pixel)
speed_mps = pixels_per_sec * 0.05
speed_kph = speed_mps * 3.6

if speed_kph > POSTED_SPEED_LIMIT:
    flag_violation(curr_car, "OVERSPEEDING")''',
            laymanExplanation:
                'Multiply pixel speed by a single guess number to get km/h. If it exceeds the speed limit, issue a speeding violation.',
            latexMath: r'V_{\text{kph}} = \left( V_{\text{px}} \times \text{PPM} \right) \times 3.6 > V_{\text{limit}}',
            mathAnalogy:
                'The One-Size-Fits-All Scale: Assuming every inch on the screen represents exactly 10 feet of real asphalt everywhere.',
            failureMode:
                'Complete Inaccuracy: Completely breaks without depth calibration, ticketing slow cars near the camera while missing speeding cars in the distance.',
            aiOptimizationFix:
                'DeepSORT Calibrated Kinematic Ledger: Calculates 3D ground-plane velocity vector averaged across calibrated optical markers.',
          ),
        ];

      default:
        return const [
          CodeStepData(
            title: '1. Brute Force Iteration & Centroid Computation',
            codeSnippet: '''# Naive un-indexed loop across all detections
for detection in frame_detections:
    cx = (detection.x1 + detection.x2) / 2.0
    cy = (detection.y1 + detection.y2) / 2.0''',
            laymanExplanation:
                'Finds the exact center point of each detected box by averaging edges.',
            latexMath: r'C = \left( \frac{x_1 + x_2}{2}, \frac{y_1 + y_2}{2} \right)',
            mathAnalogy:
                'The Center Bullseye: Balancing the bounding box on a pin to find its center of mass.',
            failureMode:
                'Combinatorial overhead without batching; vulnerable to single-frame detector dropouts.',
            aiOptimizationFix:
                'ByteTrack tracklet association preserves state even when detections drop for several frames.',
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _getStepsForViolation(widget.violation.id);
    if (_currentStep >= steps.length) {
      _currentStep = 0;
    }
    final step = steps[_currentStep];

    return Row(
      children: [
        // LEFT COLUMN: CODE EDITOR & STEP LIST
        Expanded(
          flex: 11,
          child: Container(
            color: const Color(0xFF1E1E2E), // Dark IDE background
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER / STEP INDICATOR
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.code, color: Colors.cyanAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Naive Brute Force Code (${widget.violation.title})",
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "Step ${_currentStep + 1} of ${steps.length}",
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // CODE BLOCK VIEWER
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181825),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        step.codeSnippet,
                        style: const TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 14,
                          color: Color(0xFFCDD6F4),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // STEP SELECTOR BUTTONS
                Row(
                  children: [
                    IconButton(
                      tooltip: "Previous Step",
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white12,
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white24,
                      ),
                      onPressed: _currentStep > 0
                          ? () => setState(() => _currentStep--)
                          : null,
                      icon: const Icon(Icons.arrow_back, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(steps.length, (idx) {
                            final isSel = idx == _currentStep;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: ChoiceChip(
                                label: Text("${idx + 1}"),
                                selected: isSel,
                                selectedColor: Colors.cyanAccent,
                                labelStyle: TextStyle(
                                  color: isSel ? Colors.black : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                ),
                                backgroundColor: Colors.white10,
                                onSelected: (_) => setState(() => _currentStep = idx),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: "Next Step",
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.white10,
                      ),
                      onPressed: _currentStep < steps.length - 1
                          ? () => setState(() => _currentStep++)
                          : null,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // RIGHT COLUMN: LAYMAN EXPLANATION & MATH BREAKDOWN
        Expanded(
          flex: 10,
          child: Container(
            color: Colors.blueGrey[50],
            padding: const EdgeInsets.all(20),
            child: ListView(
              children: [
                // STEP TITLE
                Text(
                  step.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 12),

                // 1. IN PLAIN ENGLISH (LAYMAN)
                _buildCard(
                  icon: Icons.lightbulb_outline,
                  iconColor: Colors.amber[800]!,
                  title: "In Plain English (Layman Explanation)",
                  content: Text(
                    step.laymanExplanation,
                    style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
                  ),
                  bgColor: Colors.amber[50]!,
                  borderColor: Colors.amber[200]!,
                ),
                const SizedBox(height: 12),

                // 2. THE MATH & EVERYDAY ANALOGY
                _buildCard(
                  icon: Icons.functions,
                  iconColor: Colors.indigo,
                  title: "The Math & Everyday Analogy",
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (step.latexMath != null) ...[
                        MathText(latexCode: step.latexMath!),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        step.mathAnalogy,
                        style: const TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFF334155),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                  bgColor: Colors.indigo[50]!,
                  borderColor: Colors.indigo[200]!,
                ),
                const SizedBox(height: 12),

                // 3. WHY THIS BRUTE FORCE CODE FAILS
                _buildCard(
                  icon: Icons.warning_amber_rounded,
                  iconColor: Colors.red[800]!,
                  title: "Why This Brute Force Code Breaks",
                  content: Text(
                    step.failureMode,
                    style: TextStyle(fontSize: 13, height: 1.4, color: Colors.red[900]),
                  ),
                  bgColor: Colors.red[50]!,
                  borderColor: Colors.red[200]!,
                ),
                const SizedBox(height: 12),

                // 4. HOW MODERN AI FIXES IT
                _buildCard(
                  icon: Icons.check_circle_outline,
                  iconColor: Colors.green[800]!,
                  title: "How Our AI Pipeline Fixes It",
                  content: Text(
                    step.aiOptimizationFix,
                    style: TextStyle(fontSize: 13, height: 1.4, color: Colors.green[900]),
                  ),
                  bgColor: Colors.green[50]!,
                  borderColor: Colors.green[200]!,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget content,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: iconColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          content,
        ],
      ),
    );
  }
}
