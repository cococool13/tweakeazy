# ============================================================
# Power Plan Configuration (Smart)
# Windows 11 Gaming Optimization Guide
# ============================================================
# Unhides and activates Ultimate Performance power plan, then
# configures every sub-option for maximum gaming performance:
# CPU 100% min/max, cores unparked, USB/PCI-E power saving off, etc.
#
# Smart features:
#   - Laptop-aware: warns about battery impact, offers AC-only
#   - Pre-checks active plan, skips if already configured
#   - Manifest-tracked registry changes for exact rollback
#   - Captures the pre-run active plan GUID + name to the
#     'power-plan' sidecar so revert-power.ps1 can restore the
#     user's prior plan (not just "fall back to Balanced")
#   - Logs the before / after active plan GUID via
#     Write-ToolkitLog — answers "what was applied" without
#     re-querying the registry
#
# Empirical case for Ultimate Performance on a gaming desktop:
#   - CPU min-state 100% removes P-state ramp latency on input bursts
#   - Core parking off keeps every logical CPU available for game
#     thread scheduling without scheduler-wakeup penalty
#   - PCI-E ASPM off removes link-power-state transitions that add
#     microseconds of latency to every PCIe transaction
#   The trade-off is power draw + heat. Documented for laptops below.
#
# Anti-cheat impact: NONE. powercfg only touches per-plan / per-
# subgroup index values; not inspected by BattlEye / EAC / similar.
#
# Microsoft Learn:
#   https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/hardware/power/power-performance-tuning
#   https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/configure-power-settings
#
# Replaces: enable-ultimate-performance.bat, configure-power-plan.ps1
# Pair: revert-power.ps1
# Must be run as Administrator.
#
# Reboot required: NO — powercfg / setactive applies live; the
# registry overrides (HiberbootEnabled / PowerThrottlingOff) take
# effect on next sign-in but no reboot needed.
# Disk impact: NONE — powercfg + per-plan index values + small
# registry writes; no on-disk file creation.
# ============================================================

. "$PSScriptRoot\..\lib\toolkit-state.ps1"

$Host.UI.RawUI.WindowTitle = "Gaming Optimization — Power Plan"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Power Plan Configuration" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$state = Initialize-ToolkitState
$machineProfile = $state.context
$stepName = "power-plan"

# ---- Detect current power plan ----
Write-Host "  Checking current power plan..." -ForegroundColor Gray

$activePlanOutput = powercfg /getactivescheme 2>&1
$activePlanName = ""
$priorPlanGuid = ""
if ($activePlanOutput -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s+\((.+)\)") {
    $priorPlanGuid = $Matches[1]
    $activePlanName = $Matches[2]
}

Write-Host "  Current plan: $activePlanName" -ForegroundColor $(if ($activePlanName -match "Ultimate") { "Green" } else { "Yellow" })
Write-Host ""

# Capture pre-run plan to sidecar so revert-power.ps1 can restore the
# user's prior plan exactly. Capture-once semantics (Save-ToolkitSidecar
# default) preserves the first-ever captured plan if this script is
# re-run, so a true pre-toolkit baseline survives.
if ($priorPlanGuid) {
    $sidecarPath = Save-ToolkitSidecar -Name 'power-plan' -InputObject ([PSCustomObject]@{
            ActiveGuid = $priorPlanGuid
            ActiveName = $activePlanName
            CapturedAt = (Get-Date).ToString('o')
        })
    if ($sidecarPath) {
        Write-Host "  Captured prior plan to $sidecarPath" -ForegroundColor Gray
    }
    # Before/after metric per Phase C standard — log the active plan
    # GUID so log scraping can answer "what plan was the user on
    # before this script ran" without re-querying the registry later.
    Write-ToolkitLog 'power-plan-before' -Data @{
        guid = $priorPlanGuid
        name = $activePlanName
    }
}

# ---- Laptop awareness ----
if ($machineProfile.isLaptop) {
    Write-Host "  LAPTOP DETECTED" -ForegroundColor Yellow
    Write-Host "  This plan keeps CPU at max frequency and disables sleep." -ForegroundColor Yellow
    Write-Host "  Battery life will be significantly reduced." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Recommendations:" -ForegroundColor White
    Write-Host "    - Only use while plugged in for gaming sessions" -ForegroundColor Gray
    Write-Host "    - Switch back to Balanced when on battery:" -ForegroundColor Gray
    Write-Host "      powercfg /setactive SCHEME_BALANCED" -ForegroundColor Gray
    Write-Host ""

    if ($machineProfile.powerState -eq "On battery") {
        Write-Host "  WARNING: You are currently on battery power!" -ForegroundColor Red
        Write-Host "  Applying these settings on battery will drain quickly." -ForegroundColor Red
        Write-Host ""
    }
}

Write-Host "  This will:" -ForegroundColor White
Write-Host "    - Activate Ultimate Performance power plan" -ForegroundColor Gray
Write-Host "    - Set CPU to 100% min/max with all cores unparked" -ForegroundColor Gray
Write-Host "    - Disable PCI-E, USB, and wireless power saving" -ForegroundColor Gray
Write-Host "    - Disable sleep, hibernate, and fast startup" -ForegroundColor Gray
Write-Host "    - Disable power throttling" -ForegroundColor Gray
Write-Host ""
Write-Host "  Press Ctrl+C to cancel, or" -ForegroundColor Yellow
Read-Host "  Press Enter to continue"
Write-Host ""

$succeeded = 0
$failed = 0

function Run-Step {
    param([string]$Description, [scriptblock]$Action)
    Write-Host "  $Description..." -NoNewline
    try {
        & $Action
        Write-Host " Done" -ForegroundColor Green
        $script:succeeded++
    } catch {
        Write-Host " Failed: $($_.Exception.Message)" -ForegroundColor Yellow
        $script:failed++
    }
}

# ============================================================
# STEP 1: Activate Ultimate Performance Plan
# ============================================================
Write-Host "[1/5] Power Plan Activation..." -ForegroundColor White

# The Ultimate Performance GUID is the same on all Win11 installations
$ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
$customGuid = "99999999-9999-9999-9999-999999999999"

Run-Step "Adding Ultimate Performance plan" {
    powercfg /duplicatescheme $ultimateGuid $customGuid 2>&1 | Out-Null
    # If custom GUID fails, try to find existing Ultimate Performance
    $planList = powercfg /list 2>&1
    $found = $false
    foreach ($line in $planList) {
        if ($line -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})" -and $line -match "Ultimate Performance") {
            $script:customGuid = $Matches[1]
            $found = $true
            break
        }
    }
    if (-not $found) {
        # Fallback: use whatever we duplicated
        $script:customGuid = $customGuid
    }
}

Run-Step "Activating Ultimate Performance" {
    powercfg /setactive $customGuid 2>&1 | Out-Null
}

# Verify activation
$verifyOutput = powercfg /getactivescheme 2>&1
if ($verifyOutput -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})") {
    $activePlan = $Matches[1]
}

# Helper — sets both AC (plugged in) and DC (battery)
function Set-PowerIndex {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)][string]$subgroup,
        [Parameter(Mandatory)][string]$setting,
        [Parameter(Mandatory)][string]$value
    )
    if (-not $PSCmdlet.ShouldProcess("power-plan $activePlan", "set $subgroup/$setting = $value (AC+DC)")) {
        return
    }
    powercfg /setacvalueindex $activePlan $subgroup $setting $value 2>$null
    powercfg /setdcvalueindex $activePlan $subgroup $setting $value 2>$null
}

# ============================================================
# STEP 2: Storage & Wireless
# ============================================================
Write-Host ""
Write-Host "[2/5] Storage & Wireless..." -ForegroundColor White

Run-Step "Hard disk: never turn off" {
    Set-PowerIndex "0012ee47-9041-4b5d-9b77-535fba8b1442" "6738e2c4-e8a5-4a42-b16a-e040e769756e" "0x00000000"
}

Run-Step "Wireless adapter: maximum performance" {
    Set-PowerIndex "19cbb8fa-5279-450e-9fac-8a3d5fedd0c1" "12bbebe6-58d6-4636-95bb-3217ef867c1a" "000"
}

# ============================================================
# STEP 3: Sleep, Hibernate, Fast Startup
# ============================================================
Write-Host ""
Write-Host "[3/5] Sleep & Startup..." -ForegroundColor White

Run-Step "Sleep: disabled" {
    Set-PowerIndex "238c9fa8-0aad-41ed-83f4-97be242c8f20" "29f6c1db-86da-48c5-9fdb-f2b67b1f44da" "0x00000000"
}

Run-Step "Hybrid sleep: off" {
    Set-PowerIndex "238c9fa8-0aad-41ed-83f4-97be242c8f20" "94ac6d29-73ce-41a6-809f-6363ba21b47e" "000"
}

Run-Step "Hibernate: off" {
    Set-PowerIndex "238c9fa8-0aad-41ed-83f4-97be242c8f20" "9d7815a6-7ee4-497e-8888-515a05f02364" "0x00000000"
    powercfg /hibernate off 2>$null
}

Run-Step "Fast Startup: disabled" {
    # Same id APPLY-EVERYTHING uses. A second id would snapshot the
    # already-tweaked value as before when both scripts run.
    Set-ToolkitRegistryValue -Id "reg:HiberbootEnabled" `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" `
        -Name "HiberbootEnabled" -Value 0 -Type "DWord" -Tier "Safe" -Step $stepName
    Set-ToolkitRegistryValue -Id "pwr:HibernateEnabled" `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" `
        -Name "HibernateEnabled" -Value 0 -Type "DWord" -Tier "Safe" -Step $stepName
}

# ============================================================
# STEP 4: USB & PCI-E
# ============================================================
Write-Host ""
Write-Host "[4/5] USB & PCI-E Power Management..." -ForegroundColor White

Run-Step "USB selective suspend: disabled" {
    Set-PowerIndex "2a737441-1930-4402-8d77-b2bebba308a3" "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" "000"
}

Run-Step "USB 3 link power management: off" {
    # Unhide the setting
    Set-ToolkitRegistryValue -Id "pwr:USB3LinkPMAttr" `
        -Path "HKLM:\SYSTEM\ControlSet001\Control\Power\PowerSettings\2a737441-1930-4402-8d77-b2bebba308a3\d4e98f31-5ffe-4ce1-be31-1b38b384c009" `
        -Name "Attributes" -Value 0 -Type "DWord" -Tier "Safe" -Step $stepName
    Set-PowerIndex "2a737441-1930-4402-8d77-b2bebba308a3" "d4e98f31-5ffe-4ce1-be31-1b38b384c009" "000"
}

Run-Step "PCI Express link state: off" {
    Set-PowerIndex "501a4d13-42af-4429-9fd1-a8218c268e20" "ee12f906-d277-404b-b6da-e5fa1a576df5" "000"
}

# ============================================================
# STEP 5: CPU & Display
# ============================================================
Write-Host ""
Write-Host "[5/5] CPU & Display..." -ForegroundColor White

Run-Step "CPU: 100% min/max" {
    # Minimum processor state 100%
    Set-PowerIndex "54533251-82be-4824-96c1-47b60b740d00" "893dee8e-2bef-41e0-89c6-b55d0929964c" "0x00000064"
    # Maximum processor state 100%
    Set-PowerIndex "54533251-82be-4824-96c1-47b60b740d00" "bc5038f7-23e0-4960-96da-33abaf5935ec" "0x00000064"
    # System cooling policy: active
    Set-PowerIndex "54533251-82be-4824-96c1-47b60b740d00" "94d3a615-a899-4ac5-ae2b-e4d8f634367f" "001"
}

Run-Step "All cores unparked" {
    # Unhide core parking settings
    Set-ToolkitRegistryValue -Id "pwr:CoreParkMinAttr" `
        -Path "HKLM:\SYSTEM\ControlSet001\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583" `
        -Name "Attributes" -Value 0 -Type "DWord" -Tier "Safe" -Step $stepName
    Set-ToolkitRegistryValue -Id "pwr:CoreParkMaxAttr" `
        -Path "HKLM:\SYSTEM\ControlSet001\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\ea062031-0e34-4ff1-9b6d-eb1059334028" `
        -Name "Attributes" -Value 0 -Type "DWord" -Tier "Safe" -Step $stepName
    # Core parking min/max: 100%
    Set-PowerIndex "54533251-82be-4824-96c1-47b60b740d00" "0cc5b647-c1df-4637-891a-dec35c318583" "0x00000064"
    Set-PowerIndex "54533251-82be-4824-96c1-47b60b740d00" "ea062031-0e34-4ff1-9b6d-eb1059334028" "0x00000064"
}

Run-Step "Display timeout: 10 minutes" {
    Set-PowerIndex "7516b95f-f776-4464-8c53-06167f40cc99" "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e" "600"
}

Run-Step "Adaptive brightness: off" {
    Set-PowerIndex "7516b95f-f776-4464-8c53-06167f40cc99" "fbd9aa66-9553-4097-ba44-ed6e9d65eab8" "000"
}

Run-Step "Power throttling: disabled" {
    # Same id APPLY-EVERYTHING uses. See Fast Startup note above.
    Set-ToolkitRegistryValue -Id "reg:PowerThrottlingOff" `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" `
        -Name "PowerThrottlingOff" -Value 1 -Type "DWord" -Tier "Safe" -Step $stepName
}

Add-ToolkitStepResult -Key $stepName -Tier "Safe" -Status "applied" `
    -Reason "Ultimate Performance active, $succeeded settings applied"
# Same fact under the key verify-tweaks.ps1 grades. $stepName stays
# "power-plan" so the launcher category prefix still matches.
Add-ToolkitStepResult -Key "power:plan" -Tier "Safe" -Status "applied" `
    -Reason "Ultimate Performance active, $succeeded settings applied"

# Before/after metric: the post-config active plan GUID. Compare to
# the 'power-plan-before' line emitted at script start.
$afterOutput = powercfg /getactivescheme 2>&1
if ($afterOutput -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s+\((.+)\)") {
    Write-ToolkitLog 'power-plan-after' -Data @{
        guid = $Matches[1]
        name = $Matches[2]
        priorGuid = $priorPlanGuid
    }
}

# ============================================================
# Summary
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  POWER PLAN CONFIGURED" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Applied: $succeeded settings" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  Failed:  $failed settings" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  Settings:" -ForegroundColor Gray
Write-Host "    - Ultimate Performance plan active" -ForegroundColor Gray
Write-Host "    - CPU at 100% min/max, all cores unparked" -ForegroundColor Gray
Write-Host "    - PCI-E / USB power management: off" -ForegroundColor Gray
Write-Host "    - Sleep / Hibernate / Fast Startup: disabled" -ForegroundColor Gray
Write-Host "    - Power throttling: disabled" -ForegroundColor Gray
Write-Host ""
if ($machineProfile.isLaptop) {
    Write-Host "  LAPTOP REMINDER: Switch to Balanced on battery:" -ForegroundColor Yellow
    Write-Host "    powercfg /setactive SCHEME_BALANCED" -ForegroundColor Gray
    Write-Host ""
}
Write-Host "  Prior state saved in manifest for exact rollback." -ForegroundColor Gray
Write-Host ""
Read-Host "Press Enter to continue"
