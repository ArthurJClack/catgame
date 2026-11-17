; One-click installer for Cat Game (Inno Setup 6).
; Built by .github/workflows/release.yml:  iscc /DAppVersion=0.1.42 installer\catgame.iss
; Expects the exported game in build\win\ (CatGame.exe + steam dlls, relative to the repo root).
;
; - installs per user into %LOCALAPPDATA%\Programs\CatGame, so no admin / UAC prompt
; - start menu + desktop shortcut, launches the game when done
; - the in-game updater re-runs this same setup with /VERYSILENT /UPDATE [/RELAUNCH]

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6A0C7F3E-4C1B-4E57-9B5A-CA7C0FFEE001}
AppName=Cat Game
AppVersion={#AppVersion}
AppVerName=Cat Game {#AppVersion}
AppPublisher=ArthurJClack
AppPublisherURL=https://github.com/ArthurJClack/catgame
AppUpdatesURL=https://github.com/ArthurJClack/catgame/releases
DefaultDirName={localappdata}\Programs\CatGame
DefaultGroupName=Cat Game
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableReadyPage=yes
DisableWelcomePage=yes
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=CatGame-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\CatGame.exe
CloseApplications=force
RestartApplications=no

[Files]
; the exe plus GodotSteam's dlls (multiplayer) and steam_appid.txt
Source: "..\build\win\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{autoprograms}\Cat Game"; Filename: "{app}\CatGame.exe"
Name: "{autodesktop}\Cat Game"; Filename: "{app}\CatGame.exe"; Check: not IsUpdate

[Run]
; normal install: start the game when the wizard closes
Filename: "{app}\CatGame.exe"; Description: "play Cat Game"; Flags: nowait postinstall skipifsilent
; silent update from inside the game (F9): start the new version again
Filename: "{app}\CatGame.exe"; Flags: nowait; Check: WantRelaunch

[Code]
function IsUpdate(): Boolean;
begin
  Result := Pos('/UPDATE', UpperCase(GetCmdTail())) > 0;
end;

function WantRelaunch(): Boolean;
begin
  Result := Pos('/RELAUNCH', UpperCase(GetCmdTail())) > 0;
end;

function InitializeSetup(): Boolean;
begin
  // the game starts the installer and then quits; give it a moment to let go of the exe
  if IsUpdate() then
    Sleep(1500);
  Result := True;
end;
