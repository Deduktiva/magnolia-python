# Download and unpack CPython. Mirrors download-libffi.ps1's idempotent
# extract-once pattern: subsequent runs no-op when the cache is warm,
# so MSBuild incremental builds don't re-fetch the tarball.
#
# The version + expected SHA-256 are read from sibling files
# (python-version, python-sha256). python.org publishes a release
# tarball with .sigstore signatures, but the GitHub tag archive is
# the canonical source the previous in-tree update-python.sh used and
# is signed-by-HTTPS plus immutable per-tag. The pin is in-tree.
#
# The GitHub tag archive extracts to cpython-<version>/. We rename it
# to python-<version>/ for path symmetry with the other devendored
# deps (and so the vcxproj's $(PythonSourceDir) substitution stays
# clean: $(MSBuildProjectDirectory)\python\python-$(PythonVersion)\).
#
# Keep this file ASCII-only. Without a UTF-8 BOM, powershell.exe on
# Windows reads .ps1 sources as Windows-1252; a UTF-8 em-dash (0xE2 0x80
# 0x94) decodes to "a..." with 0x94 as a right-double-quote that
# prematurely terminates whatever string it's inside, and the parser
# blows up several lines later with a misleading error.
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'sha256.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'python-version') -Raw).Trim()
$ExpectedSha256 = (Get-Content (Join-Path $ScriptDir 'python-sha256') -Raw).Trim().ToLower()
$Tarball = "cpython-$Version.tar.gz"
$Url = "https://github.com/python/cpython/archive/refs/tags/v$Version.tar.gz"
$ExtractDir = Join-Path $ScriptDir "python\python-$Version"

if (Test-Path $ExtractDir) { exit 0 }

Push-Location $ScriptDir
try {
    if (!(Test-Path python)) { New-Item -ItemType Directory -Path python | Out-Null }
    Push-Location python
    try {
        if (Test-Path $Tarball) { Remove-Item -Force $Tarball }

        Invoke-WebRequest -OutFile $Tarball -Uri $Url

        $actual = Get-Sha256Hex (Join-Path $PWD.Path $Tarball)
        if ($ExpectedSha256 -ne $actual) {
            Remove-Item -Force $Tarball
            throw "SHA-256 mismatch for ${Tarball}: expected $ExpectedSha256, got $actual (pinned in MagPython/python-sha256 -- regenerate via MagPython/update-python.sh before changing)"
        }

        # tar.exe ships in modern Windows (10 1803+, Server 2019+) and is
        # available on the GitHub windows-2025 runner.
        & tar.exe -xzf $Tarball
        if ($LASTEXITCODE -ne 0) { throw "tar -xzf $Tarball failed" }

        # Upstream extracts to cpython-<version>/. Rename to python-<version>/
        # so $(PythonSourceDir) in the vcxprojs has a stable shape across
        # version bumps without per-bump edits.
        $upstreamDir = "cpython-$Version"
        if (!(Test-Path $upstreamDir)) {
            throw "tar extract did not produce expected dir $upstreamDir"
        }
        Move-Item -Path $upstreamDir -Destination "python-$Version"
    } finally { Pop-Location }
} finally { Pop-Location }
