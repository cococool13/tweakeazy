#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Scoring contract for 10 verify/verify-tweaks.ps1.

.DESCRIPTION
    Default Apply All must not FAIL checks it does not apply. Storage
    Sense and the Security Trade-off checks are graded only when their
    step is recorded as applied. An active Ultimate plan reports
    APPLIED only when power:plan was recorded.

    The Check function is loaded from the script AST so this file does
    not execute the health-check body (registry, services, Read-Host).

.NOTES
    # CROSS-PLATFORM-NOTE
    # Parser + in-memory scoring only. No Windows registry access.
#>

BeforeDiscovery {
    $script:OptInLabels = @(
        'Storage Sense disabled'
        'Windows Update auto-restart blocked'
        'Windows Update service disabled'
        'VBS disabled'
        'HVCI disabled'
        'Spectre / Meltdown mitigations override applied'
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:VerifyPath = Get-ToolkitScriptPath '10 verify/verify-tweaks.ps1'
    $script:VerifyText = Get-Content -Raw -LiteralPath $script:VerifyPath
    $parseErrors = $null
    $script:VerifyAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:VerifyPath, [ref]$null, [ref]$parseErrors
    )
    if ($parseErrors) { throw ($parseErrors -join [Environment]::NewLine) }

    foreach ($name in @('Write-CheckStatus', 'Check')) {
        $fn = $script:VerifyAst.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
            }, $true) | Select-Object -First 1
        if (-not $fn) { throw "Missing function $name in verify-tweaks.ps1" }
        . ([scriptblock]::Create($fn.Extent.Text))
    }

    $script:CheckCalls = @()
    $commands = $script:VerifyAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Check'
        }, $true)
    foreach ($cmd in $commands) {
        $label = $null
        $stepKey = ''
        $only = $false
        # Element 0 is the command name token ("Check"), not an argument.
        $elements = @($cmd.CommandElements)
        for ($i = 1; $i -lt $elements.Count; $i++) {
            $el = $elements[$i]
            if ($el -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                if ($null -eq $label) { $label = $el.Value } else { $stepKey = $el.Value }
            } elseif ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                if ($el.ParameterName -eq 'OnlyIfRecorded') { $only = $true }
            }
        }
        $script:CheckCalls += [PSCustomObject]@{
            Label = $label
            StepKey = $stepKey
            OnlyIfRecorded = $only
        }
    }

    # Replace the script's Write-Host helper in this same scope so Check
    # (defined above) records rows instead of printing them.
    function Write-CheckStatus {
        param(
            [string]$Label,
            [string]$Status,
            [ConsoleColor]$Color
        )
        [void]$script:Rows.Add([PSCustomObject]@{ Label = $Label; Status = $Status })
    }

    function Get-ToolkitRecordedStatus {
        param([string]$Key)
        if ($script:Recorded.ContainsKey($Key)) { return $script:Recorded[$Key] }
        return $null
    }

    function Read-VerifyBaseline {
        $script:pass = 0
        $script:fail = 0
        $script:warn = 0
        $script:applied = 0
        $script:preexisting = 0
        $script:unsupported = 0
        $script:drifted = 0
        $script:Rows = New-Object System.Collections.Generic.List[object]
    }

    function Invoke-ParsedChecks {
        # Opt-in probes return false (setting absent). Every other probe
        # returns true (default Apply All left that setting in place).
        foreach ($call in $script:CheckCalls) {
            $script:ProbeReturns = -not $call.OnlyIfRecorded
            if ($call.OnlyIfRecorded) {
                Check -Label $call.Label -Test { $script:ProbeReturns } -StepKey $call.StepKey -OnlyIfRecorded
            } else {
                Check -Label $call.Label -Test { $script:ProbeReturns } -StepKey $call.StepKey
            }
        }
    }
}

Describe 'verify-tweaks.ps1 — default Apply All scoring' {

    Context 'Call sites' {
        It 'parses without errors' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:VerifyPath, [ref]$null, [ref]$errors
            )
            $errors | Should -BeNullOrEmpty
        }

        It 'gates <_> on a recorded applied step' -ForEach $script:OptInLabels {
            $label = $_
            $call = $script:CheckCalls | Where-Object { $_.Label -eq $label } | Select-Object -First 1
            $call | Should -Not -BeNullOrEmpty
            $call.OnlyIfRecorded | Should -BeTrue
            $call.StepKey | Should -Not -BeNullOrEmpty
        }

        It 'always grades the Ultimate Performance check' {
            $call = $script:CheckCalls | Where-Object { $_.Label -eq 'Ultimate Performance plan is active' }
            $call.OnlyIfRecorded | Should -BeFalse
            $call.StepKey | Should -Be 'power:plan'
        }

        It 'footer does not call trade-offs intentional on the default path' {
            $script:VerifyText | Should -Not -Match 'intentional in Apply Everything'
            $script:VerifyText | Should -Match 'Security Trade-off and Storage Sense checks are graded only when their step is recorded\. Default Apply All leaves them off\.'
        }
    }

    Context 'Score when opt-in steps are absent' {
        BeforeEach {
            Read-VerifyBaseline
            # Default Apply All records the plan and the phase skips.
            # It does not record Storage Sense or the trade-off keys.
            $script:Recorded = @{
                'power:plan' = 'applied'
                'phase9-windows-update' = 'skipped'
                'phase10-security-tradeoffs' = 'skipped'
            }
            Invoke-ParsedChecks
        }

        It 'does not FAIL Storage Sense or Security Trade-off checks' {
            $script:fail | Should -Be 0
            $script:drifted | Should -Be 0
            foreach ($label in $script:OptInLabels) {
                $row = $script:Rows | Where-Object { $_.Label -eq $label }
                $row | Should -BeNullOrEmpty
            }
        }

        It 'reports an active Ultimate plan as APPLIED when power:plan is recorded' {
            $row = $script:Rows | Where-Object { $_.Label -eq 'Ultimate Performance plan is active' }
            $row.Status | Should -Be 'APPLIED'
            $script:applied | Should -BeGreaterThan 0
        }
    }

    Context 'Score when power:plan was never written' {
        BeforeEach {
            Read-VerifyBaseline
            $script:Recorded = @{
                'phase9-windows-update' = 'skipped'
                'phase10-security-tradeoffs' = 'skipped'
            }
            Invoke-ParsedChecks
        }

        It 'reports an active Ultimate plan as PREEXISTING' {
            $row = $script:Rows | Where-Object { $_.Label -eq 'Ultimate Performance plan is active' }
            $row.Status | Should -Be 'PREEXISTING'
            $script:fail | Should -Be 0
        }
    }

    Context 'Score when a trade-off step was applied' {
        BeforeEach {
            Read-VerifyBaseline
            $script:Recorded = @{
                'power:plan' = 'applied'
                'reg:StorageSenseMaster' = 'applied'
                'reg:NoAutoRebootWithLoggedOnUsers' = 'applied'
                'service:wuauserv' = 'applied'
                'reg:EnableVBS' = 'applied'
                'reg:HVCIEnabled' = 'applied'
                'reg:FeatureSettingsOverride' = 'applied'
            }
            Invoke-ParsedChecks
        }

        It 'grades a recorded step that no longer matches as DRIFTED' {
            $gated = @($script:CheckCalls | Where-Object { $_.OnlyIfRecorded })
            $script:fail | Should -Be $gated.Count
            $script:drifted | Should -Be $gated.Count
            foreach ($label in $script:OptInLabels) {
                $row = $script:Rows | Where-Object { $_.Label -eq $label }
                $row.Status | Should -Be 'DRIFTED'
            }
        }

        It 'does not grade a step recorded as skipped' {
            Read-VerifyBaseline
            $script:Recorded = @{ 'reg:HVCIEnabled' = 'skipped' }
            Check -Label 'HVCI disabled' -Test { $false } -StepKey 'reg:HVCIEnabled' -OnlyIfRecorded
            $script:fail | Should -Be 0
            $script:Rows.Count | Should -Be 0
        }
    }
}

Describe 'power:plan writers' {
    It 'configure-power.ps1 records the verify key' {
        $path = Get-ToolkitScriptPath '2 power plan/configure-power.ps1'
        $text = Get-Content -Raw -LiteralPath $path
        $text | Should -Match 'Add-ToolkitStepResult\s+-Key\s+"power:plan"'
        $text | Should -Match 'Add-ToolkitStepResult\s+-Key\s+\$stepName'
    }
}
