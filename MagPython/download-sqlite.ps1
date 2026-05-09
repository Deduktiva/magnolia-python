# Download and unpack the SQLite amalgamation. Three pin files
# (version + year + SHA-256) are needed because sqlite.org's URL
# embeds a calendar-year segment that isn't derivable from the
# version (see https://sqlite.org/chronology.html).
#
# Upstream's zip extracts to sqlite-amalgamation-<numeric>/. Renamed
# to sqlite-<version>/ so SQLite.vcxproj's BuildDir can refer to it
# via $(SQLiteVersion) without recomputing the numeric encoding.
#
# Keep this file ASCII-only (see download-helpers.ps1's note for why).
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'download-helpers.ps1')

$Version = (Get-Content (Join-Path $ScriptDir 'sqlite-version') -Raw).Trim()
$Year    = (Get-Content (Join-Path $ScriptDir 'sqlite-year') -Raw).Trim()
$Sha     = (Get-Content (Join-Path $ScriptDir 'sqlite-sha256') -Raw).Trim().ToLower()

# Compute the numeric encoding sqlite.org's URL embeds.
$parts   = $Version.Split('.')
$Numeric = '{0:D7}' -f ([int]$parts[0] * 1000000 + [int]$parts[1] * 10000 + [int]$parts[2] * 100)

Get-PinnedSource `
    -ScriptDir $ScriptDir -Name 'sqlite' -ExpectedSha256 $Sha `
    -Url "https://sqlite.org/$Year/sqlite-amalgamation-$Numeric.zip" `
    -ArchiveName "sqlite-amalgamation-$Numeric.zip" `
    -TargetDir "sqlite\sqlite-$Version" `
    -WorkDir 'sqlite' `
    -RenameFrom "sqlite-amalgamation-$Numeric" -RenameTo "sqlite-$Version" `
    -TarFlags '-xf'
