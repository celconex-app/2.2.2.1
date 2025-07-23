; Celconex Installer Script - Inno Setup (.iss)

[Setup]
AppName=Celconex
AppVersion=1.0.0
DefaultDirName={pf}\Celconex
DefaultGroupName=Celconex
UninstallDisplayIcon={app}\celconex_icon.ico
OutputDir=.
OutputBaseFilename=CelconexInstaller
SetupIconFile=celconex_icon.ico
Compression=lzma
SolidCompression=yes

[Files]
Source: "CelconexApp\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs
Source: "celconex_icon.ico"; DestDir: "{app}"

[Icons]
Name: "{commondesktop}\Celconex"; Filename: "{app}\CelconexApp.exe"; IconFilename: "{app}\celconex_icon.ico"

[Run]
Filename: "{app}\CelconexApp.exe"; Description: "Iniciar Celconex"; Flags: nowait postinstall skipifsilent