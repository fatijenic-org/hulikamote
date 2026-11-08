"""
store.py - Data access layer (Phase 4: SQLite).
Supports 3 mock users. Violations are user-scoped.
FCM tokens are user-scoped so pushes only go to the right phone.
USE_MOCK = True  → mock stream violations
USE_MOCK = False → real ONNX inference (Phase 5)
"""
import asyncio
import os
import uuid
import random
import json
from datetime import datetime, timezone

import firebase_admin
from firebase_admin import credentials, messaging

import cloud
import database as db
import emailer
import evidence_files
from demerit_points import normalize_plate

# ─── Config ──────────────────────────────────────────────────────────────────

# Phase 5: flip to False when real inference is wired
USE_MOCK: bool = False

def set_mock_mode(enabled: bool):
    global USE_MOCK
    USE_MOCK = enabled

MOCK_CLASSES = ["no_helmet", "no_seatbelt", "red_light", "wrong_lane"]

# 3 mock user accounts. Password is plain-text for mock purposes only.
MOCK_USERS = [
    {
        "id": "user_001",
        "name": "Juan Dela Cruz",
        "license_no": "N01-12-345678",
        "license_type": "Professional",
        "restrictions": "1, 2, 4",
        "expiry": "10/24/2028",
        "address": "123 Rizal St., Manila",
        "password": "password123",
    },
    {
        "id": "user_002",
        "name": "Maria Santos",
        "license_no": "N02-23-456789",
        "license_type": "Non-Professional",
        "restrictions": "1, 2",
        "expiry": "05/10/2027",
        "address": "456 Mabini Ave., Quezon City",
        "password": "password123",
    },
    {
        "id": "user_003",
        "name": "Pedro Reyes",
        "license_no": "N03-34-567890",
        "license_type": "Professional",
        "restrictions": "1, 2, 3, 4",
        "expiry": "03/15/2026",
        "address": "789 Bonifacio Blvd., Makati",
        "password": "password123",
    },
]

# ─── Firebase Init ────────────────────────────────────────────────────────────

FIREBASE_KEY_PATH = os.path.join(os.path.dirname(__file__), "firebase-service-account.json")
_firebase_initialized = False

if os.path.exists(FIREBASE_KEY_PATH):
    try:
        cred = credentials.Certificate(FIREBASE_KEY_PATH)
        firebase_admin.initialize_app(cred)
        _firebase_initialized = True
        print("Firebase Admin initialized successfully.")
    except Exception as e:
        print(f"Failed to initialize Firebase Admin: {e}")
else:
    print(f"Warning: {FIREBASE_KEY_PATH} not found. Push notifications will be mocked.")

# ─── Users ────────────────────────────────────────────────────────────────────

async def get_all_users() -> list[dict]:
    rows = await db.database.fetch_all(db.users_table.select())
    return [dict(r) for r in rows]


async def get_user_by_license(license_no: str) -> dict | None:
    row = await db.database.fetch_one(
        db.users_table.select().where(db.users_table.c.license_no == license_no)
    )
    return dict(row) if row else None


async def get_user_by_id(user_id: str) -> dict | None:
    row = await db.database.fetch_one(
        db.users_table.select().where(db.users_table.c.id == user_id)
    )
    return dict(row) if row else None


async def get_user_by_plate(plate: str) -> dict | None:
    """The motorist this plate is registered to (spaces, hyphens and case do not matter), or None."""
    key = normalize_plate(plate)
    if not key:
        return None
    u, v = db.users_table, db.vehicles_table
    row = await db.database.fetch_one(u.select().select_from(u.join(v, v.c.user_id == u.c.id)).where(v.c.plate_key == key))
    return dict(row) if row else None


# ─── Registry: who owns which plate, where to e-mail them ────────────────────

DEMO_PLATES = {"user_001": "ABC 1234", "user_002": "DEF 5678", "user_003": "GHI 9012"}      # made up, for the demo


async def list_registry() -> list[dict]:
    """Every motorist with the e-mail and plates on file. Never includes the password."""
    users = await db.database.fetch_all(db.users_table.select().order_by(db.users_table.c.name))
    plates: dict[str, list[str]] = {}
    for r in await db.database.fetch_all(db.vehicles_table.select().order_by(db.vehicles_table.c.plate)):
        plates.setdefault(r["user_id"], []).append(r["plate"])
    return [{"id": u["id"], "name": u["name"], "license_no": u["license_no"], "email": u["email"],
             "plates": plates.get(u["id"], [])} for u in users]


async def set_user_email(user_id: str, email: str) -> bool:
    """False if there is no such motorist. An empty e-mail means 'do not e-mail this motorist'."""
    if not await get_user_by_id(user_id):
        return False
    await db.database.execute(db.users_table.update().where(db.users_table.c.id == user_id).values(email=email))
    return True


async def register_plate(plate: str, user_id: str) -> dict | None:
    """Put a plate on a motorist (it moves if it belonged to someone else). None if the plate is not a plate
    or there is no such motorist."""
    key = normalize_plate(plate)
    if not key or not await get_user_by_id(user_id):
        return None
    shown = plate.strip().upper()
    await db.database.execute(
        db.vehicles_table.insert().prefix_with("OR REPLACE").values(plate_key=key, plate=shown, user_id=user_id)
    )
    return {"plate": shown, "user_id": user_id}


async def unregister_plate(plate: str) -> bool:
    """False if that plate was not registered."""
    key = normalize_plate(plate)
    found = await db.database.fetch_one(db.vehicles_table.select().where(db.vehicles_table.c.plate_key == key)) if key else None
    if found:
        await db.database.execute(db.vehicles_table.delete().where(db.vehicles_table.c.plate_key == key))
    return found is not None


async def get_user_plates(user_id: str) -> list[str]:
    rows = await db.database.fetch_all(db.vehicles_table.select().where(db.vehicles_table.c.user_id == user_id).order_by(db.vehicles_table.c.plate))
    return [r["plate"] for r in rows]


async def create_motorist(name: str, plate: str, email: str, password_hash: str) -> dict | None:
    """A motorist account made in the phone app, owning one plate. None if it is not a plate or the plate has an account."""
    key = normalize_plate(plate)
    if not key or await get_user_by_plate(plate):
        return None
    user = {"id": f"user_{uuid.uuid4().hex[:8]}", "name": name, "license_no": f"PLATE-{key}", "license_type": "Not provided",
            "restrictions": "", "expiry": "-", "address": "-", "password": password_hash, "email": email}
    await db.database.execute(db.users_table.insert().values(**user))
    await register_plate(plate, user["id"])
    await _adopt_tickets(user["id"], key)
    return user


async def _adopt_tickets(user_id: str, plate_key: str) -> None:
    """Tickets that were made before this plate had an account belong to the new owner now."""
    v = db.violations_table
    rows = await db.database.fetch_all(v.select().with_only_columns(v.c.id, v.c.plate_text).where(v.c.user_id == "unregistered"))
    for row in rows:
        if normalize_plate(row["plate_text"]) == plate_key:
            await db.database.execute(v.update().where(v.c.id == row["id"]).values(user_id=user_id))


async def update_motorist(user_id: str, name: str | None = None, password_hash: str | None = None) -> bool:
    """Change a motorist's name and/or password hash. False if there is no such motorist."""
    if not await get_user_by_id(user_id):
        return False
    values = {k: v for k, v in (("name", name), ("password", password_hash)) if v is not None}
    if values:
        await db.database.execute(db.users_table.update().where(db.users_table.c.id == user_id).values(**values))
    return True


async def delete_motorist(user_id: str) -> bool:
    """Remove a motorist and their plates and phones. Their tickets stay (they just have no owner any more)."""
    if not await get_user_by_id(user_id):
        return False
    await db.database.execute(db.vehicles_table.delete().where(db.vehicles_table.c.user_id == user_id))
    await db.database.execute(db.fcm_tokens_table.delete().where(db.fcm_tokens_table.c.user_id == user_id))
    await db.database.execute(db.users_table.delete().where(db.users_table.c.id == user_id))
    return True


async def get_violation(violation_id: str) -> dict | None:
    row = await db.database.fetch_one(db.violations_table.select().where(db.violations_table.c.id == violation_id))
    return dict(row) if row else None


async def get_appeal_for(violation_id: str) -> dict | None:
    row = await db.database.fetch_one(db.appeals_table.select().where(db.appeals_table.c.violation_id == violation_id))
    return dict(row) if row else None


async def add_appeal(violation_id: str, user_id: str, reason: str) -> dict:
    appeal = {"id": str(uuid.uuid4()), "violation_id": violation_id, "user_id": user_id, "reason": reason,
              "status": "pending", "created_at": datetime.now(timezone.utc).isoformat()}
    await db.database.execute(db.appeals_table.insert().values(**appeal))
    return appeal


async def list_appeals(user_id: str) -> list[dict]:
    query = db.appeals_table.select().where(db.appeals_table.c.user_id == user_id).order_by(db.appeals_table.c.created_at.desc())
    return [dict(r) for r in await db.database.fetch_all(query)]


async def seed_registry() -> None:
    """Give the 3 mock motorists a plate each, only while no plate is registered (so the demo works out of the box)."""
    if await db.database.fetch_val("SELECT COUNT(*) FROM vehicles"):
        return
    for user_id, plate in DEMO_PLATES.items():
        await register_plate(plate, user_id)


# ─── FCM Token ───────────────────────────────────────────────────────────────

async def add_fcm_token(token: str, user_id: str) -> None:
    """Upsert a user-scoped FCM token."""
    query = (
        db.fcm_tokens_table.insert()
        .prefix_with("OR REPLACE")
        .values(token=token, user_id=user_id)
    )
    await db.database.execute(query)


async def remove_fcm_token(token: str) -> None:
    """The phone signed out: it gets no more pushes for that account."""
    await db.database.execute(db.fcm_tokens_table.delete().where(db.fcm_tokens_table.c.token == token))


async def _get_tokens_for_user(user_id: str) -> list[str]:
    rows = await db.database.fetch_all(
        db.fcm_tokens_table.select().where(db.fcm_tokens_table.c.user_id == user_id)
    )
    return [r["token"] for r in rows]

# ─── Violations ───────────────────────────────────────────────────────────────

async def get_violations(page: int = 1, size: int = 20, user_id: str | None = None, status: str | None = None, track_id: int | None = None) -> dict:
    query = (
        db.violations_table.select()
        .add_columns(db.users_table.c.name.label("user_name"))
        .select_from(
            db.violations_table.outerjoin(
                db.users_table, db.violations_table.c.user_id == db.users_table.c.id
            )
        )
    )
    count_query = "SELECT COUNT(*) FROM violations WHERE 1=1"
    
    where_clauses = []
    if user_id:
        where_clauses.append(db.violations_table.c.user_id == user_id)
        count_query += f" AND user_id = '{user_id}'"
    if status:
        where_clauses.append(db.violations_table.c.status == status)
        count_query += f" AND status = '{status}'"
    if track_id is not None:
        where_clauses.append(db.violations_table.c.track_id == track_id)
        count_query += f" AND track_id = {int(track_id)}"
        
    for clause in where_clauses:
        query = query.where(clause)

    total = await db.database.fetch_val(count_query)
    offset = (page - 1) * size
    rows = await db.database.fetch_all(
        query.order_by(db.violations_table.c.timestamp.desc()).limit(size).offset(offset)
    )
    
    items = []
    for r in rows:
        d = dict(r)
        if d.get("user_id") == "scanning":
            d["user_name"] = "SCANNING..."
        elif d.get("user_id") == "unregistered" and not d.get("user_name"):
            pass # Name is usually already set, but just in case
        elif d.get("user_id") == "no_plate_found":
            d["user_name"] = "NO PLATE FOUND"
        items.append(d)
        
    return {
        "total": total,
        "page": page,
        "size": size,
        "items": items,
    }

async def update_violation_status(violation_id: str, status: str) -> dict | None:
    query = db.violations_table.update().where(db.violations_table.c.id == violation_id).values(status=status)
    await db.database.execute(query)
    
    row = await db.database.fetch_one(db.violations_table.select().where(db.violations_table.c.id == violation_id))
    if not row:
        return None
    
    v = dict(row)
    if status == 'approved':
        v = await _link_owner(v)
        await _notify_owner(v)

    return v

async def get_approved_violations() -> list[dict]:
    """Confirmed tickets only (id, plate, class, time) - what the demerit counter adds up."""
    t = db.violations_table
    query = t.select().with_only_columns(t.c.id, t.c.plate_text, t.c.cls, t.c.timestamp).where(t.c.status == "approved")
    return [dict(r) for r in await db.database.fetch_all(query)]


async def update_violation_user(violation_id: str, user_id: str) -> bool:
    query = db.violations_table.update().where(db.violations_table.c.id == violation_id).values(user_id=user_id)
    await db.database.execute(query)
    return True


async def set_violation_evidence(row_ids: list[str], evidence_paths: list[str]) -> int:
    """Operator removed photos from a ticket: every row of the ticket keeps only the photos left."""
    for rid in row_ids:
        await db.database.execute(
            db.violations_table.update().where(db.violations_table.c.id == rid).values(evidence_paths=json.dumps(evidence_paths))
        )
    return len(row_ids)


async def update_violation_plate(row_ids: list[str], plate_text: str, user_id: str) -> int:
    """Operator plate edit: every given row carries the plate and the owner id that goes with it."""
    for rid in row_ids:
        await db.database.execute(
            db.violations_table.update().where(db.violations_table.c.id == rid)
            .values(plate_text=plate_text, user_id=user_id)
        )
    return len(row_ids)


def _levenshtein(a: str, b: str) -> int:
    """Compute edit distance between two strings."""
    if len(a) < len(b):
        a, b = b, a
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a):
        curr = [i + 1]
        for j, cb in enumerate(b):
            curr.append(min(prev[j + 1] + 1, curr[j] + 1, prev[j] + (ca != cb)))
        prev = curr
    return prev[-1]


async def add_violation(
    cls: str,
    confidence: float,
    user_id: str,
    image_path: str = "",
    notify: bool = True,
    status: str = "pending",
    evidence_paths: list[str] | None = None,
    track_id: int = -1,
    source: str = "live",
    session_id: str = "default",
    plate_text: str = "unidentified",
    dedupe: bool = True,
) -> dict:
    # ── Duplicate-ticket deduplication (idempotent upsert) ───────────────────
    # If the same plate already has this violation in this session, merge
    # evidence frames rather than creating a ghost entry from an ID switch.
    # Skips unidentified plates to avoid merging genuinely different unknowns.
    # dedupe=False: the caller already decided (a forensic ticket the operator may have judged): always a new row.
    _UNIDENTIFIED = ("unidentified", "no_plate_found", "")
    if dedupe and plate_text and plate_text not in _UNIDENTIFIED:
        existing_rows = await db.database.fetch_all(
            db.violations_table.select().where(
                (db.violations_table.c.session_id == session_id) &
                (db.violations_table.c.cls == cls)
            )
        )
        for row in existing_rows:
            row_plate = row["plate_text"] or ""
            # Merge if plates match exactly OR differ by ≤1 char (OCR jitter tolerance)
            if row_plate not in _UNIDENTIFIED and \
               _levenshtein(plate_text.upper(), row_plate.upper()) <= 1:
                existing_ev: list = json.loads(row["evidence_paths"] or "[]")
                merged = list(dict.fromkeys(existing_ev + (evidence_paths or [])))
                await db.database.execute(
                    db.violations_table.update()
                    .where(db.violations_table.c.id == row["id"])
                    .values(evidence_paths=json.dumps(merged))
                )
                return dict(row)  # canonical ticket returned, no new row written
    # ── Normal insert ─────────────────────────────────────────────────────────
    v = {
        "id": str(uuid.uuid4()),
        "user_id": user_id,
        "cls": cls,
        "confidence": round(confidence, 3),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "image_path": image_path,
        "status": status,
        "evidence_paths": json.dumps(evidence_paths or []),
        "track_id": track_id,
        "source": source,
        "session_id": session_id,
        "plate_text": plate_text,
    }
    await db.database.execute(db.violations_table.insert().values(**v))

    if notify and status == 'approved':
        await _notify_owner(v)

    return v


async def delete_violations(ids: list[str]) -> int:
    """Remove violation rows by id (an analysis was cancelled after some of its tickets were already released)."""
    for rid in ids:
        await db.database.execute(db.violations_table.delete().where(db.violations_table.c.id == rid))
    return len(ids)


async def delete_all_violations() -> int:
    """Delete all violations from DB. Returns count deleted."""
    count = await db.database.fetch_val("SELECT COUNT(*) FROM violations")
    await db.database.execute(db.violations_table.delete())
    return count

# ─── Notifications ────────────────────────────────────────────────────────────

async def _link_owner(v: dict) -> dict:
    """A plate can be registered after its ticket was made, so look the owner up again when the ticket is approved."""
    owner = await get_user_by_plate(v.get("plate_text"))
    if owner and owner["id"] != v["user_id"]:
        await update_violation_user(v["id"], owner["id"])
        v = {**v, "user_id": owner["id"]}
    return v


async def _notify_owner(v: dict) -> None:
    published = None
    if emailer.mode() == "online" and cloud.configured():
        published = await asyncio.to_thread(cloud.publish, v, evidence_files.frames_of(v))
        if published.user_id or published.status == "failed":
            await _record_cloud(v, published)
    await _send_push_notification(v, extra_tokens=published.tokens if published else ())
    await _send_email_notification(v)


async def _record_cloud(v: dict, published) -> None:
    """Keep a line in the laptop's own notice list for what went to the phone cloud (the dashboard shows it)."""
    try:
        await db.database.execute(db.notices_table.insert().values(
            id=str(uuid.uuid4()), user_id=f"cloud:{published.user_id or 'none'}", to_email="phone app",
            subject=published.subject or f"Phone app: {v['cls'].replace('_', ' ').title()} ({v.get('plate_text')})",
            body=published.body or published.detail, status=published.status, detail=published.detail,
            frames=json.dumps(published.frames), created_at=datetime.now(timezone.utc).isoformat()))
    except Exception as exc:
        print(f"[CLOUD] could not record the notice: {exc}")


async def add_notice(user_id: str, to_email: str, msg, result, frames: list[str] = ()) -> None:
    body = msg.get_body(preferencelist=("plain",)).get_content()          # the text, whether or not photos are attached
    await db.database.execute(db.notices_table.insert().values(
        id=str(uuid.uuid4()), user_id=user_id, to_email=to_email, subject=msg["Subject"], body=body,
        status=result.status, detail=result.detail, frames=json.dumps(list(frames)),
        created_at=datetime.now(timezone.utc).isoformat(),
    ))


async def list_notices(user_id: str | None = None, limit: int = 50, after: str | None = None) -> list[dict]:
    """Newest first, with the motorist's name. `after` (an ISO time) keeps only notices written since then."""
    n, u = db.notices_table, db.users_table
    query = n.select().add_columns(u.c.name.label("user_name")).select_from(n.outerjoin(u, n.c.user_id == u.c.id))
    if user_id:
        query = query.where(n.c.user_id == user_id)
    if after:
        query = query.where(n.c.created_at > after)
    notices = [dict(r) for r in await db.database.fetch_all(query.order_by(n.c.created_at.desc()).limit(limit))]
    for notice in notices:
        notice["frames"] = json.loads(notice.get("frames") or "[]")
    return notices


async def _send_email_notification(v: dict) -> None:
    """Write the notice to the motorist the ticket belongs to: e-mail it (online) or leave it in the mailbox (offline).
    A problem is logged, never raised: it must not undo a review."""
    owner = await get_user_by_id(v["user_id"])
    if not owner:
        print(f"[NOTICE] Ticket owner {v['user_id']} is not a registered motorist, skipping.")
        return
    online = emailer.mode() == "online"
    if online and not owner.get("email"):
        print(f"[NOTICE] No e-mail on file for {owner['name']}, skipping.")
        return
    try:
        frames = evidence_files.frames_of(v)
        msg = emailer.build_message(owner, v, frames)
        result = await asyncio.to_thread(emailer.send, msg) if online else emailer.Result("local", "")
        await add_notice(owner["id"], owner.get("email", ""), msg, result, frames)
    except Exception as exc:
        print(f"[NOTICE] Error: {exc}")


PUSH_CHANNEL = "hulikamote_alerts"           # the channel the phone app creates; a push on it pops up on screen
APP_GOOGLE_SERVICES = os.path.join(os.path.dirname(__file__), "..", "hulikamote_app", "android", "app", "google-services.json")


def _android_push() -> "messaging.AndroidConfig":
    return messaging.AndroidConfig(priority="high", notification=messaging.AndroidNotification(channel_id=PUSH_CHANNEL))


def _push_for(v: dict, tokens: list[str]) -> "messaging.MulticastMessage":
    label = v["cls"].replace("_", " ").title()
    plate = v.get("plate_text") or ""
    shown = label if plate in ("", "unidentified", "no_plate_found") else f"{label} \u00b7 {plate}"
    return messaging.MulticastMessage(
        notification=messaging.Notification(title="New violation on your record", body=shown),
        android=_android_push(),
        data={"violation_id": v["id"], "user_id": v["user_id"], "class": v["cls"],
              "confidence": str(v["confidence"]), "timestamp": v["timestamp"]},
        tokens=tokens,
    )


def _project_of(path: str, *keys: str) -> str:
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for key in keys:
            data = data[key]
        return str(data)
    except (OSError, ValueError, KeyError, TypeError):
        return ""


def push_status() -> dict:
    """Is push set up on this laptop? It checks the key file and that it matches the app's Firebase project; only a real
    phone can prove delivery (see send_test_push)."""
    if not os.path.exists(FIREBASE_KEY_PATH):
        return {"ready": False, "detail": "No Firebase key on this laptop (hulikamote_backend/firebase-service-account.json). "
                                          "Without it a phone only gets notices while the app is open."}
    if not _firebase_initialized:
        return {"ready": False, "detail": "The Firebase key file cannot be used. Download a new one: Firebase console > Project settings > Service accounts."}
    key_project = _project_of(FIREBASE_KEY_PATH, "project_id")
    app_project = _project_of(APP_GOOGLE_SERVICES, "project_info", "project_id")
    if app_project and key_project and key_project != app_project:
        return {"ready": False, "detail": f"The Firebase key is for project '{key_project}' but the phone app is built for '{app_project}'. Use the key of '{app_project}'."}
    return {"ready": True, "detail": f"Push is ready (Firebase project {key_project or 'unknown'})."}


async def _send_push_notification(v: dict, extra_tokens=()) -> None:
    """Send FCM push to the phones of this violation's owner: those registered with the laptop and (online) the
    ones registered in the phone cloud."""
    tokens = list(dict.fromkeys([*await _get_tokens_for_user(v["user_id"]), *extra_tokens]))
    if not tokens:
        print(f"[FCM] No tokens registered for user {v['user_id']}, skipping push.")
        return

    if _firebase_initialized:
        try:
            response = await asyncio.to_thread(messaging.send_each_for_multicast, _push_for(v, tokens))
            print(f"FCM [{v['user_id']}]: Sent {response.success_count}, failed {response.failure_count}")
        except Exception as e:
            print(f"FCM Error: {e}")
    else:
        print(f"[MOCK FCM] user={v['user_id']} | {v['cls']}")


async def send_test_push() -> dict:
    """Push a test message to every phone that is registered (on the laptop and in the cloud): {ready, detail, phones, sent, failed}."""
    status = push_status()
    result = {**status, "phones": 0, "sent": 0, "failed": 0}
    if not status["ready"]:
        return result
    tokens = [r["token"] for r in await db.database.fetch_all(db.fcm_tokens_table.select())]
    if cloud.configured():
        try:
            tokens += await asyncio.to_thread(cloud.all_device_tokens)
        except cloud.CloudError as exc:
            print(f"[CLOUD] could not read the phones: {exc}")
    tokens = list(dict.fromkeys(tokens))[:500]
    result["phones"] = len(tokens)
    if not tokens:
        return {**result, "detail": "No phone is registered yet. Sign in on the phone first."}
    message = messaging.MulticastMessage(
        notification=messaging.Notification(title="HULI-KAMOTE test", body="If you can read this, push works."),
        android=_android_push(), tokens=tokens)
    try:
        response = await asyncio.to_thread(messaging.send_each_for_multicast, message)
    except Exception as exc:
        return {**result, "ready": False, "detail": f"Firebase refused: {exc}"}
    return {**result, "sent": response.success_count, "failed": response.failure_count,
            "detail": f"Sent to {response.success_count} of {len(tokens)} phones."}

# ─── Seed ─────────────────────────────────────────────────────────────────────

async def seed_users() -> None:
    """Seed the 3 mock users only if the users table is empty."""
    count = await db.database.fetch_val("SELECT COUNT(*) FROM users")
    if count == 0:
        print("Seeding 3 mock users...")
        for u in MOCK_USERS:
            await db.database.execute(db.users_table.insert().values(**u))


async def merge_violation_rows(keep_ids: list[str], drop_ids: list[str], evidence_paths: list[str],
                               plate_text: str, track_id: int) -> list[str]:
    """
    Operator "Same car" merge at DB level. Rows of the dropped ticket whose violation
    class the kept ticket already has are folded in and deleted; other rows are adopted.
    Every surviving row gets the merged evidence, plate and primary track id.
    Returns the surviving row ids.
    """
    async def _rows(ids):
        out = []
        for i in ids:
            r = await db.database.fetch_one(db.violations_table.select().where(db.violations_table.c.id == i))
            if r:
                out.append(dict(r))
        return out

    keep_rows, drop_rows = await _rows(keep_ids), await _rows(drop_ids)
    keep_classes = {r["cls"] for r in keep_rows}
    survivors = [r["id"] for r in keep_rows]
    for r in drop_rows:
        if r["cls"] in keep_classes:
            await db.database.execute(db.violations_table.delete().where(db.violations_table.c.id == r["id"]))
        else:
            survivors.append(r["id"])
    for vid in survivors:
        await db.database.execute(
            db.violations_table.update().where(db.violations_table.c.id == vid)
            .values(evidence_paths=json.dumps(evidence_paths), plate_text=plate_text, track_id=track_id)
        )
    return survivors


async def split_violation_rows(row_ids: list[str], remaining_evidence: list[str], new_evidence: list[str],
                               session_id: str) -> list[str]:
    """
    Operator "Split": existing rows keep only `remaining_evidence`; a copy of each row
    (same violation class and track id, plate 'unidentified') is inserted with
    `new_evidence`. Returns the new row ids.
    """
    new_ids = []
    for rid in row_ids:
        row = await db.database.fetch_one(db.violations_table.select().where(db.violations_table.c.id == rid))
        if not row:
            continue
        await db.database.execute(
            db.violations_table.update().where(db.violations_table.c.id == rid)
            .values(evidence_paths=json.dumps(remaining_evidence))
        )
        v = await add_violation(
            cls=row["cls"], confidence=row["confidence"], user_id="no_plate_found",
            image_path=f"snapshots/evidence/{new_evidence[0]}", notify=False, status="pending",
            evidence_paths=new_evidence, track_id=row["track_id"], source=row["source"],
            session_id=session_id, plate_text="unidentified",
        )
        new_ids.append(v["id"])
    return new_ids
