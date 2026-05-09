# Download and unpack jom — Qt's drop-in nmake replacement that supports
# parallel jobs (-j). Microsoft's nmake is single-threaded; jom + cl
# spawns one cl process per CPU core, cutting the OpenSSL build from
# ~6 minutes to under 2 on a 4-core runner. Also used by ZLib.vcxproj.
#
# Mirrors download-libmpdec.ps1's idempotent extract-once pattern.
#
# The version + expected SHA-256 are read from sibling files
# (jom-version, jom-sha256). qt.io's downloads page doesn't publish
# per-zip .sha256 sidecars on the same path as the zip, so the
# in-tree pin is the sole hash check (run update-jom.sh to
# regenerate after a version bump).
#
# Keep this file ASCII-only. Without a UTF-8 BOM, powershell.exe on
# Windows reads .ps1 sources as Windows-1252; a UTF-8 em-dash (0xE2 0x80
# 0x94) decodes to "a..." with 0x94 as a right-double-quote that
# prematurely terminates whatever string it's inside, and the parser
# blows up several lines later with a misleading error.
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'sha256.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'jom-version') -Raw).Trim()
$ExpectedSha256 = (Get-Content (Join-Path $ScriptDir 'jom-sha256') -Raw).Trim().ToLower()
# qt.io's URL uses underscore-separated version (jom_1_1_4.zip)
# rather than dot-separated (jom_1.1.4.zip) — convert here.
$VersionUnderscored = $Version -replace '\.', '_'
$Zip = "jom_$VersionUnderscored.zip"
$Url = "https://download.qt.io/official_releases/jom/$Zip"
# jom doesn't extract to a subdir — its zip contains jom.exe at the
# root. Stage under MagPython/jom/ to keep the openssl.vcxproj /
# ZLib.vcxproj `set PATH=$(MSBuildProjectDirectory)\jom;%PATH%` lines
# stable across version bumps.
$ExtractDir = Join-Path $ScriptDir "jom"

if (Test-Path $ExtractDir) { exit 0 }

Push-Location $ScriptDir
try {
    if (Test-Path $Zip) { Remove-Item -Force $Zip }

    Invoke-WebRequest -OutFile $Zip -Uri $Url

    $actual = Get-Sha256Hex (Join-Path $PWD.Path $Zip)
    if ($ExpectedSha256 -ne $actual) {
        Remove-Item -Force $Zip
        throw "SHA-256 mismatch for ${Zip}: expected $ExpectedSha256, got $actual (pinned in MagPython/jom-sha256 -- regenerate via MagPython/update-jom.sh before changing)"
    }

    # tar.exe on Windows 10+ handles .zip via libarchive. Same
    # module-loading dependency reasoning as in download-nasm.ps1
    # (Expand-Archive's module isn't guaranteed under MSBuild's
    # powershell -NonInteractive invocation).
    if (!(Test-Path jom)) { New-Item -ItemType Directory -Path jom | Out-Null }
    Push-Location jom
    try {
        Move-Item -Path "..\$Zip" -Destination "$Zip"
        & tar.exe -xf $Zip
        if ($LASTEXITCODE -ne 0) { throw "tar -xf $Zip failed" }
        Remove-Item -Force $Zip
    } finally { Pop-Location }
} finally { Pop-Location }
