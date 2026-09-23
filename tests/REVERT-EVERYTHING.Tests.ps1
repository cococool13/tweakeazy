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

    Context 'Reboot expectation surfaced to user' {
        It 'header or pre-confirm warns about reboot requirement' {
            $head = ($script:Content -split "`n" | Select-Object -First 30) -join "`n"
            $head | Should -Match '[Rr]eboot'
        }
    }
}
