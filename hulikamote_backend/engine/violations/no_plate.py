"""
no_plate - a vehicle with no licence plate.

Heuristic: judged over the WHOLE track, never on a short run of misses.
  - A look only counts when it was fair: the vehicle class is settled, the box is at least 60 px
    wide, and a motorcycle shows its REAR (PH motorcycles carry a rear plate only; "rear visible" =
    moving up the image, away from a camera that faces the traffic).
  - After 6 fair looks with no plate at all the suspicion is only PENDING ("no plate seen yet");
    a plate found at any later look clears it.
  - The ticket is decided when the vehicle leaves or the video ends (decide_end): no plate in any
    fair look -> no_plate. Evidence photos of a cleared suspicion are deleted by the ledger.

"No plate" is not "plate not read". Every ticket (of any violation) carries plate_status, from the plate model's
confidence over ALL the looks at the vehicle (plate_evidence gives the numbers):
    read         a plate was seen and its text was read (set after the OCR, routers/forensic.py)
    not_read     a plate was SEEN (one look at 0.5 or more, or weaker looks that add up to 0.8) but no text was read
    unclear      the model fired weakly once or twice: a plate may be there; not a "no plate" and not a sure plate
    no_plate     6 or more fair looks and the model never fired: the vehicle shows no plate
    not_checked  too few fair looks to say anything (vehicle too small, too short on screen, motorcycle seen from the front)
The thresholds 0.5 / 0.8 are first values: measure them with training_lab/scripts/plate_status_eval.py.
"""
import math

from engine import marks
from engine.violations.base import Violation

NO_PLATE_MIN_CHECKS = 6     # fair looks needed (~3 s with SPECIALIST_INTERVAL=5 at 10 inferences/s)
NO_PLATE_MIN_WIDTH = 60     # px; a smaller vehicle is too far away for its plate to be found
PLATE_SURE_CONF = 0.5       # one look this confident: a plate was seen
PLATE_SEEN_SUM = 0.8        # ...or weaker looks whose confidences add up to this (for example four looks at 0.2)


def plate_evidence(ledger) -> dict:
    """The numbers behind plate_status: fair looks, looks that found a plate, and the plate model's confidence in them."""
    confs = list(getattr(ledger, "plate_confs", []))
    return {"fair_looks": ledger.plate_checks, "fair_hits": ledger.plate_hits, "plate_looks": len(confs),
            "best_conf": round(max(confs), 3) if confs else 0.0, "conf_sum": round(sum(confs), 3)}


def plate_status(ledger) -> str:
    """no_plate | not_read | unclear | not_checked for a vehicle whose plate text is not known (yet). See the module text."""
    confs = list(getattr(ledger, "plate_confs", []))
    if confs:
        seen = max(confs) >= PLATE_SURE_CONF or sum(confs) >= PLATE_SEEN_SUM
        return "not_read" if seen else "unclear"
    return "no_plate" if ledger.plate_checks >= NO_PLATE_MIN_CHECKS else "not_checked"


class NoPlate(Violation):
    key = "no_plate"
    job = "plate"

    def record_look(self, mgr, track_id: int, plate_found: bool) -> bool:
        """Record one plate-detector look at a vehicle. Returns True while the suspicion is pending."""
        if track_id not in mgr.ledgers:
            return False
        ledger = mgr.ledgers[track_id]
        vclass = ledger.vclass
        if vclass in ("unknown", "person") or not ledger.path:
            return False
        if ledger.path[-1][3] < NO_PLATE_MIN_WIDTH:
            return False
        if vclass == "motorcycle":
            dx, dy = ledger.get_movement_vector()
            if not (dy < 0 and math.hypot(dx, dy) >= 6.0):
                return False

        ledger.plate_checks += 1
        if plate_found:
            ledger.plate_hits += 1
            ledger.pending.discard(self.key)
            return False
        if ledger.plate_hits == 0 and ledger.plate_checks >= NO_PLATE_MIN_CHECKS:
            ledger.pending.add(self.key)
            return True
        return False

    def judge(self, pipe, det, look):
        mgr = pipe.ledger_manager
        self.record_look(mgr, det.track_id, look.found)
        ledger = mgr.ledgers.get(det.track_id)
        if look.found and ledger is not None:        # every look that found a plate counts as evidence, fair or not
            ledger.plate_confs.append(float(getattr(look, "confidence", 0.0)))
        if not look.found and ledger is not None:
            # Provisional: the ticket is decided when the vehicle leaves (decide_end)
            marks.set_marks(ledger, self.key, det.bbox, [(look.search_box, "NO PLATE SEEN YET", marks.YELLOW)])

    def decide_end(self, ledger):
        if self.key in ledger.pending and ledger.plate_hits == 0:
            ledger.violations.add(self.key)
