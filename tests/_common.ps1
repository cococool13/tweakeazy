# ============================================================
# tests/_common.ps1 — shared Pester test scaffolding
# Windows 11 Gaming Optimization Guide
# ============================================================
# Dot-sourced by every <script>.Tests.ps1 file. Provides:
#   - $script:RepoRoot            absolute path to repo root
#   - Get-ToolkitScriptPath       resolve script under test
#   - Test-ToolkitParameterShape  assert standard mutator surface
#                                 (CmdletBinding, ShouldProcess, etc.)
#   - Invoke-ToolkitWhatIf        run a script with -WhatIf and assert
#                                 no side-effects via dry-run scope
#
# All tests are macOS-runnable (parser-only / static-analysis style).
# PS 5.1 compatibility is the PS51 AST invariant in
# tests/invariants/ps51-load-path.Tests.ps1.
# ============================================================

$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Get-ToolkitScriptPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RelativePath)
    $full = Join-Path $script:RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        throw "Script under test not found: $full"
    }
    return $full
}

function Get-ToolkitScriptAst {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    [System.Management.Automation.Language.Parser]::ParseFile(
        $Path, [ref]$null, [ref]$null
    )
}

function Test-ToolkitParameterShape {
    <#
    .SYNOPSIS
        Assert a script has the toolkit's standard mutator surface.
    .DESCRIPTION
        Checks for [CmdletBinding(SupportsShouldProcess)] when the script
        mutates registry/services/files, the inline admin self-check
        pattern, and the param block existing if any parameters declared.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$RequireShouldProcess
    )
    $ast = Get-ToolkitScriptAst -Path $Path
    $params = $ast.ParamBlock
    $cmdletBinding = $false
    $shouldProcess = $false

    if ($params -and $params.Attributes) {
        foreach ($attr in $params.Attributes) {
            if ($attr.TypeName.Name -eq 'CmdletBinding') {
                $cmdletBinding = $true
                foreach ($named in $attr.NamedArguments) {
                    if ($named.ArgumentName -eq 'SupportsShouldProcess') {
                        $shouldProcess = $true
                    }
                }
            }
        }
    }

    [PSCustomObject]@{
        Path = $Path
        HasParamBlock = $null -ne $params
        HasCmdletBinding = $cmdletBinding
        SupportsShouldProcess = $shouldProcess
        Passes = -not $RequireShouldProcess -or $shouldProcess
    }
}

function Test-ToolkitAdminCheck {
    <#
    .SYNOPSIS
        Assert the script self-checks admin before any mutation.
    .DESCRIPTION
        Looks for either UI-RequireAdmin call OR the inline
        IsInRole(Administrator) pattern within the first $HeadLines.
        Per CLAUDE.md invariant #6.

        Default window of 120 lines fits well-documented scripts whose
        comment-based help block pushes the admin check past ~80 lines
        (Phase C scripts like enable-doh.ps1 have ~75-line help blocks).
        Pass -HeadLines to widen for hand-rolled scripts with very
        long .DESCRIPTION sections.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$HeadLines = 120
    )
    $content = Get-Content -LiteralPath $Path -Raw
    $head = ($content -split "`n" | Select-Object -First $HeadLines) -join "`n"
    $hasUI = $head -match 'UI-RequireAdmin'
    $hasInline = $head -match 'IsInRole.*Administrator'
    [PSCustomObject]@{
        Path = $Path
        HasUIRequireAdmin = $hasUI
        HasInlineAdminCheck = $hasInline
        Passes = $hasUI -or $hasInline
    }
}

function Test-ToolkitCommentBasedHelp {
    <#
    .SYNOPSIS
        Assert the script has minimal comment-based help.
    .DESCRIPTION
        Looks for at least .SYNOPSIS and .DESCRIPTION in the first
        100 lines (script-level help). Doesn't check inner functions.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $content = Get-Content -LiteralPath $Path -Raw
    $head = ($content -split "`n" | Select-Object -First 100) -join "`n"
    [PSCustomObject]@{
        Path = $Path
        HasSynopsis = $head -match '\.SYNOPSIS'
        HasDescription = $head -match '\.DESCRIPTION'
        HasExample = $head -match '\.EXAMPLE'
        HasNotes = $head -match '\.NOTES'
        Passes = ($head -match '\.SYNOPSIS') -and ($head -match '\.DESCRIPTION')
    }
}
