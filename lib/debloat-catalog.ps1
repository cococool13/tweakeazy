# ============================================================
# Shared debloat catalog — one Appx list and one winget map
# Windows 11 Gaming Optimization Guide
# ============================================================
# Tier: Safe (catalog data) / Advanced (Xbox App row)
#
# Single removal list for:
#   9 cleanup/debloat.ps1
#   APPLY-EVERYTHING.ps1 Phase 13
#   11 hardware checks/check-uwp-apps.ps1 (read-only flags)
#
# WingetId is the value passed to `winget install --exact --id`.
# It is not the Appx package name. Inbox apps use the Microsoft
# Store product id (source msstore). Personal Teams is the
# exception: Appx name MicrosoftTeams maps to winget id
# Microsoft.Teams.Free (PackageFamilyName
# MicrosoftTeams_8wekyb3d8bbwe). Cortana's Appx name
# Microsoft.549981C3F5F10 maps to store id 9NFFX4SZZ23L.
#
# Invoke-ToolkitDebloatRemoval records a package only after the
# matching Remove-Appx* call returns. A failed provisioned remove
# must not land in state.packages.provisionedRemoved.
#
# Callers that remove packages must dot-source lib/toolkit-state.ps1
# first so Record-ToolkitPackageRemoval exists.
# ============================================================

$script:ToolkitDebloatNeverRemove = @(
    'Microsoft.WindowsStore'
    'Microsoft.WindowsTerminal'
    'Microsoft.WindowsCalculator'
    'Microsoft.Windows.Photos'
    'Microsoft.ScreenSketch'
    'Microsoft.Paint'
    'Microsoft.WindowsNotepad'
    'Microsoft.DesktopAppInstaller'
)

# Name = Appx package name (Get-AppxPackage -Name / manifest key).
# WingetId = winget --id. WingetSource = winget --source.
$script:ToolkitDebloatCatalog = @(
    @{ Name = 'Clipchamp.Clipchamp'; Description = 'Clipchamp Video Editor'; Tier = 'Safe'; WingetId = '9P1J8S7CCWWT'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.BingNews'; Description = 'Bing News'; Tier = 'Safe'; WingetId = '9WZDNCRFHVFW'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.BingWeather'; Description = 'Bing Weather'; Tier = 'Safe'; WingetId = '9WZDNCRFJ3Q2'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.GetHelp'; Description = 'Get Help'; Tier = 'Safe'; WingetId = '9PKDZBMV1H3T'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.Getstarted'; Description = 'Tips'; Tier = 'Safe'; WingetId = '9WZDNCRDTBJJ'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.MicrosoftOfficeHub'; Description = 'Office Hub'; Tier = 'Safe'; WingetId = '9WZDNCRD29V9'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.MicrosoftSolitaireCollection'; Description = 'Solitaire Collection'; Tier = 'Safe'; WingetId = '9WZDNCRFHWD2'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.MicrosoftStickyNotes'; Description = 'Sticky Notes'; Tier = 'Safe'; WingetId = '9NBLGGH4QGHW'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.People'; Description = 'People'; Tier = 'Safe'; WingetId = '9NBLGGH10PG8'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.PowerAutomateDesktop'; Description = 'Power Automate'; Tier = 'Safe'; WingetId = '9NFTCH6J7FHV'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.Todos'; Description = 'Microsoft To Do'; Tier = 'Safe'; WingetId = '9NBLGGH5R558'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.WindowsAlarms'; Description = 'Alarms & Clock'; Tier = 'Safe'; WingetId = '9WZDNCRFJ3PR'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.WindowsFeedbackHub'; Description = 'Feedback Hub'; Tier = 'Safe'; WingetId = '9NBLGGH4R32N'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.WindowsMaps'; Description = 'Maps'; Tier = 'Safe'; WingetId = '9WZDNCRDTBVB'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.WindowsSoundRecorder'; Description = 'Sound Recorder'; Tier = 'Safe'; WingetId = '9WZDNCRFHWKN'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.YourPhone'; Description = 'Phone Link'; Tier = 'Safe'; WingetId = '9NMPJ99VJBWV'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.ZuneMusic'; Description = 'Groove Music / Media Player'; Tier = 'Safe'; WingetId = '9WZDNCRFJ3PT'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.ZuneVideo'; Description = 'Movies & TV'; Tier = 'Safe'; WingetId = '9WZDNCRFJ3P2'; WingetSource = 'msstore' }
    @{ Name = 'MicrosoftCorporationII.QuickAssist'; Description = 'Quick Assist'; Tier = 'Safe'; WingetId = '9P7BP5VNWKX5'; WingetSource = 'msstore' }
    @{ Name = 'MicrosoftTeams'; Description = 'Teams (personal)'; Tier = 'Safe'; WingetId = 'Microsoft.Teams.Free'; WingetSource = 'winget' }
    @{ Name = 'Microsoft.549981C3F5F10'; Description = 'Cortana'; Tier = 'Safe'; WingetId = '9NFFX4SZZ23L'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.OutlookForWindows'; Description = 'Outlook for Windows'; Tier = 'Safe'; WingetId = '9NRX63209R7B'; WingetSource = 'msstore' }
    @{ Name = 'Microsoft.GamingApp'; Description = 'Xbox App'; Tier = 'Advanced'; WingetId = '9MV0B5HZVK9Z'; WingetSource = 'msstore' }
)

function Get-ToolkitDebloatCatalog {
    <#
    .SYNOPSIS
        Return the shared debloat app list (Appx name, tier, winget id).
    #>
    [CmdletBinding()]
    param()

    $rows = @()
    foreach ($app in $script:ToolkitDebloatCatalog) {
        $rows += [PSCustomObject]@{
            Name = [string]$app.Name
            Description = [string]$app.Description
            Tier = [string]$app.Tier
            WingetId = [string]$app.WingetId
            WingetSource = [string]$app.WingetSource
        }
    }
    return $rows
}

function Get-ToolkitDebloatNeverRemove {
    <#
    .SYNOPSIS
        Return Appx names debloat must never remove.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    foreach ($name in $script:ToolkitDebloatNeverRemove) {
        $name
    }
}

function Resolve-ToolkitDebloatWingetId {
    <#
    .SYNOPSIS
        Map a recorded Appx package name to its winget id and source.
    .DESCRIPTION
        Returns $null when the name is not in the catalog. Callers must
        not pass the Appx name to winget --id as a fallback.
    .OUTPUTS
        PSCustomObject with PackageName, Id, Source — or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$PackageName
    )

    if ([string]::IsNullOrWhiteSpace($PackageName)) {
        return $null
    }

    foreach ($app in $script:ToolkitDebloatCatalog) {
        if ($app.Name -eq $PackageName) {
            return [PSCustomObject]@{
                PackageName = [string]$app.Name
                Id = [string]$app.WingetId
                Source = [string]$app.WingetSource
            }
        }
    }

    return $null
}

function Invoke-ToolkitDebloatRemoval {
    <#
    .SYNOPSIS
        Remove one Appx package for the current user or from the image.
    .DESCRIPTION
        Records the removal only after Remove-AppxPackage or
        Remove-AppxProvisionedPackage succeeds. Names on the
        never-remove list are not touched and are not recorded.
    .OUTPUTS
        PSCustomObject with Removed, Failed, Absent, Protected counts/flags.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [ValidateSet('User', 'Provisioned')]
        [string]$Scope
    )

    $result = [PSCustomObject]@{
        PackageName = $PackageName
        Scope = $Scope
        Removed = 0
        Failed = 0
        Absent = $false
        Protected = $false
    }

    if ($script:ToolkitDebloatNeverRemove -contains $PackageName) {
        $result.Protected = $true
        return $result
    }

    if ($Scope -eq 'User') {
        $packages = @(Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)
        if ($packages.Count -eq 0) {
            $result.Absent = $true
            return $result
        }
        try {
            $packages | Remove-AppxPackage -ErrorAction Stop
            Record-ToolkitPackageRemoval -PackageName $PackageName
            $result.Removed = 1
        } catch {
            $result.Failed = 1
        }
        return $result
    }

    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $PackageName })
    if ($provisioned.Count -eq 0) {
        $result.Absent = $true
        return $result
    }

    foreach ($prov in $provisioned) {
        try {
            # DISM removes by the full PackageName, not the Appx DisplayName.
            # A missing name is a failed remove and must not be recorded.
            $fullName = [string]$prov.PackageName
            if ([string]::IsNullOrWhiteSpace($fullName)) {
                throw 'Provisioned package is missing PackageName'
            }
            Remove-AppxProvisionedPackage -Online -PackageName $fullName -ErrorAction Stop | Out-Null
            Record-ToolkitPackageRemoval -PackageName $PackageName -Provisioned
            $result.Removed++
        } catch {
            $result.Failed++
        }
    }

    return $result
}
