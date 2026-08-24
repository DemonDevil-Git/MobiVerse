$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $PSCommandPath
$appSource = Join-Path $packageRoot 'App'
$dependencies = Join-Path $packageRoot 'Dependencies'
$webViewInstaller = Join-Path $dependencies 'MicrosoftEdgeWebView2RuntimeInstallerARM64.exe'
$installDirectory = Join-Path $env:LOCALAPPDATA 'Programs\MobiVerse'
$startMenuDirectory = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\MobiVerse'
$applicationPath = Join-Path $installDirectory 'MobiVerse.exe'
$calibreDirectory = Join-Path $installDirectory 'ThirdParty\calibre'
$uninstallScript = Join-Path $installDirectory 'Uninstall-MobiVerse.ps1'
$statusPath = Join-Path $env:TEMP ("MobiVerse-Install-" + [guid]::NewGuid().ToString('N') + '.json')
$logPath = Join-Path $env:TEMP 'MobiVerse-Install.log'

function Write-Status([string]$stage, [string]$message, [int]$progress, [string]$detail = '') {
    $payload = [ordered]@{ stage = $stage; message = $message; progress = $progress; detail = $detail }
    $temporary = $statusPath + '.tmp'
    $payload | ConvertTo-Json -Compress | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $statusPath -Force
    Add-Content -LiteralPath $logPath -Value ("{0:o}  [{1}] {2} {3}" -f [DateTimeOffset]::Now, $stage, $message, $detail)
}

function Set-RegistryDefault([string]$path, [string]$value) {
    New-Item -Path $path -Force | Out-Null
    Set-Item -Path $path -Value $value
}

try {
Write-Status 'starting' 'Preparing MobiVerse' 4
$uiScript = Join-Path $packageRoot 'Show-InstallProgress.ps1'
if (Test-Path $uiScript) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoLogo','-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"' + $uiScript + '"'),'-StatusPath',('"' + $statusPath + '"')) | Out-Null
}

if (-not [Environment]::Is64BitOperatingSystem) { throw 'MobiVerse requires a 64-bit Windows installation.' }
if (-not (Test-Path (Join-Path $appSource 'MobiVerse.exe'))) { throw 'The App directory is incomplete.' }
if (-not (Test-Path $webViewInstaller)) { throw 'The bundled ARM64 WebView2 installer is missing.' }
if (-not (Test-Path (Join-Path $appSource 'ThirdParty\calibre\ebook-convert.exe'))) { throw 'The bundled Calibre conversion engine is missing.' }

Write-Status 'runtime' 'Installing the reading engine' 12 'WebView2 ARM64 runtime'
$webViewProcess = Start-Process -FilePath $webViewInstaller -ArgumentList '/silent', '/install' -WindowStyle Hidden -Wait -PassThru
if ($webViewProcess.ExitCode -notin 0, 3010) { Add-Content -LiteralPath $logPath -Value "WebView2 exit code: $($webViewProcess.ExitCode)" }

Write-Status 'copying' 'Installing MobiVerse' 38 'Copying application and conversion engine'
New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Copy-Item -Path (Join-Path $appSource '*') -Destination $installDirectory -Recurse -Force
Copy-Item -Path (Join-Path $packageRoot 'Uninstall-MobiVerse.ps1') -Destination $uninstallScript -Force

Write-Status 'verifying' 'Checking bundled components' 78 'Calibre conversion engine'
$ebookConvert = Get-ChildItem -Path $calibreDirectory -Filter 'ebook-convert.exe' -File -Recurse | Select-Object -First 1
$ebookMeta = Get-ChildItem -Path $calibreDirectory -Filter 'ebook-meta.exe' -File -Recurse | Select-Object -First 1
if (-not $ebookConvert -or -not $ebookMeta) { throw 'Calibre installed, but its command-line tools could not be found.' }

Write-Status 'registering' 'Finishing setup' 88 'Shortcuts and Open with entries'
$progId = 'MobiVerse.Book'
Set-RegistryDefault "HKCU:\Software\Classes\$progId" 'MobiVerse book'
Set-RegistryDefault "HKCU:\Software\Classes\$progId\DefaultIcon" ('"' + $applicationPath + '",0')
Set-RegistryDefault "HKCU:\Software\Classes\$progId\shell\open\command" ('"' + $applicationPath + '" "%1"')
Set-RegistryDefault 'HKCU:\Software\Classes\Applications\MobiVerse.exe\shell\open\command' ('"' + $applicationPath + '" "%1"')

$extensions = '.epub', '.mobi', '.azw', '.azw3', '.cbz', '.cbr', '.zip', '.pdf'
foreach ($extension in $extensions) {
    $supportedTypes = "HKCU:\Software\Classes\Applications\MobiVerse.exe\SupportedTypes"
    New-Item -Path $supportedTypes -Force | Out-Null
    New-ItemProperty -Path $supportedTypes -Name $extension -Value '' -PropertyType String -Force | Out-Null
    $openWith = "HKCU:\Software\Classes\$extension\OpenWithProgids"
    New-Item -Path $openWith -Force | Out-Null
    New-ItemProperty -Path $openWith -Name $progId -Value '' -PropertyType String -Force | Out-Null
}

$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\MobiVerse'
New-Item -Path $uninstallKey -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name DisplayName -Value 'MobiVerse' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name DisplayVersion -Value '2.3.1' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name Publisher -Value 'MobiVerse' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name InstallLocation -Value $installDirectory -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name DisplayIcon -Value $applicationPath -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name UninstallString -Value ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $uninstallScript + '"') -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null

New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path $startMenuDirectory 'MobiVerse.lnk'))
$shortcut.TargetPath = $applicationPath
$shortcut.WorkingDirectory = $installDirectory
$shortcut.IconLocation = $applicationPath
$shortcut.Save()
$uninstallShortcut = $shell.CreateShortcut((Join-Path $startMenuDirectory 'Uninstall MobiVerse.lnk'))
$uninstallShortcut.TargetPath = 'powershell.exe'
$uninstallShortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $uninstallScript + '"'
$uninstallShortcut.WorkingDirectory = $installDirectory
$uninstallShortcut.Save()

Write-Status 'complete' 'MobiVerse is ready' 100 'Opening the application'
Start-Sleep -Milliseconds 700
Start-Process -FilePath $applicationPath
Start-Sleep -Milliseconds 700
}
catch {
    $message = $_.Exception.Message
    Add-Content -LiteralPath $logPath -Value $_.Exception.ToString()
    Write-Status 'error' 'Installation could not be completed' 100 ($message + "`nLog: " + $logPath)
    Start-Sleep -Seconds 15
    exit 1
}
