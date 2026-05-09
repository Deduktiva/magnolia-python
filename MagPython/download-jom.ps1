# Download and unpack jom — Qt's drop-in nmake replacement that supports
# parallel jobs (-j). Microsoft's nmake is single-threaded; jom + cl
# spawns one cl process per CPU core, cutting an OpenSSL build from
# ~6 minutes to under 2 on a 4-core runner. Also used by ZLib.vcxproj.
#
# qt.io's URL uses underscore-separated version (jom_1_1_4.zip) and the
# zip extracts files at the root rather than a subdir; pass WorkDir='jom'
# so the helper cd's into MagPython/jom/ before extracting and the files
# land where TargetDir expects.
#
# Keep this file ASCII-only (see download-helpers.ps1's note for why).
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'download-helpers.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'jom-version') -Raw).Trim()
$Sha     = (Get-Content (Join-Path $ScriptDir 'jom-sha256') -Raw).Trim().ToLower()
$VersionUnderscored = $Version -replace '\.', '_'

Get-PinnedSource `
    -ScriptDir $ScriptDir -Name 'jom' -ExpectedSha256 $Sha `
    -Url "https://download.qt.io/official_releases/jom/jom_$VersionUnderscored.zip" `
    -ArchiveName "jom_$VersionUnderscored.zip" `
    -TargetDir 'jom' `
    -WorkDir 'jom' `
    -TarFlags '-xf'
