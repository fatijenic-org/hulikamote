"""
engine.violations - one module per violation (see base.py for the shape and the three families).

ALL is the order violations are evaluated and drawn in. REGISTRY looks one up by its key.
"""
from engine.violations.base import VEHICLE_CLASSES, Violation  # noqa: F401
from engine.violations.blocking_intersection import BlockingIntersection
from engine.violations.counterflow import Counterflow
from engine.violations.crossing_solid_line import CrossingSolidLine
from engine.violations.disregarding_signs import DisregardingSigns
from engine.violations.distracted_driving import DistractedDriving
from engine.violations.double_parking import DoubleParking
from engine.violations.illegal_loading import IllegalLoading
from engine.violations.illegal_parking import IllegalParking
from engine.violations.illegal_u_turn import IllegalUTurn
from engine.violations.illegal_turn import IllegalTurn
from engine.violations.missing_side_mirror import MissingSideMirror
from engine.violations.no_helmet import NoHelmet
from engine.violations.no_plate import NoPlate
from engine.violations.no_seatbelt import NoSeatbelt
from engine.violations.overloading import Overloading
from engine.violations.overtaking_on_right import OvertakingOnRight
from engine.violations.pedestrian_lane import PedestrianLane
from engine.violations.passenger_outside import PassengerOutside
from engine.violations.red_light import RedLight
from engine.violations.restricted_lane import RestrictedLane
from engine.violations.sidewalk_driving import SidewalkDriving
from engine.violations.signal_light import SignalLight
from engine.violations.swerving import Swerving
from engine.violations.tricycle_on_highway import TricycleOnHighway
from engine.violations.truck_ban import TruckBan

ALL: list[Violation] = [
    # zone rules (judged from the path inside drawn zones)
    Counterflow(), IllegalParking(), RestrictedLane(), PedestrianLane(), IllegalTurn(),
    Swerving(), RedLight(), DisregardingSigns(), SignalLight(),
    IllegalUTurn(), BlockingIntersection(), CrossingSolidLine(),
    # added after the first 20: Philippine road rules, all judged from the path inside a drawn zone
    IllegalLoading(), TruckBan(), TricycleOnHighway(), SidewalkDriving(), DoubleParking(),
    OvertakingOnRight(),
    # frame checks (what is on screen now)
    Overloading(), PassengerOutside(),
    # model checks (a specialist model's look at the vehicle)
    NoPlate(), NoHelmet(), NoSeatbelt(), DistractedDriving(), MissingSideMirror(),
]

REGISTRY: dict[str, Violation] = {v.key: v for v in ALL}

# Keys of rules that were merged into another one: old saved configs still load (2026-11-17: three passenger rules -> one)
LEGACY_KEYS: dict[str, str] = {"pickup_passengers": "passenger_outside", "riding_outside_vehicle": "passenger_outside",
                               "kuliglig_passenger": "passenger_outside"}


def current_keys(keys) -> list[str]:
    """Violation keys with merged ones renamed, in order, without duplicates."""
    out = []
    for k in keys or []:
        k = LEGACY_KEYS.get(k, k)
        if k not in out:
            out.append(k)
    return out
ZONE_VIOLATIONS: list[Violation] = [v for v in ALL if v.zone_key]

# violation key -> ROI list name in camera_config, and the BGR colour its zones are drawn in
ZONE_RULES: dict[str, str] = {v.key: v.zone_key for v in ZONE_VIOLATIONS}
ZONE_COLORS: dict[str, tuple] = {v.key: v.color for v in ZONE_VIOLATIONS}
# Zone fields that are points (scaled with the polygon to the processed frame size)
ZONE_POINT_FIELDS = ("stop_line", "light_box", "sign_points")
