# Download and unpack libmpdec (mpdecimal).
#
# Keep this file ASCII-only (see download-helpers.ps1's note for why).
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'download-helpers.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'libmpdec-version') -Raw).Trim()
$Sha     = (Get-Content (Join-Path $ScriptDir 'libmpdec-sha256') -Raw).Trim().ToLower()

Get-PinnedSource `
    -ScriptDir $ScriptDir -Name 'libmpdec' -ExpectedSha256 $Sha `
    -Url "https://www.bytereef.org/software/mpdecimal/releases/mpdecimal-$Version.tar.gz" `
    -ArchiveName "mpdecimal-$Version.tar.gz" `
    -TargetDir "libmpdec\mpdecimal-$Version" `
    -WorkDir 'libmpdec'
