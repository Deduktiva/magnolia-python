# Shared logic for the per-dep download-*.ps1 scripts. Dot-source
# this file from each wrapper and call Get-PinnedSource. See
# update-pin-common.sh for the parallel Unix-side helper.
#
# Why a separate file: the eight download-*.ps1 scripts (openssl,
# zlib, libffi, sqlite, libmpdec, python, nasm, jom) each shipped
# ~50-70 lines of nearly-identical boilerplate around 3 dep-specific
# bits (URL, archive name, expected extract dir + optional rename).
# Concentrating the boilerplate here lets each wrapper drop to ~12
# lines of pure config.
#
# Keep this file ASCII-only. Without a UTF-8 BOM, powershell.exe on
# Windows reads .ps1 sources as Windows-1252; a UTF-8 em-dash (0xE2 0x80
# 0x94) decodes to "a..." with 0x94 as a right-double-quote that
# prematurely terminates whatever string it's inside, and the parser
# blows up several lines later with a misleading error.

$ErrorActionPreference = "Stop"

# Pull in Get-Sha256Hex once at helpers-load time. Wrappers don't
# need to dot-source sha256.ps1 separately.
. (Join-Path $PSScriptRoot 'sha256.ps1')

# Get-PinnedSource: download a tarball/zip, verify its SHA-256,
# extract under MagPython/, and (optionally) rename the upstream
# extract dir to a stable name.
#
# The function is a no-op when the target dir already exists, so
# it's safe to invoke unconditionally — MSBuild incremental builds
# skip the work after the first run.
#
# Parameters:
#   -ScriptDir        the calling wrapper's directory (MagPython/).
#                     Used as the root for relative paths.
#   -Name             pin-file basename, e.g. "openssl". Used in
#                     error messages: "pinned in MagPython/<Name>-sha256
#                     -- regenerate via MagPython/update-<Name>.sh".
#   -ExpectedSha256   lowercase-hex hash the wrapper read from the
#                     pin file.
#   -Url              full upstream URL.
#   -ArchiveName      filename to download into (filename only, no
#                     dir).
#   -TargetDir        path relative to ScriptDir of the dir that
#                     should exist after extraction. Function
#                     early-exits if it already does. For versioned
#                     deps: "openssl\openssl-3.5.6". For unversioned
#                     (nasm, jom): "nasm" / "jom".
#   -WorkDir          optional. Path relative to ScriptDir to cd
#                     into for the download + extract. Defaults to
#                     ScriptDir itself. Used for:
#                       - versioned deps with a per-name cache
#                         subdir (most): WorkDir = "<Name>".
#                       - jom (which extracts files at root rather
#                         than into a subdir): WorkDir = "jom" so
#                         the files land where TargetDir expects.
#                     Created if missing.
#   -RenameFrom       optional. After extract, the dir that upstream
#                     produced (relative to WorkDir). If set,
#                     gets Move-Item'd to RenameTo.
#   -RenameTo         optional. Companion to RenameFrom.
#   -TarFlags         tar.exe flag string. Defaults to "-xzf" for
#                     .tar.gz; pass "-xf" for .zip (tar.exe on
#                     Windows 10+ uses libarchive and handles
#                     both).
function Get-PinnedSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptDir,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ExpectedSha256,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$ArchiveName,
        [Parameter(Mandatory)][string]$TargetDir,
        [string]$WorkDir = '',
        [string]$RenameFrom = '',
        [string]$RenameTo = '',
        [string]$TarFlags = '-xzf'
    )

    if (Test-Path (Join-Path $ScriptDir $TargetDir)) { return }

    $effectiveWorkDir = if ($WorkDir -eq '') { $ScriptDir } else { Join-Path $ScriptDir $WorkDir }
    if (!(Test-Path $effectiveWorkDir)) {
        New-Item -ItemType Directory -Path $effectiveWorkDir | Out-Null
    }

    Push-Location $effectiveWorkDir
    try {
        if (Test-Path $ArchiveName) { Remove-Item -Force $ArchiveName }

        Invoke-WebRequest -OutFile $ArchiveName -Uri $Url

        # Get-Sha256Hex needs an absolute path — .NET APIs use the
        # .NET CWD, not PowerShell's Push-Location-tracked CWD.
        $actual = Get-Sha256Hex (Join-Path $PWD.Path $ArchiveName)
        if ($ExpectedSha256 -ne $actual) {
            Remove-Item -Force $ArchiveName
            throw "SHA-256 mismatch for ${ArchiveName}: expected $ExpectedSha256, got $actual (pinned in MagPython/$Name-sha256 -- regenerate via MagPython/update-$Name.sh before changing)"
        }

        & tar.exe $TarFlags $ArchiveName
        if ($LASTEXITCODE -ne 0) { throw "tar $TarFlags $ArchiveName failed" }

        if ($RenameFrom -ne '') {
            if (!(Test-Path $RenameFrom)) {
                throw "tar extract did not produce expected directory '$RenameFrom'"
            }
            Move-Item -Path $RenameFrom -Destination $RenameTo
        }

        Remove-Item -Force $ArchiveName
    } finally { Pop-Location }
}
