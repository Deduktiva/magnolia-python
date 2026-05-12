# Download and unpack zlib.
#
# Keep this file ASCII-only (see download-helpers.ps1's note for why).
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'download-helpers.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'zlib-version') -Raw).Trim()
$Sha     = (Get-Content (Join-Path $ScriptDir 'zlib-sha256') -Raw).Trim().ToLower()

Get-PinnedSource `
    -ScriptDir $ScriptDir -Name 'zlib' -ExpectedSha256 $Sha `
    -Url "https://github.com/madler/zlib/releases/download/v$Version/zlib-$Version.tar.gz" `
    -ArchiveName "zlib-$Version.tar.gz" `
    -TargetDir "zlib\zlib-$Version" `
    -WorkDir 'zlib'
