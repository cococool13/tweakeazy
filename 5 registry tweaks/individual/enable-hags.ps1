<#
.SYNOPSIS
    [EXPERIMENTAL] Enable Hardware-Accelerated GPU Scheduling (HAGS)
    by setting HwSchMode = 2. Requires explicit -Experimental flag.

.DESCRIPTION
    Hardware-Accelerated GPU Scheduling moves frame-submission and
    memory-management work from the OS/driver layer onto a dedicated
    GPU-side scheduler. The intent is lower latency and reduced CPU
    overhead — and on many systems that's what you get.

    ### Case FOR HAGS ###
      - Lower frame-time variance in CPU-bound games on older CPUs
        (the OS scheduler isn't on the critical path every frame)
      - Slightly lower input latency in DX12/Vulkan titles
      - Required for AutoHDR + Variable Refresh Rate combinations on
        some hardware (without HAGS the OS falls back to a slower
        composition path)
      - Some titles (Halo Infinite, Forza Horizon 5) post-launch
        patches list HAGS as recommended

    ### Case AGAINST HAGS — 24H2 / 25H2 regression reports ###
      - Win11 24H2 (build 26100+) introduced WDDM scheduler changes
        that interact poorly with HAGS on multiple NVIDIA driver
        branches (566.x, 572.x, 576.x). Symptoms: increased frame-
        time variance, stutter in fullscreen exclusive games,
        occasional DPC latency spikes.
      - Win11 25H2 (build 26200+) carries the same WDDM scheduler
        changes — fixes promised but not yet shipped as of this
        writing.
      - Some users report TDR (Timeout Detection & Recovery) events
        more frequently with HAGS on 24H2+ versus off.

    Whether HAGS helps or hurts on YOUR rig is empirical. Test with
    a frame-time logger (CapFrameX, PresentMon) before and after.
    Don't trust a flag on a forum post.

    ### Gating ###
    Because the 24H2+ regression reports are credible and unresolved,
    this script refuses to run without an explicit -Experimental
    switch. Passing -Experimental signals "I read the description
    and I'm going to A/B test this — please make the change."

    Anti-cheat impact: NONE. HAGS is a kernel scheduler feature
    Reboot required: SEE-SCRIPT — heuristic-default; refine in follow-up.
    Disk impact: NONE — registry-only write; no on-disk file creation.
    Microsoft built into Windows itself; anti-cheats don't inspect
    HwSchMode and there are no reports of false positives. Safe on
    R6 Siege / Valorant / EAC / BE.

.PARAMETER Experimental
    REQUIRED. Confirms the user has read the 24H2/25H2 regression
    notes and accepts the risk. Without it the script no-ops with
    a message pointing back to this help block.

.NOTES
    Tier: Advanced (kernel scheduler change; reversible)
    Pair: disable-hags.ps1
    Microsoft Learn:
      https://learn.microsoft.com/en-us/windows-hardware/drivers/display/hardware-accelerated-gpu-scheduling
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [switch]$Experimental
)

. "$PSScriptRoot\..\..\lib\toolkit-state.ps1"
. "$PSScriptRoot\..\..\lib\ui-helpers.ps1"

$Host.UI.RawUI.WindowTitle = 'Enable HAGS [Experimental]'
UI-Header -Title 'Enable Hardware-Accelerated GPU Scheduling' -Subtitle '[EXPERIMENTAL] HwSchMode = 2'
UI-RequireAdmin -ScriptName 'Enable HAGS'

if (-not $Experimental) {
    UI-Note -Message '[GATE] -Experimental flag required.' -Color $script:UI_Warning
    UI-Note -Message '       Win11 24H2 (26100+) and 25H2 (26200+) have unresolved HAGS'
    UI-Note -Message '       regression reports on multiple NVIDIA driver branches.'
    UI-Note -Message '       Read the .DESCRIPTION block (Get-Help enable-hags.ps1 -Full)'
    UI-Note -Message '       then re-run with: .\enable-hags.ps1 -Experimental'
    UI-Exit
    exit 1
}

Initialize-ToolkitState | Out-Null
UI-ResetCounters

if (-not $PSCmdlet.ShouldProcess('HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\HwSchMode', 'Set to 2 (HAGS enabled)')) {
    UI-Skip -Label 'Enable HAGS' -Reason '-WhatIf preview'
    UI-Exit
    exit 0
}

UI-Step -Label 'Setting HwSchMode = 2 (HAGS enabled)' -Action {
    # Shared id with Apply and GPU configure. Do not invent nv:/amd:/intel:.
    Set-ToolkitRegistryValue `
        -Id 'reg:HwSchMode' `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' `
        -Name 'HwSchMode' `
        -Value 2 -Type 'DWord' `
        -Tier 'Advanced' -Step 'hags'
    Add-ToolkitStepResult -Key 'reg:HwSchMode' -Tier 'Advanced' -Status 'applied' `
        -Reason '[EXPERIMENTAL] HAGS enabled via HwSchMode=2'
}

UI-Summary -DoneMessage 'HAGS enabled (EXPERIMENTAL)' -Details @(
    'REBOOT REQUIRED for the GPU scheduler to switch over.',
    'After reboot, test 2-3 of your games with a frame-time logger.',
    'If frame pacing or stutter regresses, run disable-hags.ps1.'
) -RevertHint 'Run disable-hags.ps1 in this folder, or REVERT-EVERYTHING.ps1.'
UI-Exit
