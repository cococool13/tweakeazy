# ============================================================
# AMD GPU — Hidden Performance Settings
# Windows 11 Gaming Optimization Guide
# ============================================================
# Tier: Advanced
#
# Applies registry-based performance settings for competitive gaming.
# All changes tracked via Set-ToolkitRegistryValue for rollback.
#
# Requires: lib/toolkit-state.ps1, lib/gpu-detection.ps1
# Called by: 6 gpu/install-gpu-driver.ps1 (which already verifies admin),
# but also safe to invoke standalone — admin self-check below ensures
# the script fails fast rather than producing cryptic Set-ItemProperty
# errors when run from a non-admin shell. (CLAUDE.md invariant #6)
#
# Anti-cheat impact: NONE — AMD driver registry values at the
# adapter's Display Class GUID subkey; not inspected by BattlEye /
# EAC / Vanguard. Same surface AMD's own Radeon Software writes.
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
    Write-Host "  [ERROR] configure-amd.ps1 must be run as Administrator." -ForegroundColor Red
    Write-Host "  Re-launch PowerShell as Admin or invoke via 6 gpu\install-gpu-driver.ps1." -ForegroundColor Red
    Write-Host ""
    exit 1
}

. "$PSScriptRoot\..\..\lib\toolkit-state.ps1"
. "$PSScriptRoot\..\..\lib\gpu-detection.ps1"

$stepName = "gpu-amd-settings"

function Apply-AmdAdapterSettings {
    param([Parameter(Mandatory)][string]$AdapterPath)

    Write-Host "  Applying AMD adapter-level settings..." -ForegroundColor Cyan

    # CURSOR-AUDIT #25: ULPS disable was previously duplicated here AND in
    # 6 gpu/configure-amd-ulps.ps1 (different manifest Ids; same target keys).
    # ULPS is now owned by configure-amd-ulps.ps1 (per-adapter Id format,
    # vendor-gated to AMD, paired revert at revert-amd-ulps.ps1). To get
    # ULPS off, run that script before or after this one.

    # Disable deep sleep clock gating — keeps GPU responsive
    Set-ToolkitRegistryValue -Id "amd:PP_SclkDeepSleepDisable" `
        -Path $AdapterPath -Name "PP_SclkDeepSleepDisable" `
        -Value 1 -Type "DWord" -Tier "Advanced" -Step $stepName

    # Disable DMA copy — reduces overhead
    Set-ToolkitRegistryValue -Id "amd:DisableDMACopy" `
        -Path $AdapterPath -Name "DisableDMACopy" `
        -Value 1 -Type "DWord" -Tier "Advanced" -Step $stepName

    # Enable block writes — better memory performance
    Set-ToolkitRegistryValue -Id "amd:DisableBlockWrite" `
        -Path $AdapterPath -Name "DisableBlockWrite" `
        -Value 0 -Type "DWord" -Tier "Advanced" -Step $stepName

    # Disable stutter mode — prevents micro-stuttering
    Set-ToolkitRegistryValue -Id "amd:StutterMode" `
        -Path $AdapterPath -Name "StutterMode" `
        -Value 0 -Type "DWord" -Tier "Advanced" -Step $stepName

    # Disable DRMDMA power gating — keeps GPU clocks stable
    Set-ToolkitRegistryValue -Id "amd:DisableDrmdmaPowerGating" `
        -Path $AdapterPath -Name "DisableDrmdmaPowerGating" `
        -Value 1 -Type "DWord" -Tier "Advanced" -Step $stepName

    # Disable power gating for consistent performance
    Set-ToolkitRegistryValue -Id "amd:EnableAspmL0s" `
        -Path $AdapterPath -Name "EnableAspmL0s" `
        -Value 0 -Type "DWord" -Tier "Advanced" -Step $stepName

    Set-ToolkitRegistryValue -Id "amd:EnableAspmL1" `
        -Path $AdapterPath -Name "EnableAspmL1" `
        -Value 0 -Type "DWord" -Tier "Advanced" -Step $stepName
}

function Apply-AmdSystemSettings {
    Write-Host "  Applying system-level GPU settings..." -ForegroundColor Cyan

    $graphicsDriversPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"

    # Hardware Accelerated GPU Scheduling (HAGS).
    # One registry value. Capture-once is per manifest id, so a vendor
    # id (amd:HwSchMode) stores the post-apply value 2 as the original
    # when Apply or enable-hags already wrote it. Track only reg:HwSchMode.
    # Rollback is REVERT-EVERYTHING / the hags pair, not revert-amd.ps1.
    Set-ToolkitRegistryValue -Id "reg:HwSchMode" `
        -Path $graphicsDriversPath -Name "HwSchMode" `
        -Value 2 -Type "DWord" -Tier "Advanced" -Step $stepName
}

# --- Execute ---
try {
    Initialize-ToolkitState | Out-Null
    $gpu = Get-GpuVendor | Where-Object { $_.Vendor -eq "amd" } | Select-Object -First 1
    if (-not $gpu) {
        throw "No AMD GPU detected"
    }

    if (-not $gpu.AdapterRegistryPath) {
        throw "Could not resolve AMD adapter registry path for: $($gpu.FriendlyName)"
    }

    Write-Host ""
    Write-Host "Configuring AMD GPU: $($gpu.FriendlyName)" -ForegroundColor Green
    Write-Host "Adapter path: $($gpu.AdapterRegistryPath)" -ForegroundColor Gray
    Write-Host ""

    # Check ReBAR / Smart Access Memory status
    $rebarStatus = Test-ReBarEnabled -AdapterRegistryPath $gpu.AdapterRegistryPath
    if ($rebarStatus -eq $false) {
        Write-Host "  [WARNING] Smart Access Memory (ReBAR) appears DISABLED." -ForegroundColor Yellow
        Write-Host "  Enable it in BIOS for better performance. See BIOS-CHECKLIST.md." -ForegroundColor Yellow
        Write-Host ""
    } elseif ($rebarStatus -eq $true) {
        Write-Host "  Smart Access Memory (ReBAR): Enabled" -ForegroundColor Green
    }

    Apply-AmdAdapterSettings -AdapterPath $gpu.AdapterRegistryPath
    Apply-AmdSystemSettings

    Add-ToolkitStepResult -Key $stepName -Tier "Advanced" -Status "applied" -Reason "AMD hidden performance settings"
    Write-Host ""
    Write-Host "AMD performance settings applied." -ForegroundColor Green

} catch {
    Add-ToolkitStepResult -Key $stepName -Tier "Advanced" -Status "failed" -Reason $_.Exception.Message
    throw
}
