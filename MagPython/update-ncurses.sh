#!/usr/bin/env bash
# Update the ncurses pin files (MagPython/ncurses-version,
# MagPython/ncurses-sha256) to a new release on the 6.x line.
#
# Usage: MagPython/update-ncurses.sh <version>
#   e.g. MagPython/update-ncurses.sh 6.5
#
# Pulls from ftp.gnu.org's GNU mirror (the canonical upstream is
# invisible-island.net, but ftp.gnu.org's layout is easier to fetch
# programmatically).
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

. "$(cd "$(dirname "$0")" && pwd)/update-pin-common.sh"

update_pin \
    --name ncurses \
    --version-pattern '6.[0-9]*' \
    --version-pattern-help '6.x line' \
    --tarball-url 'https://ftp.gnu.org/gnu/ncurses/ncurses-<v>.tar.gz' \
    "$@"
