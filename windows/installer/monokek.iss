; Inno Setup script for the MonoKek POS Windows installer.
; Built by .github/workflows/build.yml:
;   iscc /DAppVersion=1.2.3 /DSourceDir=<abs path to build\windows\x64\runner\Release> windows\installer\monokek.iss
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; Fixed GUID: identifies the app across versions so a new installer upgrades in place.
AppId={{6F1B7C52-3D0E-4B8A-9C41-5A2E8D7F0B19}
AppName=MonoKek POS
AppVersion={#AppVersion}
AppPublisher=MonoKek
DefaultDirName={autopf}\MonoKek POS
DefaultGroupName=MonoKek POS
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=MonoKekPOS-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\MonoKekPOS.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MonoKek POS"; Filename: "{app}\MonoKekPOS.exe"
Name: "{autodesktop}\MonoKek POS"; Filename: "{app}\MonoKekPOS.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\MonoKekPOS.exe"; Description: "Lancer MonoKek POS"; Flags: nowait postinstall skipifsilent
