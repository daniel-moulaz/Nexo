$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $projectRoot '.flutter-plugins-dependencies'
if (!(Test-Path -LiteralPath $manifestPath)) { throw 'Execute flutter pub get primeiro.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$links = Join-Path $projectRoot 'windows/flutter/ephemeral/.plugin_symlinks'
New-Item -ItemType Directory -Path $links -Force | Out-Null
foreach ($plugin in $manifest.plugins.windows) {
    if ($plugin.name -notmatch '^[a-zA-Z0-9_]+$') { throw 'Nome de plugin inválido.' }
    $target = (Resolve-Path -LiteralPath $plugin.path).Path.TrimEnd('\')
    $link = Join-Path $links $plugin.name
    if (Test-Path -LiteralPath $link) {
        $existing = Get-Item -LiteralPath $link -Force
        if (!$existing.LinkType -or $existing.Target[0].TrimEnd('\') -ne $target) {
            throw "Link divergente: $link. Não foi removido automaticamente."
        }
    } else {
        # NTFS directory junctions need no Developer Mode and no SDK patching.
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    }
}
Write-Output 'Links Windows preparados. Use flutter build windows --release --no-pub.'
