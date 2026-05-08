#!/usr/bin/env bash
# Build MagPython for Linux x86_64 inside the manylinux2014 container.
# Mirrors MagPython/MagPython.metaproj on Windows and produces
# MagPython-linux-x86_64.zip with the same shape as the Windows artifact:
#
#   MagPython/
#     libMagPython.so.1.0
#     libMagPython.so -> libMagPython.so.1.0
#     libcrypto.so.1.1
#     libssl.so.1.1
#     include/Python/...
#     lib/...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-common.sh
source "$SCRIPT_DIR/build-common.sh"

# manylinux2014 ships several CPython interpreters under /opt/python.
# Use cp312 if available; otherwise fall back to whatever python3 is on PATH.
HOST_PYTHON="/opt/python/cp313-cp313/bin/python3"
[ -x "$HOST_PYTHON" ] || HOST_PYTHON="$(command -v python3)"

# manylinux_2_28 ships patchelf (auditwheel needs it) but not zip; install
# zip on demand. Keep the install line idempotent so re-runs are cheap.
if ! command -v zip >/dev/null; then
    if command -v dnf >/dev/null; then
        dnf install -y zip
    elif command -v yum >/dev/null; then
        yum install -y zip
    elif command -v apt-get >/dev/null; then
        apt-get update && apt-get install -y zip
    else
        echo "no supported package manager to install zip"; exit 1
    fi
fi
command -v patchelf >/dev/null || { echo "patchelf not found"; exit 1; }

prep_build_tree
install_setup_local
build_static_deps ""
build_openssl linux-x86_64

log "Configuring libMagPython"
mkdir -p "$BUILD/main"
(cd "$BUILD/main"
 configure_libmagpython "-Wl,-rpath,\$\$ORIGIN" \
     PYTHON_FOR_REGEN="$HOST_PYTHON")

regen_frozen      "$BUILD/main" "$HOST_PYTHON"
flip_modules_to_static "$BUILD/main"

log "Building libpython"
(cd "$BUILD/main" && make -j"$JOBS")

log "Renaming libpython3.13 -> libMagPython"
(cd "$BUILD/main"
 # The shared lib CPython produces is libpython3.13.so.1.0 with SONAME
 # libpython3.13.so.1.0. Copy to the unversioned MagPython name, rewrite
 # the SONAME so consumers see a single file libMagPython.so (matching
 # MagPython.dll on Windows), and replace the RUNPATH with just $ORIGIN.
 # Without the RUNPATH rewrite, --with-openssl-rpath=auto leaves the
 # build's absolute openssl-out/lib path embedded, which only works on
 # the build machine — $ORIGIN means "look next to libMagPython.so",
 # which is where the artifact zip places libcrypto/libssl.
 cp libpython3.13.so.1.0 "$STAGE/libMagPython.so"
 patchelf --set-soname libMagPython.so "$STAGE/libMagPython.so"
 patchelf --set-rpath '$ORIGIN' "$STAGE/libMagPython.so")

log "Copying OpenSSL shared libs"
# install_sw places .so.1.1 (real) + unversioned symlink in lib (or lib64).
ssl_libdir="$BUILD/openssl-out/lib"
[ -d "$ssl_libdir" ] || ssl_libdir="$BUILD/openssl-out/lib64"
cp -P "$ssl_libdir"/libcrypto.so* "$STAGE/"
cp -P "$ssl_libdir"/libssl.so*    "$STAGE/"

log "Stripping debug symbols from shared libs"
# CPython builds with -g -O3 by default; the embedded debug info adds
# tens of MB to libMagPython.so and is useless to consumers of the
# artifact. `strip` (no flags) keeps dynamic symbols intact, which is
# what shared-library consumers need.
for f in "$STAGE"/libMagPython.so "$STAGE"/libcrypto.so.1.1 "$STAGE"/libssl.so.1.1; do
    strip "$f"
done

stage_headers_and_stdlib "$BUILD/main"
run_smoke_test '$ORIGIN'

# Sanity: ensure no surprise glibc-only-recent symbols. manylinux2014 ships
# auditwheel; skip this check gracefully if it isn't available locally.
if command -v auditwheel >/dev/null; then
    log "auditwheel show (informational)"
    auditwheel show "$STAGE/libMagPython.so" || true
fi

zip_artifact linux-x86_64
