# Shared SHA-256 helper for the download-*.ps1 scripts. Dot-source
# this file and call Get-Sha256Hex with an absolute path.
#
# Why not Get-FileHash: on the windows-2025 GitHub runner, MSBuild's
# `powershell.exe -NonInteractive -file ...` invocation reports
# Get-FileHash as "not recognized as a cmdlet" (the Microsoft.PowerShell.Utility
# module isn't auto-loaded under that invocation form). The .NET API
# below has no module-loading dependency and works under any
# PowerShell / runner combination.
#
# Callers pass an absolute path: .NET APIs use the .NET CWD, not
# PowerShell's Push-Location-tracked CWD, so a relative path here
# would resolve against the wrong directory and silently fail.
#
# Keep this file ASCII-only. Without a UTF-8 BOM, powershell.exe on
# Windows reads .ps1 sources as Windows-1252; a UTF-8 em-dash (0xE2 0x80
# 0x94) decodes to "a..." with 0x94 as a right-double-quote that
# prematurely terminates whatever string it's inside, and the parser
# blows up several lines later with a misleading error.

function Get-Sha256Hex {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $hashBytes = $sha.ComputeHash($stream)
    } finally {
        $stream.Dispose()
    }
    return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLower()
}
