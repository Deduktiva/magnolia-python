# Extract the leading /* ... */ comment block from sqlite3.h.
#
# The sqlite-amalgamation-<num>.zip we devendor (see download-sqlite.ps1
# / setup_sqlite in build-common.sh) ships only sqlite3.{c,h},
# sqlite3ext.h and shell.c — there's no separate LICENSE file. SQLite is
# in the public domain and the canonical "blessing" lives in the leading
# comment of every shipped source file (the same text published at
# https://www.sqlite.org/copyright.html). Pulling it out of sqlite3.h
# gives the licenses/ tree something concrete for sqlite, version-aligned
# with whatever amalgamation is pinned.
#
# Mirrors the awk extraction in build-common.sh's stage_licenses helper
# so Linux/macOS and Windows artifacts ship the same text.
param(
    [Parameter(Mandatory = $true)] [string] $Sqlite3H,
    [Parameter(Mandatory = $true)] [string] $OutPath
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Sqlite3H)) {
    throw "sqlite3.h not found at $Sqlite3H"
}

$content = Get-Content -LiteralPath $Sqlite3H -Raw
# (?s) enables DOTALL so .*? spans newlines; the leading-comment block is
# the first /* ... */ in the file.
$m = [regex]::Match($content, '(?s)/\*.*?\*/')
if (-not $m.Success) {
    throw "No leading /* ... */ comment block found in $Sqlite3H"
}

$dir = Split-Path -Parent $OutPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
# UTF-8 without BOM, matching the encoding the upstream header uses.
[System.IO.File]::WriteAllText($OutPath, $m.Value, (New-Object System.Text.UTF8Encoding($false)))
