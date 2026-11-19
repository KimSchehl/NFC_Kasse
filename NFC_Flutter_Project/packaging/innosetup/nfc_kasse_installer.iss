; NFC-Kasse Backend installer.
; Build with (from repo root, after PyInstaller + WinSW staging are done):
;   "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" packaging\innosetup\nfc_kasse_installer.iss
;
; Expects, relative to this file:
;   ..\pyinstaller\dist\NfcKasseBackend\   (PyInstaller onedir output)
;   ..\winsw\NfcKasseService.exe           (downloaded, see packaging\build_installer.bat)
;   ..\winsw\NfcKasseService.xml
;   ..\pgsql\{bin,lib,share}              (PostgreSQL server, downloaded by build_installer.bat)

#define MyAppName "NFC-Kasse Backend"
; Overridden from build_installer.bat via "ISCC /DMyAppVersion=X.Y.Z ..." --
; that value comes straight from nfc_kasse_app\pubspec.yaml, the same single
; source of truth build_and_deploy.bat already names the APK after. This
; fallback only matters for a manual/local ISCC run without that flag.
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppPublisher "Kim Schehl"
; Real single braces here (not the {{ escape [Setup] directives need for a
; literal leading brace) -- ISPP substitutes {#MyAppId} as plain text before
; Inno's own constant-escaping pass ever runs, so AppId={{#MyAppId} below
; comes out exactly as "AppId={{2EF18757-...}", the form Inno requires. The
; single-brace form is also what [Code] needs for the uninstall registry key.
#define MyAppId "{2EF18757-6135-4143-991F-DA4D728CEE16}"

[Setup]
; Fixed, never change once released -- this is how Inno Setup recognizes
; "this is an upgrade of the same app" across versions.
AppId={{#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\NFC-Kasse
DefaultGroupName=NFC-Kasse
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=NFC-Kasse-Setup
OutputDir=..\..\packaging\innosetup\dist
SetupIconFile=assets\nfc_kasse.ico
UninstallDisplayIcon={app}\NfcKasseBackend.exe
; Auto-creates a log in %TEMP% ("Setup Log <date>.txt") on every run, no
; /LOG flag needed -- otherwise a normal double-click install leaves no
; record at all if something goes wrong, which is exactly the failure mode
; a real customer would hit (they don't know to pass command-line flags).
SetupLogging=yes
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Restart Manager: asks to close the admin tool (Verwaltung\NfcKasseAdmin.exe)
; if it is open during an update -- its files are locked otherwise. Setup
; restarts it afterwards. The backend service is handled in PrepareToInstall.
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "Desktop-Symbol erstellen"; GroupDescription: "Zusätzliche Symbole:"

[Dirs]
; Keeps kasse.db/config.env/bon.yaml/logs/backups untouched by Inno's own
; uninstall-file-removal logic and by every UPGRADE install (Inno never
; removes an uninsneveruninstall dir just because a newer version is being
; installed over it). Program files in {app} do NOT get this flag -- those
; are meant to disappear on uninstall. A real, standalone REMOVAL can still
; delete this directory -- see InitializeUninstall/CurUninstallStepChanged below,
; which ask the user first (opt-in, defaults to keeping the data).
Name: "{commonappdata}\NFC-Kasse"; Flags: uninsneveruninstall

[Files]
Source: "..\pyinstaller\dist\NfcKasseBackend\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "..\winsw\NfcKasseService.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\winsw\NfcKasseService.xml"; DestDir: "{app}"; Flags: ignoreversion
; PostgreSQL server + tools. Always installed: pg_dump/pg_restore are needed
; for backups even when an existing PostgreSQL server is used. The database
; cluster itself (pgdata) lives in {commonappdata}, never in {app}.
Source: "..\pgsql\*"; DestDir: "{app}\pgsql"; Flags: recursesubdirs createallsubdirs ignoreversion
; Nothing here ever targets {commonappdata} -- an upgrade install therefore
; never touches real data, purely by construction, no special-case logic
; needed.
; Verwaltungstool -- own subfolder so its bundled Flutter runtime DLLs never
; sit alongside (or risk name-colliding with) the backend's own files.
Source: "..\..\nfc_kasse_admin\build\windows\x64\runner\Release\*"; DestDir: "{app}\Verwaltung"; Flags: recursesubdirs createallsubdirs ignoreversion

[Registry]
; Web Bluetooth (the BLE NFC reader, see nfc-ble-reader/) only works in a
; "secure context" (HTTPS or localhost) -- the webapp itself is plain HTTP,
; so without this, using it from a browser ON THIS SAME PC needs the
; "unsafely-treat-insecure-origin-as-secure" flag set by hand in
; edge://flags / chrome://flags, which resets on browser updates and is easy
; to forget after a reinstall. This achieves the same thing via the
; documented enterprise policy instead, for both browsers (whichever the
; customer actually has) -- persists across updates, no manual flag needed.
; Assumes the default PORT=8000, same caveat as the "NFC-Kasse öffnen"
; shortcuts below -- goes stale if PORT is edited in config.env afterward.
; Two origins covered: localhost (browsing on this same PC) and
; nfc-kasse.lan (the local DNS name this install is reachable under from
; other devices on the LAN, e.g. via an AdGuard/router DNS rewrite) -- still
; only takes effect on THIS PC's own browser policy, though; a browser on a
; *different* device needs the same policy set on that device separately.
Root: HKLM; Subkey: "SOFTWARE\Policies\Microsoft\Edge\OverrideSecurityRestrictionsOnInsecureOrigin"; ValueType: string; ValueName: "1"; ValueData: "http://localhost:8000"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\Policies\Microsoft\Edge\OverrideSecurityRestrictionsOnInsecureOrigin"; ValueType: string; ValueName: "2"; ValueData: "http://nfc-kasse.lan:8000"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\Policies\Google\Chrome\OverrideSecurityRestrictionsOnInsecureOrigin"; ValueType: string; ValueName: "1"; ValueData: "http://localhost:8000"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\Policies\Google\Chrome\OverrideSecurityRestrictionsOnInsecureOrigin"; ValueType: string; ValueName: "2"; ValueData: "http://nfc-kasse.lan:8000"; Flags: uninsdeletekey

[Icons]
Name: "{group}\NFC-Kasse öffnen"; Filename: "http://localhost:8000/webapp"
Name: "{group}\Dienst starten"; Filename: "{app}\NfcKasseService.exe"; Parameters: "start"
Name: "{group}\Dienst stoppen"; Filename: "{app}\NfcKasseService.exe"; Parameters: "stop"
Name: "{group}\NFC-Kasse Verwaltung"; Filename: "{app}\Verwaltung\NfcKasseAdmin.exe"
Name: "{commondesktop}\NFC-Kasse öffnen"; Filename: "http://localhost:8000/webapp"; Tasks: desktopicon
Name: "{commondesktop}\NFC-Kasse Verwaltung"; Filename: "{app}\Verwaltung\NfcKasseAdmin.exe"; Tasks: desktopicon
; "NFC-Kasse Backend deinstallieren" is auto-generated by Inno Setup.

[Run]
; Update: the bundled PostgreSQL service was stopped in PrepareToInstall.
; Fails harmlessly when it doesn't exist (fresh install / existing server).
Filename: "{sys}\sc.exe"; Parameters: "start NfcKassePostgres"; Flags: runhidden waituntilterminated; StatusMsg: "Datenbankdienst wird gestartet..."
; BeforeInstall: RunDbSetup creates/connects the database (see [Code]) right
; before the backend service is registered.
Filename: "{app}\NfcKasseService.exe"; Parameters: "install"; Flags: runhidden waituntilterminated; StatusMsg: "Windows-Dienst wird registriert..."; BeforeInstall: RunDbSetup
; Delete first: every (re)install used to add another identical rule.
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""NFC-Kasse Backend"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""NFC-Kasse Backend"" dir=in action=allow program=""{app}\NfcKasseBackend.exe"" enable=yes profile=any"; Flags: runhidden waituntilterminated; StatusMsg: "Firewall-Regel wird eingerichtet..."
; Scoped by program path, not localport -- PORT is user-editable in
; config.env after install, so a port-scoped rule would go stale the moment
; someone changes it. Program-scoped stays correct regardless.
Filename: "{app}\NfcKasseService.exe"; Parameters: "start"; Flags: runhidden waituntilterminated; StatusMsg: "Dienst wird gestartet..."; Check: DbReady
Filename: "http://localhost:8000/webapp"; Flags: postinstall shellexec skipifsilent nowait; Description: "NFC-Kasse jetzt öffnen"; Check: DbReady
; Assumes fresh-install defaults (HOST/PORT/WEBAPP_ROUTE as generated by
; service_main.py's config.env template) -- correct for a first install,
; goes stale if PORT/WEBAPP_ROUTE are edited later. Same caveat applies to
; the Start Menu/Desktop shortcuts above.

[UninstallRun]
; Inno Setup guarantees these run BEFORE [Files]-installed files are
; deleted -- required ordering, since a service can't be cleanly unregistered
; once the exe backing it no longer exists.
Filename: "{app}\NfcKasseService.exe"; Parameters: "stopwait"; Flags: runhidden waituntilterminated; RunOnceId: "StopService"
Filename: "{app}\NfcKasseService.exe"; Parameters: "uninstall"; Flags: runhidden waituntilterminated; RunOnceId: "UninstallService"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""NFC-Kasse Backend"""; Flags: runhidden waituntilterminated; RunOnceId: "RemoveFirewallRule"
; Bundled PostgreSQL (if it was installed): "net stop" waits until it is
; down, then the registration goes. Its data (pgdata) stays unless the user
; chose to delete the data folder. Harmless when the service doesn't exist.
Filename: "{sys}\net.exe"; Parameters: "stop NfcKassePostgres"; Flags: runhidden waituntilterminated; RunOnceId: "StopPostgres"
Filename: "{sys}\sc.exe"; Parameters: "delete NfcKassePostgres"; Flags: runhidden waituntilterminated; RunOnceId: "DeletePostgresService"

[Code]
var
  ModePage: TWizardPage;
  ClosingAfterUninstall: Boolean;
  InstallRadio, UpdateRadio, UninstallRadio: TNewRadioButton;

function UninstallRegKey: String;
begin
  Result := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppId}_is1';
end;

function IsAlreadyInstalled: Boolean;
begin
  Result := RegKeyExists(HKLM, UninstallRegKey);
end;

// ---------------------------------------------------------------------------
// Database (PostgreSQL): wizard pages + NfcKasseBackend.exe db-setup
// ---------------------------------------------------------------------------
// Shown only while config.env has no DATABASE_URL yet (fresh install, or the
// first update from a SQLite version). Either a bundled PostgreSQL server is
// installed (root user + password chosen here) or an existing server is used
// (an admin login is asked for, used once and not stored). In both cases a
// dedicated kasse user + database nfc_kasse are created; only that user ends
// up in config.env. Third way for IT admins who won't type an admin password
// into a foreign setup: the wizard shows the SQL, they run it themselves and
// only enter the kasse user here ("prepared" in backend/pg_setup.py).
// DbModePage index: 0 = install, 1 = existing (Setup creates), 2 = prepared.

var
  DbModePage: TInputOptionWizardPage;
  RootPage, ExistingPage, KassePage: TInputQueryWizardPage;
  CmdPage: TOutputMsgMemoWizardPage;
  RootShow, ExistingShow, KasseShow: TNewCheckBox;
  DbSetupNeeded, DbSetupFailed: Boolean;

function ConfigHasDatabaseUrl: Boolean;
var
  Lines: TArrayOfString;
  i: Integer;
  Line: String;
begin
  Result := False;
  if not LoadStringsFromFile(ExpandConstant('{commonappdata}\NFC-Kasse\config.env'), Lines) then
    exit;
  for i := 0 to GetArrayLength(Lines) - 1 do
  begin
    Line := Trim(Lines[i]);
    if (Pos('DATABASE_URL=', Line) = 1) and (Length(Line) > Length('DATABASE_URL=')) then
      Result := True;
  end;
end;

// EnterpriseDB's installer (the usual way PostgreSQL gets onto Windows)
// registers itself here.
function PostgresDetected: Boolean;
begin
  Result := RegKeyExists(HKLM, 'SOFTWARE\PostgreSQL\Installations');
end;

procedure ShowPasswordsClick(Sender: TObject);
var
  Hide: Boolean;
begin
  Hide := not TNewCheckBox(Sender).Checked;
  if Sender = RootShow then
  begin
    RootPage.Edits[1].Password := Hide;
    RootPage.Edits[2].Password := Hide;
  end
  else if Sender = ExistingShow then
    ExistingPage.Edits[3].Password := Hide
  else
  begin
    KassePage.Edits[1].Password := Hide;
    KassePage.Edits[2].Password := Hide;
  end;
end;

// "Passwörter anzeigen" below the page's last edit.
function AddShowCheckBox(Page: TInputQueryWizardPage; LastEdit: Integer): TNewCheckBox;
begin
  Result := TNewCheckBox.Create(Page);
  Result.Parent := Page.Surface;
  Result.Caption := 'Passwörter anzeigen';
  Result.Top := Page.Edits[LastEdit].Top + Page.Edits[LastEdit].Height + ScaleY(10);
  Result.Width := Page.SurfaceWidth;
  Result.OnClick := @ShowPasswordsClick;
end;

procedure CreateDatabasePages;
begin
  DbSetupNeeded := not ConfigHasDatabaseUrl;

  DbModePage := CreateInputOptionPage(wpSelectDir, 'Datenbank',
    'Wo sollen die Kassendaten gespeichert werden?',
    'NFC-Kasse speichert alle Daten in einer PostgreSQL-Datenbank.', True, False);
  DbModePage.Add('PostgreSQL mitinstallieren (empfohlen)');
  DbModePage.Add('Vorhandenen PostgreSQL-Server verwenden, das Setup legt Benutzer und Datenbank an (Administrator-Zugang nötig)');
  DbModePage.Add('Vorhandenen PostgreSQL-Server verwenden, Benutzer und Datenbank legt der Datenbank-Administrator selbst an (ohne Administrator-Zugang)');
  if PostgresDetected then
    DbModePage.SelectedValueIndex := 1
  else
    DbModePage.SelectedValueIndex := 0;

  RootPage := CreateInputQueryPage(DbModePage.ID, 'Datenbank-Administrator',
    'Root-Benutzer des neuen PostgreSQL-Servers anlegen',
    'Mit diesem Benutzer verwalten Sie den Datenbankserver. Das Passwort gut ' +
    'aufbewahren, es lässt sich nicht wiederherstellen.');
  RootPage.Add('Benutzername:', False);
  RootPage.Add('Passwort (mindestens 8 Zeichen):', True);
  RootPage.Add('Passwort wiederholen:', True);
  RootPage.Values[0] := 'postgres';
  RootShow := AddShowCheckBox(RootPage, 2);

  ExistingPage := CreateInputQueryPage(RootPage.ID, 'Vorhandener PostgreSQL-Server',
    'Zugang zum Datenbankserver',
    'Ein Benutzer, der Benutzer und Datenbanken anlegen darf (z. B. postgres). ' +
    'Er wird nur für die Einrichtung verwendet und nicht gespeichert.');
  ExistingPage.Add('Server:', False);
  ExistingPage.Add('Port:', False);
  ExistingPage.Add('Benutzername:', False);
  ExistingPage.Add('Passwort:', True);
  ExistingPage.Values[0] := 'localhost';
  ExistingPage.Values[1] := '5432';
  ExistingPage.Values[2] := 'postgres';
  ExistingShow := AddShowCheckBox(ExistingPage, 3);

  CmdPage := CreateOutputMsgMemoPage(ExistingPage.ID, 'Benutzer und Datenbank anlegen',
    'Befehle für den Datenbank-Administrator',
    'Diese Befehle als Administrator auf dem PostgreSQL-Server ausführen (z. B. in psql) ' +
    'und danach auf Weiter klicken. Benutzername und Passwort dürfen Sie anpassen, ' +
    'die Datenbank muss nfc_kasse heißen und diesem Benutzer gehören.', '');

  KassePage := CreateInputQueryPage(CmdPage.ID, 'Kassensystem-Benutzer',
    'Eigener Datenbank-Benutzer für die NFC-Kasse',
    'Mit diesem Benutzer arbeitet die Kasse. Er erhält nur Zugriff auf die ' +
    'Datenbank nfc_kasse und wird in config.env gespeichert.');
  KassePage.Add('Benutzername:', False);
  KassePage.Add('Passwort (mindestens 8 Zeichen):', True);
  KassePage.Add('Passwort wiederholen:', True);
  KassePage.Values[0] := 'nfc_kasse';
  KasseShow := AddShowCheckBox(KassePage, 2);
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (PageID = DbModePage.ID) or (PageID = RootPage.ID) or (PageID = ExistingPage.ID) or
     (PageID = CmdPage.ID) or (PageID = KassePage.ID) then
  begin
    if not DbSetupNeeded then
      Result := True
    else if PageID = RootPage.ID then
      Result := DbModePage.SelectedValueIndex <> 0
    else if PageID = ExistingPage.ID then
      Result := DbModePage.SelectedValueIndex = 0
    else if PageID = CmdPage.ID then
      Result := DbModePage.SelectedValueIndex <> 2;
  end;
end;

// ExistingPage asks for the admin login only when Setup creates the user;
// CmdPage shows the SQL for the server just entered.
procedure CurPageChanged(CurPageID: Integer);
var
  AskAdmin: Boolean;
  NL: String;
begin
  if CurPageID = ExistingPage.ID then
  begin
    AskAdmin := DbModePage.SelectedValueIndex = 1;
    ExistingPage.PromptLabels[2].Visible := AskAdmin;
    ExistingPage.Edits[2].Visible := AskAdmin;
    ExistingPage.PromptLabels[3].Visible := AskAdmin;
    ExistingPage.Edits[3].Visible := AskAdmin;
    ExistingShow.Visible := AskAdmin;
    if AskAdmin then
      ExistingPage.SubCaptionLabel.Caption := 'Ein Benutzer, der Benutzer und Datenbanken anlegen darf ' +
        '(z. B. postgres). Er wird nur für die Einrichtung verwendet und nicht gespeichert.'
    else
      ExistingPage.SubCaptionLabel.Caption := 'Adresse des PostgreSQL-Servers, auf dem der ' +
        'Datenbank-Administrator Benutzer und Datenbank anlegt.';
  end
  else if CurPageID = CmdPage.ID then
  begin
    NL := #13#10;
    CmdPage.RichEditViewer.Lines.Text :=
      'Anmelden, zum Beispiel:' + NL +
      '  psql -h ' + Trim(ExistingPage.Values[0]) + ' -p ' + Trim(ExistingPage.Values[1]) + ' -U postgres' + NL + NL +
      'Dann:' + NL +
      '  CREATE ROLE nfc_kasse LOGIN PASSWORD ''HIER-EIN-PASSWORT'';' + NL +
      '  CREATE DATABASE nfc_kasse OWNER nfc_kasse ENCODING ''UTF8'' TEMPLATE template0;' + NL + NL +
      'Läuft der Server auf einem anderen Rechner, muss er Verbindungen von diesem ' +
      'Rechner zulassen (listen_addresses in postgresql.conf, Eintrag in pg_hba.conf). ' +
      'Die Kasse braucht danach nur die Rechte als Besitzer dieser einen Datenbank.';
  end;
end;

// Lower-case letters, digits and "_", not starting with a digit -- a plain
// PostgreSQL identifier.
function CheckUserName(const Name: String): Boolean;
var
  i: Integer;
  c: Char;
begin
  Result := (Length(Name) >= 1) and (Length(Name) <= 63);
  for i := 1 to Length(Name) do
  begin
    c := Name[i];
    if not (((c >= 'a') and (c <= 'z')) or (c = '_') or ((c >= '0') and (c <= '9') and (i > 1))) then
      Result := False;
  end;
  if not Result then
    MsgBox('Benutzername: nur Kleinbuchstaben, Ziffern und _ verwenden, nicht mit einer Ziffer beginnen.',
      mbError, MB_OK);
end;

function CheckNewPassword(const Password, Repeated: String): Boolean;
begin
  Result := False;
  if Length(Password) < 8 then
    MsgBox('Das Passwort muss mindestens 8 Zeichen lang sein.', mbError, MB_OK)
  else if Password <> Repeated then
    MsgBox('Die beiden Passwörter stimmen nicht überein.', mbError, MB_OK)
  else
    Result := True;
end;

function SuperUserName: String;
begin
  if DbModePage.SelectedValueIndex = 0 then
    Result := RootPage.Values[0]
  else if DbModePage.SelectedValueIndex = 1 then
    Result := ExistingPage.Values[2]
  else
    Result := '';
end;

function CheckDatabasePage(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = RootPage.ID then
    Result := CheckUserName(RootPage.Values[0]) and
      CheckNewPassword(RootPage.Values[1], RootPage.Values[2])
  else if CurPageID = ExistingPage.ID then
  begin
    if (Trim(ExistingPage.Values[0]) = '') or (StrToIntDef(ExistingPage.Values[1], 0) <= 0) then
    begin
      MsgBox('Bitte Server und Port angeben.', mbError, MB_OK);
      Result := False;
    end
    else if (DbModePage.SelectedValueIndex = 1) and
       ((Trim(ExistingPage.Values[2]) = '') or (ExistingPage.Values[3] = '')) then
    begin
      MsgBox('Bitte Benutzername und Passwort des Administrators angeben.', mbError, MB_OK);
      Result := False;
    end;
  end
  else if CurPageID = KassePage.ID then
  begin
    if DbModePage.SelectedValueIndex = 2 then
    begin
      // Created by the IT admin: whatever password he chose, just typed twice.
      Result := (KassePage.Values[1] <> '') and (KassePage.Values[1] = KassePage.Values[2]);
      if not Result then
        MsgBox('Bitte das Passwort des Benutzers zweimal gleich eingeben.', mbError, MB_OK);
      Result := Result and CheckUserName(KassePage.Values[0]);
    end
    else
      Result := CheckUserName(KassePage.Values[0]) and
        CheckNewPassword(KassePage.Values[1], KassePage.Values[2]);
    if Result and (KassePage.Values[0] = SuperUserName) then
    begin
      MsgBox('Der Kassensystem-Benutzer muss sich vom Administrator unterscheiden.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function JsonText(const S: String): String;
begin
  Result := S;
  StringChangeEx(Result, '\', '\\', True);
  StringChangeEx(Result, '"', '\"', True);
  Result := '"' + Result + '"';
end;

// [Run] BeforeInstall of the backend service registration. The passwords go
// through a file in Setup's own temp folder (deleted right after), never
// through a command line.
procedure RunDbSetup;
var
  Json, InFile, ResFile, Msg, NL: String;
  Lines: TArrayOfString;
  ResultCode: Integer;
begin
  if not DbSetupNeeded then
    exit;
  if DbModePage.SelectedValueIndex = 0 then
    Json := '{"mode":"install","superuser":' + JsonText(RootPage.Values[0]) +
      ',"superpassword":' + JsonText(RootPage.Values[1])
  else if DbModePage.SelectedValueIndex = 2 then
    Json := '{"mode":"prepared","host":' + JsonText(Trim(ExistingPage.Values[0])) +
      ',"port":' + IntToStr(StrToIntDef(ExistingPage.Values[1], 5432))
  else
    Json := '{"mode":"existing","host":' + JsonText(Trim(ExistingPage.Values[0])) +
      ',"port":' + IntToStr(StrToIntDef(ExistingPage.Values[1], 5432)) +
      ',"superuser":' + JsonText(Trim(ExistingPage.Values[2])) +
      ',"superpassword":' + JsonText(ExistingPage.Values[3]);
  Json := Json + ',"pg_bin":' + JsonText(ExpandConstant('{app}\pgsql\bin')) +
    ',"kasse_user":' + JsonText(KassePage.Values[0]) +
    ',"kasse_password":' + JsonText(KassePage.Values[1]) + '}';

  InFile := ExpandConstant('{tmp}\db-setup.json');
  ResFile := ExpandConstant('{tmp}\db-setup-result.txt');
  SetArrayLength(Lines, 1);
  Lines[0] := Json;
  SaveStringsToUTF8File(InFile, Lines, False);
  WizardForm.StatusLabel.Caption := 'Datenbank wird eingerichtet...';
  Exec(ExpandConstant('{app}\NfcKasseBackend.exe'),
    'db-setup --input "' + InFile + '" --result "' + ResFile + '"',
    ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);
  DeleteFile(InFile);
  if ResultCode = 0 then
    exit;

  DbSetupFailed := True;
  Msg := 'Unbekannter Fehler (Code ' + IntToStr(ResultCode) + ').';
  if LoadStringsFromFile(ResFile, Lines) and (GetArrayLength(Lines) > 0) then
    Msg := Lines[0];
  NL := #13#10;
  MsgBox('Die Datenbank konnte nicht eingerichtet werden:' + NL + NL + Msg + NL + NL +
    'Der Dienst wird nicht gestartet. Bitte das Setup erneut ausführen.', mbError, MB_OK);
end;

// [Run] Check: start the service only with a working database.
function DbReady: Boolean;
begin
  Result := not DbSetupFailed;
end;

// A plain re-run of Setup (e.g. double-clicking the download again to
// update) would otherwise walk straight into the normal wizard with no
// indication of whether this is a fresh install or an upgrade, and no way
// to uninstall short of hunting it down in "Apps & Features". This page
// makes that explicit and steers "Deinstallieren" to the existing
// uninstaller instead of duplicating its logic here.
procedure InitializeWizard;
var
  installed: Boolean;
begin
  installed := IsAlreadyInstalled;

  ModePage := CreateCustomPage(wpWelcome, 'Installationsmodus',
    'Was möchten Sie tun?');

  InstallRadio := TNewRadioButton.Create(ModePage);
  InstallRadio.Parent := ModePage.Surface;
  InstallRadio.Caption := 'Installieren';
  InstallRadio.Top := 0;
  InstallRadio.Width := ModePage.SurfaceWidth;
  InstallRadio.Enabled := not installed;
  InstallRadio.Checked := not installed;

  UpdateRadio := TNewRadioButton.Create(ModePage);
  UpdateRadio.Parent := ModePage.Surface;
  UpdateRadio.Caption := 'Aktualisieren';
  UpdateRadio.Top := InstallRadio.Top + InstallRadio.Height + 12;
  UpdateRadio.Width := ModePage.SurfaceWidth;
  UpdateRadio.Enabled := installed;
  UpdateRadio.Checked := installed;

  UninstallRadio := TNewRadioButton.Create(ModePage);
  UninstallRadio.Parent := ModePage.Surface;
  UninstallRadio.Caption := 'Deinstallieren';
  UninstallRadio.Top := UpdateRadio.Top + UpdateRadio.Height + 12;
  UninstallRadio.Width := ModePage.SurfaceWidth;
  UninstallRadio.Enabled := installed;

  CreateDatabasePages;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  uninstallString: String;
  resultCode: Integer;
begin
  Result := CheckDatabasePage(CurPageID);
  if (CurPageID <> ModePage.ID) or not UninstallRadio.Checked then
    exit;

  if RegQueryStringValue(HKLM, UninstallRegKey, 'UninstallString', uninstallString) then
    Exec(RemoveQuotes(uninstallString), '', '', SW_SHOW, ewWaitUntilTerminated, resultCode)
  else
    MsgBox('Bestehende Installation konnte nicht gefunden werden.', mbError, MB_OK);

  // Whatever happened above (uninstalled, or the uninstaller's own confirm
  // prompt was cancelled), this Setup run is done -- continuing on to
  // Select Destination/Ready/Install would just reinstall right over
  // whatever was or wasn't just removed. Abort does NOT end Setup from
  // NextButtonClick (it only cancels the page change, the wizard stayed
  // open), so close the wizard; CancelButtonClick skips the "really cancel?"
  // question for this case.
  ClosingAfterUninstall := True;
  Result := False;
  WizardForm.Close;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if ClosingAfterUninstall then
    Confirm := False;
end;

// True while a process with this image name is still alive. tasklist's
// output goes through cmd into a temp file because Exec can't capture
// stdout; the filter makes it print the image name only on a match.
function ProcessRunning(const ExeName: String): Boolean;
var
  TmpFile: String;
  Output: AnsiString;
  ResultCode: Integer;
begin
  Result := False;
  TmpFile := ExpandConstant('{tmp}\tasklist.txt');
  if Exec(ExpandConstant('{cmd}'), '/C tasklist /NH /FI "IMAGENAME eq ' + ExeName +
      '" > "' + TmpFile + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and
     LoadStringFromFile(TmpFile, Output) then
    Result := Pos(Lowercase(ExeName), Lowercase(String(Output))) > 0;
end;

// Waits up to TimeoutSec for every process of ExeName to exit, then kills
// the rest. Returns False only if one survives even taskkill.
function WaitForExit(const ExeName: String; TimeoutSec: Integer): Boolean;
var
  i, ResultCode: Integer;
begin
  for i := 1 to TimeoutSec * 2 do
  begin
    if not ProcessRunning(ExeName) then
    begin
      Result := True;
      exit;
    end;
    Sleep(500);
  end;
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM ' + ExeName, '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
  for i := 1 to 10 do
  begin
    if not ProcessRunning(ExeName) then
    begin
      Result := True;
      exit;
    end;
    Sleep(500);
  end;
  Result := not ProcessRunning(ExeName);
end;

// Upgrade-in-place safety: everything that holds files in {app} open must be
// gone before [Files] runs, or replacing NfcKasseBackend.exe fails with
// "DeleteFile ... Code 5, Access denied". Runs on the "Vorbereitung" page,
// before Inno's own Restart-Manager check (CloseApplications), and can still
// abort cleanly with a message instead of failing halfway through [Files].
//
// WinSW 2.x 'stop' only SENDS the stop request and returns at once; the
// backend then needs a few seconds to shut down (open SSE streams of the
// customer display / leaderboard, mDNS goodbye), so 'stopwait' is used and
// the process is additionally waited for -- and killed as a last resort,
// which is safe: database commits are atomic, the service is stopped anyway.
// All calls are harmless on a fresh install (non-zero exit, ignored).
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  ServiceExe: String;
begin
  Result := '';
  ServiceExe := ExpandConstant('{app}\NfcKasseService.exe');
  if FileExists(ServiceExe) then
  begin
    Exec(ServiceExe, 'stopwait', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    // Also uninstall the old registration, not just stop it -- otherwise
    // [Run]'s later 'install' step fails with "service already exists"
    // every single upgrade (harmless -- the following 'start' step still
    // succeeds -- but it logs a scary-looking FATAL line in wrapper.log
    // for something that isn't actually a problem). Re-registering fresh
    // each time also means an updated WinSW XML (e.g. changed recovery
    // settings in a future release) actually takes effect on upgrade,
    // rather than the SCM keeping stale settings from the previous
    // version's registration.
    Exec(ServiceExe, 'uninstall', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  // The bundled PostgreSQL holds {app}\pgsql open; "net stop" waits until it
  // is down ([Run] starts it again). Nothing happens without that service.
  Exec(ExpandConstant('{sys}\net.exe'), 'stop NfcKassePostgres', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

  // The service process itself, plus any admin_cli run the admin tool
  // started (backup, Fest start, licence check), which use the same exe.
  if not WaitForExit('NfcKasseBackend.exe', 20) or
     not WaitForExit('NfcKasseService.exe', 5) then
    Result := 'Der NFC-Kasse-Dienst konnte nicht beendet werden. ' +
      'Bitte den Computer neu starten und das Setup erneut ausführen.';
end;

// ---------------------------------------------------------------------------
// Uninstaller: optional removal of C:\ProgramData\NFC-Kasse\
// ---------------------------------------------------------------------------

var
  DeleteDataDirConfirmed: Boolean;

// InitializeUninstall runs before Inno's own "really remove NFC-Kasse
// Backend?" confirmation, which is exactly what we want -- asking about
// data loss up front, with "Nein" as the safe default (MB_DEFBUTTON2), so
// hitting Enter without reading never destroys anything.
function InitializeUninstall(): Boolean;
var
  DataDir, NL, Msg: String;
begin
  Result := True;
  DataDir := ExpandConstant('{commonappdata}\NFC-Kasse');
  DeleteDataDirConfirmed := False;
  if DirExists(DataDir) then
  begin
    // Built via a local NL variable rather than inline #13#10 -- ISPP (the
    // preprocessor, a separate pass over the raw text before Pascal Script
    // ever sees it) treats a leading '#' on any line as a directive marker,
    // so a continuation line starting with "#13#10 + ..." fails to compile
    // with "Unknown preprocessor directive". This sidesteps it entirely.
    NL := #13#10;
    Msg := 'Sollen auch alle gespeicherten Daten gelöscht werden?' + NL + NL +
      'ACHTUNG: Dies löscht unwiderruflich die Konfiguration (config.env), ' +
      'die Datenbank (Ordner pgdata) mit allen Kunden, Guthaben und Buchungen, ' +
      'alle Backups, das Bon-Layout (bon.yaml) und alle Protokolle unter:' +
      NL + DataDir + NL + NL +
      'Bei einer späteren Neuinstallation stehen diese Daten dann NICHT ' +
      'mehr zur Verfügung. Wählen Sie "Nein", um sie zu behalten.';
    DeleteDataDirConfirmed := (MsgBox(Msg, mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES);
  end;
end;

// Opt-in only (the answer from InitializeUninstall); unconfirmed, the data
// folder -- config.env, pgdata, bon.yaml, backups, logs -- stays untouched.
// Not an [UninstallDelete] entry with a Check: Inno evaluates such a Check
// while INSTALLING (when it writes the uninstall log), where this answer
// doesn't exist yet -- the entry was never recorded and the folder always
// survived. Runs after services and program files are gone ([UninstallRun]
// stopped NfcKassePostgres, so pgdata is no longer locked).
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) and DeleteDataDirConfirmed then
    DelTree(ExpandConstant('{commonappdata}\NFC-Kasse'), True, True, True);
end;
