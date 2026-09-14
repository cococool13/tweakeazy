# ============================================================
# Windows 11 Gaming Toolkit - Launcher
#
# Layout: header / Quick actions / Categories / Tools.
# Reads the manifest at $env:ProgramData\Win11GamingToolkit\state\
# and shows per-category status (applied / drift) when known.
# Pure PS 5.1, no external modules, no ANSI escape sequences.
# ============================================================

. "$PSScriptRoot\lib\toolkit-state.ps1"
. "$PSScriptRoot\lib\ui-helpers.ps1"

$Host.UI.RawUI.WindowTitle = "Win11 Gaming Toolkit"

$script:LauncherUseAscii = $false
$script:LauncherTerminalWidth = 80

function Initialize-LauncherEnvironment {
    if ($Host.Name -match "ISE") {
        $script:LauncherUseAscii = $true
    }
    try {
        $width = $Host.UI.RawUI.WindowSize.Width
        if ($width -and $width -gt 0) {
            $script:LauncherTerminalWidth = [int]$width
        }
    } catch {
        $script:LauncherTerminalWidth = 80
    }
    if ($script:LauncherTerminalWidth -lt 80) {
        $script:LauncherUseAscii = $true
    }
}

# ----- Static menu definition ----------------------------------------------

$script:LauncherCategories = @(
    [PSCustomObject]@{ Key = "0"; Title = "Prerequisites"; Tier = "Safe"; Folder = "0 prerequisites"; StepPrefixes = @("prerequisites", "prereq:") }
    [PSCustomObject]@{ Key = "1"; Title = "Backup"; Tier = "Safe"; Folder = "1 backup"; StepPrefixes = @("backup", "restore-point") }
    [PSCustomObject]@{ Key = "2"; Title = "Power plan"; Tier = "Advanced"; Folder = "2 power plan"; StepPrefixes = @("power-plan", "ultimate-perf", "power") }
    [PSCustomObject]@{ Key = "4"; Title = "Services"; Tier = "Advanced"; Folder = "4 services"; StepPrefixes = @("services-", "service:", "service-") }
    [PSCustomObject]@{ Key = "5"; Title = "Registry tweaks"; Tier = "Advanced"; Folder = "5 registry tweaks"; StepPrefixes = @("reg:", "registry", "mmagent", "mpo", "ntfs-", "edge-bg", "spectre-meltdown", "writecache-flush") }
    [PSCustomObject]@{ Key = "6"; Title = "GPU"; Tier = "Advanced"; Folder = "6 gpu"; StepPrefixes = @("gpu-", "gpu:") }
    [PSCustomObject]@{ Key = "7"; Title = "Network"; Tier = "Safe"; Folder = "7 network"; StepPrefixes = @("network-", "dns-", "dns:", "nic-", "ipv6-") }
    [PSCustomObject]@{ Key = "8"; Title = "Security vs performance"; Tier = "Security Trade-off"; Folder = "8 security vs performance"; StepPrefixes = @("vbs-", "vbs:", "spectre-meltdown", "bcd:nx", "dep-", "hvci", "lsa-") }
    [PSCustomObject]@{ Key = "9"; Title = "Cleanup"; Tier = "Advanced"; Folder = "9 cleanup"; StepPrefixes = @("cleanup", "debloat") }
    [PSCustomObject]@{ Key = "10"; Title = "Verify"; Tier = "Safe"; Folder = "10 verify"; StepPrefixes = @() }
    [PSCustomObject]@{ Key = "11"; Title = "Hardware checks"; Tier = "Safe"; Folder = "11 hardware checks"; StepPrefixes = @() }
    [PSCustomObject]@{ Key = "12"; Title = "Hardware"; Tier = "Safe"; Folder = "12 hardware"; StepPrefixes = @() }
    # Launchers for signed third-party GUIs. No StepPrefixes: these run
    # someone else's tool rather than applying a tracked toolkit step, so
    # they never appear in the manifest or in REVERT-EVERYTHING.
    [PSCustomObject]@{ Key = "13"; Title = "External tools"; Tier = "Advanced"; Folder = "13 external tools"; StepPrefixes = @() }
)

$script:LauncherQuickActions = @(
    [PSCustomObject]@{ Key = "A"; Label = "Apply All"; Description = "All tweaks"; Path = "APPLY-EVERYTHING.ps1" }
    [PSCustomObject]@{ Key = "V"; Label = "Verify status"; Description = ""; Path = "10 verify\verify-tweaks.ps1" }
    [PSCustomObject]@{ Key = "R"; Label = "Revert All"; Description = "rollback to manifest"; Path = "REVERT-EVERYTHING.ps1" }
)

# ----- Manifest snapshot helpers -------------------------------------------

function Get-LauncherManifestSnapshot {
    $snapshot = [PSCustomObject]@{
        State = $null
        StepCount = 0
        ApplyEntries = @()
        AppliedKeys = @()
    }

    $state = $null
    try {
        $state = Get-ToolkitState
    } catch {
        $state = $null
    }
    $snapshot.State = $state
    if (-not $state) {
        return $snapshot
    }

    $stepKeys = @()
    $stepStatus = @{}
    if ($state.PSObject.Properties["steps"] -and $state.steps) {
        if ($state.steps -is [hashtable]) {
            foreach ($entry in $state.steps.GetEnumerator()) {
                $stepKeys += $entry.Key
                $stepStatus[$entry.Key] = $entry.Value.status
            }
        } else {
            foreach ($prop in $state.steps.PSObject.Properties) {
                $stepKeys += $prop.Name
                $stepStatus[$prop.Name] = $prop.Value.status
            }
        }
    }

    $appliedKeys = @()
    foreach ($key in $stepKeys) {
        if ($stepStatus[$key] -eq "applied") {
            $appliedKeys += $key
        }
    }

    $applyEntries = @()
    if ($state.PSObject.Properties["registry"] -and $state.registry) {
        if ($state.registry -is [hashtable]) {
            foreach ($entry in $state.registry.GetEnumerator()) {
                $applyEntries += [PSCustomObject]@{ Id = $entry.Key; Step = $entry.Value.step; Path = $entry.Value.path; Name = $entry.Value.name; Before = $entry.Value.before }
            }
        } else {
            foreach ($prop in $state.registry.PSObject.Properties) {
                $applyEntries += [PSCustomObject]@{ Id = $prop.Name; Step = $prop.Value.step; Path = $prop.Value.path; Name = $prop.Value.name; Before = $prop.Value.before }
            }
        }
    }

    $snapshot.StepCount = $stepKeys.Count
    $snapshot.AppliedKeys = $appliedKeys
    $snapshot.ApplyEntries = $applyEntries
    return $snapshot
}

function Test-CategoryStepMatch {
    param(
        [string]$Key,
        [string[]]$Prefixes
    )
    if (-not $Key -or -not $Prefixes) { return $false }
    foreach ($prefix in $Prefixes) {
        if ($Key -like "$prefix*") { return $true }
    }
    return $false
}

function Get-CategoryStatus {
    param(
        [PSCustomObject]$Category,
        [PSCustomObject]$Snapshot
    )

    if (-not $Snapshot.State) { return "" }
    if ($Category.StepPrefixes.Count -eq 0) { return "" }

    $matched = @($Snapshot.AppliedKeys | Where-Object { Test-CategoryStepMatch -Key $_ -Prefixes $Category.StepPrefixes })
    if ($matched.Count -eq 0) { return "" }

    $relevantApply = @($Snapshot.ApplyEntries | Where-Object { Test-CategoryStepMatch -Key $_.Step -Prefixes $Category.StepPrefixes })
    foreach ($entry in $relevantApply) {
        if (-not $entry.Before) { continue }
        try {
            $current = Get-ToolkitRegistryState -Path $entry.Path -Name $entry.Name
        } catch {
            continue
        }
        if (-not $entry.Before.valueExists) {
            if ($current.valueExists) { continue }
            return "drift"
        }
        if ($current.valueExists -and "$($current.value)" -eq "$($entry.Before.value)") {
            return "drift"
        }
    }
    return "applied"
}

# ----- Rendering primitives -------------------------------------------------

function Get-LauncherTierColor {
    param([string]$Tier)
    switch ($Tier) {
        "Safe" { return $script:UI_Success }
        "Advanced" { return $script:UI_Warning }
        "Security Trade-off" { return $script:UI_Error }
        default { return $script:UI_Info }
    }
}

function Get-LauncherTierLabel {
    param([string]$Tier)
    if ($Tier -eq "Security Trade-off") { return "Trade-off" }
    return $Tier
}

function Write-LauncherSectionLabel {
    param([string]$Label)
    Write-Host ""
    Write-Host ("  {0}" -f $Label) -ForegroundColor $script:UI_Warning
}

function Write-LauncherKeyLine {
    param(
        [string]$Key,
        [string]$Label,
        [string]$Tier,
        [string]$Status,
        [string]$Detail = ""
    )

    $padKey = $Key.PadLeft(4)
    Write-Host "    [" -NoNewline -ForegroundColor $script:UI_Soft
    Write-Host $padKey.Trim() -NoNewline -ForegroundColor $script:UI_Header
    Write-Host "]  " -NoNewline -ForegroundColor $script:UI_Soft

    Write-Host ("{0,-26}" -f $Label) -NoNewline -ForegroundColor $script:UI_Label

    if ($Tier) {
        $tierLabel = Get-LauncherTierLabel -Tier $Tier
        Write-Host ("{0,-13}" -f $tierLabel) -NoNewline -ForegroundColor (Get-LauncherTierColor -Tier $Tier)
    } else {
        Write-Host ("{0,-13}" -f "") -NoNewline
    }

    if ($Status -eq "applied") {
        Write-Host "[OK] applied" -NoNewline -ForegroundColor $script:UI_Header
    } elseif ($Status -eq "drift") {
        Write-Host "!  drift" -NoNewline -ForegroundColor $script:UI_Error
    } elseif ($Detail) {
        Write-Host $Detail -NoNewline -ForegroundColor $script:UI_Soft
    }

    Write-Host ""
}

function Write-LauncherHeader {
    param([PSCustomObject]$Snapshot)

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $adminLabel = if ($isAdmin) { "yes" } else { "no" }

    $build = ""
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) { $build = $os.BuildNumber }
    } catch {
        $build = ""
    }

    $stepCount = if ($Snapshot.State) { $Snapshot.StepCount } else { 0 }

    $left = "Win11 Gaming Toolkit"
    $right = "v$script:ToolkitVersion"
    $width = 70
    if ($script:LauncherTerminalWidth -lt $width + 4) {
        $width = $script:LauncherTerminalWidth - 4
        if ($width -lt 40) { $width = 40 }
    }
    $padInner = $width - $left.Length - $right.Length
    if ($padInner -lt 1) { $padInner = 1 }
    $title = "  " + $left + (" " * $padInner) + $right + "  "

    $stats = "  Admin: {0}   Build: {1}   Manifest: {2} entries" -f $adminLabel, $build, $stepCount
    if ($stats.Length -gt $width + 4) {
        $stats = $stats.Substring(0, $width + 4)
    }
    $statsPad = $width + 4 - $stats.Length
    if ($statsPad -gt 0) { $stats = $stats + (" " * $statsPad) }

    $borderChar = if ($script:LauncherUseAscii) { "-" } else { [char]0x2500 }
    $cornerTL = if ($script:LauncherUseAscii) { "+" } else { [char]0x250C }
    $cornerTR = if ($script:LauncherUseAscii) { "+" } else { [char]0x2510 }
    $cornerBL = if ($script:LauncherUseAscii) { "+" } else { [char]0x2514 }
    $cornerBR = if ($script:LauncherUseAscii) { "+" } else { [char]0x2518 }
    $vert = if ($script:LauncherUseAscii) { "|" } else { [char]0x2502 }

    $borderLine = ($borderChar.ToString() * ($width + 2))
    $top = "$cornerTL$borderLine$cornerTR"
    $bottom = "$cornerBL$borderLine$cornerBR"

    $titleLine = "$vert$title$vert"
    $statsLine = "$vert$stats$vert"

    Write-Host ""
    Write-Host $top -ForegroundColor $script:UI_Soft
    Write-Host $titleLine
    Write-Host $statsLine -ForegroundColor $script:UI_Soft
    Write-Host $bottom -ForegroundColor $script:UI_Soft
}

# ----- Main menu render -----------------------------------------------------

function Show-MainMenu {
    param([PSCustomObject]$Snapshot)

    Clear-Host
    Write-LauncherHeader -Snapshot $Snapshot

    Write-LauncherSectionLabel -Label "Quick actions"
    foreach ($action in $script:LauncherQuickActions) {
        Write-LauncherKeyLine -Key $action.Key -Label $action.Label -Tier "" -Status "" -Detail $action.Description
    }

    Write-LauncherSectionLabel -Label "Categories"
    foreach ($category in $script:LauncherCategories) {
        $status = Get-CategoryStatus -Category $category -Snapshot $Snapshot
        Write-LauncherKeyLine -Key $category.Key -Label $category.Title -Tier $category.Tier -Status $status
    }

    Write-LauncherSectionLabel -Label "Tools"
    Write-Host "    [" -NoNewline -ForegroundColor $script:UI_Soft
    Write-Host "M" -NoNewline -ForegroundColor $script:UI_Header
    Write-Host "]  View manifest          [" -NoNewline -ForegroundColor $script:UI_Soft
    Write-Host "L" -NoNewline -ForegroundColor $script:UI_Header
    Write-Host "]  View recent log" -ForegroundColor $script:UI_Soft
    Write-Host "    [" -NoNewline -ForegroundColor $script:UI_Soft
    Write-Host "B" -NoNewline -ForegroundColor $script:UI_Header
    Write-Host "]  Regenerate baseline    [" -NoNewline -ForegroundColor $script:UI_Soft
    Write-Host "?" -NoNewline -ForegroundColor $script:UI_Header
    Write-Host "]  Help     [" -NoNewline -ForegroundColor $script:UI_Soft
    Write-Host "Q" -NoNewline -ForegroundColor $script:UI_Header
    Write-Host "]  Quit" -ForegroundColor $script:UI_Soft

    Write-Host ""
}

# ----- Category submenu render ---------------------------------------------

function Get-CategoryFiles {
    param([string]$Folder)

    $root = Join-Path $PSScriptRoot $Folder
    if (-not (Test-Path -LiteralPath $root)) { return @() }

    $files = Get-ChildItem -LiteralPath $root -Recurse -File -Include "*.ps1", "*.bat", "*.reg" -ErrorAction SilentlyContinue
    return @($files | Sort-Object FullName)
}

function Show-CategoryMenu {
    param([PSCustomObject]$Category)

    while ($true) {
        Clear-Host
        $files = Get-CategoryFiles -Folder $Category.Folder
        Write-Host ""
        Write-Host ("  {0}  [{1}]" -f $Category.Title, $Category.Key) -ForegroundColor $script:UI_Header
        Write-Host ("  Tier: {0}" -f (Get-LauncherTierLabel -Tier $Category.Tier)) -ForegroundColor (Get-LauncherTierColor -Tier $Category.Tier)
        Write-Host ("  Folder: {0}" -f $Category.Folder) -ForegroundColor $script:UI_Soft
        Write-Host ""

        if ($files.Count -eq 0) {
            Write-Host "    (no scripts in this folder)" -ForegroundColor $script:UI_Soft
            Write-Host ""
            Write-Host "    [Q] Back" -ForegroundColor $script:UI_Soft
            Write-Host ""
            Read-Host "  Press Enter or Q to return" | Out-Null
            return
        }

        $index = 1
        $entries = @()
        foreach ($file in $files) {
            $rel = $file.FullName.Substring($PSScriptRoot.Length).TrimStart("\", "/")
            Write-Host "    [" -NoNewline -ForegroundColor $script:UI_Soft
            Write-Host ("{0,2}" -f $index) -NoNewline -ForegroundColor $script:UI_Header
            Write-Host "]  " -NoNewline -ForegroundColor $script:UI_Soft
            Write-Host $rel -ForegroundColor $script:UI_Label
            $entries += [PSCustomObject]@{ Index = $index; File = $file; Relative = $rel }
            $index++
        }

        Write-Host ""
        Write-Host "    [Q] Back to main menu" -ForegroundColor $script:UI_Soft
        Write-Host ""

        $choice = (Read-Host "  Choose").Trim()
        if (-not $choice) { continue }
        if ($choice -ieq "Q") { return }

        $num = 0
        if ([int]::TryParse($choice, [ref]$num)) {
            $entry = $entries | Where-Object { $_.Index -eq $num }
            if ($entry) {
                Invoke-CategoryFile -File $entry.File
                continue
            }
        }
        Write-Host "  Invalid choice." -ForegroundColor $script:UI_Warning
        Start-Sleep -Seconds 1
    }
}

function Invoke-CategoryFile {
    param($File)

    Write-Host ""
    Write-Host ("  Running: {0}" -f $File.Name) -ForegroundColor $script:UI_Header
    Write-Host ""

    switch -Regex ($File.Extension) {
        "\.ps1$" {
            & $File.FullName
        }
        "\.bat$" {
            cmd /c "`"$($File.FullName)`""
        }
        "\.reg$" {
            reg import "$($File.FullName)"
        }
        default {
            Write-Host "  Unknown file type." -ForegroundColor $script:UI_Warning
        }
    }

    Write-Host ""
    Read-Host "  Press Enter to continue"
}

# ----- Tool actions ---------------------------------------------------------

function Invoke-QuickAction {
    param([string]$Key)

    $action = $script:LauncherQuickActions | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    if (-not $action) { return }

    $full = Join-Path $PSScriptRoot $action.Path
    if (-not (Test-Path -LiteralPath $full)) {
        Write-Host ("  Missing: {0}" -f $action.Path) -ForegroundColor $script:UI_Error
        Read-Host "  Press Enter"
        return
    }

    Write-Host ""
    Write-Host ("  Running: {0}" -f $action.Label) -ForegroundColor $script:UI_Header
    Write-Host ""

    if ($Key -eq "A") {
        # Apply All: prompt for the Security Trade-offs gate (default OFF).
        # Phases 9 (Windows Update suppression) and 10 (VBS / HVCI / LSA /
        # Spectre) are skipped unless the user explicitly opts in here.
        Write-Host "  Security Trade-offs (default: NO)" -ForegroundColor $script:UI_Warning
        Write-Host "  Include Phase 9 (Windows Update suppression) and Phase 10" -ForegroundColor $script:UI_Soft
        Write-Host "  (VBS / HVCI / LSA / Spectre/Meltdown disable)?" -ForegroundColor $script:UI_Soft
        Write-Host ""
        Write-Host "  [!] ANTI-CHEAT: HVCI/VBS changes may break BattlEye and EAC on" -ForegroundColor $script:UI_Error
        Write-Host "      Win11 24H2+ (R6 Siege and similar titles)." -ForegroundColor $script:UI_Error
        Write-Host "  [!] Windows Update suppression stalls anti-cheat/security patches." -ForegroundColor $script:UI_Error
        Write-Host ""
        $includeTradeoffs = UI-AskYesNo -Prompt "  Include Security Trade-offs?" -DefaultNo $true
        Write-Host ""
        if ($includeTradeoffs) {
            & $full -IncludeSecurityTradeoffs
        } else {
            & $full
        }
    } else {
        & $full
    }

    Write-Host ""
    Read-Host "  Press Enter to return"
}

function Invoke-ViewManifest {
    $path = Get-ToolkitManifestPath
    if (Test-Path -LiteralPath $path) {
        Invoke-Item -LiteralPath $path
    } else {
        Write-Host ""
        Write-Host "  No manifest yet. Run [A] Apply or any tracked tweak first." -ForegroundColor $script:UI_Soft
        Write-Host ""
        Read-Host "  Press Enter"
    }
}

function Invoke-ViewRecentLog {
    $logRoot = Get-ToolkitLogRoot
    if (-not (Test-Path -LiteralPath $logRoot)) {
        Write-Host ""
        Write-Host "  (no logs yet)" -ForegroundColor $script:UI_Soft
        Write-Host "  Log directory: $logRoot" -ForegroundColor $script:UI_Soft
        Write-Host ""
        Read-Host "  Press Enter"
        return
    }
    $logs = Get-ChildItem -LiteralPath $logRoot -File -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if (-not $logs -or $logs.Count -eq 0) {
        Write-Host ""
        Write-Host "  (no logs yet)" -ForegroundColor $script:UI_Soft
        Write-Host "  Log directory: $logRoot" -ForegroundColor $script:UI_Soft
        Write-Host ""
        Read-Host "  Press Enter"
        return
    }
    $latest = $logs[0]
    Write-Host ""
    Write-Host ("  Tail of: {0}" -f $latest.Name) -ForegroundColor $script:UI_Header
    Write-Host ("  Path:    {0}" -f $latest.FullName) -ForegroundColor $script:UI_Soft
    Write-Host ""
    Get-Content -LiteralPath $latest.FullName -Tail 40 -ErrorAction SilentlyContinue
    Write-Host ""
    Read-Host "  Press Enter to return"
}

function Invoke-RegenerateBaseline {
    Write-Host ""
    Write-Host "  Regenerate baseline?" -ForegroundColor $script:UI_Warning
    Write-Host "  This rewrites the manifest. Existing 'before' snapshots are lost." -ForegroundColor $script:UI_Soft
    $answer = (Read-Host "  Type YES to confirm").Trim()
    if ($answer -cne "YES") {
        Write-Host "  Cancelled." -ForegroundColor $script:UI_Soft
        Read-Host "  Press Enter"
        return
    }
    try {
        Initialize-ToolkitState -ForceNew | Out-Null
        Write-Host ""
        Write-Host "  Baseline manifest regenerated." -ForegroundColor $script:UI_Success
    } catch {
        Write-Host ""
        Write-Host "  Failed: $_" -ForegroundColor $script:UI_Error
    }
    Write-Host ""
    Read-Host "  Press Enter"
}

function Show-Help {
    Clear-Host
    Write-Host ""
    Write-Host "  Win11 Gaming Toolkit - Keybindings" -ForegroundColor $script:UI_Header
    Write-Host ""
    Write-Host "  Quick actions" -ForegroundColor $script:UI_Warning
    Write-Host "    [A]   Apply All       Run APPLY-EVERYTHING.ps1"
    Write-Host "    [V]   Verify status   Run 10 verify\verify-tweaks.ps1"
    Write-Host "    [R]   Revert All      Run REVERT-EVERYTHING.ps1"
    Write-Host ""
    Write-Host "  Categories" -ForegroundColor $script:UI_Warning
    foreach ($category in $script:LauncherCategories) {
        Write-Host ("    [{0,-2}]  {1,-26}{2}" -f $category.Key, $category.Title, $category.Folder) -ForegroundColor $script:UI_Label
    }
    Write-Host ""
    Write-Host "  Tools" -ForegroundColor $script:UI_Warning
    Write-Host "    [M]   View manifest         Open manifest.json in default editor"
    Write-Host "    [L]   View recent log       Tail newest *.log under ProgramData"
    Write-Host "    [B]   Regenerate baseline   Reset manifest after confirmation"
    Write-Host "    [?]   Help                  This screen"
    Write-Host "    [Q]   Quit                  Exit launcher"
    Write-Host ""
    Write-Host "  Status indicators" -ForegroundColor $script:UI_Warning
    Write-Host "    [OK] applied   Tracked tweak from this category was applied" -ForegroundColor $script:UI_Header
    Write-Host "    !  drift       Tracked tweak was applied but OS now reports the pre-toolkit value" -ForegroundColor $script:UI_Error
    Write-Host "    (blank)        Untracked or never applied" -ForegroundColor $script:UI_Soft
    Write-Host ""
    Read-Host "  Press Enter to return"
}

# ----- Input loop -----------------------------------------------------------

function Read-MenuChoice {
    param([string[]]$ValidKeys)

    $choice = (Read-Host "  PS>").Trim().ToUpperInvariant()
    if (-not $choice) { return $null }
    foreach ($key in $ValidKeys) {
        if ($choice -eq $key.ToUpperInvariant()) { return $key }
    }
    return $choice
}

function Start-Launcher {
    # Top-level interactive orchestrator. Doesn't directly mutate system
    # state — every state change happens via the dispatched scripts, each
    # of which has its own ShouldProcess gate. ShouldProcess at this level
    # would be a UX nuisance (prompts before showing the menu).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Top-level menu orchestrator; mutations happen in dispatched child scripts which each have their own ShouldProcess gates.'
    )]
    [CmdletBinding()]
    param()
    Initialize-LauncherEnvironment

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host ""
        Write-Host "  Win11 Gaming Toolkit must be run as Administrator." -ForegroundColor $script:UI_Error
        Write-Host "  Right-click PowerShell > Run as Administrator, then re-run launcher.ps1." -ForegroundColor $script:UI_Soft
        Write-Host ""
        exit 1
    }

    $validKeys = @("A", "V", "R", "M", "L", "B", "?", "Q")
    foreach ($category in $script:LauncherCategories) { $validKeys += $category.Key }

    while ($true) {
        $snapshot = Get-LauncherManifestSnapshot
        Show-MainMenu -Snapshot $snapshot

        $choice = Read-MenuChoice -ValidKeys $validKeys
        if (-not $choice) { continue }

        switch ($choice) {
            "Q" { return }
            "A" { Invoke-QuickAction -Key "A" }
            "V" { Invoke-QuickAction -Key "V" }
            "R" { Invoke-QuickAction -Key "R" }
            "M" { Invoke-ViewManifest }
            "L" { Invoke-ViewRecentLog }
            "B" { Invoke-RegenerateBaseline }
            "?" { Show-Help }
            default {
                $category = $script:LauncherCategories | Where-Object { $_.Key -eq $choice } | Select-Object -First 1
                if ($category) {
                    Show-CategoryMenu -Category $category
                } else {
                    Write-Host "  Unknown choice." -ForegroundColor $script:UI_Warning
                    Start-Sleep -Seconds 1
                }
            }
        }
    }
}

Start-Launcher
