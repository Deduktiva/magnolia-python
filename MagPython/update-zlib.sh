#!/usr/bin/env bash
# Update the vendored zlib/ tree to a new 1.x release.
#
# Usage: MagPython/update-zlib.sh <version>
#   e.g. MagPython/update-zlib.sh 1.3.1
#
# Refuses to run if <version> is not on the zlib 1.x line. Downloads the
# release tarball from the matching madler/zlib GitHub release tag and
# replaces the contents of zlib/ in place. zlib does not publish .sha256
# sidecars on its GitHub releases, so no upstream-anchored hash check is
# possible — we trust HTTPS to GitHub plus the immutability of release
# artifacts. The SHA-256 of the downloaded tarball is printed for the
# record (paste it into the commit message) but not verified.
#
# Also reports drift between MagPython/MagPython.vcxproj's zlib .c/.h
# references and the new tree, with the previous tree's intentional
# exclusions (the gz* family, etc.) subtracted so each run only surfaces
# drift introduced by *this* upgrade.
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <zlib-version-on-1.x-line>" >&2
    echo "  e.g.  $0 1.3.1" >&2
    exit 64
fi

case "$VERSION" in
    1.[0-9]*) ;;
    *)
        echo "Refusing to update: '$VERSION' is not on the zlib 1.x line." >&2
        echo "A 2.x bump would need a manual review of the build glue." >&2
        exit 65
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZLIB_DIR="$REPO_ROOT/zlib"
VCXPROJ="$SCRIPT_DIR/MagPython.vcxproj"

# Used only to print the SHA of the downloaded tarball for the record.
if command -v shasum >/dev/null 2>&1; then
    SHA256="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    SHA256="sha256sum"
else
    SHA256=""
fi

TARBALL="zlib-${VERSION}.tar.gz"
URL="https://github.com/madler/zlib/releases/download/v${VERSION}/${TARBALL}"

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t zlib-update)"
trap 'rm -rf "$TMP"' EXIT

# Extract the .c/.h files MagPython.vcxproj wires into the build, in the
# form "<name>.c" / "<name>.h" — used as the "expected" set in drift
# detection. Pulled once, since the vcxproj doesn't change between the
# pre-replace baseline pass and the post-replace check.
VCXPROJ_FILES="$TMP/vcxproj-files.txt"
grep -oE '\$\(zlibDir\)\\[A-Za-z0-9_.]+\.[ch]' "$VCXPROJ" \
    | sed 's,^\$(zlibDir)\\,,' \
    | sort -u > "$VCXPROJ_FILES"

# Collect top-level .c and .h files in <zlib-tree>, output names only
# (no directory prefix), sorted/unique. Only depth 1 — zlib has subdirs
# (contrib/, examples/, ...) the build doesn't touch.
list_top_level() {
    local tree="$1"
    local out="$2"
    if [ ! -d "$tree" ]; then
        : > "$out"
        return 0
    fi
    (
        cd "$tree"
        find . -maxdepth 1 \( -name '*.c' -o -name '*.h' \) -print
    ) | sed 's,^\./,,' | sort -u > "$out"
}

# Compute the set of top-level .c/.h files in <zlib-tree> that are NOT
# referenced by MagPython.vcxproj — i.e. the intentional-exclusion set.
unlisted_in_tree() {
    local tree="$1"
    local out="$2"
    local tag="$3"

    local all="$TMP/tree-$tag.txt"
    list_top_level "$tree" "$all"
    comm -23 "$all" "$VCXPROJ_FILES" > "$out"
}

# Snapshot the existing tree's intentional exclusions before replacing it.
BASELINE_UNLISTED="$TMP/baseline-unlisted.txt"
unlisted_in_tree "$ZLIB_DIR" "$BASELINE_UNLISTED" "old"

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
SRC="$TMP/extract/zlib-${VERSION}"
if [ ! -d "$SRC" ]; then
    echo "Unexpected tarball layout: $SRC missing" >&2
    exit 71
fi

echo "Replacing $ZLIB_DIR ..."
rm -rf "$ZLIB_DIR"
mkdir -p "$ZLIB_DIR"
( cd "$SRC" && tar -cf - . ) | ( cd "$ZLIB_DIR" && tar -xf - )

# ---------------------------------------------------------------------------
# Sanity-check MagPython.vcxproj's zlib references against the new tree.
# ---------------------------------------------------------------------------
echo ""
echo "Checking MagPython/MagPython.vcxproj zlib references ..."

POST_UNLISTED="$TMP/post-unlisted.txt"
unlisted_in_tree "$ZLIB_DIR" "$POST_UNLISTED" "new"

TREE_NEW_ALL="$TMP/tree-new-all.txt"
list_top_level "$ZLIB_DIR" "$TREE_NEW_ALL"

# NEW: top-level files unlisted in the new tree but NOT in the baseline
# (i.e. truly new exclusions introduced by this upgrade).
# GONE: anything MagPython.vcxproj names that no longer exists in the
# new tree — always reported (these break the build).
NEW_FILES="$(comm -23 "$POST_UNLISTED" "$BASELINE_UNLISTED" || true)"
GONE_FILES="$(comm -13 "$TREE_NEW_ALL" "$VCXPROJ_FILES"     || true)"

if [ -n "$NEW_FILES" ]; then
    echo ""
    echo "  New top-level .c/.h files (added by this upgrade) that are NOT"
    echo "  referenced by MagPython.vcxproj. Review each — add to the"
    echo "  matching <ClCompile>/<ClInclude> ItemGroup, or confirm it is"
    echo "  intentionally excluded (e.g. the gz* family, which Python's"
    echo "  zlibmodule does not use):"
    echo "$NEW_FILES" | sed 's/^/    /'
fi
if [ -n "$GONE_FILES" ]; then
    echo ""
    echo "  Files referenced by MagPython.vcxproj that NO LONGER exist in"
    echo "  the zlib tree. <ClInclude> entries for missing files are silent"
    echo "  in MSBuild but rot the IDE view; <ClCompile> entries WILL break"
    echo "  the build. Remove or rename in MagPython.vcxproj:"
    echo "$GONE_FILES" | sed 's/^/    /'
fi
if [ -z "$NEW_FILES" ] && [ -z "$GONE_FILES" ]; then
    echo "  No new drift relative to the previous tree."
fi

echo ""
echo "Done. zlib $VERSION imported into $ZLIB_DIR"
echo "Next steps:"
echo "  1. Update the zlib version in README.md (vendored-libraries table"
echo "     and Licensing section)."
echo "  2. Reconcile any drift reported above in MagPython/MagPython.vcxproj."
echo "  3. Run a full Windows build to confirm the new tree compiles."
echo "  4. Commit with: git add zlib MagPython README.md"
echo "                  git commit -m 'Import unpacked zlib $VERSION'"
