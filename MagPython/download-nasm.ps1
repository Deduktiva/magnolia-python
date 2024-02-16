# Download and unpack netwide assembler.
$ErrorActionPreference = "Stop"
$Version = "2.16.01"
if (!(Test-Path nasm)) {
    if (Test-Path nasm.zip) { del -force nasm.zip }
    Invoke-WebRequest -OutFile nasm.zip -Uri "https://www.nasm.us/pub/nasm/releasebuilds/$Version/win32/nasm-$Version-win32.zip"
    if (Test-Path nasm-$Version) { del -recurse -force nasm-$Version }
    Expand-Archive -Path nasm.zip -DestinationPath .
    ren nasm-$Version nasm
}
