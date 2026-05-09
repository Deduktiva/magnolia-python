# Download and unpack CPython. The GitHub tag archive is signed-by-HTTPS
# and immutable per-tag — same source the pre-devendor in-tree
# update-python.sh used. python.org publishes a release tarball with
# .sigstore signatures we could fold in later; the in-tree SHA-256 pin
# (verified at build time AND on every PR by the cache key) provides
# equivalent integrity.
#
# Upstream tag archive extracts to cpython-<version>/. Renamed to
# python-<version>/ so $(PythonSourceDir) in the vcxprojs has a
# stable shape across version bumps without per-bump edits.
#
# Keep this file ASCII-only (see download-helpers.ps1's note for why).
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'download-helpers.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'python-version') -Raw).Trim()
$Sha     = (Get-Content (Join-Path $ScriptDir 'python-sha256') -Raw).Trim().ToLower()

Get-PinnedSource `
    -ScriptDir $ScriptDir -Name 'python' -ExpectedSha256 $Sha `
    -Url "https://github.com/python/cpython/archive/refs/tags/v$Version.tar.gz" `
    -ArchiveName "cpython-$Version.tar.gz" `
    -TargetDir "python\python-$Version" `
    -WorkDir 'python' `
    -RenameFrom "cpython-$Version" -RenameTo "python-$Version"
