# ============================================================
# Windows 11 Debloat Script (Smart)
# Windows 11 Gaming Optimization Guide
# ============================================================
# Tier: Safe (for the default app set) / Advanced (Xbox App)
#
# Removes pre-installed bloatware apps that waste resources.
# Shows what will be removed with confirmation before acting.
# Records all removals in state.packages.removed and
# state.packages.provisionedRemoved for audit trail and revert.
#
# Pair: restore-debloat.ps1 reads the manifest and reinstalls
# recorded packages via the Appx-to-winget map in
# lib/debloat-catalog.ps1. Provisioned (per-image) reinstall
# typically needs the original Windows install media; winget covers
# the per-user reinstall path.
#
# The removal list is that same catalog (shared with Apply All).
# Provisioned removals are recorded only after
# Remove-AppxProvisionedPackage succeeds.
#
# Replaces: debloat.ps1 (dumb version)
# Must be run as Administrator.
# ============================================================

. "$PSScriptRoot\..\lib\toolkit-state.ps1"
. "$PSScriptRoot\..\lib\debloat-catalog.ps1"

$Host.UI.RawUI.WindowTitle = "Gaming Optimization — Debloat"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Windows 11 Debloat — Remove Bloatware Apps" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Initialize-ToolkitState | Out-Null
$stepName = "debloat"

# Shared with Apply All. Do not keep a second list in this file.
$appsToRemove = @(Get-ToolkitDebloatCatalog)
$neverRemove = @(Get-ToolkitDebloatNeverRemove)

# ============================================================
# Scan installed apps
# ============================================================
Write-Host "  Scanning installed apps..." -ForegroundColor Gray
Write-Host ""

$toRemove = @()
$alreadyGone = @()

foreach ($app in $appsToRemove) {
    # Defense in depth: enforce the safety list at scan time. Curated
    # $appsToRemove should never include $neverRemove entries, but if it
    # does (typo, future PR mistake), skip rather than remove a protected
    # app. Clears PSUseDeclaredVarsMoreThanAssignments by actually using
    # the list it advertises.
    if ($neverRemove -contains $app.Name) {
        Write-Host "  [SAFETY] Skipping $($app.Name) (in NEVER-REMOVE list)" -ForegroundColor Red
        continue
    }
    $package = Get-AppxPackage -Name $app.Name -ErrorAction SilentlyContinue
    if ($package) {
        $toRemove += $app
    } else {
        $alreadyGone += $app
    }
}

if ($alreadyGone.Count -gt 0) {
    Write-Host "  Already removed ($($alreadyGone.Count)):" -ForegroundColor Gray
    foreach ($app in $alreadyGone) {
        Write-Host "    [GONE] $($app.Description)" -ForegroundColor DarkGreen
    }
    Write-Host ""
}

if ($toRemove.Count -eq 0) {
    Write-Host "  All bloatware already removed. Nothing to do." -ForegroundColor Green
    Add-ToolkitStepResult -Key $stepName -Tier "Safe" -Status "preexisting" -Reason "All bloatware already removed"
    Read-Host "Press Enter to exit"
    exit 0
}

# ============================================================
# Show confirmation with categorization
# ============================================================
$safeApps = @($toRemove | Where-Object { $_.Tier -eq "Safe" })
$advancedApps = @($toRemove | Where-Object { $_.Tier -eq "Advanced" })

Write-Host "  Will remove ($($toRemove.Count) apps):" -ForegroundColor Yellow
Write-Host ""

if ($safeApps.Count -gt 0) {
    Write-Host "  Safe to remove:" -ForegroundColor Green
    foreach ($app in $safeApps) {
        Write-Host "    $($app.Description) ($($app.Name))" -ForegroundColor White
    }
}

if ($advancedApps.Count -gt 0) {
    Write-Host ""
    Write-Host "  Advanced (review carefully):" -ForegroundColor Yellow
    foreach ($app in $advancedApps) {
        Write-Host "    $($app.Description) ($($app.Name))" -ForegroundColor Yellow
        if ($app.Name -eq "Microsoft.GamingApp") {
            Write-Host "      ^ Only remove if NOT using Xbox Game Pass" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "  Protected apps (NEVER removed):" -ForegroundColor DarkGray
Write-Host "    Calculator, Photos, Snipping Tool, Paint, Notepad," -ForegroundColor DarkGray
Write-Host "    Terminal, Store, winget" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Press Ctrl+C to cancel, or" -ForegroundColor Yellow
Read-Host "  Press Enter to continue"
Write-Host ""

# ============================================================
# Remove apps
# ============================================================
$removed = 0
$skipped = 0
$current = 0

foreach ($app in $toRemove) {
    $current++
    Write-Host "  [$current/$($toRemove.Count)] $($app.Description)..." -NoNewline
    $userResult = Invoke-ToolkitDebloatRemoval -PackageName $app.Name -Scope User
    if ($userResult.Protected) {
        Write-Host " Skipped (protected)" -ForegroundColor Red
        continue
    }
    if ($userResult.Absent) {
        Write-Host " Already gone" -ForegroundColor Gray
        continue
    }
    if ($userResult.Removed -gt 0) {
        Write-Host " Removed" -ForegroundColor Green
        $removed++
    } else {
        Write-Host " Failed (may need Store)" -ForegroundColor Yellow
        $skipped++
    }
}

# ============================================================
# Remove provisioned packages (prevents reinstall on new users)
# ============================================================
Write-Host ""
Write-Host "  Removing provisioned packages..." -ForegroundColor Gray

$provRemoved = 0
$provSkipped = 0
foreach ($app in $toRemove) {
    # Records state.packages.provisionedRemoved only after a successful remove.
    $provResult = Invoke-ToolkitDebloatRemoval -PackageName $app.Name -Scope Provisioned
    if ($provResult.Protected) { continue }
    $provRemoved += $provResult.Removed
    $provSkipped += $provResult.Failed
}

if ($provRemoved -gt 0) {
    Write-Host "  Removed $provRemoved provisioned packages" -ForegroundColor Green
}
if ($provSkipped -gt 0) {
    Write-Host "  Skipped $provSkipped provisioned packages" -ForegroundColor Yellow
}

Add-ToolkitStepResult -Key $stepName -Tier "Safe" -Status "applied" `
    -Reason "Removed $removed apps, $provRemoved provisioned, $skipped failed"

# ============================================================
# Summary
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  DEBLOAT COMPLETE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Removed:      $removed apps" -ForegroundColor Green
Write-Host "  Provisioned:  $provRemoved (prevents reinstall)" -ForegroundColor Green
if ($skipped -gt 0) {
    Write-Host "  Skipped:      $skipped apps (manual removal needed)" -ForegroundColor Yellow
}
Write-Host "  Already gone: $($alreadyGone.Count) apps" -ForegroundColor Gray
Write-Host ""
Write-Host "  Removals recorded in manifest for audit trail." -ForegroundColor Gray
Write-Host "  To reinstall: run restore-debloat.ps1 (winget-driven, reads manifest)." -ForegroundColor Gray
Write-Host "  Or open Microsoft Store and search by name for any individual app." -ForegroundColor Gray
Write-Host ""
Read-Host "Press Enter to continue"
