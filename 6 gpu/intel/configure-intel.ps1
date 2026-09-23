# ============================================================
# Intel GPU — Hidden Performance Settings
# Windows 11 Gaming Optimization Guide
# ============================================================
# Tier: Advanced
#
# Applies registry-based performance settings for competitive gaming.
# All changes tracked via Set-ToolkitRegistryValue for rollback.
#
# NOTE: ReBAR is CRITICAL for Intel Arc — 20-30% performance drop without it.
# This script checks and warns if ReBAR is disabled.
#
# Requires: lib/toolkit-state.ps1, lib/gpu-detection.ps1
# Called by: 6 gpu/install-gpu-driver.ps1 (which already verifies admin),
# but also safe to invoke standalone — admin self-check below ensures
# the script fails fast rather than producing cryptic Set-ItemProperty
# errors when run from a non-admin shell. (CLAUDE.md invariant #6)
#
# Anti-cheat impact: NONE — Intel driver registry values at the
# adapter's Display Class GUID subkey; not inspected by BattlEye /
# EAC / Vanguard. Same surface Intel's own Arc Control writes.
# Reboot required: SEE-SCRIPT — heuristic-default; refine in follow-up.
# Disk impact: NONE — registry / cmdlet only; no installer / file extraction.
# ============================================================

# CURSOR-AUDIT #6: explicit per-script admin gate. Inline rather than
# UI-RequireAdmin because the dot-source paths in this folder reach
# ..\lib\* (intentional sibling sourcing from install-gpu-driver.ps1's
# scope when invoked via &); going through ui-helpers.ps1 would require
# fixing those resolutions in a separate change.
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  [ERROR] configure-intel.ps1 must be run as Administrator." -ForegroundColor Red
    Write-Host "  Re-launch PowerShell as Admin or invoke via 6 gpu\install-gpu-driver.ps1." -ForegroundColor Red
    Write-Host ""
    exit 1
}

. "$PSScriptRoot\..\..\lib\toolkit-state.ps1"
. "$PSScriptRoot\..\..\lib\gpu-detection.ps1"

$stepName = "gpu-intel-settings"

function Apply-IntelAdapterSettings {
    param([Parameter(Mandatory)][string]$AdapterPath)

    Write-Host "  Applying Intel adapter-level settings..." -ForegroundColor Cyan

    # Disable VSync globally
    Set-ToolkitRegistryValue -Id "intel:VSyncControl" `
        -Path $AdapterPath -Name "VSyncControl" `
        -Value 0 -Type "DWord" -Tier "Advanced" -Step $stepName

    # Maximum performance power plan profile (2 = max perf)
    Set-ToolkitRegistryValue -Id "intel:PowerPlanProfile" `
        -Path $AdapterPath -Name "PowerPlanProfile" `
        -Value 2 -Type "DWord" -Tier "Advanced" -Step $stepName

    # Disable frame pacing (reduces input latency)
    Set-ToolkitRegistryValue -Id "intel:FramePacing" `
        -Path $AdapterPath -Name "FramePacing" `
        -Value 0 -Type "DWord" -Tier "Advanced" -Step $stepName

    # AC power policy: maximum performance
    Set-ToolkitRegistryValue -Id "intel:ACPowerPolicyVersion" `
        -Path $AdapterPath -Name "ACPowerPolicyVersion" `
        -Value 1 -Type "DWord" -Tier "Advanced" -Step $stepName

    # DC power policy: maximum performance (for laptops)
    Set-ToolkitRegistryValue -Id "intel:DCPowerPolicyVersion" `
        -Path $AdapterPath -Name "DCPowerPolicyVersion" `
        -Value 1 -Type "DWord" -Tier "Advanced" -Step $stepName
}

function Apply-IntelSystemSettings {
    Write-Host "  Applying system-level GPU settings..." -ForegroundColor Cyan

    $graphicsDriversPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"

    # Hardware Accelerated GPU Scheduling (HAGS).
    # One registry value. Capture-once is per manifest id, so a vendor
    # id (intel:HwSchMode) stores the post-apply value 2 as the original
    # when Apply or enable-hags already wrote it. Track only reg:HwSchMode.
    # Rollback is REVERT-EVERYTHING / the hags pair, not revert-intel.ps1.
    Set-ToolkitRegistryValue -Id "reg:HwSchMode" `
        -Path $graphicsDriversPath -Name "HwSchMode" `
        -Value 2 -Type "DWord" -Tier "Advanced" -Step $stepName
}

# --- Execute ---
try {
    Initialize-ToolkitState | Out-Null
    $gpu = Get-GpuVendor | Where-Object { $_.Vendor -eq "intel" } | Select-Object -First 1
    if (-not $gpu) {
        throw "No Intel GPU detected"
    }

    if (-not $gpu.AdapterRegistryPath) {
        throw "Could not resolve Intel adapter registry path for: $($gpu.FriendlyName)"
    }

    Write-Host ""
    Write-Host "Configuring Intel GPU: $($gpu.FriendlyName)" -ForegroundColor Green
    Write-Host "Adapter path: $($gpu.AdapterRegistryPath)" -ForegroundColor Gray
    Write-Host ""

    # ReBAR check — CRITICAL for Intel Arc
    $isArc = Test-IntelArcDevice -DeviceId $gpu.DeviceId
    $rebarStatus = Test-ReBarEnabled -AdapterRegistryPath $gpu.AdapterRegistryPath

    if ($isArc) {
        Write-Host "  Intel Arc GPU detected. ReBAR is CRITICAL for performance." -ForegroundColor Yellow
        if ($rebarStatus -eq $false) {
            Write-Host ""
            Write-Host "  ============================================================" -ForegroundColor Red
            Write-Host "  WARNING: Resizable BAR (ReBAR) appears DISABLED!" -ForegroundColor Red
            Write-Host "  Intel Arc loses 20-30% performance without ReBAR." -ForegroundColor Red
            Write-Host "  Enable 'Above 4G Decoding' and 'Resizable BAR' in BIOS." -ForegroundColor Red
            Write-Host "  See BIOS-CHECKLIST.md for instructions." -ForegroundColor Red
            Write-Host "  ============================================================" -ForegroundColor Red
            Write-Host ""
            Add-ToolkitNote "Intel Arc: ReBAR appears disabled. Enable in BIOS for 20-30% more performance."
        } elseif ($rebarStatus -eq $true) {
            Write-Host "  ReBAR: Enabled" -ForegroundColor Green
        } else {
            Write-Host "  ReBAR: Could not determine status. Verify in BIOS." -ForegroundColor Yellow
        }
    }

    Apply-IntelAdapterSettings -AdapterPath $gpu.AdapterRegistryPath
    Apply-IntelSystemSettings

    Add-ToolkitStepResult -Key $stepName -Tier "Advanced" -Status "applied" -Reason "Intel hidden performance settings"
    Write-Host ""
    Write-Host "Intel performance settings applied." -ForegroundColor Green

} catch {
    Add-ToolkitStepResult -Key $stepName -Tier "Advanced" -Status "failed" -Reason $_.Exception.Message
    throw
}
