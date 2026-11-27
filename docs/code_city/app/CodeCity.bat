@echo off
rem Double-click to open Code City. Or drag a project folder onto this file.
cd /d "%~dp0"
node build_app.js
if errorlevel 1 pause
start "" "node_moduleslectron\distlectron.exe" . %*
