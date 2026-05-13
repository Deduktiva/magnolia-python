#!/usr/bin/env bash
# Update the libffi pin files (MagPython/libffi-version,
# MagPython/libffi-sha256) AND regenerate the project-local
# MagPython/libffi-msvc-include/{x86,x64}/ffi.h to a new release on
# the 3.x line.
#
# Usage: MagPython/update-libffi.sh <version>
#   e.g. MagPython/update-libffi.sh 3.5.3
#
# Two halves:
#   1. update_pin (shared with the other devendored deps): downloads
#      the tarball, validates SHA-256, writes the two pin files.
#   2. Inline regen of MagPython/libffi-msvc-include/x86/ffi.h and
#      .../x64/ffi.h from upstream's include/ffi.h.in template. autoconf
#      normally does these @VAR@ substitutions at ./configure time;
#      upstream doesn't ship a Windows configure equivalent for
#      x86_win32 / x86_win64, so we do it here. The two committed ffi.h
#      files are what LibFFI.vcxproj's <ClInclude> picks up at build
#      time (the include dir is selected by $(Platform)).
#
#   Also prints the current MagPython/libffi-msvc-include/{x86,x64}/fficonfig.h
#   diff target if upstream's fficonfig.h.in template has changed —
#   regenerating fficonfig.h needs a real configure run on a
#   Linux/macOS host (see README's "Updating pinned libffi").
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/update-pin-common.sh"

update_pin \
    --name libffi \
    --version-pattern '3.[0-9]*.[0-9]*' \
    --version-pattern-help '3.x line' \
    --tarball-url 'https://github.com/libffi/libffi/releases/download/v<v>/libffi-<v>.tar.gz' \
    "$@"

# update_pin already validated and wrote the pin files. Now regenerate
# ffi.h. The version is whatever update_pin just wrote.
VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/libffi-version")"
CACHE="$SCRIPT_DIR/libffi"
SRC="$CACHE/libffi-$VERSION"

# Reuse the build-time cache if it's already populated (a previous
# build, or a previous run of this script). Otherwise download +
# extract — the same operation setup_libffi does at build time, but
# we need it now to read upstream's include/ffi.h.in template.
if [ ! -d "$SRC" ]; then
    echo ""
    echo "Fetching libffi $VERSION for ffi.h template regen..."
    mkdir -p "$CACHE"
    tarball="$CACHE/libffi-$VERSION.tar.gz"
    if [ ! -f "$tarball" ]; then
        curl --fail --silent --show-error --location \
            -o "$tarball" \
            "https://github.com/libffi/libffi/releases/download/v$VERSION/libffi-$VERSION.tar.gz"
    fi
    tar -xzf "$tarball" -C "$CACHE"
fi

template="$SRC/include/ffi.h.in"
if [ ! -f "$template" ]; then
    echo "ERROR: missing $template — refusing to regenerate ffi.h." >&2
    exit 73
fi

# FFI_VERSION_NUMBER is libffi's configure.ac convention:
#   <major>*10000 + <minor>*100 + <patch>
# (e.g. 3.5.2 -> 30502). Older libffi (3.4.x and earlier) didn't emit
# the @FFI_VERSION_*@ tokens, but a sed substitution for an absent
# pattern is a no-op so applying them unconditionally is safe.
IFS=. read -r FFI_MAJ FFI_MIN FFI_PAT <<EOF
$VERSION
EOF
FFI_VERSION_NUMBER=$(( FFI_MAJ * 10000 + FFI_MIN * 100 + ${FFI_PAT:-0} ))

# Abort if upstream introduces a new @VAR@ token we don't substitute —
# silently passing one through would write a malformed ffi.h that the
# Windows build would only fail on, with a confusing error.
unknown_tokens="$(grep -oE '@[A-Z_][A-Z0-9_]*@' "$template" \
    | sort -u \
    | grep -vE '^@(VERSION|TARGET|HAVE_LONG_DOUBLE|FFI_EXEC_TRAMPOLINE_TABLE|FFI_VERSION_STRING|FFI_VERSION_NUMBER)@$' \
    || true)"
if [ -n "$unknown_tokens" ]; then
    echo "ERROR: $template introduces unknown @VAR@ tokens:" >&2
    printf '  %s\n' $unknown_tokens >&2
    echo "Update update-libffi.sh's substitution list before bumping." >&2
    exit 74
fi

# Regenerate one ffi.h per arch. The @TARGET@ token picks the codepath
# inside libffi at compile time: X86_WIN32 for the 32-bit Win32 build,
# X86_WIN64 for the 64-bit AMD64 build. Everything else is identical
# (libffi's ffi.h is mostly type/macro definitions that aren't
# arch-conditional in the template).
for arch in x86 x64; do
    case "$arch" in
        x86) target=X86_WIN32 ;;
        x64) target=X86_WIN64 ;;
    esac

    out="$SCRIPT_DIR/libffi-msvc-include/$arch/ffi.h"
    mkdir -p "$(dirname "$out")"
    sed \
        -e "s/@VERSION@/${VERSION}/g" \
        -e "s/@FFI_VERSION_STRING@/${VERSION}/g" \
        -e "s/@FFI_VERSION_NUMBER@/${FFI_VERSION_NUMBER}/g" \
        -e "s/@TARGET@/${target}/g" \
        -e 's/@HAVE_LONG_DOUBLE@/0/g' \
        -e 's/@FFI_EXEC_TRAMPOLINE_TABLE@/0/g' \
        "$template" > "$out"

    # Sanity-check: any @VAR@ tokens still in the output mean we missed
    # one in the substitution pass above.
    if grep -nE '@[A-Z_][A-Z0-9_]*@' "$out" >/dev/null 2>&1; then
        echo "ERROR: unsubstituted @VAR@ tokens remain in regenerated ffi.h:" >&2
        grep -nE '@[A-Z_][A-Z0-9_]*@' "$out" >&2
        exit 75
    fi

    echo ""
    echo "Regenerated MagPython/libffi-msvc-include/$arch/ffi.h from upstream template."
done

# fficonfig.h is autoheader output that depends on autoconf
# feature-detection results, so we can't substitute tokens by hand
# the way ffi.h works. If upstream's fficonfig.h.in template has
# changed since the previous bump, the project-local fficonfig.h
# variants may need to be regenerated by hand on a Linux/macOS host.
template="$SRC/fficonfig.h.in"
if [ -f "$template" ]; then
    echo ""
    echo "If MagPython/libffi-msvc-include/{x86,x64}/fficonfig.h needs updating,"
    echo "regenerate them on a Linux/macOS host (one configure run per arch):"
    echo "  cd $SRC"
    echo "  ./configure --host=i686-w64-mingw32 --enable-static"
    echo "  cp fficonfig.h $SCRIPT_DIR/libffi-msvc-include/x86/fficonfig.h"
    echo "  ./configure --host=x86_64-w64-mingw32 --enable-static"
    echo "  cp fficonfig.h $SCRIPT_DIR/libffi-msvc-include/x64/fficonfig.h"
fi

echo ""
echo "Next steps:"
echo "  1. Run a full Windows + Linux + macOS build to confirm the new"
echo "     version compiles. The build cross-checks the downloaded"
echo "     tarball against the SHA in MagPython/libffi-sha256."
echo "  2. Commit pin + regenerated header(s) together:"
echo "       git add MagPython/libffi-version MagPython/libffi-sha256 \\"
echo "               MagPython/libffi-msvc-include/"
echo "       git commit -m 'Bump libffi pin to $VERSION'"
