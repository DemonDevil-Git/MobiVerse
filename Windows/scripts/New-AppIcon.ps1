param(
    [Parameter(Mandatory = $true)][string]$SourcePng,
    [Parameter(Mandatory = $true)][string]$DestinationIco
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeIconMethods {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool DestroyIcon(IntPtr handle);
}
'@

$destinationDirectory = Split-Path -Parent $DestinationIco
New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
$bitmap = [System.Drawing.Bitmap]::FromFile((Resolve-Path $SourcePng))
$handle = $bitmap.GetHicon()
try {
    $icon = [System.Drawing.Icon]::FromHandle($handle)
    $stream = [System.IO.File]::Create($DestinationIco)
    try { $icon.Save($stream) } finally { $stream.Dispose(); $icon.Dispose() }
} finally {
    [NativeIconMethods]::DestroyIcon($handle) | Out-Null
    $bitmap.Dispose()
}
