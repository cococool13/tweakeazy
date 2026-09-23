# ============================================================
# Restore Debloat — reinstall apps removed by debloat.ps1
# Windows 11 Gaming Optimization Guide
# ============================================================
# Tier: Safe (reinstalls Microsoft-published apps)
#
# Reads state.packages.removed and state.packages.provisionedRemoved
# from the manifest and reinstalls each package via the Appx-to-winget
# map in lib/debloat-catalog.ps1. Appx names are not winget ids
# (Microsoft.549981C3F5F10, MicrosoftTeams, and the rest of the
# catalog). Unmapped names are not passed to winget --id; the script
# prints a Store search URL instead.
#
# Pair with: debloat.ps1
# Must be run as Administrator (winget Appx scope often needs elevation
# for provisioned packages and per-machine reinstalls).
# ============================================================

. "$PSScriptRoot\..\lib\toolkit-state.ps1"
. "$PSScriptRoot\..\lib\ui-helpers.ps1"
. "$PSScriptRoot\..\lib\debloat-catalog.ps1"

$Host.UI.RawUI.WindowTitle = "Gaming Optimization — Restore Debloat"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Restore Debloat — Reinstall Removed Apps" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

UI-RequireAdmin -ScriptName "Restore Debloat"

# winget is required. If absent (older Win10 image, Server, stripped ISO),
# the script still prints the list and the Microsoft Store fallback URLs
# so the user can recover manually.
$wingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
if (-not $wingetAvailable) {
    Write-Host "  [WARN] winget not found on PATH." -ForegroundColor Yellow
    Write-Host "         Reinstall is best-effort: this script will print the list" -ForegroundColor Yellow
    Write-Host "         of removed apps and Microsoft Store search URLs, but won't" -ForegroundColor Yellow
    Write-Host "         install them automatically. Install App Installer from the" -ForegroundColor Yellow
    Write-Host "         Microsoft Store and re-run for automation." -ForegroundColor Yellow
    Write-Host ""
}

$state = Get-ToolkitState
if (-not $state) {
    Write-Host "  No manifest found at $(Get-ToolkitManifestPath)" -ForegroundColor Yellow
    Write-Host "  Nothing to restore — debloat.ps1 hasn't been run, or the manifest" -ForegroundColor Yellow
    Write-Host "  was wiped. Open Microsoft Store and search by name for any app" -ForegroundColor Yellow
    Write-Host "  you want back." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 0
}

$removed = @()
$provisioned = @()
if ($state.PSObject.Properties["packages"] -and $state.packages) {
    if ($state.packages.PSObject.Properties["removed"]) {
        $removed = @($state.packages.removed | Where-Object { $_ })
    }
    if ($state.packages.PSObject.Properties["provisionedRemoved"]) {
        $provisioned = @($state.packages.provisionedRemoved | Where-Object { $_ })
    }
}

# Merge — provisioned removals that aren't also in the user-removed list
# still need reinstall surface; treat the union as the work queue.
$work = @()
foreach ($name in $removed) { if ($work -notcontains $name) { $work += $name } }
foreach ($name in $provisioned) { if ($work -notcontains $name) { $work += $name } }

if ($work.Count -eq 0) {
    Write-Host "  No packages recorded as removed in the manifest." -ForegroundColor Green
    Write-Host "  Nothing to restore." -ForegroundColor Green
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 0
}

Write-Host "  Packages recorded as removed: $($work.Count)" -ForegroundColor Yellow
foreach ($name in $work) {
    Write-Host "    - $name" -ForegroundColor White
}
Write-Host ""
Write-Host "  Press Ctrl+C to cancel, or" -ForegroundColor Yellow
Read-Host "  Press Enter to continue"
Write-Host ""

$installed = 0
$failed = 0
$current = 0
foreach ($name in $work) {
    $current++
    $resolved = Resolve-ToolkitDebloatWingetId -PackageName $name
    if (-not $resolved) {
        $url = "ms-windows-store://search/?query=$([Uri]::EscapeDataString($name))"
        Write-Host "  [$current/$($work.Count)] $name" -ForegroundColor White
        Write-Host "      No winget id mapped. Not passed to winget --id." -ForegroundColor Yellow
        Write-Host "      Open: $url" -ForegroundColor DarkGray
        $failed++
        continue
    }

    if ($resolved.Source -eq 'msstore') {
        $storeUrl = "ms-windows-store://pdp/?ProductId=$($resolved.Id)"
    } else {
        $storeUrl = "ms-windows-store://search/?query=$([Uri]::EscapeDataString($resolved.Id))"
    }

    if (-not $wingetAvailable) {
        Write-Host "  [$current/$($work.Count)] $name -> $($resolved.Id)" -ForegroundColor White
        Write-Host "      Open: $storeUrl" -ForegroundColor DarkGray
        $failed++
        continue
    }

    Write-Host "  [$current/$($work.Count)] winget install --id $($resolved.Id) ($name)..." -NoNewline -ForegroundColor Gray
    # Discard stdout/stderr; we make the success/failure decision off
    # $LASTEXITCODE alone. Capture suppressed for cleaner console output.
    & winget install --exact --id $resolved.Id --source $resolved.Source --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host " Installed" -ForegroundColor Green
        $installed++
    } else {
        Write-Host " Failed (exit $LASTEXITCODE)" -ForegroundColor Yellow
        Write-Host "      Try Microsoft Store: $storeUrl" -ForegroundColor DarkGray
        $failed++
    }
}

Add-ToolkitStepResult -Key "debloat-restore" -Tier "Safe" -Status "applied" `
    -Reason "Reinstalled $installed of $($work.Count) recorded packages"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  RESTORE COMPLETE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Installed:  $installed" -ForegroundColor Green
Write-Host "  Not installed: $failed" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Notes:" -ForegroundColor Gray
Write-Host "    - winget --id comes from lib/debloat-catalog.ps1, not the Appx name." -ForegroundColor Gray
Write-Host "    - winget will only reinstall the per-user package. Provisioned" -ForegroundColor Gray
Write-Host "      (per-image) reinstall requires the original Windows install media" -ForegroundColor Gray
Write-Host "      or signing into a fresh Microsoft account." -ForegroundColor Gray
Write-Host "    - Apps that failed via winget can be found by searching the" -ForegroundColor Gray
Write-Host "      Microsoft Store by name." -ForegroundColor Gray
Write-Host ""
Read-Host "Press Enter to exit"
