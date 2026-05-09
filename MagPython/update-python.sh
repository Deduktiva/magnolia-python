#!/usr/bin/env bash
# Update the CPython pin files (MagPython/python-version,
# MagPython/python-sha256) to a new release on the 3.x line.
#
# Usage: MagPython/update-python.sh <version>
#   e.g. MagPython/update-python.sh 3.13.14
#
# python.org publishes signed release tarballs but the GitHub tag
# archive is what the build's download path uses (signed-by-HTTPS,
# immutable per-tag, and consistent with the pre-devendor in-tree
# update-python.sh). This script downloads the tag archive, computes
# SHA-256 locally, and writes both pin files.
#
# Compatible with bash 3.2 (the default on macOS).
#
# A cross-minor bump (e.g. 3.13 -> 3.14) routinely adds or renames
# C source files referenced by MagPython/MagPython.vcxproj's per-file
# <ClCompile> list. The Verify python drift workflow surfaces any
# GONE refs on the resulting PR; reconciling them is part of the
# upgrade work and may need <ClCompile> additions / removals plus a
# manual review of the build glue.

set -eu

. "$(cd "$(dirname "$0")" && pwd)/update-pin-common.sh"

update_pin \
    --name python \
    --version-pattern '3.[0-9]*.[0-9]*' \
    --version-pattern-help '3.x line' \
    --tarball-url 'https://github.com/python/cpython/archive/refs/tags/v<v>.tar.gz' \
    "$@"
