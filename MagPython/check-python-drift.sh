#!/usr/bin/env bash
# Verify that every .c/.h file referenced by MagPython/MagPython.vcxproj
# and MagPython/FreezeMagPython.vcxproj via $(PythonSourceDir)\... exists
# in the build-time-downloaded CPython tree.
#
# Catches the cross-minor-bump case where upstream renamed/added/
# removed sources — without this check, the drift only surfaces at
# the next Windows build when cl.exe fails with a C1083 error 5+
# minutes into a metaproj run, often with a misleading attribution.
#
# As with check-libffi-drift.sh, this is GONE-only: it confirms every
# vcxproj ref still exists in the new tree, but doesn't try to detect
# NEW upstream files we should be compiling — that needs baseline
# bookkeeping the pre-devendor update-python.sh maintained but is
# not feasible post-devendor. Manual review of upstream's What's New
# during a cross-minor bump is the practical complement.
#
# Run by .github/workflows/Verify python drift.yml on PRs that touch
# MagPython/{python-version,python-sha256,MagPython.vcxproj,FreezeMagPython.vcxproj}.
# The workflow populates the cache via setup_python before running this.
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/python-version")"
SOURCE_DIR="$SCRIPT_DIR/python/python-$VERSION"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: CPython cache not populated at $SOURCE_DIR" >&2
    echo "       Run \`. MagPython/build-common.sh; setup_python\` first." >&2
    exit 1
fi

missing_total=0
ref_total=0
for vcxproj in "$SCRIPT_DIR/MagPython.vcxproj" "$SCRIPT_DIR/FreezeMagPython.vcxproj"; do
    [ -f "$vcxproj" ] || { echo "ERROR: missing $vcxproj" >&2; exit 1; }

    # Pull each Include="$(PythonSourceDir)\..." path that ends in .c or .h.
    while IFS= read -r path; do
        ref_total=$((ref_total + 1))
        # Trim the variable prefix and convert backslashes to forward slashes.
        rel="${path#'$(PythonSourceDir)\'}"
        rel="${rel//\\//}"
        ref="$SOURCE_DIR/$rel"
        if [ ! -f "$ref" ]; then
            echo "MISSING ($(basename "$vcxproj")): $path -> $ref"
            missing_total=$((missing_total + 1))
        fi
    done < <(grep -oE 'Include="\$\(PythonSourceDir\)\\[^"]+\.[ch]"' "$vcxproj" | sed -E 's/^Include="//; s/"$//')
done

if [ "$missing_total" -gt 0 ]; then
    echo
    echo "ERROR: $missing_total of $ref_total \$(PythonSourceDir) refs missing from CPython $VERSION."
    echo
    echo "Either upstream renamed/removed files in this version (the vcxproj"
    echo "<ClCompile>/<ClInclude> lists need editing), or the pin file points"
    echo "at the wrong tree."
    exit 1
fi

echo "OK: all $ref_total \$(PythonSourceDir) refs (across MagPython.vcxproj + FreezeMagPython.vcxproj) resolve in CPython $VERSION."
