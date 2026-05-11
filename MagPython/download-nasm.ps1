# Download and unpack netwide assembler.
#
# Stage the extracted tree as MagPython/nasm/ (unversioned) rather
# than nasm-<version>/ so the openssl.vcxproj NMakeBuildCommandLine's
# `set PATH=$(MSBuildProjectDirectory)\nasm;%PATH%` line stays stable
# across nasm bumps.
#
# Keep this file ASCII-only (see download-helpers.ps1's note for why).
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'download-helpers.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'nasm-version') -Raw).Trim()
$Sha     = (Get-Content (Join-Path $ScriptDir 'nasm-sha256') -Raw).Trim().ToLower()

Get-PinnedSource `
    -ScriptDir $ScriptDir -Name 'nasm' -ExpectedSha256 $Sha `
    -Url "https://www.nasm.us/pub/nasm/releasebuilds/$Version/win32/nasm-$Version-win32.zip" `
    -ArchiveName "nasm-$Version-win32.zip" `
    -TargetDir 'nasm' `
    -RenameFrom "nasm-$Version" -RenameTo 'nasm' `
    -TarFlags '-xf'
