#!/usr/bin/env bash
# Run upstream libffi's ./configure under MSVC and write fficonfig.h +
# include/ffi.h for the requested MSBuild Platform.
#
# Usage: build-libffi-msvc-headers.sh <Win32|x64>
#
# Invoked by LibFFI.vcxproj's RegenLibffiMsvcHeaders target. The recipe
# is the one upstream's README documents for MSVC: msvcc.sh wraps cl.exe,
# LD=link, CPP/CXXCPP delegate to `cl -EP`. libffi's configure.host
# picks X86_WIN32 vs X86_WIN64 from sizeof(size_t), so 32/64 just needs
# -m64 on the msvcc.sh CC + a matching autoconf --build hint.
#
# Out-of-tree builddir (magpython-msvc-build-$Platform/) so x86 and x64
# outputs don't share state when both Platforms are built from the same
# checkout. configure alone is enough — AC_CONFIG_HEADERS writes
# fficonfig.h, AC_CONFIG_FILES sed-substitutes include/ffi.h. No `make`.
# Idempotent: re-runs skip if outputs are newer than the inputs.

set -eu
set -x

PLATFORM="${1:-}"
case "$PLATFORM" in
    Win32)
        MSVCC_FLAGS=""
        BUILD_TRIPLE=""
        ;;
    x64)
        # -m64 tells msvcc.sh to target 64-bit. --build=x86_64-pc-mingw64
        # is the recipe upstream's docs point at for x64 ("you may also
        # need to specify --build appropriately"); it gives autoconf a
        # 64-bit Windows host to anchor its probes against without
        # affecting MSVC compiler invocation.
        MSVCC_FLAGS="-m64"
        BUILD_TRIPLE="--build=x86_64-pc-mingw64"
        ;;
    *)
        echo "Usage: $0 <Win32|x64>" >&2
        exit 64
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/libffi-version")"
SRC="$SCRIPT_DIR/libffi/libffi-$VERSION"
BUILDDIR="$SRC/magpython-msvc-build-$PLATFORM"

if [ ! -d "$SRC" ]; then
    echo "ERROR: libffi source tree missing at $SRC" >&2
    echo "       LibFFI.vcxproj's DownloadLibffi target runs before this" >&2
    echo "       step and should have extracted it." >&2
    exit 73
fi
if [ ! -f "$SRC/configure" ]; then
    echo "ERROR: $SRC/configure missing — upstream tarball corrupt?" >&2
    exit 74
fi
if [ ! -f "$SRC/msvcc.sh" ]; then
    echo "ERROR: $SRC/msvcc.sh missing — required as the MSVC wrapper for CC" >&2
    exit 75
fi
if [ ! -f "$SRC/include/ffi.h.in" ]; then
    echo "ERROR: $SRC/include/ffi.h.in missing — upstream restructured?" >&2
    exit 76
fi

out_fficonfig="$BUILDDIR/fficonfig.h"
out_ffi_h="$BUILDDIR/include/ffi.h"

# Idempotency check: skip configure if both outputs already exist and
# are newer than the upstream inputs. configure itself is the cheapest
# witness for "the tarball was re-extracted since the last run" — its
# mtime resets on re-extract.
if [ -f "$out_fficonfig" ] && [ -f "$out_ffi_h" ] \
   && [ "$out_fficonfig" -nt "$SRC/configure" ] \
   && [ "$out_ffi_h" -nt "$SRC/include/ffi.h.in" ]; then
    set +x
    echo "magpython-msvc-build-$PLATFORM/{fficonfig.h, include/ffi.h} up to date."
    exit 0
fi

# msvcc.sh wraps cl.exe; without cl on PATH the configure run dies deep
# inside an AC_PROG_CC probe with an opaque error. Surface the precondition
# up front instead.
if ! command -v cl.exe >/dev/null 2>&1 && ! command -v cl >/dev/null 2>&1; then
    echo "ERROR: cl.exe not on PATH. This script must run from an MSYS2 bash" >&2
    echo "       that inherits PATH from an enclosing VS Developer Command" >&2
    echo "       Prompt — in CI that's msys2/setup-msys2 with path-type:" >&2
    echo "       inherit after ilammy/msvc-dev-cmd; locally launch bash from" >&2
    echo "       a Native Tools Command Prompt." >&2
    exit 77
fi

# Tarball extraction on Windows can drop +x bits; msvcc.sh and configure
# both need to be executable from bash. Restoring +x is cheap and safe to
# repeat on each run.
chmod +x "$SRC/msvcc.sh" "$SRC/configure"

mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

# Assemble configure args as an array so the optional --build triple
# doesn't pass through as an empty positional arg when it's unset for x86.
configure_cc="$SRC/msvcc.sh"
if [ -n "$MSVCC_FLAGS" ]; then
    configure_cc="$SRC/msvcc.sh $MSVCC_FLAGS"
fi
configure_args=(
    CC="$configure_cc"
    CXX="$configure_cc"
    LD=link
    CPP="cl -nologo -EP"
    CXXCPP="cl -nologo -EP"
    CPPFLAGS="-DFFI_BUILDING_DLL"
    --enable-static
    --disable-shared
    --disable-docs
)
if [ -n "$BUILD_TRIPLE" ]; then
    configure_args+=("$BUILD_TRIPLE")
fi

"$SRC/configure" "${configure_args[@]}"

# Sanity-check outputs landed where AC_CONFIG_HEADERS/AC_CONFIG_FILES
# promise. If upstream restructures configure.ac to move these, the build
# would otherwise fail much later with cl.exe C1083 'cannot open ffi.h'.
[ -f "$out_fficonfig" ] || {
    echo "ERROR: configure did not write $out_fficonfig" >&2
    exit 78
}
[ -f "$out_ffi_h" ] || {
    echo "ERROR: configure did not write $out_ffi_h" >&2
    exit 79
}
