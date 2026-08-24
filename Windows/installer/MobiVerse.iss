#ifndef SourceDir
  #error SourceDir must point to the self-contained publish directory.
#endif
#ifndef OutputDir
  #define OutputDir ".\artifacts"
#endif
#ifndef AppVersion
  #define AppVersion "2.3.1"
#endif
#ifndef AppBuild
  #define AppBuild "12"
#endif

[Setup]
AppId={{3EAC99D3-E8F9-4D8A-99EC-8E16C867BE25}
AppName=MobiVerse
AppVersion={#AppVersion}
AppPublisher=MobiVerse
AppPublisherURL=https://github.com/DemonDevil-Git/MobiVerse
DefaultDirName={localappdata}\Programs\MobiVerse
DefaultGroupName=MobiVerse
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=MobiVerse-{#AppVersion}-win-x64-setup
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupIconFile=..\src\MobiVerse.App\Resources\MobiVerse.ico
UninstallDisplayIcon={app}\MobiVerse.exe
LicenseFile=..\..\LICENSE
VersionInfoVersion={#AppVersion}.{#AppBuild}
VersionInfoProductName=MobiVerse
VersionInfoDescription=MobiVerse Windows installer

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MobiVerse"; Filename: "{app}\MobiVerse.exe"
Name: "{autodesktop}\MobiVerse"; Filename: "{app}\MobiVerse.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Registry]
Root: HKCU; Subkey: "Software\Classes\MobiVerse.Book"; ValueType: string; ValueData: "MobiVerse book"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\MobiVerse.Book\DefaultIcon"; ValueType: string; ValueData: "{app}\MobiVerse.exe,0"
Root: HKCU; Subkey: "Software\Classes\MobiVerse.Book\shell\open\command"; ValueType: string; ValueData: """{app}\MobiVerse.exe"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\Applications\MobiVerse.exe\shell\open\command"; ValueType: string; ValueData: """{app}\MobiVerse.exe"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Applications\MobiVerse.exe\SupportedTypes"; ValueType: string; ValueName: ".epub"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\Applications\MobiVerse.exe\SupportedTypes"; ValueType: string; ValueName: ".mobi"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\Applications\MobiVerse.exe\SupportedTypes"; ValueType: string; ValueName: ".azw"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\Applications\MobiVerse.exe\SupportedTypes"; ValueType: string; ValueName: ".azw3"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\Applications\MobiVerse.exe\SupportedTypes"; ValueType: string; ValueName: ".cbz"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\Applications\MobiVerse.exe\SupportedTypes"; ValueType: string; ValueName: ".cbr"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\Applications\MobiVerse.exe\SupportedTypes"; ValueType: string; ValueName: ".zip"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\Applications\MobiVerse.exe\SupportedTypes"; ValueType: string; ValueName: ".pdf"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\.epub\OpenWithProgids"; ValueType: string; ValueName: "MobiVerse.Book"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.mobi\OpenWithProgids"; ValueType: string; ValueName: "MobiVerse.Book"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.azw\OpenWithProgids"; ValueType: string; ValueName: "MobiVerse.Book"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.azw3\OpenWithProgids"; ValueType: string; ValueName: "MobiVerse.Book"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.cbz\OpenWithProgids"; ValueType: string; ValueName: "MobiVerse.Book"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.cbr\OpenWithProgids"; ValueType: string; ValueName: "MobiVerse.Book"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.zip\OpenWithProgids"; ValueType: string; ValueName: "MobiVerse.Book"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "MobiVerse.Book"; ValueData: ""; Flags: uninsdeletevalue

[Run]
Filename: "{app}\MobiVerse.exe"; Description: "Launch MobiVerse"; Flags: nowait postinstall skipifsilent

[Code]
procedure SHChangeNotify(wEventId: LongWord; uFlags: LongWord; dwItem1: Integer; dwItem2: Integer);
  external 'SHChangeNotify@shell32.dll stdcall';

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    SHChangeNotify($08000000, $0000, 0, 0);
end;
