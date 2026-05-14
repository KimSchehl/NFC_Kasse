@echo off
setlocal enabledelayedexpansion
title NFC-Kasse -- Build und Deploy
cd /d "%~dp0"

echo.
echo  ================================================
echo   NFC-Kasse -- Build und Deploy
echo  ================================================
echo.

set "PUBSPEC=nfc_kasse_app\pubspec.yaml"
set "APK_SRC=nfc_kasse_app\build\app\outputs\flutter-apk\app-release.apk"
set "UPDATES_DIR=backend\updates"

:: ---- 1. Aktuelle Version aus pubspec.yaml lesen -------------
if not exist "%PUBSPEC%" (
    echo  [FEHLER] %PUBSPEC% nicht gefunden.
    pause & exit /b 1
)

for /f "usebackq tokens=*" %%v in (`powershell -NoProfile -Command "(Select-String -Path '%PUBSPEC%' -Pattern '^version:').Line.Split(':')[1].Trim()"`) do set "VER_LINE=%%v"

:: Semver und Build-Nummer trennen  (z.B. "1.0.0+1" -> "1.0.0" und "1")
for /f "tokens=1,2 delims=+" %%a in ("!VER_LINE!") do (
    set "SEMVER_OLD=%%a"
    set "BUILD_OLD=%%b"
)
:: Major, Minor, Patch trennen
for /f "tokens=1,2,3 delims=." %%a in ("!SEMVER_OLD!") do (
    set "MAJOR=%%a"
    set "MINOR=%%b"
    set "PATCH_OLD=%%c"
)

if not defined MAJOR   ( echo  [FEHLER] Versionsformat ungueltig: !VER_LINE! & pause & exit /b 1 )
if not defined MINOR   ( echo  [FEHLER] Versionsformat ungueltig: !VER_LINE! & pause & exit /b 1 )
if not defined PATCH_OLD ( echo  [FEHLER] Versionsformat ungueltig: !VER_LINE! & pause & exit /b 1 )
if not defined BUILD_OLD ( echo  [FEHLER] Build-Nummer fehlt in pubspec.yaml -- Format muss X.X.X+N sein. & pause & exit /b 1 )

echo  Aktuelle Version:  !SEMVER_OLD!+!BUILD_OLD!

:: ---- 2. Patch + Build hochzaehlen -------------------------
set /a "PATCH_NEW=PATCH_OLD+1"
set /a "BUILD_NEW=BUILD_OLD+1"
set "NEW_SEMVER=!MAJOR!.!MINOR!.!PATCH_NEW!"
set "NEW_VERSION=!NEW_SEMVER!+!BUILD_NEW!"
set "APK_NAME=nfc-kasse_!NEW_SEMVER!.apk"

echo  Neue Version:      !NEW_SEMVER!+!BUILD_NEW!
echo  Ausgabe-APK:       %UPDATES_DIR%\!APK_NAME!
echo.

:: ---- 3. pubspec.yaml aktualisieren -------------------------
echo  [1/3] Aktualisiere pubspec.yaml ...
powershell -NoProfile -Command "$c = Get-Content '%PUBSPEC%'; $c = $c -replace '^version: .*', 'version: !NEW_VERSION!'; Set-Content '%PUBSPEC%' -Value $c -Encoding UTF8"
if errorlevel 1 (
    echo  [FEHLER] pubspec.yaml konnte nicht aktualisiert werden.
    pause & exit /b 1
)

:: ---- 4. Flutter Build --------------------------------------
echo  [2/3] Baue Release-APK (das dauert ein paar Minuten) ...
cd nfc_kasse_app
call flutter build apk --release
set "BUILD_EC=!errorlevel!"
cd ..

if "!BUILD_EC!" neq "0" (
    echo.
    echo  [FEHLER] Build fehlgeschlagen -- setze Version zurueck auf !SEMVER_OLD!+!BUILD_OLD! ...
    powershell -NoProfile -Command "$c = Get-Content '%PUBSPEC%'; $c = $c -replace '^version: .*', 'version: !SEMVER_OLD!+!BUILD_OLD!'; Set-Content '%PUBSPEC%' -Value $c -Encoding UTF8" 2>nul
    pause & exit /b 1
)

:: ---- 5. APK nach backend/updates kopieren ------------------
echo  [3/3] Kopiere APK nach %UPDATES_DIR% ...
if not exist "%UPDATES_DIR%" mkdir "%UPDATES_DIR%"
copy /y "%APK_SRC%" "%UPDATES_DIR%\!APK_NAME!" >nul
if errorlevel 1 (
    echo  [FEHLER] Kopieren fehlgeschlagen.
    pause & exit /b 1
)

echo.
echo  ================================================
echo   Fertig!
echo.
echo   Version:  !NEW_SEMVER!+!BUILD_NEW!
echo   Datei:    %UPDATES_DIR%\!APK_NAME!
echo.
echo   Starte das Backend neu, damit das Update
echo   fuer die App sichtbar wird.
echo  ================================================
echo.
pause
