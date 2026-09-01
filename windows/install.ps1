# SPDX-License-Identifier: GPL-2.0-only

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$repository = 'B12Konsument/Fedora-SL-Remix'
$headers = @{ 'User-Agent' = 'Fedora-SL7-Remix-Windows-Bootstrap' }
$bootstrapRoot = Join-Path $env:TEMP ("fedora-sl7-bootstrap-{0}" -f [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $bootstrapRoot | Out-Null

try {
    Write-Host '[Fedora SL7 Remix] Resolving the newest published release, including prereleases.' -ForegroundColor Cyan
    $releases = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri "https://api.github.com/repos/$repository/releases?per_page=20"
    $release = $releases | Where-Object { -not $_.draft } | Select-Object -First 1
    if ($null -eq $release) { throw 'No published Fedora SL7 Remix release is available yet.' }

    $layoutAsset = $release.assets | Where-Object { $_.name -eq 'personalization-layout.json' } | Select-Object -First 1
    if ($null -eq $layoutAsset) { throw 'The release has no personalization-layout.json asset.' }
    $layoutPath = Join-Path $bootstrapRoot 'personalization-layout.json'
    Invoke-WebRequest -UseBasicParsing -Uri $layoutAsset.browser_download_url -OutFile $layoutPath
    $layout = Get-Content -LiteralPath $layoutPath -Raw | ConvertFrom-Json
    if ($null -eq $layout.windows_bundle) { throw 'The release has no verified Windows customizer bundle.' }
    $bundleName = [string]$layout.windows_bundle.name
    if ($bundleName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+[.]zip$' -or $bundleName.Contains('..') -or
        [string]$layout.windows_bundle.sha256 -notmatch '^[0-9a-f]{64}$' -or [long]$layout.windows_bundle.size -le 0) {
        throw 'The release contains invalid Windows customizer metadata.'
    }

    $bundleAsset = $release.assets | Where-Object { $_.name -eq $bundleName } | Select-Object -First 1
    if ($null -eq $bundleAsset) { throw "The release has no $bundleName asset." }
    $bundlePath = Join-Path $bootstrapRoot $bundleName
    Invoke-WebRequest -UseBasicParsing -Uri $bundleAsset.browser_download_url -OutFile $bundlePath
    if ((Get-Item -LiteralPath $bundlePath).Length -ne [long]$layout.windows_bundle.size) {
        throw 'The downloaded Windows customizer bundle has the wrong size.'
    }
    $actual = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne ([string]$layout.windows_bundle.sha256).ToLowerInvariant()) {
        throw 'The downloaded Windows customizer bundle failed SHA-256 verification.'
    }

    $expanded = Join-Path $bootstrapRoot 'expanded'
    Expand-Archive -LiteralPath $bundlePath -DestinationPath $expanded
    $scriptPath = Join-Path $expanded 'windows\New-FedoraSl7Iso.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw 'The Windows customizer bundle is malformed.' }
    & $scriptPath -Release ([string]$release.tag_name) -LayoutPath $layoutPath
    if (-not $?) { throw 'The Windows ISO personalizer did not complete successfully.' }
}
catch {
    throw $_.Exception.Message
}
finally {
    if (Test-Path -LiteralPath $bootstrapRoot) {
        Remove-Item -LiteralPath $bootstrapRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
