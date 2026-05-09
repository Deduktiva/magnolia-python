# Download and unpack libffi. libffi/libffi doesn't publish per-tarball
# .sha256 sidecars on its GitHub releases, so the in-tree pin is the
# sole hash check.
#
# This script does NOT regenerate the project-local
# MagPython/libffi-msvc-include/ffi.h — that's update-libffi.sh's
# job (run by a maintainer at version-bump time, since regen needs
# the upstream include/ffi.h.in template). The committed ffi.h is
# the build's source of truth for the @VERSION@ / @TARGET@ /
# @HAVE_LONG_DOUBLE@ / @FFI_EXEC_TRAMPOLINE_TABLE@ substitutions
# autoconf would normally do at configure time on Unix.
#
# Keep this file ASCII-only (see download-helpers.ps1's note for why).
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'download-helpers.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'libffi-version') -Raw).Trim()
$Sha     = (Get-Content (Join-Path $ScriptDir 'libffi-sha256') -Raw).Trim().ToLower()

Get-PinnedSource `
    -ScriptDir $ScriptDir -Name 'libffi' -ExpectedSha256 $Sha `
    -Url "https://github.com/libffi/libffi/releases/download/v$Version/libffi-$Version.tar.gz" `
    -ArchiveName "libffi-$Version.tar.gz" `
    -TargetDir "libffi\libffi-$Version" `
    -WorkDir 'libffi'
