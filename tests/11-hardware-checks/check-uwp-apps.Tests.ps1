#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract tests for 11 hardware checks/check-uwp-apps.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:Target = Get-ToolkitScriptPath '11 hardware checks/check-uwp-apps.ps1'
    $script:Content = Get-Content -Raw -LiteralPath $script:Target
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Target, [ref]$null, [ref]$null)
}

Describe 'check-uwp-apps.ps1 — surface contract' {

    Context 'File health' {
        It 'parses without errors' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:Target, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'Param surface (read-only audit, no mutation)' {
        It 'does NOT declare SupportsShouldProcess (read-only)' {
            $cb = $script:Ast.ParamBlock.Attributes |
                Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }
            # If a future commit adds SupportsShouldProcess, that means
            # the script now mutates — which would violate the "Tier:
            # Safe (read-only)" header claim. Catch it here.
            $hasSP = $false
            if ($cb) {
                foreach ($n in $cb.NamedArguments) {
                    if ($n.ArgumentName -eq 'SupportsShouldProcess') { $hasSP = $true }
                }
            }
            $hasSP | Should -BeFalse -Because 'check-uwp-apps.ps1 is read-only; do not promote to mutator without a sibling restore script'
        }

        It 'has -Sort with valid values Name/Publisher/Status' {
            $sortParam = $script:Ast.ParamBlock.Parameters |
                Where-Object { $_.Name.VariablePath.UserPath -eq 'Sort' }
            $sortParam | Should -Not -BeNullOrEmpty
            $validate = $sortParam.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
            $validate | Should -Not -BeNullOrEmpty
            $values = $validate.PositionalArguments | ForEach-Object {
                if ($_.PSObject.Properties['Value']) { $_.Value }
            }
            $values | Should -Contain 'Name'
            $values | Should -Contain 'Publisher'
            $values | Should -Contain 'Status'
        }

        It 'has -OnlyDebloatCandidates switch' {
            $names = $script:Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
            $names | Should -Contain 'OnlyDebloatCandidates'
        }

        It 'has -AsObject switch (for pipeline consumers)' {
            $names = $script:Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
            $names | Should -Contain 'AsObject'
        }
    }

    Context 'Comment-based help' {
        It 'has SYNOPSIS / DESCRIPTION / EXAMPLE (≥3) / NOTES' {
            $h = Test-ToolkitCommentBasedHelp -Path $script:Target
            $h.HasSynopsis | Should -BeTrue
            $h.HasDescription | Should -BeTrue
            $h.HasNotes | Should -BeTrue
            $exCount = ([regex]::Matches($script:Content, '\.EXAMPLE')).Count
            $exCount | Should -BeGreaterOrEqual 3 -Because 'AsObject + OnlyDebloatCandidates + default each warrant an example'
        }

        It 'cites Microsoft Learn docs for Get-AppxPackage' {
            $script:Content | Should -Match 'learn\.microsoft\.com.*Get-AppxPackage'
        }
    }

    Context 'Pairs with the shared debloat catalog (audit-then-decide UX)' {
        It 'reads Get-ToolkitDebloatCatalog and Get-ToolkitDebloatNeverRemove' {
            # The list lives in lib/debloat-catalog.ps1. Parsing
            # debloat.ps1 would drift the moment that script stopped
            # embedding the array literal.
            $script:Content | Should -Match 'debloat-catalog\.ps1'
            $script:Content | Should -Match 'Get-ToolkitDebloatCatalog'
            $script:Content | Should -Match 'Get-ToolkitDebloatNeverRemove'
        }
    }
}
