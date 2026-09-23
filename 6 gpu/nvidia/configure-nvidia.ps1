# ============================================================
# NVIDIA GPU — Hidden Performance Settings
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
# Anti-cheat impact: NONE — NVIDIA driver registry values at the
# adapter's Display Class GUID subkey; not inspected by BattlEye /
# EAC / Vanguard. Same surface NVIDIA Control Panel writes.
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
    Write-Host "  [ERROR] configure-nvidia.ps1 must be run as Administrator." -ForegroundColor Red
    Write-Host "  Re-launch PowerShell as Admin or invoke via 6 gpu\install-gpu-driver.ps1." -ForegroundColor Red
    Write-Host ""
    exit 1
}

. "$PSScriptRoot\..\..\lib\toolkit-state.ps1"
. "$PSScriptRoot\..\..\lib\gpu-detection.ps1"

$stepName = "gpu-nvidia-settings"

function Apply-NvidiaAdapterSettings {
    param([Parameter(Mandatory)][string]$AdapterPath)

    Write-Host "  Applying adapter-level settings..." -ForegroundColor Cyan

    # Disable HDCP (reduces overhead in non-DRM scenarios)
    Set-ToolkitRegistryValue -Id "nv:RMHdcpKeyglobZero" `
        -Path $AdapterPath -Name "RMHdcpKeyglobZero" `
        -Value 1 -Type "DWord" -Tier "Advanced" -Step $stepName

    # Per-core DPC processing (reduces DPC latency on multi-core CPUs)
    Set-ToolkitRegistryValue -Id "nv:RmGpsPsEnablePerCpuCoreDpc" `
        -Path $AdapterPath -Name "RmGpsPsEnablePerCpuCoreDpc" `
        -Value 1 -Type "DWord" -Tier "Advanced" -Step $stepName

    # Disable preemptive context switching for lower latency
    Set-ToolkitRegistryValue -Id "nv:RmDisableGpuAsmScrubber" `
        -Path $AdapterPath -Name "RmDisableGpuAsmScrubber" `
        -Value 1 -Type "DWord" -Tier "Advanced" -Step $stepName
}

function Apply-NvidiaGlobalProfileSettings {
    Write-Host "  Applying global profile settings..." -ForegroundColor Cyan

    $nvGlobalPath = "HKLM:\SOFTWARE\NVIDIA Corporation\Global\NVTweak"

    # Power management: prefer maximum performance
    Set-ToolkitRegistryValue -Id "nv:Powermizer" `
        -Path $nvGlobalPath -Name "Powermizer" `
        -Value 1 -Type "DWord" -Tier "Advanced" -Step $stepName
}

function Apply-Nvidia3DSettings {
    Write-Host "  Applying 3D / driver profile settings..." -ForegroundColor Cyan

    $nvProfilePath = "HKCU:\SOFTWARE\NVIDIA Corporation\Global\NVTweak"

    # Threaded optimization: on (1 = on, 0 = off, 2 = auto)
    Set-ToolkitRegistryValue -Id "nv:ThreadedOptimization" `
        -Path $nvProfilePath -Name "ThreadedOptimization" `
        -Value 1 -Type "DWord" -Tier "Advanced" -Step $stepName
}

function Apply-NvidiaDriverSettings {
    <#
    .SYNOPSIS
        Applies NVIDIA driver-wide settings via NVIDIA profile registry keys.
        These mirror what NVIDIA Profile Inspector (NPI) sets.
    #>
    Write-Host "  Applying driver-wide performance settings..." -ForegroundColor Cyan

    $profileBase = "HKLM:\SOFTWARE\NVIDIA Corporation\Global\NVTweak"

    # Shader cache size: unlimited
    # Registry value 0x209746C1 = OGL_SHADER_DISK_CACHE_MAX_SIZE
    Set-ToolkitRegistryValue -Id "nv:ShaderCacheSize" `
        -Path $profileBase -Name "ShaderCacheSize" `
        -Value 0xFFFFFFFF -Type "DWord" -Tier "Advanced" -Step $stepName

    # CUDA P2 state: disable forced P2 (keeps GPU at P0 during compute)
    Set-ToolkitRegistryValue -Id "nv:CudaForceP2State" `
        -Path $profileBase -Name "CudaForceP2State" `
        -Value 0 -Type "DWord" -Tier "Advanced" -Step $stepName
}

function Apply-NvidiaSystemSettings {
    Write-Host "  Applying system-level GPU settings..." -ForegroundColor Cyan

    $graphicsDriversPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"

    # Hardware Accelerated GPU Scheduling (HAGS).
    # One registry value. Capture-once is per manifest id, so a vendor
    # id (nv:HwSchMode) stores the post-apply value 2 as the original
    # when Apply or enable-hags already wrote it. Track only reg:HwSchMode.
    # Rollback is REVERT-EVERYTHING / the hags pair, not revert-nvidia.ps1.
    Set-ToolkitRegistryValue -Id "reg:HwSchMode" `
        -Path $graphicsDriversPath -Name "HwSchMode" `
        -Value 2 -Type "DWord" -Tier "Advanced" -Step $stepName

    # Disable NVIDIA telemetry reporting via registry
    $telemetryPath = "HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client"
    Set-ToolkitRegistryValue -Id "nv:OptInOrOutPreference" `
        -Path $telemetryPath -Name "OptInOrOutPreference" `
        -Value 0 -Type "DWord" -Tier "Advanced" -Step $stepName
}

# --- Execute ---
try {
    Initialize-ToolkitState | Out-Null
    $gpu = Get-GpuVendor | Where-Object { $_.Vendor -eq "nvidia" } | Select-Object -First 1
    if (-not $gpu) {
        throw "No NVIDIA GPU detected"
    }

    if (-not $gpu.AdapterRegistryPath) {
        throw "Could not resolve NVIDIA adapter registry path for: $($gpu.FriendlyName)"
    }

    Write-Host ""
    Write-Host "Configuring NVIDIA GPU: $($gpu.FriendlyName)" -ForegroundColor Green
    Write-Host "Adapter path: $($gpu.AdapterRegistryPath)" -ForegroundColor Gray
    Write-Host ""

    # Check ReBAR status
    $rebarStatus = Test-ReBarEnabled -AdapterRegistryPath $gpu.AdapterRegistryPath
    if ($rebarStatus -eq $false) {
        Write-Host "  [WARNING] Resizable BAR (ReBAR) appears DISABLED." -ForegroundColor Yellow
        Write-Host "  Enable it in BIOS for better performance. See BIOS-CHECKLIST.md." -ForegroundColor Yellow
        Write-Host ""
    } elseif ($rebarStatus -eq $true) {
        Write-Host "  ReBAR: Enabled" -ForegroundColor Green
    }

    Apply-NvidiaAdapterSettings -AdapterPath $gpu.AdapterRegistryPath
    Apply-NvidiaGlobalProfileSettings
    Apply-Nvidia3DSettings
    Apply-NvidiaDriverSettings
    Apply-NvidiaSystemSettings

    Add-ToolkitStepResult -Key $stepName -Tier "Advanced" -Status "applied" -Reason "NVIDIA hidden performance settings"
    Write-Host ""
    Write-Host "NVIDIA performance settings applied." -ForegroundColor Green

} catch {
    Add-ToolkitStepResult -Key $stepName -Tier "Advanced" -Status "failed" -Reason $_.Exception.Message
    throw
}
