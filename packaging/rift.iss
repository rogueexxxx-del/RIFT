; Inno Setup script for RIFT.
;
; Input is a staged directory, NOT the build tree: run
;     cmake --install build-release --prefix dist
; first. That step runs windeployqt, so `dist` already contains the Qt DLLs,
; the platform + imageformats plugins and the QML modules. Pointing this script
; at the build tree instead would produce an installer that works only on a
; machine that already has Qt.
;
; Build the installer with:
;     iscc packaging\rift.iss
; Override the staged dir with:  iscc /DStageDir=..\dist packaging\rift.iss

#define AppName     "RIFT"
#define AppVersion  "1.0.0"
#define AppPublisher "Revanth Rangisetti"
#define AppExe      "rift_shell.exe"

#ifndef StageDir
  #define StageDir "..\dist"
#endif

[Setup]
AppId={{7C3F9A21-5E4B-4C86-9D2A-1F0B6E8A4C57}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
; Per-user install by default: it needs no admin prompt, which is one less
; barrier for someone trying the app for the first time.
PrivilegesRequiredOverridesAllowed=dialog
PrivilegesRequired=lowest
OutputDir=..\dist-installer
OutputBaseFilename=RIFT-{#AppVersion}-setup
SetupIconFile=..\assets\rift.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The engine is D3D11 + x64 only; a 32-bit machine would install and then fail
; at startup with no message.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; \
  GroupDescription: "Additional shortcuts"; Flags: unchecked
Name: "associate"; Description: "Open .rt project files with {#AppName}"; \
  GroupDescription: "File associations"

[Files]
; Everything windeployqt and cmake --install staged, recursively.
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; .rt is RIFT's own project format. Written under HKA so it lands in HKCU for a
; per-user install and HKLM for an all-users one, without a second code path.
Root: HKA; Subkey: "Software\Classes\.rt"; ValueType: string; \
  ValueName: ""; ValueData: "RIFT.Project"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\RIFT.Project"; ValueType: string; \
  ValueName: ""; ValueData: "RIFT project"; Flags: uninsdeletekey; Tasks: associate
Root: HKA; Subkey: "Software\Classes\RIFT.Project\DefaultIcon"; ValueType: string; \
  ValueName: ""; ValueData: "{app}\{#AppExe},0"; Tasks: associate
Root: HKA; Subkey: "Software\Classes\RIFT.Project\shell\open\command"; ValueType: string; \
  ValueName: ""; ValueData: """{app}\{#AppExe}"" --open ""%1"""; Tasks: associate

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; \
  Flags: nowait postinstall skipifsilent
