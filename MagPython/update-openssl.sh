#!/usr/bin/env bash
# Update the OpenSSL pin files (MagPython/openssl-version,
# MagPython/openssl-sha256) to a new release on the 3.x line.
#
# Usage: MagPython/update-openssl.sh <version>
#   e.g. MagPython/update-openssl.sh 3.5.7
#
# Fetches openssl-<version>.tar.gz.sha256 from the upstream GitHub
# release, validates it as a 64-char lowercase hex digest, and writes
# both pin files. The build downloads + verifies the tarball at build
# time (see MagPython/download-openssl.ps1 and setup_openssl in
# build-common.sh), so this script intentionally does NOT download the
# tarball itself — only the small sidecar.
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <openssl-version>" >&2
    echo "  e.g.  $0 3.5.7" >&2
    exit 64
fi

case "$VERSION" in
    3.[0-9]*.[0-9]*) ;;
    *)
        echo "Refusing to update: '$VERSION' is not on the 3.x line." >&2
        echo "A cross-major bump warrants a manual review of the build glue" >&2
        echo "(Configure flag set, soname conventions, OpenSslDllSuffix" >&2
        echo "derivation in MagPython/common.props)." >&2
        exit 65
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
URL="https://github.com/openssl/openssl/releases/download/openssl-${VERSION}/openssl-${VERSION}.tar.gz.sha256"

TMP="$(mktemp 2>/dev/null || mktemp -t openssl-sidecar)"
trap 'rm -f "$TMP"' EXIT

echo "Fetching $URL ..."
if ! curl --fail --silent --show-error --location --output "$TMP" "$URL"; then
    echo "Failed to fetch the upstream .sha256 sidecar." >&2
    echo "Check that openssl-$VERSION exists on https://github.com/openssl/openssl/releases" >&2
    exit 70
fi

# Sidecar format is "<hash> *<filename>" or just "<hash>"; first token,
# lowercased, is what we want.
SHA="$(awk '{print tolower($1); exit}' "$TMP")"

# Validate the sidecar contents: 64 lowercase hex chars exactly. A
# malformed sidecar (HTML error page, truncated download) would
# otherwise quietly write a junk pin and fail the build only at the
# next CI run with a confusing "SHA-256 mismatch" error.
if [ "${#SHA}" -ne 64 ]; then
    echo "Unexpected sidecar contents (length ${#SHA}, expected 64): '$SHA'" >&2
    exit 71
fi
case "$SHA" in
    *[!0-9a-f]*)
        echo "Sidecar hash contains non-hex characters: $SHA" >&2
        exit 72
        ;;
esac

printf '%s\n' "$VERSION" > "$SCRIPT_DIR/openssl-version"
printf '%s\n' "$SHA"    > "$SCRIPT_DIR/openssl-sha256"

echo ""
echo "Updated:"
echo "  MagPython/openssl-version -> $VERSION"
echo "  MagPython/openssl-sha256  -> $SHA"
echo ""
echo "Next steps:"
echo "  1. Run a full Windows + Linux + macOS build to confirm the new"
echo "     version compiles. The build cross-checks the downloaded"
echo "     tarball against this SHA *and* against the upstream sidecar."
echo "  2. Commit both pin files together:"
echo "       git add MagPython/openssl-version MagPython/openssl-sha256"
echo "       git commit -m 'Bump OpenSSL pin to $VERSION'"
