# SPDX-License-Identifier: GPL-2.0-only

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Repository = 'B12Konsument/Fedora-SL-Remix'
$script:RequiredFirmware = @(
    'qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn',
    'qcom/x1e80100/microsoft/Romulus/adsp_dtbs.elf',
    'qcom/x1e80100/microsoft/Romulus/adspr.jsn',
    'qcom/x1e80100/microsoft/Romulus/adsps.jsn',
    'qcom/x1e80100/microsoft/Romulus/adspua.jsn',
    'qcom/x1e80100/microsoft/Romulus/battmgr.jsn',
    'qcom/x1e80100/microsoft/Romulus/cdsp_dtbs.elf',
    'qcom/x1e80100/microsoft/Romulus/cdspr.jsn',
    'qcom/x1e80100/microsoft/Romulus/qcadsp8380.mbn',
    'qcom/x1e80100/microsoft/Romulus/qccdsp8380.mbn'
)

function Get-Sl7RequiredFirmware {
    return @($script:RequiredFirmware)
}

function Get-Sl7Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-Sl7Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Sl7DownloadsPath {
    param([string]$RegistryValue, [string]$UserProfile)
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $name = '{374DE290-123F-4565-9164-39C4925E467B}'
    if (-not $RegistryValue) {
        try {
            $RegistryValue = (Get-ItemProperty -LiteralPath $key -Name $name).$name
        }
        catch {}
    }
    if ($RegistryValue) {
        return [Environment]::ExpandEnvironmentVariables($RegistryValue)
    }
    if (-not $UserProfile) { $UserProfile = [Environment]::GetFolderPath('UserProfile') }
    return $UserProfile.TrimEnd('\') + '\Downloads'
}

function New-Sl7ElevationArguments {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$OptionsFile,
        [Parameter(Mandatory = $true)][string]$OptionsSha256
    )
    return @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ScriptPath`"",
        '-OptionsFile', "`"$OptionsFile`"", '-OptionsSha256', $OptionsSha256
    )
}

function Assert-Sl7WindowsArm64 {
    param(
        [object]$OperatingSystem,
        [object]$Processor,
        [PlatformID]$Platform = [Environment]::OSVersion.Platform
    )
    if ($Platform -ne [PlatformID]::Win32NT) {
        throw 'The ISO personalizer requires Windows 11 ARM64.'
    }
    if ($null -eq $OperatingSystem) {
        $OperatingSystem = Get-CimInstance Win32_OperatingSystem
    }
    if ($null -eq $Processor) {
        $Processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    }
    if ([int]$OperatingSystem.BuildNumber -lt 22000) {
        throw 'Windows 11 or newer is required.'
    }
    if ([int]$Processor.Architecture -ne 12) {
        throw 'This computer is not running Windows on ARM64.'
    }
}

function Get-Sl7Hardware {
    param(
        [ValidateSet('Auto', 'Romulus13', 'Romulus15')][string]$Model = 'Auto',
        [object]$ComputerSystem,
        [object]$ComputerSystemProduct
    )
    if ($null -eq $ComputerSystem) {
        $ComputerSystem = Get-CimInstance Win32_ComputerSystem
    }
    if ($null -eq $ComputerSystemProduct) {
        $ComputerSystemProduct = Get-CimInstance Win32_ComputerSystemProduct
    }
    $candidates = @(
        [string]$ComputerSystem.SystemSKUNumber,
        [string]$ComputerSystem.Model,
        [string]$ComputerSystemProduct.Name,
        [string]$ComputerSystemProduct.Version
    )
    $sku = $null
    foreach ($candidate in $candidates) {
        $normalized = (($candidate -replace '[^A-Za-z0-9]+', '_').Trim('_'))
        if ($normalized -match 'Surface_Laptop_7th_Edition_2036') { $sku = 'Surface_Laptop_7th_Edition_2036'; break }
        if ($normalized -match 'Surface_Laptop_7th_Edition_2037') { $sku = 'Surface_Laptop_7th_Edition_2037'; break }
    }
    if ($null -eq $sku) {
        throw 'This is not a supported Surface Laptop 7 (expected Microsoft system SKU 2036 or 2037).'
    }
    if ($Model -eq 'Auto') {
        $Model = if ($sku -like '*2036') { 'Romulus13' } else { 'Romulus15' }
    }
    return [pscustomobject]@{
        Sku = $sku
        Model = $Model
        DisplayInches = if ($Model -eq 'Romulus13') { '13.8' } else { '15' }
        Dtb = if ($Model -eq 'Romulus13') { '/boot/dtb/fedora-sl7-remix/romulus13.dtb' } else { '/boot/dtb/fedora-sl7-remix/romulus15.dtb' }
    }
}

function Get-Sl7GitHubRelease {
    param([string]$Release = 'latest')
    $headers = @{ 'User-Agent' = 'Fedora-SL7-Remix-Windows-Personalizer' }
    if ($Release -eq 'latest') {
        $releases = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri "https://api.github.com/repos/$script:Repository/releases?per_page=20"
        $result = $releases | Where-Object { -not $_.draft } | Select-Object -First 1
    }
    else {
        $escaped = [Uri]::EscapeDataString($Release)
        $result = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri "https://api.github.com/repos/$script:Repository/releases/tags/$escaped"
    }
    if ($null -eq $result) { throw "No published project release matched '$Release'." }
    return $result
}

function Get-Sl7ReleaseAssetUrl {
    param([Parameter(Mandatory = $true)]$Release, [Parameter(Mandatory = $true)][string]$Name)
    $asset = $Release.assets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($null -eq $asset) { throw "Release '$($Release.tag_name)' has no asset named '$Name'." }
    return [string]$asset.browser_download_url
}

function Assert-Sl7PersonalizationLayout {
    param(
        [Parameter(Mandatory = $true)]$Layout,
        [Parameter(Mandatory = $true)][version]$CustomizerVersion
    )
    try {
        if ([int]$Layout.schema -ne 1) { throw 'unsupported schema' }
        if ($CustomizerVersion -lt [version]$Layout.minimum_customizer_version) {
            throw "customizer $($Layout.minimum_customizer_version) or newer is required"
        }
        if ([int]$Layout.fedora_release -ne 44) { throw 'Fedora release is not 44' }
        if ([string]$Layout.remix_version -notmatch '^\d+\.\d+\.\d+([._-][A-Za-z0-9.-]+)?$') {
            throw 'invalid remix version'
        }
        if ([string]$Layout.source_lock_sha256 -notmatch '^[0-9a-f]{64}$') { throw 'invalid source-lock hash' }

        [long]$baseSize = [long]$Layout.base_iso.size
        if ($baseSize -le 0 -or [string]$Layout.base_iso.sha256 -notmatch '^[0-9a-f]{64}$') {
            throw 'invalid base ISO size or hash'
        }
        $baseName = [string]$Layout.base_iso.name
        if ($baseName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$' -or $baseName.Contains('..')) {
            throw 'unsafe base ISO name'
        }
        $parts = @($Layout.base_iso.parts)
        if ($parts.Count -eq 0) { throw 'release has no base ISO parts' }
        [long]$partBytes = 0
        foreach ($part in $parts) {
            $partName = [string]$part.name
            if ($partName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$' -or $partName.Contains('..')) {
                throw 'unsafe release-part name'
            }
            if ([long]$part.size -le 0 -or [string]$part.sha256 -notmatch '^[0-9a-f]{64}$') {
                throw 'invalid release-part size or hash'
            }
            $partBytes += [long]$part.size
        }
        if ($partBytes -ne $baseSize) { throw 'release-part sizes do not equal the base ISO size' }

        $selector = $Layout.slots.model_selector
        $payload = $Layout.slots.personalization
        if ([string]$selector.path -ne '/boot/sl7/model.cfg' -or [long]$selector.length -ne 4096) {
            throw 'invalid model-selector slot'
        }
        if ([string]$payload.path -ne '/boot/sl7/personalization.cpio' -or
            [long]$payload.length -ne 268435456) {
            throw 'invalid personalization slot'
        }
        foreach ($slot in @($selector, $payload)) {
            if ([long]$slot.offset -lt 0 -or ([long]$slot.offset + [long]$slot.length) -gt $baseSize -or
                [string]$slot.placeholder_sha256 -notmatch '^[0-9a-f]{64}$') {
                throw 'slot is outside the base ISO or has an invalid placeholder hash'
            }
        }
        [long]$selectorEnd = [long]$selector.offset + [long]$selector.length
        [long]$payloadEnd = [long]$payload.offset + [long]$payload.length
        if ([long]$selector.offset -lt $payloadEnd -and [long]$payload.offset -lt $selectorEnd) {
            throw 'personalization slots overlap'
        }

        $sku13 = $Layout.hardware.Surface_Laptop_7th_Edition_2036
        $sku15 = $Layout.hardware.Surface_Laptop_7th_Edition_2037
        if ([string]$sku13.model -ne 'Romulus13' -or
            [string]$sku13.dtb -ne '/boot/dtb/fedora-sl7-remix/romulus13.dtb' -or
            [string]$sku15.model -ne 'Romulus15' -or
            [string]$sku15.dtb -ne '/boot/dtb/fedora-sl7-remix/romulus15.dtb') {
            throw 'invalid SKU-to-DTB mapping'
        }

        $msi = $Layout.microsoft_msi
        $msiUri = [Uri]([string]$msi.url)
        if ($msiUri.Scheme -ne 'https' -or $msiUri.Host -ne 'download.microsoft.com' -or
            [long]$msi.size -le 0 -or [string]$msi.sha256 -notmatch '^[0-9a-f]{64}$' -or
            -not [string]$msi.version -or [string]$msi.filename -notmatch '^[A-Za-z0-9._-]+[.]msi$') {
            throw 'invalid Microsoft MSI metadata'
        }
    }
    catch {
        throw "Release personalization layout is invalid: $($_.Exception.Message)"
    }
}

function Receive-Sl7BitsFile {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$PartialPath
    )
    $nameMaterial = [Text.Encoding]::UTF8.GetBytes("$Uri`n$PartialPath")
    $nameHash = [Security.Cryptography.SHA256]::Create()
    try {
        $displayName = 'Fedora SL7 Remix ' +
            (([BitConverter]::ToString($nameHash.ComputeHash($nameMaterial))).Replace('-', '').Substring(0, 20))
    }
    finally { $nameHash.Dispose() }
    $job = Get-BitsTransfer -Name $displayName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $job) {
        if (Test-Path -LiteralPath $PartialPath) {
            throw 'A resumable HTTPS partial already exists.'
        }
        $bitsArguments = @{
            Source = $Uri
            Destination = $PartialPath
            DisplayName = $displayName
            Description = 'Fedora SL7 Remix verified download'
            Asynchronous = $true
        }
        $job = Start-BitsTransfer @bitsArguments
    }
    while ($true) {
        $job = Get-BitsTransfer -Id $job.Id
        switch ([string]$job.JobState) {
            'Transferred' {
                Complete-BitsTransfer -BitsJob $job
                return
            }
            'Error' {
                $message = [string]$job.ErrorDescription
                Remove-BitsTransfer -BitsJob $job -Confirm:$false
                throw "BITS reported an unrecoverable error: $message"
            }
            'Cancelled' {
                Remove-BitsTransfer -BitsJob $job -Confirm:$false -ErrorAction SilentlyContinue
                throw 'The BITS download was cancelled.'
            }
            'Acknowledged' { return }
            'Suspended' { Resume-BitsTransfer -BitsJob $job -Asynchronous | Out-Null }
            default { Start-Sleep -Seconds 1 }
        }
    }
}

function Receive-Sl7File {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$Sha256
    )
    if ((Test-Path -LiteralPath $Destination) -and $Sha256) {
        if ((Get-Sl7Sha256 $Destination) -eq $Sha256.ToLowerInvariant()) { return $Destination }
    }
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $partial = "$Destination.partial"
    if ((Test-Path -LiteralPath $partial) -and $Sha256 -and
        (Get-Sl7Sha256 $partial) -eq $Sha256.ToLowerInvariant()) {
        Move-Item -Force -LiteralPath $partial -Destination $Destination
        return $Destination
    }
    try {
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            try {
                Receive-Sl7BitsFile -Uri $Uri -PartialPath $partial
            }
            catch {
                Write-Warning "BITS was unavailable for this transfer; using resumable HTTPS. $($_.Exception.Message)"
                Receive-Sl7HttpsPartial -Uri $Uri -PartialPath $partial
            }
        }
        else {
            Receive-Sl7HttpsPartial -Uri $Uri -PartialPath $partial
        }
    }
    catch {
        throw "Download failed for $Uri. Recoverable partial data was kept. $($_.Exception.Message)"
    }
    if ($Sha256 -and (Get-Sl7Sha256 $partial) -ne $Sha256.ToLowerInvariant()) {
        Remove-Item -Force -LiteralPath $partial -ErrorAction SilentlyContinue
        throw "SHA-256 verification failed for $Uri."
    }
    Move-Item -Force -LiteralPath $partial -Destination $Destination
    return $Destination
}

function New-Sl7HttpRequest {
    param([Parameter(Mandatory = $true)][string]$Uri)
    return [Net.HttpWebRequest]::Create($Uri)
}

function Receive-Sl7HttpsPartial {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$PartialPath
    )
    $lastError = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            [long]$existing = if (Test-Path -LiteralPath $PartialPath) {
                (Get-Item -LiteralPath $PartialPath).Length
            } else { 0 }
            $request = New-Sl7HttpRequest $Uri
            $request.Method = 'GET'
            $request.AllowAutoRedirect = $true
            $request.UserAgent = 'Fedora-SL7-Remix-Windows-Personalizer'
            if ($existing -gt 0) { $request.AddRange($existing) }
            $response = $request.GetResponse()
            try {
                $append = $existing -gt 0 -and [int]$response.StatusCode -eq 206
                $mode = if ($append) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }
                $output = [IO.File]::Open($PartialPath, $mode, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try {
                    $input = $response.GetResponseStream()
                    try { $input.CopyTo($output) } finally { $input.Dispose() }
                }
                finally { $output.Dispose() }
            }
            finally { $response.Dispose() }
            return
        }
        catch {
            $lastError = $_.Exception
            if ($attempt -lt 3) { Start-Sleep -Seconds ([Math]::Pow(2, $attempt - 1)) }
        }
    }
    throw "HTTPS download failed after three attempts: $($lastError.Message)"
}

function Test-Sl7MicrosoftCatalog {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$FilePath
    )
    if (-not (Get-Command Test-FileCatalog -ErrorAction SilentlyContinue)) { return $false }
    foreach ($catalog in Get-ChildItem -LiteralPath $Directory -Filter '*.cat' -File -ErrorAction SilentlyContinue) {
        $signature = Get-AuthenticodeSignature -LiteralPath $catalog.FullName
        if ($signature.Status -eq 'Valid' -and $null -ne $signature.SignerCertificate -and
            $signature.SignerCertificate.Subject -match 'Microsoft') {
            try {
                $catalogStatus = Test-FileCatalog -Path $FilePath -CatalogFilePath $catalog.FullName -ErrorAction Stop
                if ([string]$catalogStatus -eq 'Valid') { return $true }
            }
            catch { continue }
        }
    }
    return $false
}

function Test-Sl7MicrosoftSignature {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [object]$Signature
    )
    if ($null -eq $Signature) {
        $Signature = Get-AuthenticodeSignature -LiteralPath $FilePath
    }
    return $Signature.Status -eq 'Valid' -and $null -ne $Signature.SignerCertificate -and
        $Signature.SignerCertificate.Subject -match 'Microsoft'
}

function Get-Sl7PnpPackageDirectories {
    param(
        [Parameter(Mandatory = $true)][xml]$Inventory,
        [Parameter(Mandatory = $true)][string]$DriverStore
    )
    $directories = @{}
    $drivers = @($Inventory.SelectNodes("//*[local-name()='driver' or local-name()='Driver']"))
    $scopes = if ($drivers.Count -gt 0) { $drivers } else { @($Inventory.DocumentElement) }
    foreach ($scope in $scopes) {
        $devices = $scope.SelectSingleNode(".//*[local-name()='devices' or local-name()='Devices']")
        if ($null -ne $devices) {
            $count = $devices.SelectSingleNode("./*[local-name()='count' or local-name()='Count']")
            $countValue = if ($null -ne $count) { [string]$count.InnerText } else { [string]$devices.GetAttribute('count') }
            if ($countValue -match '^\s*0\s*$') { continue }
        }
        foreach ($node in $scope.SelectNodes('.//text()')) {
            $value = ([string]$node.Value).Replace('/', '\')
            if ($value -match '(?i)FileRepository\\([^\\]+)') {
                # These are Windows paths even when this pure parser is exercised by
                # cross-platform CI, so do not ask the current path provider to resolve C:.
                $directories[($DriverStore.TrimEnd('\') + '\' + $Matches[1])] = $true
            }
        }
    }
    return @($directories.Keys)
}

function Get-Sl7FirmwareFromTree {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$RequireMicrosoftCatalog,
        [string[]]$AllowedPackageRoots = @()
    )
    $files = @{}
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($relative in $script:RequiredFirmware) {
        $name = Split-Path -Leaf $relative
        $candidates = @(Get-ChildItem -LiteralPath $Root -Filter $name -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending)
        $selected = $null
        foreach ($candidate in $candidates) {
            $relativeCandidate = $candidate.FullName.Substring($Root.TrimEnd('\').Length).TrimStart('\')
            $packageName = ($relativeCandidate -split '\\')[0]
            $packageRoot = if ($packageName) { $Root.TrimEnd('\') + '\' + $packageName } else { $Root }
            $allowed = $AllowedPackageRoots.Count -eq 0 -or @($AllowedPackageRoots | Where-Object {
                [string]::Equals($_.TrimEnd('\'), $packageRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
            }).Count -gt 0
            if ($allowed -and (-not $RequireMicrosoftCatalog -or
                (Test-Sl7MicrosoftCatalog -Directory $packageRoot -FilePath $candidate.FullName))) {
                $selected = $candidate.FullName
                break
            }
        }
        if ($null -eq $selected) { $missing.Add($relative) } else { $files[$relative] = $selected }
    }
    return [pscustomobject]@{ Complete = ($missing.Count -eq 0); Files = $files; Missing = @($missing) }
}

function Get-Sl7WindowsFirmware {
    param([string]$WindowsRoot = $env:SystemRoot)
    $inventory = Join-Path $env:TEMP ("sl7-pnp-{0}.xml" -f [Guid]::NewGuid().ToString('N'))
    $packageRoots = @()
    try {
        $process = Start-Process -FilePath (Join-Path $WindowsRoot 'System32\pnputil.exe') -ArgumentList @(
            '/enum-drivers', '/devices', '/files', '/format', 'xml', '/output-file', $inventory
        ) -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) {
            Write-Warning 'PnPUtil could not create a driver inventory; signed DriverStore validation will still run.'
        }
        elseif (Test-Path -LiteralPath $inventory) {
            [xml]$inventoryXml = Get-Content -LiteralPath $inventory -Raw
            $store = Join-Path $WindowsRoot 'System32\DriverStore\FileRepository'
            $packageRoots = @(Get-Sl7PnpPackageDirectories -Inventory $inventoryXml -DriverStore $store)
        }
    }
    finally {
        Remove-Item -Force -LiteralPath $inventory -ErrorAction SilentlyContinue
    }
    $store = Join-Path $WindowsRoot 'System32\DriverStore\FileRepository'
    if ($packageRoots.Count -eq 0) {
        Write-Warning 'PnPUtil reported no active package paths; scanning all Microsoft-signed DriverStore packages.'
    }
    $result = Get-Sl7FirmwareFromTree -Root $store -RequireMicrosoftCatalog -AllowedPackageRoots $packageRoots
    $gpuRelative = 'qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn'
    if ($result.Missing -contains $gpuRelative) {
        $systemGpu = Join-Path $WindowsRoot 'System32\qcdxkmsuc8380.mbn'
        if ((Test-Path -LiteralPath $systemGpu) -and (Test-Sl7MicrosoftSignature -FilePath $systemGpu)) {
            $result.Files[$gpuRelative] = $systemGpu
            $result.Missing = @($result.Missing | Where-Object { $_ -ne $gpuRelative })
            $result.Complete = $result.Missing.Count -eq 0
        }
    }
    return $result
}

function Expand-Sl7MicrosoftMsi {
    param(
        [Parameter(Mandatory = $true)][string]$MsiPath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )
    if ((Get-Sl7Sha256 $MsiPath) -ne $ExpectedSha256.ToLowerInvariant()) {
        throw 'The Microsoft MSI SHA-256 does not match the locked project source.'
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $arguments = "/a `"$MsiPath`" /qn TARGETDIR=`"$Destination`""
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) { throw "Microsoft MSI extraction failed with exit code $($process.ExitCode)." }
    $result = Get-Sl7FirmwareFromTree -Root $Destination
    if (-not $result.Complete) { throw "The locked Microsoft MSI lacks required firmware: $($result.Missing -join ', ')" }
    return $result
}

function Write-Sl7Ascii {
    param([System.IO.Stream]$Stream, [string]$Text)
    $bytes = [Text.Encoding]::ASCII.GetBytes($Text)
    $Stream.Write($bytes, 0, $bytes.Length)
}

function Write-Sl7Padding {
    param([System.IO.Stream]$Stream, [int]$Alignment = 4)
    $count = [int](($Alignment - ($Stream.Position % $Alignment)) % $Alignment)
    if ($count -gt 0) { $Stream.Write((New-Object byte[] $count), 0, $count) }
}

function Add-Sl7NewcEntry {
    param(
        [System.IO.Stream]$Stream,
        [uint32]$Inode,
        [string]$ArchivePath,
        [uint32]$Mode,
        [string]$SourcePath
    )
    $nameBytes = [Text.Encoding]::UTF8.GetBytes($ArchivePath)
    $fileSize = if ($SourcePath) { [uint32](Get-Item -LiteralPath $SourcePath).Length } else { [uint32]0 }
    $fields = @($Inode, $Mode, 0, 0, 1, 0, $fileSize, 0, 0, 0, 0, ($nameBytes.Length + 1), 0)
    Write-Sl7Ascii $Stream '070701'
    foreach ($field in $fields) { Write-Sl7Ascii $Stream ([uint32]$field).ToString('x8') }
    $Stream.Write($nameBytes, 0, $nameBytes.Length)
    $Stream.WriteByte(0)
    Write-Sl7Padding $Stream
    if ($SourcePath) {
        $input = [IO.File]::OpenRead($SourcePath)
        try { $input.CopyTo($Stream) } finally { $input.Dispose() }
        Write-Sl7Padding $Stream
    }
}

function New-Sl7PersonalizationCpio {
    param(
        [Parameter(Mandatory = $true)][hashtable]$FirmwareFiles,
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )
    $entries = New-Object System.Collections.Generic.List[object]
    $early = 'qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn'
    $entries.Add([pscustomobject]@{ Path = "usr/lib/firmware/updates/$early"; Source = $FirmwareFiles[$early] })
    foreach ($relative in $script:RequiredFirmware) {
        $entries.Add([pscustomobject]@{ Path = "sl7-personalization/firmware/$relative"; Source = $FirmwareFiles[$relative] })
    }
    $entries.Add([pscustomobject]@{ Path = 'sl7-personalization/manifest.json'; Source = $ManifestPath })

    $directories = @{}
    foreach ($entry in $entries) {
        $parts = $entry.Path -split '/'
        for ($index = 1; $index -lt $parts.Length; $index++) {
            $directories[($parts[0..($index - 1)] -join '/')] = $true
        }
    }
    $stream = [IO.File]::Open($OutputPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        [uint32]$inode = 1
        foreach ($directory in ($directories.Keys | Sort-Object { ($_ -split '/').Length }, { $_ })) {
            Add-Sl7NewcEntry $stream $inode $directory ([uint32]0x000041ED) $null
            $inode++
        }
        foreach ($entry in $entries) {
            Add-Sl7NewcEntry $stream $inode $entry.Path ([uint32]0x000081A4) $entry.Source
            $inode++
        }
        Add-Sl7NewcEntry $stream $inode 'TRAILER!!!' 0 $null
    }
    finally { $stream.Dispose() }
    return $OutputPath
}

function New-Sl7ModelSelector {
    param([Parameter(Mandatory = $true)]$Hardware, [int]$Length = 4096)
    $text = @"
# FEDORA_SL7_MODEL_SLOT_V1
set sl7_personalized="1"
set sl7_model="$($Hardware.Model)"
set sl7_model_label="Surface Laptop 7 $($Hardware.DisplayInches)-inch"
set sl7_dtb="$($Hardware.Dtb)"
"@
    $content = [Text.Encoding]::ASCII.GetBytes($text.Replace("`r`n", "`n"))
    if ($content.Length -gt $Length) { throw 'The model selector exceeds its reserved ISO slot.' }
    $result = New-Object byte[] $Length
    for ($index = 0; $index -lt $result.Length; $index++) { $result[$index] = 0x20 }
    [Array]::Copy($content, $result, $content.Length)
    return $result
}

function Get-Sl7SegmentSha256 {
    param([System.IO.Stream]$Stream, [long]$Offset, [long]$Length)
    $null = $Stream.Seek($Offset, [IO.SeekOrigin]::Begin)
    $hash = [Security.Cryptography.SHA256]::Create()
    $buffer = New-Object byte[] (1024 * 1024)
    $remaining = $Length
    try {
        while ($remaining -gt 0) {
            $wanted = [int][Math]::Min($buffer.Length, $remaining)
            $read = $Stream.Read($buffer, 0, $wanted)
            if ($read -le 0) { throw 'Unexpected end of ISO while hashing a personalization slot.' }
            $remaining -= $read
            if ($remaining -gt 0) { $null = $hash.TransformBlock($buffer, 0, $read, $null, 0) }
            else { $null = $hash.TransformFinalBlock($buffer, 0, $read) }
        }
        return ([BitConverter]::ToString($hash.Hash)).Replace('-', '').ToLowerInvariant()
    }
    finally { $hash.Dispose() }
}

function Set-Sl7IsoSlot {
    param(
        [Parameter(Mandatory = $true)][string]$IsoPath,
        [Parameter(Mandatory = $true)]$Slot,
        [byte[]]$Bytes,
        [string]$FilePath
    )
    $hasBytes = $null -ne $Bytes
    $hasFile = -not [string]::IsNullOrWhiteSpace($FilePath)
    if ($hasBytes -eq $hasFile) { throw 'Provide exactly one ISO-slot data source.' }

    $stream = [IO.File]::Open($IsoPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $placeholder = Get-Sl7SegmentSha256 $stream ([long]$Slot.offset) ([long]$Slot.length)
        if ($placeholder -ne ([string]$Slot.placeholder_sha256).ToLowerInvariant()) {
            throw "The base ISO placeholder hash is wrong for slot '$($Slot.path)'."
        }
        $length = if ($hasBytes) { $Bytes.Length } else { (Get-Item -LiteralPath $FilePath).Length }
        if ($length -gt [long]$Slot.length) { throw "Personalization data does not fit slot '$($Slot.path)'." }
        $null = $stream.Seek([long]$Slot.offset, [IO.SeekOrigin]::Begin)
        if ($hasBytes) { $stream.Write($Bytes, 0, $Bytes.Length) }
        else {
            $input = [IO.File]::OpenRead($FilePath)
            try { $input.CopyTo($stream) } finally { $input.Dispose() }
        }
        $zeros = New-Object byte[] (1024 * 1024)
        [long]$remaining = [long]$Slot.length - $length
        while ($remaining -gt 0) {
            $count = [int][Math]::Min($zeros.Length, $remaining)
            $stream.Write($zeros, 0, $count)
            $remaining -= $count
        }
        $stream.Flush()

        # Hash the intended data plus its zero padding, then hash the bytes back
        # from the ISO. This catches short writes without loading the 256 MiB
        # personalization extent into memory.
        $expectedHasher = [Security.Cryptography.IncrementalHash]::CreateHash(
            [Security.Cryptography.HashAlgorithmName]::SHA256
        )
        try {
            if ($hasBytes) {
                $expectedHasher.AppendData($Bytes)
            }
            else {
                $input = [IO.File]::OpenRead($FilePath)
                $buffer = New-Object byte[] (1024 * 1024)
                try {
                    while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $expectedHasher.AppendData($buffer, 0, $read)
                    }
                }
                finally { $input.Dispose() }
            }
            [long]$hashPadding = [long]$Slot.length - $length
            $zeroBuffer = New-Object byte[] (1024 * 1024)
            while ($hashPadding -gt 0) {
                $count = [int][Math]::Min($zeroBuffer.Length, $hashPadding)
                $expectedHasher.AppendData($zeroBuffer, 0, $count)
                $hashPadding -= $count
            }
            $expectedHash = ([BitConverter]::ToString($expectedHasher.GetHashAndReset())).Replace('-', '').ToLowerInvariant()
        }
        finally { $expectedHasher.Dispose() }
        $writtenHash = Get-Sl7SegmentSha256 $stream ([long]$Slot.offset) ([long]$Slot.length)
        if ($writtenHash -ne $expectedHash) {
            throw "Read-back verification failed for ISO slot '$($Slot.path)'."
        }
    }
    finally { $stream.Dispose() }
}

function Join-Sl7BaseIso {
    param(
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)]$Layout,
        [Parameter(Mandatory = $true)][string]$CacheDirectory,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )
    $parts = @($Layout.base_iso.parts)
    if ($parts.Count -eq 0) {
        $parts = @([pscustomobject]@{ name = $Layout.base_iso.name; sha256 = $Layout.base_iso.sha256; size = $Layout.base_iso.size })
    }
    $output = [IO.File]::Open($OutputPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        foreach ($part in $parts) {
            $destination = Join-Path $CacheDirectory ([string]$part.name)
            $url = Get-Sl7ReleaseAssetUrl $Release ([string]$part.name)
            Receive-Sl7File $url $destination ([string]$part.sha256) | Out-Null
            $input = [IO.File]::OpenRead($destination)
            try { $input.CopyTo($output) } finally { $input.Dispose() }
        }
    }
    finally { $output.Dispose() }
    if ((Get-Sl7Sha256 $OutputPath) -ne ([string]$Layout.base_iso.sha256).ToLowerInvariant()) {
        throw 'The reassembled personalization-base ISO failed SHA-256 verification.'
    }
}

function Publish-Sl7AtomicIso {
    param(
        [Parameter(Mandatory = $true)][string]$PartialPath,
        [Parameter(Mandatory = $true)][string]$FinalPath,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )
    $partialFull = [IO.Path]::GetFullPath($PartialPath)
    $finalFull = [IO.Path]::GetFullPath($FinalPath)
    if (-not [string]::Equals(
        [IO.Path]::GetDirectoryName($partialFull),
        [IO.Path]::GetDirectoryName($finalFull),
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'The temporary and final ISO must be on the same filesystem path for atomic publication.'
    }
    $expected = $ExpectedSha256.ToLowerInvariant()
    if ((Get-Sl7Sha256 $partialFull) -ne $expected) {
        throw 'The completed private ISO failed SHA-256 verification before publication.'
    }
    Move-Item -Force -LiteralPath $partialFull -Destination $finalFull
    if ((Get-Sl7Sha256 $finalFull) -ne $expected) {
        throw 'The atomically published ISO failed final SHA-256 verification.'
    }
    return $finalFull
}

Export-ModuleMember -Function @(
    'Assert-Sl7PersonalizationLayout', 'Assert-Sl7WindowsArm64', 'Expand-Sl7MicrosoftMsi', 'Get-Sl7DownloadsPath',
    'Get-Sl7FirmwareFromTree', 'Get-Sl7GitHubRelease', 'Get-Sl7Hardware',
    'Get-Sl7PnpPackageDirectories', 'Get-Sl7ReleaseAssetUrl', 'Get-Sl7RequiredFirmware', 'Get-Sl7SegmentSha256',
    'Get-Sl7Sha256', 'Get-Sl7WindowsFirmware', 'Join-Sl7BaseIso',
    'New-Sl7ElevationArguments', 'New-Sl7ModelSelector', 'New-Sl7PersonalizationCpio', 'Publish-Sl7AtomicIso',
    'Receive-Sl7BitsFile', 'Receive-Sl7File', 'Receive-Sl7HttpsPartial',
    'Receive-Sl7HttpsPartial', 'Set-Sl7IsoSlot', 'Test-Sl7Administrator', 'Test-Sl7MicrosoftCatalog',
    'Test-Sl7MicrosoftSignature'
)
