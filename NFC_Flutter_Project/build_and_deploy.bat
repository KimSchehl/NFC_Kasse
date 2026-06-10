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
set "WEB_SRC=nfc_kasse_app\build\web"
set "WEB_DEST=backend\webapp"
set "UPDATES_DIR=backend\updates"

:: WEBAPP_ROUTE aus config.env lesen (Fallback: /webapp)
set "WEBAPP_ROUTE=/webapp"
if exist "config.env" (
    for /f "usebackq tokens=1,2 delims== eol=#" %%a in ("config.env") do (
        if "%%a"=="WEBAPP_ROUTE" set "WEBAPP_ROUTE=%%b"
    )
)
set "BASE_HREF=!WEBAPP_ROUTE!/"

:: ---- Auswahl: Was soll gebaut werden? -----------------------
echo  Was soll gebaut werden?
echo.
echo    [1]  APK + Web App  (beides)
echo    [2]  Nur APK
echo    [3]  Nur Web App
echo.
choice /C 123 /N /M "  Auswahl (1/2/3): "
set "SEL=%errorlevel%"
echo.

if "%SEL%"=="1" ( set "BUILD_APK=1" & set "BUILD_WEB=1" )
if "%SEL%"=="2" ( set "BUILD_APK=1" & set "BUILD_WEB=0" )
if "%SEL%"=="3" ( set "BUILD_APK=0" & set "BUILD_WEB=1" )

:: ---- 1. Version lesen ----------------------------------------
if not exist "%PUBSPEC%" (
    echo  [FEHLER] %PUBSPEC% nicht gefunden.
    pause & exit /b 1
)

for /f "usebackq tokens=*" %%v in (`powershell -NoProfile -Command "(Select-String -Path '%PUBSPEC%' -Pattern '^version:').Line.Split(':')[1].Trim()"`) do set "VER_LINE=%%v"

for /f "tokens=1,2 delims=+" %%a in ("!VER_LINE!") do (
    set "SEMVER_OLD=%%a"
    set "BUILD_OLD=%%b"
)
for /f "tokens=1,2,3 delims=." %%a in ("!SEMVER_OLD!") do (
    set "MAJOR=%%a"
    set "MINOR=%%b"
    set "PATCH_OLD=%%c"
)

if not defined MAJOR     ( echo  [FEHLER] Versionsformat ungueltig: !VER_LINE! & pause & exit /b 1 )
if not defined MINOR     ( echo  [FEHLER] Versionsformat ungueltig: !VER_LINE! & pause & exit /b 1 )
if not defined PATCH_OLD ( echo  [FEHLER] Versionsformat ungueltig: !VER_LINE! & pause & exit /b 1 )
if not defined BUILD_OLD ( echo  [FEHLER] Build-Nummer fehlt -- Format muss X.X.X+N sein. & pause & exit /b 1 )

set /a "PATCH_NEW=PATCH_OLD+1"
set /a "BUILD_NEW=BUILD_OLD+1"
set "NEW_SEMVER=!MAJOR!.!MINOR!.!PATCH_NEW!"
set "NEW_VERSION=!NEW_SEMVER!+!BUILD_NEW!"
set "APK_NAME=nfc-kasse_!NEW_SEMVER!.apk"

echo  Aktuelle Version:  !SEMVER_OLD!+!BUILD_OLD!
echo  Neue Version:      !NEW_SEMVER!+!BUILD_NEW!
if "!BUILD_APK!"=="1" echo  Ausgabe-APK:       %UPDATES_DIR%\!APK_NAME!
if "!BUILD_WEB!"=="1" echo  Web Base-Href:     !BASE_HREF!
echo.

:: ---- 2. pubspec.yaml aktualisieren --------------------------
echo  [VERSION] Aktualisiere pubspec.yaml ...
powershell -NoProfile -Command "$c = Get-Content '%PUBSPEC%'; $c = $c -replace '^version: .*', 'version: !NEW_VERSION!'; Set-Content '%PUBSPEC%' -Value $c -Encoding UTF8"
if errorlevel 1 (
    echo  [FEHLER] pubspec.yaml konnte nicht aktualisiert werden.
    pause & exit /b 1
)

:: ---- 3. APK Build (optional) --------------------------------
set "APK_OK=0"
if "!BUILD_APK!"=="1" (
    echo  [APK] Baue Release-APK (das dauert ein paar Minuten^) ...
    cd nfc_kasse_app
    call flutter build apk --release
    set "BUILD_EC=!errorlevel!"
    cd ..

    if "!BUILD_EC!" neq "0" (
        echo.
        echo  [FEHLER] APK-Build fehlgeschlagen -- setze Version zurueck ...
        powershell -NoProfile -Command "$c = Get-Content '%PUBSPEC%'; $c = $c -replace '^version: .*', 'version: !SEMVER_OLD!+!BUILD_OLD!'; Set-Content '%PUBSPEC%' -Value $c -Encoding UTF8" 2>nul
        pause & exit /b 1
    )
    set "APK_OK=1"
)

:: ---- 4. Web Build (optional) --------------------------------
set "WEB_OK=0"
if "!BUILD_WEB!"=="1" (
    echo  [WEB] Baue Flutter Web App (Base-Href: !BASE_HREF!^) ...
    cd nfc_kasse_app
    if not exist "web" (
        echo  [SETUP] Web-Plattform noch nicht aktiviert -- wird einmalig konfiguriert ...
        call flutter create . --platforms web >nul
    )
    call flutter build web --release --no-web-resources-cdn --no-tree-shake-icons --base-href "!BASE_HREF!"
    set "WEB_EC=!errorlevel!"
    cd ..

    if "!WEB_EC!" neq "0" (
        echo  [WARNUNG] Web-Build fehlgeschlagen.
        set "WEB_OK=0"
    ) else (
        set "WEB_OK=1"
    )
)

:: ---- 5. Dateien kopieren ------------------------------------
echo  [COPY] Kopiere Dateien ...

if "!APK_OK!"=="1" (
    if not exist "%UPDATES_DIR%" mkdir "%UPDATES_DIR%"
    copy /y "%APK_SRC%" "%UPDATES_DIR%\!APK_NAME!" >nul
    if errorlevel 1 (
        echo  [FEHLER] APK-Kopieren fehlgeschlagen.
        pause & exit /b 1
    )
    echo  [OK] APK: %UPDATES_DIR%\!APK_NAME!
)

if "!WEB_OK!"=="1" (
    if exist "%WEB_DEST%" rmdir /s /q "%WEB_DEST%"
    xcopy /e /i /q "%WEB_SRC%" "%WEB_DEST%" >nul
    if errorlevel 1 (
        echo  [WARNUNG] Web-Dateien konnten nicht kopiert werden.
    ) else (
        echo  [OK] Web App: %WEB_DEST%\
    )
)

:: ---- Zusammenfassung ----------------------------------------
echo.
echo  ================================================
echo   Fertig!
echo.
echo   Version:  !NEW_SEMVER!+!BUILD_NEW!
if "!APK_OK!"=="1"  echo   APK:      %UPDATES_DIR%\!APK_NAME!
if "!BUILD_APK!"=="1" if "!APK_OK!"=="0" echo   APK:      [fehlgeschlagen]
if "!WEB_OK!"=="1"  echo   Web App:  %WEB_DEST%\  ^(Route: !WEBAPP_ROUTE!^)
if "!BUILD_WEB!"=="1" if "!WEB_OK!"=="0" echo   Web App:  [fehlgeschlagen]
echo.
echo   Starte das Backend neu, damit die Aenderungen
echo   fuer die Nutzer sichtbar werden.
echo  ================================================
echo.
pause
