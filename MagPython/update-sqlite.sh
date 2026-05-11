#!/usr/bin/env bash
# Update the sqlite pin files (MagPython/sqlite-version,
# MagPython/sqlite-year, MagPython/sqlite-sha256) to a new release on
# the 3.x line.
#
# Usage: MagPython/update-sqlite.sh <version> <year>
#   e.g. MagPython/update-sqlite.sh 3.53.1 2025
#
# sqlite.org's URL embeds a calendar-year segment that isn't derivable
# from the version (see https://sqlite.org/chronology.html), so the
# script takes <year> as a second positional. The zip filename is
# computed from the version's numeric encoding
# (<major>*1000000 + <minor>*10000 + <patch>*100).
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

VERSION="${1:-}"
YEAR="${2:-}"
if [ -z "$VERSION" ] || [ -z "$YEAR" ]; then
    echo "Usage: $0 <version> <year>" >&2
    echo "  e.g.  $0 3.53.1 2025" >&2
    echo "  Find the year for a given version on https://sqlite.org/chronology.html" >&2
    exit 64
fi

case "$YEAR" in
    [0-9][0-9][0-9][0-9]) ;;
    *)
        echo "Refusing: '$YEAR' is not a four-digit year." >&2
        exit 65
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/update-pin-common.sh"

# Compute the numeric version encoding sqlite.org's URL embeds.
IFS=. read -r MAJ MIN PAT <<EOF
$VERSION
EOF
NUMERIC="$(printf '%07d' $(( MAJ * 1000000 + MIN * 10000 + PAT * 100 )))"

# Pre-substitute the URL (no <v> token left) so update_pin's
# substitute step is a no-op. update_pin writes sqlite-version and
# sqlite-sha256; we write sqlite-year ourselves below since it's not a
# universal pin shape across the other devendored deps.
update_pin \
    --name sqlite \
    --version-pattern '3.[0-9]*.[0-9]*' \
    --version-pattern-help '3.x line' \
    --tarball-url "https://sqlite.org/$YEAR/sqlite-amalgamation-$NUMERIC.zip" \
    "$VERSION"

printf '%s\n' "$YEAR" > "$SCRIPT_DIR/sqlite-year"

echo ""
echo "Also wrote: MagPython/sqlite-year -> $YEAR"
echo "Make sure to include it in the commit:"
echo "  git add MagPython/sqlite-version MagPython/sqlite-year MagPython/sqlite-sha256"
echo "  git commit -m 'Bump sqlite pin to $VERSION ($YEAR)'"
