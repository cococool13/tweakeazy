#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract tests for lib/toolkit-state.ps1.

.DESCRIPTION
    AST-driven tests that run on any platform. Validate:
      - Public helper functions are present and exported (or accessible
        via dot-source).
      - Mutating helpers (Set-Toolkit*) carry SupportsShouldProcess.
      - In-memory helpers (Set-ToolkitMapValue) have explicit
        suppression so future analyzer runs don't re-flag them.

    Runtime tests (actual registry / service writes) are tagged
    'WindowsOnly' and live in tests/integration/. This file is
    static-only and safe on macOS / Linux CI runners.

.NOTES
    Test rig: tests/_common.ps1 provides shared helpers.
#>

BeforeDiscovery {
    # Pester v5 quirk: -ForEach iterations must be expanded at DISCOVERY
    # time, not run time. Loop variables defined inside Describe/Context
    # don't survive into It blocks.
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:Mutators = @(
        @{ Name = 'Set-ToolkitRegistryValue' }
        @{ Name = 'Set-ToolkitServiceStartMode' }
        @{ Name = 'Set-ToolkitDnsServers' }
    )
    $script:ExpectedPublic = @(
        @{ Name = 'Get-ToolkitManifestPath' }
        @{ Name = 'Get-ToolkitLogRoot' }
        @{ Name = 'Get-ToolkitLogFile' }
        @{ Name = 'Write-ToolkitLog' }
        @{ Name = 'Write-ToolkitScriptStart' }
        @{ Name = 'Initialize-ToolkitState' }
        @{ Name = 'Get-ToolkitState' }
        @{ Name = 'Save-ToolkitState' }
        @{ Name = 'Set-ToolkitRegistryValue' }
        @{ Name = 'Restore-ToolkitRegistryValue' }
        @{ Name = 'Set-ToolkitServiceStartMode' }
        @{ Name = 'Restore-ToolkitServiceStartMode' }
        @{ Name = 'Set-ToolkitDnsServers' }
        @{ Name = 'Add-ToolkitStepResult' }
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:Target = Get-ToolkitScriptPath 'lib/toolkit-state.ps1'
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Target, [ref]$null, [ref]$null
    )
    $script:Functions = $script:Ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)
    $script:FunctionNames = @($script:Functions | ForEach-Object Name)
}

Describe 'lib/toolkit-state.ps1 — surface contract' {

    Context 'File health' {
        It 'parses without errors' {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:Target, [ref]$tokens, [ref]$errors
            )
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'Mutating helpers declare SupportsShouldProcess (PSSA #15)' {
        It '<Name> carries [CmdletBinding(SupportsShouldProcess)]' -ForEach $script:Mutators {
            $fn = $script:Functions | Where-Object Name -EQ $Name
            $fn | Should -Not -BeNullOrEmpty -Because 'the function must exist for this test to be meaningful'

            $hasShouldProcess = $false
            $cmdletBinding = $fn.Body.ParamBlock.Attributes |
                Where-Object { $_.TypeName.Name -eq 'CmdletBinding' } |
                Select-Object -First 1
            if ($cmdletBinding) {
                foreach ($named in $cmdletBinding.NamedArguments) {
                    if ($named.ArgumentName -eq 'SupportsShouldProcess') {
                        $hasShouldProcess = $true
                    }
                }
            }
            $hasShouldProcess | Should -BeTrue -Because 'every mutator must support -WhatIf / -Confirm per CLAUDE.md quality bar'
        }

        It 'Set-ToolkitMapValue has analyzer suppression (in-memory only)' {
            $fn = $script:Functions | Where-Object Name -EQ 'Set-ToolkitMapValue'
            $fn | Should -Not -BeNullOrEmpty
            $hasSuppression = $false
            foreach ($attr in $fn.Body.ParamBlock.Attributes) {
                if ($attr.TypeName.Name -match 'SuppressMessage') {
                    foreach ($arg in $attr.PositionalArguments) {
                        if ($arg.Extent.Text -match 'PSUseShouldProcessForStateChangingFunctions') {
                            $hasSuppression = $true
                        }
                    }
                }
            }
            $hasSuppression | Should -BeTrue
        }
    }

    Context 'Public surface' {
        It 'exports <Name>' -ForEach $script:ExpectedPublic {
            $script:FunctionNames | Should -Contain $Name
        }
    }

    Context 'Write-ToolkitLog produces JSONL with required fields' {
        BeforeAll {
            . $script:Target
            # Force a fresh per-test log path via reflection of script-scope var.
            $tempLog = Join-Path ([System.IO.Path]::GetTempPath()) ("toolkit-test-{0}.log" -f [Guid]::NewGuid())
            Set-Variable -Scope script -Name 'ToolkitLogFile' -Value $tempLog
            $script:TempLog = $tempLog
        }

        AfterAll {
            if (Test-Path -LiteralPath $script:TempLog) {
                Remove-Item -LiteralPath $script:TempLog -Force -ErrorAction SilentlyContinue
            }
        }

        It 'appends a JSON line with ts/level/msg' {
            Write-ToolkitLog 'pester-test-1'
            Test-Path -LiteralPath $script:TempLog | Should -BeTrue
            $lines = @(Get-Content -LiteralPath $script:TempLog | Where-Object { $_.Trim() })
            $lines.Count | Should -BeGreaterOrEqual 1
            $obj = $lines[-1] | ConvertFrom-Json
            $obj.ts | Should -Not -BeNullOrEmpty
            $obj.level | Should -Be 'info'
            $obj.msg | Should -Be 'pester-test-1'
        }

        It 'includes optional Data as a nested object' {
            Write-ToolkitLog 'pester-test-2' -Data @{ key = 'value'; n = 42 }
            $lines = @(Get-Content -LiteralPath $script:TempLog | Where-Object { $_.Trim() })
            $obj = $lines[-1] | ConvertFrom-Json
            $obj.data.key | Should -Be 'value'
            $obj.data.n | Should -Be 42
        }

        It "honors -Level 'warn' / 'error'" {
            Write-ToolkitLog 'warn-line' -Level 'warn'
            Write-ToolkitLog 'error-line' -Level 'error'
            $lines = @(Get-Content -LiteralPath $script:TempLog | Where-Object { $_.Trim() })
            ($lines[-2] | ConvertFrom-Json).level | Should -Be 'warn'
            ($lines[-1] | ConvertFrom-Json).level | Should -Be 'error'
        }

        It 'rejects invalid -Level values at param-bind time' {
            { Write-ToolkitLog 'x' -Level 'fatal' } | Should -Throw
        }
    }
}

Describe 'lib/toolkit-state.ps1 — behavioral coverage push' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '..' '..' 'lib' 'toolkit-state.ps1')
    }

    Context 'Path resolvers (Get-ToolkitManifestPath, LogRoot, LogFile)' {
        It 'Get-ToolkitManifestPath returns a non-empty path under the state root' {
            $p = Get-ToolkitManifestPath
            $p | Should -Not -BeNullOrEmpty
            $p | Should -Match 'manifest\.json$'
        }
        It 'Get-ToolkitLogRoot returns a non-empty path under the toolkit data root' {
            $r = Get-ToolkitLogRoot
            $r | Should -Not -BeNullOrEmpty
            $r | Should -Match 'logs$'
        }
        It 'Get-ToolkitLogFile returns a path inside Get-ToolkitLogRoot' {
            $f = Get-ToolkitLogFile
            $root = Get-ToolkitLogRoot
            # The .log file should sit directly under the log root.
            (Split-Path -Parent $f) | Should -Be $root
            $f | Should -Match '\.log$'
        }
    }

    Context 'Map helpers — hashtable AND PSCustomObject paths' {

        It 'Test-ToolkitMapHasKey returns true/false on a hashtable' {
            $ht = @{ a = 1; b = 2 }
            Test-ToolkitMapHasKey -Map $ht -Key 'a' | Should -BeTrue
            Test-ToolkitMapHasKey -Map $ht -Key 'missing' | Should -BeFalse
        }

        It 'Test-ToolkitMapHasKey returns true/false on a PSCustomObject' {
            $obj = [PSCustomObject]@{ x = 'one'; y = 'two' }
            Test-ToolkitMapHasKey -Map $obj -Key 'x' | Should -BeTrue
            Test-ToolkitMapHasKey -Map $obj -Key 'missing' | Should -BeFalse
        }

        It 'Get-ToolkitMapValue returns the value from a hashtable' {
            $ht = @{ a = 'alpha'; b = 'beta' }
            Get-ToolkitMapValue -Map $ht -Key 'b' | Should -Be 'beta'
        }

        It 'Get-ToolkitMapValue returns the value from a PSCustomObject' {
            $obj = [PSCustomObject]@{ x = 42; y = 99 }
            Get-ToolkitMapValue -Map $obj -Key 'x' | Should -Be 42
        }

        It 'Set-ToolkitMapValue mutates an existing hashtable key' {
            $ht = @{ a = 1 }
            Set-ToolkitMapValue -Map $ht -Key 'a' -Value 5
            $ht['a'] | Should -Be 5
        }

        It 'Set-ToolkitMapValue adds a new hashtable key' {
            $ht = @{ a = 1 }
            Set-ToolkitMapValue -Map $ht -Key 'b' -Value 7
            $ht['b'] | Should -Be 7
        }

        It 'Set-ToolkitMapValue mutates an existing PSCustomObject property' {
            $obj = [PSCustomObject]@{ x = 'old' }
            Set-ToolkitMapValue -Map $obj -Key 'x' -Value 'new'
            $obj.x | Should -Be 'new'
        }

        It 'Set-ToolkitMapValue adds a new PSCustomObject property via Add-Member' {
            $obj = [PSCustomObject]@{ x = 1 }
            Set-ToolkitMapValue -Map $obj -Key 'y' -Value 'fresh'
            $obj.y | Should -Be 'fresh'
        }
    }

    Context 'Test-ToolkitCommand — Get-Command wrapper' {
        It 'returns $true for a built-in cmdlet that exists in scope' {
            Test-ToolkitCommand -Name 'Get-Date' | Should -BeTrue
        }
        It 'returns $false for a definitely-missing command' {
            Test-ToolkitCommand -Name 'Definitely-Not-A-Real-Cmdlet-XYZ123' | Should -BeFalse
        }
    }

    Context 'DNS pure-data helpers' {

        It 'Normalize-ToolkitDnsAddressFamily normalizes all known forms to IPv4' {
            Normalize-ToolkitDnsAddressFamily -AddressFamily 'IPv4'         | Should -Be 'IPv4'
            Normalize-ToolkitDnsAddressFamily -AddressFamily 2              | Should -Be 'IPv4'
            Normalize-ToolkitDnsAddressFamily -AddressFamily 'InterNetwork' | Should -Be 'IPv4'
        }

        It 'Normalize-ToolkitDnsAddressFamily normalizes all known forms to IPv6' {
            Normalize-ToolkitDnsAddressFamily -AddressFamily 'IPv6'           | Should -Be 'IPv6'
            Normalize-ToolkitDnsAddressFamily -AddressFamily 23               | Should -Be 'IPv6'
            Normalize-ToolkitDnsAddressFamily -AddressFamily 'InterNetworkV6' | Should -Be 'IPv6'
        }

        It 'Normalize-ToolkitDnsAddressFamily returns $null on unrecognized input' {
            Normalize-ToolkitDnsAddressFamily -AddressFamily 'IPv5' | Should -BeNullOrEmpty
            Normalize-ToolkitDnsAddressFamily -AddressFamily 'bogus' | Should -BeNullOrEmpty
        }

        It 'Get-ToolkitDnsAddressFamily classifies real DNS server addresses' {
            Get-ToolkitDnsAddressFamily -Address '1.1.1.1'       | Should -Be 'IPv4'
            Get-ToolkitDnsAddressFamily -Address '8.8.8.8'       | Should -Be 'IPv4'
            Get-ToolkitDnsAddressFamily -Address '2606:4700::1111' | Should -Be 'IPv6'
            Get-ToolkitDnsAddressFamily -Address '2001:4860:4860::8888' | Should -Be 'IPv6'
        }

        It 'Get-ToolkitDnsAddressFamily returns $null on garbage input' {
            Get-ToolkitDnsAddressFamily -Address 'not-an-address' | Should -BeNullOrEmpty
            Get-ToolkitDnsAddressFamily -Address '999.999.999.999' | Should -BeNullOrEmpty
        }

        It 'Group-ToolkitDnsServersByFamily splits a mixed list into v4/v6 buckets' {
            $g = Group-ToolkitDnsServersByFamily -ServerAddresses @('1.1.1.1', '2606:4700::1111', '8.8.8.8')
            @($g['IPv4']) | Should -Be @('1.1.1.1', '8.8.8.8')
            @($g['IPv6']) | Should -Be @('2606:4700::1111')
        }

        It 'Group-ToolkitDnsServersByFamily throws on an invalid address inside the list' {
            { Group-ToolkitDnsServersByFamily -ServerAddresses @('1.1.1.1', 'garbage', '8.8.8.8') } |
                Should -Throw '*Invalid DNS server address*'
        }

        It 'Group-ToolkitDnsServersByFamily throws when no addresses provided' {
            { Group-ToolkitDnsServersByFamily -ServerAddresses @() } |
                Should -Throw '*No DNS server addresses provided*'
        }

        It 'Group-ToolkitDnsServersByFamily filters out null / empty entries' {
            $g = Group-ToolkitDnsServersByFamily -ServerAddresses @('', '1.1.1.1', $null)
            @($g['IPv4']) | Should -Be @('1.1.1.1')
        }
    }

    Context 'Save-ToolkitState / Get-ToolkitState / Initialize-ToolkitState round-trip' {

        BeforeEach {
            # Per-test isolated state file. Override the script:
            # ToolkitStateRoot + ToolkitStateFile so writes don't pollute
            # the dev box's real state dir.
            $script:OrigStateRoot = $script:ToolkitStateRoot
            $script:OrigStateFile = $script:ToolkitStateFile
            $script:TmpStateDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ts-state-" + [guid]::NewGuid())
            New-Item -ItemType Directory -Path $script:TmpStateDir -Force | Out-Null
            $script:ToolkitStateRoot = $script:TmpStateDir
            $script:ToolkitStateFile = Join-Path $script:TmpStateDir 'manifest.json'
            # Force a fresh in-memory state per test.
            Set-Variable -Scope script -Name 'ToolkitState' -Value $null
            # Mock the heavy machine-profile probe (Windows-only CIM).
            Mock Get-ToolkitMachineProfile {
                [PSCustomObject]@{
                    generatedAt = (Get-Date).ToString('o')
                    systemName = 'TEST-PC'
                    isLaptop = $false
                    powerState = 'Desktop / AC'
                    gpuCount = 1
                    isHybridGraphics = $false
                    partOfDomain = $false
                }
            }
        }

        AfterEach {
            $script:ToolkitStateRoot = $script:OrigStateRoot
            $script:ToolkitStateFile = $script:OrigStateFile
            Set-Variable -Scope script -Name 'ToolkitState' -Value $null
            if ($script:TmpStateDir -and (Test-Path $script:TmpStateDir)) {
                Remove-Item -LiteralPath $script:TmpStateDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Initialize-ToolkitState creates a manifest with all required top-level keys' {
            $state = Initialize-ToolkitState 6>$null
            $state | Should -Not -BeNullOrEmpty
            $state.version | Should -Not -BeNullOrEmpty
            $state.context.systemName | Should -Be 'TEST-PC'
            # Pester pipeline unwraps the empty array → $null for the
            # bare-element BeOfType assertion. Wrap in a single-element
            # outer array; an empty .notes still has a .Count property.
            (, $state.notes).Count | Should -Be 1
            $state.registry | Should -BeOfType [hashtable]
            $state.services | Should -BeOfType [hashtable]
            $state.dns.captured | Should -BeFalse
            $state.steps | Should -BeOfType [hashtable]
            # File should now exist on disk
            Test-Path $script:ToolkitStateFile | Should -BeTrue
        }

        It 'Initialize-ToolkitState preserves an existing manifest (no clobber)' {
            $first = Initialize-ToolkitState 6>$null
            # createdAt is a string when freshly created (just got .ToString('o')).
            # After save → load round-trip ConvertFrom-Json parses ISO-8601
            # strings into DateTime. Compare via .ToString('o') so the
            # round-trip type change doesn't blow the assertion.
            $originalIso = ([datetime]$first.createdAt).ToString('o')
            Start-Sleep -Milliseconds 10
            Set-Variable -Scope script -Name 'ToolkitState' -Value $null
            $second = Initialize-ToolkitState 6>$null
            ([datetime]$second.createdAt).ToString('o') | Should -Be $originalIso
        }

        It 'Get-ToolkitState returns $null when no manifest has been saved' {
            Get-ToolkitState | Should -BeNullOrEmpty
        }

        It 'Get-ToolkitState returns the in-memory state after Save-ToolkitState' {
            Initialize-ToolkitState 6>$null | Out-Null
            $loaded = Get-ToolkitState
            $loaded.context.systemName | Should -Be 'TEST-PC'
        }

        It 'Save-ToolkitState updates the lastUpdated timestamp' {
            $s = Initialize-ToolkitState 6>$null
            $before = $s.lastUpdated
            Start-Sleep -Milliseconds 10
            Save-ToolkitState
            $s.lastUpdated | Should -Not -Be $before
        }
    }

    Context 'Add-ToolkitNote / Add-ToolkitStepResult — state-tracking helpers' {

        BeforeEach {
            $script:OrigStateRoot = $script:ToolkitStateRoot
            $script:OrigStateFile = $script:ToolkitStateFile
            $script:TmpStateDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ts-notes-" + [guid]::NewGuid())
            New-Item -ItemType Directory -Path $script:TmpStateDir -Force | Out-Null
            $script:ToolkitStateRoot = $script:TmpStateDir
            $script:ToolkitStateFile = Join-Path $script:TmpStateDir 'manifest.json'
            Set-Variable -Scope script -Name 'ToolkitState' -Value $null
            Mock Get-ToolkitMachineProfile {
                [PSCustomObject]@{ systemName = 'TEST-PC'; isLaptop = $false; gpuCount = 1 }
            }
            Initialize-ToolkitState 6>$null | Out-Null
        }

        AfterEach {
            $script:ToolkitStateRoot = $script:OrigStateRoot
            $script:ToolkitStateFile = $script:OrigStateFile
            Set-Variable -Scope script -Name 'ToolkitState' -Value $null
            if ($script:TmpStateDir -and (Test-Path $script:TmpStateDir)) {
                Remove-Item -LiteralPath $script:TmpStateDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Add-ToolkitNote appends to the notes array' {
            Add-ToolkitNote -Message 'first note'
            Add-ToolkitNote -Message 'second note'
            $state = Get-ToolkitState
            $state.notes.Count | Should -Be 2
            $state.notes[0] | Should -Be 'first note'
        }

        It 'Add-ToolkitStepResult registers a step with tier/status/reason/updatedAt' {
            Add-ToolkitStepResult -Key 'test-step' -Tier 'Safe' -Status 'applied' -Reason 'unit test'
            $state = Get-ToolkitState
            $entry = Get-ToolkitMapValue -Map $state.steps -Key 'test-step'
            $entry.tier | Should -Be 'Safe'
            $entry.status | Should -Be 'applied'
            $entry.reason | Should -Be 'unit test'
            $entry.updatedAt | Should -Not -BeNullOrEmpty
        }

        It 'Add-ToolkitStepResult overwrites an existing step on re-call' {
            Add-ToolkitStepResult -Key 'step1' -Tier 'Safe' -Status 'applied' -Reason 'first'
            Add-ToolkitStepResult -Key 'step1' -Tier 'Advanced' -Status 'reverted' -Reason 'second'
            $state = Get-ToolkitState
            $entry = Get-ToolkitMapValue -Map $state.steps -Key 'step1'
            $entry.tier | Should -Be 'Advanced'
            $entry.status | Should -Be 'reverted'
            $entry.reason | Should -Be 'second'
        }
    }
}

