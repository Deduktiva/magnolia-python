#!/usr/bin/env bash
# Update the vendored sqlite/ amalgamation to a new SQLite release.
#
# Usage: MagPython/update-sqlite.sh <version> <year>
#   e.g. MagPython/update-sqlite.sh 3.45.1 2024
#
# Refuses to run if <version> is not on the SQLite 3.x line. Downloads
# the amalgamation .zip from sqlite.org and replaces the contents of
# sqlite/ in place. SQLite does not publish .sha256 sidecars on its
# download endpoints, so no upstream-anchored hash check is possible —
# we trust HTTPS to sqlite.org. The SHA-256 of the downloaded .zip is
# printed for the record (paste it into the commit message). The
# downloaded amalgamation's embedded SQLITE_VERSION is verified
# against the requested version as a sanity check.
#
# Also reports drift between MagPython/MagPython.vcxproj's sqlite
# .c/.h references and the new tree, with the previous tree's
# intentional exclusions (shell.c — the SQLite CLI, which Python's
# _sqlite3 module does not use) subtracted so each run only surfaces
# drift introduced by *this* upgrade.
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

VERSION="${1:-}"
YEAR="${2:-}"
if [ -z "$VERSION" ] || [ -z "$YEAR" ]; then
    echo "Usage: $0 <version> <year>" >&2
    echo "  e.g.  $0 3.45.1 2024" >&2
    echo "" >&2
    echo "<year> is the calendar year the release was published — sqlite.org's" >&2
    echo "download URL embeds it. Find it on https://sqlite.org/chronology.html" >&2
    echo "or in the release announcement." >&2
    exit 64
fi

case "$VERSION" in
    3.[0-9]*.[0-9]*) ;;
    *)
        echo "Refusing to update: '$VERSION' is not on the SQLite 3.x line." >&2
        echo "A 4.x bump would need a manual review of the build glue." >&2
        exit 65
        ;;
esac

case "$YEAR" in
    [0-9][0-9][0-9][0-9]) ;;
    *)
        echo "Refusing: '$YEAR' is not a four-digit year." >&2
        exit 65
        ;;
esac

# 3.45.1 -> 3045001 expressed as 7 digits with leading zeros; sqlite.org's
# download filename uses the formula <major>*1000000 + <minor>*10000
# + <patch>*100 (i.e. each component takes a fixed 2-digit slot, plus
# trailing 00 for sub-patch revisions which the project doesn't ship).
IFS=. read -r SQ_MAJ SQ_MIN SQ_PAT <<EOF
$VERSION
EOF
SQ_NUM=$(( SQ_MAJ * 1000000 + SQ_MIN * 10000 + SQ_PAT * 100 ))
SQ_NUM_PAD=$(printf '%07d' "$SQ_NUM")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SQLITE_DIR="$REPO_ROOT/sqlite"
VCXPROJ="$SCRIPT_DIR/MagPython.vcxproj"

# Used only to print the SHA of the downloaded zip for the record.
if command -v shasum >/dev/null 2>&1; then
    SHA256="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    SHA256="sha256sum"
else
    SHA256=""
fi

if ! command -v unzip >/dev/null 2>&1; then
    echo "Need 'unzip' on PATH (the SQLite amalgamation ships as a .zip)." >&2
    exit 69
fi

ZIPNAME="sqlite-amalgamation-${SQ_NUM_PAD}.zip"
URL="https://sqlite.org/${YEAR}/${ZIPNAME}"

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t sqlite-update)"
trap 'rm -rf "$TMP"' EXIT

# Extract the .c/.h files MagPython.vcxproj wires into the build, in the
# form "<name>.c" / "<name>.h" — used as the "expected" set in drift
# detection.
VCXPROJ_FILES="$TMP/vcxproj-files.txt"
grep -oE '\$\(sqlite3Dir\)\\[A-Za-z0-9_.]+\.[ch]' "$VCXPROJ" \
    | sed 's,^\$(sqlite3Dir)\\,,' \
    | sort -u > "$VCXPROJ_FILES"

# Top-level .c/.h files in <sqlite-tree>, names only, sorted/unique.
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

# Files in <sqlite-tree> that are NOT referenced by MagPython.vcxproj —
# the intentional-exclusion set.
unlisted_in_tree() {
    local tree="$1"
    local out="$2"
    local tag="$3"

    local all="$TMP/tree-$tag.txt"
    list_top_level "$tree" "$all"
    comm -23 "$all" "$VCXPROJ_FILES" > "$out"
}

BASELINE_UNLISTED="$TMP/baseline-unlisted.txt"
unlisted_in_tree "$SQLITE_DIR" "$BASELINE_UNLISTED" "old"

echo "Downloading $ZIPNAME ..."
echo "  GET $URL"
curl --fail --silent --show-error --location --output "$TMP/$ZIPNAME" "$URL"

if [ -n "$SHA256" ]; then
    ACTUAL_SHA256="$($SHA256 "$TMP/$ZIPNAME" | awk '{print $1}')"
    echo "  SHA-256: $ACTUAL_SHA256"
fi

echo "Extracting ..."
unzip -q "$TMP/$ZIPNAME" -d "$TMP/extract"
SRC="$TMP/extract/sqlite-amalgamation-${SQ_NUM_PAD}"
if [ ! -d "$SRC" ]; then
    echo "Unexpected zip layout: $SRC missing" >&2
    exit 71
fi

# Sanity-check the embedded version matches what we asked for.
if [ -f "$SRC/sqlite3.h" ]; then
    EMBEDDED="$(grep -oE '#define[ \t]+SQLITE_VERSION[ \t]+"[^"]+"' "$SRC/sqlite3.h" \
        | head -1 | sed 's/.*"\(.*\)".*/\1/')"
    if [ -n "$EMBEDDED" ] && [ "$EMBEDDED" != "$VERSION" ]; then
        echo "Version mismatch:" >&2
        echo "  requested $VERSION" >&2
        echo "  embedded  $EMBEDDED (from sqlite3.h SQLITE_VERSION)" >&2
        exit 72
    fi
    echo "  Embedded SQLITE_VERSION: $EMBEDDED"
fi

echo "Replacing $SQLITE_DIR ..."
rm -rf "$SQLITE_DIR"
mkdir -p "$SQLITE_DIR"
( cd "$SRC" && tar -cf - . ) | ( cd "$SQLITE_DIR" && tar -xf - )

# ---------------------------------------------------------------------------
# Sanity-check MagPython.vcxproj's sqlite references against the new tree.
# ---------------------------------------------------------------------------
echo ""
echo "Checking MagPython/MagPython.vcxproj sqlite references ..."

POST_UNLISTED="$TMP/post-unlisted.txt"
unlisted_in_tree "$SQLITE_DIR" "$POST_UNLISTED" "new"

TREE_NEW_ALL="$TMP/tree-new-all.txt"
list_top_level "$SQLITE_DIR" "$TREE_NEW_ALL"

NEW_FILES="$(comm -23 "$POST_UNLISTED" "$BASELINE_UNLISTED" || true)"
GONE_FILES="$(comm -13 "$TREE_NEW_ALL" "$VCXPROJ_FILES"     || true)"

if [ -n "$NEW_FILES" ]; then
    echo ""
    echo "  New top-level .c/.h files (added by this upgrade) that are NOT"
    echo "  referenced by MagPython.vcxproj. Review each — add to the"
    echo "  matching <ClCompile>/<ClInclude> ItemGroup, or confirm it is"
    echo "  intentionally excluded (e.g. shell.c, the SQLite CLI):"
    echo "$NEW_FILES" | sed 's/^/    /'
fi
if [ -n "$GONE_FILES" ]; then
    echo ""
    echo "  Files referenced by MagPython.vcxproj that NO LONGER exist in"
    echo "  the sqlite tree (these will break the build — remove or rename"
    echo "  in MagPython.vcxproj):"
    echo "$GONE_FILES" | sed 's/^/    /'
fi
if [ -z "$NEW_FILES" ] && [ -z "$GONE_FILES" ]; then
    echo "  No new drift relative to the previous tree."
fi

echo ""
echo "Done. SQLite $VERSION imported into $SQLITE_DIR"
echo "Next steps:"
echo "  1. Update the SQLite version in README.md (vendored-libraries table)."
echo "  2. Reconcile any drift reported above in MagPython/MagPython.vcxproj."
echo "  3. Run a full Windows build to confirm the new tree compiles."
echo "  4. Commit with: git add sqlite MagPython README.md"
echo "                  git commit -m 'Import sqlite-amalgamation-${SQ_NUM_PAD}'"
