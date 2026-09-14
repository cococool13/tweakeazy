#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract tests for launcher.ps1.

.DESCRIPTION
    Launcher.ps1 is the user's primary entry point. Regressions in
    its category list, key map, or quick-action wiring break every
    downstream script. These AST-level tests catch:
      - Function surface stability (20 named functions)
      - LauncherCategories key uniqueness (no two folders fight for [N])
      - LauncherQuickActions completeness (A V R always present)
      - Apply-All wiring includes the IncludeSecurityTradeoffs prompt
      - Admin refusal short-circuit present

    Runtime tests (actual menu rendering, key bindings) are Windows-
    only and live under tests/integration/.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '_common.ps1')
    $script:ExpectedFunctions = @(
        @{ Name = 'Initialize-LauncherEnvironment' }
        @{ Name = 'Get-LauncherManifestSnapshot' }
        @{ Name = 'Get-CategoryStatus' }
        @{ Name = 'Show-MainMenu' }
        @{ Name = 'Show-CategoryMenu' }
        @{ Name = 'Invoke-CategoryFile' }
        @{ Name = 'Invoke-QuickAction' }
        @{ Name = 'Invoke-ViewManifest' }
        @{ Name = 'Invoke-ViewRecentLog' }
        @{ Name = 'Invoke-RegenerateBaseline' }
        @{ Name = 'Start-Launcher' }
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot '_common.ps1')
    $script:Target = Get-ToolkitScriptPath 'launcher.ps1'
    $script:Content = Get-Content -Raw -LiteralPath $script:Target
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Target, [ref]$null, [ref]$null
    )
    $script:Functions = $script:Ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)
    $script:FunctionNames = @($script:Functions | ForEach-Object Name)
}

Describe 'launcher.ps1 — surface contract' {

    Context 'File health' {
        It 'parses without errors' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:Target, [ref]$null, [ref]$errors
            )
            $errors | Should -BeNullOrEmpty
        }

        It 'has 20 named functions' {
            # Regression catch: drift past this count means someone
            # added/removed without updating $script:ExpectedFunctions.
            # If this fails, audit the diff and update both this number
            # AND the expected list above.
            $script:Functions.Count | Should -Be 20
        }
    }

    Context 'Public function surface' {
        It 'declares <Name>' -ForEach $script:ExpectedFunctions {
            $script:FunctionNames | Should -Contain $Name
        }
    }

    Context 'LauncherCategories key map' {
        It 'declares no duplicate Key values' {
            # The launcher routes by Key; collisions silently break a folder.
            # Pre-fix bug: "1 backup" + "1 Check" both wanted [1].
            $keyLines = ($script:Content -split "`n") | Where-Object { $_ -match '^\s*\[PSCustomObject\]@\{\s*Key\s*=' }
            $keys = $keyLines | ForEach-Object {
                if ($_ -match 'Key\s*=\s*"([^"]+)"') { $Matches[1] }
            }
            $duplicates = @($keys | Group-Object | Where-Object Count -gt 1)
            $duplicates.Count | Should -Be 0 -Because 'duplicate keys silently break menu routing for the second folder'
        }

        It 'wires both new folders (Keys 11, 12)' {
            $script:Content | Should -Match 'Key\s*=\s*"11"'
            $script:Content | Should -Match 'Key\s*=\s*"12"'
        }
    }

    Context 'LauncherQuickActions completeness' {
        It 'declares the A / V / R quick actions' {
            $script:Content | Should -Match 'Key\s*=\s*"A".*APPLY-EVERYTHING'
            $script:Content | Should -Match 'Key\s*=\s*"V".*verify-tweaks'
            $script:Content | Should -Match 'Key\s*=\s*"R".*REVERT-EVERYTHING'
        }
    }

    Context 'Apply All security trade-offs prompt (CURSOR-AUDIT #1)' {
        It 'Invoke-QuickAction prompts for IncludeSecurityTradeoffs when Key=A' {
            $fn = $script:Functions | Where-Object Name -EQ 'Invoke-QuickAction'
            $fn | Should -Not -BeNullOrEmpty
            $body = $fn.Body.Extent.Text
            $body | Should -Match 'Include\s*Security\s*Trade-?offs'
            $body | Should -Match '-IncludeSecurityTradeoffs'
        }
    }

    Context 'Admin refusal short-circuit' {
        It 'Start-Launcher exits early when not Administrator' {
            $fn = $script:Functions | Where-Object Name -EQ 'Start-Launcher'
            $fn | Should -Not -BeNullOrEmpty
            $body = $fn.Body.Extent.Text
            $body | Should -Match 'IsInRole.*Administrator'
            $body | Should -Match 'exit 1'
        }
    }
}
