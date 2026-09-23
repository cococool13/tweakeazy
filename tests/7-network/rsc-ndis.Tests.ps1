#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract tests for the RSC and NDIS coalescing script pairs.

.DESCRIPTION
    Same shape as tests/7-network/rss-tuning.Tests.ps1. Capture lives on
    the disable script and restore on the enable script (inverse of RSS,
    same direction as interrupt-moderation).
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:RscEnable = Get-ToolkitScriptPath '7 network/enable-rsc.ps1'
    $script:RscDisable = Get-ToolkitScriptPath '7 network/disable-rsc.ps1'
    $script:NdisEnable = Get-ToolkitScriptPath '7 network/enable-ndis-coalescing.ps1'
    $script:NdisDisable = Get-ToolkitScriptPath '7 network/disable-ndis-coalescing.ps1'
    $script:RscEnableContent = Get-Content -Raw -LiteralPath $script:RscEnable
    $script:RscDisableContent = Get-Content -Raw -LiteralPath $script:RscDisable
    $script:NdisEnableContent = Get-Content -Raw -LiteralPath $script:NdisEnable
    $script:NdisDisableContent = Get-Content -Raw -LiteralPath $script:NdisDisable
}

Describe 'RSC script pair' {

    Context 'File health' {
        It 'enable parses' {
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:RscEnable, [ref]$null, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }
        It 'disable parses' {
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:RscDisable, [ref]$null, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }
    }

    Context 'Mutator surface' {
        It 'enable supports ShouldProcess' {
            (Test-ToolkitParameterShape -Path $script:RscEnable -RequireShouldProcess).SupportsShouldProcess | Should -BeTrue
        }
        It 'disable supports ShouldProcess' {
            (Test-ToolkitParameterShape -Path $script:RscDisable -RequireShouldProcess).SupportsShouldProcess | Should -BeTrue
        }
        It 'enable self-checks admin' {
            (Test-ToolkitAdminCheck -Path $script:RscEnable).Passes | Should -BeTrue
        }
        It 'disable self-checks admin' {
            (Test-ToolkitAdminCheck -Path $script:RscDisable).Passes | Should -BeTrue
        }
    }

    Context 'Sidecar via lib helpers' {
        It 'disable uses Save-ToolkitSidecar -Name rsc-coalesce' {
            # Capture is on disable; enable restores. Inverse of the RSS pair.
            $script:RscDisableContent | Should -Match "Save-ToolkitSidecar\s+-Name\s+'rsc-coalesce'"
        }
        It 'enable reads via Read-ToolkitSidecar -Name rsc-coalesce' {
            $script:RscEnableContent | Should -Match "Read-ToolkitSidecar\s+-Name\s+'rsc-coalesce'"
        }
        It 'enable cleans up via Remove-ToolkitSidecar -Name rsc-coalesce' {
            $script:RscEnableContent | Should -Match "Remove-ToolkitSidecar\s+-Name\s+'rsc-coalesce'"
        }
        It 'enable+disable agree on the sidecar stem' {
            $disableMatch = [regex]::Match($script:RscDisableContent, "Save-ToolkitSidecar\s+-Name\s+'([^']+)'")
            $enableMatch = [regex]::Match($script:RscEnableContent, "Read-ToolkitSidecar\s+-Name\s+'([^']+)'")
            $disableMatch.Success | Should -BeTrue
            $enableMatch.Success | Should -BeTrue
            $disableMatch.Groups[1].Value | Should -Be $enableMatch.Groups[1].Value
        }
    }

    Context 'Microsoft Learn citation' {
        It 'enable cites Enable-NetAdapterRsc docs' {
            $script:RscEnableContent | Should -Match 'learn\.microsoft\.com.*Enable-NetAdapterRsc'
        }
    }

    Context 'Comment-based help' {
        It 'enable has SYNOPSIS / DESCRIPTION / NOTES' {
            # These scripts do not declare .EXAMPLE. RSS enable does.
            $h = Test-ToolkitCommentBasedHelp -Path $script:RscEnable
            $h.HasSynopsis | Should -BeTrue
            $h.HasDescription | Should -BeTrue
            $h.HasNotes | Should -BeTrue
        }
    }
}

Describe 'NDIS coalescing script pair' {

    Context 'File health' {
        It 'enable parses' {
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:NdisEnable, [ref]$null, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }
        It 'disable parses' {
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:NdisDisable, [ref]$null, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }
    }

    Context 'Mutator surface' {
        It 'enable supports ShouldProcess' {
            (Test-ToolkitParameterShape -Path $script:NdisEnable -RequireShouldProcess).SupportsShouldProcess | Should -BeTrue
        }
        It 'disable supports ShouldProcess' {
            (Test-ToolkitParameterShape -Path $script:NdisDisable -RequireShouldProcess).SupportsShouldProcess | Should -BeTrue
        }
        It 'enable self-checks admin' {
            (Test-ToolkitAdminCheck -Path $script:NdisEnable).Passes | Should -BeTrue
        }
        It 'disable self-checks admin' {
            (Test-ToolkitAdminCheck -Path $script:NdisDisable).Passes | Should -BeTrue
        }
    }

    Context 'Sidecar via lib helpers' {
        It 'disable uses Save-ToolkitSidecar -Name ndis-coalesce' {
            $script:NdisDisableContent | Should -Match "Save-ToolkitSidecar\s+-Name\s+'ndis-coalesce'"
        }
        It 'enable reads via Read-ToolkitSidecar -Name ndis-coalesce' {
            $script:NdisEnableContent | Should -Match "Read-ToolkitSidecar\s+-Name\s+'ndis-coalesce'"
        }
        It 'enable cleans up via Remove-ToolkitSidecar -Name ndis-coalesce' {
            $script:NdisEnableContent | Should -Match "Remove-ToolkitSidecar\s+-Name\s+'ndis-coalesce'"
        }
        It 'enable+disable agree on the sidecar stem' {
            $disableMatch = [regex]::Match($script:NdisDisableContent, "Save-ToolkitSidecar\s+-Name\s+'([^']+)'")
            $enableMatch = [regex]::Match($script:NdisEnableContent, "Read-ToolkitSidecar\s+-Name\s+'([^']+)'")
            $disableMatch.Success | Should -BeTrue
            $enableMatch.Success | Should -BeTrue
            $disableMatch.Groups[1].Value | Should -Be $enableMatch.Groups[1].Value
        }
    }

    Context 'Vendor property name coverage' {
        $vendorProperties = @(
            @{ Property = '*IRQCoalesce' }
            @{ Property = 'RxIrqMod' }
            @{ Property = 'TxIrqMod' }
            @{ Property = '*RxIrqCoalesce' }
        )
        It 'disable script searches for <Property>' -ForEach $vendorProperties {
            $script:NdisDisableContent | Should -Match ([regex]::Escape($Property))
        }
    }

    Context 'Microsoft Learn citation' {
        It 'disable cites Set-NetAdapterAdvancedProperty docs' {
            # Citation lives on the disable script. enable-ndis-coalescing.ps1 has no Learn URL.
            $script:NdisDisableContent | Should -Match 'learn\.microsoft\.com.*Set-NetAdapterAdvancedProperty'
        }
    }

    Context 'Comment-based help' {
        It 'enable has SYNOPSIS / DESCRIPTION / NOTES' {
            $h = Test-ToolkitCommentBasedHelp -Path $script:NdisEnable
            $h.HasSynopsis | Should -BeTrue
            $h.HasDescription | Should -BeTrue
            $h.HasNotes | Should -BeTrue
        }
    }
}
