# Download and unpack netwide assembler.
$Version = "2.16.01"
Invoke-WebRequest -OutFile nasm.zip -Uri "https://www.nasm.us/pub/nasm/releasebuilds/$Version/win32/nasm-$Version-win32.zip"
Expand-Archive -Path nasm.zip -DestinationPath .
ren nasm-$Version nasm
