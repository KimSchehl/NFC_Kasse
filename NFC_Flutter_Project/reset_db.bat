@echo off
setlocal enabledelayedexpansion
title NFC-Kasse — Datenbank zurücksetzen

cd /d "%~dp0"

echo.
echo  ================================================
echo   NFC-Kasse  --  Datenbank zuruecksetzen
echo  ================================================
echo.
echo  WICHTIG: Stoppe das Backend (start_backend.bat)
echo  bevor du dieses Skript ausfuehrst!
echo.
pause

:: ---- Python suchen (gleiche Logik wie start_backend.bat) ----
set "PYTHON="

py --version >nul 2>&1
if not errorlevel 1 (
    set "PYTHON=py"
    goto :have_python
)

for /f "delims=" %%P in ('where python 2^>nul') do (
    echo %%P | findstr /i "WindowsApps" >nul
    if errorlevel 1 (
        set "PYTHON=%%P"
        goto :have_python
    )
)

echo  [FEHLER] Python nicht gefunden.
echo  Bitte zuerst start_backend.bat ausfuehren (installiert Python).
pause
exit /b 1

:have_python
echo  [OK] Python: !PYTHON!
echo.

:: ---- Reset-Skript starten ------------------------------------
"!PYTHON!" backend\reset_db.py

echo.
pause
