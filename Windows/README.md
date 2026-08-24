# MobiVerse for Windows

This directory contains the Windows port of MobiVerse 2.3.1 (Build 12) for Windows 11 ARM64. The .NET 8 WPF application, Calibre, and bundled Fixed Version WebView2 Runtime are x64 components that run through Windows 11 ARM64 compatibility.

The Windows 2.3.1 source now includes the macOS 2.3.1 feature set:

- Shelf and Browse workspaces with application appearance preferences.
- WebView2 browser tabs, bookmarks, downloads, download-directory preferences, privacy clearing, and configurable main-page PDF downloads.
- Local content classification and import review with text/comic profile overrides and comic reading direction.
- EPUB 3 text conversion, ruby preservation, broken-resource/identifier/navigation repair, and EPUBCheck reporting.
- Direction-aware fixed-layout comic/PDF output with the 2.3.1 OPF validation corrections.
- Paginated text reading across all spine sections, reader themes, font and line-spacing controls, comic zoom/full screen, and persisted section/page positions.

## Development build

Requirements:

- Windows 10 1809+ x64
- .NET 8 SDK
- Visual Studio 2022 with the .NET desktop workload, or `dotnet` CLI

```powershell
dotnet test .\MobiVerse.sln
dotnet build .\MobiVerse.sln -c Release
dotnet run --project .\src\MobiVerse.App\MobiVerse.App.csproj
```

Development builds can use Calibre installed under `Program Files\Calibre2` or available on `PATH`. Fixed-layout PDF conversion uses `Windows.Data.Pdf` and does not require Calibre; reflowable text PDF conversion uses Calibre.

## macOS packaging workflow

Windows-side debugging is intentionally manual. Build and assemble the Windows package on macOS, then copy the portable ZIP to Windows for validation; do not automate Parallels interaction. `MobiVerse.App.MacCross.csproj` compiles the Windows application from macOS using WindowsDesktop reference assemblies and runtime-loaded loose XAML. The normal Windows build continues to use `MobiVerse.App.csproj` and compiled WPF XAML.

## Portable release

Download the Windows x64 Calibre files and unpack an x64 Fixed Version WebView2 Runtime, then set:

```powershell
$env:MOBIVERSE_CALIBRE_DIR = 'C:\staging\calibre'
$env:MOBIVERSE_CALIBRE_SOURCE_URL = 'https://github.com/kovidgoyal/calibre/releases/tag/v9.10.0'
$env:MOBIVERSE_WEBVIEW2_DIR = 'C:\staging\webview2-fixed'
.\scripts\Build-Release.ps1
```

The script tests and publishes a self-contained `win-x64` application, stages Calibre and WebView2 beside the executable, builds `MobiVerse-2.3.1-Windows11-ARM64-Portable.zip` plus its `.sha256` file, and prints the SHA-256 hash. Set `SIGNTOOL_PATH` and `WINDOWS_CERT_THUMBPRINT` to Authenticode-sign the executable. Unsigned builds are functional but may trigger SmartScreen.

Users extract the complete folder to a local disk and double-click `MobiVerse.exe`. No installation, administrator access, registry changes, or system WebView2 deployment is required. The executable must remain beside its DLLs and `ThirdParty` directory.
