#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Behavioral tests for lib/gpu-download.ps1 — per-vendor URL
    resolvers and the download + verify chain.

.DESCRIPTION
    Exercises every function via mocked Invoke-WebRequest +
    overridden $script:GpuDriverStageRoot pointing at a per-test
    temp dir. No real network traffic, no real file writes outside
    the temp scope.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    . (Join-Path $PSScriptRoot '..' '..' 'lib' 'download-helpers.ps1')
    . (Join-Path $PSScriptRoot '..' '..' 'lib' 'gpu-download.ps1')

    # Manifest shape that matches the real versions.json gpu subtree:
    # vendor → { version, url, sha256, components, driverOnlyInf }
    $script:SampleManifest = [PSCustomObject]@{
        nvidia = [PSCustomObject]@{
            version = '572.83'
            url = 'https://example.com/nv-572.83.exe'
            sha256 = ('a' * 64)
            components = @('Display.Driver', 'HDAudio')
        }
        amd = [PSCustomObject]@{
            version = '25.3.1'
            url = 'https://example.com/amd-25.3.1.exe'
            sha256 = ('b' * 64)
        }
        intel = [PSCustomObject]@{
            version = '32.0.101.6789'
            url = 'https://example.com/intel-101.zip'
            sha256 = ('c' * 64)
            driverOnlyInf = $true
        }
    }
}

Describe 'lib/gpu-download.ps1' {

    Context 'Cross-platform stage-root fallback (loads clean on macOS)' {
        It 'declares a non-empty $script:GpuDriverStageRoot under a GamingOpt/Drivers path' {
            # Regression for the dev-macOS Join-Path null bug
            # surfaced 2026-05-24 session 6. Mirrors the same pattern
            # already applied to lib/version-manifest.ps1 + toolkit-state.
            $script:GpuDriverStageRoot | Should -Not -BeNullOrEmpty
            $script:GpuDriverStageRoot | Should -Match 'GamingOpt'
            $script:GpuDriverStageRoot | Should -Match 'Drivers'
        }
    }

    Context 'Resolve-NvidiaDriverUrl — pinned vs AutoDetect branches' {

        It 'returns pinned-manifest values when AutoDetect is off' {
            $r = Resolve-NvidiaDriverUrl -Manifest $script:SampleManifest
            $r.Version | Should -Be '572.83'
            $r.Url | Should -Be 'https://example.com/nv-572.83.exe'
            $r.ExpectedHash | Should -Be ('a' * 64)
            $r.AutoDetected | Should -BeFalse
        }

        It 'queries the NVIDIA API when -AutoDetect + DeviceId provided (mocked)' {
            Mock Invoke-WebRequest {
                $jsonText = @'
{ "IDS": [ { "downloadInfo": { "Version": "576.10", "DownloadURL": "https://api.example/nv-576.10.exe" } } ] }
'@
                [PSCustomObject]@{ Content = $jsonText }
            }
            $r = Resolve-NvidiaDriverUrl -Manifest $script:SampleManifest `
                -DeviceId '2B85' -AutoDetect
            $r.Version | Should -Be '576.10'
            $r.Url | Should -Be 'https://api.example/nv-576.10.exe'
            $r.AutoDetected | Should -BeTrue
            $r.ExpectedSignerCN | Should -Be 'NVIDIA Corporation'
        }

        It 'falls back to pinned values when the AutoDetect API call throws' {
            Mock Invoke-WebRequest { throw 'no network' }
            $r = Resolve-NvidiaDriverUrl -Manifest $script:SampleManifest `
                -DeviceId '2B85' -AutoDetect 6>$null
            # Falls through to the pinned-manifest branch
            $r.Version | Should -Be '572.83'
            $r.AutoDetected | Should -BeFalse
        }
    }

    Context 'Resolve-AmdDriverUrl / Resolve-IntelDriverUrl — pure pickers' {

        It 'Resolve-AmdDriverUrl returns the amd subtree fields' {
            $r = Resolve-AmdDriverUrl -Manifest $script:SampleManifest
            $r.Version | Should -Be '25.3.1'
            $r.Url | Should -Be 'https://example.com/amd-25.3.1.exe'
            $r.ExpectedHash | Should -Be ('b' * 64)
            $r.AutoDetected | Should -BeFalse
        }

        It 'Resolve-IntelDriverUrl returns the intel subtree fields including DriverOnlyInf' {
            $r = Resolve-IntelDriverUrl -Manifest $script:SampleManifest
            $r.Version | Should -Be '32.0.101.6789'
            $r.Url | Should -Be 'https://example.com/intel-101.zip'
            $r.DriverOnlyInf | Should -BeTrue
        }
    }

    Context 'Get-GpuDriverInstaller — download + verify chain' {

        BeforeEach {
            # Per-test stage root so downloads land in a controlled spot
            # and tests don't see each other's leftovers.
            $script:OrigStageRoot = $script:GpuDriverStageRoot
            $script:TmpStage = Join-Path ([System.IO.Path]::GetTempPath()) ("gpudl-stage-" + [guid]::NewGuid())
            $script:GpuDriverStageRoot = $script:TmpStage
        }

        AfterEach {
            $script:GpuDriverStageRoot = $script:OrigStageRoot
            if ($script:TmpStage -and (Test-Path $script:TmpStage)) {
                Remove-Item -LiteralPath $script:TmpStage -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'rejects a placeholder hash (non-64-char-hex) and falls through to Authenticode-only' {
            # Get-FileFromWeb mocked to just create a non-empty file
            # (Invoke-WebRequest emulation without the real download).
            Mock Get-FileFromWeb {
                param([string]$Url, [string]$File)
                'fake-payload' * 200 | Set-Content -LiteralPath $File
            }
            Mock Test-FileAuthenticode { $true }
            $result = Get-GpuDriverInstaller -Vendor 'nvidia' -Url 'https://example.com/foo.exe' `
                -ExpectedHash 'NOT-A-VALID-HASH' -ExpectedSignerCN 'NVIDIA Corporation' 6>$null
            Test-Path $result | Should -BeTrue
        }

        It 'verifies and accepts a real-shape SHA-256 hash on successful match' {
            Mock Get-FileFromWeb {
                param([string]$Url, [string]$File)
                'fake-payload' * 200 | Set-Content -LiteralPath $File
            }
            Mock Test-FileSha256 { $true }
            $result = Get-GpuDriverInstaller -Vendor 'amd' -Url 'https://example.com/bar.exe' `
                -ExpectedHash ('d' * 64) 6>$null
            Test-Path $result | Should -BeTrue
        }

        It 'throws and cleans up the file when SHA-256 mismatches' {
            Mock Get-FileFromWeb {
                param([string]$Url, [string]$File)
                'corrupt-payload' * 200 | Set-Content -LiteralPath $File
            }
            Mock Test-FileSha256 { $false }
            { Get-GpuDriverInstaller -Vendor 'intel' -Url 'https://example.com/baz.exe' `
                    -ExpectedHash ('e' * 64) 6>$null } |
                Should -Throw '*hash mismatch*'
        }

        It 'throws and cleans up when Authenticode signer verification fails' {
            Mock Get-FileFromWeb {
                param([string]$Url, [string]$File)
                'fake-payload' * 200 | Set-Content -LiteralPath $File
            }
            Mock Test-FileAuthenticode { $false }
            { Get-GpuDriverInstaller -Vendor 'nvidia' -Url 'https://example.com/qux.exe' `
                    -ExpectedSignerCN 'Bogus, Inc.' 6>$null } |
                Should -Throw '*Authenticode verification failed*'
        }

        It 'skips re-download when the file is already staged and hash still matches' {
            Mock Get-FileFromWeb {
                param([string]$Url, [string]$File)
                # Should NOT be called in the cached path
                throw 'Get-FileFromWeb was called even though cache hit was expected'
            }
            Mock Test-FileSha256 { $true }
            # Pre-stage the file at the expected output path
            $vendorDir = Join-Path $script:GpuDriverStageRoot 'nvidia'
            New-Item -ItemType Directory -Path $vendorDir -Force | Out-Null
            $stagedPath = Join-Path $vendorDir 'pre-staged.exe'
            'stale-payload' | Set-Content -LiteralPath $stagedPath
            $result = Get-GpuDriverInstaller -Vendor 'nvidia' -Url 'https://example.com/pre-staged.exe' `
                -ExpectedHash ('f' * 64) 6>$null
            $result | Should -Be $stagedPath
        }
    }
}
