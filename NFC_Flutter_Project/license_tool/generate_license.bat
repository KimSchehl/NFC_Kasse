@echo off
:: Doppelklick-Start fuer generate_license.py (Lizenz-Keys erzeugen).
:: Laeuft immer aus diesem Ordner, damit private_key.pem gefunden wird.
cd /d "%~dp0"

set "PYTHON=py"
py --version >nul 2>&1 || set "PYTHON=python"
%PYTHON% --version >nul 2>&1 || (
    echo [FEHLER] Python nicht gefunden. Bitte zuerst start_backend.bat ausfuehren oder Python installieren.
    pause
    exit /b 1
)

%PYTHON% -c "import cryptography" >nul 2>&1 || (
    echo [SETUP] Installiere cryptography ...
    %PYTHON% -m pip install cryptography || (
        echo [FEHLER] cryptography konnte nicht installiert werden.
        pause
        exit /b 1
    )
)

:: Das Skript wartet am Ende selbst auf einen Tastendruck (auch bei Fehlern).
%PYTHON% generate_license.py
