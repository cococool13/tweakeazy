# ============================================================
# REVERT EVERYTHING — Undo Gaming Optimizations
# Windows 11 Gaming Optimization Guide
# ============================================================
#
# Restores everything it can from the manifest-backed state capture.
# Falls back to default-based restoration for the broader registry pack.
#
# Anti-cheat impact: NONE — the revert direction is universally safe.
# Restoring HVCI / VBS to ON (if previously disabled) re-satisfies
# BattlEye / Vanguard policy requirements; all other restores return
# the OS to its default state which anti-cheat layers expect.
# Reboot required: SEE-SCRIPT — heuristic-default; refine in follow-up.
# Disk impact: NONE — registry / cmdlet only; no installer / file extraction.
#
# Must be run as Administrator. Requires reboot after completion.
# ============================================================

. "$PSScriptRoot\lib\toolkit-state.ps1"
. "$PSScriptRoot\lib\ui-helpers.ps1"
. "$PSScriptRoot\lib\gpu-detection.ps1"

$Host.UI.RawUI.WindowTitle = "Windows 11 Gaming Optimization — Revert Everything"
UI-Header -Title "Revert Everything" -Subtitle "Restore the tracked full-stack path"
UI-RequireAdmin -ScriptName "Revert Everything"
UI-Confirm -Message "Manifest-backed state is restored first, then default-based fallbacks are applied." -Warnings @(
    "Removed Store apps may still require manual reinstall.",
    "A reboot is required for the rollback to fully settle."
)

$state = Initialize-ToolkitState
$manifestPath = Get-ToolkitManifestPath
UI-ResetCounters

function Run-Step {
    param([string]$Description, [scriptblock]$Action)
    UI-Step -Label $Description -Action $Action
}

function Restore-TrackedRegistryStep {
    param([string]$Id)
    Restore-ToolkitRegistryValue -Id $Id | Out-Null
}

# ============================================================
# STEP 1: POWER PLAN
# ============================================================
UI-Section -Title "Phase 1: Power Baseline"

Run-Step "Activating Balanced power plan" {
    powercfg /setactive SCHEME_BALANCED 2>&1 | Out-Null
}
Run-Step "Deleting custom power plan" {
    powercfg /delete 99999999-9999-9999-9999-999999999999 2>&1 | Out-Null
}
Run-Step "Re-enabling hibernate" {
    powercfg /hibernate on 2>&1 | Out-Null
}
Run-Step "Re-enabling Fast Startup" {
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v "HiberbootEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "HibernateEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
}
Run-Step "Removing power throttling override" {
    reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v "PowerThrottlingOff" /f 2>&1 | Out-Null
}

# ============================================================
# STEP 2: WINDOWS SETTINGS
# ============================================================
UI-Section -Title "Phase 2: Windows Settings"

Run-Step "Transparency effects" { Restore-TrackedRegistryStep "reg:EnableTransparency" }
Run-Step "Background apps" {
    Restore-TrackedRegistryStep "reg:GlobalUserDisabled"
    Restore-TrackedRegistryStep "reg:BackgroundAppGlobalToggle"
}
Run-Step "HAGS" { Restore-TrackedRegistryStep "reg:HwSchMode" }
Run-Step "Notifications" {
    Restore-TrackedRegistryStep "reg:ToastsEnabled"
    Restore-TrackedRegistryStep "reg:NotificationSound"
}
Run-Step "Restoring Edge background policies" {
    Restore-TrackedRegistryStep "reg:EdgeStartupBoostEnabled"
    Restore-TrackedRegistryStep "reg:EdgeBackgroundModeEnabled"
}

# ============================================================
# STEP 3: SERVICES
# ============================================================
UI-Section -Title "Phase 3: Services"

foreach ($svc in @("DiagTrack", "PhoneSvc", "lfsvc", "RetailDemo", "MapsBroker", "Fax", "Spooler", "WSearch", "CscService")) {
    Run-Step "Restoring $svc" {
        if (-not (Restore-ToolkitServiceStartMode -Name $svc)) {
            if ($svc -in @("DiagTrack", "Spooler", "WSearch", "MapsBroker")) {
                sc.exe config $svc start= auto 2>&1 | Out-Null
            } else {
                sc.exe config $svc start= demand 2>&1 | Out-Null
            }
        }
    }
}

# ============================================================
# STEP 4: REGISTRY TWEAKS
# ============================================================
UI-Section -Title "Phase 4: Registry Pack"

Run-Step "Restoring DWM Multiplane Overlay" {
    if (-not (Restore-ToolkitRegistryValue -Id "reg:DwmOverlayTestMode")) {
        # No manifest entry — clear the value so DWM uses driver default.
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name "OverlayTestMode" -ErrorAction SilentlyContinue
    }
}
Run-Step "Restoring NTFS last-access updates" {
    Restore-TrackedRegistryStep "reg:NtfsDisableLastAccessUpdate"
}
Run-Step "MenuShowDelay = 400" { reg add "HKCU\Control Panel\Desktop" /v "MenuShowDelay" /t REG_SZ /d "400" /f 2>&1 | Out-Null }
Run-Step "MouseHoverTime = 400" { reg add "HKCU\Control Panel\Mouse" /v "MouseHoverTime" /t REG_SZ /d "400" /f 2>&1 | Out-Null }
Run-Step "Removing startup delay override" { reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" /v "StartupDelayInMSec" /f 2>&1 | Out-Null }
Run-Step "Re-enabling auto driver searching" { reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" /v "SearchOrderConfig" /t REG_DWORD /d 1 /f 2>&1 | Out-Null }
Run-Step "Removing fullscreen optimization overrides" {
    reg delete "HKCU\System\GameConfigStore" /v "GameDVR_FSEBehaviorMode" /f 2>&1 | Out-Null
    reg delete "HKCU\System\GameConfigStore" /v "GameDVR_HonorUserFSEBehaviorMode" /f 2>&1 | Out-Null
    reg delete "HKCU\System\GameConfigStore" /v "GameDVR_FSEBehavior" /f 2>&1 | Out-Null
    reg delete "HKCU\System\GameConfigStore" /v "GameDVR_DXGIHonorFSEWindowsCompatible" /f 2>&1 | Out-Null
}
Run-Step "Restoring game priority defaults" {
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 2 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Priority" /t REG_DWORD /d 2 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d "Medium" /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "SFIO Priority" /t REG_SZ /d "Normal" /f 2>&1 | Out-Null
}
Run-Step "Restoring network throttling defaults" {
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "SystemResponsiveness" /t REG_DWORD /d 0x14 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "NetworkThrottlingIndex" /t REG_DWORD /d 0x0a /f 2>&1 | Out-Null
}
Run-Step "Re-enabling Game Bar / DVR" {
    reg add "HKCU\System\GameConfigStore" /v "GameDVR_Enabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" /v "AppCaptureEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\GameBar" /v "UseNexusForGameBarEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    # Apply asserts Game Mode on. DWORD 1 is the Windows 11 default.
    reg add "HKCU\Software\Microsoft\GameBar" /v "AutoGameModeEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
}
Run-Step "Restoring mouse acceleration" {
    reg add "HKCU\Control Panel\Mouse" /v "MouseSpeed" /t REG_SZ /d "1" /f 2>&1 | Out-Null
    reg add "HKCU\Control Panel\Mouse" /v "MouseThreshold1" /t REG_SZ /d "6" /f 2>&1 | Out-Null
    reg add "HKCU\Control Panel\Mouse" /v "MouseThreshold2" /t REG_SZ /d "10" /f 2>&1 | Out-Null
}
Run-Step "Restoring visual effects defaults" {
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v "VisualFXSetting" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    # Apply writes the performance mask 9012038012000000. VisualFXSetting=0
    # ("Let Windows choose") pairs with 9E1E078012000000. FontSmoothing 2 is
    # ClearType, the Windows default Apply also asserts.
    reg add "HKCU\Control Panel\Desktop" /v "UserPreferencesMask" /t REG_BINARY /d "9E1E078012000000" /f 2>&1 | Out-Null
    reg add "HKCU\Control Panel\Desktop" /v "FontSmoothing" /t REG_SZ /d "2" /f 2>&1 | Out-Null
    reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v "MinAnimate" /t REG_SZ /d "1" /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarAnimations" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" /v "Win32PrioritySeparation" /t REG_DWORD /d 2 /f 2>&1 | Out-Null
}
Run-Step "Restoring Explorer defaults" {
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "LaunchTo" /t REG_DWORD /d 2 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "HideFileExt" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ShowSyncProviderNotifications" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" /v "FullPath" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" /v "ShowFrequent" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" /v "DisableAutoplay" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
}
Run-Step "Restoring default sound scheme" {
    reg add "HKCU\AppEvents\Schemes" /ve /t REG_SZ /d ".Default" /f 2>&1 | Out-Null
    reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" /v "DisableStartupSound" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    # Apply blanks these .Current values. The scheme name alone does not
    # refill them, so each event stays silent. Copy the Windows Default
    # sibling (.Default) back onto .Current. Same event list as Apply.
    $soundEvents = @(
        ".Default",
        "DeviceConnect",
        "DeviceDisconnect",
        "DeviceFail",
        "MailBeep",
        "Notification.Default",
        "SystemAsterisk",
        "SystemExclamation",
        "SystemNotification",
        "WindowsUAC"
    )
    foreach ($soundEvent in $soundEvents) {
        $defaultKey = "HKCU:\AppEvents\Schemes\Apps\.Default\$soundEvent\.Default"
        $currentKey = "HKCU\AppEvents\Schemes\Apps\.Default\$soundEvent\.Current"
        $wav = $null
        $schemeItem = Get-Item -LiteralPath $defaultKey -ErrorAction SilentlyContinue
        if ($schemeItem) {
            $wav = $schemeItem.GetValue("")
        }
        if ([string]::IsNullOrEmpty([string]$wav)) {
            reg delete $currentKey /ve /f 2>&1 | Out-Null
        } else {
            reg add $currentKey /ve /t REG_SZ /d "$wav" /f 2>&1 | Out-Null
        }
    }
}
Run-Step "Restoring accessibility defaults" {
    reg add "HKCU\Control Panel\Accessibility\StickyKeys" /v "Flags" /t REG_SZ /d "510" /f 2>&1 | Out-Null
    reg add "HKCU\Control Panel\Accessibility\ToggleKeys" /v "Flags" /t REG_SZ /d "62" /f 2>&1 | Out-Null
    reg add "HKCU\Control Panel\Accessibility\Keyboard Response" /v "Flags" /t REG_SZ /d "126" /f 2>&1 | Out-Null
}
Run-Step "Restoring privacy defaults" {
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\InputPersonalization" /v "RestrictImplicitInkCollection" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\InputPersonalization" /v "RestrictImplicitTextCollection" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg delete "HKCU\SOFTWARE\Microsoft\Siuf\Rules" /v "NumberOfSIUFInPeriod" /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v "PublishUserActivities" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings" /v "IsDynamicSearchBoxEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings" /v "IsDeviceSearchHistoryEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" /v "Disabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" /v "Value" /t REG_SZ /d "Allow" /f 2>&1 | Out-Null
}

# ============================================================
# STEP 5: STARTUP
# ============================================================
UI-Section -Title "Phase 5: Startup Cleanup"

Run-Step "Re-enabling OneDrive startup" { reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive" /v "DisableFileSyncNGSC" /f 2>&1 | Out-Null }
Run-Step "Re-enabling Teams startup" { reg delete "HKLM\SOFTWARE\Policies\Microsoft\Office\16.0\common\officeupdate" /v "preventteamsinstall" /f 2>&1 | Out-Null }
Run-Step "Re-enabling Widgets" {
    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v "AllowNewsAndInterests" /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarDa" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
}
Run-Step "Re-enabling Cortana" { reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortana" /f 2>&1 | Out-Null }
Run-Step "Re-enabling Copilot" {
    reg delete "HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot" /v "TurnOffWindowsCopilot" /f 2>&1 | Out-Null
    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v "TurnOffWindowsCopilot" /f 2>&1 | Out-Null
}

# ============================================================
# STEP 6: GPU MSI MODE
# ============================================================
UI-Section -Title "Phase 6: GPU MSI Mode"

Run-Step "Removing MSI mode overrides (manifest-driven)" {
    $regKeys = $state.registry
    $properties = if ($regKeys -is [hashtable]) {
        $regKeys.GetEnumerator() | ForEach-Object { [PSCustomObject]@{ Name = $_.Key; Value = $_.Value } }
    } else {
        $regKeys.PSObject.Properties
    }
    $msiCount = 0
    foreach ($prop in $properties) {
        if ($prop.Value.step -eq "gpu-msi") {
            Restore-ToolkitRegistryValue -Id $prop.Name | Out-Null
            $msiCount++
        }
    }
    if ($msiCount -eq 0) {
        # Fallback for pre-manifest installs: enumerate live and clear blindly.
        $gpuDevices = @(Get-GpuVendor)
        foreach ($gpu in $gpuDevices) {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($gpu.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            Remove-ItemProperty -Path $regPath -Name "MSISupported" -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# STEP 6.5: GPU HIDDEN SETTINGS
# ============================================================
UI-Section -Title "Phase 6.5: GPU Performance Settings"

$gpuSteps = @(
    "gpu-nvidia-settings",
    "gpu-amd-settings",
    "gpu-intel-settings",
    "gpu-p0-state",
    "gpu-amd-ulps"
)
foreach ($gpuStep in $gpuSteps) {
    $regKeys = $state.registry
    $properties = if ($regKeys -is [hashtable]) {
        $regKeys.GetEnumerator() | ForEach-Object { [PSCustomObject]@{ Name = $_.Key; Value = $_.Value } }
    } else {
        $regKeys.PSObject.Properties
    }
    foreach ($prop in $properties) {
        if ($prop.Value.step -eq $gpuStep) {
            Run-Step "Reverting $($prop.Name)" {
                Restore-ToolkitRegistryValue -Id $prop.Name | Out-Null
            }
        }
    }
}

# Restore GPU-related services disabled during driver install
foreach ($svc in @("NvTelemetryContainer", "amdfendr", "amdfendrmgr", "Intel(R) Computing Improvement Program")) {
    if (Test-ToolkitMapHasKey -Map $state.services -Key $svc) {
        Run-Step "Restoring $svc" {
            Restore-ToolkitServiceStartMode -Name $svc | Out-Null
        }
    }
}

# ============================================================
# STEP 7: NETWORK
# ============================================================
UI-Section -Title "Phase 7: Network"

Run-Step "Restoring TCP timestamps" { netsh int tcp set global timestamps=enabled 2>&1 | Out-Null }
Run-Step "Re-enabling Large Send Offload" {
    Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
        Set-NetAdapterAdvancedProperty -Name $_.Name -DisplayName "Large Send Offload*" -DisplayValue "Enabled" -ErrorAction SilentlyContinue
    }
}
Run-Step "Removing Nagle overrides" {
    # CURSOR-AUDIT #5 fix: prefer manifest-driven restore. Both APPLY-EVERYTHING.ps1
    # and 7 network/optimize-network.ps1 now write tracked entries with Id format
    # net:TcpAckFrequency:<iface-guid> / net:TCPNoDelay:<iface-guid>. Restore from
    # manifest first, then fall back to blind remove for any interface whose
    # Nagle state pre-dates the toolkit-state pattern (legacy apply path).
    $handled = @{}
    $state = Get-ToolkitState
    if ($state -and $state.PSObject.Properties["registry"] -and $state.registry) {
        $regKeys = @()
        if ($state.registry -is [hashtable]) {
            $regKeys = @($state.registry.Keys)
        } else {
            $regKeys = @($state.registry.PSObject.Properties.Name)
        }
        foreach ($id in $regKeys) {
            if ($id -like "net:TcpAckFrequency:*" -or $id -like "net:TCPNoDelay:*") {
                $entry = Get-ToolkitMapValue -Map $state.registry -Key $id
                if (Restore-ToolkitRegistryValue -Id $id) {
                    if ($entry -and $entry.path -and $entry.name) {
                        $handled["$($entry.path)|$($entry.name)"] = $true
                    }
                }
            }
        }
    }
    $interfaces = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    Get-ChildItem $interfaces -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($name in @("TcpAckFrequency", "TCPNoDelay")) {
            $key = "$($_.PSPath)|$name"
            if (-not $handled.ContainsKey($key)) {
                Remove-ItemProperty $_.PSPath -Name $name -ErrorAction SilentlyContinue
            }
        }
    }
}
Run-Step "Restoring DNS" {
    if (-not (Restore-ToolkitDnsServers)) {
        Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
            Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        }
        Clear-DnsClientCache -ErrorAction SilentlyContinue
    }
}

# ============================================================
# STEP 8: WINDOWS UPDATE + SECURITY
# ============================================================
UI-Section -Title "Phase 8: Windows Update and Security Trade-offs"

Run-Step "Restoring Windows Update policies" {
    Restore-TrackedRegistryStep "reg:NoAutoRebootWithLoggedOnUsers"
    Restore-TrackedRegistryStep "reg:AUOptions"
    Restore-TrackedRegistryStep "reg:NoAutoUpdate"
    Restore-TrackedRegistryStep "reg:ActiveHoursStart"
    Restore-TrackedRegistryStep "reg:ActiveHoursEnd"
    Restore-TrackedRegistryStep "reg:IsActiveHoursEnabled"
    Restore-TrackedRegistryStep "reg:WaaSMedicSvcStart"
}
Run-Step "Re-enabling Windows Update services" {
    foreach ($svc in @("wuauserv", "UsoSvc", "DoSvc")) {
        if (-not (Restore-ToolkitServiceStartMode -Name $svc)) {
            if ($svc -eq "DoSvc") {
                sc.exe config $svc start= auto 2>&1 | Out-Null
            } else {
                sc.exe config $svc start= demand 2>&1 | Out-Null
            }
        }
        Start-Service -Name $svc -ErrorAction SilentlyContinue
    }
}
Run-Step "Restoring VBS / HVCI / LSA" {
    Restore-TrackedRegistryStep "reg:HVCIEnabled"
    Restore-TrackedRegistryStep "reg:EnableVBS"
    Restore-TrackedRegistryStep "reg:RunAsPPL"
    Restore-TrackedRegistryStep "reg:LsaCfgFlags"
}
Run-Step "Restoring Spectre / Meltdown mitigations" {
    Restore-TrackedRegistryStep "reg:FeatureSettingsOverride"
    Restore-TrackedRegistryStep "reg:FeatureSettingsOverrideMask"
}

# ============================================================
# STEP 9: WINDOWS CUSTOMIZATION
# ============================================================
UI-Section -Title "Phase 9: Windows Customization"

Run-Step "Restoring Win11 context menu" { reg delete "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" /f 2>&1 | Out-Null }
Run-Step "Re-enabling Bing search" {
    reg delete "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v "DisableSearchBoxSuggestions" /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v "BingSearchEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
}
Run-Step "Restoring taskbar defaults" {
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v "SearchboxTaskbarMode" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ShowTaskViewButton" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarMn" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
}
Run-Step "Re-enabling lock screen tips" {
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "RotatingLockScreenOverlayEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338387Enabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-310093Enabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
}
Run-Step "Re-enabling suggested content" {
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338393Enabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-353694Enabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-353696Enabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "Start_IrisRecommendations" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
}
Run-Step "Restoring light mode" {
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "AppsUseLightTheme" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "SystemUsesLightTheme" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
}
Run-Step "Restart Explorer" {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer.exe
    }
}

# ============================================================
# STEP 10: DEFENDER + TIMER
# ============================================================
UI-Section -Title "Phase 10: Defender and Timer Resolution"

Run-Step "Removing toolkit-added Defender exclusions" {
    Restore-ToolkitDefenderExclusions | Out-Null
}
Run-Step "Stopping and removing STR service" {
    if (Get-Service -Name "STR" -ErrorAction SilentlyContinue) {
        Stop-Service -Name "STR" -Force -ErrorAction SilentlyContinue
        sc.exe delete "STR" 2>&1 | Out-Null
        Start-Sleep -Seconds 2
    }
    Remove-Item "$env:SystemRoot\SetTimerResolutionService.exe" -Force -ErrorAction SilentlyContinue
    reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "GlobalTimerResolutionRequests" /f 2>&1 | Out-Null
}

# ============================================================
# SUMMARY
# ============================================================
UI-Summary -DoneMessage "Revert Everything complete" -Details @(
    "Manifest:   $manifestPath",
    "Follow-up:  Reinstall removed apps from Microsoft Store or winget if needed.",
    "Follow-up:  Any external tools run after Apply Everything still need manual cleanup."
) -RevertHint "If something still looks off after reboot, run Verify and compare against GUIDE.md."
UI-Note -Message "Some broad registry areas still use default-based rollback." -Color $script:UI_Warning
UI-Note -Message "Reboot is required for all rollback changes to take effect." -Color $script:UI_Warning

if (UI-AskYesNo -Prompt "Reboot now?") {
    UI-Note -Message "Rebooting in 5 seconds..." -Color $script:UI_Warning
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    UI-Note -Message "Remember to reboot." -Color $script:UI_Warning
    UI-Exit
}
