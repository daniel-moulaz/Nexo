$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$bundle = Join-Path $projectRoot 'build/windows/x64/runner/Release'
$versionLine = Select-String -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Pattern '^version: (.+)$'
$version = $versionLine.Matches[0].Groups[1].Value.Trim()
if ($version -notmatch '^\d+\.\d+\.\d+\+\d+$') { throw 'Vers?o inv?lida.' }
foreach ($item in @('Nexo.exe','flutter_windows.dll','sqlite3.dll','data/app.so','data/icudtl.dat','data/flutter_assets','msvcp140.dll','vcruntime140.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path $bundle $item))) { throw "Bundle incompleto: $item" }
}
$unexpected = Get-ChildItem -LiteralPath $bundle -Recurse -File | Where-Object { $_.Extension -in @('.db','.sqlite','.keystore','.pfx','.log') }
if ($unexpected) { throw 'O bundle cont?m arquivo de dados, credencial ou log. Revise antes de distribuir.' }
$destination = Join-Path $projectRoot 'build/distribution'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$archive = Join-Path $destination "Nexo-$version-windows-x64.zip"
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $archive -Force
$hash = Get-FileHash -LiteralPath $archive -Algorithm SHA256
Set-Content -LiteralPath "$archive.sha256" -Value "$($hash.Hash)  $([IO.Path]::GetFileName($archive))" -Encoding ASCII
Write-Output $archive
Write-Output "SHA256: $($hash.Hash)"
