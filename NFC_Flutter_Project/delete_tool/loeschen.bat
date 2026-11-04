@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title NFC-Kasse - Veranstalter und Feste loeschen

:: ============================================================
:: Deletes a whole Veranstalter or a single ended Fest.
:: * Asks for admin rights (needed to stop/start the service)
:: * Installs Python 3.13 via winget if missing
:: * Creates its own .venv with questionary on first run
:: Optional: loeschen.bat --db "D:\pfad\kasse.db"
:: ============================================================

cd /d "%~dp0"

:: ---- 1. Admin rights ----------------------------------------
net session >nul 2>&1
if errorlevel 1 (
    echo  Adminrechte werden angefordert ...
    if "%~1"=="" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b 0
)

:: ---- 2. Locate Python ----------------------------------------
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
echo  [SETUP] Python nicht gefunden, wird ueber winget installiert ...
winget install -e --id Python.Python.3.13 --scope user ^
    --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
    echo  [FEHLER] Python konnte nicht installiert werden.
    echo  Bitte von https://www.python.org/downloads/ installieren und erneut starten.
    pause
    exit /b 1
)
for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do (
    if exist "%%D\python.exe" (
        set "PYTHON=%%D\python.exe"
        goto :have_python
    )
)
echo  Python ist installiert, aber in diesem Fenster noch nicht bekannt.
echo  Bitte das Fenster schliessen und loeschen.bat erneut starten.
pause
exit /b 0

:have_python

:: ---- 3. Own virtual environment ----------------------------
if not exist ".venv\Scripts\python.exe" (
    echo  [SETUP] Lege Python-Umgebung an ...
    "!PYTHON!" -m venv .venv
    if errorlevel 1 (
        echo  [FEHLER] venv konnte nicht angelegt werden.
        pause
        exit /b 1
    )
)
fc /b requirements.txt .venv\requirements.installed >nul 2>&1
if errorlevel 1 (
    echo  [SETUP] Installiere Abhaengigkeiten ...
    ".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -q -r requirements.txt
    if errorlevel 1 (
        echo  [FEHLER] Abhaengigkeiten konnten nicht installiert werden.
        pause
        exit /b 1
    )
    copy /y requirements.txt .venv\requirements.installed >nul
)

:: ---- 4. Run -------------------------------------------------
set "PYTHONUTF8=1"
".venv\Scripts\python.exe" delete_tool.py %*
echo.
pause
