#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif
#ifndef PublishDir
  #define PublishDir "..\artifacts\publish"
#endif
#ifndef OutputDir
  #define OutputDir "..\artifacts\installer"
#endif

[Setup]
AppId={{C7E42F6C-E1A8-49EF-B4DE-32C7C9C8C21F}
AppName=弹来弹去
AppVersion={#MyAppVersion}
AppPublisher=belcheckyoung
AppPublisherURL=https://github.com/belcheckyoung/DanLaiDanQu
AppSupportURL=https://github.com/belcheckyoung/DanLaiDanQu/issues
DefaultDirName={localappdata}\Programs\DanLaiDanQu
DefaultGroupName=弹来弹去
UninstallDisplayIcon={app}\DanLaiDanQu.Windows.exe
OutputDir={#OutputDir}
OutputBaseFilename=DanLaiDanQu-Windows-v{#MyAppVersion}-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
DisableProgramGroupPage=yes
SetupLogging=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\弹来弹去"; Filename: "{app}\DanLaiDanQu.Windows.exe"
Name: "{autodesktop}\弹来弹去"; Filename: "{app}\DanLaiDanQu.Windows.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\DanLaiDanQu.Windows.exe"; Description: "启动弹来弹去"; Flags: nowait postinstall skipifsilent
