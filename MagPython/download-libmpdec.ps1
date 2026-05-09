# Download and unpack libmpdec (mpdecimal). Mirrors download-nasm.ps1's
# idempotent extract-once pattern: subsequent runs no-op when the cache is
# warm, so MSBuild incremental builds don't re-fetch the tarball.
#
# The version + expected SHA-256 are read from sibling files
# (libmpdec-version, libmpdec-sha256) so common.props, build-common.sh
# (Linux/macOS), and this script all share one source of truth.
# bytereef.org doesn't publish per-tarball .sha256 sidecars (the hashes
# live only in the HTML table at
# https://www.bytereef.org/mpdecimal/download.html), so the pin is
# in-tree.
#
# Keep this file ASCII-only. Without a UTF-8 BOM, powershell.exe on
# Windows reads .ps1 sources as Windows-1252; a UTF-8 em-dash (0xE2 0x80
# 0x94) decodes to "a..." with 0x94 as a right-double-quote that
# prematurely terminates whatever string it's inside, and the parser
# blows up several lines later with a misleading error.
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'sha256.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'libmpdec-version') -Raw).Trim()
$ExpectedSha256 = (Get-Content (Join-Path $ScriptDir 'libmpdec-sha256') -Raw).Trim().ToLower()
$BaseUrl = "https://www.bytereef.org/software/mpdecimal/releases"
$Tarball = "mpdecimal-$Version.tar.gz"
$ExtractDir = Join-Path $ScriptDir "libmpdec\mpdecimal-$Version"

if (Test-Path $ExtractDir) { exit 0 }

Push-Location $ScriptDir
try {
    if (!(Test-Path libmpdec)) { New-Item -ItemType Directory -Path libmpdec | Out-Null }
    Push-Location libmpdec
    try {
        if (Test-Path $Tarball) { Remove-Item -Force $Tarball }

        Invoke-WebRequest -OutFile $Tarball -Uri "$BaseUrl/$Tarball"

        $actual = Get-Sha256Hex (Join-Path $PWD.Path $Tarball)
        if ($ExpectedSha256 -ne $actual) {
            Remove-Item -Force $Tarball
            throw "SHA-256 mismatch for ${Tarball}: expected $ExpectedSha256, got $actual (pinned in MagPython/libmpdec-sha256 -- confirm against the table at https://www.bytereef.org/mpdecimal/download.html before changing)"
        }

        # tar.exe ships in modern Windows (10 1803+, Server 2019+) and is
        # available on the GitHub windows-2025 runner. Avoids pulling in a
        # third-party PowerShell archive cmdlet for tar.gz support.
        & tar.exe -xzf $Tarball
        if ($LASTEXITCODE -ne 0) { throw "tar -xzf $Tarball failed" }
    } finally { Pop-Location }
} finally { Pop-Location }
