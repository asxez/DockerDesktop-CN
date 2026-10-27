@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore.ps1"
if errorlevel 1 (
  echo.
  echo Restore failed. See the messages above.
  pause
)
