#!/usr/bin/env bash
# Compose release notes from per-platform MagPython-*.md fragments
# (emitted by Build All.yml's "Generate build details" step) and create
# the GitHub release with the build .zip artifacts attached. Invoked by
# .github/workflows/Release.yml.
#
# Usage:
#   MagPython/release.sh <release-name> [artifacts-dir]
#
# artifacts-dir defaults to ./artifacts and must contain the downloaded
# build artifacts in their per-platform subdirectories (the layout
# actions/download-artifact produces with no `name` filter).
#
# Env:
#   GH_TOKEN     required for `gh release create` (CI passes github.token)
#   GITHUB_SHA   target commit for the release; defaults to HEAD locally
#   DRY_RUN=1    compose and print body.md, skip gh — useful when iterating
#                on the notes layout outside CI

set -euo pipefail

NAME="${1:-}"
ARTIFACTS="${2:-artifacts}"
[ -n "$NAME" ] || { echo "usage: $0 <release-name> [artifacts-dir]" >&2; exit 1; }
[ -d "$ARTIFACTS" ] || { echo "artifacts directory not found: $ARTIFACTS" >&2; exit 1; }

mapfile -t FRAGMENTS < <(find "$ARTIFACTS" -name 'MagPython-*.md' -type f | sort)
[ "${#FRAGMENTS[@]}" -gt 0 ] || {
    echo "no MagPython-*.md fragments found under $ARTIFACTS/" >&2
    exit 1
}

BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT

{
    echo "## Build details"
    echo
    for f in "${FRAGMENTS[@]}"; do
        cat "$f"
        echo
    done
} > "$BODY"

echo "--- composed release body ---"
cat "$BODY"
echo "--- end ---"

if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "DRY_RUN=1, skipping gh release create"
    exit 0
fi

mapfile -t ASSETS < <(find "$ARTIFACTS" -name '*.zip' -type f | sort)
[ "${#ASSETS[@]}" -gt 0 ] || {
    echo "no .zip artifacts found under $ARTIFACTS/" >&2
    exit 1
}

# --generate-notes appends GitHub's auto-generated changelog after the
# body we wrote (the API pre-pends `body` to the generated notes).
gh release create "$NAME" \
    --title "$NAME" \
    --target "${GITHUB_SHA:-HEAD}" \
    --notes-file "$BODY" \
    --generate-notes \
    "${ASSETS[@]}"
