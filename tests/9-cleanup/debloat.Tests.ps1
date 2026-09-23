#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract tests for 9 cleanup/debloat.ps1.

.DESCRIPTION
    debloat.ps1 is the most destructive routine "in the Safe tier" — it
    removes UWP packages permanently. Regressions here cause real data
    loss (removed apps not restorable from arbitrary backups).

    Key invariants tested:
      - $neverRemove safety list is enforced on every removal candidate
        (regression test for f71d130 — the bug where the list was
        declared but never consulted)
      - Removals go through Invoke-ToolkitDebloatRemoval, which
        records state.packages.removed only after Remove-AppxPackage
        succeeds (so restore-debloat.ps1 can read)
      - Provisioned-package removal is recorded only after success,
        via the same helper, so a failed image-level remove is not
        written to state.packages.provisionedRemoved
      - Admin self-check present
      - Pair script (9 cleanup/restore-debloat.ps1) exists
      - Microsoft.WindowsStore is in the protected list (you can't
        winget-reinstall apps without the Store; removing it is fatal)

.NOTES
    # CROSS-PLATFORM-NOTE
    # Actual Get-AppxPackage / Remove-AppxPackage calls are Windows-only.
    # See tests/manual/debloat.md for the human verifier checklist.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:CriticallyProtected = @(
        @{ Name = 'Microsoft.WindowsStore' }      # without this, no winget restore path
        @{ Name = 'Microsoft.DesktopAppInstaller' } # ditto — IS winget itself
        @{ Name = 'Microsoft.Windows.Photos' }    # default image viewer
        @{ Name = 'Microsoft.WindowsCalculator' } # ditto, fallback calc
        @{ Name = 'Microsoft.WindowsTerminal' }   # primary admin shell on 24H2+
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:Target = Get-ToolkitScriptPath '9 cleanup/debloat.ps1'
    $script:RestorePair = Get-ToolkitScriptPath '9 cleanup/restore-debloat.ps1'
    $script:Content = Get-Content -Raw -LiteralPath $script:Target
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Target, [ref]$null, [ref]$null
    )
}

Describe '9 cleanup/debloat.ps1 — surface contract' {

    Context 'File health' {
        It 'parses without errors' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:Target, [ref]$null, [ref]$errors
            )
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'Admin self-check (CLAUDE.md invariant #6)' {
        It 'has IsInRole(Administrator) check in script body' {
            $head = ($script:Content -split "`n" | Select-Object -First 50) -join "`n"
            $head | Should -Match 'IsInRole.*Administrator'
        }
    }

    Context 'Safety list (regression test for f71d130)' {
        It 'loads $neverRemove from the shared catalog' {
            $script:Content | Should -Match '\$neverRemove\s*=\s*@\(Get-ToolkitDebloatNeverRemove\)'
        }

        It 'enforces $neverRemove inside the foreach (this WAS the bug)' {
            # Pre-f71d130: list existed but was never checked.
            # The fix wires a `if ($neverRemove -contains $app.Name) { continue }`
            # at the top of the scan loop.
            $script:Content | Should -Match '\$neverRemove\s+-contains\s+\$app\.Name'
        }

        It 'loads the removal list from the shared catalog' {
            $script:Content | Should -Match '\$appsToRemove\s*=\s*@\(Get-ToolkitDebloatCatalog\)'
        }

        It 'critically-protected app <Name> is on the shared never-remove list' -ForEach $script:CriticallyProtected {
            $catalog = Get-Content -Raw -LiteralPath (Get-ToolkitScriptPath 'lib/debloat-catalog.ps1')
            $catalog | Should -Match ([regex]::Escape($Name))
        }
    }

    Context 'Manifest tracking (CLAUDE.md invariant #5)' {
        It 'removes the current-user package through Invoke-ToolkitDebloatRemoval' {
            $script:Content | Should -Match 'Invoke-ToolkitDebloatRemoval\s+-PackageName\s+\$app\.Name\s+-Scope\s+User'
        }

        It 'removes the provisioned package through Invoke-ToolkitDebloatRemoval' {
            $script:Content | Should -Match 'Invoke-ToolkitDebloatRemoval\s+-PackageName\s+\$app\.Name\s+-Scope\s+Provisioned'
        }

        It 'does not call Remove-AppxProvisionedPackage itself' {
            $calls = $script:Ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq 'Remove-AppxProvisionedPackage'
                }, $true)
            @($calls) | Should -BeNullOrEmpty
        }
    }

    Context 'Restore pairing convention' {
        It 'restore-debloat.ps1 exists alongside it' {
            Test-Path -LiteralPath $script:RestorePair | Should -BeTrue
        }

        It 'header points users at the pair script' {
            $head = ($script:Content -split "`n" | Select-Object -First 25) -join "`n"
            $head | Should -Match 'restore-debloat\.ps1'
        }
    }

    Context 'Removal preview gates on user confirm' {
        It 'shows what will be removed before actually removing' {
            # User must see the list and respond before any
            # Remove-AppxPackage runs. Pre-confirm prompt pattern.
            $script:Content | Should -Match 'Press\s+Enter\s+to\s+continue'
        }
    }
}
