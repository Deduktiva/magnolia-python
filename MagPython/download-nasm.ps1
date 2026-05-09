# Download and unpack netwide assembler. Mirrors download-libmpdec.ps1's
# idempotent extract-once pattern: subsequent runs no-op when the cache
# is warm, so MSBuild incremental builds don't re-fetch the zip.
#
# The version + expected SHA-256 are read from sibling files
# (nasm-version, nasm-sha256). nasm.us doesn't publish per-zip .sha256
# sidecars, so the in-tree pin is the sole hash check (run
# update-nasm.sh to regenerate after a version bump).
#
# Keep this file ASCII-only. Without a UTF-8 BOM, powershell.exe on
# Windows reads .ps1 sources as Windows-1252; a UTF-8 em-dash (0xE2 0x80
# 0x94) decodes to "a..." with 0x94 as a right-double-quote that
# prematurely terminates whatever string it's inside, and the parser
# blows up several lines later with a misleading error.
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'sha256.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'nasm-version') -Raw).Trim()
$ExpectedSha256 = (Get-Content (Join-Path $ScriptDir 'nasm-sha256') -Raw).Trim().ToLower()
$Zip = "nasm-$Version-win32.zip"
$Url = "https://www.nasm.us/pub/nasm/releasebuilds/$Version/win32/$Zip"
# Stage the extracted tree as MagPython/nasm/ (unversioned) rather
# than nasm-<version>/ so the openssl.vcxproj NMakeBuildCommandLine's
# `set PATH=$(MSBuildProjectDirectory)\nasm;%PATH%` line stays stable
# across nasm bumps.
$ExtractDir = Join-Path $ScriptDir "nasm"

if (Test-Path $ExtractDir) { exit 0 }

Push-Location $ScriptDir
try {
    if (Test-Path $Zip) { Remove-Item -Force $Zip }

    Invoke-WebRequest -OutFile $Zip -Uri $Url

    $actual = Get-Sha256Hex (Join-Path $PWD.Path $Zip)
    if ($ExpectedSha256 -ne $actual) {
        Remove-Item -Force $Zip
        throw "SHA-256 mismatch for ${Zip}: expected $ExpectedSha256, got $actual (pinned in MagPython/nasm-sha256 -- regenerate via MagPython/update-nasm.sh before changing)"
    }

    # tar.exe on Windows 10+ uses libarchive and handles .zip too;
    # Expand-Archive (which the previous version of this script used)
    # is in Microsoft.PowerShell.Archive, which isn't guaranteed to be
    # auto-loaded under MSBuild's powershell -NonInteractive -file ...
    # invocation. Same module-loading concern as Get-FileHash; tar.exe
    # has no such dependency.
    & tar.exe -xf $Zip
    if ($LASTEXITCODE -ne 0) { throw "tar -xf $Zip failed" }

    # Upstream extracts to nasm-<version>/. Rename to nasm/ so the
    # openssl.vcxproj PATH addition sees a stable location.
    if (Test-Path "nasm-$Version") {
        Move-Item -Path "nasm-$Version" -Destination "nasm"
    }
    Remove-Item -Force $Zip
} finally { Pop-Location }
