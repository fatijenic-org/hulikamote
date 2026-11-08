"""
sketches.py - one small drawing per kind of violation (330 x 170), so the idea is visible before the code is read.
They are teaching pictures, not screenshots: boxes and arrows only.
"""
from __future__ import annotations

import math

from lib import svg


def _arrow(x1, y1, x2, y2, kind="in") -> str:
    ang = math.atan2(y2 - y1, x2 - x1)
    s = 10
    a = (x2 - s * math.cos(ang - 0.45), y2 - s * math.sin(ang - 0.45))
    b = (x2 - s * math.cos(ang + 0.45), y2 - s * math.sin(ang + 0.45))
    return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" class="a-{kind}"/>'
            f'<polygon points="{x2},{y2} {a[0]:.1f},{a[1]:.1f} {b[0]:.1f},{b[1]:.1f}" class="a-{kind}h"/>')


def _t(x, y, s, anchor="start", cls="sk") -> str:
    return f'<text x="{x}" y="{y}" class="{cls}" text-anchor="{anchor}">{s}</text>'


def _road() -> str:
    return '<rect x="6" y="6" width="318" height="158" rx="10" class="road"/>'


def _car(x, y, w, h, extra="veh") -> str:
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" class="{extra}"/>'


def _person(x, y, w, h) -> str:
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="5" class="per"/><circle cx="{x + w / 2}" cy="{y + 7}" r="5" class="per"/>'


def _zone(pts) -> str:
    return f'<polygon points="{" ".join(f"{x},{y}" for x, y in pts)}" class="zone"/>'


def _cross(x, y, r=11) -> str:
    return f'<circle cx="{x}" cy="{y}" r="{r}" class="no" fill="var(--surface)"/><path d="M{x - 5} {y - 5}L{x + 5} {y + 5}M{x + 5} {y - 5}L{x - 5} {y + 5}" class="no"/>'


def _tick(x, y, r=11) -> str:
    return f'<circle cx="{x}" cy="{y}" r="{r}" class="ok" fill="var(--surface)"/><path d="M{x - 5} {y}L{x - 1} {y + 5}L{x + 6} {y - 5}" class="ok"/>'


Z = [(24, 26), (306, 26), (306, 144), (24, 144)]

KINDS = {
    "flow": lambda: (_road() + _zone(Z) + _arrow(50, 55, 270, 55, "ok") + _t(160, 46, "legal direction", "middle")
                     + _car(150, 88, 64, 32) + _arrow(240, 104, 110, 104, "no") + _t(160, 136, "driving the other way", "middle")),
    "timer": lambda: (_road() + _zone(Z) + _car(110, 62, 90, 46) + _t(155, 90, "stopped", "middle")
                      + '<circle cx="262" cy="56" r="22" class="zone" fill="var(--surface)"/><path d="M262 56V42M262 56L272 62" class="a-in"/>'
                      + _t(262, 96, "longer than", "middle") + _t(262, 108, "the time limit", "middle")),
    "lane": lambda: (_road() + '<line x1="165" y1="10" x2="165" y2="160" class="path"/>' + _zone([(170, 20), (312, 20), (312, 150), (170, 150)])
                     + _t(241, 40, "reserved lane", "middle") + _car(205, 70, 70, 40) + _cross(240, 90) + _t(240, 134, "vehicle type not allowed", "middle")
                     + _car(60, 70, 70, 40) + _tick(95, 90) + _t(95, 134, "other lane: fine", "middle")),
    "turn": lambda: (_road() + '<rect x="130" y="6" width="70" height="158" class="road"/>' + _zone([(110, 60), (230, 60), (230, 150), (110, 150)])
                     + _arrow(165, 150, 165, 112, "ok") + _t(180, 135, "enters going straight") + _arrow(165, 108, 70, 84, "no") + _t(36, 74, "forbidden turn")
                     + '<path d="M165 150 Q165 96 85 86" class="path"/>'),
    "uturn": lambda: (_road() + _zone(Z) + '<path d="M120 140 L120 66 Q120 34 165 34 Q210 34 210 66 L210 140" class="path"/>' + _arrow(210, 110, 210, 140, "no")
                      + _t(165, 24, "heading swings 150 degrees or more", "middle") + _t(165, 160, "and moves sideways: a real U-turn", "middle")),
    "swerve": lambda: (_road() + _zone(Z) + '<polyline points="' + " ".join(f"{30 + i * 8},{85 + 28 * math.sin(i / 2.2):.1f}" for i in range(36))
                       + '" class="path"/>' + _arrow(300, 85, 310, 85, "in") + _t(165, 24, "left - right - left within 6 seconds", "middle")),
    "line": lambda: (_road() + _zone([(24, 26), (306, 26), (306, 150), (24, 150)]) + '<line x1="24" y1="92" x2="306" y2="92" class="no" stroke-width="5"/>'
                     + _car(130, 56, 70, 52) + _arrow(165, 140, 165, 112, "in") + _t(250, 84, "line", "middle") + _t(165, 20, "ground point passes the line", "middle")),
    "light": lambda: (_road() + _zone([(24, 26), (306, 26), (306, 150), (24, 150)]) + '<line x1="24" y1="92" x2="240" y2="92" class="no" stroke-width="5"/>'
                      + _car(95, 54, 70, 52) + _arrow(130, 140, 130, 112, "in") + '<rect x="268" y="30" width="30" height="76" rx="6" fill="#222"/>'
                      + '<circle cx="283" cy="48" r="8" fill="#e34948"/><circle cx="283" cy="68" r="8" fill="#555"/><circle cx="283" cy="88" r="8" fill="#555"/>'
                      + _t(165, 20, "crosses the stop line while the light is red", "middle")),
    "sign": lambda: (_road() + _zone([(24, 40), (250, 40), (250, 146), (24, 146)]) + '<circle cx="288" cy="52" r="20" fill="#e34948"/><rect x="274" y="48" width="28" height="8" fill="#fff"/>'
                     + _car(80, 80, 70, 40) + _arrow(165, 100, 235, 100, "no") + _t(137, 30, "one zone for each sign", "middle")),
    "riders": lambda: (_road() + _person(122, 50, 24, 52) + _person(152, 44, 24, 58) + _person(182, 50, 24, 52) + _car(100, 98, 130, 36) + _t(165, 152, "3 riders: more than 2 allowed", "middle")),
    "bed": lambda: (_road() + _car(210, 74, 82, 58) + _t(251, 108, "cab", "middle") + _car(52, 90, 150, 42, "veh dash")
                    + _person(84, 56, 24, 56) + _person(124, 60, 24, 52) + _t(127, 150, "open bed", "middle") + _arrow(300, 54, 232, 54, "in") + _t(250, 44, "travel", "middle")),
    "roof": lambda: (_road() + _car(56, 70, 210, 70) + _person(112, 28, 22, 50) + _t(123, 22, "roof", "middle") + _person(262, 86, 22, 46) + _t(272, 150, "hanging", "middle")
                     + '<rect x="70" y="84" width="22" height="22" rx="3" fill="var(--surface)" stroke="var(--axis)"/><rect x="104" y="84" width="22" height="22" rx="3" fill="var(--surface)" stroke="var(--axis)"/>'),
    "helmet": lambda: (_road() + _person(62, 38, 56, 100) + '<rect x="76" y="34" width="28" height="22" rx="8" class="ok"/>' + _t(90, 152, "helmet", "middle")
                       + _person(206, 38, 56, 100) + '<rect x="220" y="34" width="28" height="22" rx="8" class="no" stroke-dasharray="4 3"/>' + _t(234, 152, "NO HELMET", "middle")),
    "plate": lambda: (_road() + _car(70, 30, 190, 110) + '<rect x="130" y="102" width="70" height="24" rx="3" class="ok"/>' + _t(165, 119, "AB 1234", "middle")
                      + _t(165, 22, "find the plate, cut it out, read it", "middle")),
    "noplate": lambda: (_road() + _car(70, 30, 190, 110) + '<rect x="130" y="102" width="70" height="24" rx="3" class="no" stroke-dasharray="4 3"/>' + _t(165, 119, "?", "middle")
                        + _t(165, 22, "no plate in any fair look: decided when it leaves", "middle")),
    "cabin": lambda: (_road() + '<path d="M70 40 L260 40 L240 100 L90 100 Z" class="zone"/>' + '<line x1="120" y1="46" x2="170" y2="96" class="ok" stroke-width="5"/>'
                      + _t(165, 30, "windshield: clear? seatbelt? phone?", "middle") + '<rect x="205" y="64" width="14" height="24" rx="3" class="no"/>'
                      + _t(120, 125, "seatbelt strap", "middle") + _t(212, 125, "phone", "middle") + _car(70, 112, 190, 38, "veh")),
    "mirror": lambda: (_road() + '<line x1="105" y1="60" x2="225" y2="60" class="a-in"/><rect x="152" y="60" width="26" height="70" rx="8" class="veh"/>'
                       + '<circle cx="95" cy="52" r="12" class="ok"/><circle cx="235" cy="52" r="12" class="ok"/>' + _t(165, 152, "front or rear view: count the mirrors", "middle")),
    "blink": lambda: (_road() + _car(100, 40, 130, 70) + '<circle cx="110" cy="100" r="9" fill="#eda100"/><circle cx="220" cy="100" r="9" fill="#555"/>'
                      + "".join(f'<rect x="{40 + i * 36}" y="{128 if i % 2 else 124}" width="22" height="{8 if i % 2 else 16}" class="f4"/>' for i in range(8))
                      + _t(165, 26, "turn with no blinking amber on either edge", "middle")),
}


def sketch(kind: str, label: str = "") -> str:
    return svg(330, 170, KINDS[kind](), label or f"Sketch: {kind}", "viz sketch")
