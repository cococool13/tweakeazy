#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Read-only contract for the two hardware info display scripts.

.DESCRIPTION
    show-system-summary.ps1 lives under launcher [11] Hardware checks.
    show-mouse-info.ps1 lives under launcher [12] Hardware. Both only
    display state. These tests lock that contract and the header menu
    numbers so they cannot drift back to launcher [1] Backup or
    launcher [7] Network, and so show-mouse-info keeps pointing at
    check-input-polling.ps1 (the HID audit that already exists).
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:InfoCases = @(
        @{
            Name = 'show-system-summary'
            Relative = '11 hardware checks/show-system-summary.ps1'
            LauncherKey = '[11]'
            Folder = '11 hardware checks'
        }
        @{
            Name = 'show-mouse-info'
            Relative = '12 hardware/show-mouse-info.ps1'
            LauncherKey = '[12]'
            Folder = '12 hardware'
        }
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
}

Describe 'Hardware info scripts stay read-only and name their real launcher keys' {

    Context 'File health' {
        It '<Name>.ps1 parses' -ForEach $script:InfoCases {
            $path = Get-ToolkitScriptPath $Relative
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'Read-only contract (no tracked-write helpers, no Set-/Remove-/New-ItemProperty)' {
        It '<Name>.ps1 does not call any mutator' -ForEach $script:InfoCases {
            $path = Get-ToolkitScriptPath $Relative
            $content = Get-Content -Raw -LiteralPath $path
            $content | Should -Not -Match 'Set-ToolkitRegistryValue'
            $content | Should -Not -Match 'Set-ToolkitServiceStartMode'
            $content | Should -Not -Match 'Set-TrackedRegistry'
            $content | Should -Not -Match 'Set-TrackedService'
            $content | Should -Not -Match 'Set-ItemProperty'
            $content | Should -Not -Match 'Remove-ItemProperty'
            $content | Should -Not -Match 'New-ItemProperty'
            $content | Should -Not -Match 'sc\.exe'
        }
    }

    Context 'Header names the folder that exists and the launcher key that opens it' {
        It '<Name>.ps1 declares Tier: Safe (read-only)' -ForEach $script:InfoCases {
            $path = Get-ToolkitScriptPath $Relative
            (Get-Content -Raw -LiteralPath $path) | Should -Match 'Tier:\s*Safe \(read-only\)'
        }
        It '<Name>.ps1 tells the user to open launcher <LauncherKey>' -ForEach $script:InfoCases {
            $path = Get-ToolkitScriptPath $Relative
            $content = Get-Content -Raw -LiteralPath $path
            $content.Contains("Run from the launcher $LauncherKey submenu") | Should -BeTrue
            $content.Contains($Folder) | Should -BeTrue
        }
        It '<Name>.ps1 does not point at Backup [1], Network [7], or a missing upstream folder' -ForEach $script:InfoCases {
            $path = Get-ToolkitScriptPath $Relative
            $content = Get-Content -Raw -LiteralPath $path
            $content | Should -Not -Match 'launcher \[1\]'
            $content | Should -Not -Match 'launcher \[7\]'
            $content | Should -Not -Match '(?i)seed script'
            $content | Should -Not -Match '1 Check/'
            $content | Should -Not -Match '7 Hardware/'
            $content | Should -Not -Match '(?i)Future scripts'
        }
    }

    Context 'show-mouse-info points at the polling audit that already exists' {
        It 'names check-input-polling.ps1 and drops the unshipped polling scripts' {
            $path = Get-ToolkitScriptPath '12 hardware/show-mouse-info.ps1'
            $content = Get-Content -Raw -LiteralPath $path
            $content | Should -Match 'check-input-polling\.ps1'
            $content | Should -Not -Match 'check-mouse-polling'
            $content | Should -Not -Match 'check-controller-polling'
            $content | Should -Not -Match 'check-bufferbloat'
        }
    }
}
