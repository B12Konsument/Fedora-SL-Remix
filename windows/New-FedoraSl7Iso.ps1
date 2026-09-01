# SPDX-License-Identifier: GPL-2.0-only

<#
.SYNOPSIS
Creates a private Fedora SL7 Remix ISO for the current supported Surface.

.DESCRIPTION
Validates Windows 11 ARM64 and Surface Laptop 7 SKU 2036/2037, obtains signed
Microsoft firmware locally or from the checksum-locked official MSI, verifies
the published firmware-free base, and writes one personalized ISO. The script
does not partition disks or write USB media.

.PARAMETER Release
GitHub release tag to use, or latest. The default is latest.

.PARAMETER FirmwareSource
Auto tries signed local Windows packages before offering the MSI. Windows
requires the local set. Msi uses MsiPath or downloads the locked official MSI.

.PARAMETER MsiPath
Path to a local copy of the exact checksum-locked Microsoft Surface MSI.

.PARAMETER OutputDirectory
Destination directory. The current interactive user's Downloads folder is the
default and is preserved across UAC elevation.

.PARAMETER Model
Auto uses the detected SKU. Romulus13 or Romulus15 is a warned advanced DTB
override and still requires a supported Surface Laptop 7 SKU.

.PARAMETER KeepCache
Retains verified release parts and private temporary extraction data.

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\New-FedoraSl7Iso.ps1
#>

[CmdletBinding()]
param(
    [string]$Release = 'latest',
    [ValidateSet('Auto', 'Windows', 'Msi')][string]$FirmwareSource = 'Auto',
    [string]$MsiPath,
    [string]$OutputDirectory,
    [ValidateSet('Auto', 'Romulus13', 'Romulus15')][string]$Model = 'Auto',
    [switch]$KeepCache,
    [Parameter(DontShow = $true)][string]$LayoutPath,
    [Parameter(DontShow = $true)][string]$OptionsFile,
    [Parameter(DontShow = $true)][string]$OptionsSha256
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'FedoraSl7Remix.psm1') -Force
$customizerVersion = [version]'0.2.1'

function Write-Step {
    param([string]$Text)
    Write-Host "[Fedora SL7 Remix] $Text" -ForegroundColor Cyan
}

function Confirm-Choice {
    param([string]$Prompt)
    $answer = Read-Host "$Prompt [y/N]"
    return $answer -match '^(y|yes)$'
}

function Remove-SafeDirectory {
    param([string]$Path, [string]$ExpectedParent)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $parent = (Resolve-Path -LiteralPath $ExpectedParent).Path.TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected temporary path: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

if ($OptionsFile) {
    if (-not $OptionsSha256) {
        Remove-Item -Force -LiteralPath $OptionsFile -ErrorAction SilentlyContinue
        throw 'The UAC handoff options failed integrity verification.'
    }
    $saved = Read-Sl7ElevationHandoff -Path $OptionsFile -ExpectedSha256 $OptionsSha256
    $Release = [string]$saved.Release
    $FirmwareSource = [string]$saved.FirmwareSource
    $MsiPath = [string]$saved.MsiPath
    $OutputDirectory = [string]$saved.OutputDirectory
    $Model = [string]$saved.Model
    $KeepCache = [bool]$saved.KeepCache
    $LayoutPath = [string]$saved.LayoutPath
}

if ($MsiPath -and $FirmwareSource -eq 'Auto') { $FirmwareSource = 'Msi' }
if ($MsiPath) { $MsiPath = [IO.Path]::GetFullPath($MsiPath) }

if (-not $OutputDirectory) { $OutputDirectory = Get-Sl7DownloadsPath }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

if (-not (Test-Sl7Administrator)) {
    $elevationFile = Join-Path $env:TEMP ("fedora-sl7-elevation-{0}.json" -f [Guid]::NewGuid().ToString('N'))
    try {
        $elevationHash = New-Sl7ElevationHandoff -Path $elevationFile -Release $Release `
            -FirmwareSource $FirmwareSource -MsiPath $MsiPath -OutputDirectory $OutputDirectory `
            -Model $Model -KeepCache ([bool]$KeepCache) -LayoutPath $LayoutPath
        Write-Step 'Administrator access is required to read the signed Windows driver store.'
        $arguments = New-Sl7ElevationArguments -ScriptPath $PSCommandPath -OptionsFile $elevationFile -OptionsSha256 $elevationHash
        $child = Start-Sl7ElevatedPowerShell -ArgumentList $arguments
    }
    finally {
        Remove-Item -Force -LiteralPath $elevationFile -ErrorAction SilentlyContinue
    }
    if ($child.ExitCode -ne 0) { throw "The elevated ISO personalizer failed with exit code $($child.ExitCode)." }
    return
}

$taskRoot = Join-Path $env:TEMP ("fedora-sl7-personalizer-{0}" -f [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $taskRoot | Out-Null
$downloadedMsi = $false
$msiCacheRoot = Join-Path $env:LOCALAPPDATA 'FedoraSL7Remix\cache\microsoft'
$success = $false
$partialIso = $null

try {
    Write-Step 'Validating Windows and Surface hardware before downloading the ISO.'
    Assert-Sl7WindowsArm64
    $hardware = Get-Sl7Hardware -Model $Model
    if ($Model -ne 'Auto') {
        Write-Warning "Manual model override selected: $Model. A wrong DTB can prevent the ISO from booting."
        if (-not (Confirm-Choice 'Continue with the manual hardware override?')) { throw 'Cancelled by the user.' }
    }
    Write-Host "Detected $($hardware.Model), $($hardware.DisplayInches)-inch, SKU $($hardware.Sku)."

    try {
        $githubRelease = Get-Sl7GitHubRelease -Release $Release
    }
    catch {
        throw "Network access to the requested GitHub release is required. $($_.Exception.Message)"
    }
    if (-not $LayoutPath) {
        $LayoutPath = Join-Path $taskRoot 'personalization-layout.json'
        $layoutUrl = Get-Sl7ReleaseAssetUrl $githubRelease 'personalization-layout.json'
        Receive-Sl7File $layoutUrl $LayoutPath | Out-Null
    }
    $layout = Get-Content -LiteralPath $LayoutPath -Raw | ConvertFrom-Json
    Assert-Sl7PersonalizationLayout -Layout $layout -CustomizerVersion $customizerVersion
    if (-not ($layout.hardware.PSObject.Properties.Name -contains $hardware.Sku)) {
        throw "The selected release does not support SKU $($hardware.Sku)."
    }

    $safeTag = ([string]$githubRelease.tag_name) -replace '[^A-Za-z0-9._-]', '_'
    $cacheRoot = Join-Path $env:LOCALAPPDATA "FedoraSL7Remix\cache\$safeTag"

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    [long]$baseBytes = [long]$layout.base_iso.size
    [long]$msiBytes = [long]$layout.microsoft_msi.size
    if ($baseBytes -le 0 -or $msiBytes -le 0) { throw 'Release metadata contains invalid file sizes.' }
    $outputDriveRoot = [IO.Path]::GetPathRoot($OutputDirectory)
    $cacheDriveRoot = [IO.Path]::GetPathRoot($cacheRoot)
    if ([string]::Equals($outputDriveRoot, $cacheDriveRoot, [StringComparison]::OrdinalIgnoreCase)) {
        [long]$requiredBytes = [Math]::Max(10GB, ($baseBytes * 2 + $msiBytes + 2GB))
        $drive = New-Object IO.DriveInfo($outputDriveRoot)
        if ($drive.AvailableFreeSpace -lt $requiredBytes) {
            throw ("At least {0:N1} GiB free space is required on {1}." -f ($requiredBytes / 1GB), $outputDriveRoot)
        }
    }
    else {
        [long]$outputBytes = $baseBytes + 1GB
        [long]$cacheBytes = $baseBytes + $msiBytes + 2GB
        $outputDrive = New-Object IO.DriveInfo($outputDriveRoot)
        $cacheDrive = New-Object IO.DriveInfo($cacheDriveRoot)
        if ($outputDrive.AvailableFreeSpace -lt $outputBytes) {
            throw ("At least {0:N1} GiB free space is required on the output drive {1}." -f ($outputBytes / 1GB), $outputDriveRoot)
        }
        if ($cacheDrive.AvailableFreeSpace -lt $cacheBytes) {
            throw ("At least {0:N1} GiB free space is required on the cache drive {1}." -f ($cacheBytes / 1GB), $cacheDriveRoot)
        }
    }

    Write-Host ''
    Write-Host 'Microsoft firmware notice' -ForegroundColor Yellow
    Write-Host 'The resulting ISO contains proprietary firmware copied for use on this device.'
    Write-Host 'It is for personal use only and must not be redistributed.'
    Write-Host 'This tool creates an ISO; it does not repartition a disk or write USB media.'
    if (-not (Confirm-Choice 'Create a private device-specific ISO?')) { throw 'Cancelled by the user.' }

    $firmwareResult = $null
    $firmwareSourceUsed = $null
    $firmwareSourceVersion = $null
    if ($FirmwareSource -in @('Auto', 'Windows')) {
        Write-Step 'Inspecting active, Microsoft-signed packages in the Windows DriverStore.'
        $firmwareResult = Get-Sl7WindowsFirmware
        if ($firmwareResult.Complete) {
            $firmwareSourceUsed = 'WindowsDriverStore'
            $firmwareSourceVersion = 'active-signed-packages'
        }
        elseif ($FirmwareSource -eq 'Windows') {
            throw "The local Windows firmware set is incomplete: $($firmwareResult.Missing -join ', ')"
        }
        else {
            Write-Warning "The local firmware set is incomplete: $($firmwareResult.Missing -join ', ')"
            if (-not (Confirm-Choice 'Download the checksum-locked official Microsoft Surface MSI instead?')) {
                throw 'Firmware fallback was declined.'
            }
        }
    }

    if ($null -eq $firmwareResult -or -not $firmwareResult.Complete) {
        $msi = $layout.microsoft_msi
        if ($MsiPath) {
            $resolvedMsi = (Resolve-Path -LiteralPath $MsiPath).Path
        }
        else {
            $resolvedMsi = Join-Path $msiCacheRoot ([string]$msi.filename)
            Write-Step 'Downloading the checksum-locked official Microsoft Surface MSI.'
            Receive-Sl7File ([string]$msi.url) $resolvedMsi ([string]$msi.sha256) | Out-Null
            $downloadedMsi = $true
        }
        Write-Step 'Extracting the verified Microsoft MSI locally.'
        $firmwareResult = Expand-Sl7MicrosoftMsi -MsiPath $resolvedMsi -Destination (Join-Path $taskRoot 'msi') -ExpectedSha256 ([string]$msi.sha256)
        $firmwareSourceUsed = 'PinnedMicrosoftMsi'
        $firmwareSourceVersion = [string]$msi.version
    }

    $fileReport = @()
    foreach ($relative in Get-Sl7RequiredFirmware) {
        $fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($firmwareResult.Files[$relative]).FileVersion
        if (-not $fileVersion) { $fileVersion = 'not-reported' }
        $fileReport += [ordered]@{
            path = $relative
            sha256 = Get-Sl7Sha256 $firmwareResult.Files[$relative]
            version = $fileVersion
        }
    }
    $privateManifest = [ordered]@{
        schema = 1
        model = $hardware.Model
        sku = $hardware.Sku
        display_inches = $hardware.DisplayInches
        firmware_source = $firmwareSourceUsed
        firmware_source_version = $firmwareSourceVersion
        files = $fileReport
    }
    $privateManifestPath = Join-Path $taskRoot 'manifest.json'
    [IO.File]::WriteAllText(
        $privateManifestPath,
        ($privateManifest | ConvertTo-Json -Depth 5),
        ([Text.UTF8Encoding]::new($false))
    )

    $cpioPath = Join-Path $taskRoot 'personalization.cpio'
    Write-Step 'Creating the private early-boot firmware archive.'
    New-Sl7PersonalizationCpio -FirmwareFiles $firmwareResult.Files -ManifestPath $privateManifestPath -OutputPath $cpioPath | Out-Null
    if ((Get-Item -LiteralPath $cpioPath).Length -gt [long]$layout.slots.personalization.length) {
        throw 'The private firmware archive exceeds the reserved ISO slot.'
    }

    New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null
    $outputName = "Fedora-SL7-Remix-44-$($layout.remix_version)-$($hardware.Model)-PRIVATE.aarch64.iso"
    $partialIso = Join-Path $OutputDirectory "$outputName.partial"
    $finalIso = Join-Path $OutputDirectory $outputName

    Write-Step "Downloading and verifying the $($layout.base_iso.name) release parts."
    Join-Sl7BaseIso -Release $githubRelease -Layout $layout -CacheDirectory $cacheRoot -OutputPath $partialIso
    Write-Step 'Applying the hardware selector and private firmware to the verified base ISO.'
    $selector = New-Sl7ModelSelector -Hardware $hardware -Length ([int]$layout.slots.model_selector.length)
    Set-Sl7IsoSlot -IsoPath $partialIso -Slot $layout.slots.model_selector -Bytes $selector
    Set-Sl7IsoSlot -IsoPath $partialIso -Slot $layout.slots.personalization -FilePath $cpioPath

    $outputHash = Get-Sl7Sha256 $partialIso
    Publish-Sl7AtomicIso -PartialPath $partialIso -FinalPath $finalIso -ExpectedSha256 $outputHash | Out-Null
    "$outputHash  $outputName" | Set-Content -LiteralPath "$finalIso.sha256" -Encoding ASCII
    $redactedReport = [ordered]@{
        schema = 1
        iso = $outputName
        sha256 = $outputHash
        release = [string]$githubRelease.tag_name
        fedora_release = 44
        remix_version = [string]$layout.remix_version
        model = $hardware.Model
        sku = $hardware.Sku
        firmware_source = $firmwareSourceUsed
        firmware_source_version = $firmwareSourceVersion
        firmware = $fileReport
        redistributable = $false
    }
    [IO.File]::WriteAllText(
        "$finalIso.json",
        ($redactedReport | ConvertTo-Json -Depth 5),
        ([Text.UTF8Encoding]::new($false))
    )

    if (-not $KeepCache) { Remove-SafeDirectory $cacheRoot (Join-Path $env:LOCALAPPDATA 'FedoraSL7Remix\cache') }
    if ($downloadedMsi -and -not $KeepCache) {
        Remove-SafeDirectory $msiCacheRoot (Join-Path $env:LOCALAPPDATA 'FedoraSL7Remix\cache')
    }
    $success = $true
    Write-Host ''
    Write-Host 'Private ISO created successfully:' -ForegroundColor Green
    Write-Host $finalIso
    Write-Host 'Secure Boot must be disabled. Do not redistribute this ISO.' -ForegroundColor Yellow
    if ($KeepCache) { Write-Host "Temporary private data was retained in: $taskRoot" -ForegroundColor Yellow }
}
catch {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally {
    if (-not $success -and $partialIso -and (Test-Path -LiteralPath $partialIso)) {
        Remove-Item -Force -LiteralPath $partialIso -ErrorAction SilentlyContinue
    }
    if ((-not $KeepCache) -and (Test-Path -LiteralPath $taskRoot)) {
        Remove-SafeDirectory $taskRoot $env:TEMP
    }
    if ($downloadedMsi -and -not $KeepCache -and (Test-Path -LiteralPath $msiCacheRoot)) {
        Remove-SafeDirectory $msiCacheRoot (Join-Path $env:LOCALAPPDATA 'FedoraSL7Remix\cache')
    }
    if (-not $success) {
        Write-Host 'No disk was repartitioned and no USB media was written.' -ForegroundColor Yellow
        if ($KeepCache) { Write-Host "Temporary private data was retained in: $taskRoot" -ForegroundColor Yellow }
    }
}
