#!/usr/bin/env bash
# Update the libffi pin files (MagPython/libffi-version,
# MagPython/libffi-sha256) to a new release on the 3.x line.
#
# Usage: MagPython/update-libffi.sh <version>
#   e.g. MagPython/update-libffi.sh 3.5.3
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

. "$(cd "$(dirname "$0")" && pwd)/update-pin-common.sh"

update_pin \
    --name libffi \
    --version-pattern '3.[0-9]*.[0-9]*' \
    --version-pattern-help '3.x line' \
    --tarball-url 'https://github.com/libffi/libffi/releases/download/v<v>/libffi-<v>.tar.gz' \
    "$@"
