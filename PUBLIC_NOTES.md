# HULI-KAMOTE: shareable copy (code only)

This copy was made from the `dev` branch with a fresh history. These were left out on purpose:

| Left out | Why | How to get it back |
|---|---|---|
| Model weights (`*.onnx`, `*.pt`, `*.pth`, `*.t7`, `*.pb`) | Size and third-party licences (Ultralytics YOLO is AGPL-3.0) | Ask the team; the Models page lists what the backend expects under `hulikamote_backend/models/` |
| Videos and archives (`*.mp4`, `*.avi`, `*.zip`) | Footage shows real people and plates | Use your own clips |
| Training pictures and labels (`training_lab/datasets/*`) | Third-party images with mixed licences; see each `DATASET_CARD.md` for sources | Rebuild with the dataset tools in `training_lab/` |
| Databases (`*.db`) | Seed accounts and violation records | Created on first run |
| Keys and credentials (`*.key`, Firebase service account, `google-services.json`) | Secrets | Make your own; see `supabase/README.md` |
| Binaries (`mediamtx.exe`) and `_archive/` | Size | Download from the tool's own site |

No licence has been chosen for this code yet. Add a `LICENSE` file before reusing it outside the team.
