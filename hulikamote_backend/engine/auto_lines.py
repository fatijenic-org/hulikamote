"""
auto_lines.py - "Crossing a solid line" without drawing anything.

When a Forensic run selects the rule and no line was drawn, the painted solid lane lines of the video are
found with the road finder (engine/road_lines.py, no model: a fixed camera and some traffic passing are
needed) and handed to the rule as if the operator had drawn them. Lines the operator did draw always win,
and the operator can turn this off in the wizard (`auto_lines: false`).

The finder gives straight lines. A curved line, a faded one, or a video the finder cannot read is not found:
the run then says so in plain words instead of silently checking nothing, and the operator draws the line
(any number of points, so a curve can be followed).
"""
import logging

log = logging.getLogger(__name__)

RULE = "crossing_solid_line"
REF = (1920, 1080)          # the wizard's own coordinate space: the pipeline scales from it

# A lane line is long in the picture: it runs along the road. A short one is a sidewalk edge, a curb or a stretch of cracks
# (measured on a real overpass clip: the finder's two "lines" were 9% and 16% of the picture's height, on the sidewalk;
# the real lane lines are several times longer). Shorter than this share of the picture's height is not used.
MIN_LENGTH = 0.20


def solid_line_rois(result: dict, ref: tuple[int, int] = REF) -> list[dict]:
    """The solid lane lines of a finder result as wizard zones ({"line": [[x, y], [x, y]]}, no road section), in `ref` pixels."""
    if not result.get("ok"):
        return []
    vw, vh = result["video_size"]
    sx, sy = ref[0] / vw, ref[1] / vh
    rois = []
    for line in result.get("lane_lines", []):
        if line.get("style") != "solid":
            continue
        (x0, y0), (x1, y1) = line["p0"], line["p1"]
        if ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5 < MIN_LENGTH * vh:
            continue
        rois.append({"line": [[round(x0 * sx, 1), round(y0 * sy, 1)], [round(x1 * sx, 1), round(y1 * sy, 1)]],
                     "auto": True, "colour": line.get("colour")})
    return rois


def fill_solid_lines(config: dict, video_path, analyse=None) -> str | None:
    """Put the painted solid lines of the video into the rule's zones when the rule is on and nothing was drawn.
    Changes `config` (the wizard payload) in place. Returns a plain sentence for the operator when the rule will check
    nothing (or None when it is fine, or when this does not apply). Never raises: a failure here must not stop the run."""
    if RULE not in (config.get("active_violations") or []):
        return None
    per_violation = config.setdefault("per_violation_configs", {})
    settings = per_violation.setdefault(RULE, {})
    if settings.get("rois"):
        return None                                           # drawn lines win
    if settings.get("auto_lines", True) is False:
        return "Crossing a solid line has no line drawn and finding it from the paint is off: it checks nothing."
    try:
        if analyse is None:
            from engine.road_lines import analyse_video as analyse
        result, _background = analyse(video_path)
    except Exception as exc:                                  # the finder needs ffmpeg and a readable video
        log.warning("[auto_lines] The road could not be read: %s", exc)
        return f"The video could not be read to find the solid lines ({exc}). Crossing a solid line checks nothing: draw the line."
    rois = solid_line_rois(result)
    if not rois:
        reason = result.get("reason") or "No painted solid lane line was found."
        return f"{reason.rstrip('.')}. Crossing a solid line checks nothing in this video: draw the line."
    settings["rois"] = rois
    log.info("[auto_lines] %d painted solid line(s) found and used", len(rois))
    return None
