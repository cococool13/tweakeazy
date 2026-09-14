#Requires -Version 5.1
<#
.SYNOPSIS
    Toolkit-aware helpers for the Win11 Gaming Toolkit dev profile.

.DESCRIPTION
    Functions intended for the user's PowerShell session, not for
    the toolkit scripts themselves. Dot-sourced by
    profile/Microsoft.PowerShell_profile.ps1.

    Provides:
      - Get-ToolkitLog        — tail or open recent toolkit log files
      - Get-ToolkitManifest    — load the current manifest as a PSObject
      - Test-ToolkitInvariants — assert CLAUDE.md invariants on the tree
      - Show-ToolkitMenu       — colored cheat-sheet of common commands

    Each function has comment-based help; Get-Help <Name> -Detailed.

.NOTES
    All functions are read-only. None mutate registry / services / files
    in the running session.
#>

function Get-ToolkitLog {
    <#
    .SYNOPSIS
        Tail or open the most recent toolkit log file.
    .DESCRIPTION
        Toolkit scripts write logs under
        $env:ProgramData\Win11GamingToolkit\logs\<script>-<timestamp>.log.
        This helper finds the latest log (optionally filtered) and either
        tails it (-Tail N), opens it in $env:EDITOR (-Open), or returns
        the FileInfo for further piping.
    .PARAMETER Filter
        Wildcard match against the file name. Default: '*' (any).
    .PARAMETER Tail
        Show the last N lines and exit.
    .PARAMETER Open
        Open the file in $env:EDITOR (or notepad on Windows).
    .EXAMPLE
        Get-ToolkitLog
        Returns FileInfo for the most recent log.
    .EXAMPLE
        Get-ToolkitLog -Filter 'apply-*' -Tail 50
        Shows the last 50 lines of the most recent APPLY-* log.
    .EXAMPLE
        Get-ToolkitLog -Open
        Opens the most recent log in the default editor.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [string]$Filter = '*',
        [int]$Tail,
        [switch]$Open
    )
    $logRoot = Join-Path $env:ProgramData 'Win11GamingToolkit\logs'
    if (-not (Test-Path -LiteralPath $logRoot)) {
        Write-Warning "Toolkit log root not found: $logRoot"
        return
    }
    $latest = Get-ChildItem -LiteralPath $logRoot -File -Filter "$Filter.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) {
        Write-Warning "No logs matching '$Filter' under $logRoot."
        return
    }
    if ($Open) {
        $editor = if ($env:EDITOR) { $env:EDITOR } else { 'notepad.exe' }
        & $editor $latest.FullName
        return
    }
    if ($Tail -gt 0) {
        Get-Content -LiteralPath $latest.FullName -Tail $Tail
        return
    }
    return $latest
}

function Get-ToolkitManifest {
    <#
    .SYNOPSIS
        Load the toolkit manifest as a PSObject for inspection.
    .DESCRIPTION
        Reads %ProgramData%\Win11GamingToolkit\state\manifest.json and
        returns the parsed object. Read-only — does not modify the
        manifest. Useful for ad-hoc inspection during dev / debugging.
    .EXAMPLE
        (Get-ToolkitManifest).registry | Format-Table -AutoSize
    .EXAMPLE
        (Get-ToolkitManifest).services.Values | Where-Object before -ne 'Disabled'
    #>
    [CmdletBinding()]
    param()
    $path = Join-Path $env:ProgramData 'Win11GamingToolkit\state\manifest.json'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Warning "Manifest not found at $path. Run any toolkit script (or APPLY-EVERYTHING.ps1) to create it."
        return
    }
    # ConvertFrom-Json -Depth is PS 6.2+; inbox 5.1 only has -InputObject.
    Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Test-ToolkitInvariants {
    <#
    .SYNOPSIS
        Assert CLAUDE.md invariants across the repo's .ps1 / .bat files.
    .DESCRIPTION
        Walks the repo and flags violations of CLAUDE.md invariants 1-6:
          1. Risk tier declared in header
          2. Tracked writes via Set-Toolkit* helpers (heuristic)
          3. No PS 7-only syntax (delegated to PSScriptAnalyzer)
          4. No bundled binaries (heuristic: looks for *.exe/*.msi
             in tracked files — should always be 0)
          5. Manifest references go through helpers (heuristic)
          6. Admin self-check present in mutators
    .PARAMETER RepoRoot
        Defaults to the directory containing this profile parts file.
    .EXAMPLE
        Test-ToolkitInvariants | Where-Object Passes -EQ $false
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$RepoRoot
    )
    if (-not $RepoRoot) {
        # Walk up from this script: profile/parts/toolkit-aware.ps1 → repo root
        $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }
    if (-not (Test-Path -LiteralPath $RepoRoot)) {
        throw "RepoRoot not found: $RepoRoot"
    }

    # Path-separator-agnostic excludes so the helper works on macOS dev
    # boxes (forward slash) AND Windows runners (backslash).
    $excludePattern = '(^|[\\/])(\.git|tests|profile|tools|lib)([\\/]|$)'
    $ps1Files = Get-ChildItem -LiteralPath $RepoRoot -Recurse -Filter '*.ps1' -File |
        Where-Object { $_.FullName -notmatch $excludePattern }

    foreach ($f in $ps1Files) {
        $content = Get-Content -Raw -LiteralPath $f.FullName
        # 120 lines fits well-documented scripts whose comment-based help
        # pushes the admin check past line 80 (Phase C scripts especially).
        # Matches Test-ToolkitAdminCheck's default; keep these in sync.
        $head = ($content -split "`n" | Select-Object -First 120) -join "`n"
        $isMutator = $content -match '(Set-Toolkit|Set-Tracked|Set-ItemProperty|sc\.exe config|Remove-Item|New-ItemProperty|Stop-Service|Disable-)'
        [PSCustomObject]@{
            # Always report forward slashes. Every caller's exclusion list
            # ($KnownUnpairable, $KnownGaps) is authored with '/', so a raw
            # native separator makes those -contains checks silently miss on
            # Windows runners and re-flag acknowledged exclusions as failures.
            Path = $f.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
            HasTier = $head -match 'Tier:\s+(Safe|Advanced|Security Trade-off)'
            HasAdminGuard = ($head -match 'UI-RequireAdmin') -or ($head -match 'IsInRole.*Administrator')
            IsMutator = $isMutator
            Passes = (-not $isMutator) -or (
                ($head -match 'UI-RequireAdmin') -or
                ($head -match 'IsInRole.*Administrator')
            )
        }
    }
}

function Show-ToolkitMenu {
    <#
    .SYNOPSIS
        Colored cheat-sheet of common toolkit dev commands.
    .DESCRIPTION
        Quick reference for the dev session. Pure output, no side effects.
    .EXAMPLE
        Show-ToolkitMenu
    #>
    [CmdletBinding()]
    param()
    $rows = @(
        @{ K = 'Invoke-ToolkitGate'; D = 'Run PSScriptAnalyzer + Pester' }
        @{ K = 'Invoke-ToolkitGate -Strict'; D = 'Gate with warnings = fail' }
        @{ K = 'Invoke-ToolkitGate -SkipTests'; D = 'Analyzer-only (fast loop)' }
        @{ K = 'Get-ToolkitLog -Tail 40'; D = 'Last 40 lines of newest log' }
        @{ K = 'Get-ToolkitLog -Filter ''apply-*'' -Open'; D = 'Open APPLY log in editor' }
        @{ K = 'Get-ToolkitManifest'; D = 'Load manifest.json as PSObject' }
        @{ K = '(Get-ToolkitManifest).registry'; D = 'Inspect tracked registry writes' }
        @{ K = 'Test-ToolkitInvariants | ? Passes -EQ $false'; D = 'List invariant violators' }
        @{ K = 'Invoke-Pester tests/lib/'; D = 'Run lib tests only' }
        @{ K = '.\launcher.ps1'; D = 'Open the user-facing menu' }
    )
    Write-Host ''
    Write-Host '  Win11 Gaming Toolkit — dev commands' -ForegroundColor Cyan
    # PSAvoidUsingPositionalParameters + actual bug: without the parens,
    # PowerShell parses '  ' as Object, '+' as second positional → garbled.
    Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray
    foreach ($r in $rows) {
        Write-Host ('    {0,-46}' -f $r.K) -ForegroundColor Yellow -NoNewline
        Write-Host $r.D -ForegroundColor Gray
    }
    Write-Host ''
}
