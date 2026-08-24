param(
    [string]$Configuration = 'Release',
    [string]$AppVersion = '2.3.1',
    [int]$BuildNumber = 12,
    [string]$CalibreDirectory = $env:MOBIVERSE_CALIBRE_DIR,
    [string]$WebView2Directory = $env:MOBIVERSE_WEBVIEW2_DIR,
    [string]$EpubCheckDirectory = $env:MOBIVERSE_EPUBCHECK_DIR,
    [string]$CalibreSourceUrl = $env:MOBIVERSE_CALIBRE_SOURCE_URL,
    [string]$SignTool = $env:SIGNTOOL_PATH,
    [string]$CertificateThumbprint = $env:WINDOWS_CERT_THUMBPRINT,
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$appProject = Join-Path $root 'src\MobiVerse.App\MobiVerse.App.csproj'
$publishDirectory = Join-Path $root 'artifacts\publish\win-x64'
$portableName = "MobiVerse-$AppVersion-Windows11-ARM64-Portable"
$portableDirectory = Join-Path $root "artifacts\portable\$portableName"
$portableArchive = Join-Path $root "artifacts\$portableName.zip"
$portableHashFile = "$portableArchive.sha256"
$assemblyVersion = "$AppVersion.0"
$fileVersion = "$AppVersion.$BuildNumber"
$informationalVersion = "$AppVersion+$BuildNumber"
$iconPath = Join-Path $root 'src\MobiVerse.App\Resources\MobiVerse.ico'
$sourceIcon = Join-Path (Split-Path -Parent $root) 'Assets\AppIcon\AppIcon.iconset\icon_256x256.png'

if (-not (Test-Path (Join-Path $CalibreDirectory 'ebook-convert.exe'))) { throw 'Set MOBIVERSE_CALIBRE_DIR to a Windows Calibre directory containing ebook-convert.exe.' }
if (-not (Test-Path (Join-Path $CalibreDirectory 'ebook-meta.exe'))) { throw 'The Calibre directory does not contain ebook-meta.exe.' }
if (-not (Test-Path (Join-Path $WebView2Directory 'msedgewebview2.exe'))) { throw 'Set MOBIVERSE_WEBVIEW2_DIR to an unpacked x64 Fixed Version WebView2 Runtime.' }
if ([string]::IsNullOrWhiteSpace($CalibreSourceUrl)) { throw 'Set MOBIVERSE_CALIBRE_SOURCE_URL to the source URL for the exact bundled Calibre version.' }

& (Join-Path $root 'scripts\New-AppIcon.ps1') -SourcePng $sourceIcon -DestinationIco $iconPath
& dotnet test (Join-Path $root 'MobiVerse.sln') --configuration $Configuration
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
if (Test-Path $publishDirectory) { Remove-Item $publishDirectory -Recurse -Force }
& dotnet publish $appProject --configuration $Configuration --runtime win-x64 --self-contained true --output $publishDirectory -p:PublishSingleFile=false -p:Version=$AppVersion -p:AssemblyVersion=$assemblyVersion -p:FileVersion=$fileVersion -p:InformationalVersion=$informationalVersion
if ($LASTEXITCODE -ne 0) { throw 'Publish failed.' }

$portableParent = Split-Path -Parent $portableDirectory
New-Item -ItemType Directory -Path $portableParent -Force | Out-Null
if (Test-Path $portableDirectory) { Remove-Item $portableDirectory -Recurse -Force }
Copy-Item $publishDirectory $portableDirectory -Recurse -Force

$thirdParty = Join-Path $portableDirectory 'ThirdParty'
New-Item -ItemType Directory -Path $thirdParty -Force | Out-Null
Copy-Item $CalibreDirectory (Join-Path $thirdParty 'calibre') -Recurse -Force
Copy-Item $WebView2Directory (Join-Path $thirdParty 'WebView2') -Recurse -Force
if ($EpubCheckDirectory -and (Test-Path $EpubCheckDirectory)) { Copy-Item $EpubCheckDirectory (Join-Path $thirdParty 'epubcheck') -Recurse -Force }
Copy-Item (Join-Path (Split-Path -Parent $root) 'LICENSE') $portableDirectory -Force
Copy-Item (Join-Path $root 'ThirdPartyNotices.Windows.md') $portableDirectory -Force
Copy-Item (Join-Path $root 'portable\README-TESTING.zh-CN.txt') $portableDirectory -Force
Copy-Item (Join-Path $root 'portable\webview2-source.txt') (Join-Path $thirdParty 'webview2-source.txt') -Force
Set-Content -Path (Join-Path $thirdParty 'calibre-source.txt') -Value "Source for the bundled Calibre version: $CalibreSourceUrl" -Encoding UTF8

if ($SignTool -and $CertificateThumbprint) {
    & $SignTool sign /sha1 $CertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 (Join-Path $portableDirectory 'MobiVerse.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Application signing failed.' }
} else {
    Write-Warning 'No Authenticode certificate configured. Windows SmartScreen may warn about this build.'
}

if (Test-Path $portableArchive) { Remove-Item $portableArchive -Force }
Compress-Archive -Path $portableDirectory -DestinationPath $portableArchive -CompressionLevel Optimal
$hash = Get-FileHash $portableArchive -Algorithm SHA256
Set-Content -Path $portableHashFile -Value "$($hash.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($portableArchive))" -Encoding ascii
$hash
