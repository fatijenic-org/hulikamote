import urllib.request
import os

url = "https://github.com/fannymonori/TF-LapSRN/raw/master/export/LapSRN_x8.pb"
output_path = "hulikamote_backend/models/LapSRN_x8.pb"

if not os.path.exists(output_path):
    print("Downloading LapSRN_x8.pb...")
    try:
        urllib.request.urlretrieve(url, output_path)
        print("Download complete.")
    except Exception as e:
        print(f"Failed to download: {e}")
else:
    print("Model already exists.")
