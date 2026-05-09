#!/usr/bin/env bash
# Build MagPython for Linux x86_64 inside the manylinux2014 container.
# Mirrors MagPython/MagPython.metaproj on Windows and produces
# MagPython-linux-x86_64.zip with the same shape as the Windows artifact:
#
#   MagPython/
#     libMagPython.so.1.0
#     libMagPython.so -> libMagPython.so.1.0
#     libcrypto.so.<openssl-shlib-version>     # 3 on the 3.x line
#     libssl.so.<openssl-shlib-version>
#     include/Python/...
#     lib/...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-common.sh
source "$SCRIPT_DIR/build-common.sh"

# manylinux_2_28 ships every actively-supported CPython under
# /opt/python/<tag>-<abitag>/bin/python3 (PEP 425 naming). Use the
# version matching the imported Python tree so regen-frozen runs the
# same interpreter the build will produce; fall back to whatever
# python3 is on PATH if the per-version slot is missing (e.g. when
# this script runs outside the manylinux container).
HOST_PYTHON="/opt/python/cp313-cp313/bin/python3"
[ -x "$HOST_PYTHON" ] || HOST_PYTHON="$(command -v python3)"

# manylinux_2_28 doesn't ship zip, and OpenSSL 3.x's Configure pulls in core
# Perl modules (IPC::Cmd, Time::Piece, ...) the AlmaLinux 8 base perl
# package omits — NOTES-PERL.md documents that RPM-based distros need
# perl-core for the full set. Install both on demand. Keep idempotent so
# re-runs are cheap.
if ! command -v zip >/dev/null \
   || ! perl -MIPC::Cmd -e1 >/dev/null 2>&1 \
   || ! perl -MTime::Piece -e1 >/dev/null 2>&1; then
    if command -v dnf >/dev/null; then
        dnf install -y zip perl-core
    elif command -v yum >/dev/null; then
        yum install -y zip perl-core
    elif command -v apt-get >/dev/null; then
        apt-get update && apt-get install -y zip
        # Debian/Ubuntu's `perl` package already includes the core modules.
    else
        echo "no supported package manager to install zip / perl-core"; exit 1
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

log "Renaming libpython$PY_X_Y -> libMagPython"
(cd "$BUILD/main"
 # The shared lib CPython produces is libpython<X.Y>.so.1.0 with SONAME
 # libpython<X.Y>.so.1.0. Copy to the unversioned MagPython name, rewrite
 # the SONAME so consumers see a single file libMagPython.so (matching
 # MagPython.dll on Windows), and replace the RUNPATH with just $ORIGIN.
 # Without the RUNPATH rewrite, --with-openssl-rpath=auto leaves the
 # build's absolute openssl-out/lib path embedded, which only works on
 # the build machine — $ORIGIN means "look next to libMagPython.so",
 # which is where the artifact zip places libcrypto/libssl.
 cp "libpython$PY_X_Y.so.1.0" "$STAGE/libMagPython.so"
 patchelf --set-soname libMagPython.so "$STAGE/libMagPython.so"
 patchelf --set-rpath '$ORIGIN' "$STAGE/libMagPython.so")

log "Copying OpenSSL shared libs"
# install_sw places libcrypto.so.<shlib-version> (real) + unversioned symlink
# in lib (we forced --libdir=lib in build_openssl).
OPENSSL_SO_VERSION="$(openssl_shlib_version)"
ssl_libdir="$BUILD/openssl-out/lib"
cp -P "$ssl_libdir"/libcrypto.so* "$STAGE/"
cp -P "$ssl_libdir"/libssl.so*    "$STAGE/"
# OpenSSL's link rules embed DT_RUNPATH=<install-prefix>/lib into the
# shared libs. That path is only valid on the build machine, and while
# libMagPython.so usually loads libssl/libcrypto first (so the soname
# lookup hits the already-mapped libs), anything that dlopens libssl
# directly would resolve libcrypto via that stale RUNPATH and fail.
# Reset both to $ORIGIN so they find each other as siblings, matching
# what libMagPython.so already does.
for f in "$STAGE/libcrypto.so.$OPENSSL_SO_VERSION" "$STAGE/libssl.so.$OPENSSL_SO_VERSION"; do
    patchelf --set-rpath '$ORIGIN' "$f"
done

log "Stripping debug symbols from shared libs"
# CPython builds with -g -O3 by default; the embedded debug info adds
# tens of MB to libMagPython.so and is useless to consumers of the
# artifact. `strip` (no flags) keeps dynamic symbols intact, which is
# what shared-library consumers need.
for f in "$STAGE/libMagPython.so" "$STAGE/libcrypto.so.$OPENSSL_SO_VERSION" "$STAGE/libssl.so.$OPENSSL_SO_VERSION"; do
    strip "$f"
done

stage_headers_and_stdlib "$BUILD/main"
stage_openssl_headers
run_smoke_test '$ORIGIN'

zip_artifact linux-x86_64
