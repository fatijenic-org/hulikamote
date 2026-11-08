"""
archive_dead_code.py - One-shot script to archive all identified dead code and scratch files.

Usage:
    python tools/archive_dead_code.py --dry-run     # Preview actions without moving files
    python tools/archive_dead_code.py --apply       # Execute moves into _archive/ preserving paths
    python tools/archive_dead_code.py --apply --track  # Use git mv for tracked files (records renames)

This script moves obsolete scratch scripts, legacy patches, broken vendored code,
and discarded training data into _archive/ while preserving their original directory paths.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ARCHIVE_DIR = REPO_ROOT / "_archive"

# Every dead code file or directory, relative to REPO_ROOT.
DEAD_CODE_MANIFEST = [
    # --- Group 1: Root scratch & one-off patch scripts ---
    {
        "path": "add_uk_format.py",
        "category": "Root Scratch",
        "reason": "Legacy regex patch for old forensic screen. Replaced by modern UI."
    },
    {
        "path": "build_ui.py",
        "category": "Root Scratch",
        "reason": "Legacy script inspecting method line bounds in old forensic analyzer."
    },
    {
        "path": "test_date.dart",
        "category": "Root Scratch",
        "reason": "Throwaway 1-line scratch testing DateTime.difference()."
    },
    {
        "path": "test",
        "category": "Root Scratch",
        "reason": "Personal roleplay interview class notes completely unrelated to the project."
    },
    {
        "path": "runs",
        "category": "Root Artifact",
        "reason": "17MB misplaced YOLO run directory from incorrect root run (HANDOVER line 147)."
    },

    # --- Group 2: Obsolete patch tools ---
    {
        "path": "tools/pending_patches",
        "category": "Tools (Pending Patches)",
        "reason": "Pre-integration patches (stall_fix & plate_edit) applied in 711737f and a025da8."
    },

    # --- Group 3: One-off debug/patch scripts in temp_scripts/ ---
    {
        "path": "temp_scripts",
        "category": "Historical Patch Scripts",
        "reason": "62 historical patch/migration scripts from Sessions 014-016. Already baked in."
    },

    # --- Group 4: Backend dead code, throwaway tests, and broken scripts ---
    {
        "path": "hulikamote_backend/fix_ui.py",
        "category": "Backend Scratch",
        "reason": "Old regex string substitution patch for old monitoring screen."
    },
    {
        "path": "hulikamote_backend/test_extract.py",
        "category": "Backend Manual Test",
        "reason": "Ad-hoc 6-line manual frame extraction test outside pytest suite."
    },
    {
        "path": "hulikamote_backend/test_ffmpeg_pipe.py",
        "category": "Backend Manual Test",
        "reason": "Ad-hoc manual FFmpeg pipe simulator script outside pytest suite."
    },
    {
        "path": "hulikamote_backend/test_forensic.py",
        "category": "Backend Manual Test",
        "reason": "Ad-hoc manual script monkey-patching cv2.VideoCapture outside pytest suite."
    },
    {
        "path": "hulikamote_backend/test_rtsp.py",
        "category": "Backend Manual Test",
        "reason": "Ad-hoc manual RTSP capture verification script outside pytest suite."
    },
    {
        "path": "hulikamote_backend/test_ws.py",
        "category": "Backend Manual Test",
        "reason": "Ad-hoc manual WebSocket frame verification script outside pytest suite."
    },
    {
        "path": "hulikamote_backend/tracker.py",
        "category": "Backend Dead Code",
        "reason": "Legacy SimpleIoUTracker from Aug 2025; superseded by engine/tracker.py."
    },
    {
        "path": "hulikamote_backend/inference/onnx_engine.py",
        "category": "Backend Dead Code",
        "reason": "23-line dummy stub with empty pre/postprocess stubs; YOLO uses yolo_inference.py."
    },
    {
        "path": "hulikamote_backend/scripts/activate_custom_model.py",
        "category": "Backend Legacy Script",
        "reason": "Obsolete script directly editing yolo_inference.py; superseded by engine/registry.py."
    },
    {
        "path": "hulikamote_backend/scripts/train_colab.py",
        "category": "Backend Legacy Script",
        "reason": "Initial thesis Colab export script before dedicated training_lab was created."
    },
    {
        "path": "hulikamote_backend/engine/deep_sort/deep/evaluate.py",
        "category": "Backend Vendored DeepSort",
        "reason": "Standalone Market-1501 evaluator vendored from original DeepSORT repo, uncalled."
    },
    {
        "path": "hulikamote_backend/engine/deep_sort/deep/prepare_market1501.py",
        "category": "Backend Vendored DeepSort",
        "reason": "Standalone Market-1501 dataset preparer vendored from original DeepSORT repo, uncalled."
    },
    {
        "path": "hulikamote_backend/engine/deep_sort/deep/pt_to_onnx.py",
        "category": "Backend Vendored DeepSort",
        "reason": "Standalone Market-1501 PyTorch to ONNX exporter vendored from DeepSORT repo, uncalled."
    },
    {
        "path": "hulikamote_backend/engine/deep_sort/deep/test.py",
        "category": "Backend Vendored DeepSort",
        "reason": "Standalone Market-1501 test runner vendored from DeepSORT repo, uncalled."
    },
    {
        "path": "hulikamote_backend/engine/deep_sort/deep/train.py",
        "category": "Backend Vendored DeepSort",
        "reason": "Broken Market-1501 trainer (crashes on non-64x128 images, NameError without resume)."
    },

    # --- Group 5: Training Lab scratch & rejected downloads ---
    {
        "path": "training_lab/scripts/_esrgan_temp",
        "category": "Training Lab Scratch",
        "reason": "Temporary folder containing hardcoded absolute-path RealESRGAN export script."
    },
    {
        "path": "training_lab/train",
        "category": "Training Lab Rejected Download",
        "reason": "Discarded Roboflow download (21 labels) at lab root (HANDOVER line 148)."
    },
    {
        "path": "training_lab/valid",
        "category": "Training Lab Rejected Download",
        "reason": "Discarded Roboflow download validation split at lab root (HANDOVER line 148)."
    },
    {
        "path": "training_lab/test",
        "category": "Training Lab Rejected Download",
        "reason": "Discarded Roboflow download test split at lab root (HANDOVER line 148)."
    },
    {
        "path": "training_lab/data.yaml",
        "category": "Training Lab Rejected Download",
        "reason": "Config file for discarded Roboflow download at lab root (HANDOVER line 148)."
    },
    {
        "path": "training_lab/README.dataset.txt",
        "category": "Training Lab Rejected Download",
        "reason": "Readme for discarded Roboflow download at lab root (HANDOVER line 148)."
    },
    {
        "path": "training_lab/README.roboflow.txt",
        "category": "Training Lab Rejected Download",
        "reason": "Readme for discarded Roboflow download at lab root (HANDOVER line 148)."
    },
]


def is_tracked_by_git(rel_path: str) -> bool:
    """Check if file or directory contains files tracked by git."""
    res = subprocess.run(
        ["git", "ls-files", rel_path],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    return bool(res.stdout.strip())


def generate_readme(manifest: list[dict]) -> str:
    """Generate comprehensive documentation of all archived dead codes."""
    lines = [
        "# Archive of Decommissioned & Dead Code",
        "",
        "This directory is a non-destructive archive of obsolete, scratch, and superseded code",
        "preserved for historical audit and rollback purposes rather than outright deletion.",
        "",
        "Every file and directory in `_archive/` mirrors its exact relative path from the repository root.",
        "",
        "---",
        "",
        "## Archived Items by Category",
        "",
        "| Original Root Path | Category | Reason / Historical Context |",
        "|---|---|---|",
    ]
    for item in sorted(manifest, key=lambda x: (x["category"], x["path"])):
        lines.append(f"| `{item['path']}` | {item['category']} | {item['reason']} |")

    lines.extend([
        "",
        "---",
        "",
        "## Rollback Procedure",
        "To restore any file back to its original location in the codebase:",
        "```powershell",
        "# Example for a single file:",
        "Move-Item _archive/hulikamote_backend/tracker.py hulikamote_backend/tracker.py",
        "",
        "# Or if tracked by git, revert using:",
        "git checkout HEAD -- <original_path>",
        "```",
        "",
        "Generated automatically by `tools/archive_dead_code.py`.",
    ])
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Archive dead code and scratch files.")
    parser.add_argument("--dry-run", action="store_true", help="Preview moves without modifying filesystem")
    parser.add_argument("--apply", action="store_true", help="Perform the archival moves")
    parser.add_argument("--track", action="store_true", help="Use git mv for git-tracked files (records renames)")
    args = parser.parse_args()

    if not args.dry_run and not args.apply:
        print("Please specify either --dry-run or --apply.")
        parser.print_help()
        sys.exit(1)

    print(f"=== HULI-KAMOTE Dead Code Archival Planner ===")
    print(f"Repository Root: {REPO_ROOT}")
    print(f"Destination:     {ARCHIVE_DIR}\n")

    items_to_move = []
    missing_items = []
    already_archived = []

    for item in DEAD_CODE_MANIFEST:
        rel = item["path"]
        src = REPO_ROOT / rel
        dst = ARCHIVE_DIR / rel

        if src.exists():
            tracked = is_tracked_by_git(rel)
            items_to_move.append({**item, "src": src, "dst": dst, "tracked": tracked})
        elif dst.exists():
            already_archived.append(item)
        else:
            missing_items.append(item)

    print(f"Found {len(items_to_move)} active items ready to archive:")
    for item in items_to_move:
        tracked_str = "[git tracked]" if item["tracked"] else "[untracked/ignored]"
        print(f"  -> {item['path']:<45} {tracked_str:<20} ({item['category']})")

    if already_archived:
        print(f"\nAlready in _archive/ ({len(already_archived)} items):")
        for item in already_archived:
            print(f"  [x] {item['path']}")

    if missing_items:
        print(f"\nNot found on disk ({len(missing_items)} items):")
        for item in missing_items:
            print(f"  [?] {item['path']}")

    if args.dry_run:
        print("\n[DRY RUN COMPLETE] No filesystem changes were made.")
        return

    # Execute moves
    print("\nExecuting archival moves...")
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)

    for item in items_to_move:
        src: Path = item["src"]
        dst: Path = item["dst"]
        dst.parent.mkdir(parents=True, exist_ok=True)

        if args.track and item["tracked"]:
            print(f"  git mv {item['path']} -> _archive/{item['path']}")
            subprocess.run(["git", "mv", str(src), str(dst)], cwd=REPO_ROOT, check=True)
        else:
            print(f"  move   {item['path']} -> _archive/{item['path']}")
            shutil.move(str(src), str(dst))

    # Write documentation README
    readme_path = ARCHIVE_DIR / "README.md"
    readme_content = generate_readme(DEAD_CODE_MANIFEST)
    readme_path.write_text(readme_content, encoding="utf-8")
    print(f"\nUpdated documentation at: {readme_path}")
    print("Archival complete.")


if __name__ == "__main__":
    main()
