#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract tests for 6 gpu/force-rebar.ps1 + disable-rebar.ps1.

.NOTES
    Same shape as tests/7-network/rss-tuning.Tests.ps1: parse, mutator
    surface, cross-script parity, header contract. ReBAR tracks state
    through the manifest (Set-ToolkitRegistryValue / Restore-ToolkitRegistryValue),
    not a sidecar file.

    Verify: static only. Code-complete, runtime-pending — these tests do
    not write HwUMAEnable or reboot a Windows host. MANUAL-TEST-CHECKLIST.md
    remains the runtime gate.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:Force = Get-ToolkitScriptPath '6 gpu/force-rebar.ps1'
    $script:Disable = Get-ToolkitScriptPath '6 gpu/disable-rebar.ps1'
    $script:ForceContent = Get-Content -Raw -LiteralPath $script:Force
    $script:DisableContent = Get-Content -Raw -LiteralPath $script:Disable
    $script:ApplyEverything = Get-Content -Raw -LiteralPath (Get-ToolkitScriptPath 'APPLY-EVERYTHING.ps1')
}

Describe 'ReBAR script pair' {

    Context 'File health' {
        It 'force parses' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:Force, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }
        It 'disable parses' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:Disable, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'Mutator surface' {
        It 'force self-checks admin' {
            (Test-ToolkitAdminCheck -Path $script:Force).Passes | Should -BeTrue
        }
        It 'disable self-checks admin' {
            (Test-ToolkitAdminCheck -Path $script:Disable).Passes | Should -BeTrue
        }
        It 'force routes HwUMAEnable through Set-ToolkitRegistryValue' {
            # Script-level SupportsShouldProcess is not declared. The repo
            # ShouldProcess invariant accepts this helper as the gate.
            $script:ForceContent | Should -Match 'Set-ToolkitRegistryValue'
            $script:ForceContent | Should -Match '-Name\s+"HwUMAEnable"'
            $script:ForceContent | Should -Match '-Value\s+1'
            $script:ForceContent | Should -Match '-Type\s+"DWord"'
        }
        It 'disable restores through Restore-ToolkitRegistryValue' {
            $script:DisableContent | Should -Match 'Restore-ToolkitRegistryValue\s+-Id\s+\$id'
        }
        It 'force resolves adapters via Get-GpuVendor' {
            $script:ForceContent | Should -Match 'gpu-detection\.ps1'
            $script:ForceContent | Should -Match 'Get-GpuVendor'
        }
    }

    Context 'Manifest id parity' {
        It 'force and disable agree on the GpuHwUMAEnable id stem' {
            $filter = [regex]::Match($script:DisableContent, '-like\s+"(reg:GpuHwUMAEnable:[^"]*)"')
            $filter.Success | Should -BeTrue
            $stem = $filter.Groups[1].Value.TrimEnd('*')
            $script:ForceContent | Should -Match ([regex]::Escape($stem))
            # A device-qualified id must satisfy the disable filter.
            ('reg:GpuHwUMAEnable:PCI\VEN_10DE&DEV_2684') -like $filter.Groups[1].Value | Should -BeTrue
        }
        It 'force records step gpu-rebar at tier Advanced' {
            $script:ForceContent | Should -Match '-Tier\s+"Advanced"'
            $script:ForceContent | Should -Match '-Step\s+"gpu-rebar"'
            $script:ForceContent | Should -Match '-Key\s+"gpu-rebar"'
        }
        It 'disable records step gpu-rebar-revert at tier Safe' {
            $script:DisableContent | Should -Match '-Key\s+"gpu-rebar-revert"'
            $script:DisableContent | Should -Match '-Tier\s+"Safe"'
        }
    }

    Context 'Opt-in and header' {
        It 'APPLY-EVERYTHING does not invoke the ReBAR pair' {
            $script:ApplyEverything | Should -Not -Match 'force-rebar\.ps1'
            $script:ApplyEverything | Should -Not -Match 'disable-rebar\.ps1'
        }
        It 'force header tier is Advanced and states no anti-cheat impact' {
            $script:ForceContent | Should -Match 'Tier:\s+Advanced'
            $script:ForceContent | Should -Match 'Anti-cheat impact:\s*NONE'
            $script:ForceContent | Should -Match 'Reboot required:'
            $script:ForceContent | Should -Match 'Disk impact:\s*NONE'
        }
        It 'disable header tier is Safe' {
            $script:DisableContent | Should -Match 'Tier:\s+Safe'
        }
        It 'pair names each other' {
            $script:ForceContent | Should -Match 'disable-rebar\.ps1'
            $script:DisableContent | Should -Match 'force-rebar\.ps1'
        }
    }
}
