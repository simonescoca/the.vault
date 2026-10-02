; The Vault — Windows installer (Inno Setup 6).
; Built by .github/workflows/release.yml:  ISCC.exe /DAppVersion=1.0.0 windows\installer\TheVault.iss
; Installs for the current user only (no administrator password), in %LOCALAPPDATA%\Programs\The Vault.
; Uninstalling keeps the vault data in %APPDATA%\simonescoca\The Vault; the app's "Esci da questo dispositivo" deletes it.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "The Vault"
#define AppExe "TheVault.exe"

[Setup]
; Never change AppId: Windows uses it to recognise updates of the same app.
AppId={{D3F6A8DC-04A4-4CC2-B9AB-D2D88210D60B}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=simonescoca
AppPublisherURL=https://github.com/simonescoca/the.vault
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; The app keeps this mutex while it runs (windows/runner/main.cpp): setup asks to close it before updating.
AppMutex=TheVault.SingleInstance
CloseApplications=yes
RestartApplications=no
OutputDir=..\..\build\installer
OutputBaseFilename=TheVault-Windows-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=no
LanguageDetectionMethod=uilanguage

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
