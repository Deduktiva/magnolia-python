# Download and unpack jom — Qt's drop-in nmake replacement that supports
# parallel jobs (-j). Microsoft's nmake is single-threaded; jom + cl spawns
# one cl process per CPU core, cutting an OpenSSL build from ~6 minutes
# to under 2 on a 4-core runner.
$ErrorActionPreference = "Stop"
$Version = "1.1.4"
if (!(Test-Path jom)) {
    if (Test-Path jom.zip) { del -force jom.zip }
    Invoke-WebRequest -OutFile jom.zip -Uri "https://download.qt.io/official_releases/jom/jom_$($Version -replace '\.','_').zip"
    Expand-Archive -Path jom.zip -DestinationPath jom
}
