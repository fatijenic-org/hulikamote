"""
run_mark.py - where did the CURRENT run of a vehicle begin?

The path of one tracker number can be the paths of two or three vehicles, one after the other (engine/track_continuity.py). A rule that
compares the paths of TWO vehicles (Overtaking on the right) must only use the part of each path that really is one vehicle. This keeps
that start time up to date, one new picture at a time, so asking for it costs almost nothing (track_continuity.last_run walks the whole
path every time).

The path of a ledger is (t, x, y, w): the box height is not kept, so the width stands in for it, as in last_run.
"""
from engine.track_continuity import continues

KEEP = 12            # samples of the run that are remembered (continues() only looks at the last few)


class RunMark:
    def __init__(self):
        self.start_t = None      # when the current run began
        self.last_t = None       # time of the newest picture seen
        self.recent: list = []   # the newest samples of the run


def run_start(ledger):
    """The time at which the newest continuous run of `ledger`'s path began, or None when it has no path."""
    path = ledger.path
    if not path:
        return None
    mark = getattr(ledger, "run_mark", None)
    if mark is None:
        mark = ledger.run_mark = RunMark()
    if mark.last_t is not None and path[-1][0] <= mark.last_t:
        return mark.start_t
    fresh = []
    for p in reversed(path):                       # only the pictures that came since the last look
        if mark.last_t is not None and p[0] <= mark.last_t:
            break
        fresh.append(p)
    fresh.reverse()
    for p in fresh:
        sample = (p[0], p[1], p[2], p[3], p[3])
        if mark.start_t is None or not continues(mark.recent, sample):
            mark.start_t, mark.recent = sample[0], [sample]
        else:
            mark.recent.append(sample)
            del mark.recent[:-KEEP]
        mark.last_t = sample[0]
    return mark.start_t
