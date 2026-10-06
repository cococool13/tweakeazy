<#
.SYNOPSIS
    Disable Hardware-Accelerated GPU Scheduling (HAGS) by setting
    HwSchMode = 1 — the canonical "OS scheduler" value.

.DESCRIPTION
    Counterpart to enable-hags.ps1. Restores the OS-side GPU scheduler
    by writing HwSchMode = 1 (the documented "OS scheduler" value,
    distinct from "missing key" which Windows treats as default-on
    on most modern GPUs).

    No -Experimental flag required — disabling HAGS is the safer
    direction and matches what the user gets on a fresh Windows
    install where HwSchMode isn't set.

    The manifest entry from enable-hags.ps1 is preserved for an
    exact-prior-value restore via REVERT-EVERYTHING.ps1. This script
    instead writes the canonical-off value so the change is
    immediate and the user doesn't need to know about manifest state.

    Anti-cheat impact: NONE.
    Reboot required: SEE-SCRIPT — heuristic-default; refine in follow-up.
    Disk impact: NONE — registry-only write; no on-disk file creation.

.NOTES
    Tier: Safe (returns OS to scheduler-managed GPU work)
    Pair: enable-hags.ps1
    Microsoft Learn:
      https://learn.microsoft.com/en-us/windows-hardware/drivers/display/hardware-accelerated-gpu-scheduling
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param()

. "$PSScriptRoot\..\..\lib\toolkit-state.ps1"
. "$PSScriptRoot\..\..\lib\ui-helpers.ps1"

$Host.UI.RawUI.WindowTitle = 'Disable HAGS'
UI-Header -Title 'Disable Hardware-Accelerated GPU Scheduling' -Subtitle 'HwSchMode = 1 (OS scheduler)'
UI-RequireAdmin -ScriptName 'Disable HAGS'

Initialize-ToolkitState | Out-Null
UI-ResetCounters

if (-not $PSCmdlet.ShouldProcess('HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\HwSchMode', 'Set to 1 (HAGS disabled)')) {
    UI-Skip -Label 'Disable HAGS' -Reason '-WhatIf preview'
    UI-Exit
    exit 0
}

UI-Step -Label 'Setting HwSchMode = 1 (HAGS disabled)' -Action {
    # Shared id with Apply and GPU configure. Do not invent nv:/amd:/intel:.
    Set-ToolkitRegistryValue `
        -Id 'reg:HwSchMode' `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' `
        -Name 'HwSchMode' `
        -Value 1 -Type 'DWord' `
        -Tier 'Safe' -Step 'hags'
    Add-ToolkitStepResult -Key 'reg:HwSchMode' -Tier 'Safe' -Status 'applied' `
        -Reason 'HAGS disabled via HwSchMode=1'
}

UI-Summary -DoneMessage 'HAGS disabled' -Details @(
    'REBOOT REQUIRED for the GPU scheduler change to take effect.',
    'If you want it back, run enable-hags.ps1 -Experimental.'
) -RevertHint 'Run enable-hags.ps1 -Experimental in this folder.'
UI-Exit
