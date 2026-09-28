#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract tests for 11 hardware checks/check-storage.ps1.

.DESCRIPTION
    Validates the TRIM-check + repair script's surface contract.
    Static-only. fsutil behavior is outside this file. A Windows
    Sandbox config lives at tests/sandbox/check-storage.wsb.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:Target = Get-ToolkitScriptPath '11 hardware checks/check-storage.ps1'
    $script:Content = Get-Content -Raw -LiteralPath $script:Target
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Target, [ref]$null, [ref]$null
    )
}

Describe 'check-storage.ps1 — surface contract' {

    Context 'File health' {
        It 'parses without errors' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:Target, [ref]$null, [ref]$errors
            )
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'Mutator surface (CLAUDE.md quality bar)' {
        It 'declares [CmdletBinding(SupportsShouldProcess)]' {
            $shape = Test-ToolkitParameterShape -Path $script:Target -RequireShouldProcess
            $shape.SupportsShouldProcess | Should -BeTrue
        }

        It 'has -Fix and -Force switch parameters' {
            $names = $script:Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
            $names | Should -Contain 'Fix'
            $names | Should -Contain 'Force'
        }
    }

    Context 'Comment-based help (CLAUDE.md quality bar)' {
        It 'has SYNOPSIS and DESCRIPTION' {
            $help = Test-ToolkitCommentBasedHelp -Path $script:Target
            $help.HasSynopsis | Should -BeTrue
            $help.HasDescription | Should -BeTrue
        }

        It 'has at least two .EXAMPLE blocks' {
            $count = ([regex]::Matches($script:Content, '\.EXAMPLE')).Count
            $count | Should -BeGreaterOrEqual 2
        }

        It 'documents exit codes in .NOTES' {
            $script:Content | Should -Match 'Exit codes:'
        }
    }

    Context 'Sources cited in header (CLAUDE.md non-obvious-pattern bar)' {
        It 'cites a Microsoft Learn URL for fsutil behavior' {
            $script:Content | Should -Match 'learn\.microsoft\.com.*fsutil'
        }
    }
}
