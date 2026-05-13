# Download and unpack libffi.
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
