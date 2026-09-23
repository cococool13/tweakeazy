@echo off
:: ============================================================
:: Shared UI Helper for Batch Scripts
:: Windows 11 Gaming Optimization Guide
:: ============================================================
:: Labels in this file are not visible to other scripts.
:: `call :ui_header` from a caller looks up :ui_header in the
:: CALLER, so these routines never run. Pass the routine name:
::
::   call "%~dp0..\lib\ui-helpers.bat" ui_header "Title" "Subtitle"
::   call "%~dp0..\lib\ui-helpers.bat" ui_admin_check
::   if errorlevel 1 exit /b 1
::   call "%~dp0..\lib\ui-helpers.bat" ui_step_ok "Step description"
::   call "%~dp0..\lib\ui-helpers.bat" ui_summary "Done" "Revert hint"
::
:: No arguments: define color and counter variables, then return.
:: ui_header resets the OK / FAIL / SKIP tally.
:: ui_admin_check returns 1 when not elevated. It does not stop
:: the caller. The caller must exit when errorlevel is 1 or higher.
:: ============================================================

:: Enable ANSI escape sequences (Windows 10 1511+)
:: The escape character is generated via a self-modifying prompt trick.
:: Cached for later dispatches in the same cmd session.
if defined UI_COLORS_READY goto :ui_colors_done
for /f %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"

:: Color codes (ANSI SGR sequences)
set "C_OK=%ESC%[92m"
set "C_ERR=%ESC%[91m"
set "C_WARN=%ESC%[93m"
set "C_HEAD=%ESC%[96m"
set "C_DIM=%ESC%[90m"
set "C_WHITE=%ESC%[97m"
set "C_R=%ESC%[0m"

:: Bold variants
set "C_BOK=%ESC%[1;92m"
set "C_BERR=%ESC%[1;91m"
set "C_BWARN=%ESC%[1;93m"
set "C_BHEAD=%ESC%[1;96m"
set "UI_COLORS_READY=1"

:ui_colors_done

:: ---- Counters (kept across dispatches; ui_header resets them) ----
if not defined UI_OK set /a UI_OK=0
if not defined UI_FAIL set /a UI_FAIL=0
if not defined UI_SKIP set /a UI_SKIP=0

:: No argument: color and counter init only.
if "%~1"=="" goto :eof

set "UI_CMD=%~1"
shift

if /I "%UI_CMD%"=="ui_header" goto :ui_header
if /I "%UI_CMD%"=="ui_section" goto :ui_section
if /I "%UI_CMD%"=="ui_admin_check" goto :ui_admin_check
if /I "%UI_CMD%"=="ui_step_ok" goto :ui_step_ok
if /I "%UI_CMD%"=="ui_step_fail" goto :ui_step_fail
if /I "%UI_CMD%"=="ui_step_skip" goto :ui_step_skip
if /I "%UI_CMD%"=="ui_summary" goto :ui_summary
if /I "%UI_CMD%"=="ui_confirm" goto :ui_confirm

echo   %C_ERR%[ERROR] Unknown UI helper command: %UI_CMD%%C_R%
exit /b 1

:: ============================================================
:: ROUTINES (reached only by the dispatcher above)
:: Argument 1 was the routine name and has been shifted away.
:: ============================================================

:ui_header
:: Usage: call ui-helpers.bat ui_header "Title" ["Subtitle"]
:: A new header starts a new tally so a second run in the same
:: cmd window does not add to the previous summary.
set /a UI_OK=0
set /a UI_FAIL=0
set /a UI_SKIP=0
echo.
echo   %C_HEAD%============================================================%C_R%
echo     %C_HEAD%%~1%C_R%
if not "%~2"=="" echo     %C_HEAD%%~2%C_R%
echo   %C_HEAD%============================================================%C_R%
echo.
goto :eof

:ui_section
:: Usage: call ui-helpers.bat ui_section "Section Title"
echo.
echo   %C_DIM%------------------------------------------------------------%C_R%
echo     %C_WHITE%%~1%C_R%
echo   %C_DIM%------------------------------------------------------------%C_R%
echo.
goto :eof

:ui_admin_check
:: Usage: call ui-helpers.bat ui_admin_check
:: exit /b is outside the parentheses so the caller's errorlevel is 1.
net session >nul 2>&1
if %errorlevel% equ 0 goto :eof
echo.
echo   %C_ERR%[ERROR] This script must be run as Administrator.%C_R%
echo   %C_ERR%Right-click and select "Run as administrator".%C_R%
echo.
pause
exit /b 1

:ui_step_ok
:: Usage: call ui-helpers.bat ui_step_ok "Step description"
set /a UI_OK+=1
echo     %~1  %C_OK%[OK]%C_R%
goto :eof

:ui_step_fail
:: Usage: call ui-helpers.bat ui_step_fail "Step description"
set /a UI_FAIL+=1
echo     %~1  %C_ERR%[FAIL]%C_R%
goto :eof

:ui_step_skip
:: Usage: call ui-helpers.bat ui_step_skip "Step description"
set /a UI_SKIP+=1
echo     %~1  %C_WARN%[SKIP]%C_R%
goto :eof

:ui_summary
:: Usage: call ui-helpers.bat ui_summary "Done message" ["Revert hint"]
echo.
echo   %C_HEAD%============================================================%C_R%
if %UI_FAIL% equ 0 (
    echo     %C_OK%[DONE] %~1%C_R%
) else (
    echo     %C_WARN%[DONE] %~1 (with errors)%C_R%
)
echo.
echo     %C_OK%Succeeded: %UI_OK%%C_R%
if %UI_SKIP% gtr 0 echo     %C_WARN%Skipped:   %UI_SKIP%%C_R%
if %UI_FAIL% gtr 0 echo     %C_ERR%Failed:    %UI_FAIL%%C_R%
if not "%~2"=="" (
    echo.
    echo     %C_DIM%To revert: %~2%C_R%
)
echo   %C_HEAD%============================================================%C_R%
echo.
goto :eof

:ui_confirm
:: Usage: call ui-helpers.bat ui_confirm
echo.
echo     %C_WARN%Press Ctrl+C to cancel, or%C_R%
pause >nul 2>&1
echo     (continuing...)
goto :eof
