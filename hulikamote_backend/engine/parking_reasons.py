"""
parking_reasons.py - why parking is banned in a marked area (the sub-conditions of the Illegal parking rule).

Source: Republic Act No. 4136 (Land Transportation and Traffic Code), Section 46 "Parking prohibited in specified places", items (a) to (h)
(https://lawphil.net/statutes/repacts/ra1964/ra_4136_1964.html). The Section says no driver shall park a vehicle, or permit it to stand,
whether attended or unattended, upon a highway:

  (a) within an intersection                               judged by the rule "Blocking the intersection"
  (b) on a crosswalk                                       judged by the rule "Pedestrian lane blocked"
  (c) within 6 meters of the intersection of curb lines    marked here: "corner"
  (d) within 4 meters of the driveway entrance to a fire station   marked here: "fire_station"
  (e) within 4 meters of a fire hydrant                    marked here: "hydrant"
  (f) in front of a private driveway                       marked here: "driveway"
  (g) on the roadway side of a vehicle stopped or parked at the curb or edge (double parking)   judged by the rule "Double parking"
  (h) where official signs prohibit parking                marked here: "sign"

RA 9514 (Fire Code) Section 8(d) also forbids obstructing designated fire lanes or access to fire hydrants, but it gives no distance and does
not mention parking; the 4 meters come from RA 4136 Section 46(e).

The five "marked here" places are boxes the operator puts on the picture (engine/loading_signs.py): the box IS the banned area, so the operator
sizes it (4 meters is about one car length). The other three have their own rules and their own zones; they are only named here.
"""

REASONS = {
    "sign": {
        "item": "h", "label": "Official no-parking sign", "lines": ("NO", "PARKING"), "mark": "No-parking sign",
    },
    "hydrant": {
        "item": "e", "meters": 4, "label": "Fire hydrant (4 m)", "lines": ("FIRE HYDRANT", "NO PARKING"),
        "mark": "Within 4 m of fire hydrant",
    },
    "fire_station": {
        "item": "d", "meters": 4, "label": "Fire station driveway (4 m)", "lines": ("FIRE STATION", "NO PARKING"),
        "mark": "Within 4 m of fire station driveway",
    },
    "corner": {
        "item": "c", "meters": 6, "label": "Corner, curb lines meet (6 m)", "lines": ("CORNER", "NO PARKING"),
        "mark": "Within 6 m of the corner",
    },
    "driveway": {
        "item": "f", "label": "Private driveway", "lines": ("DRIVEWAY", "NO PARKING"), "mark": "In front of a private driveway",
    },
}
DEFAULT_KIND = "sign"

# Section 46 items that another rule judges: (item, what it says, rule key)
OTHER_RULES = (
    ("a", "within an intersection", "blocking_intersection"),
    ("b", "on a crosswalk", "pedestrian_lane"),
    ("g", "on the roadway side of a vehicle parked at the curb (double parking)", "double_parking"),
)


def kind_of(sign: dict) -> str:
    """The reason of a placed sign; a missing or unknown kind is an official no-parking sign."""
    kind = sign.get("kind") if isinstance(sign, dict) else None
    return kind if kind in REASONS else DEFAULT_KIND


def lines_of(kind) -> tuple:
    """The two lines of text drawn on a sign of this kind."""
    return REASONS.get(kind, REASONS[DEFAULT_KIND])["lines"]


def mark_of(kind) -> str:
    """The short label put on a flagged vehicle's evidence photo."""
    return REASONS.get(kind, REASONS[DEFAULT_KIND])["mark"]
