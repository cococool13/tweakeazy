# ============================================================
# VERIFY TWEAKS — Health Check Report
# Windows 11 Gaming Optimization Guide
# ============================================================
#
# Reports current tweak state with manifest awareness:
#   - APPLIED BY TOOLKIT
#   - ALREADY PRESENT
#   - SKIPPED UNSUPPORTED
#   - DRIFTED / FAILED
#
# Does NOT change anything.
# ============================================================

. "$PSScriptRoot\..\lib\toolkit-state.ps1"
. "$PSScriptRoot\..\lib\ui-helpers.ps1"
. "$PSScriptRoot\..\lib\gpu-detection.ps1"

$Host.UI.RawUI.WindowTitle = "Gaming Optimization — Verification Report"
UI-Header -Title "Gaming Optimization Health Check" -Subtitle "Verify the same phases exposed by the launcher and guide"

$manifest = Get-ToolkitState
$pass = 0
$fail = 0
$warn = 0
$applied = 0
$preexisting = 0
$unsupported = 0
$drifted = 0

function Write-CheckStatus {
    param(
        [string]$Label,
        [string]$Status,
        [ConsoleColor]$Color
    )
    Write-Host ("  [{0}] {1}" -f $Status, $Label) -ForegroundColor $Color
}

function Check {
    param(
        [string]$Label,
        [scriptblock]$Test,
        [string]$StepKey = "",
        [scriptblock]$StepKeyResolver = $null
    )

    try {
        $result = & $Test
        $resolvedStepKey = if ($StepKeyResolver) { & $StepKeyResolver } else { $StepKey }
        if ($result -eq "SKIP") {
            Write-CheckStatus -Label $Label -Status "SKIPPED" -Color DarkYellow
            $script:unsupported++
            return
        }
        if ($result -eq "WARN") {
            Write-CheckStatus -Label $Label -Status "WARN" -Color Yellow
            $script:warn++
            return
        }
        if ($result) {
            $recorded = if ($resolvedStepKey) { Get-ToolkitRecordedStatus -Key $resolvedStepKey } else { $null }
            if ($recorded -eq "applied") {
                Write-CheckStatus -Label $Label -Status "APPLIED" -Color Green
                $script:applied++
            } else {
                Write-CheckStatus -Label $Label -Status "PREEXISTING" -Color Cyan
                $script:preexisting++
            }
            $script:pass++
            return
        }

        if ($resolvedStepKey -and (Get-ToolkitRecordedStatus -Key $resolvedStepKey)) {
            Write-CheckStatus -Label $Label -Status "DRIFTED" -Color Red
            $script:drifted++
        } else {
            Write-CheckStatus -Label $Label -Status "FAIL" -Color Red
        }
        $script:fail++
    } catch {
        Write-CheckStatus -Label "$Label — $($_.Exception.Message)" -Status "ERROR" -Color DarkGray
    }
}

UI-Section -Title "Manifest"
if ($manifest) {
    UI-Note -Message "Manifest found: $(Get-ToolkitManifestPath)"
    UI-Note -Message "Created: $($manifest.createdAt)"
    UI-Note -Message "Package removals tracked: $(@($manifest.packages.removed).Count)"
} else {
    UI-Note -Message "No manifest found. Existing settings will be treated as preexisting." -Color $script:UI_Warning
}

# ============================================================
# POWER PLAN
# ============================================================
UI-Section -Title "Phase 1: Power Baseline"

Check "Ultimate Performance plan is active" {
    $active = powercfg /getactivescheme 2>&1
    $active -match "Ultimate Performance" -or $active -match "99999999-9999-9999-9999-999999999999"
} "power:plan"

Check "Hibernate is disabled" {
    $val = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "HibernateEnabled" -ErrorAction SilentlyContinue).HibernateEnabled
    $val -eq 0
}

Check "Fast Startup is disabled" {
    $val = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -ErrorAction SilentlyContinue).HiberbootEnabled
    $val -eq 0
}

# ============================================================
# WINDOWS SETTINGS
# ============================================================
UI-Section -Title "Phase 2: Windows Settings"

Check "Transparency effects disabled" {
    (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -ErrorAction SilentlyContinue).EnableTransparency -eq 0
} "reg:EnableTransparency"

Check "Background apps disabled" {
    (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -ErrorAction SilentlyContinue).GlobalUserDisabled -eq 1
} "reg:GlobalUserDisabled"

# HwSchMode is one GraphicsDrivers value. Every writer tracks it as
# reg:HwSchMode (Apply, GPU configure, the hags pair). Vendor ids
# nv:HwSchMode / amd:HwSchMode / intel:HwSchMode are retired: capture-once
# is per id, so those entries can store the post-apply value 2 as the
# original. This check keys only reg:HwSchMode.
Check "Hardware Accelerated GPU Scheduling enabled" {
    (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -ErrorAction SilentlyContinue).HwSchMode -eq 2
} "reg:HwSchMode"
UI-Note -Message "HwSchMode rollback id is reg:HwSchMode only (not nv:/amd:/intel:)."
if ($manifest -and $manifest.PSObject.Properties["registry"] -and $manifest.registry) {
    foreach ($retiredHwSchId in @("nv:HwSchMode", "amd:HwSchMode", "intel:HwSchMode")) {
        if (Test-ToolkitMapHasKey -Map $manifest.registry -Key $retiredHwSchId) {
            UI-Note -Message "Retired manifest id $retiredHwSchId ignored. Its captured original can be post-apply value 2; vendor revert does not restore it." -Color $script:UI_Warning
            $warn++
        }
    }
}

Check "Notifications suppressed" {
    (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "NOC_GLOBAL_SETTING_TOASTS_ENABLED" -ErrorAction SilentlyContinue).NOC_GLOBAL_SETTING_TOASTS_ENABLED -eq 0
} "reg:ToastsEnabled"

Check "Edge Startup Boost disabled" {
    (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "StartupBoostEnabled" -ErrorAction SilentlyContinue).StartupBoostEnabled -eq 0
} "reg:EdgeStartupBoostEnabled"

Check "Edge background mode disabled" {
    (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -ErrorAction SilentlyContinue).BackgroundModeEnabled -eq 0
} "reg:EdgeBackgroundModeEnabled"

Check "Storage Sense disabled" {
    # Per-user toggle; value name is the literal string "01" (DWORD).
    (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -ErrorAction SilentlyContinue)."01" -eq 0
} "reg:StorageSenseMaster"

# ============================================================
# SERVICES
# ============================================================
UI-Section -Title "Phase 3: Services"

foreach ($svc in @(
        @("DiagTrack", "DiagTrack"),
        @("PhoneSvc", "Phone Service"),
        @("lfsvc", "Geolocation Service"),
        @("RetailDemo", "Retail Demo"),
        @("MapsBroker", "Downloaded Maps Manager"),
        @("Fax", "Fax"),
        @("Spooler", "Print Spooler"),
        @("WSearch", "Windows Search"),
        @("CscService", "Offline Files")
    )) {
    Check "$($svc[1]) disabled" {
        $service = Get-Service -Name $svc[0] -ErrorAction SilentlyContinue
        if (-not $service) { return "SKIP" }
        $service.StartType -eq "Disabled"
    } "service:$($svc[0])"
}

# ============================================================
# REGISTRY + STARTUP
# ============================================================
UI-Section -Title "Phase 4 and 5: Registry Pack and Startup Cleanup"

Check "MenuShowDelay = 0" {
    (Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -ErrorAction SilentlyContinue).MenuShowDelay -eq "0"
}
Check "MouseHoverTime = 10" {
    (Get-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseHoverTime" -ErrorAction SilentlyContinue).MouseHoverTime -eq "10"
}
Check "Network throttling disabled" {
    $val = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -ErrorAction SilentlyContinue).NetworkThrottlingIndex
    $val -eq 0xFFFFFFFF -or $val -eq 4294967295
}
Check "Game Bar / DVR disabled" {
    (Get-ItemProperty "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -ErrorAction SilentlyContinue).GameDVR_Enabled -eq 0
}
Check "OneDrive autostart policy disabled" {
    (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -ErrorAction SilentlyContinue).DisableFileSyncNGSC -eq 1
}
Check "Widgets disabled" {
    (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -ErrorAction SilentlyContinue).AllowNewsAndInterests -eq 0
}
Check "Copilot disabled" {
    (Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -ErrorAction SilentlyContinue).TurnOffWindowsCopilot -eq 1
}
Check "Multiplane Overlay (MPO) disabled" {
    (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name "OverlayTestMode" -ErrorAction SilentlyContinue).OverlayTestMode -eq 5
} "reg:DwmOverlayTestMode"

Check "NTFS last-access updates disabled" {
    (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsDisableLastAccessUpdate" -ErrorAction SilentlyContinue).NtfsDisableLastAccessUpdate -eq 1
} "reg:NtfsDisableLastAccessUpdate"

# ============================================================
# GPU + NETWORK
# ============================================================
UI-Section -Title "Phase 6 to 8: GPU, Network, and Update Path"

$gpuDevices = @(Get-GpuVendor)
if ($gpuDevices.Count -eq 0) {
    Write-CheckStatus -Label "No NVIDIA / AMD / Intel GPUs found" -Status "SKIPPED" -Color DarkYellow
    $unsupported++
} else {
    foreach ($gpu in $gpuDevices) {
        Check "MSI mode enabled for $($gpu.FriendlyName)" {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($gpu.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            (Get-ItemProperty $regPath -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported -eq 1
        } "gpu-msi:$($gpu.InstanceId)"
    }

    if ((Get-ToolkitRecordedStatus -Key "gpu-p0-state") -eq "applied") {
        foreach ($gpu in @($gpuDevices | Where-Object { $_.Vendor -eq "nvidia" })) {
            Check "NVIDIA P0 state forced for $($gpu.FriendlyName)" {
                if (-not $gpu.AdapterRegistryPath) { return "SKIP" }
                $props = Get-ItemProperty $gpu.AdapterRegistryPath -ErrorAction SilentlyContinue
                ($props.PerfLevelSrc -eq 0x2222) -and ($props.DisableDynamicPstate -eq 1)
            } "gpu-p0-state"
        }
    }

    if ((Get-ToolkitRecordedStatus -Key "gpu-amd-ulps") -eq "applied") {
        foreach ($gpu in @($gpuDevices | Where-Object { $_.Vendor -eq "amd" })) {
            Check "AMD ULPS disabled for $($gpu.FriendlyName)" {
                if (-not $gpu.AdapterRegistryPath) { return "SKIP" }
                (Get-ItemProperty $gpu.AdapterRegistryPath -Name "EnableUlps" -ErrorAction SilentlyContinue).EnableUlps -eq 0
            } "gpu-amd-ulps"
        }
    }
}

Check "TCP timestamps disabled" {
    (netsh int tcp show global 2>&1) -match "Timestamps\s*:\s*disabled"
}
Check "RSS enabled" {
    (netsh int tcp show global 2>&1) -match "Receive-Side Scaling State\s*:\s*enabled"
}
Check "Cloudflare / Google DNS present on at least one adapter" {
    $adapters = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $optimized = @("1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4")
    foreach ($adapter in $adapters) {
        foreach ($dns in @($adapter.ServerAddresses)) {
            if ($optimized -contains $dns) {
                $script:LastDnsMatchKey = "dns:$($adapter.InterfaceIndex)"
                return $true
            }
        }
    }
    $script:LastDnsMatchKey = $null
    return $false
} "" { $script:LastDnsMatchKey }

# ============================================================
# WINDOWS UPDATE + SECURITY TRADE-OFFS
# ============================================================
Check "Windows Update auto-restart blocked" {
    (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue).NoAutoRebootWithLoggedOnUsers -eq 1
} "reg:NoAutoRebootWithLoggedOnUsers"

Check "Windows Update service disabled" {
    $service = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    if (-not $service) { return "SKIP" }
    $service.StartType -eq "Disabled"
} "service:wuauserv"

Check "VBS disabled" {
    $vbs = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
    if (-not $vbs) { return "SKIP" }
    $vbs.VirtualizationBasedSecurityStatus -eq 0
} "reg:EnableVBS"

Check "HVCI disabled" {
    $val = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
    if ($null -eq $val) { return "SKIP" }
    $val -eq 0
} "reg:HVCIEnabled"

Check "Spectre / Meltdown mitigations override applied" {
    $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    $override = (Get-ItemProperty $mmPath -Name "FeatureSettingsOverride" -ErrorAction SilentlyContinue).FeatureSettingsOverride
    $mask = (Get-ItemProperty $mmPath -Name "FeatureSettingsOverrideMask" -ErrorAction SilentlyContinue).FeatureSettingsOverrideMask
    ($override -eq 3) -and ($mask -eq 3)
} "reg:FeatureSettingsOverride"

Check "Toolkit-added Defender exclusions are still present" {
    if (-not $manifest -or -not $manifest.defender -or @($manifest.defender.added).Count -eq 0) {
        return "SKIP"
    }
    $current = @((Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath)
    foreach ($path in @($manifest.defender.added)) {
        if ($current -notcontains $path) {
            return $false
        }
    }
    return $true
} "defender:manifest"

# ============================================================
# CUSTOMIZATION + BONUS
# ============================================================
UI-Section -Title "Phase 9 to 12: Customization, Defender, and Bonus Checks"

Check "Classic right-click menu enabled" {
    Test-Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
}
Check "Bing / web results disabled" {
    (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -ErrorAction SilentlyContinue).BingSearchEnabled -eq 0
}
Check "Dark mode enabled" {
    (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue).AppsUseLightTheme -eq 0
}
Check "Timer Resolution Service installed" {
    $service = Get-Service -Name "STR" -ErrorAction SilentlyContinue
    if (-not $service) { return "SKIP" }
    $service.Status -eq "Running"
}

# ============================================================
# SUMMARY
# ============================================================
UI-Header -Title "Health Check Results"
Write-Host "  PASS:                $pass" -ForegroundColor Green
Write-Host "  APPLIED BY TOOLKIT:  $applied" -ForegroundColor Green
Write-Host "  ALREADY PRESENT:     $preexisting" -ForegroundColor Cyan
Write-Host "  SKIPPED UNSUPPORTED: $unsupported" -ForegroundColor DarkYellow
if ($warn -gt 0) {
    Write-Host "  WARN:                $warn" -ForegroundColor Yellow
}
if ($drifted -gt 0) {
    Write-Host "  DRIFTED:             $drifted" -ForegroundColor Red
}
if ($fail -gt 0) {
    Write-Host "  FAIL:                $fail" -ForegroundColor Red
}
Write-Host ""

$total = $pass + $fail
if ($total -gt 0) {
    $pct = [math]::Round(($pass / $total) * 100)
    Write-Host "  Apply Everything coverage: $pct% ($pass/$total tracked checks passing)" -ForegroundColor White
}
if ($manifest) {
    UI-Note -Message "Manifest: $(Get-ToolkitManifestPath)"
    UI-Note -Message "Recorded package removals: $(@($manifest.packages.removed).Count)"
}
UI-Note -Message "Security Trade-off items are intentional in Apply Everything."
UI-Exit
