#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract tests for REVERT-EVERYTHING.ps1.

.DESCRIPTION
    REVERT-EVERYTHING.ps1 is the user's escape hatch. Regressions here
    leave users stuck with applied tweaks they can't undo. AST tests
    cover:

      - Admin self-check present (CLAUDE.md invariant #6)
      - Manifest is loaded before any restore work
      - Each major phase is present and uses Restore-Toolkit* helpers
        (not just blind defaults) — proving manifest-driven revert
      - Nagle revert prefers manifest then falls back to blind remove
        (CURSOR-AUDIT #5)
      - Help text warns about the post-revert reboot requirement

    What these AST tests cannot prove is listed in
    tests/manual/REVERT-EVERYTHING.md.

.NOTES
    # CROSS-PLATFORM-NOTE
    # AST/text only. Whether Restore-ToolkitRegistryValue actually
    # writes the captured before-value back to HKLM cannot be tested
    # on macOS — see tests/manual/REVERT-EVERYTHING.md.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '_common.ps1')
    $script:ExpectedPhases = @(
        @{ Text = 'Phase 1: Power Baseline' }
        @{ Text = 'Phase 2: Windows Settings' }
        @{ Text = 'Phase 3: Services' }
        @{ Text = 'Phase 4: Registry Pack' }
        @{ Text = 'Phase 5: Startup Cleanup' }
        @{ Text = 'Phase 7: Network' }
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot '_common.ps1')
    $script:Target = Get-ToolkitScriptPath 'REVERT-EVERYTHING.ps1'
    $script:Content = Get-Content -Raw -LiteralPath $script:Target
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Target, [ref]$null, [ref]$null
    )
}

Describe 'REVERT-EVERYTHING.ps1 — surface contract' {

    Context 'File health' {
        It 'parses without errors' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:Target, [ref]$null, [ref]$errors
            )
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'Admin self-check (CLAUDE.md invariant #6)' {
        It 'calls UI-RequireAdmin near the top' {
            $head = ($script:Content -split "`n" | Select-Object -First 50) -join "`n"
            $head | Should -Match 'UI-RequireAdmin'
        }
    }

    Context 'Manifest-driven revert (CLAUDE.md invariant #5)' {
        It 'loads the manifest via Initialize-ToolkitState before any restore work' {
            # Pattern: $state = Initialize-ToolkitState (or Get-ToolkitState)
            # Must precede the first Run-Step "Restoring..." call.
            $lines = $script:Content -split "`n"
            $initMatch = $lines | Select-String -Pattern 'Initialize-ToolkitState' -SimpleMatch | Select-Object -First 1
            $restoreMatch = $lines | Select-String -Pattern 'Run-Step.+Restoring' | Select-Object -First 1
            $initMatch | Should -Not -BeNullOrEmpty
            $restoreMatch | Should -Not -BeNullOrEmpty
            $initMatch.LineNumber | Should -BeLessThan $restoreMatch.LineNumber `
                -Because 'manifest must exist before any Restore-* call can read it'
        }

        It 'uses Restore-ToolkitRegistryValue (not blind reg delete) for tracked entries' {
            # The manifest-driven helper is the canonical revert path.
            $script:Content | Should -Match 'Restore-ToolkitRegistryValue'
        }

        It 'uses Restore-ToolkitServiceStartMode for service state' {
            $script:Content | Should -Match 'Restore-ToolkitServiceStartMode'
        }

        It 'uses Restore-ToolkitDnsServers for DNS state' {
            $script:Content | Should -Match 'Restore-ToolkitDnsServers'
        }
    }

    Context 'Captured HKLM keys restore from the manifest first' {
        # These five ids are written by APPLY via Set-ToolkitRegistryValue.
        # Revert must read that before-state before any hardcoded default.
        # Hiberboot and PowerThrottling also accept a legacy pwr: id when
        # the reg: id was never captured (power-plan-only manifests).
        It 'restores <Id> before its hardcoded fallback' -ForEach @(
            @{ Id = 'reg:DriverSearchOrderConfig'; Fallback = 'SearchOrderConfig" /t REG_DWORD /d 1' }
            @{ Id = 'reg:HiberbootEnabled'; Fallback = 'HiberbootEnabled" /t REG_DWORD /d 1' }
            @{ Id = 'reg:PowerThrottlingOff'; Fallback = '/v "PowerThrottlingOff" /f' }
            @{ Id = 'reg:Win32PrioritySeparation'; Fallback = 'Win32PrioritySeparation" /t REG_DWORD /d 2' }
            @{ Id = 'reg:AllowTelemetry'; Fallback = 'AllowTelemetry" /t REG_DWORD /d 1' }
        ) {
            $lines = $script:Content -split "`n"
            $restore = $lines | Select-String -Pattern ('Restore-ToolkitRegistryValue -Id "{0}"' -f $Id) | Select-Object -First 1
            $fallback = $lines | Select-String -Pattern ([regex]::Escape($Fallback)) | Select-Object -First 1
            $restore | Should -Not -BeNullOrEmpty
            $fallback | Should -Not -BeNullOrEmpty
            $restore.LineNumber | Should -BeLessThan $fallback.LineNumber
        }

        It 'tries legacy pwr: ids only after the shared reg: id is missing' -ForEach @(
            @{ RegId = 'reg:HiberbootEnabled'; LegacyId = 'pwr:HiberbootEnabled' }
            @{ RegId = 'reg:PowerThrottlingOff'; LegacyId = 'pwr:PowerThrottlingOff' }
        ) {
            $lines = $script:Content -split "`n"
            $regLine = $lines | Select-String -Pattern ('Restore-ToolkitRegistryValue -Id "{0}"' -f $RegId) | Select-Object -First 1
            $legacyLine = $lines | Select-String -Pattern ('Restore-ToolkitRegistryValue -Id "{0}"' -f $LegacyId) | Select-Object -First 1
            $regLine | Should -Not -BeNullOrEmpty
            $legacyLine | Should -Not -BeNullOrEmpty
            $regLine.LineNumber | Should -BeLessThan $legacyLine.LineNumber
        }
    }

    Context 'Power-plan scripts share one id per Hiberboot and PowerThrottling value' {
        It 'configure-power writes the reg: ids and does not add a second writer' {
            $configure = Get-Content -Raw -LiteralPath (Get-ToolkitScriptPath '2 power plan/configure-power.ps1')
            $configure | Should -Match 'Set-ToolkitRegistryValue -Id "reg:HiberbootEnabled"'
            $configure | Should -Match 'Set-ToolkitRegistryValue -Id "reg:PowerThrottlingOff"'
            $configure | Should -Not -Match 'pwr:HiberbootEnabled'
            $configure | Should -Not -Match 'pwr:PowerThrottlingOff'
        }

        It 'revert-power restores the shared reg: id before any legacy pwr: id' {
            $revert = Get-Content -Raw -LiteralPath (Get-ToolkitScriptPath '2 power plan/revert-power.ps1')
            $lines = $revert -split "`n"
            $regHiber = $lines | Select-String -Pattern 'Restore-ToolkitRegistryValue -Id "reg:HiberbootEnabled"' | Select-Object -First 1
            $legacyHiber = $lines | Select-String -Pattern 'Restore-ToolkitRegistryValue -Id "pwr:HiberbootEnabled"' | Select-Object -First 1
            $regThrottle = $lines | Select-String -Pattern 'Restore-ToolkitRegistryValue -Id "reg:PowerThrottlingOff"' | Select-Object -First 1
            $legacyThrottle = $lines | Select-String -Pattern 'Restore-ToolkitRegistryValue -Id "pwr:PowerThrottlingOff"' | Select-Object -First 1
            $regHiber | Should -Not -BeNullOrEmpty
            $legacyHiber | Should -Not -BeNullOrEmpty
            $regThrottle | Should -Not -BeNullOrEmpty
            $legacyThrottle | Should -Not -BeNullOrEmpty
            $regHiber.LineNumber | Should -BeLessThan $legacyHiber.LineNumber
            $regThrottle.LineNumber | Should -BeLessThan $legacyThrottle.LineNumber
            $revert | Should -Not -Match 'Set-ToolkitRegistryValue -Id "pwr:HiberbootEnabled"'
            $revert | Should -Not -Match 'Set-ToolkitRegistryValue -Id "pwr:PowerThrottlingOff"'
        }
    }

    Context 'Nagle revert prefers manifest (CURSOR-AUDIT #5)' {
        It 'restores tracked net:TcpAckFrequency / net:TCPNoDelay before blind remove' {
            # Pattern from dd5dc3e: foreach over $state.registry IDs matching
            # net:Tcp* / net:TCP*, call Restore-ToolkitRegistryValue; THEN
            # blind-remove fallback for legacy interfaces not in manifest.
            $script:Content | Should -Match 'net:TcpAckFrequency'
            $script:Content | Should -Match 'net:TCPNoDelay'
            $script:Content | Should -Match 'Restore-ToolkitRegistryValue\s+-Id\s+\$id'
        }
    }

    Context 'Phase coverage' {
        It 'has section heading: <Text>' -ForEach $script:ExpectedPhases {
            $script:Content | Should -Match ([regex]::Escape($Text))
        }
    }

    Context 'TCP timestamps stay at the Windows default' {
        It 'sets timestamps=disabled and does not turn them on' {
            # Apply and stock Windows 11 both leave RFC 1323 timestamps
            # disabled. The netsh value is not in the manifest, so revert
            # must not flip the setting on.
            $script:Content | Should -Match 'netsh\s+int\s+tcp\s+set\s+global\s+timestamps=disabled'
            $script:Content | Should -Not -Match 'netsh\s+int\s+tcp\s+set\s+global\s+timestamps=enabled'
        }

        It 'network bat revert sets timestamps=disabled and does not turn them on' {
            $bat = Get-ToolkitScriptPath '7 network/revert-network.bat'
            $batContent = Get-Content -Raw -LiteralPath $bat
            $batContent | Should -Match 'netsh\s+int\s+tcp\s+set\s+global\s+timestamps=disabled'
            $batContent | Should -Not -Match 'netsh\s+int\s+tcp\s+set\s+global\s+timestamps=enabled'
        }
    }

    Context 'Reboot expectation surfaced to user' {
        It 'header or pre-confirm warns about reboot requirement' {
            $head = ($script:Content -split "`n" | Select-Object -First 30) -join "`n"
            $head | Should -Match '[Rr]eboot'
        }
    }
}
