@echo off
:: Forensic Evidence Ingestion Tool Launcher (Anti-Flash-Exit)
:: Pure English script to prevent Windows console encoding / garbling issues.

title Forensic Evidence Ingestion Tool Launcher
cd /d "%~dp0"

:: Check for Administrative privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :run_script
) else (
    echo [INFO] Requesting Administrator privileges for drive mapping...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:run_script
echo Launching Forensics Core Module...
:: Added -NoExit flag below to capture and freeze any errors on screen instead of closing.
PowerShell -NoExit -NoProfile -ExecutionPolicy Bypass -File "%~dp0Evidence_Ingest_Tool.ps1"
exit /b