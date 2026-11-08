"""
publish_release.py — Upload a trained ONNX model to GitHub Releases.

Usage:
    set GITHUB_TOKEN=your_pat_here
    python scripts/publish_release.py --file ../hulikamote_backend/models/Plate Models/plate_specialist_train2_20260923.onnx --tag plate_specialist_train2 --repo fatijenic-org/huli-kamote
"""
import os
import argparse
import requests
from pathlib import Path

def publish(file_path: str, tag: str, repo: str):
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("[ERROR] GITHUB_TOKEN environment variable is not set.")
        print("Please set it: set GITHUB_TOKEN=ghp_xxx")
        return

    file_p = Path(file_path)
    if not file_p.exists():
        print(f"[ERROR] File not found: {file_path}")
        return

    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json"
    }

    # 1. Create or get the Release
    print(f"[GitHub] Creating release tag '{tag}' for {repo}...")
    release_data = {
        "tag_name": tag,
        "name": f"Model Release: {tag}",
        "body": f"Automated model upload for {file_p.name}",
        "draft": False,
        "prerelease": False
    }
    
    res = requests.post(
        f"https://api.github.com/repos/{repo}/releases",
        json=release_data,
        headers=headers
    )
    
    if res.status_code == 201:
        release_id = res.json()["id"]
        upload_url = res.json()["upload_url"].split("{")[0]
        print(f"[GitHub] Release created (ID: {release_id})")
    elif res.status_code == 422 and "already_exists" in res.text:
        print(f"[GitHub] Tag '{tag}' already exists. Fetching existing release...")
        # Get release by tag
        res = requests.get(
            f"https://api.github.com/repos/{repo}/releases/tags/{tag}",
            headers=headers
        )
        release_id = res.json()["id"]
        upload_url = res.json()["upload_url"].split("{")[0]
    else:
        print(f"[ERROR] Failed to create release: {res.status_code} - {res.text}")
        return

    # 2. Upload the Asset
    print(f"[GitHub] Uploading {file_p.name} ({file_p.stat().st_size / 1024 / 1024:.2f} MB)...")
    with open(file_p, "rb") as f:
        asset_res = requests.post(
            f"{upload_url}?name={file_p.name}",
            headers={
                "Authorization": f"token {token}",
                "Content-Type": "application/octet-stream"
            },
            data=f
        )
        
    if asset_res.status_code == 201:
        print(f"[GitHub] ✅ Successfully uploaded to GitHub Releases!")
        print(f"URL: {asset_res.json()['browser_download_url']}")
    else:
        print(f"[ERROR] Failed to upload asset: {asset_res.status_code} - {asset_res.text}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True, help="Path to the ONNX file")
    parser.add_argument("--tag", required=True, help="Git tag for the release (e.g. plate_specialist_v1)")
    parser.add_argument("--repo", default="fatijenic-org/huli-kamote", help="GitHub repository (owner/repo)")
    args = parser.parse_args()

    publish(args.file, args.tag, args.repo)
