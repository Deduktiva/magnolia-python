# Download and unpack OpenSSL. Verified against the pinned SHA-256
# *and* the upstream .sha256 sidecar (defense-in-depth: the in-tree
# pin defends against a tampered upstream tarball+sidecar pair, the
# sidecar cross-check defends against a tampered in-tree pin).
#
# Keep this file ASCII-only (see download-helpers.ps1's note for why).
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'download-helpers.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'openssl-version') -Raw).Trim()
$Sha     = (Get-Content (Join-Path $ScriptDir 'openssl-sha256') -Raw).Trim().ToLower()
$BaseUrl = "https://github.com/openssl/openssl/releases/download/openssl-$Version"

Get-PinnedSource `
    -ScriptDir $ScriptDir -Name 'openssl' -ExpectedSha256 $Sha `
    -Url "$BaseUrl/openssl-$Version.tar.gz" `
    -ArchiveName "openssl-$Version.tar.gz" `
    -TargetDir "openssl\openssl-$Version" `
    -WorkDir 'openssl' `
    -SidecarUrl "$BaseUrl/openssl-$Version.tar.gz.sha256"
