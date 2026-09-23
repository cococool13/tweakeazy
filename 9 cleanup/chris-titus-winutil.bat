@echo off
:: ============================================================
:: Launch Chris Titus Tech Windows Utility (WinUtil)
:: Windows 11 Gaming Optimization Guide
:: ============================================================
:: WinUtil is a popular open-source Windows debloating and
:: optimization tool with a GUI. It can:
::   - Remove bloatware with checkboxes
::   - Install common programs (browsers, tools, etc.)
::   - Apply Windows tweaks via a simple interface
::   - Configure Windows Update policies
::
:: Source: https://github.com/ChrisTitusTech/winutil
:: ============================================================

:: Routines live in ui-helpers.bat. Pass the name; a label call
:: resolves in this file and would skip the admin check.
call "%~dp0..\lib\ui-helpers.bat" ui_header "Chris Titus Tech Windows Utility (WinUtil)"
call "%~dp0..\lib\ui-helpers.bat" ui_admin_check
if errorlevel 1 exit /b 1

set "WINUTIL_VERSION=26.04.21"
set "WINUTIL_URL=https://github.com/ChrisTitusTech/winutil/releases/download/%WINUTIL_VERSION%/winutil.ps1"
set "WINUTIL_SHA256=4c2595118edd3355065c1f449cd7e0092614dfc2552e8ac8e4ec4231a6d9a719"

echo   This will download and run WinUtil from GitHub release %WINUTIL_VERSION%.
echo   %C_DIM%Nothing is permanently installed — it runs once and exits.%C_R%
echo.
echo   %C_WHITE%Features:%C_R%
echo     %C_DIM%- Install common programs (browsers, 7-Zip, etc.)%C_R%
echo     %C_DIM%- Remove Windows bloatware via GUI checkboxes%C_R%
echo     %C_DIM%- Apply performance tweaks%C_R%
echo     %C_DIM%- Configure Windows Update%C_R%
echo.
echo   %C_DIM%Source: github.com/ChrisTitusTech/winutil%C_R%
echo   %C_DIM%Pinned URL: %WINUTIL_URL%%C_R%
echo.
echo   %C_WARN%SECURITY NOTE:%C_R%
echo   %C_DIM%This downloads PowerShell code from GitHub and runs it.%C_R%
echo   %C_DIM%The downloaded file must match this SHA-256 before it runs:%C_R%
echo   %C_DIM%%WINUTIL_SHA256%%C_R%
echo.
echo   %C_WARN%Press Ctrl+C to cancel, or%C_R%
pause

echo.
echo     Downloading WinUtil to local file...

:: Download to local file first, verify SHA-256, then run from disk.
set "WINUTIL_FILE=%TEMP%\winutil.ps1"
powershell -NoProfile -Command "Invoke-WebRequest -Uri '%WINUTIL_URL%' -OutFile '%WINUTIL_FILE%' -UseBasicParsing"

if not exist "%WINUTIL_FILE%" (
    echo   %C_ERR%[ERROR] Download failed.%C_R%
    echo   %C_DIM%Try manually: https://github.com/ChrisTitusTech/winutil/releases%C_R%
    pause
    exit /b 1
)

call "%~dp0..\lib\ui-helpers.bat" ui_step_ok "Downloaded to %WINUTIL_FILE%"

for /f "tokens=*" %%h in ('powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 '%WINUTIL_FILE%').Hash.ToLowerInvariant()"') do set "WINUTIL_HASH=%%h"
echo.
echo   %C_HEAD%Expected SHA-256:%C_R% %WINUTIL_SHA256%
echo   %C_HEAD%Actual SHA-256:  %C_R% %WINUTIL_HASH%
echo.
if /I not "%WINUTIL_HASH%"=="%WINUTIL_SHA256%" (
    echo   %C_ERR%[ERROR] SHA-256 mismatch. WinUtil will not run.%C_R%
    echo   %C_DIM%Delete the file and update this wrapper only after auditing the new release.%C_R%
    del "%WINUTIL_FILE%" 2>nul
    pause
    exit /b 1
)

call "%~dp0..\lib\ui-helpers.bat" ui_step_ok "SHA-256 verified"

echo   %C_WARN%SECURITY: The verified script has been saved locally. You can review it%C_R%
echo   %C_WARN%before running. To review: open the file in a text editor.%C_R%
echo.
echo   %C_WARN%Press Ctrl+C to cancel and review first, or%C_R%
pause

echo.
echo     Launching WinUtil...
powershell -ExecutionPolicy Bypass -File "%WINUTIL_FILE%"

:: Clean up
del "%WINUTIL_FILE%" 2>nul

echo.
echo   %C_OK%WinUtil session ended.%C_R%
echo.
pause
