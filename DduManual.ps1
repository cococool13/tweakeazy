param(
    [switch]$PrepareSafeMode,
    [switch]$Automatic
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    exit
}

$Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
Clear-Host
$ProgressPreference = "SilentlyContinue"

. "$PSScriptRoot\lib\download-helpers.ps1"
. "$PSScriptRoot\lib\version-manifest.ps1"

$stageRoot = Join-Path $env:ProgramData "GamingOpt"
$dduRoot = Join-Path $stageRoot "DDU"
$resumeScriptPath = Join-Path $stageRoot "DDU-Resume.ps1"
$leaveSafeMode = Join-Path $stageRoot "Leave-Safe-Mode.cmd"
$launchLog = Join-Path $stageRoot "DDU-Auto.log"
# Note: $sevenZipInstaller used to live here; the 7zip auto-bootstrap path
# was removed when Ensure-7Zip switched to winget. Path kept commented for
# historical reference if the manual installer fallback is revived.
# $sevenZipInstaller = Join-Path $env:TEMP "7zip-installer.exe"
$dduInstaller = Join-Path $env:TEMP "DDU-setup.exe"
$runOnceName = "*!GamingOpt-DDU"
# Pre-DDU SearchOrderConfig snapshot. Held is true only after
# Set-DduDriverSearchPolicy actually runs; Handoff means the Safe Mode
# resume script owns the restore across reboot.
$script:DriverSearchPrior = $null
$script:DriverSearchHeld = $false
$script:DriverSearchHandoff = $false

# Fetch DDU version info from manifest (GitHub → cache → bundled)
$dduManifest = Get-ToolManifest -Name "ddu"
$dduDownloadUrl = $dduManifest.url
$expectedDduSha256 = $dduManifest.sha256

# Shared helpers (Write-Info, Get-FileFromWeb, Ensure-Internet, Ensure-Directory,
# Ensure-7Zip, Test-FileSha256, Test-FileAuthenticode) loaded from lib/download-helpers.ps1

function Stage-DduPayload {
    Ensure-Directory -Path $stageRoot
    Ensure-Directory -Path $dduRoot

    $sevenZipExe = Ensure-7Zip

    Write-Info "Downloading DDU v$($dduManifest.version)..."
    Get-FileFromWeb -Url $dduDownloadUrl -File $dduInstaller
    if (-not (Test-Path $dduInstaller) -or (Get-Item $dduInstaller).Length -lt 100000) {
        throw "DDU download failed"
    }
    if (-not (Test-FileSha256 -Path $dduInstaller -ExpectedHash $expectedDduSha256)) {
        throw "DDU installer hash mismatch"
    }

    Remove-Item -Path (Join-Path $dduRoot "*") -Recurse -Force -ErrorAction SilentlyContinue
    & $sevenZipExe x $dduInstaller "-o$dduRoot" -y | Out-Null

    $dduExe = Join-Path $dduRoot "Display Driver Uninstaller.exe"
    if (-not (Test-Path $dduExe)) {
        throw "DDU extraction failed"
    }

    $dduSettingsDir = Join-Path $dduRoot "Settings"
    Ensure-Directory -Path $dduSettingsDir

    # Keep the generated Settings.xml version aligned with the verified DDU
    # payload from versions.json instead of hardcoding a second copy here.
    $dduSettingsVersion = [string]$dduManifest.version

    @"
<?xml version="1.0" encoding="utf-8"?>
<DisplayDriverUninstaller Version="$dduSettingsVersion">
	<Settings>
		<SelectedLanguage>en-US</SelectedLanguage>
		<RemoveMonitors>True</RemoveMonitors>
		<RemoveCrimsonCache>True</RemoveCrimsonCache>
		<RemoveAMDDirs>True</RemoveAMDDirs>
		<RemoveAudioBus>True</RemoveAudioBus>
		<RemoveAMDKMPFD>True</RemoveAMDKMPFD>
		<RemoveNvidiaDirs>True</RemoveNvidiaDirs>
		<RemovePhysX>True</RemovePhysX>
		<Remove3DTVPlay>True</Remove3DTVPlay>
		<RemoveGFE>True</RemoveGFE>
		<RemoveNVBROADCAST>True</RemoveNVBROADCAST>
		<RemoveNVCP>True</RemoveNVCP>
		<RemoveINTELCP>True</RemoveINTELCP>
		<RemoveINTELIGS>True</RemoveINTELIGS>
		<RemoveOneAPI>True</RemoveOneAPI>
		<RemoveEnduranceGaming>True</RemoveEnduranceGaming>
		<RemoveIntelNpu>True</RemoveIntelNpu>
		<RemoveAMDCP>True</RemoveAMDCP>
		<UseRoamingConfig>False</UseRoamingConfig>
		<CheckUpdates>False</CheckUpdates>
		<CreateRestorePoint>False</CreateRestorePoint>
		<SaveLogs>True</SaveLogs>
		<RemoveVulkan>True</RemoveVulkan>
		<ShowOffer>False</ShowOffer>
		<EnableSafeModeDialog>False</EnableSafeModeDialog>
		<PreventWinUpdate>True</PreventWinUpdate>
		<UsedBCD>False</UsedBCD>
		<KeepNVCPopt>False</KeepNVCPopt>
		<RememberLastChoice>False</RememberLastChoice>
		<LastSelectedGPUIndex>0</LastSelectedGPUIndex>
		<LastSelectedTypeIndex>0</LastSelectedTypeIndex>
	</Settings>
</DisplayDriverUninstaller>
"@ | Set-Content -Path (Join-Path $dduSettingsDir "Settings.xml") -Force

    Set-ItemProperty -Path (Join-Path $dduSettingsDir "Settings.xml") -Name IsReadOnly -Value $true

    @'
@echo off
bcdedit /deletevalue {current} safeboot >nul 2>&1
shutdown -r -t 5
'@ | Set-Content -Path $leaveSafeMode -Force

    return $dduExe
}

function New-DduResumeScript {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]$DduExe,
        [string[]]$DduArguments,
        [switch]$ChainDriverInstall,
        [object]$DriverSearchPrior
    )

    $quotedArgs = @($DduArguments | ForEach-Object { "'{0}'" -f $_.Replace("'", "''") }) -join ", "
    $argumentsArray = if ([string]::IsNullOrWhiteSpace($quotedArgs)) { "@()" } else { "@($quotedArgs)" }
    $driverSearchLib = Join-Path $PSScriptRoot 'lib\download-helpers.ps1'
    $driverSearchRestoreBlock = Get-DduDriverSearchRestoreBlock -Prior $DriverSearchPrior -LibPath $driverSearchLib

    # Resolve the GPU driver install script path (relative to repo root)
    $gpuInstallScript = Join-Path $PSScriptRoot "6 gpu\install-gpu-driver.ps1"
    $driverInstallRunOnceName = "*!GamingOpt-DriverInstall"

    # Build the optional driver-install RunOnce block
    $driverInstallBlock = ""
    if ($ChainDriverInstall -and (Test-Path $gpuInstallScript)) {
        $driverInstallBlock = @"

    # Chain: register driver install for next normal-mode boot
    `$driverInstallScript = '$gpuInstallScript'
    if (Test-Path `$driverInstallScript) {
        New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Force | Out-Null
        `$driverCmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Maximized -File "' + `$driverInstallScript + '" -PostDdu'
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name '$driverInstallRunOnceName' -Value `$driverCmd -PropertyType String -Force | Out-Null
        Write-Host '[INFO] GPU driver install will run after next reboot.' -ForegroundColor Cyan
    }
"@
    }

    $scriptBody = @"
`$ErrorActionPreference = 'Continue'
`$Host.UI.RawUI.WindowTitle = 'GamingOpt DDU Resume'
Start-Transcript -Path '$launchLog' -Append -Force | Out-Null

try {
    cmd /c "bcdedit /deletevalue {current} safeboot" 2>&1 | Out-Null
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name '$runOnceName' -ErrorAction SilentlyContinue

    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
        `$quotedSelf = '"' + `$PSCommandPath + '"'
        Start-Process PowerShell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `$quotedSelf"
        exit
    }

    if (-not (Test-Path '$DduExe')) {
        Write-Host '[ABORT] Staged DDU executable is missing.' -ForegroundColor Red
        Write-Host 'Use the Leave-Safe-Mode helper if you want to reboot immediately.' -ForegroundColor Yellow
$driverSearchRestoreBlock
        exit 1
    }
$driverInstallBlock
    `$dduArguments = $argumentsArray
    try {
        if (`$dduArguments.Count -gt 0) {
            Start-Process -FilePath '$DduExe' -ArgumentList `$dduArguments -Wait
        } else {
            Start-Process -FilePath '$DduExe' -Wait
        }
    } finally {
$driverSearchRestoreBlock
    }
} finally {
    Stop-Transcript | Out-Null
}
"@

    Set-Content -Path $resumeScriptPath -Value $scriptBody -Force
}

function Register-DduRunOnce {
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Force | Out-Null
    $command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Maximized -File `"$resumeScriptPath`""
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name $runOnceName -Value $command -PropertyType String -Force | Out-Null
}

function Remove-DduRunOnce {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param()
    if ($PSCmdlet.ShouldProcess("HKLM:\...\RunOnce\$runOnceName", 'Remove-ItemProperty')) {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name $runOnceName -ErrorAction SilentlyContinue
    }
}

function Restore-HeldDriverSearchPolicy {
    if (-not $script:DriverSearchHeld -or $null -eq $script:DriverSearchPrior) {
        return
    }
    $prior = $script:DriverSearchPrior
    # Clear first so a failed restore cannot recurse through the catch path.
    $script:DriverSearchHeld = $false
    try {
        if ($prior.valueExists) {
            $kind = if ($prior.kind) { [string]$prior.kind } else { 'DWord' }
            Restore-DduDriverSearchPolicy -ValueExisted:$true -PreviousValue $prior.value -PreviousKind $kind
        } else {
            Restore-DduDriverSearchPolicy -ValueExisted:$false
        }
    } catch {
        Write-Host "[WARN] Driver search policy was not restored: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

try {
    Ensure-Internet

    Write-Info "Preparing DDU payload..."
    $dduExe = Stage-DduPayload
    # Manifest must exist before the tracked write so `before` is the
    # pre-DDU value. Same id as Apply Everything: an existing snapshot
    # is left alone.
    Initialize-ToolkitState | Out-Null
    $script:DriverSearchPrior = Set-DduDriverSearchPolicy
    $script:DriverSearchHeld = $null -ne $script:DriverSearchPrior

    Write-Host ""
    Write-Host "DDU staged at:" -ForegroundColor Green
    Write-Host "  $dduExe" -ForegroundColor White
    Write-Host "Safe Mode exit helper:" -ForegroundColor Green
    Write-Host "  $leaveSafeMode" -ForegroundColor White
    Write-Host ""

    if ($PrepareSafeMode) {
        $dduArguments = if ($Automatic) {
            @("-CleanSoundBlaster", "-CleanRealtek", "-CleanAllGpus", "-Restart")
        } else {
            @()
        }

        New-DduResumeScript -DduExe $dduExe -DduArguments $dduArguments -ChainDriverInstall:$Automatic -DriverSearchPrior $script:DriverSearchPrior
        Register-DduRunOnce

        Write-Info "Scheduling next boot into Safe Mode..."
        cmd /c "bcdedit /set {current} safeboot minimal"
        if ($LASTEXITCODE -ne 0) {
            Remove-DduRunOnce
            throw "Failed to schedule Safe Mode boot"
        }
        # Resume script restores SearchOrderConfig after DDU exits.
        $script:DriverSearchHandoff = $true

        if ($Automatic) {
            Write-Host "The next admin login in Safe Mode will auto-run DDU with the aggressive clean-and-restart arguments." -ForegroundColor Yellow
        } else {
            Write-Host "The next admin login in Safe Mode will auto-launch DDU for a manual run." -ForegroundColor Yellow
        }
        Write-Host "Safe boot is cleared at handoff time to prevent boot loops if DDU fails." -ForegroundColor Yellow
        Write-Host "Driver search stays off only until DDU exits; the resume script restores the previous SearchOrderConfig." -ForegroundColor Yellow
        Write-Host "Rebooting in 5 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        shutdown -r -t 0
        exit 0
    }

    Write-Host "Launching DDU in the current session." -ForegroundColor Yellow
    Write-Host "Use DduAuto.ps1 for the unattended Safe Mode handoff." -ForegroundColor Yellow
    Write-Host "Driver search is restored when DDU exits." -ForegroundColor Yellow
    try {
        Start-Process -FilePath $dduExe -Wait
    } finally {
        Restore-HeldDriverSearchPolicy
    }
    Pause
} catch {
    if (-not $script:DriverSearchHandoff) {
        Restore-HeldDriverSearchPolicy
    }
    Write-Host "[ABORT] $($_.Exception.Message)" -ForegroundColor Red
    Pause
    exit 1
}
