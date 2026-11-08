import '../domain/models/violation_visualizer_model.dart';

const List<ViolationVisualizerModel> kViolationVisualizerList = [
  // MOTORCYCLE
  ViolationVisualizerModel(
    id: 'm1',
    title: 'Counterflow',
    category: 'Motorcycle / Cars',
    definition: 'Vehicle traveling against the legal direction of traffic.',
    bruteForce: 'Brute Force Method: Scan every pixel of every frame. Compare pixel clusters to known vehicle templates. Manually check if it moves from right-to-left on a left-to-right road. Requires hardcoded road direction per camera.',
    optimizedLogic: '1. Detect vehicle bounding box (YOLO).\n2. Track vehicle across frames (assign ID).\n3. Compute velocity vector from centroid displacement.\n4. Compare velocity vector against the road\'s reference flow vector.\n5. If angle opposes legal flow, flag as counterflow.',
    mathLatex: r'''\begin{aligned}
& \text{Velocity } V = (x_{t+1} - x_t, y_{t+1} - y_t) \\
& \text{Reference } R = (r_x, r_y) \\
& \text{Dot Product } D = V \cdot R \\
& \theta = \arccos\left(\frac{D}{|V| \times |R|}\right) \\
& \text{If } \theta > 90^\circ \rightarrow \text{VIOLATION}
\end{aligned}''',
    tools: ['YOLOv8', 'ByteTrack', 'Vector Math'],
    visualizerType: VisualizerType.counterflow,
  ),
  ViolationVisualizerModel(
    id: 'm2',
    title: 'Illegal Parking',
    category: 'Motorcycle / Cars',
    definition: 'Vehicle stopped or parked in a restricted zone (e.g., No Parking ROI).',
    bruteForce: 'Brute Force Method: Check every frame if a vehicle is present. If it\'s stationary for X seconds, flag it. Prone to false positives in normal traffic stops.',
    optimizedLogic: '1. Detect vehicle (YOLO).\n2. Track across frames (ByteTrack).\n3. Measure stationarity (displacement < 5px for N frames).\n4. Check if bounding box overlaps a pre-defined no-parking polygon.\n5. If stationary inside zone > Threshold → VIOLATION.',
    mathLatex: r'''\begin{aligned}
& \text{Displacement } d = \sqrt{\Delta x^2 + \Delta y^2} \\
& \text{Stationary: } d < 5\text{px} \text{ for } N \text{ frames} \\
& \text{Zone Check (PNPoly):} \\
& \text{Count ray intersections } K \text{ with polygon} \\
& \text{If } K \pmod 2 \neq 0 \rightarrow \text{Inside Zone}
\end{aligned}''',
    tools: ['YOLOv8', 'ByteTrack', 'PNPoly Ray-Casting'],
    visualizerType: VisualizerType.zoneOverlap,
  ),
  ViolationVisualizerModel(
    id: 'm3',
    title: 'Illegal Turn',
    category: 'Motorcycle / Cars',
    definition: 'Sustained movement vector crosses an invisible prohibited ROI line at an intersection.',
    bruteForce: 'Brute Force Method: Track position across all frames. Manually define rigid entry and exit grid zones. Check if vehicle hits entry gate and then exit gate.',
    optimizedLogic: '1. Detect entry vector before an intersection zone.\n2. Track through the intersection.\n3. Detect exit vector.\n4. Compute turn angle using arctan2.\n5. Compare against prohibited turns for that zone.',
    mathLatex: r'''\begin{aligned}
& V_{\text{entry}} = C_{t_{\text{entry}}} - C_{t_{\text{entry}} - n} \\
& V_{\text{exit}}  = C_{t_{\text{exit}} + n} - C_{t_{\text{exit}}} \\
& \theta_{\text{turn}} = \text{atan2}(V_{\text{exit\_y}}, V_{\text{exit\_x}}) - \text{atan2}(V_{\text{entry\_y}}, V_{\text{entry\_x}}) \\
& \text{Check against Prohibited Angle Rules}
\end{aligned}''',
    tools: ['YOLOv8', 'ByteTrack', 'Trigonometry'],
    visualizerType: VisualizerType.illegalTurn,
  ),
  ViolationVisualizerModel(
    id: 'm4',
    title: 'No Helmet',
    category: 'Motorcycle',
    definition: 'Motorcycle rider (driver or passenger) not wearing a valid helmet.',
    bruteForce: 'Brute Force Method: Crop rider\'s head region. Compare pixel color/texture to known helmet colors.',
    optimizedLogic: '1. YOLO finds motorcycle. Track it.\n2. Sub-crop motorcycle box.\n3. Identify Rider & Helmet classes within sub-crop.\n4. Apply Geometric IoU Rule: Helmet center must be in top 20% of Rider box.\n5. Filter outliers with Temporal Voting Buffer.',
    mathLatex: r'''\begin{aligned}
& \text{Geometric IoU Constraint:} \\
& y_{\text{helmet\_center}} \le y_{\text{rider\_top}} + 0.20 \times H_{\text{rider}} \\
& \text{If Valid Helmet Not Found} \rightarrow \text{VIOLATION}
\end{aligned}''',
    tools: ['YOLOv8 (Composite Classes)', 'Geometric IoU', 'Temporal Buffer'],
    visualizerType: VisualizerType.noHelmet,
  ),
  ViolationVisualizerModel(
    id: 'm5',
    title: 'Missing Side Mirror',
    category: 'Motorcycle',
    definition: 'Motorcycle is missing one or both side mirrors.',
    bruteForce: 'Brute Force Method: Use edge detection on motorcycle. Compare resulting shape to template motorcycles with mirrors.',
    optimizedLogic: '1. Detect motorcycle bounding box.\n2. Sub-crop frame to motorcycle area.\n3. Run secondary YOLO specialized for side mirrors.\n4. If Count(Mirror) < 2 on the motorcycle frame → VIOLATION.',
    mathLatex: r'''\begin{aligned}
& Z_{\text{moto}} = \text{SubCrop}(B_{\text{moto}}) \\
& N_{\text{mirrors}} = \sum (\text{Detect}(Z_{\text{moto}}, \text{"mirror"})) \\
& \text{If } N_{\text{mirrors}} < 2 \rightarrow \text{VIOLATION}
\end{aligned}''',
    tools: ['YOLOv8', 'Sub-Cropping', 'Counting Logic'],
    visualizerType: VisualizerType.missingSideMirror,
  ),
  ViolationVisualizerModel(
    id: 'm6',
    title: 'Overloading',
    category: 'Motorcycle',
    definition: 'More than 2 riders on a single motorcycle.',
    bruteForce: 'Brute Force Method: Count total faces/helmets in the entire frame. If > 2, flag overloading (susceptible to background crowds).',
    optimizedLogic: '1. Detect motorcycle bounding box.\n2. Detect person bounding boxes with "rider" (sitting) vs "pedestrian" posture.\n3. Apply Strict 80% Overlap Rule for persons inside the motorcycle box.\n4. If Count(Valid Rider) > 2 → VIOLATION.',
    mathLatex: r'''\begin{aligned}
& \text{Overlap} = \frac{\text{Area}(B_{person} \cap B_{moto})}{\text{Area}(B_{person})} \\
& N = \sum \mathbb{I}(\text{Overlap} > 0.8 \land \text{Class} == \text{"rider"}) \\
& \text{If } N > 2 \rightarrow \text{VIOLATION}
\end{aligned}''',
    tools: ['YOLOv8 (Posture)', 'Overlap Math', 'ByteTrack'],
    visualizerType: VisualizerType.overloading,
  ),
  // CAR
  ViolationVisualizerModel(
    id: 'c1',
    title: 'No Plate Number',
    category: 'Cars / Motorcycle',
    definition: 'Vehicle has no visible license plate or it is entirely unreadable.',
    bruteForce: 'Brute Force Method: Apply edge detection to the whole vehicle. Check if any rectangle matches a plate aspect ratio.',
    optimizedLogic: '1. Detect vehicle bounding box.\n2. Sub-crop the bumper/rear region of the vehicle.\n3. Run Plate Presence Verification (YOLO).\n4. If Count(Plate) == 0 inside box → OCR skipped, flag VIOLATION.',
    mathLatex: r'''\begin{aligned}
& \text{Crop Region } Z_{rear} = [x, y+0.5H, w, 0.5H] \\
& N_{plates} = \text{YOLO}_{\text{plate}}(Z_{rear}) \\
& \text{If } N_{plates} == 0 \rightarrow \text{VIOLATION}
\end{aligned}''',
    tools: ['YOLOv8 (Plate)', 'Sub-Cropping', 'EasyOCR'],
    visualizerType: VisualizerType.staticCrop,
  ),
  ViolationVisualizerModel(
    id: 'c2',
    title: 'Red Light Running',
    category: 'Cars / Motorcycle',
    definition: 'Vehicle crosses the stop line and enters the intersection while the traffic light is red.',
    bruteForce: 'Brute Force Method: Monitor red pixels in the traffic light bounding box. If a car enters the intersection, flag it.',
    optimizedLogic: '1. Dual-ROI Calibration: Vision reads physical traffic light state.\n2. Stop Line ROI is monitored.\n3. Track vehicle centroid.\n4. If Light=RED AND vector crosses through Stop Line ROI → VIOLATION (with Grace Period checks).',
    mathLatex: r'''\begin{aligned}
& L_{\text{state}} = \text{YOLO}_{\text{light\_roi}} \\
& \text{Crossed} = C_t \in Z_{\text{stop\_line}} \\
& \text{If } (L_{\text{state}} == \text{Red}) \wedge \text{Crossed} \rightarrow \text{VIOLATION}
\end{aligned}''',
    tools: ['Dual-ROI Vision', 'ByteTrack', 'Boolean Gating'],
    visualizerType: VisualizerType.redLightRunning,
  ),
  ViolationVisualizerModel(
    id: 'c3',
    title: 'No Seatbelt',
    category: 'Cars',
    definition: 'Driver or front passenger is not wearing a seatbelt.',
    bruteForce: 'Brute Force Method: Look for a diagonal black line across the person. Fails on black shirts or dark interiors.',
    optimizedLogic: '1. Detect vehicle & windshield area.\n2. Safety Override Gate: Check if windshield is `clear_window` or `tinted_window`.\n3. If tinted, abort. If clear, check for `seatbelt` crossing driver region.\n4. If seatbelt not found → VIOLATION.',
    mathLatex: r'''\begin{aligned}
& \text{If } Class_{\text{window}} == \text{"tinted\_window"} \rightarrow \text{Abort Check} \\
& \text{Else } \rightarrow \text{Run Cabin Specialist} \\
& \text{If } P(\text{seatbelt}) < \text{threshold} \rightarrow \text{VIOLATION}
\end{aligned}''',
    tools: ['YOLOv8', 'Safety Override Gates', 'Cabin Specialist'],
    visualizerType: VisualizerType.noSeatbelt,
  ),
  ViolationVisualizerModel(
    id: 'c4',
    title: 'Crosswalk Obstruction',
    category: 'Cars / Motorcycle',
    definition: 'Vehicle stops on top of the pedestrian lane (zebra crossing) during a red light.',
    bruteForce: 'Brute Force Method: Draw a fixed box over the lane. If any car pixels enter it, trigger violation. Fails because cars legally pass through when green.',
    optimizedLogic: '1. Define Pedestrian Crosswalk ROI.\n2. Track vehicle Bounding Box.\n3. If vehicle speed hits 0 (stopped) inside ROI.\n4. Occurs while the vehicle traffic light is RED → VIOLATION.',
    mathLatex: r'''\begin{aligned}
& \text{Overlap} = \frac{\text{Area}(B_{car} \cap Z_{ped})}{\text{Area}(B_{car})} \\
& V = \frac{dy}{dt} \\
& \text{If } (\text{Overlap} > 0.2) \wedge (V \approx 0) \wedge (\text{Light} == \text{Red}) \rightarrow \text{VIOLATION}
\end{aligned}''',
    tools: ['YOLOv8', 'Velocity Filter', 'Conjunction Logic'],
    visualizerType: VisualizerType.pedestrianObstruction,
  ),
  ViolationVisualizerModel(
    id: 'c5',
    title: 'Distracted Driving (Mobile Phone)',
    category: 'Cars',
    definition: 'Driver is using a mobile phone while operating the vehicle.',
    bruteForce: 'Brute Force Method: Scan entire frame for phone-shaped rectangles. High false-positive rate with dashboard objects.',
    optimizedLogic: '1. Detect vehicle & clear windshield.\n2. Inject crop into Cabin Specialist.\n3. Look for `driver_phone` class specifically near the head/hand region.\n4. If detected → VIOLATION.',
    mathLatex: r'''\begin{aligned}
& \text{If } Class_{\text{window}} == \text{"clear\_window"} \\
& Z_{cabin} = \text{SubCrop}(B_{\text{vehicle}}) \\
& \text{If } Class_{\text{driver\_phone}} \in Z_{cabin} \rightarrow \text{VIOLATION}
\end{aligned}''',
    tools: ['YOLOv8 (Cabin Specialist)', 'Sub-Cropping', 'Contextual Classes'],
    visualizerType: VisualizerType.distractedDriving,
  ),
  // EXTENDED
  ViolationVisualizerModel(
    id: 'e1',
    title: 'Swerving',
    category: 'Extended',
    definition: 'Sudden, erratic lateral movement across lanes without signaling.',
    bruteForce: 'Brute Force Method: Compare centroid x-position per frame. If it changes suddenly, flag.',
    optimizedLogic: '1. Track vehicle centroid (ByteTrack) over short frame window.\n2. Compute lateral displacement between frames.\n3. Calculate lateral jerk (rate of change of acceleration).\n4. If jerk > threshold repeatedly → VIOLATION.',
    mathLatex: r'''\begin{aligned}
& V_{lat} = \frac{dx}{dt} \\
& J_{lat} = \frac{d^3x}{dt^3} \approx \frac{\Delta a_{lat}}{\Delta t} \\
& \text{If } (|J_{lat}| > J_{\text{threshold}}) \rightarrow \text{VIOLATION}
\end{aligned}''',
    tools: ['ByteTrack', 'Kinematics', 'Jerk Calculation'],
    visualizerType: VisualizerType.swerving,
  ),
  ViolationVisualizerModel(
    id: 'e2',
    title: 'Over-speeding',
    category: 'Extended',
    definition: 'Vehicle exceeding the designated speed limit of the road.',
    bruteForce: 'Brute Force Method: Use radar guns manually. Software cannot easily guess 3D speed from a 2D image.',
    optimizedLogic: '1. Apply Perspective Transformation math to map 2D camera pixels to a 3D real-world top-down grid.\n2. Calculate pixels traveled per second by DeepSORT centroid.\n3. Convert to real-world meters/sec, then to KPH.\n4. If KPH > Speed Limit → VIOLATION.',
    mathLatex: r'''\begin{aligned}
& P_{birdseye} = H \times P_{camera} \\
& \text{Dist} = || P_{birdseye}(t_2) - P_{birdseye}(t_1) || \\
& \text{Speed (KPH)} = \left(\frac{\text{Dist}}{t_2 - t_1}\right) \times 3.6 \\
& \text{If } \text{Speed} > \text{Limit} \rightarrow \text{VIOLATION}
\end{aligned}''',
    tools: ['Perspective Transformation', 'DeepSORT Vector', 'Homography Matrix'],
    visualizerType: VisualizerType.overspeeding,
  ),
];
