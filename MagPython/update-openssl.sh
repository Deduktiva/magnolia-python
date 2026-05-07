#!/usr/bin/env bash
# Update the vendored openssl/ tree to a new 1.1.1 release.
#
# Usage: MagPython/update-openssl.sh <version>
#   e.g. MagPython/update-openssl.sh 1.1.1w
#
# Refuses to run if <version> is not on the 1.1.1 branch.
# Downloads the source tarball + SHA-256 from openssl.org, verifies the
# checksum, and replaces the contents of openssl/ in place. Also reports
# any crypto/* or ssl/* .c files that appear in the new tree but are not
# referenced in MagPython/openssl-makefile-faster (and vice versa) so the
# faster makefile's per-directory file lists can be reviewed.
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <openssl-version-on-1.1.1-branch>" >&2
    echo "  e.g.  $0 1.1.1w" >&2
    exit 64
fi

case "$VERSION" in
    1.1.1[a-z]|1.1.1) ;;
    *)
        echo "Refusing to update: '$VERSION' is not on the 1.1.1 branch." >&2
        echo "This project intentionally stays on OpenSSL 1.1.1." >&2
        exit 65
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENSSL_DIR="$REPO_ROOT/openssl"
MAKEFILE_FASTER="$SCRIPT_DIR/openssl-makefile-faster"

if command -v shasum >/dev/null 2>&1; then
    SHA256="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    SHA256="sha256sum"
else
    echo "Need either 'shasum' or 'sha256sum' on PATH for checksum verification." >&2
    exit 69
fi

TARBALL="openssl-${VERSION}.tar.gz"
# Prefer the immutable GitHub release artifact (the openssl.org direct
# downloads currently return 403 to plain curl). 1.1.1 release tags use the
# OpenSSL_1_1_1<letter> form. Fall back to openssl.org if GitHub is down.
GH_TAG="OpenSSL_$(echo "$VERSION" | tr '.' '_')"
URL_PRIMARY="https://github.com/openssl/openssl/releases/download/${GH_TAG}/${TARBALL}"
URL_FALLBACK="https://www.openssl.org/source/old/1.1.1/${TARBALL}"

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t openssl-update)"
trap 'rm -rf "$TMP"' EXIT

download() {
    # download <out-path> <url> [<fallback-url> ...]
    local out="$1"; shift
    local url
    for url in "$@"; do
        echo "  GET $url"
        if curl --fail --silent --show-error --location --output "$out" "$url"; then
            return 0
        fi
    done
    echo "All download URLs failed for $out" >&2
    return 1
}

echo "Downloading $TARBALL ..."
download "$TMP/$TARBALL"        "$URL_PRIMARY"        "$URL_FALLBACK"
download "$TMP/$TARBALL.sha256" "$URL_PRIMARY.sha256" "$URL_FALLBACK.sha256"

echo "Verifying SHA-256 ..."
EXPECTED="$(awk '{print $1; exit}' "$TMP/$TARBALL.sha256")"
ACTUAL="$($SHA256 "$TMP/$TARBALL" | awk '{print $1}')"
if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "Checksum mismatch:" >&2
    echo "  expected $EXPECTED" >&2
    echo "  got      $ACTUAL"   >&2
    exit 70
fi
echo "  OK ($ACTUAL)"

echo "Extracting ..."
mkdir -p "$TMP/extract"
tar -xzf "$TMP/$TARBALL" -C "$TMP/extract"
SRC="$TMP/extract/openssl-${VERSION}"
if [ ! -d "$SRC" ]; then
    echo "Unexpected tarball layout: $SRC missing" >&2
    exit 71
fi

echo "Replacing $OPENSSL_DIR ..."
rm -rf "$OPENSSL_DIR"
mkdir -p "$OPENSSL_DIR"
# Copy contents (including dotfiles) without relying on GNU-only flags.
( cd "$SRC" && tar -cf - . ) | ( cd "$OPENSSL_DIR" && tar -xf - )

# ---------------------------------------------------------------------------
# Sanity-check openssl-makefile-faster against the new source tree.
#
# openssl-makefile-faster hardcodes the .c files compiled per crypto/<dir>
# and ssl/[record|statem]. Patch releases on the 1.1.1 branch rarely touch
# this layout, but a missing or added file would silently break the build,
# so we flag any drift inside the directories the faster makefile already
# covers. Directories not represented at all in the makefile (e.g.
# crypto/blake2/, crypto/aria/) are deliberately left to nmake's default
# rules in the included makefile, so we ignore them here.
# ---------------------------------------------------------------------------
echo ""
echo "Checking MagPython/openssl-makefile-faster file lists ..."

LIST_MAKEFILE="$TMP/from-makefile.txt"
LIST_TREE_ALL="$TMP/from-tree-all.txt"
LIST_TREE_COVERED="$TMP/from-tree-covered.txt"
LIST_DIRS="$TMP/covered-dirs.txt"

# Extract all crypto\... and ssl\... .c references from the makefile.
grep -oE '(crypto|ssl)\\[A-Za-z0-9_\\]+\.c' "$MAKEFILE_FASTER" \
    | tr '\\' '/' \
    | sort -u > "$LIST_MAKEFILE"

# Directories the faster makefile already cares about (parent of every
# referenced file, e.g. "crypto", "crypto/aes", "ssl", "ssl/record").
sed 's:/[^/]*$::' "$LIST_MAKEFILE" | sort -u > "$LIST_DIRS"

# All candidate .c files in the new tree under crypto/ and ssl/.
(
    cd "$OPENSSL_DIR"
    find crypto -maxdepth 2 -name '*.c' -print
    find ssl    -maxdepth 2 -name '*.c' -print
) | sort -u > "$LIST_TREE_ALL"

# Count files in <dir> at depth 1 (no further slash after the prefix).
count_in_dir() {
    awk -v d="$1/" 'index($0, d)==1 && index(substr($0, length(d)+1), "/") == 0' "$2" \
        | wc -l | tr -d ' '
}

# Keep only directories where the makefile covers >=50% of the tree's files.
# Below that threshold the makefile is intentionally selective (e.g. the
# top-level crypto/ where only threads_*.c is batched, with everything else
# left to nmake's default rules), and flagging new files would be noise.
LIST_DIRS_KEEP="$TMP/covered-dirs-keep.txt"
: > "$LIST_DIRS_KEEP"
while IFS= read -r d; do
    mfn=$(count_in_dir "$d" "$LIST_MAKEFILE")
    treen=$(count_in_dir "$d" "$LIST_TREE_ALL")
    if [ "$treen" -gt 0 ] && [ "$((mfn * 2))" -ge "$treen" ]; then
        echo "$d" >> "$LIST_DIRS_KEEP"
    fi
done < "$LIST_DIRS"

# Filter to only files whose parent directory passes the threshold.
: > "$LIST_TREE_COVERED"
while IFS= read -r path; do
    parent="${path%/*}"
    if grep -qx "$parent" "$LIST_DIRS_KEEP"; then
        echo "$path" >> "$LIST_TREE_COVERED"
    fi
done < "$LIST_TREE_ALL"
sort -u -o "$LIST_TREE_COVERED" "$LIST_TREE_COVERED"

# NEW: files in the tree (filtered to mostly-covered dirs) the makefile lacks.
# GONE: any file the makefile references that is missing from the full tree —
# always check against the unfiltered tree, since a missing file breaks the
# build regardless of which directory it sits in.
NEW_FILES="$(comm -23 "$LIST_TREE_COVERED" "$LIST_MAKEFILE" || true)"
GONE_FILES="$(comm -13 "$LIST_TREE_ALL"     "$LIST_MAKEFILE" || true)"

if [ -n "$NEW_FILES" ]; then
    echo ""
    echo "  New .c files in directories openssl-makefile-faster covers but"
    echo "  the file itself is not listed (review and add, or confirm it is"
    echo "  intentionally excluded — e.g. no-idea / no-mdc2 / non-Windows):"
    echo "$NEW_FILES" | sed 's/^/    /'
fi
if [ -n "$GONE_FILES" ]; then
    echo ""
    echo "  Files referenced by openssl-makefile-faster that NO LONGER exist"
    echo "  in the OpenSSL tree (these will break the build — remove or"
    echo "  rename in the makefile):"
    echo "$GONE_FILES" | sed 's/^/    /'
fi
if [ -z "$NEW_FILES" ] && [ -z "$GONE_FILES" ]; then
    echo "  No drift detected in directories the faster makefile covers."
fi

echo ""
echo "Done. OpenSSL $VERSION imported into $OPENSSL_DIR"
echo "Next steps:"
echo "  1. Update the OpenSSL version in README.md."
echo "  2. Reconcile any drift reported above in MagPython/openssl-makefile-faster."
echo "  3. Run a full Windows build to confirm the new tree compiles."
echo "  4. Commit with: git add openssl MagPython README.md"
echo "                  git commit -m 'Import unpacked OpenSSL $VERSION'"
