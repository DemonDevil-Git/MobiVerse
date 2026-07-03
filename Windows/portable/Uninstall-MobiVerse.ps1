$ErrorActionPreference = 'Stop'
$installDirectory = Join-Path $env:LOCALAPPDATA 'Programs\MobiVerse'
$startMenuDirectory = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\MobiVerse'
$progId = 'MobiVerse.Book'
$extensions = '.epub', '.mobi', '.azw', '.azw3', '.cbz', '.cbr', '.zip', '.pdf'

Get-Process -Name MobiVerse -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "HKCU:\Software\Classes\$progId" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'HKCU:\Software\Classes\Applications\MobiVerse.exe' -Recurse -Force -ErrorAction SilentlyContinue
foreach ($extension in $extensions) {
    Remove-ItemProperty "HKCU:\Software\Classes\$extension\OpenWithProgids" -Name $progId -Force -ErrorAction SilentlyContinue
}
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\MobiVerse' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $startMenuDirectory -Recurse -Force -ErrorAction SilentlyContinue

$cleanup = Join-Path $env:TEMP ('MobiVerse-Uninstall-' + [Guid]::NewGuid().ToString('N') + '.cmd')
$escapedDirectory = $installDirectory.Replace('%', '%%')
@"
@echo off
timeout /t 2 /nobreak >nul
rmdir /s /q "$escapedDirectory"
del /q "%~f0"
"@ | Set-Content -Path $cleanup -Encoding ASCII
Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ('"' + $cleanup + '"') -WindowStyle Hidden
