# Download and unpack zstd.
#
# Keep this file ASCII-only (see download-helpers.ps1's note for why).
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'download-helpers.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'zstd-version') -Raw).Trim()
$Sha     = (Get-Content (Join-Path $ScriptDir 'zstd-sha256') -Raw).Trim().ToLower()

Get-PinnedSource `
    -ScriptDir $ScriptDir -Name 'zstd' -ExpectedSha256 $Sha `
    -Url "https://github.com/facebook/zstd/releases/download/v$Version/zstd-$Version.tar.gz" `
    -ArchiveName "zstd-$Version.tar.gz" `
    -TargetDir "zstd\zstd-$Version" `
    -WorkDir 'zstd'
