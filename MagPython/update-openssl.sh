#!/usr/bin/env bash
# Update the OpenSSL pin files (MagPython/openssl-version,
# MagPython/openssl-sha256) to a new release on the 3.x line.
#
# Usage: MagPython/update-openssl.sh <version>
#   e.g. MagPython/update-openssl.sh 3.5.7
#
# The build downloads + verifies the tarball at build time, so this
# script intentionally only fetches the small upstream .sha256 sidecar
# rather than the full tarball.
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

. "$(cd "$(dirname "$0")" && pwd)/update-pin-common.sh"

update_pin \
    --name openssl \
    --version-pattern '3.[0-9]*.[0-9]*' \
    --version-pattern-help '3.x line' \
    --tarball-url 'https://github.com/openssl/openssl/releases/download/openssl-<v>/openssl-<v>.tar.gz' \
    --sidecar-url 'https://github.com/openssl/openssl/releases/download/openssl-<v>/openssl-<v>.tar.gz.sha256' \
    "$@"
