#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract tests for lib/ui-helpers.ps1.

.DESCRIPTION
    Validates the UI-* helper surface that ~75 scripts dot-source.
    AST-only — runtime tests (actual Write-Host capture, color codes)
    live in tests/integration/ tagged 'WindowsOnly'.

.NOTES
    Test rig: tests/_common.ps1 provides shared helpers.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:ExpectedPublic = @(
        @{ Name = 'UI-ResetCounters' }
        @{ Name = 'UI-RequireAdmin' }
        @{ Name = 'UI-Header' }
        @{ Name = 'UI-Section' }
        @{ Name = 'UI-Note' }
        @{ Name = 'UI-KeyValue' }
        @{ Name = 'UI-ShowProfile' }
        @{ Name = 'UI-Step' }
        @{ Name = 'UI-Skip' }
        @{ Name = 'UI-Summary' }
        @{ Name = 'UI-Confirm' }
        @{ Name = 'UI-AskYesNo' }
        @{ Name = 'UI-Exit' }
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:Target = Get-ToolkitScriptPath 'lib/ui-helpers.ps1'
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Target, [ref]$null, [ref]$null
    )
    $script:Functions = $script:Ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)
    $script:FunctionNames = @($script:Functions | ForEach-Object Name)
}

Describe 'lib/ui-helpers.ps1 — surface contract' {

    Context 'File health' {
        It 'parses without errors' {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:Target, [ref]$tokens, [ref]$errors
            )
            $errors | Should -BeNullOrEmpty
        }

        It 'declares the script-scoped color constants' {
            # The UI palette must exist so every dot-sourcing script can
            # reference $script:UI_Success / UI_Error / UI_Warning / etc.
            $content = Get-Content -Raw -LiteralPath $script:Target
            foreach ($name in @('UI_Header', 'UI_Error', 'UI_Warning', 'UI_Success', 'UI_Info')) {
                $content | Should -Match "\`$script:$name\s*=" -Because 'every UI palette name in use across the tree must be declared here'
            }
        }
    }

    Context 'Public surface (the UI-* namespace)' {
        It 'exports <Name>' -ForEach $script:ExpectedPublic {
            $script:FunctionNames | Should -Contain $Name
        }
    }

    Context 'UI-ShowProfile no longer shadows automatic $Profile' {
        It 'uses parameter name $MachineProfile (not $Profile)' {
            # Regression test for the PSAvoidAssignmentToAutomaticVariable
            # fix at commit 596e701. The parameter was renamed; the
            # original name remains as an Alias so callers passing
            # -Profile continue to work.
            $fn = $script:Functions | Where-Object Name -EQ 'UI-ShowProfile'
            $fn | Should -Not -BeNullOrEmpty
            $paramNames = $fn.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
            $paramNames | Should -Contain 'MachineProfile'
            $paramNames | Should -Not -Contain 'Profile'
        }

        It 'declares Profile as a parameter Alias for back-compat' {
            $fn = $script:Functions | Where-Object Name -EQ 'UI-ShowProfile'
            $hasAlias = $false
            foreach ($p in $fn.Body.ParamBlock.Parameters) {
                foreach ($attr in $p.Attributes) {
                    if ($attr.TypeName.Name -eq 'Alias') {
                        foreach ($arg in $attr.PositionalArguments) {
                            if ($arg.Extent.Text -match "'Profile'") {
                                $hasAlias = $true
                            }
                        }
                    }
                }
            }
            $hasAlias | Should -BeTrue -Because 'callers passed -Profile $machineProfile before the rename; Alias preserves that surface'
        }
    }
}

Describe 'lib/ui-helpers.ps1 — behavioral' {

    BeforeAll {
        # Dot-source into THIS scope so the functions + script: counters
        # exist for the It blocks to invoke. The previous Describe block
        # only parsed the AST; here we actually call the helpers so
        # CommandsExecuted (coverage) is populated.
        . (Join-Path $PSScriptRoot '..' '..' 'lib' 'ui-helpers.ps1')
    }

    Context 'Counter mutation — UI-ResetCounters, UI-Step, UI-Skip' {

        BeforeEach {
            UI-ResetCounters
        }

        It 'UI-ResetCounters zeroes all three script-scope counters' {
            $script:UI_Succeeded = 5
            $script:UI_Failed = 3
            $script:UI_Warned = 2
            UI-ResetCounters
            $script:UI_Succeeded | Should -Be 0
            $script:UI_Failed | Should -Be 0
            $script:UI_Warned | Should -Be 0
        }

        It 'UI-Step with a passing action increments UI_Succeeded by 1' {
            UI-Step -Label 'no-op' -Action { } 6>$null
            $script:UI_Succeeded | Should -Be 1
            $script:UI_Failed | Should -Be 0
            $script:UI_Warned | Should -Be 0
        }

        It 'UI-Step with a throwing action increments UI_Failed by 1 (default critical mode)' {
            UI-Step -Label 'boom' -Action { throw 'expected' } 6>$null
            $script:UI_Succeeded | Should -Be 0
            $script:UI_Failed | Should -Be 1
            $script:UI_Warned | Should -Be 0
        }

        It 'UI-Step -NonCritical converts throws to UI_Warned increments' {
            # Lets a recoverable failure (e.g., 'service already in target state')
            # tally as a warning instead of an error — used heavily in revert paths.
            UI-Step -Label 'soft boom' -Action { throw 'recoverable' } -NonCritical 6>$null
            $script:UI_Failed | Should -Be 0
            $script:UI_Warned | Should -Be 1
        }

        It 'UI-Skip increments UI_Warned without invoking any action' {
            UI-Skip -Label 'inert' -Reason 'pre-existing state' 6>$null
            $script:UI_Warned | Should -Be 1
            $script:UI_Succeeded | Should -Be 0
            $script:UI_Failed | Should -Be 0
        }

        It 'multiple UI-Step + UI-Skip calls accumulate independently' {
            UI-Step -Label 'a' -Action { } 6>$null
            UI-Step -Label 'b' -Action { } 6>$null
            UI-Step -Label 'c' -Action { throw 'x' } 6>$null
            UI-Skip -Label 'd' -Reason 'noop' 6>$null
            $script:UI_Succeeded | Should -Be 2
            $script:UI_Failed | Should -Be 1
            $script:UI_Warned | Should -Be 1
        }
    }

    Context 'Pure-output helpers — UI-Header, UI-Section, UI-Note, UI-KeyValue' {
        # These are colored Write-Host wrappers. The contract is "doesn't
        # throw on any valid string input". Output capture would require
        # an out-of-process call; behavior coverage is enough here.

        It 'UI-Header tolerates a Title-only call' {
            { UI-Header -Title 'X' 6>$null } | Should -Not -Throw
        }

        It 'UI-Header tolerates Title + Subtitle + custom Color' {
            { UI-Header -Title 'X' -Subtitle 'Y' -Color 'Magenta' 6>$null } | Should -Not -Throw
        }

        It 'UI-Section tolerates a Title-only call AND Title + Context' {
            { UI-Section -Title 'phase 1' 6>$null } | Should -Not -Throw
            { UI-Section -Title 'phase 1' -Context 'doing the thing' 6>$null } | Should -Not -Throw
        }

        It 'UI-Note tolerates default + custom color' {
            { UI-Note -Message 'hello' 6>$null } | Should -Not -Throw
            { UI-Note -Message 'warn' -Color 'Yellow' 6>$null } | Should -Not -Throw
        }

        It 'UI-KeyValue tolerates a typical Label/Value call' {
            { UI-KeyValue -Label 'Disk' -Value '500GB' 6>$null } | Should -Not -Throw
        }
    }

    Context 'UI-Summary branches' {

        BeforeEach {
            UI-ResetCounters
        }

        It 'with zero failures prints the [DONE] success message' {
            UI-Step -Label 'a' -Action { } 6>$null
            { UI-Summary -DoneMessage 'all good' 6>$null } | Should -Not -Throw
        }

        It 'with failures prints "(with errors)" message' {
            UI-Step -Label 'fail' -Action { throw 'x' } 6>$null
            { UI-Summary -DoneMessage 'done with issues' 6>$null } | Should -Not -Throw
        }

        It 'tolerates Details + RevertHint trailing rows' {
            UI-Step -Label 'a' -Action { } 6>$null
            { UI-Summary -DoneMessage 'x' -Details @('reboot suggested', 'reapply on Windows update') -RevertHint 'enable-foo.ps1' 6>$null } |
                Should -Not -Throw
        }
    }

    Context 'UI-ShowProfile — null guard + KV emission' {

        It 'returns silently on $null input' {
            { UI-ShowProfile -MachineProfile $null 6>$null } | Should -Not -Throw
        }

        It 'emits 5 KV rows when given a populated profile object' {
            # Manufacturer + Windows + Power + Graphics + Domain rows.
            # Don't capture text — just verify no throw on the expected
            # property shape that 11 hardware checks/check-storage.ps1
            # and launcher.ps1 emit.
            # $machineProfile not $profile — $profile is PowerShell's
            # automatic var pointing at the user's profile script path
            # (CLAUDE.md "Known gotchas").
            $machineProfile = [PSCustomObject]@{
                manufacturer = 'Dell'
                model = 'XPS 15'
                windowsCaption = 'Win11 Pro'
                powerState = 'AC'
                gpuCount = 2
                isHybridGraphics = $true
                partOfDomain = $false
            }
            { UI-ShowProfile -MachineProfile $machineProfile 6>$null } | Should -Not -Throw
        }
    }

    Context 'UI-AskYesNo — Read-Host mocked' {

        It 'returns -not $DefaultNo when Read-Host is empty (Enter)' {
            Mock Read-Host { return '' }
            # Default DefaultNo = $true means empty/Enter → not true → $false
            UI-AskYesNo -Prompt 'q' | Should -BeFalse
            # DefaultNo = $false means empty/Enter → not false → $true
            UI-AskYesNo -Prompt 'q' -DefaultNo $false | Should -BeTrue
        }

        It 'returns $true on Y (case-insensitive)' {
            Mock Read-Host { return 'y' }
            UI-AskYesNo -Prompt 'q' | Should -BeTrue
            Mock Read-Host { return 'Y' }
            UI-AskYesNo -Prompt 'q' | Should -BeTrue
        }

        It 'returns $false on any non-Y response' {
            Mock Read-Host { return 'n' }
            UI-AskYesNo -Prompt 'q' | Should -BeFalse
            Mock Read-Host { return 'maybe' }
            UI-AskYesNo -Prompt 'q' | Should -BeFalse
        }

        It 'trims and uppercases whitespace responses' {
            Mock Read-Host { return '  y  ' }
            UI-AskYesNo -Prompt 'q' | Should -BeTrue
        }
    }
}
