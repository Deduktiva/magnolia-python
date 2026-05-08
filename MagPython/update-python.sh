#!/usr/bin/env bash
# Update the vendored Python/ tree to a new CPython 3.x release.
#
# Usage: MagPython/update-python.sh <version>
#   e.g. MagPython/update-python.sh 3.13.3
#
# Refuses to run if <version> is not on the CPython 3.x line. Downloads
# the source tarball from python/cpython's GitHub tag archive and
# replaces the contents of Python/ in place. GitHub does not publish
# .sha256 sidecars on auto-generated tag archives, so no upstream-
# anchored hash check is possible — we trust HTTPS to GitHub. The
# SHA-256 of the downloaded tarball is printed for the record (paste
# it into the commit message) but not verified. The embedded
# PY_VERSION in Include/patchlevel.h is cross-checked against the
# requested version as a sanity guard.
#
# After extracting, the script drops files the build does not use and
# that python.org's release tarball also omits, so the imported tree
# stays minimal and matches the existing import's shape:
#
#   .azure-pipelines/     CI for python/cpython itself
#   .github/              CI for python/cpython itself
#   .gitignore            git metadata, not source
#   .gitattributes        git metadata, not source
#   Misc/NEWS.d/          per-version changelog fragments (not used)
#   PC/icons/             icons for the python.exe / launcher.exe GUI
#                         executables (we don't ship those)
#
# Also reports drift between MagPython/MagPython.vcxproj's
# $(PythonSourceDir)\... .c/.h references and the new tree. Drift is
# scoped to the directories the vcxproj substantially curates (>=50%
# of the directory's .c/.h files referenced) — otherwise CPython's
# very large module tree would drown the report in noise. The
# previous tree's intentional exclusions in those covered directories
# are subtracted so each run only surfaces drift introduced by *this*
# upgrade. GONE references (vcxproj entries that no longer exist) are
# always reported regardless of directory coverage — those break the
# build.
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <python-version-on-3.x-line>" >&2
    echo "  e.g.  $0 3.13.3" >&2
    exit 64
fi

case "$VERSION" in
    3.[0-9]*.[0-9]*) ;;
    *)
        echo "Refusing to update: '$VERSION' is not on the CPython 3.x line." >&2
        echo "A 4.x bump would need a manual review of the build glue." >&2
        exit 65
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_DIR="$REPO_ROOT/Python"
VCXPROJ="$SCRIPT_DIR/MagPython.vcxproj"

# Used only to print the SHA of the downloaded tarball for the record.
if command -v shasum >/dev/null 2>&1; then
    SHA256="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    SHA256="sha256sum"
else
    SHA256=""
fi

TARBALL="cpython-${VERSION}.tar.gz"
URL="https://github.com/python/cpython/archive/refs/tags/v${VERSION}.tar.gz"

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t python-update)"
trap 'rm -rf "$TMP"' EXIT

# Extract Python file references from MagPython.vcxproj in canonical
# form (forward-slash separated, no $(PythonSourceDir) prefix), e.g.
# "Include/Python.h" or "Modules/_io/iobase.c" — used as the "expected"
# set in drift detection. Pulled once, since the vcxproj does not
# change between the pre-replace baseline pass and the post-replace
# check.
VCXPROJ_FILES="$TMP/vcxproj-files.txt"
grep -oE '\$\(PythonSourceDir\)\\[^"]+\.[ch]' "$VCXPROJ" \
    | sed 's,^\$(PythonSourceDir)\\,,' \
    | tr '\\' '/' \
    | sort -u > "$VCXPROJ_FILES"

# Distinct parent directories of the referenced files — the candidate
# set of directories the drift detector considers "covered".
LIST_DIRS="$TMP/covered-dirs.txt"
sed 's:/[^/]*$::' "$VCXPROJ_FILES" | sort -u > "$LIST_DIRS"

# Count .c/.h files at depth 1 of <dir> within <listing-file>.
count_in_dir() {
    awk -v d="$1/" 'index($0, d)==1 && index(substr($0, length(d)+1), "/") == 0' "$2" \
        | wc -l | tr -d ' '
}

# Compute the set of .c/.h files in <python-tree> that live in
# directories the vcxproj mostly covers (>=50%) but are not themselves
# referenced. Output goes to <out-file>, sorted/unique. Used twice:
# once on the existing tree (to record the intentional-exclusion
# baseline) and once on the freshly imported tree (to find truly new
# drift).
unlisted_in_covered_dirs() {
    local tree="$1"
    local out="$2"
    local tag="$3"

    if [ ! -d "$tree" ]; then
        : > "$out"
        return 0
    fi

    local all="$TMP/tree-all-$tag.txt"
    local keep="$TMP/dirs-keep-$tag.txt"
    local covered="$TMP/tree-covered-$tag.txt"

    # Walk every directory the vcxproj references (depth 1 within each
    # such directory). Going through LIST_DIRS — rather than a recursive
    # find from the tree root — keeps this pass scoped to the exact set
    # of dirs the project cares about and avoids flagging files in
    # tooling/test/doc trees that the build never touches.
    : > "$all"
    while IFS= read -r d; do
        if [ -d "$tree/$d" ]; then
            (
                cd "$tree/$d"
                find . -maxdepth 1 \( -name '*.c' -o -name '*.h' \) -print
            ) | sed "s,^\./,$d/," >> "$all"
        fi
    done < "$LIST_DIRS"
    sort -u -o "$all" "$all"

    : > "$keep"
    while IFS= read -r d; do
        local mfn treen
        mfn=$(count_in_dir "$d" "$VCXPROJ_FILES")
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

# Snapshot the existing tree's intentional-exclusion baseline before
# replacing it. Files already excluded in the previous version stay
# excluded in the new one without being re-flagged on every run.
BASELINE_UNLISTED="$TMP/baseline-unlisted.txt"
unlisted_in_covered_dirs "$PYTHON_DIR" "$BASELINE_UNLISTED" "old"

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
SRC="$TMP/extract/cpython-${VERSION}"
if [ ! -d "$SRC" ]; then
    echo "Unexpected tarball layout: $SRC missing" >&2
    exit 71
fi

# Sanity-check the embedded version matches what we asked for.
PATCHLEVEL_H="$SRC/Include/patchlevel.h"
if [ -f "$PATCHLEVEL_H" ]; then
    EMBEDDED="$(grep -oE '#define[ \t]+PY_VERSION[ \t]+"[^"]+"' "$PATCHLEVEL_H" \
        | head -1 | sed 's/.*"\(.*\)".*/\1/')"
    if [ -n "$EMBEDDED" ] && [ "$EMBEDDED" != "$VERSION" ]; then
        echo "Version mismatch:" >&2
        echo "  requested $VERSION" >&2
        echo "  embedded  $EMBEDDED (from Include/patchlevel.h PY_VERSION)" >&2
        exit 72
    fi
    echo "  Embedded PY_VERSION: $EMBEDDED"
fi

# Strip files the build doesn't use and that python.org's release
# tarball also omits — keeps the imported tree minimal and stable
# across re-imports.
echo "Stripping unused upstream files ..."
DROP=(
    .azure-pipelines
    .github
    .gitignore
    .gitattributes
    Misc/NEWS.d
    PC/icons
)
for p in "${DROP[@]}"; do
    if [ -e "$SRC/$p" ]; then
        rm -rf "$SRC/$p"
        echo "  dropped $p"
    fi
done

echo "Replacing $PYTHON_DIR ..."
rm -rf "$PYTHON_DIR"
mkdir -p "$PYTHON_DIR"
( cd "$SRC" && tar -cf - . ) | ( cd "$PYTHON_DIR" && tar -xf - )

# ---------------------------------------------------------------------------
# Sanity-check MagPython.vcxproj's Python references against the new tree.
# ---------------------------------------------------------------------------
echo ""
echo "Checking MagPython/MagPython.vcxproj Python references ..."

POST_UNLISTED="$TMP/post-unlisted.txt"
unlisted_in_covered_dirs "$PYTHON_DIR" "$POST_UNLISTED" "new"

# All .c/.h files in the freshly imported tree, restricted to the
# directories the vcxproj references (depth 1). Used to detect GONE
# entries — vcxproj refs that no longer exist anywhere relevant.
TREE_NEW_ALL="$TMP/tree-all-new.txt"
: > "$TREE_NEW_ALL"
while IFS= read -r d; do
    if [ -d "$PYTHON_DIR/$d" ]; then
        (
            cd "$PYTHON_DIR/$d"
            find . -maxdepth 1 \( -name '*.c' -o -name '*.h' \) -print
        ) | sed "s,^\./,$d/," >> "$TREE_NEW_ALL"
    fi
done < "$LIST_DIRS"
sort -u -o "$TREE_NEW_ALL" "$TREE_NEW_ALL"

NEW_FILES="$(comm -23 "$POST_UNLISTED" "$BASELINE_UNLISTED" || true)"
GONE_FILES="$(comm -13 "$TREE_NEW_ALL" "$VCXPROJ_FILES"     || true)"

if [ -n "$NEW_FILES" ]; then
    echo ""
    echo "  New .c/.h files (added by this upgrade) in directories the"
    echo "  vcxproj substantially curates, but the file itself is not"
    echo "  referenced. Review each — add to the matching <ClCompile>/"
    echo "  <ClInclude> ItemGroup, or confirm it should stay excluded"
    echo "  (e.g. modules the project does not enable, platform-specific"
    echo "  variants, or stdlib bits the curated build leaves out):"
    echo "$NEW_FILES" | sed 's/^/    /'
fi
if [ -n "$GONE_FILES" ]; then
    echo ""
    echo "  Files referenced by MagPython.vcxproj that NO LONGER exist in"
    echo "  the Python tree. <ClInclude> entries for missing files are"
    echo "  silent in MSBuild but rot the IDE view; <ClCompile> entries"
    echo "  WILL break the build. Remove or rename in MagPython.vcxproj:"
    echo "$GONE_FILES" | sed 's/^/    /'
fi
if [ -z "$NEW_FILES" ] && [ -z "$GONE_FILES" ]; then
    echo "  No new drift relative to the previous tree."
fi

echo ""
echo "Done. Python $VERSION imported into $PYTHON_DIR"
echo "Next steps:"
echo "  1. Update the Python version in README.md (intro paragraph,"
echo "     vendored-libraries table, and lib/python<X.Y>/ paths in the"
echo "     Linux/macOS build-output examples)."
echo "  2. Reconcile any drift reported above in MagPython/MagPython.vcxproj."
echo "  3. Re-apply any project-local Python tree patches that the"
echo "     wipe-and-replace removed (see commits touching Python/ on top of"
echo "     the previous import — git log --oneline <prev-import>..HEAD -- Python)."
echo "  4. Run a full Windows + Linux + macOS build to confirm the new tree"
echo "     compiles end-to-end (cross-minor bumps may need additional fixes)."
echo "  5. Commit the import on its own with: git add Python"
echo "                                        git commit -m 'Import Python $VERSION'"
echo "     keeping any vcxproj/README/patch changes for follow-up commits."
