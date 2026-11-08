"""
cabin.py - pieces shared by the checks that look inside a car (seatbelt, phone).
"""
from engine.specialists import IDX_CLEAR_WINDOW, IDX_TINTED_WINDOW


def judgeable(look) -> bool:
    """Safety Override Gate: a tinted window hides the cabin, and with no clear window seen there is nothing to judge."""
    found = {d["class_id"] for d in look.dets}
    return IDX_TINTED_WINDOW not in found and IDX_CLEAR_WINDOW in found


def boxes(look, class_id: int, label: str, colour: tuple) -> list:
    """Mark entries (box, label, colour) for every detection of one class."""
    return [(d["box"], label, colour) for d in look.dets if d["class_id"] == class_id]
