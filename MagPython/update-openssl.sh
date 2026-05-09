#!/usr/bin/env bash
# Update the vendored openssl/ tree to a new release on the 3.x line.
#
# Usage: MagPython/update-openssl.sh <version>
#   e.g. MagPython/update-openssl.sh 3.5.6
#
# Downloads the source tarball + SHA-256 from openssl.org, verifies the
# checksum, and replaces the contents of openssl/ in place.
#
# Compatible with bash 3.2 (the default on macOS).

set -eu

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <openssl-version>" >&2
    echo "  e.g.  $0 3.5.6" >&2
    exit 64
fi

case "$VERSION" in
    3.[0-9]*.[0-9]*) ;;
    *)
        echo "Refusing to update: '$VERSION' is not on the 3.x line." >&2
        echo "Examples of accepted forms: 3.5.6, 3.0.20." >&2
        exit 65
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENSSL_DIR="$REPO_ROOT/openssl"

if command -v shasum >/dev/null 2>&1; then
    SHA256="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    SHA256="sha256sum"
else
    echo "Need either 'shasum' or 'sha256sum' on PATH for checksum verification." >&2
    exit 69
fi

TARBALL="openssl-${VERSION}.tar.gz"
GH_TAG="openssl-${VERSION}"
URL_PRIMARY="https://github.com/openssl/openssl/releases/download/${GH_TAG}/${TARBALL}"
# 3.x major.minor releases live at /source/ while current; older ones move
# to /source/old/<minor>/ once superseded.
MINOR="$(echo "$VERSION" | awk -F. '{print $1 "." $2}')"
URL_FALLBACK="https://www.openssl.org/source/openssl-${VERSION}.tar.gz"
URL_FALLBACK2="https://www.openssl.org/source/old/${MINOR}/openssl-${VERSION}.tar.gz"

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t openssl-update)"
trap 'rm -rf "$TMP"' EXIT

download() {
    # download <out-path> <url> [<fallback-url> ...]
    local out="$1"; shift
    local url
    for url in "$@"; do
        echo "  GET $url"
        if curl --fail --silent --show-error --location --output "$out" "$url"; then
            return 0
        fi
    done
    echo "All download URLs failed for $out" >&2
    return 1
}

echo "Downloading $TARBALL ..."
download "$TMP/$TARBALL"        "$URL_PRIMARY"        "$URL_FALLBACK"        "$URL_FALLBACK2"
download "$TMP/$TARBALL.sha256" "$URL_PRIMARY.sha256" "$URL_FALLBACK.sha256" "$URL_FALLBACK2.sha256"

echo "Verifying SHA-256 ..."
EXPECTED="$(awk '{print $1; exit}' "$TMP/$TARBALL.sha256")"
ACTUAL="$($SHA256 "$TMP/$TARBALL" | awk '{print $1}')"
if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "Checksum mismatch:" >&2
    echo "  expected $EXPECTED" >&2
    echo "  got      $ACTUAL"   >&2
    exit 70
fi
echo "  OK ($ACTUAL)"

echo "Extracting ..."
mkdir -p "$TMP/extract"
tar -xzf "$TMP/$TARBALL" -C "$TMP/extract"
SRC="$TMP/extract/openssl-${VERSION}"
if [ ! -d "$SRC" ]; then
    echo "Unexpected tarball layout: $SRC missing" >&2
    exit 71
fi

echo "Replacing $OPENSSL_DIR ..."
rm -rf "$OPENSSL_DIR"
mkdir -p "$OPENSSL_DIR"
# Copy contents (including dotfiles) without relying on GNU-only flags.
( cd "$SRC" && tar -cf - . ) | ( cd "$OPENSSL_DIR" && tar -xf - )

echo ""
echo "Done. OpenSSL $VERSION imported into $OPENSSL_DIR"
echo "Next steps:"
echo "  1. Run a full Windows + Linux + macOS build to confirm the new tree compiles."
echo "     The build glue auto-detects the soversion from openssl/VERSION.dat,"
echo "     so DLL/dylib/so filenames adapt automatically across patch bumps."
echo "  2. Update the OpenSSL version string in README.md (vendored-libraries"
echo "     table and Licensing section)."
echo "  3. Commit:  git add openssl README.md"
echo "             git commit -m 'Import unpacked OpenSSL $VERSION'"
