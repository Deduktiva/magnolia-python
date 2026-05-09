#!/usr/bin/env bash
# Update the zlib pin files (MagPython/zlib-version,
# MagPython/zlib-sha256) to a new release on the 1.x line.
#
# Usage: MagPython/update-zlib.sh <version>
#   e.g. MagPython/update-zlib.sh 1.3.2
#
# madler/zlib doesn't publish per-tarball .sha256 sidecars on its
# GitHub releases, so this script downloads the tarball, computes
# SHA-256 locally, and writes both pin files.
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

. "$(cd "$(dirname "$0")" && pwd)/update-pin-common.sh"

update_pin \
    --name zlib \
    --version-pattern '1.[0-9]*.[0-9]*' \
    --version-pattern-help '1.x line' \
    --tarball-url 'https://github.com/madler/zlib/releases/download/v<v>/zlib-<v>.tar.gz' \
    "$@"
