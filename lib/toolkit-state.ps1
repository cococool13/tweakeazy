# ============================================================
# Shared State / Preflight Helpers
# Windows 11 Gaming Optimization Guide
# ============================================================

$script:ToolkitVersionFile = Join-Path $PSScriptRoot "..\VERSION"
$script:ToolkitVersion = if (Test-Path -LiteralPath $script:ToolkitVersionFile) {
    (Get-Content -LiteralPath $script:ToolkitVersionFile -Raw).Trim()
} else {
    "0.0.0"
}
# Cross-platform state root. $env:ProgramData is null on macOS / Linux,
# so dev / test runs there land under ~/.local/share. Production
# (Windows) keeps the historical %ProgramData% location.
$script:ToolkitDataHome = if ($env:ProgramData) {
    $env:ProgramData
} elseif ($env:XDG_DATA_HOME) {
    $env:XDG_DATA_HOME
} else {
    Join-Path $HOME '.local/share'
}
$script:ToolkitStateRoot = Join-Path $script:ToolkitDataHome 'Win11GamingToolkit/state'
$script:ToolkitStateFile = Join-Path $script:ToolkitStateRoot 'manifest.json'
$script:ToolkitLogRoot = Join-Path $script:ToolkitDataHome 'Win11GamingToolkit/logs'
$script:ToolkitState = $null

# Per-process log file path. Set lazily by the first Write-ToolkitLog call
# so scripts that never log don't create empty files. Format:
#   <log-root>/<script-stem>-<yyyyMMdd-HHmmss>-<pid>.log
# Each line is JSON: { "ts":"...", "level":"info|warn|error", "msg":"...", "data":{...} }
$script:ToolkitLogFile = $null

function Get-ToolkitManifestPath {
    return $script:ToolkitStateFile
}

function Get-ToolkitLogRoot {
    return $script:ToolkitLogRoot
}

function Get-ToolkitLogFile {
    <#
    .SYNOPSIS
        Return (and lazily create) the per-process log file path.
    .DESCRIPTION
        Computes a stable per-script, per-process log path on first call
        and reuses it for the lifetime of the process. Layout:
            <ProgramData>\Win11GamingToolkit\logs\<script-stem>-<ts>-<pid>.log
        - $script:MyInvocation.MyCommand isn't reliable from a dot-sourced
          helper; we read the calling script's $PSCommandPath via
          (Get-PSCallStack)[1] which is the immediate caller.
        - When called outside any script (e.g. interactive shell), we
          fall back to "interactive".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($script:ToolkitLogFile) {
        return $script:ToolkitLogFile
    }
    if (-not (Test-Path -LiteralPath $script:ToolkitLogRoot)) {
        New-Item -ItemType Directory -Path $script:ToolkitLogRoot -Force -ErrorAction SilentlyContinue | Out-Null
    }
    $stem = 'interactive'
    try {
        $caller = (Get-PSCallStack | Select-Object -Skip 1 -First 1).ScriptName
        if ($caller) {
            $stem = [System.IO.Path]::GetFileNameWithoutExtension($caller)
        }
    } catch {
        $stem = 'unknown'
    }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $script:ToolkitLogFile = Join-Path $script:ToolkitLogRoot ("$stem-$stamp-$PID.log")
    return $script:ToolkitLogFile
}

$script:ToolkitScriptStartLogged = $false

function Write-ToolkitScriptStart {
    <#
    .SYNOPSIS
        Emit a 'script-start' log line for the calling script (once per process).
    .DESCRIPTION
        Auto-discovers the caller's script name + invocation arguments
        from Get-PSCallStack. Single-line wire-up for any mutating
        script that wants the standard "did this run today" audit
        trail without rewriting per-script log calls.

        Idempotent: only the first call per process actually writes —
        subsequent calls (e.g. when Initialize-ToolkitState re-runs)
        are no-ops, so re-init doesn't double-log.

        Usage (after admin check, before any work):
            Write-ToolkitScriptStart

        Auto-called by Initialize-ToolkitState (with SkipFrames=2) so
        most scripts get this for free without an explicit call.
        Pass -SkipFrames > 1 when wrapped through another helper.

    .PARAMETER SkipFrames
        How many call-stack frames to skip when resolving "the caller's
        script." 1 = direct caller (default). 2 = caller's caller, used
        when invoked through a helper like Initialize-ToolkitState.

    .NOTES
        Best-effort: silent if no caller can be resolved (e.g. dot-
        sourced from interactive shell).
    #>
    [CmdletBinding()]
    param(
        [int]$SkipFrames = 1
    )
    if ($script:ToolkitScriptStartLogged) { return }
    try {
        # Frame 0 = Write-ToolkitScriptStart itself; Skip $SkipFrames more.
        $caller = (Get-PSCallStack | Select-Object -Skip $SkipFrames -First 1)
        if (-not $caller -or -not $caller.ScriptName) { return }
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($caller.ScriptName)
        $argsMap = @{}
        if ($caller.InvocationInfo -and $caller.InvocationInfo.BoundParameters) {
            foreach ($k in $caller.InvocationInfo.BoundParameters.Keys) {
                $v = $caller.InvocationInfo.BoundParameters[$k]
                # SwitchParameter -> bool for cleaner JSON
                if ($v -is [System.Management.Automation.SwitchParameter]) {
                    $argsMap[$k] = [bool]$v
                } else {
                    $argsMap[$k] = $v
                }
            }
        }
        Write-ToolkitLog 'script-start' -Data @{
            script = $stem
            path = $caller.ScriptName
            args = $argsMap
        }
        $script:ToolkitScriptStartLogged = $true
    } catch {
        $null = $_
    }
}

function Write-ToolkitLog {
    <#
    .SYNOPSIS
        Append a structured log line (JSON) to the per-process toolkit log.
    .DESCRIPTION
        CLAUDE.md quality bar: "every action + every skip to
        <ProgramData>\<toolkit>\logs\<script>-<timestamp>.log, JSON-lines".
        Helpers in this file (Set-ToolkitRegistryValue,
        Set-ToolkitServiceStartMode, etc.) call this so callers don't
        have to remember.
    .PARAMETER Message
        Human-readable summary. Logged as the 'msg' field.
    .PARAMETER Level
        info | warn | error. Default 'info'.
    .PARAMETER Data
        Optional hashtable of structured fields. Serialized as the
        'data' object on the JSON line. Use for path/name/value triples.
    .EXAMPLE
        Write-ToolkitLog 'reg-set' -Data @{ path='HKLM:\...'; name='Foo'; value=1 }
    .NOTES
        Best-effort: writes are wrapped in try/catch so logging failures
        never break the calling script. Disk full / permission denied /
        log-root creation race all degrade silently.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        [ValidateSet('info', 'warn', 'error')][string]$Level = 'info',
        [hashtable]$Data
    )
    try {
        $path = Get-ToolkitLogFile
        $record = [ordered]@{
            ts = (Get-Date).ToString('o')
            level = $Level
            msg = $Message
        }
        if ($Data -and $Data.Count -gt 0) {
            $record['data'] = $Data
        }
        $line = $record | ConvertTo-Json -Compress -Depth 5
        Add-Content -LiteralPath $path -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
    } catch {
        # Best-effort logging. Caller continues regardless of disk full,
        # permission denied, log-root creation race, etc. Logging that
        # itself throws would defeat the purpose. We assign the error
        # record to $null so the PSAvoidUsingEmptyCatchBlock rule sees
        # an intentional statement.
        $null = $_
    }
}

# ============================================================
# Sidecar JSON helpers
# ============================================================
# Some tweaks (write-cache-flush, RSS tuning, interrupt moderation)
# capture pre-toolkit state in a per-tweak sidecar JSON beside the
# manifest, because the values live in vendor-specific NIC properties
# or per-PnP-device registry keys that don't fit the manifest's
# uniform Id-keyed shape. Sidecars are an escape hatch, not an
# alternative — Set-ToolkitRegistryValue stays the canonical path for
# anything that fits.
#
# Naming: each tweak owns a stem (e.g. 'writecache', 'rss', 'rss-im')
# and the helpers append '-before.json'. Files live at:
#   %ProgramData%\Win11GamingToolkit\state\<stem>-before.json
# (or the cross-platform fallback root on macOS dev boxes).

function Get-ToolkitSidecarPath {
    <#
    .SYNOPSIS
        Return the canonical sidecar file path for a given stem.
    .DESCRIPTION
        Pure path resolution; does not touch disk. Use for inspection
        or for cases where Save/Read isn't a good fit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    Join-Path $script:ToolkitStateRoot ("$Name-before.json")
}

function Save-ToolkitSidecar {
    <#
    .SYNOPSIS
        Idempotently capture pre-toolkit state to a sidecar JSON.
    .DESCRIPTION
        Default behavior is "capture once": if the sidecar already
        exists, no write happens — preserving the original pre-toolkit
        baseline across re-runs of the apply script. Pass -Force to
        overwrite (rare; useful for tests).

        Honors -WhatIf via ShouldProcess. Logs 'sidecar-captured' on
        success and 'sidecar-capture-failed' (Level=error) on I/O
        failure. Returns the sidecar path on success, $null on
        capture-skip (already exists) or write failure.
    .PARAMETER Name
        Sidecar stem (e.g. 'writecache', 'rss', 'rss-im').
    .PARAMETER InputObject
        Object to serialize. Typically an array of PSCustomObjects;
        the JSON conversion handles any serializable shape.
    .PARAMETER Force
        Overwrite an existing sidecar. Default: preserve.
    .PARAMETER Depth
        ConvertTo-Json -Depth. Default: 3.
    .EXAMPLE
        $rows = Get-NetAdapterRss | Select Name, Enabled, NumberOfReceiveQueues
        Save-ToolkitSidecar -Name 'rss' -InputObject $rows
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$InputObject,
        [switch]$Force,
        [int]$Depth = 3
    )
    if (-not (Test-Path -LiteralPath $script:ToolkitStateRoot)) {
        New-Item -ItemType Directory -Path $script:ToolkitStateRoot -Force -ErrorAction SilentlyContinue | Out-Null
    }
    $path = Get-ToolkitSidecarPath -Name $Name
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
        Write-ToolkitLog 'sidecar-preserve' -Data @{ name = $Name; path = $path; reason = 'already exists' }
        return $null
    }
    if (-not $PSCmdlet.ShouldProcess($path, "Capture sidecar '$Name'")) {
        Write-ToolkitLog 'sidecar-capture-skipped-whatif' -Level warn -Data @{ name = $Name }
        return $null
    }
    try {
        $InputObject | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $path -Encoding utf8 -ErrorAction Stop
        Write-ToolkitLog 'sidecar-captured' -Data @{ name = $Name; path = $path }
        return $path
    } catch {
        Write-ToolkitLog 'sidecar-capture-failed' -Level error -Data @{
            name = $Name; path = $path; err = $_.Exception.Message
        }
        return $null
    }
}

function Read-ToolkitSidecar {
    <#
    .SYNOPSIS
        Read a sidecar JSON and return its contents as an array.
    .DESCRIPTION
        Returns $null when the sidecar doesn't exist OR can't be
        parsed (logs 'sidecar-read-failed' in the parse-error case).
        Always returns an array on success — wraps scalars so callers
        don't have to handle the ConvertFrom-Json single-object quirk
        (single-element JSON arrays decode to scalars in PS 5.1).
    .EXAMPLE
        $snapshot = Read-ToolkitSidecar -Name 'rss'
        if (-not $snapshot) { exit 1 }
        foreach ($entry in $snapshot) { ... }
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string]$Name)
    $path = Get-ToolkitSidecarPath -Name $Name
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    try {
        $obj = Get-Content -Raw -LiteralPath $path -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $obj) { return @() }
        if ($obj -isnot [System.Array]) { return @($obj) }
        return $obj
    } catch {
        Write-ToolkitLog 'sidecar-read-failed' -Level error -Data @{
            name = $Name; path = $path; err = $_.Exception.Message
        }
        return $null
    }
}

function Remove-ToolkitSidecar {
    <#
    .SYNOPSIS
        Delete a sidecar JSON. Idempotent — silent if absent.
    .DESCRIPTION
        Called by restore-side scripts after a successful revert so the
        next apply can capture a fresh baseline. Honors -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([Parameter(Mandatory)][string]$Name)
    $path = Get-ToolkitSidecarPath -Name $Name
    if (-not (Test-Path -LiteralPath $path)) { return }
    if (-not $PSCmdlet.ShouldProcess($path, "Remove sidecar '$Name'")) { return }
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    Write-ToolkitLog 'sidecar-removed' -Data @{ name = $Name; path = $path }
}

function Test-ToolkitMapHasKey {
    param($Map, [string]$Key)
    if ($Map -is [hashtable]) {
        return $Map.ContainsKey($Key)
    }
    return $null -ne $Map.PSObject.Properties[$Key]
}

function Get-ToolkitMapValue {
    param($Map, [string]$Key)
    if ($Map -is [hashtable]) {
        return $Map[$Key]
    }
    return $Map.PSObject.Properties[$Key].Value
}

function Set-ToolkitMapValue {
    # In-memory hashtable / PSObject mutation only — does NOT touch
    # registry, services, files, or any system state. PSUseShouldProcess
    # is a heuristic on the "Set-" verb and gives a false positive here.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'In-memory state mutation only; no system side effect.'
    )]
    [CmdletBinding()]
    param($Map, [string]$Key, $Value)
    if ($Map -is [hashtable]) {
        $Map[$Key] = $Value
        return
    }
    if ($Map.PSObject.Properties[$Key]) {
        $Map.$Key = $Value
    } else {
        $Map | Add-Member -NotePropertyName $Key -NotePropertyValue $Value
    }
}

function Test-ToolkitCommand {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ToolkitMachineProfile {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $enclosure = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue
    $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    $gpuDevices = @(Get-PnpDevice -Class Display -ErrorAction SilentlyContinue)
    $activeAdapters = @()
    if (Test-ToolkitCommand "Get-NetAdapter") {
        $activeAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })
    }

    $printerCount = 0
    if (Test-ToolkitCommand "Get-Printer") {
        $printerCount = @(Get-Printer -ErrorAction SilentlyContinue).Count
    }

    $chassisTypes = @()
    if ($enclosure) {
        $chassisTypes = @($enclosure.ChassisTypes)
    }
    $laptopChassisTypes = @(8, 9, 10, 14, 30, 31, 32)
    $handheldChassisTypes = @(11, 30, 31, 32)
    $isLaptop = $false
    $isHandheld = $false
    foreach ($chassisType in $chassisTypes) {
        if ($laptopChassisTypes -contains $chassisType) {
            $isLaptop = $true
        }
        if ($handheldChassisTypes -contains $chassisType) {
            $isHandheld = $true
        }
    }

    $powerState = "Desktop / AC"
    if ($battery) {
        $powerState = "Battery-capable"
        if ($battery.BatteryStatus -in @(1, 4, 5, 11)) {
            $powerState = "On battery"
        } elseif ($battery.BatteryStatus -in @(2, 6, 7, 8, 9)) {
            $powerState = "Charging / AC"
        }
    }

    $dnsSnapshot = @()
    if (Test-ToolkitCommand "Get-DnsClientServerAddress") {
        $dnsSnapshot = @(Get-DnsClientServerAddress -ErrorAction SilentlyContinue | ForEach-Object {
                [PSCustomObject]@{
                    InterfaceAlias = $_.InterfaceAlias
                    InterfaceIndex = $_.InterfaceIndex
                    AddressFamily = $_.AddressFamily
                    ServerAddresses = @($_.ServerAddresses)
                }
            })
    }

    return [PSCustomObject]@{
        generatedAt = (Get-Date).ToString("o")
        systemName = $env:COMPUTERNAME
        manufacturer = $computerSystem.Manufacturer
        model = $computerSystem.Model
        isLaptop = $isLaptop
        isHandheld = $isHandheld
        powerState = $powerState
        gpuCount = $gpuDevices.Count
        isHybridGraphics = $gpuDevices.Count -gt 1
        activeAdapterCount = $activeAdapters.Count
        activeAdapters = @($activeAdapters | ForEach-Object { $_.Name })
        printerCount = $printerCount
        defenderAvailable = Test-ToolkitCommand "Get-MpPreference"
        partOfDomain = [bool]$computerSystem.PartOfDomain
        windowsVersion = $operatingSystem.Version
        windowsCaption = $operatingSystem.Caption
        dnsSnapshot = $dnsSnapshot
    }
}

function Save-ToolkitState {
    if (-not (Test-Path $script:ToolkitStateRoot)) {
        New-Item -ItemType Directory -Path $script:ToolkitStateRoot -Force | Out-Null
    }
    $script:ToolkitState.lastUpdated = (Get-Date).ToString("o")
    $json = $script:ToolkitState | ConvertTo-Json -Depth 12
    Set-Content -Path $script:ToolkitStateFile -Value $json -Force
}

function Get-ToolkitState {
    if ($script:ToolkitState) {
        return $script:ToolkitState
    }
    if (Test-Path $script:ToolkitStateFile) {
        $script:ToolkitState = Get-Content $script:ToolkitStateFile -Raw | ConvertFrom-Json -Depth 12
        return $script:ToolkitState
    }
    return $null
}

function Initialize-ToolkitState {
    param([switch]$ForceNew)

    # Auto-log script start for any caller. SkipFrames=2: frame 0 is
    # Write-ToolkitScriptStart, frame 1 is Initialize-ToolkitState
    # (this fn), frame 2 is the actual mutating script. Idempotent;
    # safe even if the caller also calls Write-ToolkitScriptStart
    # explicitly (the second call is a no-op).
    Write-ToolkitScriptStart -SkipFrames 2

    # Preserve captured before-state once a manifest exists. Older callers used
    # -ForceNew during apply, which could destroy the only reliable revert data.
    if (Test-Path $script:ToolkitStateFile) {
        $script:ToolkitState = Get-Content $script:ToolkitStateFile -Raw | ConvertFrom-Json -Depth 12
        return $script:ToolkitState
    }

    # PSAvoidAssignmentToAutomaticVariable: $profile is PowerShell's
    # built-in profile-path variable; using $machineProfile so reads of
    # $profile elsewhere in scope return the user's actual profile path.
    $machineProfile = Get-ToolkitMachineProfile
    $script:ToolkitState = [ordered]@{
        version = $script:ToolkitVersion
        createdAt = (Get-Date).ToString("o")
        lastUpdated = (Get-Date).ToString("o")
        context = $machineProfile
        notes = @()
        registry = @{}
        services = @{}
        dns = [ordered]@{
            captured = $false
            interfaces = @{}
        }
        defender = [ordered]@{
            captured = $false
            before = @()
            added = @()
        }
        packages = [ordered]@{
            removed = @()
            provisionedRemoved = @()
        }
        steps = @{}
    }
    Save-ToolkitState
    return $script:ToolkitState
}

function Add-ToolkitNote {
    param([string]$Message)
    $state = Get-ToolkitState
    $state.notes += $Message
    Save-ToolkitState
}

function Add-ToolkitStepResult {
    param(
        [string]$Key,
        [string]$Tier,
        [string]$Status,
        [string]$Reason = ""
    )
    $state = Get-ToolkitState
    Set-ToolkitMapValue -Map $state.steps -Key $Key -Value ([ordered]@{
            tier = $Tier
            status = $Status
            reason = $Reason
            updatedAt = (Get-Date).ToString("o")
        })
    Save-ToolkitState
}

function Get-ToolkitRegistryState {
    param(
        [string]$Path,
        [string]$Name
    )

    $valueName = if ($null -eq $Name) { "" } else { $Name }
    $pathExists = Test-Path $Path
    if (-not $pathExists) {
        return [ordered]@{
            pathExists = $false
            valueExists = $false
            kind = $null
            value = $null
        }
    }

    $item = Get-Item -Path $Path -ErrorAction Stop
    $valueNames = @($item.GetValueNames())
    # PSPossibleIncorrectComparisonWithNull — $null on left side so the
    # collection-vs-scalar coercion behaves predictably.
    $defaultExists = $null -ne $item.GetValue("", $null)
    $valueExists = if ($valueName -eq "") { $defaultExists } else { $valueNames -contains $valueName }
    if (-not $valueExists) {
        return [ordered]@{
            pathExists = $true
            valueExists = $false
            kind = $null
            value = $null
        }
    }

    return [ordered]@{
        pathExists = $true
        valueExists = $true
        kind = $item.GetValueKind($valueName).ToString()
        value = $item.GetValue($valueName, $null, "DoNotExpandEnvironmentNames")
    }
}

function Set-ToolkitRegistryValue {
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

    $state = Get-ToolkitState
    if (-not (Test-ToolkitMapHasKey -Map $state.registry -Key $Id)) {
        Set-ToolkitMapValue -Map $state.registry -Key $Id -Value ([ordered]@{
                path = $Path
                name = $Name
                tier = $Tier
                step = $Step
                before = Get-ToolkitRegistryState -Path $Path -Name $Name
            })
        Save-ToolkitState
    }

    if (-not (Test-Path $Path)) {
        # ShouldProcess gate on parent-key creation — propagates -WhatIf
        # from the calling script via the standard PSCmdlet preference chain.
        if ($PSCmdlet.ShouldProcess($Path, 'New-Item (registry key)')) {
            New-Item -Path $Path -Force | Out-Null
        } else {
            return
        }
    }
    $propertyType = switch ($Type) {
        "DWord" { "DWord" }
        "QWord" { "QWord" }
        "Binary" { "Binary" }
        "MultiString" { "MultiString" }
        "ExpandString" { "ExpandString" }
        default { "String" }
    }

    # CURSOR-AUDIT #19: skip the write when the value already matches.
    # Reduces unnecessary registry churn on re-apply and keeps audit logs
    # clean. before-state capture above already ran, so manifest is consistent.
    $current = $null
    try {
        if ($Name -eq "") {
            $current = (Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue).'(default)'
        } else {
            $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
        }
    } catch {
        $current = $null
    }
    # Type-aware compare. For DWord/QWord the registry returns an integer
    # already; for strings, do a string compare; binaries skip the fast-path
    # (compare byte arrays correctly is fragile) and always write.
    $skipWrite = $false
    if ($null -ne $current -and $propertyType -notin @("Binary", "MultiString")) {
        if ($propertyType -in @("DWord", "QWord")) {
            if ([int64]$current -eq [int64]$Value) { $skipWrite = $true }
        } else {
            if ([string]$current -eq [string]$Value) { $skipWrite = $true }
        }
    }
    if ($skipWrite) {
        Write-ToolkitLog 'reg-skip-idempotent' -Data @{
            id = $Id; path = $Path; name = $Name; value = $Value; reason = 'current value matches target'
        }
        return
    }

    $target = if ($Name -eq "") { "$Path\(default)" } else { "$Path\$Name" }
    if (-not $PSCmdlet.ShouldProcess($target, "Set value '$Value' (type $propertyType)")) {
        Write-ToolkitLog 'reg-skip-whatif' -Level warn -Data @{
            id = $Id; path = $Path; name = $Name; value = $Value
        }
        return
    }

    if ($Name -eq "") {
        $item = Get-Item -Path $Path -ErrorAction Stop
        $item.SetValue("", $Value)
    } else {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $propertyType -Force | Out-Null
    }
    Write-ToolkitLog 'reg-set' -Data @{
        id = $Id; path = $Path; name = $Name; value = $Value; type = $propertyType; tier = $Tier; step = $Step
    }
}

function Restore-ToolkitRegistryValue {
    param([string]$Id)

    $state = Get-ToolkitState
    if (-not (Test-ToolkitMapHasKey -Map $state.registry -Key $Id)) {
        return $false
    }
    $entry = Get-ToolkitMapValue -Map $state.registry -Key $Id
    $before = $entry.before
    $path = $entry.path
    $name = $entry.name

    if (-not $before.pathExists) {
        # Parenthesize Test-Path so $path doesn't get bound as -and parameter.
        # Without parens, PowerShell parses Test-Path's args greedily and the
        # Remove-ItemProperty branch is skipped (or throws), leaving the
        # toolkit-added value behind when the parent key didn't exist before.
        if ((Test-Path $path) -and $name -ne "") {
            Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
        }
        return $true
    }

    if (-not $before.valueExists) {
        if ($name -ne "") {
            Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
        }
        return $true
    }

    Set-ToolkitRegistryValue -Id $Id -Path $path -Name $name -Value $before.value -Type $before.kind -Tier $entry.tier -Step $entry.step
    return $true
}

function Set-ToolkitServiceStartMode {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]$Name,
        [string]$Mode,
        [string]$Tier,
        [string]$Step
    )

    $state = Get-ToolkitState
    if (-not (Test-ToolkitMapHasKey -Map $state.services -Key $Name)) {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
        Set-ToolkitMapValue -Map $state.services -Key $Name -Value ([ordered]@{
                name = $Name
                tier = $Tier
                step = $Step
                installed = $null -ne $service
                before = if ($service) { $service.StartMode } else { $null }
            })
        Save-ToolkitState
    }

    if (-not $PSCmdlet.ShouldProcess("service:$Name", "Set start mode to '$Mode'")) {
        Write-ToolkitLog 'svc-skip-whatif' -Level warn -Data @{ name = $Name; mode = $Mode }
        return
    }

    $output = sc.exe config $Name start= $Mode 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ToolkitLog 'svc-set-failed' -Level error -Data @{
            name = $Name; mode = $Mode; exit = $LASTEXITCODE; output = "$output"
        }
        throw "sc.exe config failed: $output"
    }
    Write-ToolkitLog 'svc-set' -Data @{ name = $Name; mode = $Mode; tier = $Tier; step = $Step }
}

function Convert-ToolkitServiceModeToScMode {
    param([string]$Mode)

    switch -Regex ($Mode) {
        "^auto$|^automatic$" { return "auto" }
        "^manual$|^demand$" { return "demand" }
        "^disabled$" { return "disabled" }
        "^delayed auto start$" { return "delayed-auto" }
        default { throw "Unsupported service start mode: $Mode" }
    }
}

function Restore-ToolkitServiceStartMode {
    param([string]$Name)

    $state = Get-ToolkitState
    if (-not (Test-ToolkitMapHasKey -Map $state.services -Key $Name)) {
        return $false
    }
    $entry = Get-ToolkitMapValue -Map $state.services -Key $Name
    if (-not $entry.installed -or -not $entry.before) {
        return $true
    }
    $restoredMode = Convert-ToolkitServiceModeToScMode -Mode ([string]$entry.before)
    $output = sc.exe config $Name start= $restoredMode 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "sc.exe config failed: $output"
    }
    return $true
}

function Normalize-ToolkitDnsAddressFamily {
    param($AddressFamily)

    switch -Regex ([string]$AddressFamily) {
        "^IPv4$|^2$|^InterNetwork$" { return "IPv4" }
        "^IPv6$|^23$|^InterNetworkV6$" { return "IPv6" }
        default { return $null }
    }
}

function Get-ToolkitDnsAddressFamily {
    param([string]$Address)

    $parsedAddress = [System.Net.IPAddress]::None
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsedAddress)) {
        return $null
    }

    return Normalize-ToolkitDnsAddressFamily -AddressFamily $parsedAddress.AddressFamily
}

function Group-ToolkitDnsServersByFamily {
    param([string[]]$ServerAddresses)

    $groups = [ordered]@{
        IPv4 = @()
        IPv6 = @()
    }

    foreach ($server in @($ServerAddresses | Where-Object { $_ })) {
        $family = Get-ToolkitDnsAddressFamily -Address $server
        if (-not $family) {
            throw "Invalid DNS server address: $server"
        }
        $groups[$family] = @($groups[$family]) + @($server)
    }

    if (@($groups["IPv4"]).Count -eq 0 -and @($groups["IPv6"]).Count -eq 0) {
        throw "No DNS server addresses provided"
    }

    return $groups
}

function Capture-ToolkitDnsState {
    $state = Get-ToolkitState
    if ($state.dns.captured -or -not (Test-ToolkitCommand "Get-DnsClientServerAddress")) {
        return
    }

    $snapshot = @(Get-DnsClientServerAddress -ErrorAction SilentlyContinue)
    foreach ($item in $snapshot) {
        $addressFamily = Normalize-ToolkitDnsAddressFamily -AddressFamily $item.AddressFamily
        if (-not $addressFamily) {
            continue
        }
        $snapshotKey = "{0}:{1}" -f $item.InterfaceIndex, $addressFamily
        Set-ToolkitMapValue -Map $state.dns.interfaces -Key $snapshotKey -Value ([ordered]@{
                interfaceAlias = $item.InterfaceAlias
                addressFamily = $addressFamily
                serverAddresses = @($item.ServerAddresses)
            })
    }
    $state.dns.captured = $true
    Save-ToolkitState
}

function Set-ToolkitDnsServers {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string[]]$ServerAddresses,
        [string]$Tier,
        [string]$Step
    )

    foreach ($commandName in @("Get-NetAdapter", "Get-DnsClientServerAddress", "Set-DnsClientServerAddress")) {
        if (-not (Test-ToolkitCommand $commandName)) {
            throw "$commandName cmdlet unavailable"
        }
    }

    $serverGroups = Group-ToolkitDnsServersByFamily -ServerAddresses $ServerAddresses
    Capture-ToolkitDnsState
    $activeAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })
    foreach ($adapter in $activeAdapters) {
        try {
            $adapterFailures = @()
            foreach ($family in @("IPv4", "IPv6")) {
                $familyServers = @($serverGroups[$family])
                if ($familyServers.Count -eq 0) {
                    continue
                }

                $target = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily $family -ErrorAction Stop
                if (-not $PSCmdlet.ShouldProcess("$($adapter.Name)/$family", "Set DNS servers to $($familyServers -join ',')")) {
                    continue
                }
                Set-DnsClientServerAddress -InputObject $target -ServerAddresses $familyServers -ErrorAction Stop

                $current = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily $family -ErrorAction Stop
                $currentServers = @($current.ServerAddresses)
                $missingServers = @($familyServers | Where-Object { $currentServers -notcontains $_ })
                if ($missingServers.Count -gt 0) {
                    $adapterFailures += "$family missing $($missingServers -join ', ')"
                }
            }

            if ($adapterFailures.Count -eq 0) {
                Add-ToolkitStepResult -Key "dns:$($adapter.ifIndex)" -Tier $Tier -Status "applied" -Reason $Step
            } else {
                Add-ToolkitStepResult -Key "dns:$($adapter.ifIndex)" -Tier $Tier -Status "skipped" -Reason "DNS verification failed on adapter $($adapter.Name): $($adapterFailures -join '; ')"
            }
        } catch {
            Add-ToolkitStepResult -Key "dns:$($adapter.ifIndex)" -Tier $Tier -Status "skipped" -Reason "DNS apply failed on adapter $($adapter.Name): $($_.Exception.Message)"
        }
    }
}

function Restore-ToolkitDnsServers {
    $state = Get-ToolkitState
    if (-not $state.dns.captured) {
        return $false
    }

    $properties = if ($state.dns.interfaces -is [hashtable]) {
        $state.dns.interfaces.GetEnumerator() | ForEach-Object { [PSCustomObject]@{ Name = $_.Key; Value = $_.Value } }
    } else {
        $state.dns.interfaces.PSObject.Properties
    }
    foreach ($property in $properties) {
        $nameParts = ([string]$property.Name) -split ":", 2
        $interfaceIndex = [int]$nameParts[0]
        $entry = $property.Value
        $addressFamily = if ($nameParts.Count -gt 1) {
            Normalize-ToolkitDnsAddressFamily -AddressFamily $nameParts[1]
        } else {
            Normalize-ToolkitDnsAddressFamily -AddressFamily $entry.addressFamily
        }
        $addresses = @($entry.serverAddresses | Where-Object { $_ })

        if ($addressFamily) {
            $target = Get-DnsClientServerAddress -InterfaceIndex $interfaceIndex -AddressFamily $addressFamily -ErrorAction SilentlyContinue
            if ($target) {
                if ($addresses.Count -gt 0) {
                    Set-DnsClientServerAddress -InputObject $target -ServerAddresses $addresses -ErrorAction SilentlyContinue
                } else {
                    Set-DnsClientServerAddress -InputObject $target -ResetServerAddresses -ErrorAction SilentlyContinue
                }
            }
        } elseif ($addresses.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ServerAddresses $addresses -ErrorAction SilentlyContinue
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        }
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    return $true
}

function Capture-ToolkitDefenderState {
    $state = Get-ToolkitState
    if ($state.defender.captured -or -not (Test-ToolkitCommand "Get-MpPreference")) {
        return
    }
    $paths = @((Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath)
    $state.defender.before = @($paths | Where-Object { $_ })
    $state.defender.captured = $true
    Save-ToolkitState
}

function Add-ToolkitDefenderExclusion {
    param(
        [string]$Path,
        [string]$Tier,
        [string]$Step
    )

    if (-not (Test-ToolkitCommand "Add-MpPreference")) {
        throw "Windows Defender cmdlets unavailable"
    }
    Capture-ToolkitDefenderState
    $current = @((Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath)
    if ($current -contains $Path) {
        Add-ToolkitStepResult -Key "defender:$Path" -Tier $Tier -Status "preexisting" -Reason $Step
        return
    }
    Add-MpPreference -ExclusionPath $Path -ErrorAction Stop
    $state = Get-ToolkitState
    if ($state.defender.added -notcontains $Path) {
        $state.defender.added += $Path
        Save-ToolkitState
    }
    Add-ToolkitStepResult -Key "defender:$Path" -Tier $Tier -Status "applied" -Reason $Step
}

function Restore-ToolkitDefenderExclusions {
    $state = Get-ToolkitState
    if (-not (Test-ToolkitCommand "Remove-MpPreference")) {
        return $false
    }
    foreach ($path in @($state.defender.added)) {
        Remove-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
    }
    return $true
}

function Record-ToolkitPackageRemoval {
    param(
        [string]$PackageName,
        [switch]$Provisioned
    )

    $state = Get-ToolkitState
    if ($Provisioned) {
        if ($state.packages.provisionedRemoved -notcontains $PackageName) {
            $state.packages.provisionedRemoved += $PackageName
        }
    } else {
        if ($state.packages.removed -notcontains $PackageName) {
            $state.packages.removed += $PackageName
        }
    }
    Save-ToolkitState
}

function Get-ToolkitRecordedStatus {
    param([string]$Key)
    $state = Get-ToolkitState
    if ($state -and (Test-ToolkitMapHasKey -Map $state.steps -Key $Key)) {
        return (Get-ToolkitMapValue -Map $state.steps -Key $Key).status
    }
    return $null
}
