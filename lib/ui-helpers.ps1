# ============================================================
# Shared UI Helper Functions
# Windows 11 Gaming Optimization Toolkit
# ============================================================

$script:UI_Header = "Cyan"
$script:UI_Section = "DarkGray"
$script:UI_Success = "Green"
$script:UI_Error = "Red"
$script:UI_Warning = "Yellow"
$script:UI_Info = "Gray"
$script:UI_Label = "White"
$script:UI_Soft = "DarkGray"

$script:UI_Succeeded = 0
$script:UI_Failed = 0
$script:UI_Warned = 0

function UI-ResetCounters {
    $script:UI_Succeeded = 0
    $script:UI_Failed = 0
    $script:UI_Warned = 0
}

function UI-RequireAdmin {
    param([string]$ScriptName = "This script")

    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host ""
        Write-Host "  [ERROR] $ScriptName must be run as Administrator." -ForegroundColor $script:UI_Error
        Write-Host "  Right-click the script > 'Run with PowerShell' (as Admin)" -ForegroundColor $script:UI_Error
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
}

function UI-Header {
    param(
        [string]$Title,
        [string]$Subtitle = "",
        [string]$Color = $script:UI_Header
    )

    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor $Color
    Write-Host "    $Title" -ForegroundColor $Color
    if ($Subtitle) {
        Write-Host "    $Subtitle" -ForegroundColor $script:UI_Label
    }
    Write-Host "  ============================================================" -ForegroundColor $Color
    Write-Host ""
}

function UI-Section {
    param(
        [string]$Title,
        [string]$Context = ""
    )

    Write-Host ""
    Write-Host "  ------------------------------------------------------------" -ForegroundColor $script:UI_Section
    Write-Host "    $Title" -ForegroundColor $script:UI_Label
    if ($Context) {
        Write-Host "    $Context" -ForegroundColor $script:UI_Info
    }
    Write-Host "  ------------------------------------------------------------" -ForegroundColor $script:UI_Section
    Write-Host ""
}

function UI-Note {
    param(
        [string]$Message,
        [string]$Color = $script:UI_Info
    )

    Write-Host "  $Message" -ForegroundColor $Color
}

function UI-KeyValue {
    param(
        [string]$Label,
        [string]$Value,
        [string]$Color = $script:UI_Label
    )

    Write-Host ("  {0,-15} {1}" -f ("${Label}:"), $Value) -ForegroundColor $Color
}

function UI-ShowProfile {
    # PSAvoidAssignmentToAutomaticVariable: PowerShell's automatic
    # $Profile is the user's profile-script path. The parameter inside
    # this function is a *machine profile* (CPU/GPU/RAM/OS metadata),
    # renamed to avoid shadowing the automatic in calling scope.
    param([Alias('Profile')]$MachineProfile)

    if (-not $MachineProfile) {
        return
    }

    UI-KeyValue -Label "Machine" -Value ("{0} {1}" -f $MachineProfile.manufacturer, $MachineProfile.model)
    UI-KeyValue -Label "Windows" -Value $MachineProfile.windowsCaption -Color $script:UI_Info
    UI-KeyValue -Label "Power" -Value $MachineProfile.powerState -Color $script:UI_Info
    UI-KeyValue -Label "Graphics" -Value ("{0} GPU(s) | Hybrid {1}" -f $MachineProfile.gpuCount, $MachineProfile.isHybridGraphics) -Color $script:UI_Info
    UI-KeyValue -Label "Domain" -Value ([string]$MachineProfile.partOfDomain) -Color $script:UI_Info
}

function UI-Step {
    param(
        [string]$Label,
        [scriptblock]$Action,
        [switch]$NonCritical
    )

    Write-Host "    $Label..." -NoNewline -ForegroundColor $script:UI_Info
    try {
        & $Action
        Write-Host " Done" -ForegroundColor $script:UI_Success
        $script:UI_Succeeded++
    } catch {
        if ($NonCritical) {
            Write-Host " Skipped" -ForegroundColor $script:UI_Warning
            $script:UI_Warned++
        } else {
            Write-Host " Failed" -ForegroundColor $script:UI_Error
            Write-Host "      $($_.Exception.Message)" -ForegroundColor $script:UI_Error
            $script:UI_Failed++
        }
    }
}

function UI-Skip {
    param(
        [string]$Label,
        [string]$Reason
    )

    Write-Host "    $Label... Skipped ($Reason)" -ForegroundColor $script:UI_Warning
    $script:UI_Warned++
}

function UI-Summary {
    param(
        [string]$DoneMessage = "Operation complete",
        [string[]]$Details = @(),
        [string]$RevertHint = ""
    )

    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor $script:UI_Header
    if ($script:UI_Failed -eq 0) {
        Write-Host "    [DONE] $DoneMessage" -ForegroundColor $script:UI_Success
    } else {
        Write-Host "    [DONE] $DoneMessage (with errors)" -ForegroundColor $script:UI_Warning
    }
    Write-Host ""
    Write-Host "    Succeeded: $($script:UI_Succeeded)" -ForegroundColor $script:UI_Success
    if ($script:UI_Warned -gt 0) {
        Write-Host "    Skipped:   $($script:UI_Warned)" -ForegroundColor $script:UI_Warning
    }
    if ($script:UI_Failed -gt 0) {
        Write-Host "    Failed:    $($script:UI_Failed)" -ForegroundColor $script:UI_Error
    }
    foreach ($detail in $Details) {
        Write-Host "    $detail" -ForegroundColor $script:UI_Info
    }
    if ($RevertHint) {
        Write-Host "    To revert: $RevertHint" -ForegroundColor $script:UI_Info
    }
    Write-Host "  ============================================================" -ForegroundColor $script:UI_Header
    Write-Host ""
}

function UI-Confirm {
    param(
        [string]$Message = "Continue?",
        [string[]]$Warnings = @()
    )

    Write-Host ""
    foreach ($warning in $Warnings) {
        Write-Host "    [!] $warning" -ForegroundColor $script:UI_Warning
    }
    if ($Message) {
        Write-Host "    $Message" -ForegroundColor $script:UI_Info
    }
    Write-Host "    Press Ctrl+C to cancel, or" -ForegroundColor $script:UI_Warning
    Read-Host "    Press Enter to continue"
}

function UI-AskYesNo {
    param(
        [string]$Prompt,
        [bool]$DefaultNo = $true
    )

    $suffix = if ($DefaultNo) { " (y/N)" } else { " (Y/n)" }
    $response = Read-Host "$Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($response)) {
        return -not $DefaultNo
    }
    return $response.Trim().ToUpper() -eq "Y"
}

function UI-Exit {
    Write-Host ""
    Read-Host "  Press Enter to exit"
}
