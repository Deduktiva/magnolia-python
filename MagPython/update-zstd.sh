#!/usr/bin/env bash
# Update the zstd pin files (MagPython/zstd-version,
# MagPython/zstd-sha256) to a new release on the 1.x line.
#
# Usage: MagPython/update-zstd.sh <version>
#   e.g. MagPython/update-zstd.sh 1.5.7

set -eu

. "$(cd "$(dirname "$0")" && pwd)/update-pin-common.sh"

update_pin \
    --name zstd \
    --version-pattern '1.[0-9]*.[0-9]*' \
    --version-pattern-help '1.x line' \
    --tarball-url 'https://github.com/facebook/zstd/releases/download/v<v>/zstd-<v>.tar.gz' \
    "$@"
