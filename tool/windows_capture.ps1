# Captures the real window of tool/windows_shots.dart at real Windows scales.
#   tool/windows_capture.ps1 -Build build/windows/x64/runner/Release -Out <folder>
# Changes the scale of one monitor for a few seconds and always returns it to
# the scale it had, even on failure. A window that lands on another monitor is
# refused: its image would not show the scale in its name.
param(
  [Parameter(Mandatory)] [string] $Build,
  [Parameter(Mandatory)] [string] $Out,
  [string] $Extra = '',
  [int[]] $Scales = @(100, 125, 150),
  [string[]] $Tabs = @('0:hoje', '11:investir'),
  [string] $Display = '\\.\DISPLAY2',
  [int] $Wait = 7,
  [int] $Width = 0,
  [int] $Height = 0
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -Path "$here\windows_shot.cs" -ReferencedAssemblies System.Drawing
[Shot]::Aware()
New-Item -ItemType Directory -Force $Out | Out-Null
$original = [Shot]::Current($Display)
"escala original de ${Display}: $original%"
Add-Type -AssemblyName System.Windows.Forms
function Bounds { ([System.Windows.Forms.Screen]::AllScreens | Where-Object { $_.DeviceName -eq $Display }).Bounds }
try {
  foreach ($scale in $Scales) {
    [Shot]::Set($Display, $scale)
    Start-Sleep -Seconds 2
    foreach ($tab in $Tabs) {
      $id, $name = $tab -split ':'
      $argv = @('--test-profile=shots', "--tab=$id")
      if ($Extra) { $argv += ($Extra -split ' ') }
      $p = Start-Process -FilePath "$Build\Nexo.exe" -ArgumentList $argv -PassThru
      try {
        $deadline = (Get-Date).AddSeconds(20)
        while ($p.MainWindowHandle -eq 0 -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200; $p.Refresh() }
        if ($p.MainWindowHandle -eq 0) { throw 'janela nao apareceu' }
        $h = $p.MainWindowHandle
        $b = Bounds
        [Shot]::Place($h, $b.X + 40, $b.Y + 40, 900, 600)
        Start-Sleep -Milliseconds 800
        if ($Width -gt 0) { [Shot]::Place($h, $b.X - 300, $b.Y, $Width, $Height) } else { [Shot]::Maximize($h) }
        Start-Sleep -Seconds $Wait
        $dpi = [Shot]::Dpi($h)
        if ($dpi -ne [int]($scale * 96 / 100)) { throw "$name a $scale% abriu com DPI ${dpi}: janela fora do monitor" }
        $file = Join-Path $Out "$name-$scale.png"
        "$name $scale% -> " + [Shot]::Save($h, $file)
      } finally {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 600
      }
    }
  }
} finally {
  [Shot]::Set($Display, $original)
  Start-Sleep -Seconds 1
  "escala restaurada: " + [Shot]::Current($Display) + "%"
}
