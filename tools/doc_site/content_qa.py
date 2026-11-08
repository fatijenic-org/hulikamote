"""Page 5 - Q&A. A small editable list of questions and answers (Markdown), saved to a local JSON file through serve.py."""
from __future__ import annotations

from pathlib import Path

from lib import Page, callout, cmd, table

HERE = Path(__file__).resolve().parent


def build() -> Page:
    p = Page("5-qa.html", "5", "Q&A",
             "The questions a panelist may ask, and your answers. Add, edit and delete them here. Answers accept Markdown. "
             "Everything is saved to a JSON file on this computer and goes nowhere else.")

    p.add('<div class="qa-help noprint"><details><summary>How saving works, and how to start it</summary>')
    p.add("<p>A web page cannot write a file by itself, so a tiny local server does it. It runs only on this computer "
          "(<code>127.0.0.1</code>), writes only <code>tools/doc_site/data/qa.json</code>, and keeps the previous version as <code>qa.json.bak</code>. "
          "Start it once, then open the page at the address it prints:</p>")
    p.add(cmd("hulikamote_backend/venv/Scripts/python.exe tools/doc_site/serve.py --open"))
    p.add("<p>Without the server (page opened straight from disk), the page still works: changes are kept in this browser, and "
          "<b>Export JSON</b> / <b>Import JSON</b> let you save and load a file by hand. The green or yellow bar below tells you which mode you are in.</p>")
    p.add(table(["Type this", "To get"], [
        ["<code>**bold**</code> &nbsp; <code>*italic*</code> &nbsp; <code>~~gone~~</code>", "<b>bold</b> &nbsp; <i>italic</i> &nbsp; <s>gone</s>"],
        ["<code>`code`</code>", "<code>code</code> (inline)"],
        ["<code># Heading</code>", "a heading (also <code>##</code>, <code>###</code>)"],
        ["<code>- item</code> or <code>1. item</code>", "a bullet list or a numbered list (<code>- [ ]</code> and <code>- [x]</code> make a checklist)"],
        ["<code>&gt; quote</code>", "an indented quote"],
        ["<code>[words](https://example.com)</code>", "a link (only http and https links work)"],
        ["three backticks on their own line, then code, then three backticks", "a code block"],
        ["<code>| a | b |</code> then <code>| --- | --- |</code> then rows", "a table"],
        ["<code>---</code>", "a dividing line"],
    ], "dense", ["46%", "54%"]))
    p.add("</details></div>")

    p.add('<div id="qa-app"><p class="note">Loading the questions...</p></div>'
          '<noscript><p>This page needs JavaScript to show and edit the questions.</p></noscript>')

    p.scripts.append((HERE / "qa_app.js").read_text(encoding="utf-8"))
    return p
