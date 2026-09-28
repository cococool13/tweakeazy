# ============================================================
# Show Mouse Info — connected mice + reported polling
# Windows 11 Gaming Optimization Guide
# Source: FR33THYFR33THY/Ultimate — read-only mouse enumeration.
# Copyright FR33THY (MIT) for the category idea.
# ============================================================
# Tier: Safe (read-only)
#
# Enumerates connected HID mouse devices via PnP and reports the
# registry-claimed polling rate where Windows exposes it.
# No manifest writes. No mutations. SampleRate is the rate the
# driver surfaces, not a measurement under load.
#
# Lives in launcher category [12] Hardware (folder "12 hardware").
# The broader HID audit (mouse, keyboard, and gamepad) is already
# check-input-polling.ps1 in this same folder.
#
# Run from the launcher [12] submenu or directly.
# ============================================================

. "$PSScriptRoot\..\lib\ui-helpers.ps1"

UI-Header -Title "Mouse Info" -Subtitle "Read-only enumeration of connected mice"

$mice = @(Get-PnpDevice -PresentOnly -Class Mouse -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "OK" })

if ($mice.Count -eq 0) {
    UI-Note -Message "No connected mouse devices detected." -Color $script:UI_Warning
    Read-Host "Press Enter to exit"
    exit 0
}

UI-KeyValue -Label "Detected" -Value "$($mice.Count) mouse device(s)"
Write-Host ""

foreach ($m in $mice) {
    Write-Host "  - $($m.FriendlyName)" -ForegroundColor White
    Write-Host "      Class:    Mouse" -ForegroundColor Gray
    Write-Host "      InstanceId: $($m.InstanceId)" -ForegroundColor Gray

    # Try to read SampleRate from the device parameters key (where some
    # mice expose their report-rate setting). Not all devices populate this.
    $devParamPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($m.InstanceId)\Device Parameters"
    $sampleRate = (Get-ItemProperty -Path $devParamPath -Name "SampleRate" -ErrorAction SilentlyContinue).SampleRate
    if ($sampleRate) {
        Write-Host "      Reported polling: ${sampleRate} Hz" -ForegroundColor Green
    } else {
        Write-Host "      Reported polling: (not exposed by driver)" -ForegroundColor Gray
    }
    Write-Host ""
}

Write-Host "  This script is read-only. Reported polling is the rate" -ForegroundColor Gray
Write-Host "  the driver surfaces. For mouse, keyboard, and gamepad" -ForegroundColor Gray
Write-Host "  in one pass, run check-input-polling.ps1 in this folder." -ForegroundColor Gray
Write-Host ""
Read-Host "Press Enter to exit"
