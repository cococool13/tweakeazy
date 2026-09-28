#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract tests for the SMT/HT pair and the wholesale Defender pair.

.DESCRIPTION
    Covers:
      8 security vs performance/disable-smt-ht.ps1 + enable-smt-ht.ps1
      8 security vs performance/disable-defender-wholesale.ps1
        + enable-defender-wholesale.ps1

    Same shape as tests/7-network/rss-tuning.Tests.ps1: parse, mutator
    surface, cross-script parity, header contract. RSC / NDIS tuning is
    out of scope.

.NOTES
    Verify: static only. Code-complete, runtime-pending — these tests do
    not call bcdedit or write Defender policy on a Windows host.
    MANUAL-TEST-CHECKLIST.md remains the runtime gate.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:DisableSmt = Get-ToolkitScriptPath '8 security vs performance/disable-smt-ht.ps1'
    $script:EnableSmt = Get-ToolkitScriptPath '8 security vs performance/enable-smt-ht.ps1'
    $script:DisableDefender = Get-ToolkitScriptPath '8 security vs performance/disable-defender-wholesale.ps1'
    $script:EnableDefender = Get-ToolkitScriptPath '8 security vs performance/enable-defender-wholesale.ps1'
    $script:DisableSmtContent = Get-Content -Raw -LiteralPath $script:DisableSmt
    $script:EnableSmtContent = Get-Content -Raw -LiteralPath $script:EnableSmt
    $script:DisableDefenderContent = Get-Content -Raw -LiteralPath $script:DisableDefender
    $script:EnableDefenderContent = Get-Content -Raw -LiteralPath $script:EnableDefender
    $script:ApplyEverything = Get-Content -Raw -LiteralPath (Get-ToolkitScriptPath 'APPLY-EVERYTHING.ps1')
}

Describe 'SMT / Hyper-Threading script pair' {

    Context 'File health' {
        It 'disable parses' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:DisableSmt, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }
        It 'enable parses' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:EnableSmt, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'Mutator surface' {
        It 'disable self-checks admin' {
            (Test-ToolkitAdminCheck -Path $script:DisableSmt).Passes | Should -BeTrue
        }
        It 'enable self-checks admin' {
            (Test-ToolkitAdminCheck -Path $script:EnableSmt).Passes | Should -BeTrue
        }
        It 'enable supports ShouldProcess' {
            (Test-ToolkitParameterShape -Path $script:EnableSmt -RequireShouldProcess).SupportsShouldProcess | Should -BeTrue
        }
        It 'enable opens the ShouldProcess gate around bcdedit /deletevalue numproc' {
            $script:EnableSmtContent | Should -Match '\$PSCmdlet\.ShouldProcess\('
            $script:EnableSmtContent | Should -Match 'bcdedit\.exe\s+/deletevalue\s+"\{current\}"\s+numproc'
        }
        It 'disable limits the current BCD entry with bcdedit /set numproc' {
            $script:DisableSmtContent | Should -Match 'bcdedit\.exe\s+/set\s+"\{current\}"\s+numproc\s+\$physicalCores'
        }
        It 'disable sets numproc from physical cores, not logical processors' {
            $script:DisableSmtContent | Should -Match '\$physicalCores\s*=\s*\[int\]\$cpu\.NumberOfCores'
            $script:DisableSmtContent | Should -Match '\$logicalCores\s*=\s*\[int\]\$cpu\.NumberOfLogicalProcessors'
            $script:DisableSmtContent | Should -Match '\$logicalCores\s+-le\s+\$physicalCores'
        }
    }

    Context 'Step, tier, and confirmation' {
        It 'disable records cpu-smt-disable at Security Trade-off' {
            $script:DisableSmtContent | Should -Match '\$stepName\s*=\s*"cpu-smt-disable"'
            $script:DisableSmtContent | Should -Match 'Tier:\s+Security Trade-off'
            $script:DisableSmtContent | Should -Match '-Tier\s+"Security Trade-off"'
        }
        It 'enable records cpu-smt-disable-revert at tier Safe' {
            $script:EnableSmtContent | Should -Match '-Key\s+"cpu-smt-disable-revert"'
            $script:EnableSmtContent | Should -Match '-Tier\s+"Safe"'
            $script:EnableSmtContent | Should -Match 'Tier:\s+Safe'
        }
        It 'disable exposes -Force and keeps the cargo-cult warning' {
            $script:DisableSmtContent | Should -Match 'param\(\[switch\]\$Force\)'
            $script:DisableSmtContent | Should -Match 'CARGO-CULT'
            $script:DisableSmtContent | Should -Match 'if\s+\(-not\s+\$Force\)'
        }
    }

    Context 'Opt-in and header' {
        It 'APPLY-EVERYTHING does not invoke the SMT pair' {
            $script:ApplyEverything | Should -Not -Match 'disable-smt-ht\.ps1'
            $script:ApplyEverything | Should -Not -Match 'enable-smt-ht\.ps1'
        }
        It 'pair names each other' {
            $script:DisableSmtContent | Should -Match 'enable-smt-ht\.ps1'
            $script:EnableSmtContent | Should -Match 'disable-smt-ht\.ps1'
        }
        It 'enable states no anti-cheat impact' {
            $script:EnableSmtContent | Should -Match 'Anti-cheat impact:\s*NONE'
            $script:EnableSmtContent | Should -Match 'Reboot required:'
            $script:EnableSmtContent | Should -Match 'Disk impact:\s*NONE'
        }
    }

    Context 'Comment-based help' {
        It 'enable has SYNOPSIS / DESCRIPTION / NOTES' {
            $h = Test-ToolkitCommentBasedHelp -Path $script:EnableSmt
            $h.HasSynopsis | Should -BeTrue
            $h.HasDescription | Should -BeTrue
            $h.HasNotes | Should -BeTrue
        }
    }
}

Describe 'Wholesale Defender script pair' {

    Context 'File health' {
        It 'disable parses' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:DisableDefender, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }
        It 'enable parses' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:EnableDefender, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'Mutator surface' {
        It 'disable self-checks admin' {
            (Test-ToolkitAdminCheck -Path $script:DisableDefender).Passes | Should -BeTrue
        }
        It 'enable self-checks admin' {
            (Test-ToolkitAdminCheck -Path $script:EnableDefender).Passes | Should -BeTrue
        }
        It 'disable routes policy writes through Set-ToolkitRegistryValue' {
            $script:DisableDefenderContent | Should -Match 'Set-ToolkitRegistryValue'
            $script:DisableDefenderContent | Should -Not -Match 'Set-ItemProperty'
        }
        It 'enable restores manifest entries through Restore-ToolkitRegistryValue' {
            $script:EnableDefenderContent | Should -Match 'Restore-ToolkitRegistryValue\s+-Id\s+\$id'
        }
        It 'disable turns realtime and IOAV off; enable turns them back on' {
            $script:DisableDefenderContent | Should -Match 'Set-MpPreference\s+-DisableRealtimeMonitoring\s+\$true'
            $script:DisableDefenderContent | Should -Match 'Set-MpPreference\s+-DisableIOAVProtection\s+\$true'
            $script:EnableDefenderContent | Should -Match 'Set-MpPreference\s+-DisableRealtimeMonitoring\s+\$false'
            $script:EnableDefenderContent | Should -Match 'Set-MpPreference\s+-DisableIOAVProtection\s+\$false'
        }
    }

    Context 'Policy id and value-name parity' {
        It 'disable writes exactly the seven Defender policy ids' {
            $found = @(
                [regex]::Matches($script:DisableDefenderContent, '-Id\s+"(reg:[^"]+)"') |
                    ForEach-Object { $_.Groups[1].Value } |
                    Sort-Object -Unique
            )
            $expected = @(
                'reg:DefenderDisableAntiSpyware'
                'reg:DefenderDisableAntiVirus'
                'reg:DefenderDisableBehaviorMonitoring'
                'reg:DefenderDisableOnAccessProtection'
                'reg:DefenderDisableRealtimeMonitoring'
                'reg:DefenderSpynetReporting'
                'reg:DefenderSubmitSamplesConsent'
            ) | Sort-Object
            ($found -join ',') | Should -Be ($expected -join ',')
        }
        It 'every disable registry id matches the enable restore filter' {
            $filter = [regex]::Match($script:EnableDefenderContent, '-like\s+"(reg:[^"]+)"')
            $filter.Success | Should -BeTrue
            $ids = @(
                [regex]::Matches($script:DisableDefenderContent, '-Id\s+"(reg:[^"]+)"') |
                    ForEach-Object { $_.Groups[1].Value }
            )
            $ids.Count | Should -BeGreaterThan 0
            foreach ($id in $ids) {
                $id -like $filter.Groups[1].Value | Should -BeTrue
            }
        }
        It 'enable fallback removes every value name disable writes' {
            $names = @(
                [regex]::Matches($script:DisableDefenderContent, '-Name\s+"([^"]+)"') |
                    ForEach-Object { $_.Groups[1].Value } |
                    Sort-Object -Unique
            )
            $names.Count | Should -BeGreaterThan 0
            foreach ($name in $names) {
                $script:EnableDefenderContent | Should -Match ('"' + [regex]::Escape($name) + '"')
            }
        }
        It 'disable records defender-wholesale at Security Trade-off' {
            $script:DisableDefenderContent | Should -Match '\$stepName\s*=\s*"defender-wholesale"'
            $script:DisableDefenderContent | Should -Match '-Tier\s+"Security Trade-off"'
            $script:DisableDefenderContent | Should -Match '-Step\s+\$stepName'
        }
        It 'enable records defender-wholesale-revert at tier Safe' {
            $script:EnableDefenderContent | Should -Match '-Key\s+"defender-wholesale-revert"'
            $script:EnableDefenderContent | Should -Match '-Tier\s+"Safe"'
        }
    }

    Context 'Opt-in and header' {
        It 'APPLY-EVERYTHING does not invoke the Defender pair' {
            $script:ApplyEverything | Should -Not -Match 'disable-defender-wholesale\.ps1'
            $script:ApplyEverything | Should -Not -Match 'enable-defender-wholesale\.ps1'
        }
        It 'disable keeps the Tamper Protection warning and -Force' {
            $script:DisableDefenderContent | Should -Match 'param\(\[switch\]\$Force\)'
            $script:DisableDefenderContent | Should -Match 'Tamper Protection'
            $script:DisableDefenderContent | Should -Match 'CARGO-CULT'
            $script:DisableDefenderContent | Should -Match 'Tier:\s+Security Trade-off'
        }
        It 'both halves state no anti-cheat impact' {
            $script:DisableDefenderContent | Should -Match 'Anti-cheat impact:\s*NONE'
            $script:EnableDefenderContent | Should -Match 'Anti-cheat impact:\s*NONE'
            $script:DisableDefenderContent | Should -Match 'Reboot required:'
            $script:EnableDefenderContent | Should -Match 'Reboot required:'
            $script:DisableDefenderContent | Should -Match 'Disk impact:\s*NONE'
            $script:EnableDefenderContent | Should -Match 'Disk impact:\s*NONE'
        }
        It 'enable header tier is Safe' {
            $script:EnableDefenderContent | Should -Match 'Tier:\s+Safe'
        }
        It 'pair names each other' {
            $script:DisableDefenderContent | Should -Match 'enable-defender-wholesale\.ps1'
            $script:EnableDefenderContent | Should -Match 'disable-defender-wholesale\.ps1'
        }
    }
}
