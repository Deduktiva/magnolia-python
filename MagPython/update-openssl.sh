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

# Extract the makefile's referenced .c files once — it doesn't change between
# the pre-replace baseline pass and the post-replace check.
LIST_MAKEFILE="$TMP/from-makefile.txt"
LIST_DIRS="$TMP/covered-dirs.txt"
grep -oE '(crypto|ssl)\\[A-Za-z0-9_\\]+\.c' "$MAKEFILE_FASTER" \
    | tr '\\' '/' \
    | sort -u > "$LIST_MAKEFILE"
sed 's:/[^/]*$::' "$LIST_MAKEFILE" | sort -u > "$LIST_DIRS"

# Count .c files at depth 1 of <dir> (no further slash after the prefix).
count_in_dir() {
    awk -v d="$1/" 'index($0, d)==1 && index(substr($0, length(d)+1), "/") == 0' "$2" \
        | wc -l | tr -d ' '
}

# Compute the set of .c files in <openssl-tree> that live in directories
# openssl-makefile-faster mostly covers (>=50%) but are not themselves
# listed. Output goes to <out-file>, sorted/unique. Used twice: once on
# the existing tree (to record the intentional-exclusion baseline) and
# once on the freshly imported tree (to find truly new drift).
unlisted_in_covered_dirs() {
    local tree="$1"
    local out="$2"
    local tag="$3"          # short suffix for tmp filenames

    if [ ! -d "$tree/crypto" ] || [ ! -d "$tree/ssl" ]; then
        : > "$out"
        return 0
    fi

    local all="$TMP/tree-all-$tag.txt"
    local keep="$TMP/dirs-keep-$tag.txt"
    local covered="$TMP/tree-covered-$tag.txt"

    (
        cd "$tree"
        find crypto -maxdepth 2 -name '*.c' -print
        find ssl    -maxdepth 2 -name '*.c' -print
    ) | sort -u > "$all"

    : > "$keep"
    while IFS= read -r d; do
        local mfn treen
        mfn=$(count_in_dir "$d" "$LIST_MAKEFILE")
        treen=$(count_in_dir "$d" "$all")
        if [ "$treen" -gt 0 ] && [ "$((mfn * 2))" -ge "$treen" ]; then
            echo "$d" >> "$keep"
        fi
    done < "$LIST_DIRS"

    : > "$covered"
    while IFS= read -r path; do
        local parent="${path%/*}"
        if grep -qx "$parent" "$keep"; then
            echo "$path" >> "$covered"
        fi
    done < "$all"
    sort -u "$covered" > "$out"
}

# Snapshot the existing tree's "intentionally excluded" baseline before we
# replace it. Files already excluded in the previous version stay excluded
# in the new one without being re-flagged on every run.
BASELINE_UNLISTED="$TMP/baseline-unlisted.txt"
unlisted_in_covered_dirs "$OPENSSL_DIR" "$BASELINE_UNLISTED" "old"

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
# so we flag any drift inside the directories the faster makefile mostly
# covers. We also subtract the baseline of files that were already
# excluded in the previous tree, so each run only surfaces drift
# introduced by *this* upgrade.
# ---------------------------------------------------------------------------
echo ""
echo "Checking MagPython/openssl-makefile-faster file lists ..."

POST_UNLISTED="$TMP/post-unlisted.txt"
unlisted_in_covered_dirs "$OPENSSL_DIR" "$POST_UNLISTED" "new"

# All .c files in the freshly imported tree (for the GONE comparison).
TREE_NEW_ALL="$TMP/tree-all-new.txt"
(
    cd "$OPENSSL_DIR"
    find crypto -maxdepth 2 -name '*.c' -print
    find ssl    -maxdepth 2 -name '*.c' -print
) | sort -u > "$TREE_NEW_ALL"

# NEW: files unlisted in the new tree but NOT already unlisted in the old
# tree (i.e. genuinely new exclusions introduced by this upgrade).
# GONE: any file the makefile references that is missing from the full new
# tree — always check against the unfiltered tree, since a missing file
# breaks the build regardless of which directory it sits in.
NEW_FILES="$(comm -23 "$POST_UNLISTED" "$BASELINE_UNLISTED" || true)"
GONE_FILES="$(comm -13 "$TREE_NEW_ALL" "$LIST_MAKEFILE"     || true)"

if [ -n "$NEW_FILES" ]; then
    echo ""
    echo "  New .c files (added by this upgrade) in directories"
    echo "  openssl-makefile-faster covers, but the file itself is not"
    echo "  listed. Review each — add to the matching MY_* list, or"
    echo "  confirm it should stay excluded (no-idea / no-mdc2 / asm-"
    echo "  replaced / non-Windows-only):"
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
    echo "  No new drift relative to the previous tree."
fi

echo ""
echo "Done. OpenSSL $VERSION imported into $OPENSSL_DIR"
echo "Next steps:"
echo "  1. Update the OpenSSL version in README.md."
echo "  2. Reconcile any drift reported above in MagPython/openssl-makefile-faster."
echo "  3. Run a full Windows build to confirm the new tree compiles."
echo "  4. Commit with: git add openssl MagPython README.md"
echo "                  git commit -m 'Import unpacked OpenSSL $VERSION'"
