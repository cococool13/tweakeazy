# ============================================================
# Shared Download / File Helpers
# Windows 11 Gaming Optimization Guide
# ============================================================
# Extracted from DduManual.ps1 for reuse by GPU driver scripts.
# ============================================================

# Cross-platform staging root. $env:ProgramData is null on macOS / Linux
# dev machines (lib gets dot-sourced by Pester tests on macOS); fall
# back to $XDG_DATA_HOME / ~/.local/share so dot-source doesn't throw.
# Production (Windows) keeps the historical %ProgramData%\GamingOpt path.
$script:GamingOptDataHome = if ($env:ProgramData) {
    $env:ProgramData
} elseif ($env:XDG_DATA_HOME) {
    $env:XDG_DATA_HOME
} else {
    Join-Path $HOME '.local/share'
}
$script:GamingOptRoot = Join-Path $script:GamingOptDataHome 'GamingOpt'

# Set-DduDriverSearchPolicy / Restore-DduDriverSearchPolicy write
# SearchOrderConfig through Set-ToolkitRegistryValue. toolkit-state.ps1
# does not dot-source this file.
. "$PSScriptRoot\toolkit-state.ps1"

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Ensure-Internet {
    # Direct .NET ping. Avoids Test-Connection's CimInstance overhead
    # and the PSAvoidUsingComputerNameHardcoded false positive on
    # well-known public DNS reachability targets. 1500ms is generous
    # for any non-loopback environment.
    $ping = [System.Net.NetworkInformation.Ping]::new()
    try {
        $reply = $ping.Send('8.8.8.8', 1500)
        if ($reply.Status -ne [System.Net.NetworkInformation.IPStatus]::Success) {
            throw "Internet connection required"
        }
    } catch [System.Net.NetworkInformation.PingException] {
        throw "Internet connection required"
    } finally {
        $ping.Dispose()
    }
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-FileFromWeb {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$File
    )

    Write-Info "Downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $File -UseBasicParsing
    if (-not (Test-Path $File) -or (Get-Item $File).Length -lt 1000) {
        throw "Download failed or file too small: $File"
    }
}

function Test-FileSha256 {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedHash
    )

    $actualHash = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    return $actualHash -eq $ExpectedHash.ToLowerInvariant()
}

function Test-FileAuthenticode {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ExpectedSignerCN = ""
    )

    $signature = Get-AuthenticodeSignature $Path
    if ($signature.Status -ne "Valid") {
        return $false
    }
    if ($ExpectedSignerCN -ne "" -and $signature.SignerCertificate.Subject -notmatch [regex]::Escape($ExpectedSignerCN)) {
        return $false
    }
    return $true
}

function Ensure-7Zip {
    $sevenZipExe = Join-Path ${env:ProgramFiles} "7-Zip\7z.exe"
    if (Test-Path $sevenZipExe) {
        return $sevenZipExe
    }

    # Fetch version info from manifest (GitHub → cache → bundled)
    . "$PSScriptRoot\version-manifest.ps1"
    $sevenZipManifest = Get-ToolManifest -Name "sevenZip"
    $sevenZipInstaller = Join-Path $env:TEMP "7zip-installer.exe"
    $sevenZipUrl = $sevenZipManifest.url
    $sevenZipHash = $sevenZipManifest.sha256

    Write-Info "Installing 7-Zip v$($sevenZipManifest.version) for archive extraction..."
    Get-FileFromWeb -Url $sevenZipUrl -File $sevenZipInstaller

    # Verify SHA-256 hash first (if hash is a valid hex string)
    if ($sevenZipHash -match "^[0-9a-fA-F]{64}$") {
        if (-not (Test-FileSha256 -Path $sevenZipInstaller -ExpectedHash $sevenZipHash)) {
            Remove-Item $sevenZipInstaller -Force -ErrorAction SilentlyContinue
            throw "7-Zip installer hash mismatch — update pinned hash if 7-Zip version changed"
        }
    }

    # Also verify Authenticode signature
    $signature = Get-AuthenticodeSignature $sevenZipInstaller
    if ($signature.Status -ne "Valid") {
        Remove-Item $sevenZipInstaller -Force -ErrorAction SilentlyContinue
        throw "7-Zip installer signature is invalid"
    }

    Start-Process -FilePath $sevenZipInstaller -ArgumentList "/S" -Wait
    if (-not (Test-Path $sevenZipExe)) {
        throw "7-Zip installation failed"
    }

    return $sevenZipExe
}

# Temporary DDU hold for HKLM\...\DriverSearching\SearchOrderConfig.
# Uses the same manifest id as APPLY-EVERYTHING (reg:DriverSearchOrderConfig).
# Set-ToolkitRegistryValue records `before` only on first insert, so a DDU
# run cannot replace an existing snapshot. Restore writes the pre-DDU live
# value back through that same helper: a machine that was already 0 (Apply
# Everything) stays 0; a machine that was 1 returns to 1.
$script:DduDriverSearchPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'
$script:DduDriverSearchName = 'SearchOrderConfig'
$script:DduDriverSearchId = 'reg:DriverSearchOrderConfig'

function Set-DduDriverSearchPolicy {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()

    if (-not (Get-ToolkitState)) {
        Initialize-ToolkitState | Out-Null
    }

    $prior = Get-ToolkitRegistryState -Path $script:DduDriverSearchPath -Name $script:DduDriverSearchName
    $target = "$script:DduDriverSearchPath\$script:DduDriverSearchName"
    if (-not $PSCmdlet.ShouldProcess($target, 'set DWORD = 0 (disable WU driver search for DDU)')) {
        return $null
    }

    Write-Info 'Temporarily disabling Windows driver search (SearchOrderConfig=0) for DDU.'
    Set-ToolkitRegistryValue -Id $script:DduDriverSearchId `
        -Path $script:DduDriverSearchPath -Name $script:DduDriverSearchName `
        -Value 0 -Type 'DWord' -Tier 'Advanced' -Step 'ddu'
    return $prior
}

function Restore-DduDriverSearchPolicy {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][bool]$ValueExisted,
        [object]$PreviousValue,
        [string]$PreviousKind = 'DWord'
    )

    if (-not (Get-ToolkitState)) {
        Initialize-ToolkitState | Out-Null
    }

    $target = "$script:DduDriverSearchPath\$script:DduDriverSearchName"
    $action = if ($ValueExisted) {
        "restore SearchOrderConfig to pre-DDU value $PreviousValue"
    } else {
        'remove SearchOrderConfig (it was absent before DDU)'
    }
    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        return
    }

    Write-Info 'Restoring Windows driver search to its pre-DDU value.'
    if (-not $ValueExisted) {
        if (Test-Path -LiteralPath $script:DduDriverSearchPath) {
            Remove-ItemProperty -LiteralPath $script:DduDriverSearchPath -Name $script:DduDriverSearchName -ErrorAction SilentlyContinue
        }
        return
    }

    $kind = if ([string]::IsNullOrWhiteSpace($PreviousKind)) { 'DWord' } else { $PreviousKind }
    Set-ToolkitRegistryValue -Id $script:DduDriverSearchId `
        -Path $script:DduDriverSearchPath -Name $script:DduDriverSearchName `
        -Value $PreviousValue -Type $kind -Tier 'Advanced' -Step 'ddu'
}

function Get-DduDriverSearchRestoreBlock {
    param(
        $Prior,
        [Parameter(Mandatory)][string]$LibPath
    )
    if ($null -eq $Prior) { return '' }

    $libEsc = $LibPath.Replace("'", "''")
    $restoreCall = if ($Prior.valueExists) {
        $kind = if ($Prior.kind) { [string]$Prior.kind } else { 'DWord' }
        $kindEsc = $kind.Replace("'", "''")
        $valueText = if ($kind -eq 'DWord' -or $kind -eq 'QWord') {
            [string]([int64]$Prior.value)
        } else {
            "'" + ([string]$Prior.value).Replace("'", "''") + "'"
        }
        "Restore-DduDriverSearchPolicy -ValueExisted:`$true -PreviousValue $valueText -PreviousKind '$kindEsc'"
    } else {
        'Restore-DduDriverSearchPolicy -ValueExisted:$false'
    }

    @"
        try {
            . '$libEsc'
            $restoreCall
        } catch {
            Write-Host ('[WARN] Driver search policy was not restored: ' + `$_.Exception.Message) -ForegroundColor Yellow
        }
"@
}

function Restore-DriverSearchPolicy {
    # GPU-install failure fallback only: force the Windows default (1) so
    # Windows Update can supply a driver. Not for DDU. DDU must call
    # Restore-DduDriverSearchPolicy so a tracked before-snapshot and the
    # pre-DDU live value are preserved.
    reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\DriverSearching" /v "SearchOrderConfig" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
}
