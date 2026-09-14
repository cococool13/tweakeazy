#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    PS 5.1 load-path footguns: ConvertFrom-Json -Depth and 3-arg Join-Path.

.DESCRIPTION
    Inbox Windows PowerShell 5.1:
      - ConvertFrom-Json has no -Depth (that parameter arrived in 6.2)
      - Join-Path accepts only Path + ChildPath (a third positional
        argument, or -AdditionalChildPath, is PS 6+)

    APPLY / REVERT / launcher / Sandbox run on 5.1. This suite AST-scans
    that load path so a future "helpful" -Depth or extra Join-Path
    argument fails the gate on any host — no Windows runtime needed.

.NOTES
    # CROSS-PLATFORM-NOTE
    # Parser-only; runs anywhere. Tagged PS51 for filter/discovery.
#>

BeforeDiscovery {
    . (Join-Path (Join-Path $PSScriptRoot '..') '_common.ps1')

    $script:LoadPathFiles = @(
        'APPLY-EVERYTHING.ps1'
        'REVERT-EVERYTHING.ps1'
        'launcher.ps1'
        'lib/toolkit-state.ps1'
        'profile/parts/toolkit-aware.ps1'
        'tools/Start-SandboxSession.ps1'
    )

    $script:LoadPathCases = foreach ($rel in $script:LoadPathFiles) {
        @{
            Path = $rel
            FullPath = (Join-Path $script:RepoRoot $rel)
        }
    }
}

Describe 'Invariant: APPLY / REVERT / launcher / Sandbox stay PS 5.1-safe' -Tag 'PS51' {

    It '<Path> exists on the load path' -ForEach $script:LoadPathCases {
        Test-Path -LiteralPath $FullPath | Should -BeTrue
    }

    It '<Path> does not pass -Depth to ConvertFrom-Json' -ForEach $script:LoadPathCases {
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $FullPath, [ref]$null, [ref]$errors
        )
        $errors | Should -BeNullOrEmpty

        $depthCalls = $ast.FindAll({
                param($n)
                if ($n -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
                if ($n.GetCommandName() -ne 'ConvertFrom-Json') { return $false }
                foreach ($elem in $n.CommandElements) {
                    if ($elem -is [System.Management.Automation.Language.CommandParameterAst] -and
                        $elem.ParameterName -eq 'Depth') {
                        return $true
                    }
                }
                return $false
            }, $true)

        $depthCalls | Should -BeNullOrEmpty `
            -Because 'ConvertFrom-Json -Depth is PS 6.2+; inbox 5.1 only has -InputObject. Keep -Depth on ConvertTo-Json.'
    }

    It '<Path> does not use 3-arg Join-Path or -AdditionalChildPath' -ForEach $script:LoadPathCases {
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $FullPath, [ref]$null, [ref]$errors
        )
        $errors | Should -BeNullOrEmpty

        $joinCalls = $ast.FindAll({
                param($n)
                if ($n -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
                return ($n.GetCommandName() -eq 'Join-Path')
            }, $true)

        $switchNames = @(
            'Resolve'
            'WhatIf'
            'Confirm'
            'Verbose'
            'Debug'
        )

        $violations = @()
        foreach ($call in $joinCalls) {
            $positional = 0
            $skipNext = $false
            $hasAdditional = $false
            foreach ($elem in ($call.CommandElements | Select-Object -Skip 1)) {
                if ($skipNext) {
                    $skipNext = $false
                    continue
                }
                if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                    if ($elem.ParameterName -eq 'AdditionalChildPath') {
                        $hasAdditional = $true
                    }
                    if ($switchNames -notcontains $elem.ParameterName) {
                        $skipNext = $true
                    }
                    continue
                }
                $positional++
            }
            if ($hasAdditional -or $positional -gt 2) {
                $violations += $call.Extent.Text
            }
        }

        $violations | Should -BeNullOrEmpty `
            -Because '3-arg Join-Path / -AdditionalChildPath is PS 6+. Use two nested Join-Path calls.'
    }
}
