@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0.."

echo ============================================
echo  NFC-Kasse Backend - Release Installer Build
echo ============================================
echo.

REM --- Step 1: stage the newest APK only (not the full updates/ history) ---
echo [1/5] Staging update seed...
python packaging\pyinstaller\stage_updates_seed.py
if errorlevel 1 goto :error

REM --- Step 2: PyInstaller onedir build ---
echo.
echo [2/5] Building frozen backend (PyInstaller)...
python -m PyInstaller packaging\pyinstaller\nfc_kasse_backend.spec --distpath packaging\pyinstaller\dist --workpath packaging\pyinstaller\build\work --noconfirm
if errorlevel 1 goto :error

REM --- Step 3: fetch WinSW if not already present ---
echo.
echo [3/5] Checking WinSW...
if not exist "packaging\winsw\NfcKasseService.exe" (
    echo   Downloading WinSW v2.12.0...
    powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe' -OutFile 'packaging\winsw\NfcKasseService.exe'"
    if errorlevel 1 goto :error
    REM Known-good SHA256 for WinSW v2.12.0 WinSW-x64.exe, recorded when
    REM first pinned. If this ever mismatches, a release asset changed
    REM unexpectedly -- stop and investigate rather than trusting it.
    powershell -NoProfile -Command "$h = (Get-FileHash 'packaging\winsw\NfcKasseService.exe' -Algorithm SHA256).Hash; if ($h -ne '05B82D46AD331CC16BDC00DE5C6332C1EF818DF8CEEFCD49C726553209B3A0DA') { Write-Error \"SHA256 mismatch: $h\"; exit 1 }"
    if errorlevel 1 goto :error
) else (
    echo   Already present, skipping download.
)

REM --- Step 4: read the release version from pubspec.yaml -------
echo.
echo [4/5] Reading version from nfc_kasse_app\pubspec.yaml...
for /f "usebackq tokens=*" %%v in (`powershell -NoProfile -Command "(Select-String -Path 'nfc_kasse_app\pubspec.yaml' -Pattern '^version:').Line.Split(':')[1].Trim().Split('+')[0]"`) do set "APP_VERSION=%%v"
if not defined APP_VERSION (
    echo ERROR: Could not read version from nfc_kasse_app\pubspec.yaml.
    goto :error
)
echo   Version: %APP_VERSION%

REM --- Step 5: compile the installer -----------------------------
echo.
echo [5/5] Compiling installer (Inno Setup)...
set ISCC="%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not exist %ISCC% set ISCC="%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not exist %ISCC% (
    echo ERROR: Inno Setup 6 not found. Install it first:
    echo   winget install -e --id JRSoftware.InnoSetup
    goto :error
)
%ISCC% "/DMyAppVersion=%APP_VERSION%" packaging\innosetup\nfc_kasse_installer.iss
if errorlevel 1 goto :error

echo.
echo ============================================
echo  Done. Installer (v%APP_VERSION%):
echo  packaging\innosetup\dist\NFC-Kasse-Setup.exe
echo ============================================
exit /b 0

:error
echo.
echo Build failed.
exit /b 1
