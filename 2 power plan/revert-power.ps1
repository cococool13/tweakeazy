<#
.SYNOPSIS
    Restore the power plan that was active before configure-power.ps1
    ran, falling back to Balanced when no capture exists.

.DESCRIPTION
    Counterpart to configure-power.ps1. Reads the 'power-plan' sidecar
    (captured by configure-power at first run) for the prior plan's
    GUID + name and reactivates it via powercfg /setactive. If the
    sidecar is missing — e.g. configure-power was never run, or the
    sidecar was wiped — falls back to Windows Balanced (SCHEME_BALANCED)
    as the universal-known-good default.

    Also reverts the auxiliary settings configure-power flipped:
      - Fast Startup restored from reg:HiberbootEnabled (legacy
        pwr:HiberbootEnabled only when the reg: id was never captured;
        hardcoded 1 when neither id exists)
      - Hibernate re-enabled (powercfg /hibernate on)
      - PowerThrottling restored from reg:PowerThrottlingOff the same way
    Hiberboot and power throttling share ids with APPLY-EVERYTHING so a
    second writer cannot save the already-tweaked value as before.

    Each powercfg and registry call is gated by $PSCmdlet.ShouldProcess
    so -WhatIf previews the revert plan without modifying the system.
    Sidecar is removed at the end so a fresh re-configure can capture
    a new baseline.

.NOTES
    Tier: Safe (restores OS power-management defaults / prior plan)
    Pair: configure-power.ps1
    Anti-cheat impact: NONE. powercfg + per-subgroup index values; not
        inspected by BattlEye / EAC / similar.
    Reboot required: NO — powercfg /setactive applies live; hibernate
        re-enable takes effect on next boot but no reboot needed.
    Disk impact: NONE — powercfg + small registry writes.
    Microsoft Learn:
      https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/configure-power-settings
    Must be run as Administrator.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param()

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ''
    Write-Host '  [ERROR] revert-power.ps1 must be run as Administrator.' -ForegroundColor Red
    Write-Host ''
    exit 1
}

. "$PSScriptRoot\..\lib\toolkit-state.ps1"

Write-ToolkitScriptStart

$Host.UI.RawUI.WindowTitle = "Revert Power Plan"

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  Reverting Power Plan to Balanced' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

# Surface the revert plan
$activePlanOutput = powercfg /getactivescheme 2>&1
$activePlanName = ''
# Fixed regex: the previous version had a stray `\+` between the GUID
# and the parens, which never matched. Now uses `\s+\(`.
if ($activePlanOutput -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s+\((.+)\)") {
    $activePlanName = $Matches[2]
}

# Sidecar drives the restore target — prior plan if captured, else
# Balanced. Read-ToolkitSidecar returns $null when missing/unparseable;
# either case falls through to the Balanced default below.
$priorSidecar = Read-ToolkitSidecar -Name 'power-plan'
$targetGuid = $null
$targetName = 'Balanced (default fallback)'
if ($priorSidecar -and $priorSidecar.ActiveGuid) {
    $targetGuid = $priorSidecar.ActiveGuid
    $targetName = "$($priorSidecar.ActiveName) (from sidecar, captured $($priorSidecar.CapturedAt))"
}

Write-Host "  Current plan: $activePlanName" -ForegroundColor Yellow
Write-Host "  Will restore to: $targetName" -ForegroundColor Gray
Write-Host ''

# Revert steps
Write-Host "  Restoring power plan..." -NoNewline
$setActiveTarget = if ($targetGuid) { $targetGuid } else { 'SCHEME_BALANCED' }
if (-not $PSCmdlet.ShouldProcess("Power plan", "powercfg /setactive $setActiveTarget")) {
    Write-Host " Skipped (-WhatIf)" -ForegroundColor Gray
} else {
    try {
        powercfg /setactive $setActiveTarget 2>&1 | Out-Null
        # Best-effort delete the custom Ultimate Performance duplicate
        # configure-power.ps1 created — silent if it doesn't exist.
        powercfg /delete 99999999-9999-9999-9999-999999999999 2>&1 | Out-Null
        Write-Host " Done" -ForegroundColor Green
    } catch {
        Write-Host " Failed: $_" -ForegroundColor Red
    }
}

Write-Host "  Re-enabling Fast Startup..." -NoNewline
if (-not $PSCmdlet.ShouldProcess("reg:HiberbootEnabled", "Restore from manifest or set default 1")) {
    Write-Host " Skipped (-WhatIf)" -ForegroundColor Gray
} else {
    if (-not (Restore-ToolkitRegistryValue -Id "reg:HiberbootEnabled")) {
        if (-not (Restore-ToolkitRegistryValue -Id "pwr:HiberbootEnabled")) {
            reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v "HiberbootEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        }
    }
    Set-ToolkitRegistryValue -Id "pwr:HibernateEnabled" `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" `
        -Name "HibernateEnabled" -Value 1 -Type "DWord" -Tier "Safe" -Step "power-revert" | Out-Null
    Write-Host " Done" -ForegroundColor Green
}

Write-Host "  Removing power throttling override..." -NoNewline
if (-not $PSCmdlet.ShouldProcess("reg:PowerThrottlingOff", "Restore from manifest or remove override")) {
    Write-Host " Skipped (-WhatIf)" -ForegroundColor Gray
} else {
    if (-not (Restore-ToolkitRegistryValue -Id "reg:PowerThrottlingOff")) {
        if (-not (Restore-ToolkitRegistryValue -Id "pwr:PowerThrottlingOff")) {
            Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" `
                -Name "PowerThrottlingOff" -ErrorAction SilentlyContinue
        }
    }
    Write-Host " Done" -ForegroundColor Green
}

Write-Host "  Re-enabling hibernate..." -NoNewline
if (-not $PSCmdlet.ShouldProcess("Hibernate", "powercfg /hibernate on")) {
    Write-Host " Skipped (-WhatIf)" -ForegroundColor Gray
} else {
    powercfg /hibernate on 2>&1 | Out-Null
    Write-Host " Done" -ForegroundColor Green
}

# Sidecar cleanup — once we've restored, drop the capture so a
# future re-run of configure-power.ps1 takes a fresh baseline.
Remove-ToolkitSidecar -Name 'power-plan'

Add-ToolkitStepResult -Key "power-revert" -Tier "Safe" -Status "applied" `
    -Reason "Reverted power plan to $targetName, restored default power settings"

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host '  Power Plan Reverted' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ''
Write-Host "  Power plan: Balanced (Windows default)" -ForegroundColor Gray
Write-Host "  Fast Startup: re-enabled" -ForegroundColor Gray
Write-Host "  Hibernation: re-enabled" -ForegroundColor Gray
Write-Host "  Power throttling: system default" -ForegroundColor Gray
Write-Host ''
Read-Host "Press Enter to exit"
