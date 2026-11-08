"""
export_json.py - export documentation pages and glossary as typed JSON block trees for Flutter.

Derives the block tree directly from the rendered HTML of each page using html.parser.
Enforces strict tag validation: any unknown HTML tag or structure fails loudly.
"""
from __future__ import annotations

import html
from html.parser import HTMLParser
import json
import re
from pathlib import Path

from glossary import G

# Canonical glossary key lookup by definition (fallback if data-key attribute missing)
_DEF_TO_KEY = {v: k for k, v in G.items()}
_LOWER_TO_KEY = {k.lower(): k for k in G}


# ─────────────────────────────────────────────────────────────────────────────
# 1. Lightweight HTML DOM tree builder using standard library HTMLParser
# ─────────────────────────────────────────────────────────────────────────────

class DomNode:
    VOID_TAGS = {"meta", "link", "br", "img", "hr", "input", "col", "line", "rect",
                 "path", "circle", "polyline", "polygon"}

    def __init__(self, tag: str, attrs: dict[str, str], parent: DomNode | None = None):
        self.tag = tag
        self.attrs = attrs
        self.classes = set(attrs.get("class", "").split())
        self.parent = parent
        self.children: list[DomNode | str] = []

    def text_content(self) -> str:
        res = []
        for c in self.children:
            if isinstance(c, str):
                res.append(c)
            else:
                res.append(c.text_content())
        return "".join(res)

    def find_all(self, tag: str, cls: str | None = None) -> list[DomNode]:
        out = []
        for c in self.children:
            if isinstance(c, DomNode):
                if c.tag == tag and (cls is None or cls in c.classes):
                    out.append(c)
                out.extend(c.find_all(tag, cls))
        return out

    def find_one(self, tag: str, cls: str | None = None) -> DomNode | None:
        for c in self.children:
            if isinstance(c, DomNode):
                if c.tag == tag and (cls is None or cls in c.classes):
                    return c
                found = c.find_one(tag, cls)
                if found:
                    return found
        return None


class DomBuilder(HTMLParser):
    def __init__(self):
        super().__init__()
        self.root = DomNode("document", {})
        self.stack: list[DomNode] = [self.root]

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]):
        attrs_dict = {k: v or "" for k, v in attrs}
        node = DomNode(tag, attrs_dict, self.stack[-1])
        self.stack[-1].children.append(node)
        if tag not in DomNode.VOID_TAGS:
            self.stack.append(node)

    def handle_endtag(self, tag: str):
        if tag in DomNode.VOID_TAGS:
            return
        if self.stack and self.stack[-1].tag == tag:
            self.stack.pop()
        else:
            # find matching tag up the stack
            idx = None
            for i in range(len(self.stack) - 1, -1, -1):
                if self.stack[i].tag == tag:
                    idx = i
                    break
            if idx is not None and idx > 0:
                while len(self.stack) > idx:
                    self.stack.pop()

    def handle_data(self, data: str):
        if self.stack:
            self.stack[-1].children.append(data)

    def handle_entityref(self, name: str):
        s = html.unescape(f"&{name};")
        if self.stack:
            self.stack[-1].children.append(s)

    def handle_charref(self, name: str):
        s = html.unescape(f"&#{name};")
        if self.stack:
            self.stack[-1].children.append(s)


# ─────────────────────────────────────────────────────────────────────────────
# 2. Inlines converter
# ─────────────────────────────────────────────────────────────────────────────

KNOWN_INLINE_TAGS = {"b", "i", "code", "a", "span", "br", "s"}

def nodes_to_inlines(children: list[DomNode | str]) -> list[dict]:
    out: list[dict] = []

    def append_text(t: str):
        if not t:
            return
        if out and out[-1].get("type") == "text":
            out[-1]["text"] += t
        else:
            out.append({"type": "text", "text": t})

    for c in children:
        if isinstance(c, str):
            append_text(c)
        elif isinstance(c, DomNode):
            if c.tag not in KNOWN_INLINE_TAGS:
                raise ValueError(f"Unknown inline HTML tag: <{c.tag}> with classes {c.classes}")

            if c.tag == "br":
                out.append({"type": "br"})
            elif c.tag == "b":
                out.append({"type": "b", "children": nodes_to_inlines(c.children)})
            elif c.tag == "i":
                # Check if it's an icon inside a chip or just italic text
                out.append({"type": "i", "children": nodes_to_inlines(c.children)})
            elif c.tag == "s":
                out.append({"type": "s", "children": nodes_to_inlines(c.children)})
            elif c.tag == "code":
                out.append({"type": "code", "text": c.text_content()})
            elif c.tag == "a":
                href = c.attrs.get("href", "")
                out.append({"type": "link", "href": href, "children": nodes_to_inlines(c.children)})
            elif c.tag == "span":
                if "term" in c.classes:
                    key = c.attrs.get("data-key")
                    tip = c.attrs.get("data-tip", "")
                    if not key and tip in _DEF_TO_KEY:
                        key = _DEF_TO_KEY[tip]
                    shown = c.text_content()
                    out.append({"type": "term", "key": key or shown, "shown": shown})
                elif "chip" in c.classes:
                    # e.g. <span class="chip ok"><i aria-hidden="true">&#10003;</i>text</span>
                    kind = "info"
                    for k in ("ok", "warn", "bad", "info", "off"):
                        if k in c.classes:
                            kind = k
                            break
                    text = ""
                    for sub in c.children:
                        if isinstance(sub, str):
                            text += sub
                        elif isinstance(sub, DomNode) and sub.tag != "i":
                            text += sub.text_content()
                    out.append({"type": "chip", "kind": kind, "text": text.strip()})
                else:
                    # generic span: flatten inlines
                    inlines = nodes_to_inlines(c.children)
                    out.extend(inlines)

    return out


# ─────────────────────────────────────────────────────────────────────────────
# 3. Scene SVG Primitives Parser
# ─────────────────────────────────────────────────────────────────────────────

def _resolve_role(classes: set[str], attrs: dict[str, str], default_role: str = "") -> tuple[str, bool]:
    """Returns (role, is_dash)."""
    dash = "dash" in classes or "stroke-dasharray" in attrs
    # Check slots/css classes
    for c in ("road", "zone", "veh", "per", "ok", "no", "path",
              "a-ok", "a-no", "a-in", "a-okh", "a-noh", "a-inh",
              "ar", "ahp", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8",
              "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "axis", "grid", "target"):
        if c in classes:
            return c, dash

    if "bx" in classes:
        for slot in ("c1", "c2", "c3", "c4", "c7", "c8"):
            if slot in classes:
                return f"bx {slot}", dash
        return "bx", dash

    fill = attrs.get("fill", "")
    stroke = attrs.get("stroke", "")
    if fill == "var(--surface)" and stroke == "var(--axis)":
        return "surface_box", dash
    if fill == "#222":
        return "dark", dash
    if fill == "#fff":
        return "light", dash
    if fill == "#e34948":
        return "crit", dash
    if fill == "#eda100":
        return "warn", dash
    if fill == "#555":
        return "muted", dash

    return default_role or "default", dash


def parse_scene_svg(svg_node: DomNode) -> dict:
    w = 760
    h = 240
    vb = svg_node.attrs.get("viewBox", "")
    if vb:
        parts = vb.split()
        if len(parts) == 4:
            w = int(float(parts[2]))
            h = int(float(parts[3]))

    aria = svg_node.attrs.get("aria-label", "")
    primitives: list[dict] = []

    def walk_svg(node: DomNode):
        for c in node.children:
            if not isinstance(c, DomNode):
                continue
            tag = c.tag
            attrs = c.attrs
            classes = c.classes

            if tag in ("defs", "marker", "title"):
                continue  # skip defs / markers
            elif tag == "rect":
                role, dash = _resolve_role(classes, attrs, "bx")
                primitives.append({
                    "type": "rect",
                    "x": float(attrs.get("x", 0)),
                    "y": float(attrs.get("y", 0)),
                    "w": float(attrs.get("width", 0)),
                    "h": float(attrs.get("height", 0)),
                    "rx": float(attrs.get("rx", 0)),
                    "role": role,
                    "dash": dash
                })
            elif tag == "line":
                role, dash = _resolve_role(classes, attrs, "ar")
                arrow = "ah" in attrs.get("marker-end", "") or role == "ar"
                sw = float(attrs.get("stroke-width", 1.0))
                primitives.append({
                    "type": "line",
                    "x1": float(attrs.get("x1", 0)),
                    "y1": float(attrs.get("y1", 0)),
                    "x2": float(attrs.get("x2", 0)),
                    "y2": float(attrs.get("y2", 0)),
                    "role": role,
                    "arrow": arrow,
                    "dash": dash,
                    "width": sw
                })
            elif tag == "circle":
                role, _ = _resolve_role(classes, attrs, "circle")
                fill_surf = attrs.get("fill") == "var(--surface)"
                primitives.append({
                    "type": "circle",
                    "cx": float(attrs.get("cx", 0)),
                    "cy": float(attrs.get("cy", 0)),
                    "r": float(attrs.get("r", 0)),
                    "role": role,
                    "fill_surface": fill_surf
                })
            elif tag == "polygon":
                role, _ = _resolve_role(classes, attrs, "zone")
                pts_str = attrs.get("points", "").strip()
                pts = []
                for pair in pts_str.split():
                    if "," in pair:
                        x, y = pair.split(",")
                        pts.append([float(x), float(y)])
                primitives.append({
                    "type": "polygon",
                    "points": pts,
                    "role": role
                })
            elif tag == "polyline":
                role, dash = _resolve_role(classes, attrs, "path")
                pts_str = attrs.get("points", "").strip()
                pts = []
                for pair in pts_str.split():
                    if "," in pair:
                        x, y = pair.split(",")
                        pts.append([float(x), float(y)])
                primitives.append({
                    "type": "polyline",
                    "points": pts,
                    "role": role,
                    "dash": dash
                })
            elif tag == "path":
                role, dash = _resolve_role(classes, attrs, "path")
                d = attrs.get("d", "")
                sw = float(attrs.get("stroke-width", 2.0))
                primitives.append({
                    "type": "path",
                    "d": d,
                    "role": role,
                    "dash": dash,
                    "width": sw
                })
            elif tag == "text":
                role = "sk"
                for tc in ("bt", "bs", "yl", "vl", "lg", "al", "tl", "sk"):
                    if tc in classes:
                        role = tc
                        break
                anchor = attrs.get("text-anchor", "start")
                primitives.append({
                    "type": "text",
                    "x": float(attrs.get("x", 0)),
                    "y": float(attrs.get("y", 0)),
                    "text": c.text_content(),
                    "role": role,
                    "anchor": anchor
                })
            elif tag == "g":
                walk_svg(c)
            else:
                raise ValueError(f"Unknown SVG tag in scene: <{tag}>")

    walk_svg(svg_node)
    return {
        "w": w,
        "h": h,
        "aria": aria,
        "primitives": primitives
    }


# ─────────────────────────────────────────────────────────────────────────────
# 4. Code Block Parser
# ─────────────────────────────────────────────────────────────────────────────

def parse_code_block(fig_node: DomNode, title: str = "") -> dict:
    file_span = fig_node.find_one("span", "file")
    path = file_span.text_content().strip() if file_span else ""

    rng_span = fig_node.find_one("span", "rng")
    first = 1
    last = 1
    if rng_span:
        m = re.search(r"lines\s+(\d+)-(\d+)", rng_span.text_content())
        if m:
            first, last = int(m.group(1)), int(m.group(2))

    lines: list[dict] = []
    pre_node = fig_node.find_one("pre")
    if pre_node:
        code_node = pre_node.find_one("code")
        if code_node:
            for child in code_node.children:
                if not isinstance(child, DomNode) or child.tag != "span" or "line" not in child.classes:
                    continue
                is_gap = "gap" in child.classes
                is_hot = "hot" in child.classes

                ln_span = child.find_one("span", "ln")
                ln_num = None
                if ln_span and ln_span.text_content().strip().isdigit():
                    ln_num = int(ln_span.text_content().strip())

                tokens: list[dict] = []
                lc_span = child.find_one("span", "lc")
                if lc_span:
                    for token_child in lc_span.children:
                        if isinstance(token_child, str):
                            tokens.append({"cls": "", "text": token_child})
                        elif isinstance(token_child, DomNode) and token_child.tag == "span":
                            token_cls = ""
                            for c in token_child.classes:
                                if c.startswith("t-"):
                                    token_cls = c[2:]
                                    break
                            tokens.append({"cls": token_cls, "text": token_child.text_content()})

                mark = None
                mk_span = child.find_one("span", "mk")
                if mk_span:
                    aria_label = mk_span.attrs.get("aria-label", "")
                    m_mk = re.search(r"note\s+(\d+)", aria_label)
                    if m_mk:
                        mark = int(m_mk.group(1))

                lines.append({
                    "n": ln_num,
                    "tokens": tokens,
                    "mark": mark,
                    "is_gap": is_gap,
                    "is_hot": is_hot
                })

    notes: list[dict] = []
    ol_walk = fig_node.find_one("ol", "walk")
    if ol_walk:
        for idx, li in enumerate(ol_walk.find_all("li"), 1):
            mk_span = li.find_one("span", "mk")
            mark = idx
            at_span = li.find_one("span", "at")
            note_line = first
            if at_span:
                m_at = re.search(r"line\s+(\d+)", at_span.text_content())
                if m_at:
                    note_line = int(m_at.group(1))

            # Remaining text in li
            note_text_parts = []
            for c in li.children:
                if isinstance(c, str):
                    note_text_parts.append(c)
                elif isinstance(c, DomNode) and "mk" not in c.classes and "at" not in c.classes:
                    note_text_parts.append(c.text_content())
            note_text = "".join(note_text_parts).strip()
            notes.append({
                "mark": mark,
                "line": note_line,
                "text": note_text
            })

    return {
        "type": "code",
        "path": path,
        "first": first,
        "last": last,
        "title": title,
        "lines": lines,
        "notes": notes
    }


# ─────────────────────────────────────────────────────────────────────────────
# 5. Table Parser
# ─────────────────────────────────────────────────────────────────────────────

def parse_table_node(tbl_container: DomNode) -> dict:
    table_node = tbl_container if tbl_container.tag == "table" else tbl_container.find_one("table")
    if not table_node:
        raise ValueError("parse_table_node: no <table> found")

    is_dense = "dense" in table_node.classes
    is_heat = "heat" in table_node.classes

    widths: list[str] = []
    colgroup = table_node.find_one("colgroup")
    if colgroup:
        for col in colgroup.find_all("col"):
            style = col.attrs.get("style", "")
            m = re.search(r"width:\s*([^;]+)", style)
            widths.append(m.group(1).strip() if m else "")

    headers: list[list[dict]] = []
    thead = table_node.find_one("thead")
    if thead:
        tr = thead.find_one("tr")
        if tr:
            for th in tr.find_all("th"):
                headers.append(nodes_to_inlines(th.children))

    rows: list[list[list[dict]]] = []
    cell_classes: list[list[str]] = []
    tbody = table_node.find_one("tbody")
    if tbody:
        for tr in tbody.find_all("tr"):
            row: list[list[dict]] = []
            classes_row: list[str] = []
            for td in tr.find_all("td"):
                row.append(nodes_to_inlines(td.children))
                c_str = " ".join(td.classes)
                classes_row.append(c_str)
            rows.append(row)
            cell_classes.append(classes_row)

    return {
        "type": "table",
        "headers": headers,
        "rows": rows,
        "widths": widths,
        "cell_classes": cell_classes,
        "is_dense": is_dense,
        "is_heat": is_heat
    }


# ─────────────────────────────────────────────────────────────────────────────
# 6. Violation Card Parser
# ─────────────────────────────────────────────────────────────────────────────

def parse_card_node(art_node: DomNode) -> dict:
    card_id = art_node.attrs.get("id", "")
    header = art_node.find_one("header")
    name = ""
    key = ""
    chips: list[dict] = []
    if header:
        h3 = header.find_one("h3")
        name = h3.text_content().strip() if h3 else ""
        vkey_span = header.find_one("span", "vkey")
        key = vkey_span.text_content().strip() if vkey_span else ""
        for sp in header.find_all("span", "chip"):
            kind = "info"
            for k in ("ok", "warn", "bad", "info", "off"):
                if k in sp.classes:
                    kind = k
                    break
            text = "".join(sub if isinstance(sub, str) else sub.text_content()
                           for sub in sp.children if not (isinstance(sub, DomNode) and sub.tag == "i")).strip()
            chips.append({"kind": kind, "text": text})

    sketch_scene = None
    vgrid = art_node.find_one("div", "vgrid")
    grid_left_blocks: list[dict] = []
    grid_right_blocks: list[dict] = []

    if vgrid:
        grid_children = [c for c in vgrid.children if isinstance(c, DomNode) and c.tag == "div"]
        if len(grid_children) >= 2:
            left_div, right_div = grid_children[0], grid_children[1]
            grid_left_blocks = parse_nodes_to_blocks(left_div.children)

            # right div contains sketch + mini view + mini test box
            svg_node = right_div.find_one("svg")
            if svg_node:
                sketch_scene = parse_scene_svg(svg_node)

            for mini in right_div.find_all("div", "mini"):
                b_node = mini.find_one("b")
                mini_title = b_node.text_content().strip() if b_node else ""
                note_span = mini.find_one("span", "note")
                note_text = note_span.text_content().strip() if note_span else ""
                ul_node = mini.find_one("ul")
                items = []
                if ul_node:
                    for li in ul_node.find_all("li"):
                        items.append(nodes_to_inlines(li.children))
                grid_right_blocks.append({
                    "type": "mini",
                    "title": mini_title,
                    "note": note_text,
                    "items": items
                })

    # Bottom elements after vgrid
    bottom_nodes: list[DomNode] = []
    seen_vgrid = False
    for c in art_node.children:
        if isinstance(c, DomNode):
            if c == vgrid:
                seen_vgrid = True
                continue
            if seen_vgrid:
                bottom_nodes.append(c)

    bottom_blocks = parse_nodes_to_blocks(bottom_nodes)

    return {
        "type": "card",
        "id": card_id,
        "key": key,
        "name": name,
        "chips": chips,
        "sketch": sketch_scene,
        "grid_left": grid_left_blocks,
        "grid_right": grid_right_blocks,
        "bottom": bottom_blocks
    }


# ─────────────────────────────────────────────────────────────────────────────
# 7. Block Parser
# ─────────────────────────────────────────────────────────────────────────────

KNOWN_BLOCK_TAGS = {"h1", "h2", "h3", "h4", "p", "ul", "ol", "dl", "div", "aside",
                    "pre", "a", "figure", "article", "section", "noscript", "details", "summary"}

def parse_nodes_to_blocks(nodes: list[DomNode | str]) -> list[dict]:
    blocks: list[dict] = []
    pending_code_title: str = ""
    i = 0

    while i < len(nodes):
        item = nodes[i]
        i += 1
        if isinstance(item, str):
            continue  # ignore inter-block whitespace

        node = item
        if node.tag not in KNOWN_BLOCK_TAGS:
            raise ValueError(f"Unknown block HTML tag: <{node.tag}> with classes {node.classes}")

        # Section wrapper: parse its inner elements
        if node.tag == "section":
            if "terms" in node.classes:
                continue  # terms section handled globally via glossary.json
            inner_blocks = parse_nodes_to_blocks(node.children)
            blocks.extend(inner_blocks)
            continue

        # Code title element immediately preceding figure.code
        if node.tag == "div" and "code-title" in node.classes:
            pending_code_title = node.text_content().strip()
            continue

        # Headings
        if node.tag in ("h1", "h2", "h3", "h4"):
            level = int(node.tag[1])
            hid = node.attrs.get("id", "")
            # check if previous sibling in section was kicker
            kicker = ""
            if blocks and blocks[-1].get("type") == "kicker":
                kicker = blocks.pop()["text"]
            blocks.append({
                "type": "heading",
                "level": level,
                "id": hid,
                "text": node.text_content().strip(),
                "kicker": kicker
            })
            continue

        # Kicker div
        if node.tag == "div" and "kicker" in node.classes:
            blocks.append({"type": "kicker", "text": node.text_content().strip()})
            continue

        # Paragraph
        if node.tag == "p":
            is_note = "note" in node.classes
            inlines = nodes_to_inlines(node.children)
            blocks.append({
                "type": "paragraph",
                "inlines": inlines,
                "is_note": is_note
            })
            continue

        # Lists
        if node.tag == "ul":
            items = [nodes_to_inlines(li.children) for li in node.find_all("li")]
            blocks.append({
                "type": "list",
                "ordered": False,
                "items": items
            })
            continue

        if node.tag == "ol":
            if "steps" in node.classes:
                items = [nodes_to_inlines(li.children) for li in node.find_all("li")]
                blocks.append({
                    "type": "steps",
                    "items": items
                })
            else:
                items = [nodes_to_inlines(li.children) for li in node.find_all("li")]
                blocks.append({
                    "type": "list",
                    "ordered": True,
                    "items": items
                })
            continue

        # Definition list (kv)
        if node.tag == "dl" and "kv" in node.classes:
            dts = [c for c in node.children if isinstance(c, DomNode) and c.tag == "dt"]
            dds = [c for c in node.children if isinstance(c, DomNode) and c.tag == "dd"]
            items = []
            for dt, dd in zip(dts, dds):
                items.append({
                    "key": dt.text_content().strip(),
                    "value": nodes_to_inlines(dd.children)
                })
            blocks.append({"type": "kv", "items": items})
            continue

        # Callout aside
        if node.tag == "aside" and "callout" in node.classes:
            kind = "info"
            for k in ("ok", "warn", "bad", "info"):
                if k in node.classes:
                    kind = k
                    break
            b_node = node.find_one("b")
            title = b_node.text_content().strip() if b_node else ""
            div_node = node.find_one("div")
            inner = parse_nodes_to_blocks(div_node.children) if div_node else []
            blocks.append({
                "type": "callout",
                "kind": kind,
                "title": title,
                "blocks": inner
            })
            continue

        # Command terminal
        if node.tag == "pre" and "cmd" in node.classes:
            code_node = node.find_one("code")
            text = code_node.text_content() if code_node else node.text_content()
            blocks.append({"type": "cmd", "text": text.strip()})
            continue

        # Ref link (<a class="ref">)
        if node.tag == "a" and "ref" in node.classes:
            code_node = node.find_one("code")
            label = code_node.text_content().strip() if code_node else ""
            at_span = node.find_one("span", "ref-at")
            path = ""
            line = 1
            if at_span:
                parts = at_span.text_content().strip().split(":")
                path = parts[0]
                if len(parts) > 1 and parts[1].isdigit():
                    line = int(parts[1])
            ref_item = {"path": path, "line": line, "label": label}
            # Collect adjacent ref links
            if blocks and blocks[-1].get("type") == "refs":
                blocks[-1]["items"].append(ref_item)
            else:
                blocks.append({"type": "refs", "items": [ref_item]})
            continue

        # Table container
        if (node.tag == "div" and "tbl" in node.classes) or node.tag == "table":
            tbl_block = parse_table_node(node)
            blocks.append(tbl_block)
            continue

        # Code block
        if node.tag == "figure" and "code" in node.classes:
            code_block = parse_code_block(node, pending_code_title)
            pending_code_title = ""
            blocks.append(code_block)
            continue

        # Figure (chart or scene diagram)
        if node.tag == "figure" and "fig" in node.classes:
            cap_node = node.find_one("figcaption")
            caption_inlines = nodes_to_inlines(cap_node.children) if cap_node else []
            svg_node = node.find_one("svg")
            if not svg_node:
                raise ValueError("figure.fig has no <svg> element")
            data_ir = svg_node.attrs.get("data-ir")
            if data_ir:
                ir_obj = json.loads(data_ir)
                ir_obj["type"] = "figure"
                ir_obj["caption"] = caption_inlines
                blocks.append(ir_obj)
            else:
                scene = parse_scene_svg(svg_node)
                blocks.append({
                    "type": "figure",
                    "kind": "scene",
                    "caption": caption_inlines,
                    "scene": scene
                })
            continue

        # Details / Accordion (e.g. Q&A items or help)
        if node.tag == "details":
            is_open = "open" in node.attrs
            summary = node.find_one("summary")
            title = summary.text_content().strip() if summary else ""
            content_nodes = [c for c in node.children if not (isinstance(c, DomNode) and c.tag == "summary")]
            inner = parse_nodes_to_blocks(content_nodes)
            blocks.append({
                "type": "callout",
                "kind": "info",
                "title": title,
                "blocks": inner,
                "is_collapsible": True,
                "is_open": is_open
            })
            continue

        # Violation Card
        if node.tag == "article" and "vcard" in node.classes:
            card_block = parse_card_node(node)
            blocks.append(card_block)
            continue

        # Q&A help details
        if node.tag == "div" and "qa-help" in node.classes:
            det = node.find_one("details")
            if det:
                is_open = "open" in det.attrs
                summary = det.find_one("summary")
                title = summary.text_content().strip() if summary else "Help"
                content_nodes = [c for c in det.children if not (isinstance(c, DomNode) and c.tag == "summary")]
                inner_blocks = parse_nodes_to_blocks(content_nodes)
                blocks.append({
                    "type": "callout",
                    "kind": "info",
                    "title": title,
                    "blocks": inner_blocks,
                    "is_collapsible": True,
                    "is_open": is_open
                })
            continue

        if node.tag == "div" and node.attrs.get("id") == "qa-app":
            blocks.append({
                "type": "qa_placeholder"
            })
            continue

        if node.tag == "noscript":
            continue

        # If it's a generic div or wrapper, parse its children
        if node.tag == "div":
            inner = parse_nodes_to_blocks(node.children)
            blocks.extend(inner)
            continue

        raise ValueError(f"Unhandled block tag: <{node.tag}> classes={node.classes}")

    return blocks


# ─────────────────────────────────────────────────────────────────────────────
# 8. Page & Glossary Exporters
# ─────────────────────────────────────────────────────────────────────────────

def html_to_page_dict(page, html_text: str) -> dict:
    builder = DomBuilder()
    builder.feed(html_text)
    doc = builder.root

    main_node = doc.find_one("main")
    if not main_node:
        raise ValueError(f"No <main> element found in {page.slug}")

    # Extract Hero section: title, lede, pn
    hero_node = main_node.find_one("div", "hero")
    title = page.title
    number = page.number
    lede_inlines = []
    if hero_node:
        h1 = hero_node.find_one("h1")
        if h1:
            title = h1.text_content().strip()
        lede_p = hero_node.find_one("p", "lede")
        if lede_p:
            lede_inlines = nodes_to_inlines(lede_p.children)
        pn_span = hero_node.find_one("span", "pn")
        if pn_span:
            number = pn_span.text_content().replace("Page", "").strip()

    # TOC
    toc = []
    for ident, t, lv in page.toc:
        # plain text title for TOC
        plain_t = re.sub(r"\[\[([^\[\]|]+?)(?:\|([^\[\]]+?))?\]\]", r"\2", t)
        if plain_t == t:
            plain_t = re.sub(r"\[\[([^\[\]|]+?)\]\]", r"\1", t)
        toc.append({
            "id": ident,
            "title": plain_t,
            "level": lv
        })

    # Body blocks (skip hero and toc nav)
    body_nodes = []
    for c in main_node.children:
        if isinstance(c, DomNode):
            if c == hero_node:
                continue
            if c.tag == "nav" and "toc" in c.classes:
                continue
            body_nodes.append(c)

    blocks = parse_nodes_to_blocks(body_nodes)

    return {
        "slug": page.slug,
        "number": number,
        "title": title,
        "lede": lede_inlines,
        "toc": toc,
        "blocks": blocks
    }


def export_page(page, html_text: str, out_dir: Path, page_key: str | None = None) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    data = html_to_page_dict(page, html_text)
    slug_name = page.slug.replace(".html", ".json")
    out_file = out_dir / slug_name
    out_file.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    if page_key and page_key != slug_name.replace(".json", ""):
        alias_file = out_dir / f"{page_key}.json"
        alias_file.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    return out_file


def export_glossary(out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / "glossary.json"
    out_file.write_text(json.dumps(G, indent=2, ensure_ascii=False), encoding="utf-8")
    return out_file
