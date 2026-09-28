#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract tests for lib/gpu-detection.ps1.

.DESCRIPTION
    Validates the vendor-detection + adapter-resolution surface that
    every 6 gpu/* script depends on. Static-only. PnP probing is
    outside this file.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:ExpectedPublic = @(
        @{ Name = 'Get-GpuVendor' }
        @{ Name = 'Get-GpuAdapterRegistryPath' }
        @{ Name = 'Test-IntelArcDevice' }
        @{ Name = 'Get-PrimaryGpu' }
        @{ Name = 'Test-ReBarEnabled' }
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:Target = Get-ToolkitScriptPath 'lib/gpu-detection.ps1'
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Target, [ref]$null, [ref]$null
    )
    $script:Functions = $script:Ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)
    $script:FunctionNames = @($script:Functions | ForEach-Object Name)
    $script:Content = Get-Content -Raw -LiteralPath $script:Target
}

Describe 'lib/gpu-detection.ps1 — surface contract' {

    Context 'File health' {
        It 'parses without errors' {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:Target, [ref]$tokens, [ref]$errors
            )
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'Public surface' {
        It 'exports <Name>' -ForEach $script:ExpectedPublic {
            $script:FunctionNames | Should -Contain $Name
        }
    }

    Context 'Vendor PCI IDs (CODEX audit fix)' {
        It 'matches NVIDIA VEN_10DE' {
            # Pre-CODEX-fix: vendor filter accepted every Display device.
            # Post-fix: must match by PCI vendor ID. Regression test.
            $script:Content | Should -Match 'VEN_10DE'
        }

        It 'matches AMD VEN_1002' {
            $script:Content | Should -Match 'VEN_1002'
        }

        It 'matches Intel VEN_8086' {
            $script:Content | Should -Match 'VEN_8086'
        }
    }

    Context 'PnP filter respects status/presence' {
        It 'uses -PresentOnly to skip ghost devices' {
            # Per CODEX audit fix #1 — the filter was missing -PresentOnly
            # before, accepting any device ever installed.
            $script:Content | Should -Match '-PresentOnly'
        }

        It 'requires Status -eq "OK"' {
            # Same audit fix — restrict to currently-healthy adapters.
            $script:Content | Should -Match 'Status\s+-eq\s+"OK"'
        }
    }
}

Describe 'lib/gpu-detection.ps1 — behavioral' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '..' '..' 'lib' 'gpu-detection.ps1')
        # Get-PnpDevice ships in the Windows-only PnpDevice module. On
        # dev macOS / Linux it doesn't exist, and Pester's Mock can only
        # intercept commands already in scope. Define a thin stub so the
        # Mock blocks below have something to override — the stub never
        # runs unless an unmocked path slips through (which would fail
        # loudly, the desired behavior).
        if (-not (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
            function Get-PnpDevice {
                param([string]$Class, [switch]$PresentOnly)
                throw 'Get-PnpDevice stub: every behavioral test must Mock this'
            }
        }
    }

    Context 'Test-IntelArcDevice — pure regex on DeviceId' {
        # Pure function: no PnP, no registry, no filesystem. Easiest
        # branch in the file to fully cover.

        It 'returns $false on null / empty / whitespace input' {
            Test-IntelArcDevice -DeviceId $null    | Should -BeFalse
            Test-IntelArcDevice -DeviceId ''       | Should -BeFalse
            Test-IntelArcDevice -DeviceId '   '    | Should -BeFalse
        }

        It 'recognizes Alchemist (Arc A-series) IDs in the 56[9A]xx range' {
            # A770: 56A0, A750: 56A1, A580: 56A5, A380: 56A5/56A6
            Test-IntelArcDevice -DeviceId '56A0' | Should -BeTrue
            Test-IntelArcDevice -DeviceId '56AF' | Should -BeTrue
            Test-IntelArcDevice -DeviceId '5690' | Should -BeTrue
            Test-IntelArcDevice -DeviceId '569F' | Should -BeTrue
        }

        It 'recognizes Battlemage (Arc B-series) IDs in the E2xx range' {
            # B580: E20B, B570: E20C/D — regex covers E20x..E2Fx
            Test-IntelArcDevice -DeviceId 'E200' | Should -BeTrue
            Test-IntelArcDevice -DeviceId 'E2FF' | Should -BeTrue
        }

        It 'rejects integrated graphics IDs and unrelated ranges' {
            # 9A40 = Tiger Lake iGPU (typical integrated), 46A8 = Alder Lake iGPU
            Test-IntelArcDevice -DeviceId '9A40' | Should -BeFalse
            Test-IntelArcDevice -DeviceId '46A8' | Should -BeFalse
            Test-IntelArcDevice -DeviceId '5680' | Should -BeFalse  # too-low 56xx
        }

        It 'rejects malformed IDs (non-hex / wrong length)' {
            Test-IntelArcDevice -DeviceId 'ZZZZ'  | Should -BeFalse
            Test-IntelArcDevice -DeviceId '56A'   | Should -BeFalse  # 3 chars
            Test-IntelArcDevice -DeviceId '56A00' | Should -BeFalse  # 5 chars
        }
    }

    Context 'Test-ReBarEnabled — null guard + property fallback' {

        It 'returns $null when path is null/empty/whitespace (no probe attempted)' {
            Test-ReBarEnabled -AdapterRegistryPath $null  | Should -BeNullOrEmpty
            Test-ReBarEnabled -AdapterRegistryPath ''     | Should -BeNullOrEmpty
            Test-ReBarEnabled -AdapterRegistryPath '   '  | Should -BeNullOrEmpty
        }

        It 'returns $null when registry path has no ReBAR-related property' {
            # Get-ItemProperty mocked to return an object with no
            # KMD_EnableLargeBar / LargeMemoryRange members at all.
            Mock Get-ItemProperty { [PSCustomObject]@{ Foo = 'bar' } }
            Test-ReBarEnabled -AdapterRegistryPath 'HKLM:\fake\path' | Should -BeNullOrEmpty
        }
    }

    Context 'Get-GpuVendor — PnP probe with mocked Get-PnpDevice' {

        It 'returns empty array when no Display devices match' {
            Mock Get-PnpDevice { @() }
            $result = Get-GpuVendor
            # Empty array result; assert via Count rather than -BeOfType
            # because Pester pipeline unwraps single-element arrays.
            (, $result).Count | Should -Be 1
            $result.Count | Should -Be 0
        }

        It 'classifies NVIDIA / AMD / Intel devices by PCI VEN_ id' {
            Mock Get-PnpDevice {
                @(
                    [PSCustomObject]@{
                        FriendlyName = 'NVIDIA GeForce RTX 5090'
                        Status = 'OK'
                        InstanceId = 'PCI\VEN_10DE&DEV_2B85&SUBSYS_0001'
                    },
                    [PSCustomObject]@{
                        FriendlyName = 'AMD Radeon RX 9070 XT'
                        Status = 'OK'
                        InstanceId = 'PCI\VEN_1002&DEV_7400&SUBSYS_0001'
                    },
                    [PSCustomObject]@{
                        FriendlyName = 'Intel Arc B580'
                        Status = 'OK'
                        InstanceId = 'PCI\VEN_8086&DEV_E20B&SUBSYS_0001'
                    }
                )
            }
            # Mock Get-GpuAdapterRegistryPath so the function doesn't try
            # to read the live Class GUID tree.
            Mock Get-GpuAdapterRegistryPath { 'HKLM:\fake' }
            $result = Get-GpuVendor
            $result.Count | Should -Be 3
            ($result | Where-Object Vendor -EQ 'nvidia').DeviceId | Should -Be '2B85'
            ($result | Where-Object Vendor -EQ 'amd').DeviceId    | Should -Be '7400'
            $intel = $result | Where-Object Vendor -EQ 'intel'
            $intel.DeviceId | Should -Be 'E20B'
            $intel.IsDiscrete | Should -BeTrue   # Arc B580 → discrete
        }

        It 'flags integrated Intel as non-discrete (IsDiscrete = false)' {
            Mock Get-PnpDevice {
                @(
                    [PSCustomObject]@{
                        FriendlyName = 'Intel UHD Graphics'
                        Status = 'OK'
                        InstanceId = 'PCI\VEN_8086&DEV_9A40&SUBSYS_0001'
                    }
                )
            }
            Mock Get-GpuAdapterRegistryPath { 'HKLM:\fake' }
            $result = Get-GpuVendor
            $result.Count | Should -Be 1
            $result[0].Vendor | Should -Be 'intel'
            $result[0].IsDiscrete | Should -BeFalse
        }
    }

    Context 'Get-PrimaryGpu — preference: discrete > integrated, NVIDIA/AMD > Intel' {

        It 'returns $null when no GPU vendors detected' {
            Mock Get-GpuVendor { @() }
            Get-PrimaryGpu | Should -BeNullOrEmpty
        }

        It 'prefers a discrete NVIDIA over discrete Intel Arc' {
            Mock Get-GpuVendor {
                @(
                    [PSCustomObject]@{ Vendor = 'intel'; IsDiscrete = $true; FriendlyName = 'Arc B580' },
                    [PSCustomObject]@{ Vendor = 'nvidia'; IsDiscrete = $true; FriendlyName = 'RTX 5090' }
                )
            }
            (Get-PrimaryGpu).Vendor | Should -Be 'nvidia'
        }

        It 'falls back to integrated when no discrete present' {
            Mock Get-GpuVendor {
                @(
                    [PSCustomObject]@{ Vendor = 'intel'; IsDiscrete = $false; FriendlyName = 'UHD Graphics' }
                )
            }
            (Get-PrimaryGpu).Vendor | Should -Be 'intel'
        }
    }
}
