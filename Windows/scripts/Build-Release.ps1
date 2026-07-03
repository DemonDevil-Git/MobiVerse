param(
    [string]$Configuration = 'Release',
    [string]$CalibreDirectory = $env:MOBIVERSE_CALIBRE_DIR,
    [string]$WebView2Directory = $env:MOBIVERSE_WEBVIEW2_DIR,
    [string]$EpubCheckDirectory = $env:MOBIVERSE_EPUBCHECK_DIR,
    [string]$CalibreSourceUrl = 'https://github.com/kovidgoyal/calibre/releases',
    [string]$InnoSetup = $env:INNO_SETUP_COMPILER,
    [string]$SignTool = $env:SIGNTOOL_PATH,
    [string]$CertificateThumbprint = $env:WINDOWS_CERT_THUMBPRINT,
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$appProject = Join-Path $root 'src\MobiVerse.App\MobiVerse.App.csproj'
$publishDirectory = Join-Path $root 'artifacts\publish\win-x64'
$installerDirectory = Join-Path $root 'artifacts\installer'
$iconPath = Join-Path $root 'src\MobiVerse.App\Resources\MobiVerse.ico'
$sourceIcon = Join-Path (Split-Path -Parent $root) 'Assets\AppIcon\AppIcon.iconset\icon_256x256.png'

if (-not (Test-Path (Join-Path $CalibreDirectory 'ebook-convert.exe'))) { throw 'Set MOBIVERSE_CALIBRE_DIR to a Windows Calibre directory containing ebook-convert.exe.' }
if (-not (Test-Path (Join-Path $CalibreDirectory 'ebook-meta.exe'))) { throw 'The Calibre directory does not contain ebook-meta.exe.' }
if (-not (Test-Path (Join-Path $WebView2Directory 'msedgewebview2.exe'))) { throw 'Set MOBIVERSE_WEBVIEW2_DIR to an unpacked x64 Fixed Version WebView2 Runtime.' }

& (Join-Path $root 'scripts\New-AppIcon.ps1') -SourcePng $sourceIcon -DestinationIco $iconPath
& dotnet test (Join-Path $root 'MobiVerse.sln') --configuration $Configuration
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
if (Test-Path $publishDirectory) { Remove-Item $publishDirectory -Recurse -Force }
& dotnet publish $appProject --configuration $Configuration --runtime win-x64 --self-contained true --output $publishDirectory -p:PublishSingleFile=false
if ($LASTEXITCODE -ne 0) { throw 'Publish failed.' }

$thirdParty = Join-Path $publishDirectory 'ThirdParty'
New-Item -ItemType Directory -Path $thirdParty -Force | Out-Null
Copy-Item $CalibreDirectory (Join-Path $thirdParty 'calibre') -Recurse -Force
Copy-Item $WebView2Directory (Join-Path $thirdParty 'WebView2') -Recurse -Force
if ($EpubCheckDirectory -and (Test-Path $EpubCheckDirectory)) { Copy-Item $EpubCheckDirectory (Join-Path $thirdParty 'epubcheck') -Recurse -Force }
Copy-Item (Join-Path (Split-Path -Parent $root) 'LICENSE') $publishDirectory -Force
Copy-Item (Join-Path $root 'ThirdPartyNotices.Windows.md') $publishDirectory -Force
Set-Content -Path (Join-Path $thirdParty 'calibre-source.txt') -Value "Source for the bundled Calibre version: $CalibreSourceUrl" -Encoding UTF8

if ($SignTool -and $CertificateThumbprint) {
    & $SignTool sign /sha1 $CertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 (Join-Path $publishDirectory 'MobiVerse.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Application signing failed.' }
} else {
    Write-Warning 'No Authenticode certificate configured. Windows SmartScreen may warn about this build.'
}

if (-not $InnoSetup) { $InnoSetup = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe' }
if (-not (Test-Path $InnoSetup)) { throw 'Install Inno Setup 6 or set INNO_SETUP_COMPILER.' }
New-Item -ItemType Directory -Path $installerDirectory -Force | Out-Null
& $InnoSetup "/DSourceDir=$publishDirectory" "/DOutputDir=$installerDirectory" "/DAppVersion=2.2.0" (Join-Path $root 'installer\MobiVerse.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }

$installer = Join-Path $installerDirectory 'MobiVerse-2.2.0-win-x64-setup.exe'
if ($SignTool -and $CertificateThumbprint) {
    & $SignTool sign /sha1 $CertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $installer
    if ($LASTEXITCODE -ne 0) { throw 'Installer signing failed.' }
}
Get-FileHash $installer -Algorithm SHA256
