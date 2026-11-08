# Road line finder (no model): how it works, how to try it, what it cannot do

Finds the painted **crosswalk**, **stop line** and **solid or dashed lane lines** of a fixed camera, then suggests zones for
`pedestrian_lane`, `red_light` and `crossing_solid_line`. Code: `hulikamote_backend/engine/road_lines.py`. Tool: `tools/find_road_lines.py`.
Wizard: the "Find lines from the video" button in the Forensic Analyzer's zone step. Tests: `hulikamote_backend/tests/engine/test_road_lines.py`.

## The steps and the studies behind them

| Step | What it does | Based on |
|---|---|---|
| 1. Read | One ffmpeg pass: ~30 colour frames for the empty road, every frame (8 per second) as a small grey picture for motion. | - |
| 2. Steady | Hand-held shake is removed by matching features to a middle frame (RANSAC), so only real movers move. The empty road is the median of the steadied frames. | standard video stabilisation |
| 3. Road direction | Moving points are tracked; each is a short line, and for vehicles all lines pass through one **vanishing point**. It is found by voting, helped by the long straight edges of the street (curbs, building lines). | [Dubska et al., BMVC 2014](https://bmva-archive.org.uk/bmvc/2014/files/paper013.pdf) (read); T-ITS 2014 version [listing](https://fit.vut.cz/research/publication/11455) (not read) |
| 4. Top view | With the vanishing point the road is redrawn as seen from above (camera assumed level, focal length guessed as one picture width). Lane lines become vertical, crosswalk stripes become equal vertical bars. | IPM; [Gavrilovic et al., ISPRS 2010](https://www.isprs.org/proceedings/XXXVIII/part3/a/pdf/43_XXXVIII-part3A.pdf) (read) |
| 5. Road region | Where vehicle-sized things moved is "road"; paint is only looked for there. | motion / activity-map lane papers, e.g. [Lane Discovery in Traffic Video](https://openjournals.uwaterloo.ca/index.php/vsl/article/view/125) (listing only) |
| 6. Marks | Paint = thin and bright (top-hat), faint regions only count if part of them clearly stands out. Crosswalk = a row of at least 4 evenly spaced bars (extended over faint ones). Stop line = long thin horizontal line. Lane line = long thin vertical line, solid or dashed by its gaps. | simple rules, all thresholds named at the top of the file |
| 7. Map back | Everything is turned back into the video's own pixels, and into the wizard's zone format (1920x1080 reference space). | - |

## Try it

```bash
cd hulikamote_backend
venv\Scripts\python.exe ..\tools\find_road_lines.py "C:/path/to/clip.mp4" --out ..\road_lines_out
```

Open `<clip>_lines.png` (the empty road with the findings), then `<clip>_topdown.png` (the same road from above with the paint picked out).
In the top view a good result looks like straight vertical lane lines and evenly spaced bars inside a green box.

## What to expect (checked on your own clips on 2026-11-06, read by eye)

- Crosswalks were outlined in the right place on all four street-level clips that have one ("Pedestrian lane", "No left turn", "No parking", "One way & No entry"), usually both the near and the far crosswalk. Small false boxes on a pavement strip appear sometimes.
- Roads with no markings (two elevated clips of a parked-vehicle street) returned nothing, which is correct.
- A wide intersection seen from a pole camera ("trafficlight") was refused: the paint could not be told from the concrete.
- Stop lines and solid lane lines are the weak part: few were found, and some are curbs or wall bases. Treat them as hints.
- Time: about the length of the clip on a 4K file (37 s for a 34 s clip here), a few seconds for 720p.

## Limits

- Needs a **fixed camera** (small shake is fine; panning is refused) and **traffic passing**: the road direction comes from vehicle movement. Too little movement gives "not enough traffic movement".
- Level camera and flat road are assumed; a camera that rolls sideways, a hill or a curve lowers accuracy.
- Faded paint, rain, glare, night and heavy shadows lower accuracy. Parked vehicles stay in the "empty road".
- Poles and other upright things smear in the top view; lines that lean are ignored on purpose.
- Everything is a suggestion for the operator to check on the picture; delete the wrong zones and draw by hand.

## The Live Monitor learns the road by itself (`engine/live_calibrator.py`)

For the live demo nobody draws anything. When a camera connects, the Live Monitor watches it for about 40 seconds, reads the paint with the finder
above in a background thread (the stream never waits), and uses what it found for the rules that need a zone. The Forensic wizard is only a test harness.

| What | Behaviour |
|---|---|
| Learning | "Learning the road 23/40 s" in the Live Monitor chip, then "Reading the road paint...". It needs what the finder needs: a fixed camera, traffic passing, daylight. A refusal tries again (3 windows in a row), then shows the reason and leaves the live view running with the rules that need no zone. |
| Crosswalk -> `pedestrian_lane` | A rule, for the selected violation, when no zone was drawn. Only crosswalks with 5 or more stripes (or 4 very clear ones) that **span the road** (at least 40% of the top view's width) are believed. Measured on the user's clips: real crosswalks 59-95%, a tiled pavement strip that looked like one 32%. |
| Stop line -> `red_light`, solid line -> `crossing_solid_line` | **Hints only**, drawn in the live picture ("hint only") and counted in the status, never turned into rules: on two of four street clips the "solid lines" were curbs. Set `"learned_lines_as_rules": true` in `camera_config.json` to make them rules (labelled best effort); it takes effect when the camera next connects or on Re-learn. |
| Drawn zones | A zone drawn in the wizard ("Use for Live Monitor") always wins over a learned one for the same rule. |
| Remembered | Per camera (the saved profile's name, else the masked address) in `camera_config.json` under `learned_road`. On connect the saved zones are used at once. The live picture is compared with the saved view (a 64-bit fingerprint) for ~5 s on every connect and every 5 minutes; a clearly different view throws the zones away and learns again. |
| Actions | Live Monitor chip menu: **Re-learn the road**, **Forget what was learned** (`POST /settings/video/road/relearn`, `/forget`). Status: `GET /settings/video/status` (field `road`) and every feed message (`road`, `road_zones`). |
| Resolution and pace | The learner watches the camera itself: the reader thread hands it every picture (`CameraSource.tap`), at the camera's own size, so it keeps its pace when the detector is slow (under load the processing loop only saw about 2 pictures a second and learning took 78 s instead of 44 s). Native 4K read the real crosswalk best; at 720p the pavement-strip false box appears more often. |

Never from a guess: a refused, failed or unclear read installs nothing, and no ticket can come from a zone that was not learned. A tiled pavement strip beside the
road can still pass for a crosswalk (see the finder's limits above); a crosswalk cropped by the picture's edge is refused rather than guessed.
