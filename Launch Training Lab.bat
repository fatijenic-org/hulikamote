@echo off
:: HULI-KAMOTE Training Lab Launcher
:: Double-click this file to open the Training Lab GUI

cd /d "%~dp0.."
echo Starting HULI-KAMOTE Training Lab...

:: Try venv python first, fall back to system python
if exist "hulikamote_backend\venv\Scripts\pythonw.exe" (
    start "" "hulikamote_backend\venv\Scripts\pythonw.exe" "training_lab\gui.py"
) else if exist "hulikamote_backend\venv\Scripts\python.exe" (
    start "" "hulikamote_backend\venv\Scripts\python.exe" "training_lab\gui.py"
) else (
    python "training_lab\gui.py"
)
