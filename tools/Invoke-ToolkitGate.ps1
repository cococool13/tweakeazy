#Requires -Version 5.1
<#
.SYNOPSIS
    Run the Win11 Gaming Toolkit quality gate: PSScriptAnalyzer + Pester.

.DESCRIPTION
    Single entrypoint for the CI/CD quality gate. Equivalent to what
    .github/workflows/ci.yml runs. Exits non-zero on any analyzer
    Error severity, or any Pester failure.

    Use locally:
        pwsh -File tools/Invoke-ToolkitGate.ps1
        pwsh -File tools/Invoke-ToolkitGate.ps1 -Path 'launcher.ps1'
        pwsh -File tools/Invoke-ToolkitGate.ps1 -Strict       # warnings fail too
        pwsh -File tools/Invoke-ToolkitGate.ps1 -SkipTests    # analyzer only

.PARAMETER Path
    Optional file or directory to scope the gate. Defaults to repo root.

.PARAMETER Strict
    Treat Warning severity as failure (Error severity always fails).
    Use after Phase A migration is complete.

.PARAMETER SkipTests
    Skip the Pester run. Useful for quick analyzer-only loops during fixes.

.PARAMETER SkipAnalyzer
    Skip PSScriptAnalyzer. Useful for Pester-only runs.

.PARAMETER Coverage
    Emit a CodeCoverage report alongside the Pester run. Two scopes:
      - lib/*.ps1  (GATING — see -LibCoverageFloor below)
      - per-folder tweak scripts (NON-GATING, baseline only)
    Lib helpers are the long-lived surface area worth gating; per-folder
    scripts are mostly system mutations Pester can't safely exercise
    from dev macOS, so they trend low and gate-by-trend would punish
    legitimate work. Two coverage rows appear in the summary when this
    is passed: CoverageLibPct (gating) and CoverageScriptsPct (report).

.PARAMETER LibCoverageFloor
    Minimum lib/*.ps1 coverage % the gate accepts. Default 25.0 — set
    just below the 28.3% baseline at the start of the overnight run
    (2026-05-24, session 6). The ~3pp safety margin absorbs refactor
    churn without forcing every commit to add tests. Push the floor up
    actively, don't let it drift down. Falling below fires GATE: FAIL
    with the same severity as a Pester failure (revert-don't-fix-forward
    per the standing rule). Only effective when -Coverage is also passed.

    Floor history:
      11.0 — introduced session 4 (baseline 11.1%)
      25.0 — raised session 6 start (baseline 28.3% after session 5 lift)

.EXAMPLE
    PS> pwsh -File tools/Invoke-ToolkitGate.ps1
    Runs full gate on repo. Exit 0 on success.

.EXAMPLE
    PS> pwsh -File tools/Invoke-ToolkitGate.ps1 -Path 'launcher.ps1' -SkipTests
    Quick analyzer-only check on a single file during a fix loop.

.NOTES
    Author:   Win11 Gaming Toolkit
    Version:  1.0
    See:      .psscriptanalyzer.psd1 for rule configuration
              tests/ for Pester suite
#>
[CmdletBinding()]
param(
    [string]$Path = (Split-Path -Parent $PSScriptRoot),
    [switch]$Strict,
    [switch]$SkipTests,
    [switch]$SkipAnalyzer,
    [switch]$Coverage,
    [double]$LibCoverageFloor = 25.0
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $repoRoot '.psscriptanalyzer.psd1'

$exitCode = 0
$summary = [ordered]@{
    AnalyzerErrors = 0
    AnalyzerWarnings = 0
    AnalyzerInfo = 0
    PesterFailed = 0
    PesterPassed = 0
    PesterSkipped = 0
    CoverageLibPct = $null      # populated only when -Coverage is passed
    CoverageScriptsPct = $null  # populated only when -Coverage is passed
}

if (-not $SkipAnalyzer) {
    Write-Output ''
    Write-Output '== PSScriptAnalyzer =='
    if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
        Write-Error 'PSScriptAnalyzer not installed. Install-Module PSScriptAnalyzer -Scope CurrentUser'
        exit 10
    }
    Import-Module PSScriptAnalyzer -ErrorAction Stop

    $analyzerArgs = @{
        Path = $Path
        Recurse = $true
        Settings = $settingsPath
        ErrorAction = 'SilentlyContinue'
    }
    $results = Invoke-ScriptAnalyzer @analyzerArgs

    # Exclude .claude/ from analyzer results regardless of path separator
    # so the gate stays stable when the dev has other worktrees mounted
    # under .claude/worktrees/ (git's working-tree home for parallel
    # branches). PSSA's -Recurse walks every directory under -Path
    # ignoring .gitignore, so sibling worktrees on stale commits would
    # otherwise poison the result on a fresh main checkout.
    $excludeFragment = '[\\/]\.claude[\\/]'
    $results = @($results | Where-Object { $_.ScriptPath -notmatch $excludeFragment })

    $summary.AnalyzerErrors = @($results | Where-Object Severity -EQ 'Error').Count
    $summary.AnalyzerWarnings = @($results | Where-Object Severity -EQ 'Warning').Count
    $summary.AnalyzerInfo = @($results | Where-Object Severity -EQ 'Information').Count

    if ($results) {
        $results | Group-Object Severity |
            ForEach-Object { Write-Output "  $($_.Name): $($_.Count)" }
        if ($summary.AnalyzerErrors -gt 0) {
            Write-Output ''
            Write-Output '-- Errors detail --'
            $results | Where-Object Severity -EQ 'Error' |
                Select-Object RuleName, ScriptName, Line, Message |
                Format-Table -AutoSize | Out-String | Write-Output
        }
    } else {
        Write-Output '  (clean)'
    }

    if ($summary.AnalyzerErrors -gt 0) { $exitCode = 1 }
    if ($Strict -and $summary.AnalyzerWarnings -gt 0) { $exitCode = 1 }
}

if (-not $SkipTests) {
    Write-Output ''
    Write-Output '== Pester =='
    $testsDir = Join-Path $repoRoot 'tests'
    if (-not (Test-Path -LiteralPath $testsDir)) {
        Write-Output '  (no tests/ directory — skipping)'
    } else {
        Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
        $config = New-PesterConfiguration
        $config.Run.Path = $testsDir
        $config.Run.PassThru = $true
        $config.Output.Verbosity = 'Normal'
        # Every test in tests/ runs on every host. The suite is static.
        if ($Coverage) {
            # Cover lib/*.ps1 AND the per-folder tweak scripts. Pester
            # emits a single combined report, so we collect both
            # globs into CodeCoverage.Path and post-split the per-file
            # records afterwards by path-prefix into the lib bucket
            # (gating) and the scripts bucket (informational).
            #
            # We deliberately exclude:
            #   tools/    — gate / dev tooling; should not gate itself
            #   tests/    — test files cover themselves trivially
            #   profile/  — dev environment only, not user-facing
            #   .claude/  — sibling worktrees / cache
            $libDir = Join-Path $repoRoot 'lib'
            $config.CodeCoverage.Enabled = $true
            $coveragePaths = @(
                (Join-Path $libDir '*.ps1')
            )
            # Per-folder tweak scripts: glob every .ps1 under numbered
            # phase folders (0..12) plus the repo-root entry points
            # (APPLY-EVERYTHING.ps1 / REVERT-EVERYTHING.ps1 /
            # launcher.ps1 / DduManual.ps1 / DduAuto.ps1).
            $rootScripts = Get-ChildItem -LiteralPath $repoRoot -Filter '*.ps1' -File -ErrorAction SilentlyContinue
            foreach ($rs in $rootScripts) { $coveragePaths += $rs.FullName }
            $phaseDirs = Get-ChildItem -LiteralPath $repoRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^\d+ ' }
            foreach ($pd in $phaseDirs) { $coveragePaths += (Join-Path $pd.FullName '*.ps1') }
            $config.CodeCoverage.Path = $coveragePaths
            $config.CodeCoverage.OutputFormat = 'JaCoCo'
            $config.CodeCoverage.OutputPath = (Join-Path $repoRoot 'coverage.xml')
        }
        $pesterResult = Invoke-Pester -Configuration $config
        $summary.PesterFailed = $pesterResult.FailedCount
        $summary.PesterPassed = $pesterResult.PassedCount
        $summary.PesterSkipped = $pesterResult.SkippedCount
        if ($Coverage -and $pesterResult.CodeCoverage) {
            $cc = $pesterResult.CodeCoverage
            # Pester v5's CodeCoverage object exposes CommandsExecuted +
            # CommandsMissed (each entry carries a .File property) and
            # the corresponding count properties. There is no
            # CommandsAnalyzed list — analyzed = executed ∪ missed.
            # Bucket by directory match on '/lib/' (or '\lib\' on
            # Windows) so the gating measure (lib only) and the
            # informational measure (scripts) are independent.
            $libSep = ([System.IO.Path]::DirectorySeparatorChar) + 'lib' + ([System.IO.Path]::DirectorySeparatorChar)
            $libGlob = '*' + $libSep + '*'
            $libExec = @($cc.CommandsExecuted | Where-Object { $_.File -like $libGlob }).Count
            $libMissed = @($cc.CommandsMissed | Where-Object { $_.File -like $libGlob }).Count
            $scriptsExec = @($cc.CommandsExecuted | Where-Object { $_.File -notlike $libGlob }).Count
            $scriptsMissed = @($cc.CommandsMissed | Where-Object { $_.File -notlike $libGlob }).Count
            $libTotal = $libExec + $libMissed
            $scriptsTotal = $scriptsExec + $scriptsMissed
            $summary.CoverageLibPct = if ($libTotal -gt 0) {
                [math]::Round(($libExec / $libTotal) * 100, 1)
            } else { 0.0 }
            $summary.CoverageScriptsPct = if ($scriptsTotal -gt 0) {
                [math]::Round(($scriptsExec / $scriptsTotal) * 100, 1)
            } else { 0.0 }
            # GATING: lib coverage must stay at or above the floor.
            if ($summary.CoverageLibPct -lt $LibCoverageFloor) {
                Write-Output ''
                Write-Output ("-- Coverage FAIL: lib at {0}% < floor {1}% --" -f $summary.CoverageLibPct, $LibCoverageFloor)
                $exitCode = 1
            }
        }
        if ($pesterResult.FailedCount -gt 0) { $exitCode = 1 }
        # Scripts coverage is informational only — never touches $exitCode.
    }
}

Write-Output ''
Write-Output '== Summary =='
foreach ($k in $summary.Keys) {
    $v = $summary[$k]
    # Suppress coverage rows entirely when -Coverage wasn't passed
    # so the default summary stays terse for the common-case run.
    if (($k -eq 'CoverageLibPct' -or $k -eq 'CoverageScriptsPct') -and $null -eq $v) { continue }
    Write-Output ("  {0,-20} {1}" -f $k, $v)
}
Write-Output ''
if ($exitCode -eq 0) {
    Write-Output 'GATE: PASS'
} else {
    Write-Output 'GATE: FAIL'
}
exit $exitCode
