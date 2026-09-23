@echo off
:: ============================================================
:: Revert Network Optimization (Restore Defaults)
:: Windows 11 Gaming Optimization Guide
:: ============================================================

:: Load UI helpers (ANSI colors)
call "%~dp0..\lib\ui-helpers.bat"

call :ui_header "Reverting Network Settings to Defaults"
call :ui_admin_check

netsh int tcp set global autotuninglevel=normal >nul 2>&1
call :ui_step_ok "[1/8] TCP Auto-Tuning restored to normal"

netsh int tcp set global rss=enabled >nul 2>&1
call :ui_step_ok "[2/8] RSS kept enabled (default)"

netsh int tcp set global dca=disabled >nul 2>&1
call :ui_step_ok "[3/8] Direct Cache Access restored to default"

:: Inbox default is disabled. Apply sets the same value. Do not turn timestamps on.
netsh int tcp set global timestamps=disabled >nul 2>&1
call :ui_step_ok "[4/8] TCP Timestamps left disabled (Windows default)"

powershell -Command "Get-NetAdapter | ForEach-Object { Set-NetAdapterAdvancedProperty -Name $_.Name -DisplayName 'Large Send Offload*' -DisplayValue 'Enabled' -ErrorAction SilentlyContinue }" >nul 2>&1
call :ui_step_ok "[5/8] Large Send Offload re-enabled"

powershell -Command ^
  "$interfaces = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'; " ^
  "Get-ChildItem $interfaces | ForEach-Object { " ^
  "  Remove-ItemProperty $_.PSPath -Name 'TcpAckFrequency' -ErrorAction SilentlyContinue; " ^
  "  Remove-ItemProperty $_.PSPath -Name 'TCPNoDelay' -ErrorAction SilentlyContinue; " ^
  "}"
call :ui_step_ok "[6/8] Nagle's Algorithm re-enabled"

powershell -Command ^
  "Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | ForEach-Object { " ^
  "  Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue; " ^
  "}"
call :ui_step_ok "[7/8] DNS reset to automatic (DHCP)"

ipconfig /flushdns >nul 2>&1
call :ui_step_ok "[8/8] DNS cache flushed"

call :ui_summary "Network settings restored to defaults"
echo   %C_DIM%A reboot is recommended.%C_R%
echo.
pause
