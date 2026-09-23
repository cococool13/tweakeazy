# ============================================================
# Revert NVIDIA Hidden Settings (Manifest-Driven)
# Windows 11 Gaming Optimization Guide
# ============================================================
# Tier: Advanced (reverts an Advanced-tier write)
#
# Pair with: configure-nvidia.ps1
# Restores every nv:* manifest entry written by configure-nvidia.ps1
# to its pre-toolkit value. Examples: nv:RMHdcpKeyglobZero, nv:Powermizer,
# nv:ThreadedOptimization, etc.
#
# HwSchMode is not in this sweep. It is one value tracked only as
# reg:HwSchMode. A retired nv:HwSchMode entry can store post-apply
# value 2 as the original; restoring it writes 2 back. REVERT-EVERYTHING
# (or the hags pair) owns that rollback.
#
# Must be run as Administrator.
# ============================================================

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  [ERROR] revert-nvidia.ps1 must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    exit 1
}

. "$PSScriptRoot\..\..\lib\toolkit-state.ps1"
. "$PSScriptRoot\..\..\lib\ui-helpers.ps1"

UI-Header -Title "Revert NVIDIA Settings" -Subtitle "Manifest-driven restore"

Initialize-ToolkitState | Out-Null
$state = Get-ToolkitState

$restored = 0
$skippedHwSch = $false
if ($state -and $state.PSObject.Properties["registry"] -and $state.registry) {
    $regKeys = @()
    if ($state.registry -is [hashtable]) {
        $regKeys = @($state.registry.Keys)
    } else {
        $regKeys = @($state.registry.PSObject.Properties.Name)
    }
    foreach ($id in $regKeys) {
        # Retired id. Do not write its captured "before" (often 2) back.
        if ($id -eq "nv:HwSchMode") { $skippedHwSch = $true; continue }
        if ($id -like "nv:*") {
            UI-Step -Label "Restoring $id" -Action {
                Restore-ToolkitRegistryValue -Id $id | Out-Null
            }
            $restored++
        }
    }
}

if ($skippedHwSch) {
    UI-Note -Message "Skipped retired nv:HwSchMode. HwSchMode rollback is reg:HwSchMode only." -Color $script:UI_Warning
}
if ($restored -eq 0) {
    UI-Note -Message "No NVIDIA settings found in manifest. Either configure-nvidia.ps1 was never run, or the manifest was wiped." -Color $script:UI_Warning
    Add-ToolkitStepResult -Key "gpu-nvidia-settings-revert" -Tier "Advanced" -Status "skipped" -Reason "No manifest entries"
} else {
    Add-ToolkitStepResult -Key "gpu-nvidia-settings-revert" -Tier "Advanced" -Status "applied" -Reason "Restored $restored NVIDIA settings"
}

UI-Summary -DoneMessage "NVIDIA settings reverted" -Details @(
    "Reboot for the NVIDIA driver to pick up the restored keys."
)
UI-Exit
