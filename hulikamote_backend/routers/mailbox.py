"""
mailbox.py - the laptop's mailbox as a small web page. A phone on the same Wi-Fi or hotspot opens
http://<laptop address>:8000/mailbox in its browser; no app, no internet, no e-mail account needed.
"""
from datetime import datetime
from html import escape
from urllib.parse import quote

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

import store

router = APIRouter(tags=["mailbox"])

PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="5"><title>{title}</title>
<style>
:root {{ color-scheme: light dark; --line: #8886; --accent: #2f6bff; }}
body {{ margin: 0; font: 16px/1.5 system-ui, sans-serif; }}
main {{ max-width: 640px; margin: 0 auto; padding: 16px; }}
h1 {{ font-size: 1.3rem; margin: 0 0 4px; }} p.hint {{ opacity: .7; margin: 0 0 16px; font-size: .9rem; }}
a.row, article {{ display: block; border: 1px solid var(--line); border-radius: 12px; padding: 12px 16px; margin: 0 0 12px; color: inherit; text-decoration: none; }}
a.row {{ display: flex; justify-content: space-between; font-weight: 600; }} a.row span {{ opacity: .7; font-weight: 400; }}
article h2 {{ font-size: 1rem; margin: 0; }} time {{ opacity: .7; font-size: .85rem; }}
pre {{ white-space: pre-wrap; font: inherit; margin: 8px 0 0; }} .back {{ color: var(--accent); }}
.frames {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 8px; margin-top: 12px; }}
.frames img {{ width: 100%; aspect-ratio: 16 / 10; object-fit: cover; border-radius: 8px; display: block; }}
</style></head><body><main>{body}</main></body></html>"""


def _page(title: str, body: str) -> HTMLResponse:
    return HTMLResponse(PAGE.format(title=escape(title), body=body))


def _when(iso: str) -> str:
    try:
        return datetime.fromisoformat(iso).astimezone().strftime("%b %d, %I:%M:%S %p")
    except ValueError:
        return iso


def _frames(names: list[str]) -> str:
    """The ticket's photos, each opening full size when tapped."""
    if not names:
        return ""
    tiles = "".join(
        f'<a href="/snapshots/evidence/{quote(n)}"><img loading="lazy" alt="Photo {i}" src="/snapshots/evidence/{quote(n)}"></a>'
        for i, n in enumerate(names, 1)
    )
    return f'<div class="frames">{tiles}</div>'


@router.get("/mailbox", response_class=HTMLResponse)
async def choose_motorist():
    counts: dict[str, int] = {}
    for n in await store.list_notices(limit=200):
        counts[n["user_id"]] = counts.get(n["user_id"], 0) + 1
    rows = "".join(
        f'<a class="row" href="/mailbox/{quote(m["id"])}">{escape(m["name"])}<span>{counts.get(m["id"], 0)} notices</span></a>'
        for m in await store.list_registry()
    )
    return _page("HULI-KAMOTE mailbox", f'<h1>HULI-KAMOTE mailbox</h1><p class="hint">Tap your name.</p>{rows}')


@router.get("/mailbox/{user_id}", response_class=HTMLResponse)
async def inbox(user_id: str):
    owner = await store.get_user_by_id(user_id)
    if not owner:
        return _page("Not found", '<h1>No such motorist</h1><a class="back" href="/mailbox">Back</a>')
    cards = "".join(
        f'<article><h2>{escape(n["subject"])}</h2><time>{escape(_when(n["created_at"]))}</time><pre>{escape(n["body"])}</pre>'
        f'{_frames(n["frames"])}</article>'
        for n in await store.list_notices(user_id)
    ) or '<p class="hint">No notices yet. This page refreshes by itself.</p>'
    return _page(f"{owner['name']} - mailbox",
                 f'<a class="back" href="/mailbox">All motorists</a><h1>{escape(owner["name"])}</h1>'
                 f'<p class="hint">Updates by itself every few seconds.</p>{cards}')
