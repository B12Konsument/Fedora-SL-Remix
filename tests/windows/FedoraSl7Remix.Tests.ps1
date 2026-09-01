# SPDX-License-Identifier: GPL-2.0-only

BeforeAll {
    Import-Module "$PSScriptRoot\..\..\windows\FedoraSl7Remix.psm1" -Force

    function New-Sl7TestLayout {
        [long]$baseSize = 300MB
        return [pscustomobject][ordered]@{
            schema = 1
            minimum_customizer_version = '0.2.1'
            fedora_release = 44
            remix_version = '0.2.1'
            source_lock_sha256 = '1' * 64
            base_iso = [pscustomobject]@{
                name = 'Fedora-SL7-base.aarch64.iso'
                size = $baseSize
                sha256 = '2' * 64
                parts = @([pscustomobject]@{ name = 'base.part-000'; size = $baseSize; sha256 = '3' * 64 })
            }
            slots = [pscustomobject]@{
                model_selector = [pscustomobject]@{ path = '/boot/sl7/model.cfg'; offset = 2048; length = 4096; placeholder_sha256 = '4' * 64 }
                personalization = [pscustomobject]@{ path = '/boot/sl7/personalization.cpio'; offset = 1MB; length = 268435456; placeholder_sha256 = '5' * 64 }
            }
            hardware = [pscustomobject]@{
                Surface_Laptop_7th_Edition_2036 = [pscustomobject]@{ model = 'Romulus13'; dtb = '/boot/dtb/fedora-sl7-remix/romulus13.dtb' }
                Surface_Laptop_7th_Edition_2037 = [pscustomobject]@{ model = 'Romulus15'; dtb = '/boot/dtb/fedora-sl7-remix/romulus15.dtb' }
            }
            microsoft_msi = [pscustomobject]@{
                filename = 'SurfaceLaptop7.msi'
                version = '26.053.36539.0'
                url = 'https://download.microsoft.com/SurfaceLaptop7.msi'
                size = 523874304
                sha256 = '6' * 64
            }
        }
    }
}

Describe 'Windows ARM64 validation' {
    It 'accepts Windows 11 on ARM64' {
        { Assert-Sl7WindowsArm64 -Platform Win32NT -OperatingSystem ([pscustomobject]@{ BuildNumber = 26100 }) -Processor ([pscustomobject]@{ Architecture = 12 }) } | Should -Not -Throw
    }

    It 'rejects x86_64 before downloads' {
        { Assert-Sl7WindowsArm64 -Platform Win32NT -OperatingSystem ([pscustomobject]@{ BuildNumber = 26100 }) -Processor ([pscustomobject]@{ Architecture = 9 }) } | Should -Throw
    }

    It 'rejects pre-Windows 11 builds' {
        { Assert-Sl7WindowsArm64 -Platform Win32NT -OperatingSystem ([pscustomobject]@{ BuildNumber = 19045 }) -Processor ([pscustomobject]@{ Architecture = 12 }) } | Should -Throw
    }
}

Describe 'release layout validation' {
    It 'accepts the fixed versioned layout' {
        { Assert-Sl7PersonalizationLayout -Layout (New-Sl7TestLayout) -CustomizerVersion '0.2.1' } | Should -Not -Throw
    }

    It 'rejects the previous Windows customizer version' {
        { Assert-Sl7PersonalizationLayout -Layout (New-Sl7TestLayout) -CustomizerVersion '0.2.0' } | Should -Throw
    }

    It 'rejects overlapping personalization slots' {
        $layout = New-Sl7TestLayout
        $layout.slots.personalization.offset = $layout.slots.model_selector.offset
        { Assert-Sl7PersonalizationLayout -Layout $layout -CustomizerVersion '0.2.1' } | Should -Throw
    }

    It 'rejects an unsafe release-part name' {
        $layout = New-Sl7TestLayout
        $layout.base_iso.parts[0].name = '../base.part-000'
        { Assert-Sl7PersonalizationLayout -Layout $layout -CustomizerVersion '0.2.1' } | Should -Throw
    }
}

Describe 'UAC handoff' {
    It 'preserves quoted paths and the integrity hash' {
        $hash = 'a' * 64
        $arguments = @(New-Sl7ElevationArguments -ScriptPath 'C:\Project With Spaces\New-FedoraSl7Iso.ps1' -OptionsFile 'C:\Temp Path\options.json' -OptionsSha256 $hash)
        $arguments | Should -Contain '"C:\Project With Spaces\New-FedoraSl7Iso.ps1"'
        $arguments | Should -Contain '"C:\Temp Path\options.json"'
        $arguments[-1] | Should -Be $hash
    }

    It 'reports a cancelled UAC prompt with a clear English error' {
        Mock -ModuleName FedoraSl7Remix Start-Process {
            $nativeError = [ComponentModel.Win32Exception]::new(1223)
            throw [InvalidOperationException]::new('Start-Process failed', $nativeError)
        }
        { Start-Sl7ElevatedPowerShell -ArgumentList @('-NoProfile') } | Should -Throw '*cancelled by the user*'
    }

    It 'round-trips every elevation parameter and deletes the handoff' {
        $handoff = Join-Path $TestDrive 'options with spaces.json'
        $hash = New-Sl7ElevationHandoff -Path $handoff -Release 'v0.2.1' -FirmwareSource 'Windows' `
            -MsiPath 'C:\Fixture Path\firmware.msi' -OutputDirectory 'C:\Fixture User\Cloud Downloads' `
            -Model 'Romulus15' -KeepCache $true -LayoutPath 'C:\Fixture Path\layout.json'
        $saved = Read-Sl7ElevationHandoff -Path $handoff -ExpectedSha256 $hash
        $saved.Release | Should -Be 'v0.2.1'
        $saved.FirmwareSource | Should -Be 'Windows'
        $saved.MsiPath | Should -Be 'C:\Fixture Path\firmware.msi'
        $saved.OutputDirectory | Should -Be 'C:\Fixture User\Cloud Downloads'
        $saved.Model | Should -Be 'Romulus15'
        $saved.KeepCache | Should -BeTrue
        $saved.LayoutPath | Should -Be 'C:\Fixture Path\layout.json'
        Test-Path -LiteralPath $handoff | Should -BeFalse
    }

    It 'rejects and deletes a tampered elevation handoff' {
        $handoff = Join-Path $TestDrive 'tampered-options.json'
        $hash = New-Sl7ElevationHandoff -Path $handoff -Release 'latest' -FirmwareSource 'Auto' `
            -OutputDirectory 'C:\Fixture User\Downloads' -Model 'Auto' -KeepCache $false
        Add-Content -LiteralPath $handoff -Value 'tampered'
        { Read-Sl7ElevationHandoff -Path $handoff -ExpectedSha256 $hash } | Should -Throw '*integrity verification*'
        Test-Path -LiteralPath $handoff | Should -BeFalse
    }
}

Describe 'Downloads known folder' {
    It 'expands the interactive user registry value' {
        $previous = $env:SL7_TEST_PROFILE
        try {
            $env:SL7_TEST_PROFILE = 'C:\Users\Surface Owner'
            Get-Sl7DownloadsPath -RegistryValue '%SL7_TEST_PROFILE%\Cloud Downloads' | Should -Be 'C:\Users\Surface Owner\Cloud Downloads'
        }
        finally { $env:SL7_TEST_PROFILE = $previous }
    }

    It 'uses the user profile fallback' {
        Get-Sl7DownloadsPath -UserProfile 'C:\Users\Surface Owner' | Should -Be 'C:\Users\Surface Owner\Downloads'
    }
}

Describe 'Surface hardware mapping' {
    It 'maps SKU 2036 to Romulus13' {
        $system = [pscustomobject]@{ SystemSKUNumber = 'Surface_Laptop_7th_Edition_2036'; Model = 'Surface' }
        $product = [pscustomobject]@{ Name = ''; Version = '' }
        $result = Get-Sl7Hardware -ComputerSystem $system -ComputerSystemProduct $product
        $result.Model | Should -Be 'Romulus13'
        $result.Dtb | Should -Be '/boot/dtb/fedora-sl7-remix/romulus13.dtb'
    }

    It 'maps SKU 2037 to Romulus15' {
        $system = [pscustomobject]@{ SystemSKUNumber = 'Surface Laptop, 7th Edition 2037'; Model = 'Surface' }
        $product = [pscustomobject]@{ Name = ''; Version = '' }
        (Get-Sl7Hardware -ComputerSystem $system -ComputerSystemProduct $product).Model | Should -Be 'Romulus15'
    }

    It 'maps the business SKU 2037 to Romulus15' {
        $system = [pscustomobject]@{ SystemSKUNumber = 'Surface_Laptop_7th_Edition_For_Business_2037'; Model = 'Surface' }
        $product = [pscustomobject]@{ Name = ''; Version = '' }
        $result = Get-Sl7Hardware -ComputerSystem $system -ComputerSystemProduct $product
        $result.Sku | Should -Be 'Surface_Laptop_7th_Edition_2037'
        $result.Model | Should -Be 'Romulus15'
    }

    It 'rejects an unsupported system before download' {
        $system = [pscustomobject]@{ SystemSKUNumber = 'Unsupported_Device'; Model = 'Surface Pro' }
        $product = [pscustomobject]@{ Name = ''; Version = '' }
        { Get-Sl7Hardware -ComputerSystem $system -ComputerSystemProduct $product } | Should -Throw
    }

    It 'does not let a manual DTB override bypass the supported-SKU check' {
        $system = [pscustomobject]@{ SystemSKUNumber = 'Surface_Laptop_7th_Edition_2038_Intel'; Model = 'Surface' }
        $product = [pscustomobject]@{ Name = ''; Version = '' }
        { Get-Sl7Hardware -Model Romulus15 -ComputerSystem $system -ComputerSystemProduct $product } | Should -Throw
    }

    It 'rejects a supported SKU prefix with an Intel suffix' {
        $system = [pscustomobject]@{ SystemSKUNumber = 'Surface_Laptop_7th_Edition_2037_Intel'; Model = 'Surface' }
        $product = [pscustomobject]@{ Name = ''; Version = '' }
        { Get-Sl7Hardware -ComputerSystem $system -ComputerSystemProduct $product } | Should -Throw
    }

    It 'allows the alternate DTB only on a supported SL7 SKU' {
        $system = [pscustomobject]@{ SystemSKUNumber = 'Surface_Laptop_7th_Edition_2037'; Model = 'Surface' }
        $product = [pscustomobject]@{ Name = ''; Version = '' }
        $result = Get-Sl7Hardware -Model Romulus13 -ComputerSystem $system -ComputerSystemProduct $product
        $result.Sku | Should -Be 'Surface_Laptop_7th_Edition_2037'
        $result.Model | Should -Be 'Romulus13'
    }
}

Describe 'Model selector' {
    It 'creates an exact fixed-size selector without identifiers' {
        $hardware = [pscustomobject]@{
            Model = 'Romulus15'; DisplayInches = '15'; Dtb = '/boot/dtb/fedora-sl7-remix/romulus15.dtb'
        }
        $selector = New-Sl7ModelSelector -Hardware $hardware -Length 4096
        $selector.Length | Should -Be 4096
        [Text.Encoding]::ASCII.GetString($selector) | Should -Match 'sl7_personalized="1"'
        [Text.Encoding]::ASCII.GetString($selector) | Should -Not -Match 'serial|MAC'
    }
}

Describe 'newc firmware archive' {
    It 'includes the early GPU firmware and all private payload paths' {
        $fixture = Join-Path $TestDrive 'firmware'
        New-Item -ItemType Directory -Path $fixture | Out-Null
        $files = @{}
        foreach ($relative in Get-Sl7RequiredFirmware) {
            $path = Join-Path $fixture (Split-Path -Leaf $relative)
            [IO.File]::WriteAllText($path, "fixture-$relative")
            $files[$relative] = $path
        }
        $manifest = Join-Path $TestDrive 'manifest.json'
        [IO.File]::WriteAllText($manifest, '{"schema":1}')
        $archive = Join-Path $TestDrive 'personalization.cpio'
        New-Sl7PersonalizationCpio -FirmwareFiles $files -ManifestPath $manifest -OutputPath $archive | Out-Null
        $bytes = [IO.File]::ReadAllBytes($archive)
        $text = [Text.Encoding]::ASCII.GetString($bytes)
        $text | Should -Match 'usr/lib/firmware/updates/qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn'
        $text | Should -Match 'sl7-personalization/firmware/qcom/x1e80100/microsoft/Romulus/qccdsp8380.mbn'
        $text | Should -Match 'TRAILER!!!'
    }
}

Describe 'fixed ISO slots' {
    It 'rejects a placeholder hash mismatch' {
        $iso = Join-Path $TestDrive 'bad-placeholder.iso'
        [IO.File]::WriteAllBytes($iso, (New-Object byte[] 8192))
        $slot = [pscustomobject]@{ path = '/slot'; offset = 1024; length = 4096; placeholder_sha256 = ('f' * 64) }
        { Set-Sl7IsoSlot -IsoPath $iso -Slot $slot -Bytes ([byte[]](1, 2, 3)) } | Should -Throw
    }

    It 'patches and zero-pads an exact verified slot' {
        $iso = Join-Path $TestDrive 'slot.iso'
        [IO.File]::WriteAllBytes($iso, (New-Object byte[] 8192))
        $stream = [IO.File]::OpenRead($iso)
        try { $placeholder = Get-Sl7SegmentSha256 $stream 1024 4096 } finally { $stream.Dispose() }
        $slot = [pscustomobject]@{ path = '/slot'; offset = 1024; length = 4096; placeholder_sha256 = $placeholder }
        Set-Sl7IsoSlot -IsoPath $iso -Slot $slot -Bytes ([byte[]](1, 2, 3))
        $result = [IO.File]::ReadAllBytes($iso)
        $result[1024] | Should -Be 1
        $result[1027] | Should -Be 0
        $result.Length | Should -Be 8192
    }

    It 'rejects data larger than the reserved extent' {
        $iso = Join-Path $TestDrive 'overflow.iso'
        [IO.File]::WriteAllBytes($iso, (New-Object byte[] 32))
        $stream = [IO.File]::OpenRead($iso)
        try { $placeholder = Get-Sl7SegmentSha256 $stream 0 16 } finally { $stream.Dispose() }
        $slot = [pscustomobject]@{ path = '/slot'; offset = 0; length = 16; placeholder_sha256 = $placeholder }
        { Set-Sl7IsoSlot -IsoPath $iso -Slot $slot -Bytes (New-Object byte[] 17) } | Should -Throw
    }
}

Describe 'verified downloads' {
    It 'atomically promotes a complete resumable partial without network access' {
        $destination = Join-Path $TestDrive 'release.part'
        $partial = "$destination.partial"
        [IO.File]::WriteAllText($partial, 'complete-synthetic-part')
        $hash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
        Receive-Sl7File -Uri 'https://invalid.example.test/unused' -Destination $destination -Sha256 $hash | Should -Be $destination
        Test-Path -LiteralPath $destination | Should -BeTrue
        Test-Path -LiteralPath $partial | Should -BeFalse
        Get-Sl7Sha256 $destination | Should -Be $hash
    }

    It 'reassembles ordered verified release parts' {
        $partOne = Join-Path $TestDrive 'part-000.fixture'
        $partTwo = Join-Path $TestDrive 'part-001.fixture'
        [IO.File]::WriteAllText($partOne, 'first-')
        [IO.File]::WriteAllText($partTwo, 'second')
        $expectedIso = Join-Path $TestDrive 'expected.iso'
        [IO.File]::WriteAllText($expectedIso, 'first-second')
        $layout = [pscustomobject]@{
            base_iso = [pscustomobject]@{
                sha256 = Get-Sl7Sha256 $expectedIso
                parts = @(
                    [pscustomobject]@{ name = 'part-000'; sha256 = Get-Sl7Sha256 $partOne; size = (Get-Item $partOne).Length },
                    [pscustomobject]@{ name = 'part-001'; sha256 = Get-Sl7Sha256 $partTwo; size = (Get-Item $partTwo).Length }
                )
            }
        }
        $release = [pscustomobject]@{ tag_name = 'v-test'; assets = @(
            [pscustomobject]@{ name = 'part-000'; browser_download_url = $partOne },
            [pscustomobject]@{ name = 'part-001'; browser_download_url = $partTwo }
        ) }
        $cache = Join-Path $TestDrive 'part-cache'
        New-Item -ItemType Directory -Path $cache | Out-Null
        Mock -ModuleName FedoraSl7Remix Receive-Sl7File {
            param($Uri, $Destination, $Sha256)
            Copy-Item -LiteralPath $Uri -Destination $Destination
            if ((Get-Sl7Sha256 $Destination) -ne $Sha256) { throw 'fixture checksum mismatch' }
        }
        $joined = Join-Path $TestDrive 'joined.iso'
        Join-Sl7BaseIso -Release $release -Layout $layout -CacheDirectory $cache -OutputPath $joined
        Get-Sl7Sha256 $joined | Should -Be $layout.base_iso.sha256
        Should -Invoke -ModuleName FedoraSl7Remix Receive-Sl7File -Times 2 -Exactly
    }

    It 'atomically replaces an existing output only after hash verification' {
        $partial = Join-Path $TestDrive 'private.iso.partial'
        $final = Join-Path $TestDrive 'private.iso'
        [IO.File]::WriteAllText($partial, 'verified-new-image')
        [IO.File]::WriteAllText($final, 'obsolete-image')
        $hash = Get-Sl7Sha256 $partial
        Publish-Sl7AtomicIso -PartialPath $partial -FinalPath $final -ExpectedSha256 $hash | Should -Be $final
        Test-Path -LiteralPath $partial | Should -BeFalse
        Get-Sl7Sha256 $final | Should -Be $hash
    }

    It 'does not publish an ISO when the expected hash is wrong' {
        $partial = Join-Path $TestDrive 'wrong.iso.partial'
        $final = Join-Path $TestDrive 'wrong.iso'
        [IO.File]::WriteAllText($partial, 'untrusted-image')
        { Publish-Sl7AtomicIso -PartialPath $partial -FinalPath $final -ExpectedSha256 ('0' * 64) } | Should -Throw
        Test-Path -LiteralPath $partial | Should -BeTrue
        Test-Path -LiteralPath $final | Should -BeFalse
    }

    It 'retries HTTPS exactly three times before failing' {
        Mock -ModuleName FedoraSl7Remix New-Sl7HttpRequest { throw 'synthetic network failure' }
        Mock -ModuleName FedoraSl7Remix Start-Sleep {}
        { Receive-Sl7HttpsPartial -Uri 'https://invalid.example.test/part' -PartialPath (Join-Path $TestDrive 'retry.partial') } | Should -Throw
        Should -Invoke -ModuleName FedoraSl7Remix New-Sl7HttpRequest -Times 3 -Exactly
        Should -Invoke -ModuleName FedoraSl7Remix Start-Sleep -Times 2 -Exactly
    }
}

Describe 'firmware completeness and redaction' {
    It 'reports every missing required file' {
        $result = Get-Sl7FirmwareFromTree -Root $TestDrive
        $result.Complete | Should -BeFalse
        $result.Missing.Count | Should -Be 10
    }

    It 'accepts only a valid Microsoft signature decision' {
        $microsoft = [pscustomobject]@{
            Status = 'Valid'
            SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Windows Hardware Compatibility Publisher' }
        }
        $other = [pscustomobject]@{
            Status = 'Valid'
            SignerCertificate = [pscustomobject]@{ Subject = 'CN=Unrelated Vendor' }
        }
        Test-Sl7MicrosoftSignature -FilePath 'unused-fixture' -Signature $microsoft | Should -BeTrue
        Test-Sl7MicrosoftSignature -FilePath 'unused-fixture' -Signature $other | Should -BeFalse
        $other.SignerCertificate.Subject = 'CN=NotMicrosoft Firmware Publisher'
        Test-Sl7MicrosoftSignature -FilePath 'unused-fixture' -Signature $other | Should -BeFalse
        $microsoft.Status = 'HashMismatch'
        Test-Sl7MicrosoftSignature -FilePath 'unused-fixture' -Signature $microsoft | Should -BeFalse
    }

    It 'uses the Windows catalog-aware signature result for a package file' {
        $package = Join-Path $TestDrive 'signed-package'
        New-Item -ItemType Directory -Force -Path $package | Out-Null
        $firmware = Join-Path $package 'firmware.mbn'
        [IO.File]::WriteAllText($firmware, 'synthetic-firmware')
        Mock -ModuleName FedoraSl7Remix Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status = 'Valid'
                SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Windows Hardware Compatibility Publisher' }
            }
        }
        Test-Sl7MicrosoftCatalog -Directory $package -FilePath $firmware | Should -BeTrue
        Should -Invoke -ModuleName FedoraSl7Remix Get-AuthenticodeSignature -Times 1 -Exactly
    }

    It 'rejects a catalog-aware signature check outside the package root' {
        $package = Join-Path $TestDrive 'signed-package'
        New-Item -ItemType Directory -Force -Path $package | Out-Null
        $outside = Join-Path $TestDrive 'outside.mbn'
        [IO.File]::WriteAllText($outside, 'synthetic-firmware')
        Mock -ModuleName FedoraSl7Remix Get-AuthenticodeSignature { throw 'must not be called' }
        Test-Sl7MicrosoftCatalog -Directory $package -FilePath $outside | Should -BeFalse
        Should -Invoke -ModuleName FedoraSl7Remix Get-AuthenticodeSignature -Times 0 -Exactly
    }

    It 'rejects an MSI before extraction when its locked hash differs' {
        $msi = Join-Path $TestDrive 'synthetic-invalid.msi'
        [IO.File]::WriteAllText($msi, 'not-an-msi')
        { Expand-Sl7MicrosoftMsi -MsiPath $msi -Destination (Join-Path $TestDrive 'msi-out') -ExpectedSha256 ('0' * 64) } | Should -Throw
        Test-Path -LiteralPath (Join-Path $TestDrive 'msi-out') | Should -BeFalse
    }

    It 'uses native MSI extraction after the locked hash succeeds' {
        $msi = Join-Path $TestDrive 'synthetic-valid.msi'
        [IO.File]::WriteAllText($msi, 'synthetic-msi-fixture')
        $expected = Get-Sl7Sha256 $msi
        $complete = [pscustomobject]@{ Complete = $true; Files = @{}; Missing = @() }
        Mock -ModuleName FedoraSl7Remix Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock -ModuleName FedoraSl7Remix Get-Sl7FirmwareFromTree { $complete }
        $result = Expand-Sl7MicrosoftMsi -MsiPath $msi -Destination (Join-Path $TestDrive 'msi-valid-out') -ExpectedSha256 $expected
        $result.Complete | Should -BeTrue
        Should -Invoke -ModuleName FedoraSl7Remix Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'msiexec.exe' }
        Should -Invoke -ModuleName FedoraSl7Remix Get-Sl7FirmwareFromTree -Times 1 -Exactly
    }

    It 'extracts active DriverStore package roots from PnPUtil XML' {
        [xml]$inventory = @'
<DriverInventory>
  <Driver><File>C:\Windows\System32\DriverStore\FileRepository\qcdx8380.inf_arm64_deadbeef\qcdxkmsuc8380.mbn</File></Driver>
  <Driver><File>C:\Windows\System32\DriverStore\FileRepository\qcadsp8380.inf_arm64_cafebabe\qcadsp8380.mbn</File></Driver>
  <Driver><Devices><Count>0</Count></Devices><File>C:\Windows\System32\DriverStore\FileRepository\unused.inf_arm64_0000\unused.sys</File></Driver>
</DriverInventory>
'@
        $result = @(Get-Sl7PnpPackageDirectories -Inventory $inventory -DriverStore 'C:\Windows\System32\DriverStore\FileRepository')
        $result.Count | Should -Be 2
        $result | Should -Contain 'C:\Windows\System32\DriverStore\FileRepository\qcdx8380.inf_arm64_deadbeef'
        $result | Should -Not -Contain 'C:\Windows\System32\DriverStore\FileRepository\unused.inf_arm64_0000'
    }

    It 'resolves active PnPUtil INF packages and excludes inactive packages' {
        $driverStore = Join-Path $TestDrive 'FileRepository'
        $windowsInf = Join-Path $TestDrive 'INF'
        $activeRoot = Join-Path $driverStore 'qcdx8380.inf_arm64_deadbeef'
        $inactiveRoot = Join-Path $driverStore 'unused.inf_arm64_cafebabe'
        New-Item -ItemType Directory -Force -Path $activeRoot, $inactiveRoot, $windowsInf | Out-Null
        [IO.File]::WriteAllText((Join-Path $windowsInf 'oem42.inf'), 'active-package')
        [IO.File]::WriteAllText((Join-Path $activeRoot 'qcdx8380.inf'), 'active-package')
        [IO.File]::WriteAllText((Join-Path $windowsInf 'oem43.inf'), 'inactive-package')
        [IO.File]::WriteAllText((Join-Path $inactiveRoot 'unused.inf'), 'inactive-package')
        [xml]$inventory = @'
<PnpUtil>
  <Driver DriverName="oem42.inf">
    <OriginalName>qcdx8380.inf</OriginalName>
    <Devices><Device><Status>Started</Status></Device></Devices>
    <Files><File Name="qcdxkmsuc8380.mbn" /></Files>
  </Driver>
  <Driver DriverName="oem43.inf">
    <OriginalName>unused.inf</OriginalName>
    <Files><File Name="unused.sys" /></Files>
  </Driver>
</PnpUtil>
'@
        $result = @(Get-Sl7PnpPackageDirectories -Inventory $inventory -DriverStore $driverStore -WindowsInf $windowsInf)
        $result | Should -Contain $activeRoot
        $result | Should -Not -Contain $inactiveRoot
        $result.Count | Should -Be 1
    }
}
