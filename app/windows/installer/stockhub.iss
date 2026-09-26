; Inno Setup script for StockHub (Windows desktop client).
; Produces a per-user installer - no admin rights needed, adds a Start Menu
; entry and (optional) desktop shortcut, plus a proper uninstaller.
;
; Build the release app first: flutter build windows --release
; Then compile: "ISCC.exe" windows\installer\stockhub.iss
; (or open this file in the Inno Setup Compiler and press Build.)

#define MyAppName "StockHub"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "StockHub"
#define MyAppExeName "stockhub.exe"
#define ReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{6B2E1B7B-6E0A-4C0E-9B0D-6A2B7B7B0F01}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Per-user install - no UAC prompt, works without admin rights on other PCs.
DefaultDirName={localappdata}\Programs\{#MyAppName}
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
DefaultGroupName={#MyAppName}
OutputDir=..\..\dist
OutputBaseFilename=StockHub-Setup-{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#ReleaseDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName} now"; Flags: nowait postinstall skipifsilent
