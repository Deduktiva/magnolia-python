#!/usr/bin/env bash
# Update the vendored libffi/ tree to a new 3.x release.
#
# Usage: MagPython/update-libffi.sh <version>
#   e.g. MagPython/update-libffi.sh 3.5.2
#
# Refuses to run if <version> is not on the libffi 3.x line. Downloads
# the release tarball from the matching libffi/libffi GitHub release
# tag and replaces the contents of libffi/ in place. libffi does not
# publish .sha256 sidecars on its GitHub releases, so no upstream-
# anchored hash check is possible — we trust HTTPS to GitHub plus the
# immutability of release artifacts. The SHA-256 of the downloaded
# tarball is printed for the record (paste it into the commit
# message) but not verified.
#
# libffi/msvc_build/x86_win32/include/ holds two pre-built MSVC
# headers that are NOT part of the upstream tarball — upstream ships
# only msvc_build/aarch64/, never the x86 Windows variant:
#
#   * ffi.h — regenerated from upstream's include/ffi.h.in by this
#     script after each import. The substitutions are stable for our
#     x86_win32 build (no long double, no Apple trampoline table) so
#     it stays in sync with each new libffi version automatically.
#
#   * fficonfig.h — the autoheader output for an x86_win32 build,
#     committed once at libffi import time and preserved across
#     upgrades by this script. If upstream's fficonfig.h.in template
#     changes (e.g. new feature flags get added in a minor bump), the
#     script will warn so the project-local copy can be regenerated
#     by hand.
#
# Also reports drift between MagPython/LibFFI.vcxproj's referenced
# .c/.S/.h files and the new tree, with the previous tree's
# intentional exclusions subtracted as a baseline so each run only
# surfaces drift introduced by *this* upgrade.
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <libffi-version-on-3.x-line>" >&2
    echo "  e.g.  $0 3.5.2" >&2
    exit 64
fi

case "$VERSION" in
    3.[0-9]*) ;;
    *)
        echo "Refusing to update: '$VERSION' is not on the libffi 3.x line." >&2
        echo "A 4.x bump would need a manual review of the build glue." >&2
        exit 65
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIBFFI_DIR="$REPO_ROOT/libffi"
VCXPROJ="$SCRIPT_DIR/LibFFI.vcxproj"
LOCAL_HEADERS_DIR="msvc_build/x86_win32/include"

# Used only to print the SHA of the downloaded tarball for the record.
if command -v shasum >/dev/null 2>&1; then
    SHA256="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    SHA256="sha256sum"
else
    SHA256=""
fi

TARBALL="libffi-${VERSION}.tar.gz"
URL="https://github.com/libffi/libffi/releases/download/v${VERSION}/${TARBALL}"

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t libffi-update)"
trap 'rm -rf "$TMP"' EXIT

# The directories LibFFI.vcxproj pulls files from for the x86_win32 build.
# msvc_build/x86_win32/include/ is included in the comparison set even
# though it's project-local — after the script regenerates ffi.h and
# restores fficonfig.h, both end up in the tree where the vcxproj
# expects them, so the drift comparison is well-defined.
COVERED_DIRS="src src/x86 include $LOCAL_HEADERS_DIR"

# Filenames in LibFFI.vcxproj that the build references. Anchored to
# Include="..." attributes so we don't pick up unrelated tokens from
# the XML namespace URL or the custom-build cl invocation.
VCXPROJ_FILES="$TMP/vcxproj-files.txt"
grep -oE 'Include="[^"]+"' "$VCXPROJ" \
    | sed -E 's,.*[\\/],,; s,"$,,' \
    | grep -E '\.(c|h|S)$' \
    | sort -u > "$VCXPROJ_FILES"

# List basenames of .c/.S/.h files in the covered directories of <tree>.
list_covered() {
    local tree="$1"
    local out="$2"
    if [ ! -d "$tree" ]; then
        : > "$out"
        return 0
    fi
    : > "$out"
    local d
    for d in $COVERED_DIRS; do
        if [ -d "$tree/$d" ]; then
            (
                cd "$tree/$d"
                find . -maxdepth 1 \
                    \( -name '*.c' -o -name '*.h' -o -name '*.S' \) \
                    -print
            ) | sed 's,^\./,,' >> "$out"
        fi
    done
    sort -u -o "$out" "$out"
}

# Files in <tree>'s covered dirs that are NOT referenced by the vcxproj —
# the intentional-exclusion set.
unlisted_in_tree() {
    local tree="$1"
    local out="$2"
    local tag="$3"

    local all="$TMP/tree-$tag.txt"
    list_covered "$tree" "$all"
    comm -23 "$all" "$VCXPROJ_FILES" > "$out"
}

BASELINE_UNLISTED="$TMP/baseline-unlisted.txt"
unlisted_in_tree "$LIBFFI_DIR" "$BASELINE_UNLISTED" "old"

# Stash the project-local fficonfig.h and the previous version's
# fficonfig.h.in template so we can restore the former and diff the
# latter once the new tree is in place.
LOCAL_FFICONFIG_H="$TMP/fficonfig.h.local"
PREV_FFICONFIG_TEMPLATE="$TMP/fficonfig.h.in.prev"
if [ -f "$LIBFFI_DIR/$LOCAL_HEADERS_DIR/fficonfig.h" ]; then
    cp "$LIBFFI_DIR/$LOCAL_HEADERS_DIR/fficonfig.h" "$LOCAL_FFICONFIG_H"
fi
if [ -f "$LIBFFI_DIR/fficonfig.h.in" ]; then
    cp "$LIBFFI_DIR/fficonfig.h.in" "$PREV_FFICONFIG_TEMPLATE"
fi

echo "Downloading $TARBALL ..."
echo "  GET $URL"
curl --fail --silent --show-error --location --output "$TMP/$TARBALL" "$URL"

if [ -n "$SHA256" ]; then
    ACTUAL_SHA256="$($SHA256 "$TMP/$TARBALL" | awk '{print $1}')"
    echo "  SHA-256: $ACTUAL_SHA256"
fi

echo "Extracting ..."
mkdir -p "$TMP/extract"
tar -xzf "$TMP/$TARBALL" -C "$TMP/extract"
SRC="$TMP/extract/libffi-${VERSION}"
if [ ! -d "$SRC" ]; then
    echo "Unexpected tarball layout: $SRC missing" >&2
    exit 71
fi

echo "Replacing $LIBFFI_DIR ..."
rm -rf "$LIBFFI_DIR"
mkdir -p "$LIBFFI_DIR"
( cd "$SRC" && tar -cf - . ) | ( cd "$LIBFFI_DIR" && tar -xf - )

# Regenerate ffi.h from the upstream template. autoconf's configure
# normally substitutes these @VAR@ tokens; for our 32-bit Windows
# build the values are stable and known.
#
# Note on FFI_VERSION_NUMBER: libffi's configure.ac sets it as
#   FFI_VERSION_NUMBER=<major>*10000 + <minor>*100 + <patch>
# (e.g. 3.5.2 -> 30502). Older libffi versions (3.4.x) did not yet
# emit these two tokens, but sed substitutions for absent patterns
# are no-ops, so applying them unconditionally is safe.
IFS=. read -r FFI_MAJ FFI_MIN FFI_PAT <<EOF
$VERSION
EOF
FFI_VERSION_NUMBER=$(( FFI_MAJ * 10000 + FFI_MIN * 100 + ${FFI_PAT:-0} ))

FFI_H_TEMPLATE="$LIBFFI_DIR/include/ffi.h.in"
GEN_FFI_H="$LIBFFI_DIR/$LOCAL_HEADERS_DIR/ffi.h"
if [ ! -f "$FFI_H_TEMPLATE" ]; then
    echo "ERROR: upstream tarball is missing include/ffi.h.in — refusing to" >&2
    echo "       regenerate ffi.h. Aborting." >&2
    exit 73
fi
mkdir -p "$LIBFFI_DIR/$LOCAL_HEADERS_DIR"
sed \
    -e "s/@VERSION@/${VERSION}/g" \
    -e "s/@FFI_VERSION_STRING@/${VERSION}/g" \
    -e "s/@FFI_VERSION_NUMBER@/${FFI_VERSION_NUMBER}/g" \
    -e 's/@TARGET@/X86_WIN32/g' \
    -e 's/@HAVE_LONG_DOUBLE@/0/g' \
    -e 's/@FFI_EXEC_TRAMPOLINE_TABLE@/0/g' \
    "$FFI_H_TEMPLATE" > "$GEN_FFI_H"
if grep -nE '@[A-Z_][A-Z0-9_]*@' "$GEN_FFI_H" >/dev/null 2>&1; then
    echo "ERROR: unresolved @VAR@ tokens in generated ffi.h — upstream" >&2
    echo "       template has gained new substitutions. Inspect:" >&2
    grep -nE '@[A-Z_][A-Z0-9_]*@' "$GEN_FFI_H" | sed 's/^/  /' >&2
    exit 74
fi
echo "  Regenerated $LOCAL_HEADERS_DIR/ffi.h from include/ffi.h.in"

# Restore the project-local fficonfig.h. fficonfig.h.in is autoheader
# output and translating it would mean re-running configure on a host
# that can build libffi natively, so we keep the previously committed
# x86_win32 fficonfig.h and warn if the template has shifted.
if [ -f "$LOCAL_FFICONFIG_H" ]; then
    cp "$LOCAL_FFICONFIG_H" "$LIBFFI_DIR/$LOCAL_HEADERS_DIR/fficonfig.h"
    echo "  Restored project-local $LOCAL_HEADERS_DIR/fficonfig.h"
else
    echo "  WARNING: no previous fficonfig.h to restore — the build will fail" >&2
    echo "           until $LOCAL_HEADERS_DIR/fficonfig.h is provided." >&2
fi

if [ -f "$PREV_FFICONFIG_TEMPLATE" ] && [ -f "$LIBFFI_DIR/fficonfig.h.in" ]; then
    if ! cmp -s "$PREV_FFICONFIG_TEMPLATE" "$LIBFFI_DIR/fficonfig.h.in"; then
        echo ""
        echo "  WARNING: upstream fficonfig.h.in changed between the previous"
        echo "  libffi version and $VERSION. The preserved project-local"
        echo "  fficonfig.h may be stale. Inspect the template diff and, if"
        echo "  needed, regenerate fficonfig.h on a Linux/macOS host:"
        echo ""
        echo "    cd <fresh libffi-${VERSION}>"
        echo "    ./configure --host=i686-w64-mingw32 --enable-static"
        echo "    cp fficonfig.h <repo>/libffi/$LOCAL_HEADERS_DIR/"
        echo ""
        echo "  Template diff:"
        diff -u "$PREV_FFICONFIG_TEMPLATE" "$LIBFFI_DIR/fficonfig.h.in" \
            | sed 's/^/    /' | head -40
    fi
fi

# ---------------------------------------------------------------------------
# Sanity-check LibFFI.vcxproj's referenced files against the new tree.
# ---------------------------------------------------------------------------
echo ""
echo "Checking MagPython/LibFFI.vcxproj file references ..."

POST_UNLISTED="$TMP/post-unlisted.txt"
unlisted_in_tree "$LIBFFI_DIR" "$POST_UNLISTED" "new"

TREE_NEW_ALL="$TMP/tree-new-all.txt"
list_covered "$LIBFFI_DIR" "$TREE_NEW_ALL"

NEW_FILES="$(comm -23 "$POST_UNLISTED" "$BASELINE_UNLISTED" || true)"
GONE_FILES="$(comm -13 "$TREE_NEW_ALL" "$VCXPROJ_FILES"     || true)"

if [ -n "$NEW_FILES" ]; then
    echo ""
    echo "  New .c/.S/.h files (added by this upgrade) in libffi's"
    echo "  covered dirs that are NOT referenced by LibFFI.vcxproj."
    echo "  Review each — add to the matching <ClCompile>/<ClInclude>/"
    echo "  <CustomBuild> ItemGroup, or confirm it is intentionally"
    echo "  excluded (e.g. 64-bit variants, GNU-asm-syntax .S files,"
    echo "  or features the project does not enable):"
    echo "$NEW_FILES" | sed 's/^/    /'
fi
if [ -n "$GONE_FILES" ]; then
    echo ""
    echo "  Files referenced by LibFFI.vcxproj that NO LONGER exist in"
    echo "  the libffi tree's covered dirs (these will break the build —"
    echo "  remove or rename in LibFFI.vcxproj):"
    echo "$GONE_FILES" | sed 's/^/    /'
fi
if [ -z "$NEW_FILES" ] && [ -z "$GONE_FILES" ]; then
    echo "  No new drift relative to the previous tree."
fi

echo ""
echo "Done. libffi $VERSION imported into $LIBFFI_DIR"
echo "Next steps:"
echo "  1. Update the libffi version in README.md (vendored-libraries table)."
echo "  2. Reconcile any drift reported above in MagPython/LibFFI.vcxproj."
echo "  3. Run a full Windows build to confirm the new tree compiles."
echo "  4. Commit with: git add libffi MagPython README.md"
echo "                  git commit -m 'Import unpacked libffi $VERSION'"
