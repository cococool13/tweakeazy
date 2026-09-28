#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Repo-wide invariant: every mutating .ps1 wires the script-start
    log call UNCONDITIONALLY (script-body scope, not behind a
    conditional that might not fire at runtime).

.DESCRIPTION
    Complement to tests/invariants/script-start-logging.Tests.ps1.
    The existing static-text scan asserts the call EXISTS in the file;
    this AST-based check asserts it EXECUTES on every invocation by
    requiring the call to live at the script body's top level (or
    inside an unconditional ParamBlock / try block — both of which
    always run).

    Concretely, the call must be a direct child of the script root,
    NOT nested inside any of:
      - IfStatementAst       (might be false)
      - ForEachStatementAst  (collection might be empty)
      - ForStatementAst      (init might never enter)
      - WhileStatementAst    (condition might be false)
      - DoUntilStatementAst  (similarly)
      - SwitchStatementAst   (no matching case)
      - FunctionDefinitionAst (only runs when the function is called)

    Try / catch / finally blocks are OK — try always enters.

    Without this invariant, a refactor that moves
        Initialize-ToolkitState
    into
        if ($SomeCondition) { Initialize-ToolkitState }
    would silently break the audit-trail guarantee on a code path the
    user actually hits, but the text-scan invariant would still pass.

    Known-good exclusions: same as the static logging invariant
    (currently none). DduManual.ps1 calls Initialize-ToolkitState
    in the script-body try before the tracked driver-search write.

    Expected gap count: small. Most scripts already place
    Initialize-ToolkitState as a top-level statement; this invariant
    surfaces any historical exceptions and stops new ones landing.

.NOTES
    # CROSS-PLATFORM-NOTE
    # Pure AST analysis. Runs anywhere.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    . (Join-Path $PSScriptRoot '..' '..' 'profile/parts/toolkit-aware.ps1')

    $script:KnownExcluded = @(
        # DduManual.ps1 used to live here. Initialize-ToolkitState now
        # sits in the script-body try, before the driver-search write.
    )

    # Gap-tracking. Same pattern as ShouldProcess / pair-restore: ship
    # the invariant with any pre-existing violations listed, drain
    # per-commit. NEVER add to silence a regression — fix the script.
    $script:LogWiringGaps = @()

    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $all = Test-ToolkitInvariants -RepoRoot $repoRoot
    $script:MutatorCases = @()
    foreach ($row in $all) {
        if (-not $row.IsMutator) { continue }
        if ($script:KnownExcluded -contains $row.Path) { continue }
        $script:MutatorCases += @{
            Path = $row.Path
            FullPath = (Join-Path $repoRoot $row.Path)
            WiringGap = ($script:LogWiringGaps -contains $row.Path)
        }
    }
}

Describe 'Invariant: log-wiring call sits at script-body scope (unconditional)' {

    It '<Path> calls Initialize-ToolkitState or Write-ToolkitScriptStart at top level' -ForEach $script:MutatorCases {
        if ($WiringGap) {
            Set-ItResult -Skipped -Because 'tracked in $LogWiringGaps; shrink per-commit'
            return
        }

        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $FullPath, [ref]$null, [ref]$errors
        )
        $errors | Should -BeNullOrEmpty -Because 'AST parse must succeed before structural check'

        # Acceptable callee names — the static invariant's two patterns.
        $acceptableNames = @('Initialize-ToolkitState', 'Write-ToolkitScriptStart')

        # Conditional AST types — call sitting inside any of these is
        # NOT unconditional, fails the invariant.
        # try/catch/finally/end blocks are allowed (try always enters);
        # ParamBlock is at script-body scope by definition.
        $conditionalAstTypes = @(
            [System.Management.Automation.Language.IfStatementAst]
            [System.Management.Automation.Language.ForEachStatementAst]
            [System.Management.Automation.Language.ForStatementAst]
            [System.Management.Automation.Language.WhileStatementAst]
            [System.Management.Automation.Language.DoUntilStatementAst]
            [System.Management.Automation.Language.DoWhileStatementAst]
            [System.Management.Automation.Language.SwitchStatementAst]
            [System.Management.Automation.Language.FunctionDefinitionAst]
        )

        # Find every CommandAst calling one of the acceptable names.
        $calls = $ast.FindAll({
                param($n)
                if ($n -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
                $cmdName = $n.GetCommandName()
                return ($cmdName -and ($acceptableNames -contains $cmdName))
            }, $true)

        $calls | Should -Not -BeNullOrEmpty `
            -Because 'static invariant should have caught absent calls already; if this fires the two invariants are out of sync'

        # At least ONE such call must live outside every conditional
        # ancestor type. Walk parent chain; if no conditional found,
        # the call is unconditional.
        $hasUnconditional = $false
        foreach ($call in $calls) {
            $node = $call.Parent
            $insideConditional = $false
            while ($null -ne $node) {
                foreach ($t in $conditionalAstTypes) {
                    if ($node -is $t) {
                        $insideConditional = $true
                        break
                    }
                }
                if ($insideConditional) { break }
                $node = $node.Parent
            }
            if (-not $insideConditional) {
                $hasUnconditional = $true
                break
            }
        }

        $hasUnconditional | Should -BeTrue `
            -Because 'every call to Initialize-ToolkitState / Write-ToolkitScriptStart was nested inside a conditional that might not fire at runtime — the audit-trail guarantee is broken on some code path the user could hit'
    }
}
