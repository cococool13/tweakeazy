#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract for DduManual.ps1 driver-search tracking.

.DESCRIPTION
    Set-DriverSearchPolicy used to raw `reg add` SearchOrderConfig=0
    and never restore it. These assertions lock the replacement:
    the write goes through Set-DduDriverSearchPolicy (manifest id
    reg:DriverSearchOrderConfig) and both the in-session path and
    the Safe Mode resume script restore the pre-DDU value after DDU
    exits.

.NOTES
    # CROSS-PLATFORM-NOTE
    # Text scan only. Runtime registry checks are MANUAL-TEST-CHECKLIST.md 16.3.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '_common.ps1')
    $script:Target = Get-ToolkitScriptPath 'DduManual.ps1'
    $script:Content = Get-Content -Raw -LiteralPath $script:Target
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Target, [ref]$null, [ref]$null
    )
}

Describe 'DduManual.ps1 — driver search policy is tracked and restored' {

    Context 'File health' {
        It 'parses without errors' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:Target, [ref]$null, [ref]$errors
            )
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'No raw SearchOrderConfig write' {
        It 'does not reg add SearchOrderConfig' {
            $script:Content | Should -Not -Match 'reg add .*SearchOrderConfig'
            $script:Content | Should -Not -Match 'Set-DriverSearchPolicy'
        }

        It 'holds the policy through Set-DduDriverSearchPolicy after Initialize-ToolkitState' {
            $script:Content | Should -Match 'Initialize-ToolkitState'
            $script:Content | Should -Match 'Set-DduDriverSearchPolicy'
        }
    }

    Context 'Restore runs after DDU exits' {
        It 'waits for the in-session DDU process, then restores' {
            $script:Content | Should -Match '(?s)Start-Process -FilePath \$dduExe -Wait.+Restore-HeldDriverSearchPolicy'
        }

        It 'embeds a resume-script restore after the Safe Mode DDU -Wait' {
            # The block text is built by Get-DduDriverSearchRestoreBlock and
            # spliced into the resume script after Start-Process -Wait.
            $script:Content | Should -Match '(?s)Start-Process -FilePath ''\$DduExe'' -Wait.+\$driverSearchRestoreBlock'
            $script:Content | Should -Match 'Get-DduDriverSearchRestoreBlock -Prior \$DriverSearchPrior'
            $script:Content | Should -Match '-DriverSearchPrior \$script:DriverSearchPrior'
        }

        It 'does not restore on the Safe Mode handoff path' {
            # Handoff is set only after safeboot is scheduled. The catch
            # restores when handoff did not happen (bcdedit failure, staging
            # throw) and skips restore once the resume script owns it.
            $script:Content | Should -Match '\$script:DriverSearchHandoff = \$true'
            $script:Content | Should -Match 'if \(-not \$script:DriverSearchHandoff\) \{\s+Restore-HeldDriverSearchPolicy'
        }

        It 'restores when Safe Mode scheduling fails, before the throw escapes' {
            $script:Content | Should -Match '(?s)Remove-DduRunOnce\s+throw "Failed to schedule Safe Mode boot"'
            $handoffAt = $script:Content.IndexOf('$script:DriverSearchHandoff = $true')
            $throwAt = $script:Content.IndexOf('throw "Failed to schedule Safe Mode boot"')
            $throwAt | Should -BeLessThan $handoffAt
        }
    }
}
