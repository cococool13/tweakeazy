#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract for lib/ui-helpers.bat argument dispatch.

.DESCRIPTION
    call :ui_* from another .bat resolves the label in the caller.
    ui-helpers.bat must dispatch on its first argument, and the two
    batch wrappers must use that entry and stop when ui_admin_check
    returns non-zero. Parser-free text checks so the suite runs on
    Linux CI. Runtime of net session / netsh is Windows-only.

.NOTES
    # CROSS-PLATFORM-NOTE
    # Text scan only. No cmd.exe required.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')

    $script:UiBatCallers = @(
        @{ Caller = '7 network/revert-network.bat' }
        @{ Caller = '9 cleanup/chris-titus-winutil.bat' }
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    $script:HelperLines = @(Get-Content -LiteralPath (Get-ToolkitScriptPath 'lib/ui-helpers.bat'))
}

Describe 'lib/ui-helpers.bat — argument dispatch' {

    It 'routes every routine label from the first argument before :ui_header' {
        $headerAt = -1
        for ($i = 0; $i -lt $script:HelperLines.Count; $i++) {
            if ($script:HelperLines[$i] -eq ':ui_header') {
                $headerAt = $i
                break
            }
        }
        $headerAt | Should -BeGreaterThan 0

        $labels = @()
        for ($i = $headerAt; $i -lt $script:HelperLines.Count; $i++) {
            if ($script:HelperLines[$i] -match '^:(ui_[A-Za-z0-9_]+)$') {
                $labelName = $Matches[1]
                $labels += $labelName
            }
        }
        $labels.Count | Should -BeGreaterThan 3

        $preamble = $script:HelperLines[0..($headerAt - 1)]
        foreach ($labelName in $labels) {
            $arm = 'if /I "%UI_CMD%"=="' + $labelName + '" goto :' + $labelName
            ($preamble -contains $arm) | Should -BeTrue
        }
    }

    It 'returns before the routines only when no argument was passed' {
        $headerAt = -1
        for ($i = 0; $i -lt $script:HelperLines.Count; $i++) {
            if ($script:HelperLines[$i] -eq ':ui_header') {
                $headerAt = $i
                break
            }
        }
        $preamble = $script:HelperLines[0..($headerAt - 1)]
        $eofLines = @($preamble | Where-Object { $_ -match 'goto :eof' })
        $eofLines.Count | Should -Be 1
        $eofLines[0] | Should -Be 'if "%~1"=="" goto :eof'
    }

    It 'does not jump to a caller-supplied label' {
        $raw = $script:HelperLines -join "`n"
        $raw | Should -Not -Match 'goto\s+%'
    }

    It 'returns admin-check failure with exit /b outside a parenthesized block' {
        $start = -1
        for ($i = 0; $i -lt $script:HelperLines.Count; $i++) {
            if ($script:HelperLines[$i] -eq ':ui_admin_check') {
                $start = $i
                break
            }
        }
        $start | Should -BeGreaterThan 0
        $body = @()
        for ($i = $start + 1; $i -lt $script:HelperLines.Count; $i++) {
            if ($script:HelperLines[$i] -match '^:[A-Za-z0-9_]') { break }
            $body += $script:HelperLines[$i]
        }
        ($body -contains 'if %errorlevel% equ 0 goto :eof') | Should -BeTrue
        ($body -contains 'exit /b 1') | Should -BeTrue
    }
}

Describe 'batch callers reach ui-helpers.bat by argument' {

    It '<Caller> calls the helper with a routine name and stops after a failed admin check' -ForEach $script:UiBatCallers {
        $text = Get-Content -LiteralPath (Get-ToolkitScriptPath $Caller) -Raw
        $text | Should -Not -Match 'call\s+:ui_'
        $text | Should -Match 'ui-helpers\.bat" ui_header '
        $text | Should -Match 'ui-helpers\.bat" ui_admin_check\r?\nif errorlevel 1 exit /b 1'
    }

    It 'revert-network.bat still applies the default network writes itself' {
        $text = Get-Content -LiteralPath (Get-ToolkitScriptPath '7 network/revert-network.bat') -Raw
        $text | Should -Match 'netsh int tcp set global autotuninglevel=normal'
        $text | Should -Match 'TcpAckFrequency'
        $text | Should -Match 'TCPNoDelay'
        $text | Should -Match 'ResetServerAddresses'
        $text | Should -Not -Match 'Set-ToolkitRegistryValue'
        $text | Should -Not -Match 'toolkit-state'
    }
}
