"""
violations.py - What each of the 25 violations needs from a clip. One place for the clip checklist and the thesis
camera-angle table. The rules themselves live in hulikamote_backend/engine/violations/ (a test keeps the keys in sync);
the numbers quoted here are read from those modules' docstrings and constants.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Need:
    key: str
    title: str
    kind: str          # "zone rule" | "frame check" | "model check"
    film: str          # what a POSITIVE clip shows
    negative: str      # what a clip that must NOT trigger shows
    view: str          # camera view the rule can work with
    setup: str         # what the operator sets in the wizard
    limit: str = ""    # known limit / caveat


NEEDS: list[Need] = [
    Need("counterflow", "Counterflow", "zone rule",
         "A vehicle drives against the legal direction for 2 s or more.",
         "Normal traffic on the same road; a vehicle crossing the road sideways.",
         "Any fixed view where the road direction is clear.",
         "Zones mode: draw the zone and the legal-flow arrow. Auto mode (flow_mode auto): no drawing, but the clip needs "
         "about 60 s of normal traffic first, because the legal direction is learned from it.",
         "Two-way roads are never judged in auto mode (both directions are normal there). Needs a fixed camera."),
    Need("illegal_parking", "Illegal parking", "zone rule",
         "A vehicle stands in the no-parking zone longer than the zone's time limit.",
         "A vehicle that stops in the zone for less than the limit; moving traffic.",
         "Any fixed view where the zone and the whole vehicle are visible.",
         "Draw the zone. Set a short time limit (for example 10 s) so test clips stay short; the default is 180 s.",
         "Judged on speed below 25 px/s, so a camera that shakes can hide a parked car."),
    Need("restricted_lane", "Restricted lane", "zone rule",
         "A vehicle type that is not allowed (for example a car in a motorcycle lane) is inside the lane zone.",
         "An allowed vehicle type in the same lane.",
         "Any fixed view where the lane and the vehicle type are clear.",
         "Draw the lane zone and tick the allowed vehicle classes.",
         "Not in the thesis list; kept as an extra."),
    Need("pedestrian_lane", "Pedestrian lane obstruction", "zone rule",
         "A vehicle stands still on the crosswalk for more than 3 s.",
         "A vehicle that drives across the crosswalk without stopping.",
         "Any fixed view where the crosswalk and the whole vehicle are visible.",
         "Draw the crosswalk zone.", ""),
    Need("illegal_turn", "Illegal turn", "zone rule",
         "A vehicle turns into the forbidden direction (heading swings 45 degrees or more).",
         "Vehicles going straight or turning the allowed way in the same zone.",
         "Elevated view of the junction (the whole turn visible for 2 s or more).",
         "Draw the zone and an arrow for the forbidden direction (an arrow pointing left = no left turn).", ""),
    Need("illegal_u_turn", "Illegal U-turn", "zone rule",
         "A vehicle turns back the way it came (150 degrees or more) and moves sideways at least 0.75 box widths.",
         "A vehicle reversing in a straight line; ordinary turns.",
         "Elevated view of the road section.",
         "Draw the area where U-turns are not allowed.",
         "The legal wording (local no-U-turn rules) still has to be confirmed before it is quoted on a ticket."),
    Need("swerving", "Swerving", "zone rule",
         "A vehicle weaves left-right-left within 6 s (swings of at least half its width).",
         "A single lane change; a steady straight path.",
         "Rear or front view along the road; the vehicle visible for 6 s or more and travelling at least 2 box widths.",
         "Draw the monitored zone (auto flow mode gives it the whole frame).", ""),
    Need("red_light", "Red light running", "zone rule",
         "A vehicle crosses the stop line while the light is red.",
         "A vehicle crossing on green; a vehicle still in the junction when the light turns red.",
         "View of the stop line and of the vehicles' wheels; the light itself visible if the real light is used.",
         "Draw the zone, the stop line and either the light box or the simulated light (red start, red / green / yellow seconds).",
         "An unknown light never produces a ticket."),
    Need("disregarding_signs", "Disregarding traffic signs", "zone rule",
         "Breaking a sign: no entry, no turn, no stopping, vehicle ban or stop sign (one clip per sign type).",
         "Obeying the same sign.",
         "Fixed view of the sign's zone.",
         "One zone per sign with its type (and an arrow or stop line where the type needs one).", ""),
    Need("signal_light", "Signal light violation (experimental)", "zone rule",
         "A turn of 45 degrees or more without a blinking indicator.",
         "Turns with a blinking indicator.",
         "Close front or rear view where the indicators at the left and right edges are visible.",
         "Draw the zone.",
         "EXPERIMENTAL: it can over-flag (hand signals are lawful, motorcycles are exempt), so it is not a headline result."),
    Need("blocking_intersection", "Blocking the intersection", "zone rule",
         "A vehicle stands still inside the junction box for more than 5 s.",
         "A vehicle passing through, or waiting before the box.",
         "Elevated view of the whole junction box.",
         "Draw the junction box.",
         "The legal basis (local anti-obstruction rules) still has to be confirmed."),
    Need("crossing_solid_line", "Crossing a solid line", "zone rule",
         "A vehicle crosses the drawn solid line (it ends up clearly past it).",
         "A vehicle wobbling on its own side of the line.",
         "Fixed view where the line and the wheels are visible.",
         "Draw the road section and the line.",
         "The legal basis (no-overtaking rules) still has to be confirmed."),
    Need("illegal_loading", "Illegal loading / unloading", "zone rule",
         "A bus, jeepney, tricycle or truck stands still in the no-loading zone for more than 8 s.",
         "A bus passing through, a short stop, a car left standing (that is illegal parking), a vehicle outside the zone.",
         "Fixed view where the zone and the whole vehicle are visible.",
         "Draw the no-loading area; set the time limit and the vehicle types that may not load there.",
         "Needs the vehicle class to settle (5+ looks). A jeepney is detected as a bus. The legal basis (MMDA / LGU "
         "loading rules) still has to be confirmed for Zamboanga City."),
    Need("truck_ban", "Truck ban / truck lane", "zone rule",
         "A truck stays inside the banned road or lane zone for 1 s or more.",
         "Cars, buses and motorcycles in the same zone; a truck outside the zone.",
         "Fixed view where the zone and the vehicle type can be told apart.",
         "Draw the banned road or lane; the banned types default to truck.",
         "No clock: for a ban that applies only at certain hours, film those hours. The stock detector may call a "
         "pickup or van a car. The legal basis still has to be confirmed."),
    Need("tricycle_on_highway", "Tricycle on a national highway", "zone rule",
         "A tricycle stays inside the highway zone for 1 s or more.",
         "Motorcycles, cars and buses on the same highway; a tricycle on a street outside the zone.",
         "Fixed view of a road where tricycles are banned (a national highway the city has not exempted).",
         "Nothing has to be drawn: ticking the rule says the whole view is a road where tricycles are banned. Draw a zone only to limit the rule to the banned part (for example when the view also shows a side street or an exempted section). The banned type defaults to tricycle.",
         "Needs a detector that knows \"tricycle\" (the stock COCO model does not). Based on DILG MC 2020-036 / 2023-195. "
         "The video cannot show that a road is a national highway, or that the city exempts a section of it, so the operator states it for each camera "
         "(DPWH national road list, the city's Tricycle Route Plan and ordinance). Confirm the local rule for Zamboanga City."),
    Need("sidewalk_driving", "Driving on the sidewalk", "zone rule",
         "A moving vehicle stays inside the sidewalk or bike-lane zone for 1.5 s or more.",
         "A parked vehicle in the zone (that is illegal parking); a vehicle crossing to a driveway in under 1.5 s.",
         "Fixed view where the sidewalk edge is clear.",
         "Draw the sidewalk or bike lane.",
         "No legal source was found yet: confirm the local ordinance before quoting it."),
    Need("double_parking", "Double parking", "zone rule",
         "A vehicle stands in the travel lane beside another stopped vehicle (there first) for more than 8 s while a "
         "third vehicle drives through the zone.",
         "A queue at a red light (nothing moves past); a vehicle stopped alone; a vehicle queued behind another.",
         "Elevated or side view where the lane, the kerb vehicle and the passing traffic are all visible.",
         "Draw the one travel lane next to the kerb, not the whole road.",
         "Needs moving traffic inside the zone; the direction of that traffic decides what \"beside\" means. "
         "Experimental until it has run on real footage."),
    Need("overloading", "Overloading (too many riders)", "frame check",
         "A motorcycle carries more riders than allowed (default 2) in most looks.",
         "Motorcycles with one or two riders; pedestrians walking past a motorcycle.",
         "Front, rear or side view with every rider's body visible and the motorcycle large enough to count heads.",
         "Set the maximum riders (default 2).",
         "Riders are counted from person boxes; heavy overlap hides riders."),
    Need("pickup_passengers", "Passengers in the back of a pickup / truck", "frame check",
         "A moving pickup or truck has people in its open back (bed).",
         "A pickup with an empty bed; a pedestrian walking beside it; a parked pickup being loaded.",
         "Front, rear or side view at a moderate height, so the bed and the cab are apart in the picture.",
         "Set how many people are tolerated (default 0).",
         "A straight top-down view cannot tell the bed from the cab. Pickups are usually detected as 'truck'. "
         "Legal basis: RA 4136 Sections 32 and 51 (the fine amounts are unconfirmed)."),
    Need("riding_outside_vehicle", "Riding on the roof or hanging off a vehicle", "frame check",
         "People on the roof of, or hanging off, a moving bus, jeepney or truck.",
         "People boarding a stopped bus; pedestrians beside a moving one.",
         "The whole side or the rear of the vehicle at a moderate height.",
         "None.",
         "Someone on the rear step seen from straight behind is hidden by the vehicle."),
    Need("no_plate", "No plate number", "model check",
         "A vehicle with no plate on it (rear view for motorcycles, which carry a rear plate only).",
         "Vehicles with a plate; a motorcycle seen from the front.",
         "Vehicles at least 60 px wide in the picture, plate side facing the camera.",
         "None. Decided when the vehicle leaves the picture or the video ends.",
         "A plate found at any fair look cancels the suspicion."),
    Need("no_helmet", "No helmet", "model check",
         "A motorcycle rider without a helmet (or a helmet hung on the arm).",
         "Riders with helmets; pedestrians.",
         "Front or rear view of the motorcycle with the riders' heads visible.",
         "None.",
         "Needs the helmet model; the training data is not from Zamboanga."),
    Need("no_seatbelt", "No seatbelt", "model check",
         "A car driver without a seatbelt, seen through a clear windshield.",
         "Belted drivers; cars with tinted windshields (judged as 'no look' by design).",
         "Front view of the car, close enough to see through the windshield, daylight.",
         "None.",
         "Tinted windows are skipped on purpose (safety gate); there is no tinted-window training data yet."),
    Need("distracted_driving", "Phone use while driving", "model check",
         "A driver holding a phone to the ear or at the wheel.",
         "Drivers with empty hands.",
         "Front view through a clear windshield, daylight.",
         "None.",
         "Not in the thesis list; kept as an extra."),
    Need("missing_side_mirror", "Missing side mirror", "model check",
         "A motorcycle with fewer than two side mirrors, seen from the front or the rear.",
         "Motorcycles with both mirrors; any motorcycle seen from the side (one mirror is always hidden).",
         "Front or rear view of the motorcycle with the mirrors large enough to see.",
         "None.",
         "Cannot work yet: the cabin model has no motorcycle-mirror training data (see datasets/CATALOG.md)."),
]

KEYS = [n.key for n in NEEDS]
BY_KEY = {n.key: n for n in NEEDS}

# What every clip should meet, whatever the violation (a working spec: tighten it with the benchmark results)
CAMERA_SPEC = [
    "Fixed camera: no panning, zooming or hand-held footage (the zones and the learned flow assume one fixed view).",
    "Mounted above the road (about 3 to 8 m) looking down at 15 to 45 degrees, not straight down.",
    "Vehicles at least 120 px wide in the picture for plate, helmet and seatbelt checks (the plate check ignores vehicles under 60 px).",
    "At least 720p and 15 fps; 25-30 fps is better. Daylight for the first test set; evening and night as a separate set.",
    "Each vehicle visible for at least 3 s (the rules need several position updates; swerving needs 6 s).",
    "No heavy rain, lens dirt or strong backlight in the main test set.",
]
