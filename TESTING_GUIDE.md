# HULI-KAMOTE — Session Testing Guide

> Run these in order. All paths are relative to the repo root:
> `C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\`

---

## Part 1 — Backend: Engine Import Fix

**What was fixed:** `engine/__init__.py` was missing, causing `ImportError` on every server start.

### Command
```powershell
cd hulikamote_backend
venv\Scripts\python.exe -c "from engine.pipeline import DecoupledPipeline; print('Import OK')"
```

### Expected Output
```
Import OK
```

---

## Part 2 — Backend: camera_config.json

**What was fixed:** Pipeline crashed on first boot — no starter config existed.

### Command
```powershell
venv\Scripts\python.exe -c "
from engine.pipeline import DecoupledPipeline
p = DecoupledPipeline('camera_config.json')
print('ROIs loaded:', p.rois)
"
```

### Expected Output
```
ROIs loaded: {
  'illegal_parking': [[100,100],[500,100],[500,400],[100,400]],
  'counterflow_vector': (1.0, 0.0)
}
```

No crash = pass. The Forensic wizard's "Use for Live Monitor" button overwrites this file with real zones later.

---

## Part 3 — Backend: Specialist Inference — Graceful Skip

**What was wired:** Helmet, Plate, and Cabin ONNX logic (not `pass`).  
**What to test now:** Graceful skip when weights don't exist yet (they need training first).

### Command
```powershell
venv\Scripts\python.exe -c "
from engine.registry import ModelRegistry
r = ModelRegistry('camera_config.json')
print('Active violations:', r.active_violations)
print('Helmet loaded:', r.get_model('helmet_specialist') is not None)
print('Plate loaded:', r.get_model('plate_specialist') is not None)
print('Cabin loaded:', r.get_model('cabin_specialist') is not None)
"
```

### Expected Output
```
[Registry] Loading primary_anchor from ...yolov8n.onnx
[Registry] Warning: helmet_specialist.onnx not found. Specialist will be skipped.
[Registry] Warning: plate_specialist.onnx not found. Specialist will be skipped.
Active violations: ['no_helmet', 'no_plate', 'illegal_parking', 'counterflow']
Helmet loaded: False
Plate loaded: False
Cabin loaded: False
```

> `False` is **correct**. When trained `.onnx` files are dropped into `models/`, these flip to `True` automatically with zero code changes.

---

## Part 4 — Backend: Plate Text + Ledger Data Flow

**What was wired:** `plate_text` flows `Plate Specialist → TrackLedger → finalized ticket → stream.py → DB user lookup`.

### Command
```powershell
venv\Scripts\python.exe -c "
from engine.ledger import TrackLedger, ActiveLedgerManager

t = TrackLedger(track_id=42)
print('1. Default plate_text:', t.plate_text)

t.plate_text = 'N01-12-345678'
print('2. After OCR write:', t.plate_text)

mgr = ActiveLedgerManager()
mgr.ledgers[42] = t
t.violations.add('no_helmet')
t.snapshot_bbox = [100, 100, 200, 200]
mgr._finalize_ticket(42)

ticket = mgr.pending_tickets[0]
print('3. Ticket plate_text:', ticket['plate_text'])
print('4. Ticket violations:', ticket['violations'])
"
```

### Expected Output
```
1. Default plate_text: unidentified
2. After OCR write: N01-12-345678
[Ledger] Queued ticket — Track 42 | Violations: {'no_helmet'}
3. Ticket plate_text: N01-12-345678
4. Ticket violations: ['no_helmet']
```

This proves the plate text travels end-to-end. Live, `stream.py` takes that plate text and calls `store.get_user_by_license()` to link the ticket to the right driver.

---

## Part 5 — Backend: Full Server Smoke Test

### Start the server
```powershell
cd hulikamote_backend
venv\Scripts\uvicorn.exe main:app --reload --port 8000
```

### What to look for in the terminal (not errors)
```
[Registry] Loading primary_anchor ...
[Registry] Warning: helmet_specialist.onnx not found. Skipped.
[Registry] Warning: plate_specialist.onnx not found. Skipped.
Firebase Admin initialized successfully.     ← or a warning if key missing, not a crash
Application startup complete.
```

### Open the API docs
`http://localhost:8000/docs`

**Verify these endpoints exist:**
- `POST /auth/login`
- `GET /violations`
- `PATCH /violations/{id}`
- `GET /settings/camera-config`
- `POST /settings/camera-config`
- `GET /settings/mock`

### Quick login test (in the Swagger UI)
1. Expand `POST /auth/login` → click **Try it out**
2. Body: `{"license_no": "N01-12-345678", "password": "password123"}`
3. Click **Execute**
4. **Expected:** `200 OK` with `user_id`, `name`, `license_no` etc. in the response

---

## Part 6 — Training Lab GUI

**What was built:** A double-click desktop app for the full training workflow.

### Launch
Double-click **`Launch Training Lab.bat`** in the repo root.

Or manually:
```powershell
hulikamote_backend\venv\Scripts\python.exe training_lab\gui.py
```

### Verify the UI loads
A window titled **"HULI-KAMOTE | Training Lab"** should appear with:
- Left panel: 4 model rows, all showing `⬛` (not yet trained) and `0 raw`
- Top: dropdown defaulting to `helmet_specialist`
- 3 tabs: `1 · Prepare Dataset`, `2 · Train & Validate`, `3 · One-Click Pipeline`
- Bottom: dark console log area with `Clear` and `⬛ Stop` buttons

### Test: Split with no data (expect graceful error)
1. Select any model from the dropdown
2. Go to **Tab 1 — Prepare Dataset**
3. Click **▶ Split Dataset**
4. Console should print:
   ```
   $ .../split_dataset.py --model helmet_specialist --ratio 0.8
   FileNotFoundError: Raw images not found at .../raw/images/
   [Process exited with code 1]
   ```
5. The app does **not crash** — this is correct behavior

### Test: Refresh button
- Click **⟳ Refresh Status** → left panel re-reads counts (still all zeros, no errors)

### Test: Stop button
1. Click **▶ Augment** (it will fail quickly since no train data)
2. While spinner is running, click **⬛ Stop**
3. Console: `[Process terminated by user]`
4. Stop button goes grey again

---

## Part 7 — Training Lab CLI Scripts

These verify each script finds its paths correctly and fails cleanly with no data.

### Split — no raw data
```powershell
hulikamote_backend\venv\Scripts\python.exe training_lab\scripts\split_dataset.py --model helmet_specialist
```
**Expected:** `FileNotFoundError: Raw images not found at .../raw/images/`

### Validate — no trained weights
```powershell
hulikamote_backend\venv\Scripts\python.exe training_lab\scripts\validate.py --model helmet_specialist
```
**Expected:** `FileNotFoundError: best.pt not found at .../runs/helmet_specialist/train/weights/best.pt`

### Export — no trained weights
```powershell
hulikamote_backend\venv\Scripts\python.exe training_lab\scripts\export_onnx.py --model helmet_specialist
```
**Expected:** Same `FileNotFoundError` for `best.pt`

> All three failures are **intentional and correct.** They confirm the scripts run, find the right paths, and fail cleanly — not silently, not with wrong paths.

---

## Part 8 — Mobile App: 3 New Screens

```powershell
cd hulikamote_app
flutter run -d windows
```

Or connect an Android device and run `flutter run`.

### 8A — Bottom Navigation Bar (new)
After login, you should see a bottom bar with 3 tabs:
- `Home` (house icon)
- `Inbox` (bell icon)
- `Profile` (person icon)

**Verify:** Tapping each tab switches the screen instantly (no loading spinner between tabs).

---

### 8B — Notifications Inbox
Tap the **bell icon**.

**Verify:**
- Screen title: `"Inbox & Updates"`
- 5 list items appear
- **First 2 items** have a light blue background (unread)
- **Last 3 items** have a white background (read)

---

### 8C — Profile Screen
Tap the **person icon**.

**Verify:**
- Screen title: `"Account Profile"`
- Profile card shows the name and license number you logged in with (e.g. `Juan Dela Cruz` / `N01-12-345678`)
- Two sections below: **Settings** and **Support** with tappable rows
- Red **"Sign Out"** button at the bottom
- Tap **Sign Out** → app navigates back to Login screen and clears the session

---

### 8D — Appeal / Contest Workflow
1. Tap **Home** tab → tap any violation in the list
2. On the Violation Detail screen, scroll to the bottom
3. **Verify two buttons appear side by side:**
   - Grey outlined `Contest Ticket` (left)
   - Red filled `Pay Fine (₱2,000)` (right)

**Test Pay Fine:**
- Tap `Pay Fine` → SnackBar at the bottom: `"Payment Gateway redirect..."`

**Test Contest Ticket:**
1. Tap `Contest Ticket` → new screen: **"Contest Violation"**
2. Screen shows the Ticket ID and Violation type in a grey info box at the top
3. Tap **Submit Appeal** with the text field empty → SnackBar: `"Please provide a reason for the appeal."`
4. Type anything in the text field → tap **Submit Appeal**
5. A 2-second spinner appears → then a dialog:
   > *"Your contestation has been forwarded to the traffic adjudication board. You will be notified of the result within 5-7 business days."*
6. Tap **OK** → returns to Violation Detail screen

---

## What Is NOT Testable Yet

These are blocked by **missing trained model weights** — not bugs.

| Feature | Blocked by |
|---|---|
| Actual helmet detection in live video | `helmet_specialist.onnx` — needs training data |
| Plate detection + OCR text extraction | `plate_specialist.onnx` + dashcam footage |
| Seatbelt / phone / mirror detection | `cabin_specialist.onnx` — needs training data |
| Auto-linking tickets to a registered driver | Plate OCR must work first |
| FCM push notifications to the mobile app | Real device + configured `firebase-service-account.json` |

The moment trained `.onnx` files are placed in `hulikamote_backend/models/`, all of the above activate with zero code changes. The Training Lab GUI is the tool to produce those files.
