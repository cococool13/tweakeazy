# ============================================================
# APPLY EVERYTHING — Aggressive Full-Stack Windows 11 Optimization
# ============================================================
#
# Applies the maximal supported tweak set in one run.
# Unsupported tweaks are skipped.
#
# What it does:
#   1. Creates a system restore point + registry backup
#   2. Enables and tunes Ultimate Performance
#   3. Automates Windows settings
#   4. Disables services aggressively
#   5. Applies registry tweaks
#   6. Disables startup bloat
#   7. Enables GPU MSI mode
#   8. Optimizes network + DNS
#   9. (opt-in) Suppresses Windows Update aggressively
#   10. (opt-in) Disables VBS / HVCI / LSA / Spectre / Meltdown
#   11. Applies Windows customization tweaks
#   12. Adds Defender exclusions
#   13. Removes bloatware apps
#   14. Cleans temp files
#
# Phases 9 and 10 are Security Trade-off tier and only run when
# -IncludeSecurityTradeoffs is passed. Default is OFF.
#
# Anti-cheat impact: COMPOSITE — depends on flags.
#   Default run (no flags): NONE. Service / registry / network tweaks
#       only; nothing reaches anti-cheat-inspected surfaces.
#   -IncludeSecurityTradeoffs: HIGH. Disables HVCI / VBS — R6 Siege
#       (BattlEye) and Valorant (Vanguard) WILL refuse to launch on
#       Win11 24H2+ until you re-enable via REVERT-EVERYTHING.ps1.
#       EAC (Apex, Fortnite) tolerates HVCI-off as of 2025 but the
#       vendors warn this may change.
#   See per-script "Anti-cheat impact:" lines for component details.
# Reboot required: SEE-SCRIPT — heuristic-default; refine in follow-up.
# Disk impact: NONE — registry / cmdlet only; no installer / file extraction.
#
# Undo: REVERT-EVERYTHING.ps1
# ============================================================

[CmdletBinding()]
param(
    # Run Phases 9 (Windows Update suppression) and 10 (VBS/HVCI/LSA/Spectre).
    # Default OFF per the v1.1 audit gate. Pass -IncludeSecurityTradeoffs to
    # opt in. Skipped phases are recorded in the manifest as "skipped".
    [switch]$IncludeSecurityTradeoffs
)

. "$PSScriptRoot\lib\toolkit-state.ps1"
. "$PSScriptRoot\lib\ui-helpers.ps1"
. "$PSScriptRoot\lib\gpu-detection.ps1"

$Host.UI.RawUI.WindowTitle = "Windows 11 Gaming Optimization — Apply Everything"
UI-Header -Title "Windows 11 Optimization" -Subtitle "Apply Everything - aggressive full-stack run"
UI-RequireAdmin -ScriptName "Apply Everything"

# Load existing manifest if present so re-runs do not wipe captured before-state.
# Set-ToolkitRegistryValue / Set-ToolkitServiceStartMode each guard against
# overwriting an existing entry's `before` block, so re-apply is idempotent.
$state = Initialize-ToolkitState
$machineProfile = $state.context

UI-ShowProfile -Profile $machineProfile
UI-Confirm -Message "This path applies every automatable tweak (Safe + Advanced)." -Warnings @(
    "Rollback is strongest where the manifest captured prior state.",
    "Use the launcher or GUIDE.md if you want a narrower path.",
    "Phases 9 (Windows Update) + 10 (VBS/HVCI/LSA/Spectre) are OFF by default; pass -IncludeSecurityTradeoffs to include them."
)

if ($IncludeSecurityTradeoffs) {
    UI-Confirm -Message "Security trade-offs are ENABLED for this run. Phase 9 (Windows Update suppression) and Phase 10 (VBS / HVCI / LSA / Spectre) will execute." -Warnings @(
        "ANTI-CHEAT: Disabling HVCI/VBS may break BattlEye and EAC on Win11 24H2+.",
        "Specifically, R6 Siege and other BattlEye titles may refuse to launch.",
        "Test your titles after reboot. Run REVERT-EVERYTHING.ps1 if anything breaks.",
        "Windows Update suppression stalls security/driver/anti-cheat patches. Plan to apply monthly updates manually."
    )
}

$startTime = Get-Date
UI-ResetCounters

function Run-Step {
    param(
        [string]$Description,
        [scriptblock]$Action
    )
    UI-Step -Label $Description -Action $Action
}

function Skip-Step {
    param(
        [string]$Description,
        [string]$Reason,
        [string]$Tier = "Advanced"
    )
    UI-Skip -Label $Description -Reason $Reason
    Add-ToolkitStepResult -Key $Description -Tier $Tier -Status "skipped" -Reason $Reason
}

function Reg-Add {
    param([string[]]$Arguments)
    $output = & reg add @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "reg add failed: $output"
    }
}

function Set-TrackedRegistry {
    # Thin pass-through to Set-ToolkitRegistryValue + step-result record.
    # ShouldProcess() called explicitly at the wrapper level so PSShouldProcess
    # is satisfied. The inner Set-ToolkitRegistryValue also calls ShouldProcess;
    # both gates are checked, which is correct (outer can decline before any
    # state-capture happens; inner gates the actual write).
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]$Id,
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$Type,
        [string]$Tier,
        [string]$Step
    )
    $target = if ($Name -eq '') { "$Path\(default)" } else { "$Path\$Name" }
    if (-not $PSCmdlet.ShouldProcess($target, "Set tracked registry value '$Value' (type $Type, tier $Tier)")) {
        return
    }
    Set-ToolkitRegistryValue -Id $Id -Path $Path -Name $Name -Value $Value -Type $Type -Tier $Tier -Step $Step
    Add-ToolkitStepResult -Key $Id -Tier $Tier -Status "applied" -Reason $Step
}

function Set-TrackedService {
    # Thin pass-through; explicit ShouldProcess at this layer.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]$Name,
        [string]$Mode,
        [string]$Tier,
        [string]$Step
    )
    if (-not $PSCmdlet.ShouldProcess("service:$Name", "Set tracked start mode '$Mode' (tier $Tier)")) {
        return
    }
    Set-ToolkitServiceStartMode -Name $Name -Mode $Mode -Tier $Tier -Step $Step
    Add-ToolkitStepResult -Key "service:$Name" -Tier $Tier -Status "applied" -Reason $Step
}

# ============================================================
# STEP 1: BACKUP
# ============================================================
UI-Section -Title "Phase 1: Safety Baseline" -Context "Create rollback points before tuning"

Run-Step "Creating system restore point" {
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description "Before Gaming Optimization" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
}

$backupDir = "$env:USERPROFILE\Documents\GamingOptBackup_$(Get-Date -Format 'yyyyMMdd_HHmm')"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
UI-Note -Message "Backing up registry to: $backupDir"
$regKeys = @(
    @("HKCU\Control Panel\Desktop", "Desktop.reg"),
    @("HKCU\Control Panel\Mouse", "Mouse.reg"),
    @("HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power", "Power.reg"),
    @("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching", "DriverSearching.reg"),
    @("HKCU\System\GameConfigStore", "GameConfigStore.reg"),
    @("HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile", "SystemProfile.reg"),
    @("HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "ExplorerAdvanced.reg"),
    @("HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo", "AdvertisingInfo.reg")
)
$backupCount = 0
foreach ($rk in $regKeys) {
    reg export $rk[0] "$backupDir\$($rk[1])" /y 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $backupCount++
    }
}
UI-Note -Message "Registry backup complete ($backupCount/$($regKeys.Count) keys exported)." -Color $script:UI_Success

# ============================================================
# STEP 2: POWER PLAN
# ============================================================
UI-Section -Title "Phase 2: Power and Core Windows Settings" -Context "Set a high-performance baseline"

$planGuid = "99999999-9999-9999-9999-999999999999"

Run-Step "Activating Ultimate Performance plan" {
    cmd /c "powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 $planGuid" 2>&1 | Out-Null
    cmd /c "powercfg /SETACTIVE $planGuid" 2>&1 | Out-Null
}

function Set-PowerIdx {
    # Power-plan AC/DC index setter. Mutates the running power profile —
    # ShouldProcess gate respects -WhatIf for the outer script.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)][string]$SubGroup,
        [Parameter(Mandatory)][string]$Setting,
        [Parameter(Mandatory)][string]$Value
    )
    if (-not $PSCmdlet.ShouldProcess("power-plan $planGuid", "set $SubGroup/$Setting = $Value (AC+DC)")) {
        return
    }
    powercfg /setacvalueindex $planGuid $SubGroup $Setting $Value 2>&1 | Out-Null
    powercfg /setdcvalueindex $planGuid $SubGroup $Setting $Value 2>&1 | Out-Null
}

Run-Step "Configuring detailed power settings" {
    Set-PowerIdx "0012ee47-9041-4b5d-9b77-535fba8b1442" "6738e2c4-e8a5-4a42-b16a-e040e769756e" "0x00000000"
    Set-PowerIdx "19cbb8fa-5279-450e-9fac-8a3d5fedd0c1" "12bbebe6-58d6-4636-95bb-3217ef867c1a" "000"
    Set-PowerIdx "238c9fa8-0aad-41ed-83f4-97be242c8f20" "29f6c1db-86da-48c5-9fdb-f2b67b1f44da" "0x00000000"
    Set-PowerIdx "238c9fa8-0aad-41ed-83f4-97be242c8f20" "94ac6d29-73ce-41a6-809f-6363ba21b47e" "000"
    Set-PowerIdx "238c9fa8-0aad-41ed-83f4-97be242c8f20" "9d7815a6-7ee4-497e-8888-515a05f02364" "0x00000000"
    powercfg /hibernate off 2>&1 | Out-Null
    Set-PowerIdx "2a737441-1930-4402-8d77-b2bebba308a3" "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" "000"
    Set-PowerIdx "501a4d13-42af-4429-9fd1-a8218c268e20" "ee12f906-d277-404b-b6da-e5fa1a576df5" "000"
    Set-PowerIdx "54533251-82be-4824-96c1-47b60b740d00" "893dee8e-2bef-41e0-89c6-b55d0929964c" "0x00000064"
    Set-PowerIdx "54533251-82be-4824-96c1-47b60b740d00" "bc5038f7-23e0-4960-96da-33abaf5935ec" "0x00000064"
    Set-PowerIdx "54533251-82be-4824-96c1-47b60b740d00" "94d3a615-a899-4ac5-ae2b-e4d8f634367f" "001"
    reg add "HKLM\System\ControlSet001\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583" /v "Attributes" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    Set-PowerIdx "54533251-82be-4824-96c1-47b60b740d00" "0cc5b647-c1df-4637-891a-dec35c318583" "0x00000064"
    Set-PowerIdx "54533251-82be-4824-96c1-47b60b740d00" "ea062031-0e34-4ff1-9b6d-eb1059334028" "0x00000064"
    Set-PowerIdx "7516b95f-f776-4464-8c53-06167f40cc99" "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e" "600"
    Set-PowerIdx "7516b95f-f776-4464-8c53-06167f40cc99" "fbd9aa66-9553-4097-ba44-ed6e9d65eab8" "000"
}

# ============================================================
# STEP 3: WINDOWS SETTINGS
# ============================================================
UI-Section -Title "Phase 3: Windows Settings" -Context "Disable common desktop overhead"

Run-Step "Disable transparency effects" {
    Set-TrackedRegistry -Id "reg:EnableTransparency" -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0 -Type "DWord" -Tier "Safe" -Step "windows-settings"
}

Run-Step "Disable background apps" {
    Set-TrackedRegistry -Id "reg:GlobalUserDisabled" -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1 -Type "DWord" -Tier "Safe" -Step "windows-settings"
    Set-TrackedRegistry -Id "reg:BackgroundAppGlobalToggle" -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "BackgroundAppGlobalToggle" -Value 0 -Type "DWord" -Tier "Safe" -Step "windows-settings"
}

Run-Step "Enable Hardware Accelerated GPU Scheduling" {
    Set-TrackedRegistry -Id "reg:HwSchMode" -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -Type "DWord" -Tier "Advanced" -Step "windows-settings"
}

Run-Step "Suppress notifications" {
    Set-TrackedRegistry -Id "reg:ToastsEnabled" -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "NOC_GLOBAL_SETTING_TOASTS_ENABLED" -Value 0 -Type "DWord" -Tier "Safe" -Step "windows-settings"
    Set-TrackedRegistry -Id "reg:NotificationSound" -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND" -Value 0 -Type "DWord" -Tier "Safe" -Step "windows-settings"
}

Run-Step "Disable Edge background startup" {
    # Sources:
    # https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/startupboostenabled
    # https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/backgroundmodeenabled
    Set-TrackedRegistry -Id "reg:EdgeStartupBoostEnabled" -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "StartupBoostEnabled" -Value 0 -Type "DWord" -Tier "Safe" -Step "edge-background"
    Set-TrackedRegistry -Id "reg:EdgeBackgroundModeEnabled" -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -Value 0 -Type "DWord" -Tier "Safe" -Step "edge-background"
}

# ============================================================
# STEP 4: SERVICES
# ============================================================
UI-Section -Title "Phase 4: Services" -Context "Disable background services that are not required for gaming"

foreach ($svc in @("DiagTrack", "PhoneSvc", "lfsvc", "RetailDemo", "MapsBroker", "Fax")) {
    Run-Step "Disabling $svc" {
        Set-TrackedService -Name $svc -Mode "disabled" -Tier "Safe" -Step "services"
        sc.exe stop $svc 2>&1 | Out-Null
    }
}
foreach ($svc in @("Spooler", "WSearch")) {
    Run-Step "Disabling $svc (aggressive)" {
        Set-TrackedService -Name $svc -Mode "disabled" -Tier "Advanced" -Step "services"
        sc.exe stop $svc 2>&1 | Out-Null
    }
}
Run-Step "Disabling Offline Files / Sync Center" {
    if (Get-Service -Name "CscService" -ErrorAction SilentlyContinue) {
        Set-TrackedService -Name "CscService" -Mode "disabled" -Tier "Advanced" -Step "services-mobsync"
        Stop-Service -Name "CscService" -Force -ErrorAction SilentlyContinue
    } else {
        Add-ToolkitStepResult -Key "service:CscService" -Tier "Advanced" -Status "skipped" -Reason "CscService not found"
    }
}

# ============================================================
# STEP 5: REGISTRY TWEAKS
# ============================================================
UI-Section -Title "Phase 5: Registry Pack" -Context "Apply low-level latency, UI, and privacy defaults"

Run-Step "MenuShowDelay = 0" { Reg-Add "HKCU\Control Panel\Desktop" /v "MenuShowDelay" /t REG_SZ /d "0" /f }
Run-Step "MouseHoverTime = 10" { Reg-Add "HKCU\Control Panel\Mouse" /v "MouseHoverTime" /t REG_SZ /d "10" /f }
Run-Step "Startup delay disabled" { Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" /v "StartupDelayInMSec" /t REG_DWORD /d 0 /f }
Run-Step "Auto driver searching disabled" {
    # CURSOR-AUDIT #13: high-impact HKLM key — track for revert
    Set-ToolkitRegistryValue -Id "reg:DriverSearchOrderConfig" `
        -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" `
        -Value 0 -Type "DWord" -Tier "Advanced" -Step "registry"
}
Run-Step "Fast Startup disabled" {
    # CURSOR-AUDIT #13: high-impact HKLM key — track for revert
    Set-ToolkitRegistryValue -Id "reg:HiberbootEnabled" `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" `
        -Value 0 -Type "DWord" -Tier "Advanced" -Step "registry"
}
Run-Step "Fullscreen optimizations disabled" {
    Reg-Add "HKCU\System\GameConfigStore" /v "GameDVR_FSEBehaviorMode" /t REG_DWORD /d 2 /f
    Reg-Add "HKCU\System\GameConfigStore" /v "GameDVR_HonorUserFSEBehaviorMode" /t REG_DWORD /d 1 /f
    Reg-Add "HKCU\System\GameConfigStore" /v "GameDVR_FSEBehavior" /t REG_DWORD /d 2 /f
    Reg-Add "HKCU\System\GameConfigStore" /v "GameDVR_DXGIHonorFSEWindowsCompatible" /t REG_DWORD /d 1 /f
}
Run-Step "Game CPU/GPU priority increased" {
    Reg-Add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f
    Reg-Add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Priority" /t REG_DWORD /d 6 /f
    Reg-Add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d "High" /f
    Reg-Add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "SFIO Priority" /t REG_SZ /d "High" /f
}
Run-Step "Network throttling disabled" {
    Reg-Add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "SystemResponsiveness" /t REG_DWORD /d 0 /f
    Reg-Add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "NetworkThrottlingIndex" /t REG_DWORD /d 0xFFFFFFFF /f
}
Run-Step "Power throttling disabled" {
    # CURSOR-AUDIT #13: high-impact HKLM key — track for revert
    Set-ToolkitRegistryValue -Id "reg:PowerThrottlingOff" `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" `
        -Value 1 -Type "DWord" -Tier "Advanced" -Step "registry"
}
Run-Step "Game Bar / DVR disabled" {
    Reg-Add "HKCU\System\GameConfigStore" /v "GameDVR_Enabled" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" /v "AppCaptureEnabled" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\GameBar" /v "UseNexusForGameBarEnabled" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\GameBar" /v "AutoGameModeEnabled" /t REG_DWORD /d 1 /f
}
Run-Step "Mouse acceleration disabled" {
    Reg-Add "HKCU\Control Panel\Mouse" /v "MouseSpeed" /t REG_SZ /d "0" /f
    Reg-Add "HKCU\Control Panel\Mouse" /v "MouseThreshold1" /t REG_SZ /d "0" /f
    Reg-Add "HKCU\Control Panel\Mouse" /v "MouseThreshold2" /t REG_SZ /d "0" /f
}
Run-Step "Visual effects optimized for performance" {
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v "VisualFXSetting" /t REG_DWORD /d 3 /f
    Reg-Add "HKCU\Control Panel\Desktop" /v "UserPreferencesMask" /t REG_BINARY /d "9012038012000000" /f
    Reg-Add "HKCU\Control Panel\Desktop" /v "FontSmoothing" /t REG_SZ /d "2" /f
    Reg-Add "HKCU\Control Panel\Desktop\WindowMetrics" /v "MinAnimate" /t REG_SZ /d "0" /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarAnimations" /t REG_DWORD /d 0 /f
    # CURSOR-AUDIT #13: high-impact HKLM key — track for revert
    Set-ToolkitRegistryValue -Id "reg:Win32PrioritySeparation" `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" `
        -Value 0x26 -Type "DWord" -Tier "Advanced" -Step "registry"
}
Run-Step "Explorer tweaks" {
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "LaunchTo" /t REG_DWORD /d 1 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "HideFileExt" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" /v "FullPath" /t REG_DWORD /d 1 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" /v "ShowFrequent" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ShowSyncProviderNotifications" /t REG_DWORD /d 0 /f
}
Run-Step "Sound scheme set to None" {
    Reg-Add "HKCU\AppEvents\Schemes" /ve /t REG_SZ /d ".None" /f
    Reg-Add "HKLM\Software\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" /v "DisableStartupSound" /t REG_DWORD /d 1 /f
    foreach ($sk in @(".Default", "DeviceConnect", "DeviceDisconnect", "DeviceFail", "MailBeep", "Notification.Default", "SystemAsterisk", "SystemExclamation", "SystemNotification", "WindowsUAC")) {
        Reg-Add "HKCU\AppEvents\Schemes\Apps\.Default\$sk\.Current" /ve /t REG_SZ /d "" /f
    }
}
Run-Step "Privacy / telemetry disabled" {
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\InputPersonalization" /v "RestrictImplicitInkCollection" /t REG_DWORD /d 1 /f
    Reg-Add "HKCU\Software\Microsoft\InputPersonalization" /v "RestrictImplicitTextCollection" /t REG_DWORD /d 1 /f
    # CURSOR-AUDIT #13: HKLM policy — track for revert (high-impact, users
    # may want to re-enable to receive Edge / Defender update signals).
    Set-ToolkitRegistryValue -Id "reg:AllowTelemetry" `
        -Path "HKLM:\Software\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" `
        -Value 0 -Type "DWord" -Tier "Advanced" -Step "registry"
    Reg-Add "HKCU\SOFTWARE\Microsoft\Siuf\Rules" /v "NumberOfSIUFInPeriod" /t REG_DWORD /d 0 /f
    Reg-Add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v "PublishUserActivities" /t REG_DWORD /d 0 /f
    Reg-Add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" /v "Value" /t REG_SZ /d "Deny" /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings" /v "IsDynamicSearchBoxEnabled" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings" /v "IsDeviceSearchHistoryEnabled" /t REG_DWORD /d 0 /f
    Reg-Add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" /v "Disabled" /t REG_DWORD /d 1 /f
}
Run-Step "Autoplay disabled" {
    Reg-Add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" /v "DisableAutoplay" /t REG_DWORD /d 1 /f
}
Run-Step "Disable Multiplane Overlay (MPO)" {
    # Source: FR33THYFR33THY/Ultimate — 8 Advanced/11 Mpo.ps1
    # OverlayTestMode=5 forces MPO off via DWM. Helps stutter / flicker
    # on some HDR + multi-monitor configs. Tracked so revert can restore.
    Set-TrackedRegistry -Id "reg:DwmOverlayTestMode" -Path "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name "OverlayTestMode" -Value 5 -Type "DWord" -Tier "Advanced" -Step "dwm-mpo"
}
Run-Step "Disable NTFS last-access updates" {
    # Source:
    # https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/fsutil-behavior
    Set-TrackedRegistry -Id "reg:NtfsDisableLastAccessUpdate" -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsDisableLastAccessUpdate" -Value 1 -Type "DWord" -Tier "Advanced" -Step "ntfs-last-access"
}
Run-Step "Accessibility shortcut popups disabled" {
    Reg-Add "HKCU\Control Panel\Accessibility\StickyKeys" /v "Flags" /t REG_SZ /d "2" /f
    Reg-Add "HKCU\Control Panel\Accessibility\ToggleKeys" /v "Flags" /t REG_SZ /d "34" /f
    Reg-Add "HKCU\Control Panel\Accessibility\Keyboard Response" /v "Flags" /t REG_SZ /d "2" /f
}

# ============================================================
# STEP 6: STARTUP
# ============================================================
UI-Section -Title "Phase 6: Startup Cleanup" -Context "Trim launch-at-boot noise"

Run-Step "Disable OneDrive autostart" {
    reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDrive" /f 2>&1 | Out-Null
    reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f 2>&1 | Out-Null
    Reg-Add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive" /v "DisableFileSyncNGSC" /t REG_DWORD /d 1 /f
}
Run-Step "Disable Teams autostart" {
    reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "com.squirrel.Teams.Teams" /f 2>&1 | Out-Null
    Reg-Add "HKLM\SOFTWARE\Policies\Microsoft\Office\16.0\common\officeupdate" /v "preventteamsinstall" /t REG_DWORD /d 1 /f
}
Run-Step "Disable Widgets" {
    Reg-Add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v "AllowNewsAndInterests" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarDa" /t REG_DWORD /d 0 /f
}
Run-Step "Disable Cortana" {
    Reg-Add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortana" /t REG_DWORD /d 0 /f
}
Run-Step "Disable Copilot" {
    Reg-Add "HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot" /v "TurnOffWindowsCopilot" /t REG_DWORD /d 1 /f
    Reg-Add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v "TurnOffWindowsCopilot" /t REG_DWORD /d 1 /f
}

# ============================================================
# STEP 7: GPU MSI MODE
# ============================================================
UI-Section -Title "Phase 7: GPU and Network Prep" -Context "Apply device-level latency changes"

$gpuDevices = @(Get-GpuVendor)
if ($gpuDevices.Count -eq 0) {
    Skip-Step -Description "MSI mode" -Reason "No NVIDIA / AMD / Intel display devices detected" -Tier "Advanced"
} else {
    foreach ($gpu in $gpuDevices) {
        Run-Step "MSI Mode for $($gpu.FriendlyName)" {
            $id = $gpu.InstanceId
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$id\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            Set-ToolkitRegistryValue `
                -Id "gpu-msi:$id" `
                -Path $regPath `
                -Name "MSISupported" `
                -Value 1 -Type "DWord" `
                -Tier "Advanced" -Step "gpu-msi"
            Add-ToolkitStepResult -Key "gpu-msi:$id" -Tier "Advanced" -Status "applied" -Reason "MSI mode enabled"
        }
    }
}

# ============================================================
# STEP 7.5: GPU DRIVER INSTALL (requires DDU — skip with note)
# ============================================================
UI-Section -Title "Phase 7.5: GPU Driver Flow" -Context "Kept separate so DDU can own the risky driver handoff"
UI-Note -Message "[SKIP] GPU driver install requires DDU flow." -Color $script:UI_Warning
UI-Note -Message "Run DduAuto.ps1 or launcher category 6 (GPU) separately." -Color $script:UI_Warning
Add-ToolkitStepResult -Key "gpu-driver-install" -Tier "Advanced" -Status "skipped" `
    -Reason "Requires DDU flow. Run DduAuto.ps1 or launcher category 6 (GPU) separately."

# ============================================================
# STEP 8: NETWORK
# ============================================================
UI-Section -Title "Phase 8: Network" -Context "Apply adapter-aware network defaults"

Run-Step "TCP Auto-Tuning = normal" { netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null }
Run-Step "RSS enabled" { netsh int tcp set global rss=enabled 2>&1 | Out-Null }
Run-Step "TCP timestamps disabled" { netsh int tcp set global timestamps=disabled 2>&1 | Out-Null }
Run-Step "Large Send Offload disabled where supported" {
    Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
        Set-NetAdapterAdvancedProperty -Name $_.Name -DisplayName "Large Send Offload*" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
    }
}
Run-Step "Nagle's Algorithm disabled on active adapters" {
    # CURSOR-AUDIT #5 fix: route per-interface writes through Set-ToolkitRegistryValue
    # so REVERT-EVERYTHING.ps1 can roll them back via the manifest. Id format matches
    # 7 network/optimize-network.ps1 — both paths produce the same manifest keys.
    $interfaces = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    Get-ChildItem $interfaces | ForEach-Object {
        $ip = (Get-ItemProperty $_.PSPath -Name "DhcpIPAddress" -ErrorAction SilentlyContinue).DhcpIPAddress
        if ($ip -and $ip -ne "0.0.0.0") {
            $iface = $_.PSChildName
            Set-ToolkitRegistryValue -Id "net:TcpAckFrequency:$iface" `
                -Path $_.PSPath -Name "TcpAckFrequency" `
                -Value 1 -Type "DWord" -Tier "Advanced" -Step "network"
            Set-ToolkitRegistryValue -Id "net:TCPNoDelay:$iface" `
                -Path $_.PSPath -Name "TCPNoDelay" `
                -Value 1 -Type "DWord" -Tier "Advanced" -Step "network"
            Add-ToolkitStepResult -Key "net:Nagle:$iface" -Tier "Advanced" -Status "applied" -Reason "Nagle disabled (TcpAckFrequency + TCPNoDelay = 1)"
        }
    }
}
Run-Step "DNS set to Cloudflare on active adapters" {
    Set-ToolkitDnsServers -ServerAddresses @("1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001") -Tier "Advanced" -Step "network"
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

# ============================================================
# STEP 9: WINDOWS UPDATE  (Security Trade-off — gated)
# ============================================================
UI-Section -Title "Phase 9: Windows Update Suppression" -Context "Security Trade-off — only runs with -IncludeSecurityTradeoffs"

if ($IncludeSecurityTradeoffs) {
    Run-Step "Disable auto-restart for updates" {
        Set-TrackedRegistry -Id "reg:NoAutoRebootWithLoggedOnUsers" -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type "DWord" -Tier "Security Trade-off" -Step "windows-update"
        Set-TrackedRegistry -Id "reg:AUOptions" -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Value 3 -Type "DWord" -Tier "Security Trade-off" -Step "windows-update"
        Set-TrackedRegistry -Id "reg:NoAutoUpdate" -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 1 -Type "DWord" -Tier "Security Trade-off" -Step "windows-update"
    }
    Run-Step "Set active hours 8AM-2AM" {
        Set-TrackedRegistry -Id "reg:ActiveHoursStart" -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "ActiveHoursStart" -Value 8 -Type "DWord" -Tier "Security Trade-off" -Step "windows-update"
        Set-TrackedRegistry -Id "reg:ActiveHoursEnd" -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "ActiveHoursEnd" -Value 2 -Type "DWord" -Tier "Security Trade-off" -Step "windows-update"
        Set-TrackedRegistry -Id "reg:IsActiveHoursEnabled" -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "IsActiveHoursEnabled" -Value 1 -Type "DWord" -Tier "Security Trade-off" -Step "windows-update"
    }
    foreach ($updateSvc in @("wuauserv", "UsoSvc", "DoSvc")) {
        Run-Step "Disable $updateSvc" {
            Set-TrackedService -Name $updateSvc -Mode "disabled" -Tier "Security Trade-off" -Step "windows-update"
            Stop-Service -Name $updateSvc -Force -ErrorAction SilentlyContinue
        }
    }
    Run-Step "Disable WaaSMedicSvc (best effort)" {
        Set-TrackedRegistry -Id "reg:WaaSMedicSvcStart" -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -Name "Start" -Value 4 -Type "DWord" -Tier "Security Trade-off" -Step "windows-update"
    }
} else {
    Skip-Step -Description "phase9-windows-update" -Reason "Skipped — pass -IncludeSecurityTradeoffs to include" -Tier "Security Trade-off"
}

# ============================================================
# STEP 10: SECURITY TRADE-OFFS  (Security Trade-off — gated)
# ============================================================
UI-Section -Title "Phase 10: Security Trade-offs" -Context "Security Trade-off — only runs with -IncludeSecurityTradeoffs"

if ($IncludeSecurityTradeoffs) {
    UI-Note -Message "[!] ANTI-CHEAT: HVCI/VBS changes may affect BattlEye and EAC on Win11 24H2+." -Color "Red"
    UI-Note -Message "    R6 Siege and other BattlEye titles may refuse to launch. Test after reboot." -Color "Red"
    UI-Note -Message "    Revert via REVERT-EVERYTHING.ps1 if affected titles stop working." -Color "Yellow"
    Write-Host ""

    Run-Step "Disable Memory Integrity (HVCI)" {
        Set-TrackedRegistry -Id "reg:HVCIEnabled" -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -Value 0 -Type "DWord" -Tier "Security Trade-off" -Step "security"
    }
    Run-Step "Disable VBS" {
        Set-TrackedRegistry -Id "reg:EnableVBS" -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -Value 0 -Type "DWord" -Tier "Security Trade-off" -Step "security"
    }
    Run-Step "Disable LSA protection" {
        Set-TrackedRegistry -Id "reg:RunAsPPL" -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -Value 0 -Type "DWord" -Tier "Security Trade-off" -Step "security"
        Set-TrackedRegistry -Id "reg:LsaCfgFlags" -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LsaCfgFlags" -Value 0 -Type "DWord" -Tier "Security Trade-off" -Step "security"
    }
    Run-Step "Disable Spectre / Meltdown CPU mitigations" {
        # Source: FR33THYFR33THY/Ultimate — 8 Advanced/3 Spectre Meltdown.ps1
        # Tier matches the surrounding section (VBS / HVCI / LSA also Security Trade-off).
        $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        Set-TrackedRegistry -Id "reg:FeatureSettingsOverride" -Path $mmPath -Name "FeatureSettingsOverride" -Value 3 -Type "DWord" -Tier "Security Trade-off" -Step "security"
        Set-TrackedRegistry -Id "reg:FeatureSettingsOverrideMask" -Path $mmPath -Name "FeatureSettingsOverrideMask" -Value 3 -Type "DWord" -Tier "Security Trade-off" -Step "security"
    }
} else {
    Skip-Step -Description "phase10-security-tradeoffs" -Reason "Skipped — pass -IncludeSecurityTradeoffs to include" -Tier "Security Trade-off"
}

# ============================================================
# STEP 11: CUSTOMIZATION
# ============================================================
UI-Section -Title "Phase 11: Windows Customization" -Context "Clean up the shell and desktop defaults"

Run-Step "Restore classic right-click menu" { Reg-Add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /ve /t REG_SZ /d "" /f }
Run-Step "Disable Bing / web results in Start search" {
    Reg-Add "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v "DisableSearchBoxSuggestions" /t REG_DWORD /d 1 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v "BingSearchEnabled" /t REG_DWORD /d 0 /f
}
Run-Step "Clean taskbar" {
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v "SearchboxTaskbarMode" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ShowTaskViewButton" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarMn" /t REG_DWORD /d 0 /f
}
Run-Step "Disable lock screen ads" {
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "RotatingLockScreenOverlayEnabled" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338387Enabled" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-310093Enabled" /t REG_DWORD /d 0 /f
}
Run-Step "Disable suggested content" {
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338393Enabled" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-353694Enabled" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-353696Enabled" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "Start_IrisRecommendations" /t REG_DWORD /d 0 /f
}
Run-Step "Show This PC on desktop" {
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" /v "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" /t REG_DWORD /d 0 /f
}
Run-Step "Enable dark mode" {
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "AppsUseLightTheme" /t REG_DWORD /d 0 /f
    Reg-Add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "SystemUsesLightTheme" /t REG_DWORD /d 0 /f
}
Run-Step "Restart Explorer" {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer.exe
    }
}

# ============================================================
# STEP 12: DEFENDER EXCLUSIONS
# ============================================================
UI-Section -Title "Phase 12: Defender Exclusions" -Context "Best-effort exclusions for common game library paths"

$gamePaths = @(
    "C:\Program Files (x86)\Steam",
    "C:\Program Files\Epic Games",
    "C:\Program Files (x86)\Origin Games",
    "C:\Program Files\EA Games",
    "C:\Program Files\Riot Games",
    "C:\Program Files (x86)\Ubisoft",
    "C:\Program Files (x86)\Battle.net",
    "C:\Program Files\GOG Galaxy\Games",
    "$env:LOCALAPPDATA\Programs\launcher"
)

foreach ($path in $gamePaths) {
    if (Test-Path $path) {
        Run-Step "Defender exclusion: $path" {
            Add-ToolkitDefenderExclusion -Path $path -Tier "Security Trade-off" -Step "defender"
        }
    } else {
        Skip-Step -Description "Defender exclusion: $path" -Reason "Path not present" -Tier "Security Trade-off"
    }
}

# ============================================================
# STEP 13: DEBLOAT
# ============================================================
UI-Section -Title "Phase 13: Debloat" -Context "Remove non-essential bundled apps"

$appsToRemove = @(
    "Clipchamp.Clipchamp", "Microsoft.BingNews", "Microsoft.BingWeather",
    "Microsoft.GetHelp", "Microsoft.Getstarted", "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection", "Microsoft.MicrosoftStickyNotes",
    "Microsoft.People", "Microsoft.PowerAutomateDesktop", "Microsoft.Todos",
    "Microsoft.WindowsAlarms", "Microsoft.WindowsFeedbackHub",
    "Microsoft.WindowsMaps", "Microsoft.WindowsSoundRecorder",
    "Microsoft.YourPhone", "Microsoft.ZuneMusic", "Microsoft.ZuneVideo",
    "MicrosoftCorporationII.QuickAssist", "MicrosoftTeams",
    "Microsoft.549981C3F5F10", "Microsoft.OutlookForWindows"
)

$removed = 0
$removeFailed = 0
foreach ($app in $appsToRemove) {
    $pkg = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
    if ($pkg) {
        try {
            $pkg | Remove-AppxPackage -ErrorAction Stop
            Record-ToolkitPackageRemoval -PackageName $app
            $removed++
        } catch {
            $removeFailed++
        }
    }

    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $app } |
        ForEach-Object {
            $_ | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue 2>&1 | Out-Null
            Record-ToolkitPackageRemoval -PackageName $app -Provisioned
        }
}
UI-Note -Message "Removed $removed bloatware apps." -Color $script:UI_Success
if ($removeFailed -gt 0) {
    UI-Note -Message "$removeFailed apps failed to remove (manual cleanup may be needed)." -Color $script:UI_Warning
}

# ============================================================
# STEP 14: CLEANUP
# ============================================================
UI-Section -Title "Phase 14: Cleanup" -Context "Clear temp files and leftover folders"

Run-Step "Clearing user temp" { Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue }
Run-Step "Clearing Windows temp" { Remove-Item -Path "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue }
Run-Step "Clearing Windows Update cache" {
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
}
Run-Step "Clearing shader cache" { Remove-Item -Path "$env:LOCALAPPDATA\D3DSCache\*" -Recurse -Force -ErrorAction SilentlyContinue }
Run-Step "Removing leftover folders" {
    # Guard: do not nuke inetpub if IIS is installed. Some devs run IIS Express
    # or full IIS for local development. Removing this directory destroys
    # site state, virtual directory configs, and IIS-managed app pools.
    $iisInstalled = $false
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName IIS-WebServer -ErrorAction Stop
        $iisInstalled = $feature.State -eq 'Enabled'
    } catch {
        # Get-WindowsOptionalFeature unavailable on Home editions or stripped
        # images — fall back to a directory contents probe. If the folder
        # contains the IIS metabase indicators, treat as installed.
        $iisMarkers = @("history", "logs", "temp", "wwwroot", "config")
        $iisInstalled = (Test-Path "$env:SystemDrive\inetpub") -and
        ((Get-ChildItem "$env:SystemDrive\inetpub" -Force -ErrorAction SilentlyContinue |
                Where-Object { $iisMarkers -contains $_.Name }).Count -ge 2)
    }
    if ($iisInstalled) {
        UI-Note -Message "      Skipping inetpub removal: IIS appears installed." -Color $script:UI_Warning
    } elseif (Test-Path "$env:SystemDrive\inetpub") {
        Remove-Item "$env:SystemDrive\inetpub" -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item "$env:SystemDrive\PerfLogs" -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""

# ============================================================
# SUMMARY
# ============================================================
$elapsed = (Get-Date) - $startTime
UI-Summary -DoneMessage "Apply Everything complete" -Details @(
    "Elapsed:    $([math]::Round($elapsed.TotalSeconds)) seconds",
    "Backup:     $backupDir",
    "Manifest:   $(Get-ToolkitManifestPath)",
    "Follow-up:  BIOS-CHECKLIST.md, Verify, optional DDU / WinUtil"
) -RevertHint "Run REVERT-EVERYTHING.ps1 after the reboot if you want to undo the tracked path."
if ($IncludeSecurityTradeoffs) {
    UI-Note -Message "This run included Windows Update suppression and security trade-off tweaks." -Color $script:UI_Warning
}
UI-Note -Message "Reboot is required before judging results." -Color $script:UI_Warning

if (UI-AskYesNo -Prompt "Reboot now?") {
    UI-Note -Message "Rebooting in 5 seconds..." -Color $script:UI_Warning
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    UI-Note -Message "Remember to reboot before judging results." -Color $script:UI_Warning
    UI-Exit
}
