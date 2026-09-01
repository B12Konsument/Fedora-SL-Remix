# SPDX-License-Identifier: GPL-2.0-only

param([Parameter(Mandatory = $true)][string]$OutputPath)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\windows\FedoraSl7Remix.psm1" -Force
$fixture = Join-Path ([IO.Path]::GetTempPath()) ("fedora-sl7-cpio-{0}" -f [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null

try {
    $files = @{}
    foreach ($relative in Get-Sl7RequiredFirmware) {
        $path = Join-Path $fixture (Split-Path -Leaf $relative)
        [IO.File]::WriteAllText($path, "synthetic-fixture-$relative", [Text.Encoding]::ASCII)
        $files[$relative] = $path
    }
    $manifest = Join-Path $fixture 'manifest.json'
    [IO.File]::WriteAllText($manifest, '{"schema":1,"source":"synthetic-test-only"}', [Text.Encoding]::UTF8)
    New-Sl7PersonalizationCpio -FirmwareFiles $files -ManifestPath $manifest -OutputPath $OutputPath | Out-Null
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
