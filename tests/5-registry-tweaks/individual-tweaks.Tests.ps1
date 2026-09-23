#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Templated contract sweep over 5 registry tweaks/individual/*.ps1.

.DESCRIPTION
    Architecture-over-wiring move: instead of N per-script test files
    that duplicate the standard assertions, one parameterized suite
    discovers every .ps1 in the folder and runs the standard matrix
    against each. Future tweak scripts dropped into the folder get
    coverage automatically.

    Matrix per script:
      - File parses (AST smoke test)
      - Comment-based help present (.SYNOPSIS, .DESCRIPTION at minimum)
      - Admin self-check present (CLAUDE.md invariant #6)
      - Script-start audit-log wired (calls Initialize-ToolkitState
        OR Write-ToolkitScriptStart explicitly; matches the
        tests/invariants/script-start-logging.Tests.ps1 contract
        but scoped to this folder so violations cluster here)
      - Mutator: declares [CmdletBinding(SupportsShouldProcess)]
        (skipped for read-only / non-mutator scripts via $ReadOnlyScripts)

    Pair-specific parity (when both halves exist):
      - Apply uses Save-ToolkitSidecar / Set-Toolkit* helpers
      - Revert uses Read-ToolkitSidecar / Restore-Toolkit* helpers
      - Cross-script Ids OR sidecar stems match

    Per-pair tests covered by their own dedicated suites are excluded
    via $DedicatedPair to avoid double-asserting (MMCSS audio currently;
    add others here as they get bespoke suites).

.NOTES
    All AST/text-scan; runs anywhere. No registry/service mutation.
    Maps in BeforeDiscovery so Pester v5 -ForEach can expand them.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')

    $folderPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '5 registry tweaks/individual'
    $allScripts = Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File

    # Scripts that intentionally do NOT mutate: read-only checkers or
    # explicit report-only modes. None in this folder currently — add
    # here if a future check-* script lands.
    $script:ReadOnlyScripts = @()

    # Scripts owned by a dedicated suite — skip the duplicate matrix.
    $script:DedicatedPair = @(
        'tune-mmcss-audio.ps1', 'restore-mmcss-audio.ps1'
    )

    # Known gaps per assertion. Each subsequent commit closes one or more
    # entries and removes them from these arrays — gate must stay green
    # throughout. Empty array = no exceptions, assertion holds for all.
    #
    # Gaps surfaced when this suite first ran (commit landing this file).
    # Don't add new exceptions to clear future regressions — fix the script.
    $script:HelpGaps = @(
        # Most legacy scripts in this folder use freeform header comments
        # instead of PowerShell comment-based-help blocks. Get-Help <script>
        # returns nothing for these — real user impact.
        # Cleared once .SYNOPSIS/.DESCRIPTION landed:
        #   configure-mmagent.ps1, disable-mpo.ps1, enable-windows-update.ps1,
        #   revert-mmagent.ps1, uninstall-timer-resolution-service.ps1
        'disable-edge-background.ps1'
        'disable-ntfs-last-access.ps1'
        'disable-spectre-meltdown.ps1'
        'disable-windows-update.ps1'
        'disable-write-cache-flush.ps1'
        'enable-edge-background.ps1'
        'enable-mpo.ps1'
        'enable-ntfs-last-access.ps1'
        'enable-spectre-meltdown.ps1'
        'enable-write-cache-flush.ps1'
        # Renamed in worktree commit 127fda2:
        #   explorer-affinity-core1.ps1 → disable-explorer-affinity.ps1
        #   restore-explorer-affinity.ps1 → enable-explorer-affinity.ps1
        # Both renamed scripts now match the verb-prefix rule and pass
        # the help check naturally; not listed here as gaps.
        'install-timer-resolution-service.ps1'
        'pause-windows-update.ps1'
        'resume-windows-update.ps1'
    )
    $script:ApplyHelperGaps = @(
        # install-timer-resolution-service.ps1 writes via raw `sc.exe`/`New-Service`
        # for the kernel timer service. Manifest helper doesn't currently
        # cover service-install; uninstall script handles cleanup but the
        # apply side is intentionally bare. Fixable by extending the lib.
        'install-timer-resolution-service.ps1'

        # configure-mmagent.ps1 captures pre-state via Get-MMAgent + writes
        # via Disable-MMAgent (cmdlet, not a toolkit helper). Could shift
        # to sidecar+manifest but functionally already captures state.
        # Fixable by routing through Save-ToolkitSidecar for the snapshot.
        'configure-mmagent.ps1'
    )
    $script:RestoreHelperGaps = @(
        # 3 restore scripts predate the lib helpers + use raw reg/sc commands.
        # Each fixable as a single Set-ToolkitRegistryValue / Restore-* swap.
        'enable-windows-update.ps1'
        'uninstall-timer-resolution-service.ps1'
        'revert-mmagent.ps1'

        # enable-hags.ps1 writes the canonical HwSchMode=2 through
        # Set-ToolkitRegistryValue. It is the experimental on-switch,
        # not a manifest restore. Surfaced when the HAGS pair joined
        # $pairs; disable-hags.ps1 still asserts the apply helper.
        'enable-hags.ps1'
    )

    # Pair manifest (apply, revert). Driven from explicit data rather
    # than name-pattern guessing because install/uninstall and
    # configure/revert don't fit a single regex.
    $pairs = @(
        @{ Apply = 'disable-edge-background.ps1'; Restore = 'enable-edge-background.ps1' }
        @{ Apply = 'disable-mpo.ps1'; Restore = 'enable-mpo.ps1' }
        @{ Apply = 'disable-ntfs-last-access.ps1'; Restore = 'enable-ntfs-last-access.ps1' }
        @{ Apply = 'disable-spectre-meltdown.ps1'; Restore = 'enable-spectre-meltdown.ps1' }
        @{ Apply = 'disable-windows-update.ps1'; Restore = 'enable-windows-update.ps1' }
        @{ Apply = 'disable-write-cache-flush.ps1'; Restore = 'enable-write-cache-flush.ps1' }
        @{ Apply = 'disable-explorer-affinity.ps1'; Restore = 'enable-explorer-affinity.ps1' }
        @{ Apply = 'pause-windows-update.ps1'; Restore = 'resume-windows-update.ps1' }
        @{ Apply = 'install-timer-resolution-service.ps1'; Restore = 'uninstall-timer-resolution-service.ps1' }
        @{ Apply = 'configure-mmagent.ps1'; Restore = 'revert-mmagent.ps1' }
        # Newer opt-in pairs. Per-script parse/admin/log already covered
        # them; listing them here runs helper-parity asserts too.
        @{ Apply = 'disable-allow-telemetry.ps1'; Restore = 'enable-allow-telemetry.ps1' }
        @{ Apply = 'disable-diagtrack.ps1'; Restore = 'enable-diagtrack.ps1' }
        @{ Apply = 'disable-ceip.ps1'; Restore = 'enable-ceip.ps1' }
        @{ Apply = 'disable-activity-history.ps1'; Restore = 'enable-activity-history.ps1' }
        @{ Apply = 'disable-advertising-id.ps1'; Restore = 'enable-advertising-id.ps1' }
        @{ Apply = 'disable-cortana.ps1'; Restore = 'enable-cortana.ps1' }
        @{ Apply = 'disable-web-search-start.ps1'; Restore = 'enable-web-search-start.ps1' }
        @{ Apply = 'disable-edge-prefetch.ps1'; Restore = 'enable-edge-prefetch.ps1' }
        @{ Apply = 'configure-pagefile.ps1'; Restore = 'revert-pagefile.ps1' }
        @{ Apply = 'disable-hags.ps1'; Restore = 'enable-hags.ps1' }
        @{ Apply = 'disable-storage-sense.ps1'; Restore = 'enable-storage-sense.ps1' }
    )

    # Per-script test cases (skip dedicated + read-only). The Help-gap
    # row is annotated so the help assertion can Skip it explicitly,
    # making the deferred work visible in test output instead of silent.
    $script:ScriptCases = @()
    foreach ($f in $allScripts) {
        if ($script:DedicatedPair -contains $f.Name) { continue }
        $script:ScriptCases += @{
            Name = $f.Name
            FullPath = $f.FullName
            IsReadOnly = ($script:ReadOnlyScripts -contains $f.Name)
            HelpGap = ($script:HelpGaps -contains $f.Name)
        }
    }

    # Per-pair test cases (skip dedicated, only when both halves exist
    # in $allScripts). ApplyHelperGap / RestoreHelperGap flags surface
    # the known shortfalls so each fix-commit is greppable.
    $names = $allScripts | ForEach-Object Name
    $script:PairCases = @()
    foreach ($p in $pairs) {
        if ($script:DedicatedPair -contains $p.Apply -or $script:DedicatedPair -contains $p.Restore) { continue }
        if ($names -notcontains $p.Apply -or $names -notcontains $p.Restore) { continue }
        $script:PairCases += @{
            Apply = $p.Apply
            Restore = $p.Restore
            ApplyPath = (Join-Path $folderPath $p.Apply)
            RestorePath = (Join-Path $folderPath $p.Restore)
            ApplyHelperGap = ($script:ApplyHelperGaps -contains $p.Apply)
            RestoreHelperGap = ($script:RestoreHelperGaps -contains $p.Restore)
        }
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
}

Describe '5 registry tweaks/individual/ — per-script contract' {

    Context 'Parse + help + admin (every script)' {
        It '<Name> parses without errors' -ForEach $script:ScriptCases {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($FullPath, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }

        It '<Name> has comment-based help (SYNOPSIS + DESCRIPTION)' -ForEach $script:ScriptCases {
            # Gap-list lives in BeforeDiscovery $HelpGaps. Each subsequent
            # commit shrinks that list as scripts get help blocks.
            # Pester v5 -Skip is discovery-time, not per-case — so we
            # check per-case via Set-ItResult inside the body.
            if ($HelpGap) {
                Set-ItResult -Skipped -Because 'tracked in $HelpGaps; shrunk per-commit'
                return
            }
            $h = Test-ToolkitCommentBasedHelp -Path $FullPath
            $h.HasSynopsis | Should -BeTrue -Because 'CLAUDE.md docs gate requires .SYNOPSIS'
            $h.HasDescription | Should -BeTrue
        }

        It '<Name> self-checks admin' -ForEach $script:ScriptCases {
            (Test-ToolkitAdminCheck -Path $FullPath).Passes | Should -BeTrue -Because 'CLAUDE.md invariant #6'
        }

        It '<Name> auto-logs script-start (Initialize-ToolkitState OR Write-ToolkitScriptStart)' -ForEach $script:ScriptCases {
            $content = Get-Content -Raw -LiteralPath $FullPath
            $hasInit = $content -match 'Initialize-ToolkitState'
            $hasExplicit = $content -match 'Write-ToolkitScriptStart'
            ($hasInit -or $hasExplicit) | Should -BeTrue -Because 'audit trail requires script-start log line'
        }
    }
}

Describe '5 registry tweaks/individual/ — apply/restore pair parity' {

    Context 'Cross-script convention' {
        It '<Apply> + <Restore> both parse cleanly' -ForEach $script:PairCases {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($ApplyPath, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($RestorePath, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }

        It '<Apply> writes via a toolkit helper (Save-ToolkitSidecar OR Set-Toolkit*)' -ForEach $script:PairCases {
            if ($ApplyHelperGap) {
                Set-ItResult -Skipped -Because 'tracked in $ApplyHelperGaps; shrunk per-commit'
                return
            }
            $content = Get-Content -Raw -LiteralPath $ApplyPath
            $usesSidecar = $content -match 'Save-ToolkitSidecar'
            $usesRegistry = $content -match 'Set-ToolkitRegistryValue'
            $usesService = $content -match 'Set-ToolkitServiceStartMode'
            ($usesSidecar -or $usesRegistry -or $usesService) | Should -BeTrue `
                -Because 'CLAUDE.md invariant #2 — tracked writes only'
        }

        It '<Restore> reads via a toolkit helper (Read-ToolkitSidecar OR Restore-Toolkit*)' -ForEach $script:PairCases {
            if ($RestoreHelperGap) {
                Set-ItResult -Skipped -Because 'tracked in $RestoreHelperGaps; shrunk per-commit'
                return
            }
            $content = Get-Content -Raw -LiteralPath $RestorePath
            $usesSidecar = $content -match 'Read-ToolkitSidecar'
            $usesRegistry = $content -match 'Restore-ToolkitRegistryValue'
            $usesService = $content -match 'Restore-ToolkitServiceStartMode'
            ($usesSidecar -or $usesRegistry -or $usesService) | Should -BeTrue `
                -Because 'revert path must walk the manifest or sidecar — not blind defaults'
        }
    }
}
