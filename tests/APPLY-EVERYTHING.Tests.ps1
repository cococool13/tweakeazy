#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract tests for APPLY-EVERYTHING.ps1.

.DESCRIPTION
    APPLY-EVERYTHING.ps1 is the maximal-apply entry point. Regressions
    here either over-apply (running gated Security Trade-off phases by
    default) or under-apply (skipping mandatory Safe/Advanced phases).
    These AST tests catch:

      - The -IncludeSecurityTradeoffs switch exists and defaults to off
      - Phase 9 (WU suppression) and Phase 10 (VBS/HVCI/LSA/Spectre)
        are wrapped in `if ($IncludeSecurityTradeoffs)` (CURSOR-AUDIT #1)
      - The Skip-Step fallback fires when phases are skipped (so the
        manifest records the skip; verify can see it)
      - The anti-cheat warning text mentions BattlEye / EAC by name
        (CURSOR-AUDIT #2; CLAUDE.md anti-cheat convention)
      - The 14-step header table is intact
      - All Set-TrackedRegistry / Set-TrackedService wrappers used
        downstream actually exist

    Runtime tests (actual registry writes) are Windows-only and live
    under tests/integration/. tests/manual/APPLY-EVERYTHING.md is the
    human-runner checklist for what can't be Pester'd statically.

.NOTES
    # CROSS-PLATFORM-NOTE
    # All assertions here are AST/text-scan only and run on any OS.
    # Behavioral assertions (Set-ItemProperty actually called, service
    # mode actually changed, manifest actually updated) cannot be
    # executed on macOS — see tests/manual/APPLY-EVERYTHING.md for the
    # Windows-only verifier checklist.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '_common.ps1')
    # Phase headings expected in the script body, in order. Drift
    # below would mean a phase was renamed / removed — investigate.
    $script:ExpectedPhaseHeadings = @(
        @{ Text = 'Phase 1: Safety Baseline' }
        @{ Text = 'Phase 2: Power and Core Windows Settings' }
        @{ Text = 'Phase 4: Services' }
        @{ Text = 'Phase 5: Registry Pack' }
        @{ Text = 'Phase 9: Windows Update Suppression' }
        @{ Text = 'Phase 10: Security Trade-offs' }
        @{ Text = 'Phase 11: Windows Customization' }
    )
    $script:ExpectedHelpers = @(
        @{ Name = 'Run-Step' }
        @{ Name = 'Skip-Step' }
        @{ Name = 'Reg-Add' }
        @{ Name = 'Set-TrackedRegistry' }
        @{ Name = 'Set-TrackedService' }
        @{ Name = 'Set-PowerIdx' }
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot '_common.ps1')
    $script:Target = Get-ToolkitScriptPath 'APPLY-EVERYTHING.ps1'
    $script:Content = Get-Content -Raw -LiteralPath $script:Target
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Target, [ref]$null, [ref]$null
    )
    $script:Functions = $script:Ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)
    $script:FunctionNames = @($script:Functions | ForEach-Object Name)
}

Describe 'APPLY-EVERYTHING.ps1 — surface contract' {

    Context 'File health' {
        It 'parses without errors' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:Target, [ref]$null, [ref]$errors
            )
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter surface (CURSOR-AUDIT #1 gate)' {
        It 'declares [CmdletBinding()]' {
            $cb = $script:Ast.ParamBlock.Attributes |
                Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }
            $cb | Should -Not -BeNullOrEmpty
        }

        It 'declares -IncludeSecurityTradeoffs as a [switch]' {
            $param = $script:Ast.ParamBlock.Parameters |
                Where-Object { $_.Name.VariablePath.UserPath -eq 'IncludeSecurityTradeoffs' }
            $param | Should -Not -BeNullOrEmpty
            $param.StaticType.FullName | Should -Be 'System.Management.Automation.SwitchParameter'
        }

        It 'IncludeSecurityTradeoffs has no default value (switch defaults false)' {
            $param = $script:Ast.ParamBlock.Parameters |
                Where-Object { $_.Name.VariablePath.UserPath -eq 'IncludeSecurityTradeoffs' }
            # A switch with no DefaultValue defaults to $false. A literal
            # $true default would be a regression — catch it here.
            $param.DefaultValue | Should -BeNullOrEmpty
        }
    }

    Context 'Security Trade-off gating (CURSOR-AUDIT #1, #2)' {
        It 'wraps Phase 9 in if ($IncludeSecurityTradeoffs)' {
            # The text-scan looks for the section heading then the gate
            # within ~50 lines. Tolerant to formatting drift.
            $idx = $script:Content.IndexOf('Phase 9: Windows Update Suppression')
            $idx | Should -BeGreaterThan -1
            $window = $script:Content.Substring($idx, [Math]::Min(3000, $script:Content.Length - $idx))
            $window | Should -Match 'if\s*\(\s*\$IncludeSecurityTradeoffs\s*\)'
        }

        It 'wraps Phase 10 in if ($IncludeSecurityTradeoffs)' {
            $idx = $script:Content.IndexOf('Phase 10: Security Trade-offs')
            $idx | Should -BeGreaterThan -1
            $window = $script:Content.Substring($idx, [Math]::Min(3000, $script:Content.Length - $idx))
            $window | Should -Match 'if\s*\(\s*\$IncludeSecurityTradeoffs\s*\)'
        }

        It 'emits Skip-Step records when phases are skipped' {
            # Required so verify-tweaks.ps1 sees the skip status instead
            # of an empty manifest entry — preserves audit trail.
            $script:Content | Should -Match 'Skip-Step\s+-Description\s+["'']phase9-windows-update'
            $script:Content | Should -Match 'Skip-Step\s+-Description\s+["'']phase10-security-tradeoffs'
        }

        It 'shows the anti-cheat warning before Phase 10 work runs' {
            # CLAUDE.md convention + CURSOR-AUDIT #2. BattlEye AND EAC
            # must both be named — generic "anti-cheat may break" is
            # too vague for users to act on.
            $idx = $script:Content.IndexOf('Phase 10: Security Trade-offs')
            $window = $script:Content.Substring($idx, [Math]::Min(2000, $script:Content.Length - $idx))
            $window | Should -Match 'ANTI-CHEAT'
            $window | Should -Match 'BattlEye'
            $window | Should -Match 'EAC'
        }

        It 'second UI-Confirm fires when -IncludeSecurityTradeoffs is set' {
            # Belt-and-suspenders: even after CLI flag, an interactive
            # second confirm gates the actual run.
            $script:Content | Should -Match 'if\s*\(\s*\$IncludeSecurityTradeoffs\s*\)\s*\{[^}]*UI-Confirm'
        }

        It 'gates the APPLY summary trade-off note on IncludeSecurityTradeoffs' {
            $idx = $script:Content.LastIndexOf('This run included Windows Update suppression')
            $idx | Should -BeGreaterThan -1
            $start = [Math]::Max(0, $idx - 250)
            $window = $script:Content.Substring($start, [Math]::Min(400, $script:Content.Length - $start))
            $window | Should -Match 'if\s*\(\s*\$IncludeSecurityTradeoffs\s*\)'
        }

        It 'does not point DDU follow-up at a dead launcher [G] key' {
            $script:Content | Should -Not -Match 'launcher \[G\]'
        }

        It 'points Phase 7.5 DDU skip at DduAuto.ps1 or launcher category 6' {
            $idx = $script:Content.IndexOf('Phase 7.5: GPU Driver Flow')
            $idx | Should -BeGreaterThan -1
            $window = $script:Content.Substring($idx, [Math]::Min(800, $script:Content.Length - $idx))
            $window | Should -Match 'DduAuto\.ps1'
            $window | Should -Match 'category 6'
        }
    }

    Context 'Phase headings present' {
        It 'has section heading: <Text>' -ForEach $script:ExpectedPhaseHeadings {
            $script:Content | Should -Match ([regex]::Escape($Text))
        }
    }

    Context 'Helper functions present' {
        It 'defines <Name>' -ForEach $script:ExpectedHelpers {
            $script:FunctionNames | Should -Contain $Name
        }
    }

    Context 'Header documents the Security Trade-off gate' {
        It 'header references -IncludeSecurityTradeoffs' {
            $head = ($script:Content -split "`n" | Select-Object -First 50) -join "`n"
            $head | Should -Match '-IncludeSecurityTradeoffs'
        }

        It 'header mentions BattlEye and EAC anti-cheat impact' {
            $head = ($script:Content -split "`n" | Select-Object -First 50) -join "`n"
            $head | Should -Match 'BattlEye'
            $head | Should -Match 'EAC'
        }
    }

    Context 'Admin self-check (CLAUDE.md invariant #6)' {
        It 'calls UI-RequireAdmin near the top' {
            $head = ($script:Content -split "`n" | Select-Object -First 80) -join "`n"
            $head | Should -Match 'UI-RequireAdmin'
        }
    }
}
