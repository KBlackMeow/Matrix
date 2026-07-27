#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

[Setup]
AppName=Matrix
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\matrix
DefaultGroupName=Matrix
OutputDir=dist
OutputBaseFilename=Matrix_Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\matrix.exe

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Matrix"; Filename: "{app}\matrix.exe"
Name: "{commondesktop}\Matrix"; Filename: "{app}\matrix.exe"

[Run]
Filename: "{app}\matrix.exe"; Description: "Run Matrix"; Flags: nowait postinstall skipifsilent