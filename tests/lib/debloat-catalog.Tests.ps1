#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Shared debloat catalog: one list, an Appx-to-winget map, and
    provisioned-removal recording only after success.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')

    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        function Get-AppxPackage {
            [CmdletBinding()]
            param([string]$Name)
        }
    }
    if (-not (Get-Command Get-AppxProvisionedPackage -ErrorAction SilentlyContinue)) {
        function Get-AppxProvisionedPackage {
            [CmdletBinding()]
            param([switch]$Online)
        }
    }
    if (-not (Get-Command Remove-AppxPackage -ErrorAction SilentlyContinue)) {
        function Remove-AppxPackage {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test stub so Pester can Mock the Windows-only cmdlet.')]
            [CmdletBinding()]
            param(
                [Parameter(ValueFromPipeline = $true)]
                $InputObject
            )
            process { }
        }
    }
    if (-not (Get-Command Remove-AppxProvisionedPackage -ErrorAction SilentlyContinue)) {
        function Remove-AppxProvisionedPackage {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test stub so Pester can Mock the Windows-only cmdlet.')]
            [CmdletBinding()]
            param(
                [Parameter(ValueFromPipeline = $true)]
                $InputObject,
                [switch]$Online
            )
            process { }
        }
    }
    if (-not (Get-Command Record-ToolkitPackageRemoval -ErrorAction SilentlyContinue)) {
        function Record-ToolkitPackageRemoval {
            [CmdletBinding()]
            param(
                [string]$PackageName,
                [switch]$Provisioned
            )
        }
    }

    . (Join-Path $PSScriptRoot '..' '..' 'lib' 'debloat-catalog.ps1')

    $script:Catalog = @(Get-ToolkitDebloatCatalog)
    $script:NeverRemove = @(Get-ToolkitDebloatNeverRemove)
    $script:RestorePath = Get-ToolkitScriptPath '9 cleanup/restore-debloat.ps1'
    $script:Restore = Get-Content -Raw -LiteralPath $script:RestorePath
}

Describe 'lib/debloat-catalog.ps1 — one shared list' {

    It 'includes both names the two old lists disagreed on' {
        $names = @($script:Catalog | ForEach-Object Name)
        $names | Should -Contain 'Microsoft.GamingApp'
        $names | Should -Contain 'Microsoft.OutlookForWindows'
    }

    It 'has unique Appx names' {
        $names = @($script:Catalog | ForEach-Object Name)
        $names.Count | Should -Be @($names | Select-Object -Unique).Count
    }

    It 'uses only Safe and Advanced tiers' {
        $tiers = @($script:Catalog | ForEach-Object Tier | Select-Object -Unique)
        foreach ($tier in $tiers) {
            $tier | Should -BeIn @('Safe', 'Advanced')
        }
    }

    It 'does not list a never-remove package' {
        foreach ($name in $script:NeverRemove) {
            $script:Catalog.Name | Should -Not -Contain $name
        }
    }

    It 'keeps Store, winget, Photos, Calculator, and Terminal protected' {
        $script:NeverRemove | Should -Contain 'Microsoft.WindowsStore'
        $script:NeverRemove | Should -Contain 'Microsoft.DesktopAppInstaller'
        $script:NeverRemove | Should -Contain 'Microsoft.Windows.Photos'
        $script:NeverRemove | Should -Contain 'Microsoft.WindowsCalculator'
        $script:NeverRemove | Should -Contain 'Microsoft.WindowsTerminal'
    }
}

Describe 'lib/debloat-catalog.ps1 — Appx-to-winget map' {

    It 'maps every catalog row to a winget id that is not the Appx name' {
        foreach ($app in $script:Catalog) {
            $resolved = Resolve-ToolkitDebloatWingetId -PackageName $app.Name
            $resolved | Should -Not -BeNullOrEmpty
            $resolved.Id | Should -Be $app.WingetId
            $resolved.Id | Should -Not -Be $app.Name
            $resolved.Source | Should -BeIn @('msstore', 'winget')
        }
    }

    It 'maps Cortana off the Appx name Microsoft.549981C3F5F10' {
        $resolved = Resolve-ToolkitDebloatWingetId -PackageName 'Microsoft.549981C3F5F10'
        $resolved.Id | Should -Be '9NFFX4SZZ23L'
        $resolved.Source | Should -Be 'msstore'
    }

    It 'maps personal Teams off the Appx name MicrosoftTeams' {
        $resolved = Resolve-ToolkitDebloatWingetId -PackageName 'MicrosoftTeams'
        $resolved.Id | Should -Be 'Microsoft.Teams.Free'
        $resolved.Source | Should -Be 'winget'
    }

    It 'returns null for an unmapped name so callers cannot pass it to winget --id' {
        Resolve-ToolkitDebloatWingetId -PackageName 'Microsoft.WindowsStore' | Should -BeNullOrEmpty
        Resolve-ToolkitDebloatWingetId -PackageName 'Not.A.Real.Package' | Should -BeNullOrEmpty
        Resolve-ToolkitDebloatWingetId -PackageName '' | Should -BeNullOrEmpty
    }

    It 'restore-debloat.ps1 installs the mapped id, not the Appx name' {
        $script:Restore | Should -Match 'Resolve-ToolkitDebloatWingetId'
        $script:Restore | Should -Match 'winget install --exact --id \$resolved\.Id --source \$resolved\.Source'
        $script:Restore | Should -Not -Match 'winget install --exact --id \$name'
    }
}

Describe 'lib/debloat-catalog.ps1 — record provisioned removal only after success' {

    It 'does not remove or record a never-remove name' {
        Mock Get-AppxPackage { throw 'protected names must not be queried' }
        Mock Record-ToolkitPackageRemoval { throw 'protected names must not be recorded' }
        $result = Invoke-ToolkitDebloatRemoval -PackageName 'Microsoft.WindowsStore' -Scope Provisioned
        $result.Protected | Should -BeTrue
        $result.Removed | Should -Be 0
        $result.Failed | Should -Be 0
    }

    It 'records a user removal only after Remove-AppxPackage succeeds' {
        Mock Get-AppxPackage { [PSCustomObject]@{ Name = 'Microsoft.BingNews' } }
        Mock Remove-AppxPackage { }
        Mock Record-ToolkitPackageRemoval { }
        $result = Invoke-ToolkitDebloatRemoval -PackageName 'Microsoft.BingNews' -Scope User
        $result.Removed | Should -Be 1
        $result.Failed | Should -Be 0
        Should -Invoke Record-ToolkitPackageRemoval -Times 1 -ParameterFilter {
            $PackageName -eq 'Microsoft.BingNews' -and -not $Provisioned
        }
    }

    It 'does not record a user removal when Remove-AppxPackage fails' {
        Mock Get-AppxPackage { [PSCustomObject]@{ Name = 'Microsoft.BingNews' } }
        Mock Remove-AppxPackage { throw 'remove failed' }
        Mock Record-ToolkitPackageRemoval { }
        $result = Invoke-ToolkitDebloatRemoval -PackageName 'Microsoft.BingNews' -Scope User
        $result.Removed | Should -Be 0
        $result.Failed | Should -Be 1
        Should -Invoke Record-ToolkitPackageRemoval -Times 0
    }

    It 'records a provisioned removal only after Remove-AppxProvisionedPackage succeeds' {
        Mock Get-AppxProvisionedPackage {
            [PSCustomObject]@{ DisplayName = 'Microsoft.BingNews' }
        }
        Mock Remove-AppxProvisionedPackage { }
        Mock Record-ToolkitPackageRemoval { }
        $result = Invoke-ToolkitDebloatRemoval -PackageName 'Microsoft.BingNews' -Scope Provisioned
        $result.Removed | Should -Be 1
        $result.Failed | Should -Be 0
        Should -Invoke Record-ToolkitPackageRemoval -Times 1 -ParameterFilter {
            $PackageName -eq 'Microsoft.BingNews' -and $Provisioned
        }
    }

    It 'does not record a provisioned removal when Remove-AppxProvisionedPackage fails' {
        Mock Get-AppxProvisionedPackage {
            [PSCustomObject]@{ DisplayName = 'Microsoft.OutlookForWindows' }
        }
        Mock Remove-AppxProvisionedPackage { throw 'provisioned remove failed' }
        Mock Record-ToolkitPackageRemoval { }
        $result = Invoke-ToolkitDebloatRemoval -PackageName 'Microsoft.OutlookForWindows' -Scope Provisioned
        $result.Removed | Should -Be 0
        $result.Failed | Should -Be 1
        Should -Invoke Record-ToolkitPackageRemoval -Times 0
    }

    It 'records only the provisioned packages that actually came off' {
        Mock Get-AppxProvisionedPackage {
            @(
                [PSCustomObject]@{ DisplayName = 'Microsoft.GamingApp' }
                [PSCustomObject]@{ DisplayName = 'Microsoft.GamingApp' }
            )
        }
        $script:ProvisionedAttempts = 0
        Mock Remove-AppxProvisionedPackage {
            $script:ProvisionedAttempts++
            if ($script:ProvisionedAttempts -gt 1) {
                throw 'second provisioned package failed'
            }
        }
        Mock Record-ToolkitPackageRemoval { }
        $result = Invoke-ToolkitDebloatRemoval -PackageName 'Microsoft.GamingApp' -Scope Provisioned
        $result.Removed | Should -Be 1
        $result.Failed | Should -Be 1
        Should -Invoke Record-ToolkitPackageRemoval -Times 1 -ParameterFilter { $Provisioned }
    }
}
