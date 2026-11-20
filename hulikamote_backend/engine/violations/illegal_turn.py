"""
illegal_turn - turning into a prohibited direction.

What counts as a turn (engine/violations/turn_watch.py): the vehicle is followed picture after picture as ONE vehicle (the trackers hand a
number to another vehicle now and then; the old rule read such a jump as a turn and flagged random vehicles, coming and going). Its way
in is its first stretch of travel in the zone; it is flagged when its heading NOW has swung 45 to 150 degrees from that way in (wider is
a U-turn), toward a banned side or into a banned arrow, for several pictures in a row, with the colours of the same vehicle. A vehicle
that goes straight on is not a turn; a long gentle bend of the road is not a turn.

Four kinds of zone:
  - Whole picture (nothing drawn, no sign): the whole picture is the zone and the enforcer sets which turns are banned at this camera
    (banned_turns: "left" and / or "right", as the driver sees them). Both switched off: the rule does not apply.
  - Overlay sign (engine/overlay_objects.py "no_left_turn" / "no_right_turn"): the operator places a sign on the picture and sizes its
    box; the box is the zone and the sign says which turn is banned in it. Drawn on the evidence photos and the result video only.
  - Road marking (Live Monitor setup): a marked road with a direction. Its area is the zone, the banned sides come from the same
    switches, and only vehicles that came in ALONG the road's arrow count ("approach"): the incoming and the outgoing road each judge
    their own traffic. The zone also carries the turn arrows (turn_arrow_left / turn_arrow_right) that the live picture can show.
  - Drawn zone with arrows: the arrows are the PROHIBITED turn directions (one zone can ban several turns); a vehicle is flagged when its
    heading ends up along one of them and did not point that way on entry.
"""
import math

from engine import loading_signs, overlay_objects
from engine.track_stitcher import compute_signature
from engine.violations.base import Violation
from engine.violations.geometry import TURN_ALIGN_COS, dot, point_in_polygon, unit, vectors_of
from engine.violations.turn_watch import TurnWatch

SIGN_SIDES = {"no_left_turn": "left", "no_right_turn": "right"}     # sign kind -> the turn it bans
DEFAULT_SIGN = "no_left_turn"
APPROACH_COS = math.cos(math.radians(60.0))     # it came in along the road's arrow: within 60 degrees of it
TURN_ARROW_FIELDS = ("turn_arrow_left", "turn_arrow_right")


def sides_of(raw, default=("left",)) -> list[str]:
    """The banned sides of a setting. Missing: the default (left). A list: its "left" / "right" entries; an empty list means "no turn is
    banned" (the rule is off); a list with nothing readable falls back to the default."""
    if raw is None:
        return list(default)
    items = [s for s in raw if s in ("left", "right")] if isinstance(raw, (list, tuple)) else []
    if not items and isinstance(raw, (list, tuple)) and len(raw) == 0:
        return []
    return list(dict.fromkeys(items)) or list(default)


class IllegalTurn(Violation):
    key = "illegal_turn"
    zone_key = "illegal_turn_zones"
    color = (0, 128, 255)
    whole_frame = True

    def whole_frame_zone(self, cfg, polygon, frame_size, flow):
        banned = sides_of(cfg.get("banned_turns"))
        if not banned:                                   # both turns switched off: nothing to judge
            return None
        return {"polygon": polygon, "whole_frame": True, "banned_turns": banned}

    # ── zones ──
    def parse_zone(self, raw):
        if not raw.get("coordinates"):
            return None
        zone = {"polygon": raw["coordinates"]}
        if raw.get("sign") or raw.get("banned_turns") is not None:
            banned = sides_of(raw.get("banned_turns"), default=())
            if not banned:
                return None
            zone["banned_turns"] = banned
            approach = raw.get("approach")
            if isinstance(approach, dict):
                a = unit(float(approach.get("x_dir", 0.0)), float(approach.get("y_dir", 0.0)))
                if a != (0.0, 0.0):
                    zone["approach"] = a
            for field in TURN_ARROW_FIELDS:
                if raw.get(field):
                    zone[field] = raw[field]
            if raw.get("sign"):
                kind = raw.get("sign_kind") if raw.get("sign_kind") in SIGN_SIDES else DEFAULT_SIGN
                zone["sign"] = True                      # drawn as an object, not as a plain outline
                zone["sign_kind"] = kind
                zone.update(overlay_objects.parsed_fields(raw, zone["polygon"], kind))
            return zone
        vectors = vectors_of(raw) or [(0.0, 0.0)]
        zone.update(vector=vectors[0], vectors=vectors)
        return zone

    def from_wizard(self, cfg):
        zones = []
        for z in cfg.get("rois", []):
            if not z.get("polygon"):
                continue
            if z.get("banned_turns") is not None:        # a road of the Live setup (its marking says which sides are banned)
                banned = sides_of(z["banned_turns"], default=())
                if banned:
                    zone = {"coordinates": z["polygon"], "banned_turns": banned}
                    for field in ("approach", *TURN_ARROW_FIELDS):
                        if z.get(field):
                            zone[field] = z[field]
                    zones.append(zone)
            elif z.get("vector"):                        # the arrows are the PROHIBITED turn directions; zones without one are skipped
                zones.append({"coordinates": z["polygon"], "prohibited_vector": z["vector"],
                              **({"prohibited_vectors": z["vectors"]} if z.get("vectors") else {})})
        for sign in loading_signs.usable_signs(cfg.get("signs")):
            kind = sign.get("kind") if sign.get("kind") in SIGN_SIDES else DEFAULT_SIGN
            zones.append({"coordinates": loading_signs.polygon(sign), "banned_turns": [SIGN_SIDES[kind]], "sign": True, "sign_kind": kind,
                          **overlay_objects.zone_fields(sign, kind, cfg)})
        return zones

    # ── judging ──
    def prepare(self, pipe, frame, detections, zones, t):
        """Once per picture: keep it, so the colours of a vehicle can be looked at when its turn is about to be believed."""
        pipe.ledger_manager.turn_frame = frame

    @staticmethod
    def _signature(mgr, ledger):
        frame = getattr(mgr, "turn_frame", None)
        if frame is None or not ledger.history:
            return None
        return compute_signature(frame, ledger.history[-1][3])

    @staticmethod
    def _judge(zone):
        """The test a swing from `entry` to `current` must pass in this zone."""
        banned = zone.get("banned_turns")
        if banned:
            approach = zone.get("approach")
            return lambda entry, current, side: side in banned and (approach is None or dot(entry, approach) >= APPROACH_COS)
        arrows = [unit(*v) for v in (zone.get("vectors") or [zone.get("vector")]) if v]
        return lambda entry, current, side: any(
            a != (0.0, 0.0) and dot(current, a) >= TURN_ALIGN_COS and dot(entry, a) < TURN_ALIGN_COS for a in arrows)

    def evaluate(self, mgr, track_id, zones):
        """Asked for every vehicle on every picture, also for one that was not seen in it: only a NEW picture of the vehicle counts
        (engine/violations/turn_watch.py decides whether it really turned)."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if not ledger.path or not ledger.history or ledger.latest_class == "unknown":
            return False
        t, cx, cy, w = ledger.path[-1]
        sample = (t, cx, cy, w, ledger.history[-1][3][3])
        flagged = False
        for i, zone in enumerate(zones):
            watch = ledger.turn_watch.setdefault((self.key, i), TurnWatch())
            if not point_in_polygon(cx, cy, zone["polygon"]):
                watch.leave(t)
                continue
            turn = watch.update(sample, self._judge(zone), lambda: self._signature(mgr, ledger), ledger.latest_class)
            if turn is not None:
                ledger.cross_points.append((turn.t, turn.point[0], turn.point[1]))
                ledger.violations.add(self.key)
                flagged = True
        return flagged

    # ── drawing ──
    def has_overlay(self, zone):
        return bool(zone.get("sign"))

    def draw_overlay(self, pipe, frame, index, zone):
        if zone.get("sign"):
            overlay_objects.draw_zone_object(frame, zone, zone.get("sign_kind") or DEFAULT_SIGN)

    def draw_zone(self, pipe, frame, index, zone):
        if zone.get("sign"):
            overlay_objects.draw_zone_object(frame, zone, zone.get("sign_kind") or DEFAULT_SIGN)
        else:
            super().draw_zone(pipe, frame, index, zone)
