#!/usr/bin/env bash
# Verify that every .c/.S/.h file referenced by MagPython/LibFFI.vcxproj
# exists in the build-time-downloaded libffi tree.
#
# Catches the case where upstream renamed/removed a file that
# LibFFI.vcxproj still references — without this check, the drift only
# surfaces at the next Windows build when cl.exe / ml.exe fails with a
# C1083 ('cannot open source file') error.
#
# The corresponding "did upstream add NEW files we should compile" check
# is harder to automate without baseline drift bookkeeping (the pre-
# devendor MagPython/update-libffi.sh did this, but the baseline tree
# is gone now). For the libffi 3.x line the per-file <ClCompile> list is
# stable, so the GONE-only check is the practical compromise.
#
# Run by .github/workflows/Verify libffi drift.yml on any PR that
# touches MagPython/{libffi-version,libffi-sha256,LibFFI.vcxproj}. The
# workflow populates the cache (via setup_libffi) before running this.
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/libffi-version")"
SOURCE_DIR="$SCRIPT_DIR/libffi/libffi-$VERSION"
VCXPROJ="$SCRIPT_DIR/LibFFI.vcxproj"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: libffi cache not populated at $SOURCE_DIR" >&2
    echo "       Run \`. MagPython/build-common.sh; setup_libffi\` first." >&2
    exit 1
fi
[ -f "$VCXPROJ" ] || { echo "ERROR: missing $VCXPROJ" >&2; exit 1; }

# Pull the path attribute from each Include="..." entry that points
# into the build tree (variable-prefixed and ending in .c/.S/.h). The
# vcxproj uses Windows backslashes; the loop below converts them.
missing=0
total=0
while IFS= read -r path; do
    total=$((total + 1))
    # NOTE: single quotes preserve a literal single backslash. The
    # vcxproj source uses one backslash between the variable and the
    # path component (Include="$(VAR)\foo.h") — earlier versions of
    # this script used '\\' which is two literal backslashes inside
    # single quotes and silently never matched, falling through to
    # the *) default and reporting a false-positive "all refs OK".
    case "$path" in
        '$(LibFFIGeneratedIncludeDir)\'*|'$(LibFFIGeneratedBuildDir)\'*)
            # ffi.h and fficonfig.h: produced by ./configure at build
            # time, don't exist on the Linux drift-check host.
            continue
            ;;
        '$(LibFFITargetSourceDir)\'*)
            ref="$SOURCE_DIR/src/x86/${path#'$(LibFFITargetSourceDir)\'}"
            ;;
        '$(LibFFISourceDir)\'*)
            ref="$SOURCE_DIR/src/${path#'$(LibFFISourceDir)\'}"
            ;;
        '$(SourceDir)\'*)
            ref="$SOURCE_DIR/${path#'$(SourceDir)\'}"
            ;;
        *)
            # Skip ClCompile/ClInclude items that don't point into our
            # source-variable namespace (none expected today, but leave
            # the door open).
            continue
            ;;
    esac
    # Convert any remaining backslashes to forward slashes for the
    # filesystem check.
    ref="${ref//\\//}"
    if [ ! -f "$ref" ]; then
        echo "MISSING: $path -> $ref"
        missing=$((missing + 1))
    fi
done < <(grep -oE 'Include="\$\([^)]+\)\\[^"]+\.[chS]"' "$VCXPROJ" | sed -E 's/^Include="//; s/"$//')

if [ "$missing" -gt 0 ]; then
    echo
    echo "ERROR: $missing of $total LibFFI.vcxproj refs missing from libffi $VERSION."
    echo
    echo "Upstream renamed/removed files in this version — LibFFI.vcxproj needs"
    echo "editing to match the new tree layout."
    exit 1
fi

echo "OK: all $total LibFFI.vcxproj refs resolve in libffi $VERSION."
