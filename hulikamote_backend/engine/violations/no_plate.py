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
"""
import math

from engine import marks
from engine.violations.base import Violation

NO_PLATE_MIN_CHECKS = 6     # fair looks needed (~3 s with SPECIALIST_INTERVAL=5 at 10 inferences/s)
NO_PLATE_MIN_WIDTH = 60     # px; a smaller vehicle is too far away for its plate to be found


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
        if not look.found and ledger is not None:
            # Provisional: the ticket is decided when the vehicle leaves (decide_end)
            marks.set_marks(ledger, self.key, det.bbox, [(look.search_box, "NO PLATE SEEN YET", marks.YELLOW)])

    def decide_end(self, ledger):
        if self.key in ledger.pending and ledger.plate_hits == 0:
            ledger.violations.add(self.key)
