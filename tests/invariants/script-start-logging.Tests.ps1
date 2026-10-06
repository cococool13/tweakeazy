#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Repo-wide invariant: every mutating .ps1 must auto-log a script-start line.

.DESCRIPTION
    Two acceptable patterns for the script-start audit trail:
      A) Calls Initialize-ToolkitState (which auto-invokes
         Write-ToolkitScriptStart with SkipFrames=2)
      B) Calls Write-ToolkitScriptStart explicitly after dot-sourcing
         lib/toolkit-state.ps1

    Either is fine; both fail-shut. A script that mutates state but
    skips both means a user can run the script and we'd have no log
    trail showing they did. CLAUDE.md quality bar: "Logging: every
    action + every skip to ProgramData\<toolkit>\logs\..."

    Known-good exclusions (with reason):
      none. DduManual.ps1 used to be excluded (own DDU-Auto.log
      transcript). It now calls Initialize-ToolkitState before the
      tracked SearchOrderConfig write, so the invariant covers it.

.NOTES
    # CROSS-PLATFORM-NOTE
    # This is a text-scan invariant; runs anywhere. Catches the
    # regression where a future commit removes Initialize-ToolkitState
    # from a script without adding an explicit Write-ToolkitScriptStart.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')

    # Acknowledged exceptions to the invariant — keep this list small
    # and re-justified each time. Format: relative path from repo root.
    $script:KnownExcluded = @(
        # DduManual.ps1 used to live here (own transcript). It now calls
        # Initialize-ToolkitState before the tracked SearchOrderConfig write.
    )

    # Discover mutators by re-using Test-ToolkitInvariants' classifier
    # (it walks .ps1 files, excludes lib/profile/tests/tools).
    . (Join-Path $PSScriptRoot '..' '..' 'profile/parts/toolkit-aware.ps1')
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $all = Test-ToolkitInvariants -RepoRoot $repoRoot
    $script:MutatorCases = @()
    foreach ($row in $all) {
        if (-not $row.IsMutator) { continue }
        if ($script:KnownExcluded -contains $row.Path) { continue }
        $script:MutatorCases += @{ Path = $row.Path; FullPath = (Join-Path $repoRoot $row.Path) }
    }
}

Describe 'Invariant: every mutator script auto-logs script-start' {

    It '<Path> calls Initialize-ToolkitState OR Write-ToolkitScriptStart' -ForEach $script:MutatorCases {
        $content = Get-Content -Raw -LiteralPath $FullPath
        $hasInit = $content -match 'Initialize-ToolkitState'
        $hasExplicit = $content -match 'Write-ToolkitScriptStart'
        ($hasInit -or $hasExplicit) | Should -BeTrue `
            -Because 'mutators must produce an audit trail; one of these calls is required'
    }
}
