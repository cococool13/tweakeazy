#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    HwSchMode is one registry value and one manifest id: reg:HwSchMode.

.DESCRIPTION
    Capture-once in Set-ToolkitRegistryValue is per id. Vendor ids
    (nv:HwSchMode, amd:HwSchMode, intel:HwSchMode) store the post-apply
    value 2 as the original when Apply or enable-hags already wrote 2.
    Vendor revert then writes 2 back.

    Every Set-ToolkitRegistryValue / Set-TrackedRegistry call that names
    HwSchMode must pass -Id reg:HwSchMode. Vendor revert scripts must
    skip the retired ids. verify-tweaks.ps1 must note the single id.

.NOTES
    Parser-only. Runs anywhere the repo is checked out.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')

    function Get-StaticParameterLiteral {
        param(
            $CommandAst,
            [string]$ParameterName
        )
        $elements = @($CommandAst.CommandElements)
        for ($i = 0; $i -lt $elements.Count; $i++) {
            $elem = $elements[$i]
            if ($elem -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                continue
            }
            if ($elem.ParameterName -ne $ParameterName) {
                continue
            }
            $argument = $null
            if ($null -ne $elem.Argument) {
                $argument = $elem.Argument
            } elseif (($i + 1) -lt $elements.Count) {
                $argument = $elements[$i + 1]
            }
            $isLiteral = $argument -is [System.Management.Automation.Language.StringConstantExpressionAst]
            $value = $null
            if ($isLiteral) {
                $value = $argument.Value
            }
            return [PSCustomObject]@{
                Present = $true
                Literal = $isLiteral
                Value = $value
            }
        }
        return [PSCustomObject]@{
            Present = $false
            Literal = $false
            Value = $null
        }
    }

    $expectedWriters = @(
        '5 registry tweaks/individual/disable-hags.ps1'
        '5 registry tweaks/individual/enable-hags.ps1'
        '6 gpu/amd/configure-amd.ps1'
        '6 gpu/intel/configure-intel.ps1'
        '6 gpu/nvidia/configure-nvidia.ps1'
        'APPLY-EVERYTHING.ps1'
    )
    $retiredIds = @('nv:HwSchMode', 'amd:HwSchMode', 'intel:HwSchMode')

    $calls = @()
    $files = Get-ChildItem -LiteralPath $script:RepoRoot -Filter '*.ps1' -Recurse -File
    foreach ($file in $files) {
        $rel = $file.FullName.Substring($script:RepoRoot.Length).TrimStart(([char[]]@([char]92, [char]47))) -replace '\\', '/'
        if ($rel -like 'tests/*') { continue }
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName, [ref]$null, [ref]$parseErrors
        )
        if ($parseErrors) {
            $calls += [PSCustomObject]@{
                Path = $rel
                Command = '<parse>'
                Id = $null
                Name = $null
                Literal = $false
                Error = ($parseErrors | ForEach-Object { $_.ToString() }) -join '; '
            }
            continue
        }
        $commands = $ast.FindAll({
                param($node)
                if ($node -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
                $commandName = $node.GetCommandName()
                ($commandName -eq 'Set-ToolkitRegistryValue') -or ($commandName -eq 'Set-TrackedRegistry')
            }, $true)
        foreach ($command in $commands) {
            $nameArg = Get-StaticParameterLiteral -CommandAst $command -ParameterName 'Name'
            $idArg = Get-StaticParameterLiteral -CommandAst $command -ParameterName 'Id'
            $mentionsHwSch = $false
            if ($nameArg.Present -and $nameArg.Value -eq 'HwSchMode') { $mentionsHwSch = $true }
            if ($idArg.Present -and $idArg.Value -like '*:HwSchMode') { $mentionsHwSch = $true }
            if (-not $mentionsHwSch) { continue }
            $calls += [PSCustomObject]@{
                Path = $rel
                Command = $command.GetCommandName()
                Id = $idArg.Value
                Name = $nameArg.Value
                Literal = ($idArg.Literal -and $nameArg.Literal)
                Error = $null
            }
        }
    }

    $script:HwSchCalls = @($calls)
    $script:ExpectedHwSchWriters = $expectedWriters
    $script:RetiredHwSchIds = $retiredIds
}

Describe 'Invariant: HwSchMode uses a single manifest id' {
    It 'parses every writer and finds the known call sites' {
        $broken = @($script:HwSchCalls | Where-Object { $_.Error })
        @($broken).Count | Should -Be 0
        $paths = @($script:HwSchCalls | ForEach-Object { $_.Path } | Sort-Object -Unique)
        ($paths -join [Environment]::NewLine) | Should -Be ($script:ExpectedHwSchWriters -join [Environment]::NewLine)
    }

    It 'writes and tracks HwSchMode only as reg:HwSchMode' {
        $script:HwSchCalls.Count | Should -BeGreaterThan 0
        foreach ($call in $script:HwSchCalls) {
            $call.Literal | Should -BeTrue -Because "$($call.Path) must pass literal -Id and -Name"
            $call.Name | Should -Be 'HwSchMode' -Because $call.Path
            $call.Id | Should -Be 'reg:HwSchMode' -Because "$($call.Path) ($($call.Command))"
        }
    }

    It 'does not pass a vendor HwSchMode id to any writer' {
        $vendor = @($script:HwSchCalls | Where-Object { $script:RetiredHwSchIds -contains $_.Id })
        $vendor | Should -BeNullOrEmpty
    }

    It 'vendor revert skips the retired id instead of restoring post-apply value 2' {
        $pairs = @(
            @{ Path = '6 gpu/nvidia/revert-nvidia.ps1'; Id = 'nv:HwSchMode' }
            @{ Path = '6 gpu/amd/revert-amd.ps1'; Id = 'amd:HwSchMode' }
            @{ Path = '6 gpu/intel/revert-intel.ps1'; Id = 'intel:HwSchMode' }
        )
        foreach ($pair in $pairs) {
            $full = Join-Path $script:RepoRoot $pair.Path
            $text = Get-Content -LiteralPath $full -Raw
            $text | Should -Match ([regex]::Escape("if (`$id -eq `"$($pair.Id)`")"))
            $text | Should -Match 'reg:HwSchMode only'
            $quoted = 'Restore-ToolkitRegistryValue -Id "{0}"' -f $pair.Id
            $text | Should -Not -Match ([regex]::Escape($quoted))
        }
    }

    It 'verify-tweaks notes that rollback is reg:HwSchMode only' {
        $full = Join-Path $script:RepoRoot '10 verify/verify-tweaks.ps1'
        $text = Get-Content -LiteralPath $full -Raw
        $text | Should -Match 'HwSchMode rollback id is reg:HwSchMode only'
        $text | Should -Match '\} "reg:HwSchMode"'
        foreach ($retired in $script:RetiredHwSchIds) {
            $text | Should -Match ([regex]::Escape($retired))
        }
    }
}
