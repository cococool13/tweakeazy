#Requires -Version 5.1
<#
.SYNOPSIS
    Launch a Windows Sandbox session with a toolkit .wsb template.

.DESCRIPTION
    Sandbox .wsb files in tests/sandbox/ use %REPO% as a placeholder
    for the host-side repo path (so they're portable across user
    machines and stay clean in git). This wrapper substitutes the
    real path into a temp .wsb and launches it.

    On non-Windows hosts the wrapper writes the temp file + tells the
    user where it is (so dev can inspect the substituted XML) without
    actually launching Sandbox (which doesn't exist on macOS).

.PARAMETER ConfigName
    Name of the .wsb file under tests/sandbox/ (with or without the
    .wsb extension). Tab-completion provided.

.PARAMETER RepoRoot
    Absolute path to the repo to mount into the Sandbox at C:\repo.
    Defaults to the repo this tool lives in.

.EXAMPLE
    PS> tools\Start-SandboxSession.ps1 apply-everything-default
    Launches Windows Sandbox with the default APPLY-EVERYTHING.ps1 run.

.EXAMPLE
    PS> tools\Start-SandboxSession.ps1 -ConfigName debloat -WhatIf
    Shows what would launch without spawning Sandbox.

.NOTES
    Author:   Win11 Gaming Toolkit
    Version:  1.0
    Tier:     Safe (read-only on host; mutates only the Sandbox VM,
                    which is destroyed on close)

    Exit codes:
      0  Sandbox launched (Windows) or temp .wsb written (other OS)
      2  Config name not found under tests/sandbox/
      3  Windows Sandbox feature not installed
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory, Position = 0)]
    [ArgumentCompleter({
            param($cmd, $param, $word)
            $repo = Split-Path -Parent $PSScriptRoot
            Get-ChildItem -LiteralPath (Join-Path $repo 'tests/sandbox') -Filter '*.wsb' -ErrorAction SilentlyContinue |
                Where-Object { $_.BaseName -like "$word*" } |
                ForEach-Object { $_.BaseName }
        })]
    [string]$ConfigName,

    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

# Normalize: accept with/without .wsb extension.
if (-not $ConfigName.EndsWith('.wsb')) { $ConfigName += '.wsb' }
# Two Join-Path calls: 3-arg Join-Path is PS 6+. File claims -Version 5.1.
$source = Join-Path (Join-Path $RepoRoot 'tests/sandbox') $ConfigName
if (-not (Test-Path -LiteralPath $source)) {
    Write-Error "Config not found: $source"
    exit 2
}

# Substitute %REPO% with the real host-side path. Sandbox's
# MappedFolder.HostFolder expects a Windows-style absolute path; on
# Windows this is already correct, on macOS the substitution still
# happens (developers can inspect the generated XML).
#
# Use String.Replace (not the -replace operator) because -replace treats
# backslashes and $-tokens as regex backref / replacement directives,
# which mangles Windows paths. .Replace is a literal substring swap.
$content = Get-Content -Raw -LiteralPath $source
$winRepo = $RepoRoot.Replace('/', '\')
$substituted = $content.Replace('%REPO%', $winRepo)

$tmpDir = if ($IsWindows -or ($null -eq $IsWindows)) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
$tmp = Join-Path $tmpDir ("toolkit-sandbox-{0}-{1}.wsb" -f [System.IO.Path]::GetFileNameWithoutExtension($ConfigName), (Get-Date -Format 'yyyyMMddHHmmss'))

if (-not $PSCmdlet.ShouldProcess($tmp, "Write substituted .wsb (repo=$RepoRoot)")) {
    Write-Output "Would write: $tmp"
    exit 0
}
Set-Content -LiteralPath $tmp -Value $substituted -Encoding utf8

if ($IsWindows -or ($null -eq $IsWindows)) {
    # WindowsSandbox.exe is the binary; .wsb files associate with it.
    $sandboxExe = Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe'
    if (-not (Test-Path -LiteralPath $sandboxExe)) {
        Write-Error 'Windows Sandbox not installed. Enable the feature: Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All'
        exit 3
    }
    Write-Output "Launching Sandbox with $ConfigName..."
    Write-Output "  temp .wsb: $tmp"
    Start-Process -FilePath $sandboxExe -ArgumentList $tmp
    Write-Output 'Sandbox window should appear within ~30 seconds.'
} else {
    Write-Output "Non-Windows host detected. Sandbox cannot launch here."
    Write-Output "Substituted .wsb written for inspection: $tmp"
    Write-Output 'Copy this file to a Windows host with Sandbox enabled to run.'
}
exit 0
