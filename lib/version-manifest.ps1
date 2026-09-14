# ============================================================
# Version Manifest — Remote Fetch with Local Fallback
# Windows 11 Gaming Optimization Guide
# ============================================================
# Fetches the latest versions.json from GitHub so scripts always
# use current driver URLs and hashes without manual edits.
#
# Flow:
#   1. Try fetching from GitHub raw (main branch)
#   2. Cache successful fetch locally for offline use
#   3. Fall back to cached copy if GitHub is unreachable
#   4. Fall back to bundled versions.json if no cache exists
# ============================================================

$script:ManifestGitHubUrl = "https://raw.githubusercontent.com/cococool13/TweakEazy/main/versions.json"

# Cache root selection mirrors lib/toolkit-state.ps1's fallback chain so
# the lib dot-sources cleanly on:
#   - Windows runtime               → $env:ProgramData (the prod target)
#   - macOS / Linux dev hosts        → $XDG_DATA_HOME
#   - Anywhere else (Server Core...) → $HOME/.local/share
# Without this chain, Join-Path threw "argument is null" on dev macOS
# and the script var ended up empty — breaking Test-Path checks downstream.
if ($env:ProgramData) {
    $script:ManifestCacheRoot = $env:ProgramData
} elseif ($env:XDG_DATA_HOME) {
    $script:ManifestCacheRoot = $env:XDG_DATA_HOME
} else {
    $script:ManifestCacheRoot = Join-Path $HOME '.local/share'
}
$script:ManifestCachePath = Join-Path $script:ManifestCacheRoot 'GamingOpt/versions-cache.json'
$script:ManifestBundledPath = Join-Path $PSScriptRoot '..' | ForEach-Object { Join-Path $_ 'versions.json' }

function Get-VersionManifest {
    <#
    .SYNOPSIS
        Returns the latest version manifest as a PSCustomObject.
        Tries GitHub first, then local cache, then bundled fallback.
    #>

    # 1. Try remote fetch
    $remote = Fetch-RemoteManifest
    if ($remote) {
        return $remote
    }

    # 2. Try cached copy
    if (Test-Path $script:ManifestCachePath) {
        Write-Host "  [INFO] Using cached version manifest." -ForegroundColor Yellow
        return Get-Content $script:ManifestCachePath -Raw | ConvertFrom-Json
    }

    # 3. Fall back to bundled
    if (Test-Path $script:ManifestBundledPath) {
        Write-Host "  [INFO] Using bundled version manifest." -ForegroundColor Yellow
        return Get-Content $script:ManifestBundledPath -Raw | ConvertFrom-Json
    }

    throw "No version manifest available (remote, cache, or bundled)"
}

function Fetch-RemoteManifest {
    <#
    .SYNOPSIS
        Fetches versions.json from GitHub. Returns $null on failure.
        Caches successful fetches for offline use.
    #>

    try {
        $response = Invoke-WebRequest -Uri $script:ManifestGitHubUrl `
            -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop

        $manifest = $response.Content | ConvertFrom-Json

        # Validate it looks like a real manifest
        if (-not $manifest.schemaVersion -or -not $manifest.gpu) {
            Write-Host "  [WARNING] Remote manifest has unexpected format." -ForegroundColor Yellow
            return $null
        }

        # Cache for offline use
        $cacheDir = Split-Path $script:ManifestCachePath -Parent
        if (-not (Test-Path $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }
        $response.Content | Set-Content -Path $script:ManifestCachePath -Force

        Write-Host "  [OK] Using latest version manifest from GitHub." -ForegroundColor Green
        return $manifest
    } catch {
        Write-Host "  [INFO] Could not reach GitHub — using local manifest." -ForegroundColor Yellow
        return $null
    }
}

function Get-GpuManifest {
    <#
    .SYNOPSIS
        Returns just the GPU section of the version manifest.
    #>
    $manifest = Get-VersionManifest
    return $manifest.gpu
}

function Get-ToolManifest {
    <#
    .SYNOPSIS
        Returns a specific tool entry from the manifest (ddu, sevenZip).
    #>
    param([Parameter(Mandatory)][string]$Name)

    $manifest = Get-VersionManifest
    $tool = $manifest.tools.$Name
    if (-not $tool) {
        throw "Tool '$Name' not found in version manifest"
    }
    return $tool
}
