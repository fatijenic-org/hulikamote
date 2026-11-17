@echo off
title HULI-KAMOTE - connect the phone
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect_usb.ps1"
echo.
pause
