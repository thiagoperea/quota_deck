; Instalador Windows do QuotaDeck (Inno Setup 6+).
; Uso: iscc /DMyAppVersion=0.7.0 /DSourceDir=<...>\Release installer\quota_deck.iss

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#ifndef SourceDir
  #define SourceDir "..\app\build\windows\x64\runner\Release"
#endif

#define MyAppName "QuotaDeck"
#define MyAppPublisher "com.thiagoperea"
#define MyAppExeName "quota_deck.exe"

[Setup]
AppId={{0F2C6B7A-5D3E-4A91-9C2B-7E4F1A8D6C31}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\QuotaDeck
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
LicenseFile=
OutputDir=..\dist-installer
OutputBaseFilename=quota_deck-{#MyAppVersion}-setup
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos:"
Name: "startup"; Description: "Iniciar com o Windows"; GroupDescription: "Inicialização:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "QuotaDeck"; ValueData: """{app}\{#MyAppExeName}"" --startup"; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Mantém config/cache/histórico em %APPDATA%\QuotaDeck por padrão.
Type: filesandordirs; Name: "{app}"
; Atalho criado pelo local_notifier para habilitar toasts no Windows.
Type: files; Name: "{userprograms}\QuotaDeck.lnk"
