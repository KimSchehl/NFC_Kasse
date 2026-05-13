@echo off
setlocal enabledelayedexpansion
title NFC-Kasse Backend

:: ============================================================
:: NFC-Kasse -- Backend Starter (Windows)
:: Reads settings from config.env next to this file.
:: Double-click or run from a terminal before starting the app.
::
:: Prerequisites (one-time setup):
::   pip install -r backend/requirements.txt
:: ============================================================

cd /d "%~dp0"

echo.
echo  ================================================
echo   NFC-Kasse Backend
echo  ================================================
echo.

:: ---- Load config.env ----------------------------------------
if not exist "config.env" (
    echo  [ERROR] config.env not found next to this script.
    echo  Copy config.env.example to config.env and edit it.
    pause
    exit /b 1
)

:: Parse KEY=VALUE lines, skip comments and blank lines.
for /f "usebackq tokens=1,2 delims== eol=#" %%a in ("config.env") do (
    set "%%a=%%b"
)

:: Validate required keys
if not defined HOST set HOST=0.0.0.0
if not defined PORT set PORT=8000
if not defined SECRET_KEY (
    echo  [ERROR] SECRET_KEY is not set in config.env.
    pause
    exit /b 1
)

:: ---- Database -----------------------------------------------
cd backend
if not exist "kasse.db" (
    echo  [SETUP] kasse.db not found -- creating database ...
    python init_db.py
    if errorlevel 1 (
        echo  [ERROR] Database creation failed. Check Python and requirements.
        pause
        exit /b 1
    )
    echo.
    echo  [SETUP] Done. Default login: admin / admin
    echo  [SETUP] Change the password immediately after first login!
    echo.
) else (
    echo  [OK] kasse.db found.
)
cd ..

:: ---- Network info -------------------------------------------
echo.
:: Find the first network adapter that has a default gateway (skips virtual adapters).
for /f %%i in ('powershell -NoProfile -Command "(Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -ne $null} | Select-Object -First 1).IPv4Address.IPAddress"') do set LAN_IP=%%i

if defined LAN_IP (
    echo  Backend URL: http://%LAN_IP%:%PORT%
) else (
    echo  Backend URL: [could not detect IP -- check ipconfig manually]
)
echo  Local URL:   http://localhost:%PORT%
echo  API Docs:    http://localhost:%PORT%/docs
echo.
echo  Press Ctrl+C to stop the server.
echo  ================================================
echo.

:: ---- Start server -------------------------------------------
cd backend
set SECRET_KEY=%SECRET_KEY%
python -m uvicorn main:app --host %HOST% --port %PORT% --reload

echo.
echo  Server stopped.
pause
