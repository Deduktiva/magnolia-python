# Download and unpack the SQLite amalgamation. Mirrors download-zlib.ps1's
# idempotent extract-once pattern: subsequent runs no-op when the cache
# is warm, so MSBuild incremental builds don't re-fetch the zip.
#
# Three pin files (version + year + SHA-256) are needed because
# sqlite.org's download URL embeds a calendar-year segment that isn't
# derivable from the version number — it tracks the actual release
# date. See https://sqlite.org/chronology.html for the year-version
# table.
#
# The zip file's name uses a numeric encoding of the version
# (<major>*1000000 + <minor>*10000 + <patch>*100, e.g. 3.53.1 ->
# 3530100), computed below.
#
# sqlite.org doesn't publish per-zip .sha256 sidecars, so the pin is
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

$Version = (Get-Content (Join-Path $ScriptDir 'sqlite-version') -Raw).Trim()
$Year = (Get-Content (Join-Path $ScriptDir 'sqlite-year') -Raw).Trim()
$ExpectedSha256 = (Get-Content (Join-Path $ScriptDir 'sqlite-sha256') -Raw).Trim().ToLower()

# Compute the numeric encoding sqlite.org's URL embeds.
$parts = $Version.Split('.')
$Numeric = '{0:D7}' -f ([int]$parts[0] * 1000000 + [int]$parts[1] * 10000 + [int]$parts[2] * 100)

$Zip = "sqlite-amalgamation-$Numeric.zip"
$Url = "https://sqlite.org/$Year/$Zip"
# Stage the extracted tree under sqlite-<version>/ rather than the
# upstream sqlite-amalgamation-<numeric>/ name so the path consumers
# (SQLite.vcxproj BuildDir, build-common.sh SQLITE_SRC) can refer to
# it via the friendlier $(SQLiteVersion) without recomputing the
# numeric encoding.
$ExtractDir = Join-Path $ScriptDir "sqlite\sqlite-$Version"

if (Test-Path $ExtractDir) { exit 0 }

Push-Location $ScriptDir
try {
    if (!(Test-Path sqlite)) { New-Item -ItemType Directory -Path sqlite | Out-Null }
    Push-Location sqlite
    try {
        if (Test-Path $Zip) { Remove-Item -Force $Zip }

        Invoke-WebRequest -OutFile $Zip -Uri $Url

        $actual = Get-Sha256Hex (Join-Path $PWD.Path $Zip)
        if ($ExpectedSha256 -ne $actual) {
            Remove-Item -Force $Zip
            throw "SHA-256 mismatch for ${Zip}: expected $ExpectedSha256, got $actual (pinned in MagPython/sqlite-sha256 -- regenerate via MagPython/update-sqlite.sh before changing)"
        }

        # tar.exe on Windows 10+ uses libarchive and handles .zip too.
        & tar.exe -xf $Zip
        if ($LASTEXITCODE -ne 0) { throw "tar -xf $Zip failed" }

        # Rename upstream's sqlite-amalgamation-<numeric>/ to
        # sqlite-<version>/ so the path is stable across version bumps
        # without recomputing the numeric encoding.
        $upstreamDir = "sqlite-amalgamation-$Numeric"
        if (!(Test-Path $upstreamDir)) {
            throw "tar extract did not produce expected dir $upstreamDir"
        }
        Move-Item -Path $upstreamDir -Destination "sqlite-$Version"
    } finally { Pop-Location }
} finally { Pop-Location }
