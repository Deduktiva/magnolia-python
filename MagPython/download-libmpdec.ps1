# Download and unpack libmpdec (mpdecimal). Mirrors download-nasm.ps1's
# idempotent extract-once pattern: subsequent runs no-op when the cache is
# warm, so MSBuild incremental builds don't re-fetch the tarball.
#
# The version is read from MagPython/libmpdec-version so common.props,
# build-common.sh (Linux/macOS), and this script all share one source of
# truth — bumping the pin is a one-file edit.
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Version = (Get-Content (Join-Path $ScriptDir 'libmpdec-version') -Raw).Trim()
$BaseUrl = "https://www.bytereef.org/software/mpdecimal/releases"
$Tarball = "mpdecimal-$Version.tar.gz"
$ExtractDir = Join-Path $ScriptDir "libmpdec\mpdecimal-$Version"

if (Test-Path $ExtractDir) { exit 0 }

Push-Location $ScriptDir
try {
    if (!(Test-Path libmpdec)) { New-Item -ItemType Directory -Path libmpdec | Out-Null }
    Push-Location libmpdec
    try {
        if (Test-Path $Tarball) { Remove-Item -Force $Tarball }
        if (Test-Path "$Tarball.sha256") { Remove-Item -Force "$Tarball.sha256" }

        Invoke-WebRequest -OutFile $Tarball         -Uri "$BaseUrl/$Tarball"
        Invoke-WebRequest -OutFile "$Tarball.sha256" -Uri "$BaseUrl/$Tarball.sha256"

        # SHA-256 sidecar format: "<hex>  <filename>" (GNU coreutils).
        $expected = (Get-Content "$Tarball.sha256" -First 1).Split()[0].ToLower()
        $actual = (Get-FileHash -Algorithm SHA256 $Tarball).Hash.ToLower()
        if ($expected -ne $actual) {
            throw "SHA-256 mismatch for ${Tarball}: expected $expected, got $actual"
        }

        # tar.exe ships in modern Windows (10 1803+, Server 2019+) and is
        # available on the GitHub windows-2025 runner. Avoids pulling in a
        # third-party PowerShell archive cmdlet for tar.gz support.
        & tar.exe -xzf $Tarball
        if ($LASTEXITCODE -ne 0) { throw "tar -xzf $Tarball failed" }
    } finally { Pop-Location }
} finally { Pop-Location }
