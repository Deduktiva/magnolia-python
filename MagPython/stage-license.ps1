# Stage one upstream license file into the artifact tree.
#
# Mirrors stage_licenses / _stage_license in build-common.sh: writes a
# "<dep> <version>" header line and a blank line, then either the verbatim
# upstream license text (-Mode Copy) or the leading /* ... */ block of a
# C source file (-Mode ExtractCComment, used for SQLite — the amalgamation
# zip ships no separate LICENSE file, so the public-domain blessing in
# sqlite3.h's leading comment is the equivalent text published at
# https://www.sqlite.org/copyright.html).
#
# Used by MagPython.vcxproj's StageLicenses target so the windows-x86 zip
# carries the same MagPython/licenses/<dep>-license.txt shape as the
# linux-x86_64 / macos-arm64 zips.
param(
    [Parameter(Mandatory = $true)] [string] $Source,
    [Parameter(Mandatory = $true)] [string] $Dep,
    [Parameter(Mandatory = $true)] [string] $Version,
    [Parameter(Mandatory = $true)] [string] $OutPath,
    [ValidateSet('Copy', 'ExtractCComment')]
    [string] $Mode = 'Copy'
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source)) {
    throw "license source not found: $Source"
}

$raw = Get-Content -LiteralPath $Source -Raw

if ($Mode -eq 'ExtractCComment') {
    # (?s) enables DOTALL so .*? spans newlines; the leading-comment block
    # is the first /* ... */ in the file.
    $m = [regex]::Match($raw, '(?s)/\*.*?\*/')
    if (-not $m.Success) {
        throw "no leading /* ... */ comment block found in $Source"
    }
    $body = $m.Value
    if ($body -notmatch 'disclaims copyright') {
        throw "leading comment of $Source does not look like the SQLite blessing"
    }
} else {
    $body = $raw
}

$dir = Split-Path -Parent $OutPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
# UTF-8 without BOM and LF for the header newlines — matches what the
# Linux/macOS shell helpers emit. The body keeps whatever line endings
# the upstream file ships with.
$header = "$Dep $Version`n`n"
[System.IO.File]::WriteAllText($OutPath, $header + $body, (New-Object System.Text.UTF8Encoding($false)))
