# Download and unpack OpenSSL. Mirrors download-libmpdec.ps1's
# idempotent extract-once pattern: subsequent runs no-op when the cache
# is warm, so MSBuild incremental builds don't re-fetch the tarball.
#
# The version + expected SHA-256 are read from sibling files
# (openssl-version, openssl-sha256) so common.props, build-common.sh
# (Linux/macOS), and this script all share one source of truth. OpenSSL
# does publish per-tarball .sha256 sidecars on GitHub Releases; the
# in-tree pin is what fails the build on a tampered tarball, the upstream
# sidecar is fetched and cross-checked as defense-in-depth.
#
# Keep this file ASCII-only. Without a UTF-8 BOM, powershell.exe on
# Windows reads .ps1 sources as Windows-1252; a UTF-8 em-dash (0xE2 0x80
# 0x94) decodes to "a..." with 0x94 as a right-double-quote that
# prematurely terminates whatever string it's inside, and the parser
# blows up several lines later with a misleading error.
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'sha256.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'openssl-version') -Raw).Trim()
$ExpectedSha256 = (Get-Content (Join-Path $ScriptDir 'openssl-sha256') -Raw).Trim().ToLower()
$Tarball = "openssl-$Version.tar.gz"
$BaseUrl = "https://github.com/openssl/openssl/releases/download/openssl-$Version"
$ExtractDir = Join-Path $ScriptDir "openssl\openssl-$Version"

if (Test-Path $ExtractDir) { exit 0 }

Push-Location $ScriptDir
try {
    if (!(Test-Path openssl)) { New-Item -ItemType Directory -Path openssl | Out-Null }
    Push-Location openssl
    try {
        if (Test-Path $Tarball) { Remove-Item -Force $Tarball }

        Invoke-WebRequest -OutFile $Tarball -Uri "$BaseUrl/$Tarball"

        $actual = Get-Sha256Hex (Join-Path $PWD.Path $Tarball)
        if ($ExpectedSha256 -ne $actual) {
            Remove-Item -Force $Tarball
            throw "SHA-256 mismatch for ${Tarball}: expected $ExpectedSha256, got $actual (pinned in MagPython/openssl-sha256 -- confirm against the upstream .sha256 sidecar at $BaseUrl/$Tarball.sha256 before changing)"
        }

        # Defense-in-depth: also fetch the upstream .sha256 sidecar and
        # cross-check. This catches a tampered in-tree pin (someone
        # bumping openssl-sha256 without re-verifying against upstream)
        # at the cost of one extra small HTTP request.
        $sidecarPath = "$Tarball.sha256"
        Invoke-WebRequest -OutFile $sidecarPath -Uri "$BaseUrl/$sidecarPath"
        $sidecar = (Get-Content $sidecarPath -Raw).Trim().ToLower()
        # The sidecar format is "<hash> *<filename>" or just "<hash>";
        # take the first whitespace-separated token.
        $sidecarHash = ($sidecar -split '\s+')[0]
        if ($sidecarHash -ne $ExpectedSha256) {
            Remove-Item -Force $Tarball, $sidecarPath
            throw "Upstream .sha256 sidecar disagrees with MagPython/openssl-sha256: sidecar=$sidecarHash, pinned=$ExpectedSha256"
        }
        Remove-Item -Force $sidecarPath

        # tar.exe ships in modern Windows (10 1803+, Server 2019+) and is
        # available on the GitHub windows-2025 runner. Avoids pulling in a
        # third-party PowerShell archive cmdlet for tar.gz support.
        & tar.exe -xzf $Tarball
        if ($LASTEXITCODE -ne 0) { throw "tar -xzf $Tarball failed" }
    } finally { Pop-Location }
} finally { Pop-Location }
