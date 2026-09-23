#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Static contract: WinUtil's pin lives in versions.json and the
    batch wrapper reads it through Get-ToolManifest, same as DDU.

.NOTES
    # CROSS-PLATFORM-NOTE
    # The .bat itself is Windows-only. These tests parse versions.json
    # and the wrapper text, then call Get-ToolManifest against the
    # bundled manifest with the network mocked off.
    # Runtime download + hash compare: MANUAL-TEST-CHECKLIST.md 15.5.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' '_common.ps1')
    . (Join-Path $PSScriptRoot '..' '..' 'lib' 'version-manifest.ps1')

    $script:BatPath = Join-Path $script:RepoRoot '9 cleanup/chris-titus-winutil.bat'
    $script:ManifestPath = Join-Path $script:RepoRoot 'versions.json'
    $script:BatText = Get-Content -Raw -LiteralPath $script:BatPath
    $script:PinnedSha = '4c2595118edd3355065c1f449cd7e0092614dfc2552e8ac8e4ec4231a6d9a719'
    $script:PinnedVersion = '26.04.21'
    $script:PinnedUrl = 'https://github.com/ChrisTitusTech/winutil/releases/download/26.04.21/winutil.ps1'
}

Describe 'versions.json tools.winutil' {
    It 'pins version, url, and a 64-char SHA-256' {
        $manifest = Get-Content -Raw -LiteralPath $script:ManifestPath | ConvertFrom-Json
        $winutil = $manifest.tools.winutil
        $winutil.version | Should -Be $script:PinnedVersion
        $winutil.url | Should -Be $script:PinnedUrl
        $winutil.sha256 | Should -Be $script:PinnedSha
        $winutil.sha256 | Should -Match '^[0-9a-f]{64}$'
    }
}

Describe '9 cleanup/chris-titus-winutil.bat' {
    It 'reads the pin through Get-ToolManifest -Name winutil' {
        $script:BatText | Should -Match "Get-ToolManifest -Name 'winutil'"
        $script:BatText | Should -Match 'version-manifest\.ps1'
    }

    It 'does not hardcode the release pin' {
        $script:BatText | Should -Not -Match 'set "WINUTIL_VERSION=26\.04\.21"'
        $script:BatText | Should -Not -Match 'set "WINUTIL_SHA256=[0-9a-fA-F]{64}"'
        $script:BatText | Should -Not -Match [regex]::Escape($script:PinnedSha)
        $script:BatText | Should -Not -Match [regex]::Escape($script:PinnedUrl)
    }

    It 'still refuses to run on a SHA-256 mismatch' {
        $script:BatText | Should -Match 'if /I not "%WINUTIL_HASH%"=="%WINUTIL_SHA256%"'
        $script:BatText | Should -Match 'SHA-256 mismatch'
        $script:BatText | Should -Match 'exit /b 1'
    }
}

Describe 'Get-ToolManifest winutil (bundled fallback, same helper as DDU)' {
    BeforeEach {
        $script:OrigCache = $script:ManifestCachePath
        $script:OrigBundled = $script:ManifestBundledPath
        $script:TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("winutil-pin-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
        $script:ManifestCachePath = Join-Path $script:TmpDir 'missing-cache.json'
        $script:ManifestBundledPath = $script:ManifestPath
        Mock Invoke-WebRequest { throw 'no network' }
    }

    AfterEach {
        $script:ManifestCachePath = $script:OrigCache
        $script:ManifestBundledPath = $script:OrigBundled
        if ($script:TmpDir -and (Test-Path -LiteralPath $script:TmpDir)) {
            Remove-Item -LiteralPath $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns the versions.json pin when remote is unreachable' {
        $tool = Get-ToolManifest -Name 'winutil' 6>$null
        $tool.version | Should -Be $script:PinnedVersion
        $tool.url | Should -Be $script:PinnedUrl
        $tool.sha256 | Should -Be $script:PinnedSha
    }
}
