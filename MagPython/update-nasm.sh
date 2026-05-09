#!/usr/bin/env bash
# Update the NASM pin files (MagPython/nasm-version,
# MagPython/nasm-sha256) to a new release on the 2.x line.
#
# Usage: MagPython/update-nasm.sh <version>
#   e.g. MagPython/update-nasm.sh 2.16.03
#
# nasm.us doesn't publish per-zip .sha256 sidecars on its
# releasebuilds tree, so this script downloads the win32 zip,
# computes SHA-256 locally, and writes both pin files. Only the
# Windows builder uses NASM (it's required by OpenSSL's x86 assembly);
# Linux / macOS get nasm via the system package manager (or don't
# need it at all because OpenSSL configures with the platform's
# default assembler).
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

. "$(cd "$(dirname "$0")" && pwd)/update-pin-common.sh"

update_pin \
    --name nasm \
    --version-pattern '2.[0-9]*.[0-9]*' \
    --version-pattern-help '2.x line' \
    --tarball-url 'https://www.nasm.us/pub/nasm/releasebuilds/<v>/win32/nasm-<v>-win32.zip' \
    "$@"
