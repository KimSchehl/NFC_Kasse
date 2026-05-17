@echo off
setlocal enabledelayedexpansion
title NFC-Kasse Backend

:: ============================================================
:: NFC-Kasse -- Backend Starter (Windows)
:: * Auto-creates config.env if missing
:: * Auto-installs Python 3.13 via winget if missing
:: * Auto-installs pip dependencies
:: Double-click or run from a terminal before starting the app.
:: ============================================================

cd /d "%~dp0"

echo.
echo  ================================================
echo   NFC-Kasse Backend
echo  ================================================
echo.

:: ---- 1. Ensure config.env exists ----------------------------
if not exist "config.env" (
    echo  [SETUP] config.env not found -- creating with defaults ...
    powershell -NoProfile -Command "$k=[System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)); Set-Content config.env -Encoding UTF8 -Value @('# NFC-Kasse Configuration','# Edit this file before starting the backend.','# Changes take effect on the next server start.','','# Network interface to bind to (0.0.0.0 = all interfaces).','HOST=0.0.0.0','','# Port the backend listens on.','PORT=8000','','# Secret used to sign login tokens (JWT).','# IMPORTANT: Change this before using with real data!',\"SECRET_KEY=`$k\",'','# Chip deposit in EUR (e.g. 3.00 for 3 Euro).','# Deducted automatically on first chip issuance; refunded on payout.','# Set to 0 to disable deposit logic.','CHIP_DEPOSIT=3.00')"
    if errorlevel 1 (
        echo  [ERROR] Could not create config.env.
        pause
        exit /b 1
    )
    echo  [SETUP] config.env created. Please review it before first use.
    echo.
)

:: ---- 2. Locate Python ----------------------------------------
set "PYTHON="

::   a) Python Launcher (py.exe) -- most reliable on Windows
py --version >nul 2>&1
if not errorlevel 1 (
    set "PYTHON=py"
    goto :have_python
)

::   b) python.exe in PATH -- skip Windows Store stub
for /f "delims=" %%P in ('where python 2^>nul') do (
    echo %%P | findstr /i "WindowsApps" >nul
    if errorlevel 1 (
        set "PYTHON=%%P"
        goto :have_python
    )
)

::   c) Not found -- install via winget
echo  [SETUP] Python not found -- installing via winget ...
echo  [SETUP] This may take a few minutes. Please wait.
winget install -e --id Python.Python.3.13 --scope user --silent ^
    --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
    echo.
    echo  [ERROR] Automatic Python installation failed.
    echo  Please install Python manually from https://www.python.org/downloads/
    echo  Check "Add Python to PATH" during setup, then run this script again.
    pause
    exit /b 1
)
echo  [OK] Python installed.

::   d) Find newly installed Python in default user location
for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do (
    if exist "%%D\python.exe" (
        set "PYTHON=%%D\python.exe"
        goto :have_python
    )
)

::   e) Refresh user PATH from registry and retry
for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('PATH','User')"`) do set "USERPATH=%%p"
if defined USERPATH set "PATH=!PATH!;!USERPATH!"
py --version >nul 2>&1
if not errorlevel 1 (
    set "PYTHON=py"
    goto :have_python
)

echo.
echo  [INFO] Python was installed but the PATH is not yet active in this window.
echo  Please CLOSE this window and run start_backend.bat again.
pause
exit /b 0

:have_python
echo  [OK] Python: !PYTHON!

:: ---- 3. Install / update Python dependencies ----------------
echo  [SETUP] Checking Python dependencies ...
"!PYTHON!" -m pip install --quiet --upgrade pip 2>nul
"!PYTHON!" -m pip install --quiet -r backend\requirements.txt
if errorlevel 1 (
    echo  [ERROR] Dependency installation failed.
    echo  Try running manually: !PYTHON! -m pip install -r backend\requirements.txt
    pause
    exit /b 1
)
echo  [OK] Dependencies ready.
echo.

:: ---- 4. Load config.env -------------------------------------
for /f "usebackq tokens=1,2 delims== eol=#" %%a in ("config.env") do (
    set "%%a=%%b"
)

if not defined HOST set HOST=0.0.0.0
if not defined PORT set PORT=8000
if not defined SECRET_KEY (
    echo  [ERROR] SECRET_KEY is not set in config.env.
    pause
    exit /b 1
)

:: ---- 5. Init database if needed ----------------------------
cd backend
if not exist "kasse.db" (
    echo  [SETUP] kasse.db not found -- creating database ...
    "!PYTHON!" init_db.py
    if errorlevel 1 (
        echo  [ERROR] Database creation failed.
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

:: ---- 6. Network info ----------------------------------------
echo.
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

:: ---- 7. Start server ----------------------------------------
cd backend
set SECRET_KEY=%SECRET_KEY%
"!PYTHON!" -m uvicorn main:app --host %HOST% --port %PORT% --reload

echo.
echo  Server stopped.
pause
