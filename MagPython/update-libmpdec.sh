#!/usr/bin/env bash
# Update the libmpdec pin files (MagPython/libmpdec-version,
# MagPython/libmpdec-sha256) to a new release on the 2.x line.
#
# Usage: MagPython/update-libmpdec.sh <version>
#   e.g. MagPython/update-libmpdec.sh 2.5.2
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

. "$(cd "$(dirname "$0")" && pwd)/update-pin-common.sh"

update_pin \
    --name libmpdec \
    --version-pattern '2.[0-9]*.[0-9]*' \
    --version-pattern-help '2.x line' \
    --tarball-url 'https://www.bytereef.org/software/mpdecimal/releases/mpdecimal-<v>.tar.gz' \
    "$@"
