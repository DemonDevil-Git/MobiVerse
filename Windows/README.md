# MobiVerse for Windows

This directory contains the Windows port of MobiVerse 2.2.0 for Windows 11 ARM64. The .NET 8 WPF application and bundled Calibre run through Windows ARM64 x64 compatibility, while the reading runtime is native ARM64.

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

Development builds can use Calibre installed under `Program Files\Calibre2` or available on `PATH`. PDF conversion uses `Windows.Data.Pdf` and does not require Calibre.

## Offline release installer

Install Inno Setup 6, download the Windows x64 Calibre files and an x64 Fixed Version WebView2 Runtime, then set:

```powershell
$env:MOBIVERSE_CALIBRE_DIR = 'C:\staging\calibre'
$env:MOBIVERSE_WEBVIEW2_DIR = 'C:\staging\webview2-fixed'
$env:INNO_SETUP_COMPILER = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
.\scripts\Build-Release.ps1
```

The script tests and publishes a self-contained `win-x64` application, stages offline dependencies, builds a per-user installer, and prints its SHA-256 hash. Set `SIGNTOOL_PATH` and `WINDOWS_CERT_THUMBPRINT` to Authenticode-sign the app and installer. Unsigned builds are functional but may trigger SmartScreen.

The installer registers MobiVerse under “Open with” for EPUB, MOBI, AZW, AZW3, CBZ, CBR, ZIP, and PDF without changing default applications.
