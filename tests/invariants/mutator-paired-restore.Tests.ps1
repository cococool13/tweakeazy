#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Repo-wide invariant: every mutating .ps1 ships with a paired
    sibling that reverses (or matches) its action.

.DESCRIPTION
    CLAUDE.md invariant: "every new opt-in tweak ships with a
    colocated enable-* (or revert-*) sibling script. Manifest-only
    revert is not a substitute for a paired script — both are required."

    For each mutator, derive the expected inverse-prefix stem and
    confirm a sibling file (.ps1 OR .bat) exists in the SAME directory.

    Pair prefix map (symmetric — checking either side finds the other):
      disable   <-> enable
      install   <-> uninstall
      configure <-> revert  (also restore)
      apply     <-> revert
      force     <-> revert  (also disable)
      pause     <-> resume
      tune      <-> restore
      optimize  <-> revert

    Acceptable: sibling stem matches inverse-prefix on either .ps1
    or .bat. Also acceptable: a configure-* script that exposes both
    -Enable and -Disable switches (configure-vbs.ps1) — apply and
    revert live in the same file; no wrapper sibling required.

    Known exclusions ($KnownUnpairable) — append-only with justification:
      - APPLY-EVERYTHING.ps1 / REVERT-EVERYTHING.ps1 mutually pair (handled
        by the inverse-stem check — listed for documentation only).
      - DduManual.ps1: standalone DDU stager; revert is "reinstall driver".
      - 0 prerequisites/install-runtimes.ps1: runtimes are install-only;
        uninstall isn't a goal of the toolkit.
      - 9 cleanup/cleanup-temp.ps1: destructive temp cleanup; no revert is
        possible by definition.

.NOTES
    # CROSS-PLATFORM-NOTE
    # Pure file-existence checks; runs anywhere the repo is checked out.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    . (Join-Path $PSScriptRoot '..' '..' 'profile/parts/toolkit-aware.ps1')

    # Acknowledged unpairables — destructive-only or install-only scripts
    # where a revert script would be meaningless. Keep tight and justified.
    $script:KnownUnpairable = @(
        'DduManual.ps1'
        '0 prerequisites/install-runtimes.ps1'
        '9 cleanup/cleanup-temp.ps1'
        # 13 external tools/*: launchers for signed third-party GUIs. They
        # download, verify, and start someone else's tool; the toolkit makes
        # no change of its own, so there is nothing for a revert sibling to
        # undo. Each tool owns its own undo (ShutUp10 restore points,
        # re-ticking an Autoruns entry, reattaching hardware). They land here
        # rather than in $PairGaps because the pair is meaningless, not missing.
        '13 external tools/launch-shutup10.ps1'
        '13 external tools/launch-autoruns.ps1'
        '13 external tools/launch-device-cleanup.ps1'
    )

    # Pair-stem gaps: scripts whose inverse-prefix sibling is missing.
    # Shrink per-commit by adding the missing pair, NOT by silencing here.
    # Each entry is a genuine "missing apply/revert sibling" violation
    # of CLAUDE.md's pair-script invariant; fixes are tracked in
    # KNOWN-ISSUES.md under "Pair-script gaps".
    # All 7 original pair-script gaps closed:
    #   - 3x GPU install/uninstall pairs   (commit 127fda2 — lib helper)
    #   - 2x explorer-affinity rename pair (worktree rename, commit 127fda2)
    #   - 4 services/disable-services      (revert-all.ps1 → enable-services.ps1)
    #   - 2 power plan/configure-power     (added revert-power.ps1)
    # Keep the (empty) array so the structure stays in place for any
    # gap a future contributor surfaces with a new mismatched-prefix script.
    $script:PairGaps = @()

    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $all = Test-ToolkitInvariants -RepoRoot $repoRoot
    $script:PairCases = @()
    foreach ($row in $all) {
        if (-not $row.IsMutator) { continue }
        if ($script:KnownUnpairable -contains $row.Path) { continue }
        $script:PairCases += @{
            Path = $row.Path
            FullPath = (Join-Path $repoRoot $row.Path)
            PairGap = ($script:PairGaps -contains $row.Path)
        }
    }
}

Describe 'Invariant: every mutator has a paired sibling (apply/revert)' {

    It '<Path> has a paired sibling in the same directory' -ForEach $script:PairCases {
        if ($PairGap) {
            Set-ItResult -Skipped -Because 'tracked in $PairGaps; shrink per-commit'
            return
        }

        # Inline the prefix map: $script: vars set in BeforeDiscovery don't
        # survive into It-body runtime scope. Symmetric — for each verb
        # prefix, list every prefix that's a valid pair on the other side.
        $pairPrefixMap = @{
            'disable' = @('enable')
            'enable' = @('disable')
            'install' = @('uninstall')
            'uninstall' = @('install')
            # configure-* can be Apply/Revert via a sibling
            # (revert-/restore-/disable-/enable-*) OR self-paired via
            # -Enable/-Disable switches on the same script.
            'configure' = @('revert', 'restore', 'disable', 'enable')
            'revert' = @('configure', 'apply', 'force', 'optimize', 'install', 'tune')
            'restore' = @('configure', 'tune', 'apply', 'disable')
            'apply' = @('revert', 'restore')
            'force' = @('revert', 'disable')
            'pause' = @('resume')
            'resume' = @('pause')
            'tune' = @('restore', 'revert')
            'optimize' = @('revert')
        }

        $dir = Split-Path -Parent $FullPath
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($FullPath)

        # Self-pair: configure-vbs.ps1 (and any mutator with both
        # -Enable and -Disable switches) applies and reverts in-file.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $FullPath, [ref]$null, [ref]$null)
        if ($ast -and $ast.ParamBlock) {
            $paramNames = @(
                $ast.ParamBlock.Parameters |
                    ForEach-Object { $_.Name.VariablePath.UserPath }
            )
            $hasEnable = $false
            $hasDisable = $false
            foreach ($n in $paramNames) {
                if ($n -eq 'Enable') { $hasEnable = $true }
                if ($n -eq 'Disable') { $hasDisable = $true }
            }
            if ($hasEnable -and $hasDisable) {
                $true | Should -BeTrue
                return
            }
        }

        # Case-insensitive sibling lookup. Test-Path is case-SENSITIVE on
        # Linux runners, so the generated candidate 'revert-EVERYTHING.ps1'
        # would never find the real 'REVERT-EVERYTHING.ps1' — a pair that
        # resolves fine on Windows/macOS. Snapshot the directory once and
        # compare names case-insensitively so the invariant means the same
        # thing on every platform.
        $siblings = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($s in (Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
            [void]$siblings.Add($s.Name)
        }

        # Normalize APPLY-EVERYTHING / REVERT-EVERYTHING (uppercase).
        # Also handles mobsync-disable (suffix-style verb) by checking both.
        $verbMatched = $false
        $foundPair = $false
        $tried = @()

        foreach ($prefix in $pairPrefixMap.Keys) {
            # Match prefix-style: 'disable-foo' / 'DISABLE-foo'.
            if ($stem -match "^(?i)$prefix-(.+)$") {
                $verbMatched = $true
                $tail = $matches[1]
                foreach ($inverse in $pairPrefixMap[$prefix]) {
                    foreach ($ext in @('.ps1', '.bat')) {
                        $candidate = "$inverse-$tail$ext"
                        $tried += (Join-Path $dir $candidate)
                        if ($siblings.Contains($candidate)) {
                            $foundPair = $true
                            break
                        }
                    }
                    if ($foundPair) { break }
                }
            }
            # Match suffix-style: 'foo-disable' / 'foo-enable' (mobsync).
            if (-not $foundPair -and $stem -match "^(.+)-(?i)$prefix$") {
                $verbMatched = $true
                $head = $matches[1]
                foreach ($inverse in $pairPrefixMap[$prefix]) {
                    foreach ($ext in @('.ps1', '.bat')) {
                        $candidate = "$head-$inverse$ext"
                        $tried += (Join-Path $dir $candidate)
                        if ($siblings.Contains($candidate)) {
                            $foundPair = $true
                            break
                        }
                    }
                    if ($foundPair) { break }
                }
            }
            if ($foundPair) { break }
        }

        # Verb didn't match any known prefix — e.g. 'explorer-affinity-core1'
        # uses a noun stem with no verb. Treat as a separate failure mode
        # so the gap-list message points the developer at the right fix:
        # rename to a verb-prefixed form, OR add to $KnownUnpairable with
        # justification.
        if (-not $verbMatched) {
            $false | Should -BeTrue `
                -Because "stem '$stem' doesn't match any known verb prefix (disable/enable/configure/etc.); rename or add to `$KnownUnpairable"
            return
        }

        $foundPair | Should -BeTrue `
            -Because "expected an inverse-prefix sibling (.ps1 or .bat) in '$dir' — none of these existed: $($tried -join ', ')"
    }
}
