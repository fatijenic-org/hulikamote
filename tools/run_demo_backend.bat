@echo off
rem Starts the backend on the DEMO data (hulikamote_backend\demo.db), not on the real database.
rem Build the demo data first:  hulikamote_backend\venv\Scripts\python.exe tools\make_demo_data.py
cd /d "%~dp0..\hulikamote_backend"
if not exist demo.db (
  echo No demo.db yet. Run:  hulikamote_backend\venv\Scripts\python.exe tools\make_demo_data.py
  pause
  exit /b 1
)
set HK_DB=demo.db
set HK_DEV=1
echo ===== DEMO DATA: the real database is not used. Developer tools in the phone app are ON. =====
venv\Scripts\uvicorn.exe main:app --host 0.0.0.0 --port 8000 --reload
