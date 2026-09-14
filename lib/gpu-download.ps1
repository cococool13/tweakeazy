# ============================================================
# GPU Driver Download & Version Resolution
# Windows 11 Gaming Optimization Guide
# ============================================================
# Requires: lib/download-helpers.ps1 (dot-sourced before this file)
# ============================================================

# Stage root selection mirrors lib/toolkit-state.ps1 + version-manifest.ps1:
#   - Windows runtime          → $env:ProgramData (prod target)
#   - macOS / Linux dev hosts  → $XDG_DATA_HOME
#   - Anywhere else            → $HOME/.local/share
# Without this chain, Join-Path threw "argument is null" on dev macOS
# and the script var ended up empty — breaking downstream Test-Path /
# New-Item calls silently.
if ($env:ProgramData) {
    $script:GpuDriverStageRoot = Join-Path $env:ProgramData 'GamingOpt/Drivers'
} elseif ($env:XDG_DATA_HOME) {
    $script:GpuDriverStageRoot = Join-Path $env:XDG_DATA_HOME 'GamingOpt/Drivers'
} else {
    $script:GpuDriverStageRoot = Join-Path $HOME '.local/share/GamingOpt/Drivers'
}

function Resolve-NvidiaDriverUrl {
    <#
    .SYNOPSIS
        Resolves the NVIDIA driver download URL. Uses the pinned manifest
        by default. With -AutoDetect, queries the NVIDIA driver API.
    #>
    param(
        [Parameter(Mandatory)]$Manifest,
        [string]$DeviceId = "",
        [switch]$AutoDetect
    )

    if ($AutoDetect -and $DeviceId -ne "") {
        try {
            $apiUrl = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?" +
            "func=DriverManualLookup&pfid=0&osID=57&languageCode=1033&isWHQL=1&dch=1&sort1=0&numberOfResults=1"

            $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
            $json = $response.Content | ConvertFrom-Json
            if ($json.IDS -and $json.IDS[0].downloadInfo) {
                $info = $json.IDS[0].downloadInfo
                return [PSCustomObject]@{
                    Version = $info.Version
                    Url = $info.DownloadURL
                    ExpectedHash = ""
                    ExpectedSignerCN = "NVIDIA Corporation"
                    Components = @("Display.Driver", "HDAudio")
                    AutoDetected = $true
                }
            }
        } catch {
            Write-Host "  NVIDIA API query failed, falling back to pinned version." -ForegroundColor Yellow
        }
    }

    $nv = $Manifest.nvidia
    return [PSCustomObject]@{
        Version = $nv.version
        Url = $nv.url
        ExpectedHash = $nv.sha256
        Components = @($nv.components)
        AutoDetected = $false
    }
}

function Resolve-AmdDriverUrl {
    <#
    .SYNOPSIS
        Resolves the AMD driver download URL from the pinned manifest.
        AMD does not provide a clean public API for driver lookups.
    #>
    param([Parameter(Mandatory)]$Manifest)

    $amd = $Manifest.amd
    return [PSCustomObject]@{
        Version = $amd.version
        Url = $amd.url
        ExpectedHash = $amd.sha256
        AutoDetected = $false
    }
}

function Resolve-IntelDriverUrl {
    <#
    .SYNOPSIS
        Resolves the Intel driver download URL from the pinned manifest.
    #>
    param([Parameter(Mandatory)]$Manifest)

    $intel = $Manifest.intel
    return [PSCustomObject]@{
        Version = $intel.version
        Url = $intel.url
        ExpectedHash = $intel.sha256
        DriverOnlyInf = [bool]$intel.driverOnlyInf
        AutoDetected = $false
    }
}

function Get-GpuDriverInstaller {
    <#
    .SYNOPSIS
        Downloads the GPU driver installer to the staging directory.
        Verifies integrity via SHA-256 (if hash provided) or Authenticode.
    .OUTPUTS
        Full path to the downloaded installer file.
    #>
    param(
        [Parameter(Mandatory)][string]$Vendor,
        [Parameter(Mandatory)][string]$Url,
        [string]$ExpectedHash = "",
        [string]$ExpectedSignerCN = ""
    )

    $vendorDir = Join-Path $script:GpuDriverStageRoot $Vendor
    Ensure-Directory -Path $vendorDir

    $fileName = [System.IO.Path]::GetFileName(([uri]$Url).AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = "$Vendor-driver-setup.exe"
    }
    $outputPath = Join-Path $vendorDir $fileName

    # Skip download if already staged and hash matches
    if ((Test-Path $outputPath) -and $ExpectedHash -ne "") {
        if (Test-FileSha256 -Path $outputPath -ExpectedHash $ExpectedHash) {
            Write-Info "Driver already staged and hash verified: $outputPath"
            return $outputPath
        }
    }

    Get-FileFromWeb -Url $Url -File $outputPath

    # Verify integrity — detect placeholder hashes
    if ($ExpectedHash -ne "" -and $ExpectedHash -notmatch "^[0-9a-fA-F]{64}$") {
        Write-Host "  [WARNING] SHA-256 hash is not a valid hex string — using Authenticode only." -ForegroundColor Yellow
        $ExpectedHash = ""
    }

    if ($ExpectedHash -ne "") {
        if (-not (Test-FileSha256 -Path $outputPath -ExpectedHash $ExpectedHash)) {
            Remove-Item $outputPath -Force -ErrorAction SilentlyContinue
            throw "Driver installer hash mismatch. Expected: $ExpectedHash"
        }
        Write-Info "SHA-256 verified."
    } elseif ($ExpectedSignerCN -ne "") {
        if (-not (Test-FileAuthenticode -Path $outputPath -ExpectedSignerCN $ExpectedSignerCN)) {
            Remove-Item $outputPath -Force -ErrorAction SilentlyContinue
            throw "Driver installer Authenticode verification failed. Expected signer: $ExpectedSignerCN"
        }
        Write-Info "Authenticode verified (signer: $ExpectedSignerCN)."
    } else {
        # Last resort: just check Authenticode is valid (any signer)
        if (-not (Test-FileAuthenticode -Path $outputPath)) {
            Write-Host "  [WARNING] Driver installer has no valid Authenticode signature." -ForegroundColor Yellow
        }
    }

    return $outputPath
}
