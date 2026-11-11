"""
lib.py - the building blocks of the documentation site: page shell, tooltips, code blocks that quote the real
source (with true line numbers and an Open-in-VS-Code link), tables, charts and diagrams (inline SVG).

Nothing here is typed from memory: code is cut out of the files by symbol name (so line numbers follow the code),
and scores / counts are read from the dataset cards, run folders and the tests index by the content modules.
"""
from __future__ import annotations

import ast
import csv
import html
import json
import re
from datetime import date
from pathlib import Path

import yaml

from glossary import G

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "documentation_site"
ABS = ROOT.as_posix()                       # for vscode://file/<abs path>:<line> links
TODAY = date.today().isoformat()

PAGES = [
    ("index.html", "Start", "Start here"),
    ("1-datasets.html", "1", "Datasets"),
    ("2-models.html", "2", "Models"),
    ("3-training-pipeline.html", "3", "Training pipeline"),
    ("4-violations.html", "4", "Violations"),
    ("5-qa.html", "5", "Q&A"),
    ("6-live-camera.html", "6", "Live camera"),
]


def esc(s) -> str:
    return html.escape(str(s), quote=True)


# ── tooltips ──────────────────────────────────────────────────────────────────
_GLOSS_KEYS = {k.lower(): k for k in G}
_TERM_RE = re.compile(r"\[\[([^\[\]|]+?)(?:\|([^\[\]]+?))?\]\]")


def resolve_terms(text: str, used: set[str]) -> str:
    def sub(m: re.Match) -> str:
        key = m.group(1).strip()
        canon = _GLOSS_KEYS.get(key.lower())
        if canon is None:
            raise KeyError(f"Term '{key}' is not in glossary.py (page text: ...{text[max(0, m.start() - 40):m.end() + 20]}...)")
        used.add(canon)
        shown = m.group(2) or key
        return f'<span class="term" tabindex="0" data-key="{esc(canon)}" data-tip="{esc(G[canon])}">{shown}</span>'
    return _TERM_RE.sub(sub, text)


# ── code blocks ───────────────────────────────────────────────────────────────
_KW = set("""and as assert async await break class continue def del elif else except finally for from global if import in is
lambda nonlocal not or pass raise return try while with yield True False None""".split())
_BUILTIN = set("""abs all any bool dict enumerate float int isinstance len list max min open print range reversed round set sorted
str sum tuple zip getattr setdefault self cls""".split())
_TOK = re.compile(r'''
   (?P<tq>[rRbBfF]{0,2}(?:"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'))
 | (?P<com>\#[^\n]*)
 | (?P<str>[rRbBfF]{0,2}"(?:\\.|[^"\\\n])*"|[rRbBfF]{0,2}'(?:\\.|[^'\\\n])*')
 | (?P<num>\b\d+(?:\.\d+)?\b)
 | (?P<id>[A-Za-z_][A-Za-z_0-9]*)
''', re.X)


def _tokens(src: str):
    """[(css class or '', text)] covering src; classes: doc str com num kw bi fn cls."""
    out, pos, prev_kw = [], 0, None
    for m in _TOK.finditer(src):
        if m.start() > pos:
            out.append(("", src[pos:m.start()]))
        kind, text = m.lastgroup, m.group()
        if kind == "tq":
            out.append(("doc", text))
        elif kind == "id":
            if text in _KW:
                out.append(("kw", text))
            elif prev_kw == "def":
                out.append(("fn", text))
            elif prev_kw == "class":
                out.append(("cls", text))
            elif text in _BUILTIN:
                out.append(("bi", text))
            else:
                out.append(("", text))
            prev_kw = text if text in ("def", "class") else None
        else:
            out.append((kind, text))
            prev_kw = None
        pos = m.end()
    if pos < len(src):
        out.append(("", src[pos:]))
    return out


def _lines_html(src: str) -> list[str]:
    """One HTML string per source line (spans never cross a line break)."""
    lines: list[list[str]] = [[]]
    for cls, text in _tokens(src):
        parts = text.split("\n")
        for i, part in enumerate(parts):
            if i:
                lines.append([])
            if part:
                safe = esc(part).replace("[", "&#91;")           # keeps [[x]] in code from becoming tooltips
                lines[-1].append(f'<span class="t-{cls}">{safe}</span>' if cls else safe)
    return ["".join(parts) for parts in lines]


def _ast_range(path: Path, symbol: str) -> tuple[int, int]:
    text = path.read_text(encoding="utf-8")
    tree = ast.parse(text)
    if symbol == "@doc":
        first = tree.body[0]
        if isinstance(first, ast.Expr) and isinstance(getattr(first, "value", None), ast.Constant):
            return first.lineno, first.end_lineno
        raise ValueError(f"{path} has no module docstring")
    defs = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)
    nodes = tree.body
    node = None
    for part in symbol.split("."):
        node = next((n for n in nodes if isinstance(n, defs) and n.name == part), None)
        if node is None and nodes is not tree.body:       # a function nested deeper inside the parent
            parent = ast.Module(body=nodes, type_ignores=[])
            node = next((n for n in ast.walk(parent) if isinstance(n, defs) and n.name == part), None)
        if node is None:
            raise KeyError(f"{symbol} not found in {path}")
        nodes = getattr(node, "body", [])
    start = min([node.lineno] + [d.lineno for d in node.decorator_list])
    return start, node.end_lineno


_BADGES = "①②③④⑤⑥⑦⑧⑨⑩⑪⑫"


def code(path: str, symbol: str | None = None, lines: tuple[int, int] | None = None, walk=None,
         title: str = "", lang: str = "py", skip: list[tuple[int, int]] | None = None) -> str:
    """
    Quote a piece of the repository. path is relative to the repo root.
    symbol: 'Class.method' / 'function' / '@doc' (module docstring), or lines=(first, last) for other files.
    walk: [(text that appears on the line, plain-language explanation), ...] in reading order: each gets a numbered
          badge on its line and a numbered sentence under the code. A text that is not found stops the build.
    skip: [(first, last)] line ranges inside the block to leave out (shown as a '...' line).
    """
    file = ROOT / path
    if symbol and path.endswith(".py"):
        first, last = _ast_range(file, symbol)
    elif lines:
        first, last = lines
    else:
        raise ValueError(f"code({path}): give symbol= or lines=")
    src_lines = file.read_text(encoding="utf-8").splitlines()
    chunk = src_lines[first - 1:last]
    # drop blank lines at both ends, keep numbering true
    while chunk and not chunk[0].strip():
        chunk.pop(0); first += 1
    while chunk and not chunk[-1].strip():
        chunk.pop(); last -= 1
    rendered = _lines_html("\n".join(chunk))
    skipset = set()
    for a, b in skip or []:
        if isinstance(a, str):                     # (text on the first skipped line, text on the last skipped line)
            la = next((n for n in range(first, last + 1) if a in src_lines[n - 1]), None)
            lb = next((n for n in range(la or first, last + 1) if b in src_lines[n - 1]), None)
            if la is None or lb is None:
                raise KeyError(f"code({path}, {symbol}): skip markers '{a}' .. '{b}' not found")
            a, b = la, lb
        skipset.update(range(a, b + 1))

    marks: dict[int, int] = {}                     # source line number -> badge number
    explain = []
    cursor = first
    for i, (needle, why) in enumerate(walk or []):
        found = None
        for ln in list(range(cursor, last + 1)) + list(range(first, cursor)):
            if needle in src_lines[ln - 1]:
                found = ln
                break
        if found is None:
            raise KeyError(f"code({path}, {symbol}): '{needle}' is not in lines {first}-{last}")
        marks[found] = i
        cursor = found
        explain.append((i, found, why))

    body, gap = [], False
    for offset, line_html in enumerate(rendered):
        ln = first + offset
        if ln in skipset:
            if not gap:
                body.append('<span class="line gap"><span class="ln"></span><span class="lc t-com">    ...</span></span>')
                gap = True
            continue
        gap = False
        badge = f'<span class="mk" aria-label="note {marks[ln] + 1}">{_BADGES[marks[ln]]}</span>' if ln in marks else ""
        body.append(f'<span class="line{" hot" if ln in marks else ""}"><span class="ln">{ln}</span>'
                    f'<span class="lc">{line_html or " "}</span>{badge}</span>')
    link_line = first
    head = (f'<figcaption><span class="file">{esc(path)}</span><span class="rng">lines {first}-{last}</span>'
            f'<a class="open" href="vscode://file/{ABS}/{esc(path)}:{link_line}">Open in [[VS Code]] &#8599;</a></figcaption>')
    cap = f'<div class="code-title">{title}</div>' if title else ""
    ol = ""
    if explain:
        items = "".join(f'<li><span class="mk">{_BADGES[i]}</span> <span class="at">line {ln}</span> {why}</li>' for i, ln, why in explain)
        ol = f'<ol class="walk">{items}</ol>'
    joined = "".join(body)               # every .line is a block: a newline between them would double the spacing
    return f'{cap}<figure class="code">{head}<pre><code>{joined}</code></pre>{ol}</figure>'


def ref(path: str, symbol: str | None = None, line: int | None = None, label: str = "") -> str:
    """A short 'path:line' reference that opens in VS Code (for lists of where things live)."""
    if symbol and path.endswith(".py"):
        line = _ast_range(ROOT / path, symbol)[0]
    line = line or 1
    text = label or (f"{Path(path).name}" + (f" &rsaquo; {esc(symbol)}" if symbol and symbol != "@doc" else ""))
    return (f'<a class="ref" href="vscode://file/{ABS}/{esc(path)}:{line}" title="{esc(path)}:{line}">'
            f'<code>{text}</code><span class="ref-at">{esc(path)}:{line}</span></a>')


# ── tests index (which tests cover which file) ────────────────────────────────
_TI = None


def tests_info(path: str) -> dict | None:
    global _TI
    if _TI is None:
        index = next((p for p in (ROOT / "docs" / "agentic_workflows" / "project_map" / "tests_index.json",
                                  ROOT / "docs" / "project_map" / "tests_index.json") if p.exists()), None)
        _TI = json.loads(index.read_text(encoding="utf-8")) if index else {"files": {}, "tests": [], "runs": {}}
    f = _TI["files"].get(path)
    if not f:
        return None
    names = []
    sentences = []
    for idx in f.get("tests", []):
        t = _TI["tests"][idx]
        if t["file"] not in [n[0] for n in names]:
            names.append((t["file"], t["name"]))
        sentences.append(t.get("sentence") or t["name"])
    return {"coverage": f.get("coverage_pct"), "tests": f.get("tests_total", 0), "files": sorted({n[0] for n in names}),
            "sentences": sentences, "generated": _TI.get("generated", ""), "runs": _TI.get("runs", {})}


# ── small HTML helpers ────────────────────────────────────────────────────────
def table(headers: list[str], rows: list[list], cls: str = "", widths: list[str] | None = None) -> str:
    cols = ""
    if widths:
        cols = "<colgroup>" + "".join(f'<col style="width:{w}">' for w in widths) + "</colgroup>"
    head = "".join(f"<th>{h}</th>" for h in headers)
    body = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in rows)
    return f'<div class="tbl"><table class="{cls}">{cols}<thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>'


def chip(kind: str, text: str) -> str:
    icon = {"ok": "&#10003;", "warn": "!", "bad": "&#10005;", "info": "i", "off": "&ndash;"}[kind]
    return f'<span class="chip {kind}"><i aria-hidden="true">{icon}</i>{text}</span>'


def callout(kind: str, title: str, body: str) -> str:
    return f'<aside class="callout {kind}"><b>{title}</b><div>{body}</div></aside>'


def steps(items: list[str]) -> str:
    return '<ol class="steps">' + "".join(f"<li>{i}</li>" for i in items) + "</ol>"


def kv(rows: list[tuple[str, str]]) -> str:
    return '<dl class="kv">' + "".join(f"<dt>{k}</dt><dd>{v}</dd>" for k, v in rows) + "</dl>"


def num(n) -> str:
    return f"{int(n):,}"


def md_inline(s: str) -> str:
    """Escape text, then turn `code` and **bold** from the markdown cards into HTML."""
    s = esc(s).replace("&#x27;", "'")
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)


def cmd(text: str) -> str:
    """A command to type in a terminal (not a quote from the repository)."""
    return f'<pre class="cmd"><code>{esc(text)}</code></pre>'


def span(path: str, start_text: str, count: int | None = None, end_text: str | None = None) -> tuple[int, int]:
    """(first, last) line numbers of a block that begins at the first line containing start_text and runs
    `count` lines, or up to the first later line containing end_text. For yaml / json quotes."""
    lines = (ROOT / path).read_text(encoding="utf-8").splitlines()
    first = next(i for i, ln in enumerate(lines, 1) if start_text in ln)
    if count:
        return first, min(len(lines), first + count - 1)
    last = next(i for i, ln in enumerate(lines[first:], first + 1) if end_text and end_text in ln)
    return first, last


def whole(path: str) -> tuple[int, int]:
    """(1, number of lines) of a file, for code(lines=...) on yaml / json files."""
    return 1, len((ROOT / path).read_text(encoding="utf-8").splitlines())


# ── data readers shared by the content modules ───────────────────────────────
def md_tables(text: str) -> list[tuple[str, list[dict]]]:
    """[(heading above the table, [row dicts])] for every markdown table in text."""
    out, heading, i, lines = [], "", 0, text.splitlines()
    while i < len(lines):
        ln = lines[i]
        if ln.startswith("#"):
            heading = ln.lstrip("# ").strip()
        if ln.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s:|-]+\|$", lines[i + 1].strip()):
            cols = [c.strip() for c in ln.strip().strip("|").split("|")]
            rows, j = [], i + 2
            while j < len(lines) and lines[j].startswith("|"):
                cells = [c.strip() for c in lines[j].strip().strip("|").split("|")]
                rows.append(dict(zip(cols, cells)))
                j += 1
            out.append((heading, rows))
            i = j
            continue
        i += 1
    return out


def card(model: str) -> dict:
    """Parse datasets/<model>/DATASET_CARD.md: contents table, sources table, limits, cleaning log, classes line."""
    text = (ROOT / "training_lab" / "datasets" / model / "DATASET_CARD.md").read_text(encoding="utf-8")
    tables = dict(md_tables(text))
    limits = re.search(r"## Known limits\n\n(.*?)\n\n## ", text, re.S)
    clean = re.search(r"## Cleaning log\n\n(.*?)\n\n## ", text, re.S)
    return {
        "contents": tables.get("Contents", []),
        "sources": tables.get("Where the pictures come from", []),
        "limits": [l[2:] for l in limits.group(1).splitlines()] if limits else [],
        "cleaning": clean.group(1) if clean else "",
        "text": text,
    }


def manifest() -> dict:
    return yaml.safe_load((ROOT / "training_lab" / "configs" / "datasets_manifest.yaml").read_text(encoding="utf-8"))


def run_summary(model: str, run: str) -> dict:
    """Facts of one training run from its args.yaml and results.csv (nothing typed by hand)."""
    folder = ROOT / "training_lab" / "runs" / model / run
    args = yaml.safe_load((folder / "args.yaml").read_text(encoding="utf-8")) if (folder / "args.yaml").exists() else {}
    rows = []
    if (folder / "results.csv").exists():
        with open(folder / "results.csv", newline="", encoding="utf-8") as f:
            rows = [{k.strip(): v.strip() for k, v in r.items()} for r in csv.DictReader(f)]
    def fval(r, k):
        return float(r.get(k, 0) or 0)
    best = max(rows, key=lambda r: 0.1 * fval(r, "metrics/mAP50(B)") + 0.9 * fval(r, "metrics/mAP50-95(B)")) if rows else None
    last = rows[-1] if rows else None
    return {
        "args": args, "epochs_done": len(rows),
        "best": {"epoch": int(float(best["epoch"])) if best and best["epoch"] != "" else None,
                 "P": fval(best, "metrics/precision(B)"), "R": fval(best, "metrics/recall(B)"),
                 "map50": fval(best, "metrics/mAP50(B)"), "map5095": fval(best, "metrics/mAP50-95(B)")} if best else None,
        "last": {"epoch": int(float(last["epoch"])), "map50": fval(last, "metrics/mAP50(B)"),
                 "map5095": fval(last, "metrics/mAP50-95(B)")} if last else None,
        "curve": [(i + 1, fval(r, "metrics/mAP50(B)")) for i, r in enumerate(rows)],
        "curve95": [(i + 1, fval(r, "metrics/mAP50-95(B)")) for i, r in enumerate(rows)],
    }


# ── SVG charts and diagrams ───────────────────────────────────────────────────
_DEFS = ('<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
         '<path d="M0 0L10 5L0 10z" class="ahp"/></marker></defs>')


def svg(w: int, h: int, inner: str, label: str, cls: str = "viz", ir: dict | None = None) -> str:
    extra = f" data-ir='{esc(json.dumps(ir))}'" if ir is not None else ""
    return (f'<svg class="{cls}" viewBox="0 0 {w} {h}" role="img" aria-label="{esc(label)}"{extra} '
            f'xmlns="http://www.w3.org/2000/svg">{_DEFS}{inner}</svg>')


def figure(svg_html: str, caption: str) -> str:
    return f'<figure class="fig">{svg_html}<figcaption>{caption}</figcaption></figure>'


def _text(x, y, s, cls="", anchor="start", extra=""):
    return f'<text x="{x}" y="{y}" class="{cls}" text-anchor="{anchor}" {extra}>{esc(s)}</text>'


def box(x, y, w, h, lines, cls="", title=None, sub=None) -> str:
    """A rounded box with centred text lines (first line bold when title is True via cls 'b')."""
    out = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="9" class="bx {cls}"/>']
    ys = y + h / 2 - (len(lines) - 1) * 8 + 4
    for i, ln in enumerate(lines):
        c = "bt" if (i == 0 and title is not False and len(lines) > 1) else "bs"
        out.append(_text(x + w / 2, ys + i * 16, ln, c, "middle"))
    return "".join(out)


def arrow(x1, y1, x2, y2, label="", dashed=False, lx=None, ly=None) -> str:
    d = ' stroke-dasharray="5 4"' if dashed else ""
    out = f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" class="ar"{d} marker-end="url(#ah)"/>'
    if label:
        out += _text(lx if lx is not None else (x1 + x2) / 2, ly if ly is not None else (y1 + y2) / 2 - 6, label, "al", "middle")
    return out


def hbar(groups, series, *, w=760, label_w=200, vmax=None, fmt=num, aria="") -> str:
    """Grouped horizontal bars. groups = [(label, [value per series])]; series = [name]."""
    n = len(series)
    bar_h, gap = 11, 3
    row_h = n * (bar_h + gap) + 12
    top = 30
    vmax = vmax or max(max(v) for _, v in groups) or 1
    plot_w = w - label_w - 70
    inner = []
    x = label_w
    for i, name in enumerate(series):                      # legend (a single series needs none)
        if n > 1:
            inner.append(f'<rect x="{x}" y="8" width="11" height="11" rx="2" class="f{i + 1}"/>')
            inner.append(_text(x + 16, 18, name, "lg"))
            x += 28 + 7 * len(name)
    inner.append(f'<line x1="{label_w}" y1="{top - 6}" x2="{label_w}" y2="{top + len(groups) * row_h}" class="axis"/>')
    for gi, (label, vals) in enumerate(groups):
        y0 = top + gi * row_h
        inner.append(_text(label_w - 10, y0 + (n * (bar_h + gap)) / 2 + 3, label, "yl", "end"))
        for si, v in enumerate(vals):
            bw = max(1.5, plot_w * v / vmax) if v else 0
            y = y0 + si * (bar_h + gap)
            inner.append(f'<rect x="{label_w + 1}" y="{y}" width="{bw:.1f}" height="{bar_h}" rx="3" class="f{si + 1}"><title>{esc(label)} - {esc(series[si])}: {fmt(v)}</title></rect>')
            inner.append(_text(label_w + bw + 6, y + bar_h - 2, fmt(v), "vl"))
    h = top + len(groups) * row_h + 4
    ir_data = {
        "kind": "hbar",
        "groups": [{"label": label, "values": [float(v) for v in vals]} for label, vals in groups],
        "series": list(series),
        "vmax": float(vmax),
        "label_w": label_w,
        "w": w,
        "aria": aria or "bar chart",
    }
    return svg(w, h, "".join(inner), aria or "bar chart", ir=ir_data)


def linechart(series, *, w=760, h=330, xmax=100, ymax=1.0, ylabel="", xlabel="epoch", hlines=None, aria="") -> str:
    """series = [(name, [(x, y), ...])]. Thin lines, end-of-line labels, recessive grid."""
    l, r, t, b = 52, 150, 16, 40
    pw, ph = w - l - r, h - t - b
    def X(v): return l + pw * v / xmax
    def Y(v): return t + ph * (1 - v / ymax)
    inner = []
    for k in range(0, 6):
        yv = ymax * k / 5
        inner.append(f'<line x1="{l}" y1="{Y(yv):.1f}" x2="{l + pw}" y2="{Y(yv):.1f}" class="grid"/>')
        inner.append(_text(l - 8, Y(yv) + 4, f"{yv:.1f}", "yl", "end"))
    step = 20 if xmax >= 60 else 10
    for xv in range(0, int(xmax) + 1, step):
        inner.append(_text(X(xv), t + ph + 18, str(xv), "yl", "middle"))
    inner.append(f'<line x1="{l}" y1="{t + ph}" x2="{l + pw}" y2="{t + ph}" class="axis"/>')
    inner.append(_text(l + pw / 2, h - 4, xlabel, "yl", "middle"))
    inner.append(_text(12, t + ph / 2, ylabel, "yl", "middle", f'transform="rotate(-90 12 {t + ph / 2})"'))
    for val, name in hlines or []:
        inner.append(f'<line x1="{l}" y1="{Y(val):.1f}" x2="{l + pw}" y2="{Y(val):.1f}" class="target" stroke-dasharray="6 4"/>')
        inner.append(_text(l + pw + 4, Y(val) + 4, name, "tl"))
    ends = []
    for si, (name, pts) in enumerate(series):
        if not pts:
            continue
        d = " ".join(f"{X(x):.1f},{Y(y):.1f}" for x, y in pts)
        inner.append(f'<polyline points="{d}" class="ln s{si + 1}" fill="none"><title>{esc(name)}</title></polyline>')
        ends.append((Y(pts[-1][1]), X(pts[-1][0]), name, si))
    ends.sort()
    last = -99
    for y, x, name, si in ends:                    # direct labels at the line ends, nudged apart
        y = max(y, last + 14)
        last = y
        inner.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="3" class="f{si + 1}"/>')
        inner.append(_text(x + 8, y + 4, name, "lg"))
    ir_data = {
        "kind": "line",
        "series": [{"name": name, "points": [{"x": float(x), "y": float(y)} for x, y in pts]} for name, pts in series],
        "xmax": float(xmax),
        "ymax": float(ymax),
        "xlabel": xlabel,
        "ylabel": ylabel,
        "hlines": [{"value": float(val), "name": name} for val, name in (hlines or [])],
        "w": w,
        "h": h,
        "aria": aria or "line chart",
    }
    return svg(w, h, "".join(inner), aria or "line chart", ir=ir_data)


# ── page shell ────────────────────────────────────────────────────────────────
class Page:
    def __init__(self, slug: str, number: str, title: str, lede: str):
        self.slug, self.number, self.title, self.lede = slug, number, title, lede
        self.parts: list[str] = []
        self.toc: list[tuple[str, str, int]] = []
        self.scripts: list[str] = []          # inline JavaScript, added at the end of the page (the Q&A page uses it)

    def add(self, *chunks: str) -> None:
        self.parts.extend(chunks)

    def h2(self, ident: str, title: str, kicker: str = "", newpage: bool = True) -> None:
        self.toc.append((ident, title, 2))
        k = f'<div class="kicker">{kicker}</div>' if kicker else ""
        self.parts.append(f'<section class="sec{" pb" if newpage else ""}" id="{ident}">{k}<h2>{title}</h2>')

    def h3(self, ident: str, title: str) -> None:
        self.toc.append((ident, title, 3))
        self.parts.append(f'<h3 id="{ident}">{title}</h3>')

    def end(self) -> None:
        self.parts.append("</section>")

    def render(self) -> str:
        used: set[str] = set()
        body = resolve_terms("".join(self.parts), used)
        lede = resolve_terms(self.lede, used)
        current = ' aria-current="page"'
        nav = "".join(
            f'<a href="{esc(f)}"{current if f == self.slug else ""}><b>{esc(n)}</b> {esc(t)}</a>'
            for f, n, t in PAGES)
        plain = lambda s: _TERM_RE.sub(lambda m: m.group(2) or m.group(1), s)      # no tooltips inside the contents list
        toc = "".join(f'<li class="l{lv}"><a href="#{i}">{plain(t)}</a></li>' for i, t, lv in self.toc)
        terms = "".join(f"<dt>{esc(k)}</dt><dd>{esc(G[k])}</dd>" for k in sorted(used, key=str.lower))
        n = f'<span class="pn">Page {esc(self.number)}</span>' if self.number != "Start" else ""
        terms_section = (
            '<section class="sec pb terms" id="terms"><h2>Terms used on this page</h2>\n'
            '<p class="note">On screen, hover or tab to any dotted word for its meaning. This list is the same meanings, for the printed copy.</p>\n'
            f'<dl>{terms}</dl></section>') if used else ""
        scripts_html = "".join(f"<script>{s}</script>" for s in self.scripts)
        toc_html = f'<nav class="toc" aria-label="On this page"><b>On this page</b><ol>{toc}</ol></nav>' if self.toc else ""
        return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>HULI-KAMOTE - {esc(self.title)}</title>
<link rel="stylesheet" href="assets/site.css"></head>
<body>
<header class="top"><div class="brand">HULI-KAMOTE <span>technical documentation</span></div><nav>{nav}</nav></header>
<main>
<div class="hero">{n}<h1>{self.title}</h1><p class="lede">{lede}</p></div>
{toc_html}
{body}
{terms_section}
</main>
<footer>Built {TODAY} by <code>tools/doc_site/build_site.py</code>. Numbers, tables and code are read from the repository files when the site is built, so they match the code on that date. Re-run the script after the code changes.</footer>
{scripts_html}
</body></html>"""


# ── styles ────────────────────────────────────────────────────────────────────
CSS = r"""
:root{--surface:#fcfcfb;--page:#f9f9f7;--ink:#0b0b0b;--ink2:#52514e;--muted:#6f6d68;--grid:#e1e0d9;--axis:#c3c2b7;--border:rgba(11,11,11,.12);
--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;--s4:#eda100;--s5:#e87ba4;--s6:#008300;--s7:#6250d6;--s8:#e34948;
--good:#0ca30c;--warn:#fab219;--serious:#ec835a;--crit:#d03b3b;--accent:#2a78d6;--code-bg:#f3f2ee;--c-str:#0a7a55;--c-kw:#6250d6;--c-num:#c4501f;--c-fn:#1c5cab;--soft:#eef4fc}
@media (prefers-color-scheme:dark){:root:where(:not([data-theme="light"])){--surface:#1a1a19;--page:#0d0d0d;--ink:#f0efec;--ink2:#c3c2b7;--muted:#a09e97;--grid:#2c2c2a;--axis:#383835;--border:rgba(255,255,255,.12);
--s1:#3987e5;--s2:#d95926;--s3:#199e70;--s4:#c98500;--s5:#d55181;--s6:#008300;--s7:#9085e9;--s8:#e66767;--accent:#6da7ec;--code-bg:#232322;--c-str:#3ecf9c;--c-kw:#9085e9;--c-num:#f0a070;--c-fn:#6da7ec;--soft:#18222f}}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;background:var(--page);color:var(--ink);font:16px/1.6 system-ui,-apple-system,"Segoe UI",sans-serif}
a{color:var(--accent)}code,pre{font-family:ui-monospace,Consolas,"Cascadia Mono",monospace}
.top{position:sticky;top:0;z-index:30;background:var(--surface);border-bottom:1px solid var(--border);display:flex;flex-wrap:wrap;gap:8px 24px;align-items:center;padding:10px 24px}
.brand{font-weight:700;letter-spacing:.02em}.brand span{font-weight:400;color:var(--muted);margin-left:8px;font-size:13px}
.top nav{display:flex;flex-wrap:wrap;gap:4px}.top nav a{padding:5px 12px;border-radius:999px;text-decoration:none;color:var(--ink2);font-size:14px}
.top nav a b{color:var(--accent);margin-right:2px}.top nav a[aria-current=page]{background:var(--soft);color:var(--ink);outline:1px solid var(--border)}
main{max-width:1020px;margin:0 auto;padding:24px 20px 80px}
.hero{padding:28px 0 8px}.pn{display:inline-block;font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:var(--accent);font-weight:700}
h1{font-size:38px;line-height:1.15;margin:6px 0 10px}.lede{font-size:19px;color:var(--ink2);max-width:760px;margin:0}
h2{font-size:27px;line-height:1.25;margin:0 0 12px}h3{font-size:20px;margin:26px 0 8px}h4{font-size:16px;margin:18px 0 6px}
.kicker{font-size:12px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);font-weight:700;margin-bottom:4px}
.sec{margin:46px 0 0;padding-top:6px}p{margin:10px 0;max-width:80ch}ul,ol{max-width:84ch}li{margin:4px 0}
.toc{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:12px 18px;margin:22px 0}
.toc b{font-size:13px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted)}.toc ol{margin:6px 0 0;padding-left:0;list-style:none;columns:2;column-gap:28px}
.toc li{margin:2px 0;break-inside:avoid}.toc .l3{padding-left:14px;font-size:14px}.toc a{text-decoration:none}
.term{border-bottom:1.5px dotted var(--accent);cursor:help;position:relative;white-space:nowrap}
.term:hover::after,.term:focus::after{content:attr(data-tip);position:absolute;left:0;top:1.7em;z-index:40;width:max-content;max-width:min(300px,78vw);white-space:normal;background:var(--ink);color:var(--surface);
 padding:9px 11px;border-radius:9px;font-size:13px;line-height:1.45;font-weight:400;text-align:left;box-shadow:0 6px 24px rgba(0,0,0,.25)}
.tbl{overflow-x:auto;margin:14px 0;border:1px solid var(--border);border-radius:10px;background:var(--surface)}
table{border-collapse:collapse;width:100%;font-size:14px}th,td{padding:8px 11px;border-bottom:1px solid var(--grid);text-align:left;vertical-align:top}
th{font-size:12px;letter-spacing:.05em;text-transform:uppercase;color:var(--muted);background:var(--page);position:sticky;top:0}tr:last-child td{border-bottom:0}
td.n,th.n{text-align:right;font-variant-numeric:tabular-nums}table.dense td,table.dense th{padding:5px 8px;font-size:13px}
.chip{display:inline-flex;gap:5px;align-items:center;font-size:12px;font-weight:600;padding:2px 9px 2px 6px;border-radius:999px;border:1px solid var(--border);white-space:nowrap;background:var(--surface)}
.chip i{font-style:normal;display:inline-grid;place-items:center;width:15px;height:15px;border-radius:50%;font-size:10px;color:#fff;font-weight:800}
.chip.ok i{background:var(--good)}.chip.warn i{background:#b07a00}.chip.bad i{background:var(--crit)}.chip.info i{background:var(--s1)}.chip.off i{background:var(--muted)}
.callout{border:1px solid var(--border);border-left:5px solid var(--s1);border-radius:10px;padding:10px 16px;margin:16px 0;background:var(--surface);max-width:90ch}
.callout.warn{border-left-color:#b07a00}.callout.bad{border-left-color:var(--crit)}.callout.ok{border-left-color:var(--good)}.callout b{display:block;margin-bottom:2px}.callout div>p:first-child{margin-top:0}
.steps{counter-reset:s;list-style:none;padding:0;margin:14px 0}.steps li{counter-increment:s;position:relative;padding:4px 0 4px 40px;margin:6px 0}
.steps li::before{content:counter(s);position:absolute;left:0;top:3px;width:27px;height:27px;border-radius:50%;background:var(--soft);border:1px solid var(--accent);color:var(--ink);display:grid;place-items:center;font-weight:700;font-size:13px}
.kv{display:grid;grid-template-columns:max-content 1fr;gap:5px 18px;margin:12px 0;font-size:15px}.kv dt{color:var(--muted);font-weight:600}.kv dd{margin:0}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:12px;margin:16px 0}.mini{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:12px 15px}.mini b{display:block}
figure{margin:0}.fig{margin:18px 0;background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:14px 14px 8px}.fig figcaption{font-size:13px;color:var(--ink2);padding:6px 4px}
svg.viz{width:100%;height:auto;display:block}svg text{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;fill:var(--ink2);font-size:12.5px}
svg .bt{fill:var(--ink);font-weight:700;font-size:13px}svg .bs{fill:var(--ink2);font-size:12px}svg .yl{fill:var(--muted);font-size:12px}svg .vl{fill:var(--ink);font-size:12px;font-variant-numeric:tabular-nums}
svg .lg{fill:var(--ink);font-size:12.5px}svg .al{fill:var(--muted);font-size:11.5px}svg .tl{fill:var(--muted);font-size:11.5px}svg .sk{fill:var(--muted);font-size:11px}
svg .grid{stroke:var(--grid);stroke-width:1}svg .axis{stroke:var(--axis);stroke-width:1.2}svg .target{stroke:var(--muted);stroke-width:1.2}svg .ar{stroke:var(--ink2);stroke-width:1.6;fill:none}svg .ahp{fill:var(--ink2)}
svg .ln{stroke-width:2.2;stroke-linejoin:round}svg .s1{stroke:var(--s1)}svg .s2{stroke:var(--s2)}svg .s3{stroke:var(--s3)}svg .s4{stroke:var(--s4)}svg .s5{stroke:var(--s5)}
svg .f1{fill:var(--s1)}svg .f2{fill:var(--s2)}svg .f3{fill:var(--s3)}svg .f4{fill:var(--s4)}svg .f5{fill:var(--s5)}svg .f6{fill:var(--s6)}svg .f7{fill:var(--s7)}svg .f8{fill:var(--s8)}
svg .bx{fill:var(--surface);stroke:var(--axis);stroke-width:1.3}
svg .bx.c1{fill:color-mix(in srgb,var(--s1) 14%,var(--surface));stroke:var(--s1)}svg .bx.c2{fill:color-mix(in srgb,var(--s2) 14%,var(--surface));stroke:var(--s2)}
svg .bx.c3{fill:color-mix(in srgb,var(--s3) 14%,var(--surface));stroke:var(--s3)}svg .bx.c4{fill:color-mix(in srgb,var(--s4) 16%,var(--surface));stroke:var(--s4)}
svg .bx.c7{fill:color-mix(in srgb,var(--s7) 13%,var(--surface));stroke:var(--s7)}svg .bx.c8{fill:color-mix(in srgb,var(--s8) 13%,var(--surface));stroke:var(--s8)}
svg .bx.dash{stroke-dasharray:5 4}svg .road{fill:color-mix(in srgb,var(--ink) 8%,var(--surface));stroke:var(--axis)}svg .zone{fill:color-mix(in srgb,var(--s1) 18%,transparent);stroke:var(--s1);stroke-width:2}
svg .veh{fill:color-mix(in srgb,var(--s2) 22%,var(--surface));stroke:var(--s2);stroke-width:2}svg .ok{fill:none;stroke:var(--good);stroke-width:2.4}svg .no{fill:none;stroke:var(--crit);stroke-width:2.4}
svg .per{fill:color-mix(in srgb,var(--s7) 25%,var(--surface));stroke:var(--s7);stroke-width:1.6}svg .path{fill:none;stroke:var(--ink2);stroke-width:2.4;stroke-dasharray:6 4}
svg .a-ok{stroke:var(--good);stroke-width:3.2}svg .a-okh{fill:var(--good)}svg .a-no{stroke:var(--crit);stroke-width:3.2}svg .a-noh{fill:var(--crit)}svg .a-in{stroke:var(--ink2);stroke-width:2.4;fill:none}svg .a-inh{fill:var(--ink2)}
svg .veh.dash{stroke-dasharray:6 4}
.sketch{max-width:340px;margin:0 auto}
figure.code{margin:8px 0 18px;border:1px solid var(--border);border-radius:10px;background:var(--code-bg);overflow:hidden}
figure.code figcaption{display:flex;flex-wrap:wrap;gap:4px 14px;align-items:center;padding:7px 12px;background:var(--surface);border-bottom:1px solid var(--border);font-size:12.5px}
.file{font-family:ui-monospace,Consolas,monospace;font-weight:600}.rng{color:var(--muted)}.open{margin-left:auto;font-weight:600;text-decoration:none}.code-title{font-weight:700;font-size:14px;margin:16px 0 0}
pre{margin:0;padding:10px 0;overflow-x:auto;font-size:12.6px;line-height:1.55}pre code{display:block;min-width:max-content}
.line{display:block;padding-right:16px;white-space:pre}.line.hot{background:color-mix(in srgb,var(--s4) 14%,transparent)}.ln{display:inline-block;width:3.4em;padding-right:1em;text-align:right;color:var(--muted);user-select:none}
.mk{display:inline-grid;place-items:center;min-width:1.5em;color:var(--accent);font-weight:700;font-family:system-ui,sans-serif;margin-left:10px;user-select:none}
.t-kw{color:var(--c-kw);font-weight:600}.t-str{color:var(--c-str)}.t-num{color:var(--c-num)}.t-com{color:var(--muted);font-style:italic}.t-doc{color:var(--muted)}.t-fn,.t-cls{color:var(--c-fn);font-weight:700}.t-bi{color:var(--c-fn)}
ol.walk{margin:0;padding:10px 16px 12px 16px;list-style:none;border-top:1px solid var(--border);background:var(--surface);font-size:14.5px;max-width:none}ol.walk li{margin:5px 0}.at{font-size:12px;color:var(--muted);margin:0 4px}
a.ref{display:inline-flex;flex-direction:column;text-decoration:none;border:1px solid var(--border);border-radius:8px;padding:4px 10px;margin:3px 6px 3px 0;background:var(--surface)}
a.ref code{font-size:13px;font-weight:600}.ref-at{font-size:11px;color:var(--muted);font-family:ui-monospace,Consolas,monospace}
.vcard{border:1px solid var(--border);border-radius:14px;background:var(--surface);padding:6px 22px 18px;margin:28px 0}.vcard>header{display:flex;flex-wrap:wrap;gap:10px 18px;align-items:center;margin:16px 0 4px}
.vcard h3{margin:0;font-size:24px}.vkey{font-family:ui-monospace,Consolas,monospace;color:var(--muted);font-size:13px}
.vgrid{display:grid;grid-template-columns:minmax(0,1fr) 340px;gap:6px 26px}.vgrid>div{min-width:0}@media (max-width:820px){.vgrid{grid-template-columns:1fr}}
.pillrow{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0}.pill{font-size:12px;padding:2px 10px;border:1px solid var(--border);border-radius:999px;background:var(--page);color:var(--ink2)}
.qa{border:1px solid var(--border);border-radius:10px;padding:8px 16px;margin:8px 0;background:var(--surface)}.qa summary{cursor:pointer}.qa p{margin:6px 0 4px}
.qa-bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:14px 0 6px}.qa-in.qa-search{flex:1 1 220px;min-width:180px;width:auto}.qa-in.qa-select{width:auto}
.qa-in{font:inherit;color:var(--ink);background:var(--surface);border:1px solid var(--axis);border-radius:8px;padding:8px 10px;width:100%}.qa-in:focus{outline:2px solid var(--accent);outline-offset:1px}
textarea.qa-in{resize:vertical;line-height:1.5;font-family:ui-monospace,Consolas,monospace;font-size:14px}
.qa-btn{font:inherit;font-size:14px;font-weight:600;cursor:pointer;color:var(--ink);background:var(--surface);border:1px solid var(--axis);border-radius:8px;padding:7px 14px}.qa-btn:hover{background:var(--soft)}
.qa-btn.primary{background:var(--accent);border-color:var(--accent);color:#fff}.qa-btn.primary:hover{filter:brightness(1.1)}.qa-btn.small{padding:4px 10px;font-size:13px}.qa-btn.danger{color:var(--crit)}
.qa-status{font-size:14px;padding:8px 12px;border-radius:8px;border:1px solid var(--border);border-left:5px solid var(--axis);background:var(--surface);margin:12px 0 0}
.qa-status.ok{border-left-color:var(--good)}.qa-status.warn{border-left-color:#b07a00}.qa-status.bad{border-left-color:var(--crit)}
.qa-count{display:block;margin:10px 2px 4px;color:var(--ink2);font-size:14px}.qa-tagbar{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:4px 0 12px}
button.pill{font:inherit;font-size:12px;cursor:pointer;color:var(--ink2)}button.pill:hover,button.pill.on{background:var(--soft);border-color:var(--accent);color:var(--ink)}
.qa-card{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:12px 18px;margin:12px 0}.qa-card>header{display:flex;gap:12px;align-items:flex-start;justify-content:space-between}
.qa-card h3{margin:2px 0 6px;font-size:18px}.qa-card footer{display:flex;flex-wrap:wrap;gap:8px 14px;align-items:center;max-width:none;margin:8px 0 0;padding:8px 0 0;font-size:inherit;color:inherit;border-top:1px solid var(--grid)}.qa-row{margin-left:auto;display:flex;gap:6px}.qa-tags{display:flex;gap:6px;flex-wrap:wrap}
.qa-md{max-width:80ch;overflow-wrap:anywhere}.qa-md p{margin:6px 0}.qa-md h3,.qa-md h4,.qa-md h5,.qa-md h6{margin:12px 0 4px;font-size:16px}.qa-md pre{background:var(--code-bg);border:1px solid var(--border);border-radius:8px;padding:8px 12px;overflow-x:auto;font-size:13px}.qa-md code{background:var(--code-bg);border-radius:4px;padding:1px 5px;font-size:.92em}.qa-md pre code{background:none;padding:0}.qa-md blockquote{margin:8px 0;padding:2px 14px;border-left:4px solid var(--axis);color:var(--ink2)}.qa-md ul,.qa-md ol{margin:6px 0;padding-left:24px}
.qa-edit{border-color:var(--accent)}.qa-label{display:block;font-size:12px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;color:var(--muted);margin:10px 0 4px}.qa-labelrow{display:flex;justify-content:space-between;align-items:flex-end}
.qa-tabs{display:flex;gap:2px}.qa-tab{font:inherit;font-size:13px;cursor:pointer;border:1px solid var(--axis);background:var(--surface);color:var(--ink2);padding:3px 12px;border-radius:8px 8px 0 0}.qa-tab.on{background:var(--soft);color:var(--ink);font-weight:700}
.qa-preview{min-height:8em;border:1px solid var(--axis);border-radius:8px;padding:8px 12px;background:var(--surface)}.qa-actions{display:flex;gap:10px;align-items:center;margin-top:12px}
.qa-help summary{cursor:pointer;font-weight:600}.qa-help pre.cmd{margin:6px 0}
pre.cmd{background:var(--code-bg);border:1px solid var(--border);border-radius:8px;padding:9px 14px;margin:10px 0;font-size:13px;max-width:100%}
.terms dt{font-weight:700;margin-top:10px}.terms dd{margin:0 0 0 0;color:var(--ink2)}.note{color:var(--ink2);font-size:14px}
footer{max-width:1020px;margin:0 auto;padding:10px 20px 50px;color:var(--muted);font-size:13px}
.heat td.y{background:color-mix(in srgb,var(--s1) 22%,var(--surface));text-align:center;font-weight:700}.heat td.m{background:color-mix(in srgb,var(--s4) 22%,var(--surface));text-align:center}.heat td.o{text-align:center;color:var(--muted)}
@media (max-width:700px){h1{font-size:30px}.toc ol{columns:1}.top{padding:8px 14px}main{padding:16px 14px 60px}}
@media print{
 :root{--surface:#fff;--page:#fff;--ink:#000;--ink2:#333;--muted:#555;--grid:#ddd;--axis:#aaa;--border:rgba(0,0,0,.25);--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;--s4:#eda100;--s5:#e87ba4;--s6:#008300;--s7:#6250d6;--s8:#e34948;--code-bg:#f6f6f4;--c-str:#0a7a55;--c-kw:#6250d6;--c-num:#c4501f;--c-fn:#1c5cab;--soft:#eef4fc}
 @page{size:A4;margin:14mm 12mm 16mm}body{font-size:10.5pt;background:#fff}.top,.toc,.note,footer{display:none}.hero{padding-top:0}h1{font-size:24pt}h2{font-size:17pt}
 .noprint,.qa-bar,.qa-tagbar,.qa-status,.qa-help{display:none!important}.qa-card{break-inside:avoid;border:0;border-bottom:1px solid #ccc;border-radius:0;padding:6px 0}
 .sec.pb{break-before:page}.term{border:0}.term::after{display:none!important}.open{display:none}figure,.vcard>header,.callout,.mini,.tbl,.steps li{break-inside:avoid}
 .vcard{border:0;padding:0;break-before:page}pre{font-size:8.2pt;white-space:pre-wrap}pre code{min-width:0}.line{white-space:pre-wrap;word-break:break-all}a{color:inherit;text-decoration:none}
 .tbl{overflow:visible}table{font-size:9pt}.terms{break-before:page}.terms dd{font-size:9.5pt}a.ref{border:0;padding:0;display:inline}.ref-at{display:inline;margin-left:4px}
}
"""
