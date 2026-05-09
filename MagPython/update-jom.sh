#!/usr/bin/env bash
# Update the jom pin files (MagPython/jom-version,
# MagPython/jom-sha256) to a new release on the 1.x line.
#
# Usage: MagPython/update-jom.sh <version>
#   e.g. MagPython/update-jom.sh 1.1.4
#
# qt.io's download page doesn't publish per-zip .sha256 sidecars on
# the same path as the zip, so this script downloads the zip,
# computes SHA-256 locally, and writes both pin files. jom is only
# used on the Windows builder (it's a Windows-only nmake replacement).
#
# qt.io's URL uses underscore-separated version (jom_1_1_4.zip);
# the substitution happens in update-pin-common.sh's update_pin
# helper via the URL template's <v> token after the dots have been
# replaced inline below.
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>" >&2
    echo "  e.g.  $0 1.1.4" >&2
    exit 64
fi

case "$VERSION" in
    1.[0-9]*.[0-9]*) ;;
    *)
        echo "Refusing to update: '$VERSION' is not on the 1.x line." >&2
        echo "A cross-major bump warrants a manual review of the build glue." >&2
        exit 65
        ;;
esac

# qt.io's URL uses underscore-separated version. Pre-substitute the
# URL ourselves rather than asking update-pin-common.sh to handle it
# — the helper does simple <v> replacement and adding a separate
# escape mechanism just for jom's URL convention isn't worth the
# complexity.
VERSION_UNDERSCORED="${VERSION//./_}"
URL="https://download.qt.io/official_releases/jom/jom_$VERSION_UNDERSCORED.zip"

. "$(cd "$(dirname "$0")" && pwd)/update-pin-common.sh"

update_pin \
    --name jom \
    --version-pattern '1.[0-9]*.[0-9]*' \
    --version-pattern-help '1.x line' \
    --tarball-url "$URL" \
    "$VERSION"
