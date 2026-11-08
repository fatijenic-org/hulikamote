"""
YouTube Video Downloader (Video-Only / 4K Ready)
Part of Huli-Kamote Tooling

Usage:
    python tools/yt_downloader.py <YOUTUBE_URL> [OUTPUT_DIR]
    or simply run:
    python tools/yt_downloader.py
"""

import os
import sys
import yt_dlp


def download_video_only(url: str, output_folder: str = "./downloads") -> str | None:
    """
    Downloads the highest quality video stream (up to 4K / 2160p) without audio.
    No FFmpeg is required for video-only downloads.
    """
    os.makedirs(output_folder, exist_ok=True)

    ydl_opts = {
        # -------------------------------------------------------------
        # VIDEO CONFIGURATION (No Audio)
        # Selects the best video stream up to 4K resolution (height <= 2160)
        # -------------------------------------------------------------
        "format": "bestvideo[height<=2160]/bestvideo",

        # =============================================================
        # [FUTURE AUDIO INTEGRATION - KEEP ASIDE FOR NOW]
        # To enable audio download & merging in the future:
        # 1. Ensure FFmpeg is installed (e.g. via 'winget install Gyan.FFmpeg')
        # 2. Replace the 'format' line above with:
        #    "format": "bestvideo[height<=2160]+bestaudio/best",
        # 3. Uncomment the line below to merge video + audio into MP4:
        #    "merge_output_format": "mp4",
        # =============================================================

        # Output template: saves clean title and resolution tag
        "outtmpl": os.path.join(output_folder, "%(title)s [%(resolution)s].%(ext)s"),

        # Windows-safe filename sanitizer (strips ?, :, *, etc.)
        "windowsfilenames": True,

        # Download settings
        "noplaylist": True,
        "quiet": False,
        "no_warnings": False,
    }

    try:
        print(f"\n[INFO] Connecting to YouTube: {url}")
        print("[INFO] Fetching highest resolution video stream (Audio disabled)...")
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            saved_filename = ydl.prepare_filename(info)

            print("\n" + "=" * 60)
            print(f"[SUCCESS] Download completed successfully!")
            print(f"[TITLE]   {info.get('title', 'Unknown')}")
            print(f"[QUALITY] {info.get('resolution', 'Unknown')}")
            print(f"[FILE]    {os.path.abspath(saved_filename)}")
            print("=" * 60 + "\n")
            return saved_filename
    except Exception as e:
        print(f"\n[ERROR] Download failed: {e}")
        return None


if __name__ == "__main__":
    target_url = ""
    output_dir = "./downloads"

    if len(sys.argv) > 1:
        target_url = sys.argv[1]
    if len(sys.argv) > 2:
        output_dir = sys.argv[2]

    if not target_url:
        print("=" * 60)
        print("  HULI-KAMOTE: YouTube 4K Video Downloader (Video-Only)")
        print("=" * 60)
        target_url = input("Enter YouTube Video URL: ").strip()

    if target_url:
        download_video_only(target_url, output_folder=output_dir)
    else:
        print("[WARN] No URL provided. Exiting.")
