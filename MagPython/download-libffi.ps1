# Download and unpack libffi. Mirrors download-zlib.ps1's idempotent
# extract-once pattern: subsequent runs no-op when the cache is warm,
# so MSBuild incremental builds don't re-fetch the tarball.
#
# The version + expected SHA-256 are read from sibling files
# (libffi-version, libffi-sha256) so common.props, build-common.sh
# (Linux/macOS), and this script all share one source of truth.
# libffi/libffi does not publish per-tarball .sha256 sidecars on its
# GitHub releases, so the pin is in-tree.
#
# This script does NOT regenerate the project-local
# MagPython/libffi-msvc-include/ffi.h — that's update-libffi.sh's
# job, run by a maintainer at version-bump time. The committed ffi.h
# is the build's source of truth for the @VERSION@ / @TARGET@ /
# @HAVE_LONG_DOUBLE@ / @FFI_EXEC_TRAMPOLINE_TABLE@ substitutions
# autoconf would normally do at configure time on Unix.
#
# Keep this file ASCII-only. Without a UTF-8 BOM, powershell.exe on
# Windows reads .ps1 sources as Windows-1252; a UTF-8 em-dash (0xE2 0x80
# 0x94) decodes to "a..." with 0x94 as a right-double-quote that
# prematurely terminates whatever string it's inside, and the parser
# blows up several lines later with a misleading error.
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'sha256.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'libffi-version') -Raw).Trim()
$ExpectedSha256 = (Get-Content (Join-Path $ScriptDir 'libffi-sha256') -Raw).Trim().ToLower()
$Tarball = "libffi-$Version.tar.gz"
$BaseUrl = "https://github.com/libffi/libffi/releases/download/v$Version"
$ExtractDir = Join-Path $ScriptDir "libffi\libffi-$Version"

if (Test-Path $ExtractDir) { exit 0 }

Push-Location $ScriptDir
try {
    if (!(Test-Path libffi)) { New-Item -ItemType Directory -Path libffi | Out-Null }
    Push-Location libffi
    try {
        if (Test-Path $Tarball) { Remove-Item -Force $Tarball }

        Invoke-WebRequest -OutFile $Tarball -Uri "$BaseUrl/$Tarball"

        $actual = Get-Sha256Hex (Join-Path $PWD.Path $Tarball)
        if ($ExpectedSha256 -ne $actual) {
            Remove-Item -Force $Tarball
            throw "SHA-256 mismatch for ${Tarball}: expected $ExpectedSha256, got $actual (pinned in MagPython/libffi-sha256 -- regenerate via MagPython/update-libffi.sh before changing)"
        }

        # tar.exe ships in modern Windows (10 1803+, Server 2019+) and is
        # available on the GitHub windows-2025 runner. Avoids pulling in a
        # third-party PowerShell archive cmdlet for tar.gz support.
        & tar.exe -xzf $Tarball
        if ($LASTEXITCODE -ne 0) { throw "tar -xzf $Tarball failed" }
    } finally { Pop-Location }
} finally { Pop-Location }
