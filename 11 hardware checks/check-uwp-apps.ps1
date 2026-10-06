#Requires -Version 5.1
<#
.SYNOPSIS
    Audit installed UWP / Microsoft Store packages — report only.

.DESCRIPTION
    Read-only inventory of every Appx package currently installed for
    the running user. Companion to 9 cleanup/debloat.ps1's "report
    then decide" UX (the audit/check pattern from FR33THY/Ultimate
    that the prior session ported as a category seed).

    Output columns:
      Name           - PackageFamilyName (the stable id)
      DisplayName    - human-readable label (best-effort; some pkgs
                       only expose Name)
      Publisher      - signing identity
      InstallLocation- where files live (useful for size estimation)
      Status         - OK / Modified / Tampered
      OnDebloatList  - flagged ✓ if lib/debloat-catalog.ps1 would
                       remove this package (same list as debloat.ps1)
      OnSafetyList   - flagged ✓ if it's on the shared never-remove list

    Sort: -Sort Name|Publisher|Status. Default: Name.
    Filter: -OnlyDebloatCandidates limits to apps debloat.ps1 would
    touch (use this to preview what running debloat would do).

    Sources cited:
      Microsoft Learn — Get-AppxPackage
        https://learn.microsoft.com/en-us/powershell/module/appx/get-appxpackage
      Microsoft Learn — UWP app lifecycle
        https://learn.microsoft.com/en-us/windows/uwp/launch-resume/app-lifecycle

.PARAMETER Sort
    Column to sort by. Default: Name.

.PARAMETER OnlyDebloatCandidates
    Limit output to apps in the shared debloat catalog — preview
    what running debloat.ps1 with no edits would target.

.PARAMETER AsObject
    Emit raw PSCustomObject rows on the pipeline instead of formatted
    text. Use for piping into Export-Csv / Out-GridView.

.EXAMPLE
    PS> .\check-uwp-apps.ps1

.EXAMPLE
    PS> .\check-uwp-apps.ps1 -OnlyDebloatCandidates -Sort Publisher

.EXAMPLE
    PS> .\check-uwp-apps.ps1 -AsObject | Export-Csv -NoTypeInformation uwp.csv

.NOTES
    Author:   Win11 Gaming Toolkit
    Version:  1.0
    Tier:     Safe (read-only)

    # CROSS-PLATFORM-NOTE
    # Get-AppxPackage is Windows-only. On macOS the script exits with
    # code 2 after the cmdlet check, no output.

    Anti-cheat impact: NONE. Pure read.

    Exit codes:
      0  Report rendered successfully
      2  Get-AppxPackage unavailable (Server Core / Linux)
#>
[CmdletBinding()]
param(
    [ValidateSet('Name', 'Publisher', 'Status')]
    [string]$Sort = 'Name',
    [switch]$OnlyDebloatCandidates,
    [switch]$AsObject
)

. "$PSScriptRoot\..\lib\ui-helpers.ps1"
. "$PSScriptRoot\..\lib\debloat-catalog.ps1"

if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
    Write-Host '  [SKIP] Get-AppxPackage not available.' -ForegroundColor Yellow
    Write-Host '         Requires Windows; Server Core may strip Appx module.' -ForegroundColor Yellow
    exit 2
}

# Shared catalog — same list debloat.ps1 and Apply All remove.
$debloatList = @(Get-ToolkitDebloatCatalog | ForEach-Object { $_.Name })
$neverRemoveList = @(Get-ToolkitDebloatNeverRemove)

UI-Header -Title 'UWP / Appx package audit' -Subtitle 'Read-only inventory'

$packages = @(Get-AppxPackage)
$rows = foreach ($p in $packages) {
    [PSCustomObject]@{
        Name = $p.Name
        DisplayName = if ($p.Name) { $p.Name } else { '(none)' }
        Publisher = ($p.Publisher -replace 'CN=', '' -replace ',.*', '')
        InstallLocation = $p.InstallLocation
        Status = $p.Status
        OnDebloatList = if ($debloatList -contains $p.Name) { '✓' } else { '' }
        OnSafetyList = if ($neverRemoveList -contains $p.Name) { '✓' } else { '' }
    }
}

if ($OnlyDebloatCandidates) {
    $rows = @($rows | Where-Object { $_.OnDebloatList -eq '✓' })
}

$rows = @($rows | Sort-Object $Sort)

if ($AsObject) {
    $rows
} else {
    $rows | Format-Table -AutoSize Name, Publisher, OnDebloatList, OnSafetyList, Status |
        Out-String -Width 200 | Write-Host
    Write-Host ('  Total: {0} packages.  Debloat candidates: {1}.  Protected (never removed): {2}.' -f `
            $packages.Count,
        ($rows | Where-Object OnDebloatList -EQ '✓').Count,
        ($rows | Where-Object OnSafetyList -EQ '✓').Count) -ForegroundColor Gray
}
exit 0
