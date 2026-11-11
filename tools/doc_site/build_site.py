"""
build_site.py - build the printable documentation site into docs/documentation_site/.

    hulikamote_backend/venv/Scripts/python.exe tools/doc_site/build_site.py            # all pages
    hulikamote_backend/venv/Scripts/python.exe tools/doc_site/build_site.py datasets   # one page

Numbers, tables and code are read from the repository when this runs (dataset cards, training runs, the tests index,
the source files), so the site matches the code of the day. Re-run after the code or the data changes.
Print: open a page in a browser and print to PDF (A4). Tooltips become the "Terms used on this page" list.
"""
from __future__ import annotations

import html.parser
import importlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import export_json  # noqa: E402
import lib  # noqa: E402

PAGES = {
    "index": "content_start",
    "datasets": "content_datasets",
    "models": "content_models",
    "pipeline": "content_pipeline",
    "violations": "content_violations",
    "qa": "content_qa",
    "live": "content_live",
}


class _Balance(html.parser.HTMLParser):
    VOID = {"meta", "link", "br", "img", "hr", "input", "col", "line", "rect", "path", "circle", "polyline", "polygon", "ellipse"}

    def __init__(self):
        super().__init__()
        self.stack, self.errors = [], []

    def handle_starttag(self, tag, attrs):
        if tag not in self.VOID:
            self.stack.append(tag)

    def handle_startendtag(self, tag, attrs):
        pass

    def handle_endtag(self, tag):
        if tag in self.VOID:
            return
        if not self.stack or self.stack[-1] != tag:
            self.errors.append(f"</{tag}> closes {self.stack[-1] if self.stack else 'nothing'}")
            if tag in self.stack:
                while self.stack and self.stack[-1] != tag:
                    self.stack.pop()
                self.stack.pop()
        else:
            self.stack.pop()


def check_html(name: str, text: str) -> list[str]:
    b = _Balance()
    b.feed(text)
    problems = b.errors[:5] + ([f"unclosed: {b.stack[:5]}"] if b.stack else [])
    return [f"{name}: {p}" for p in problems]


def main() -> int:
    wanted = sys.argv[1:] or list(PAGES)
    (lib.OUT / "assets").mkdir(parents=True, exist_ok=True)
    (lib.OUT / "assets" / "site.css").write_text(lib.CSS, encoding="utf-8")
    data_dir = lib.OUT / "data"
    export_json.export_glossary(data_dir)
    bad = []
    for key in wanted:
        module = importlib.import_module(PAGES[key])
        page = module.build()
        text = page.render()
        (lib.OUT / page.slug).write_text(text, encoding="utf-8")
        export_json.export_page(page, text, data_dir, page_key=key)
        bad += check_html(page.slug, text)
        print(f"built {page.slug}  ({len(text) // 1024} KB)")
    for line in bad:
        print("HTML PROBLEM:", line)
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
