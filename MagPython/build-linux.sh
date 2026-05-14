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
#     libsqlite3.so.0
#     libsqlite3.so -> libsqlite3.so.0
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
#
# Qt6 + PySide6 add three more system deps on top: cmake (>= 3.21 for
# Qt6's CMake build), ninja (the Qt6 / PySide6 builds drive their
# build via Ninja for parallel job control), and clang + llvm-devel
# (libclang headers / shared lib are what shiboken6 dlopens to parse Qt
# headers and generate Python bindings). manylinux_2_28's AlmaLinux 8
# base image carries old cmake (3.20) so we install a current cmake +
# ninja via pip — both ship binary wheels and are easier to keep in
# step with upstream than rebuilding the EL8 packages.
if ! command -v zip >/dev/null \
   || ! perl -MIPC::Cmd -e1 >/dev/null 2>&1 \
   || ! perl -MTime::Piece -e1 >/dev/null 2>&1 \
   || ! command -v clang >/dev/null \
   || ! ls /usr/lib*/libclang.so* >/dev/null 2>&1; then
    if command -v dnf >/dev/null; then
        dnf install -y zip perl-core clang clang-devel llvm-devel
    elif command -v yum >/dev/null; then
        yum install -y zip perl-core clang clang-devel llvm-devel
    elif command -v apt-get >/dev/null; then
        apt-get update && apt-get install -y zip clang libclang-dev llvm-dev
        # Debian/Ubuntu's `perl` package already includes the core modules.
    else
        echo "no supported package manager to install zip / perl-core / clang"; exit 1
    fi
fi
command -v patchelf >/dev/null || { echo "patchelf not found"; exit 1; }
# Use the host CPython's pip to install cmake + ninja as binary wheels.
# Keeps the host PATH overlay scoped to whatever python3 lives in;
# manylinux_2_28's /opt/python/cp313-cp313/bin is the natural target.
"$HOST_PYTHON" -m pip install --upgrade --quiet 'cmake>=3.21' ninja
# Surface the pip-installed binaries on PATH (pip drops them in the
# matching Python's bin/).
export PATH="$(dirname "$HOST_PYTHON"):$PATH"
command -v cmake >/dev/null || { echo "cmake not found after pip install"; exit 1; }
command -v ninja >/dev/null || { echo "ninja not found after pip install"; exit 1; }

prep_build_tree
setup_python
install_setup_local
build_zlib_static
build_libffi_static
build_sqlite_shared
build_openssl linux-x86_64
build_libmpdec
build_ncurses

log "Configuring libMagPython"
mkdir -p "$BUILD/main"
LIBFFI_INC="$(libffi_include_dir)"
LIBFFI_LIB="$(libffi_static_lib)"
(cd "$BUILD/main"
 configure_libmagpython "-Wl,-rpath,\$\$ORIGIN" \
     LIBFFI_CFLAGS="-I$LIBFFI_INC -I$LIBFFI_SRC/include" \
     LIBFFI_LIBS="$LIBFFI_LIB" \
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

log "Copying libsqlite3 shared lib"
cp -P "$BUILD/sqlite/libsqlite3.so.0" "$STAGE/"
ln -sf libsqlite3.so.0 "$STAGE/libsqlite3.so"

log "Stripping debug symbols from shared libs"
# CPython builds with -g -O3 by default; the embedded debug info adds
# tens of MB to libMagPython.so and is useless to consumers of the
# artifact. `strip` (no flags) keeps dynamic symbols intact, which is
# what shared-library consumers need.
for f in "$STAGE/libMagPython.so" "$STAGE/libcrypto.so.$OPENSSL_SO_VERSION" "$STAGE/libssl.so.$OPENSSL_SO_VERSION" "$STAGE/libsqlite3.so.0"; do
    strip "$f"
done

stage_headers_and_stdlib "$BUILD/main"
stage_openssl_headers
# Run the libMagPython static-dep-leakage check BEFORE Qt6 sibling libs
# land next to it — Qt6 may pull in libstdc++/libm/etc. that the
# verifier shouldn't see as part of libMagPython's NEEDED entries
# (it operates on a single .so).
verify_no_static_dep_leakage "$STAGE/libMagPython.so"

# Build + bundle Qt6 + PySide6 against the libMagPython we just produced.
# Symlinks first (PySide6's link step needs a libpythonX.Y.so to resolve
# -lpythonX.Y against), then Qt6 qtbase Core, then PySide6 (shiboken6 +
# pyside6), then stage everything into $STAGE.
#
# This block is what makes the artifact a self-contained PySide6
# consumption SDK: a downstream host application can drop the MagPython/
# directory next to its binary, add MagPython/site-packages to sys.path,
# and `import PySide6.QtCore` resolves into libraries the downstream
# never had to build or curate.
stage_libpython_symlinks
# Build the MagPython interpreter (CPython's Programs/python.c against
# libMagPython, with python3 alias). PySide6's `find_package(Python ...
# Development.Module)` runs against this binary so its sysconfig data
# is in lockstep with the headers and libpython the resulting .so files
# will link against — using the host's python on the runner would cause
# the ABI / sysconfig-mismatch failure mode shiboken6 dies on otherwise.
build_magpython_exe '$ORIGIN'
build_qt6
build_pyside6
stage_pyside6

# License staging runs last so Qt6 + PySide6 source trees are already
# fetched (their LICENSE entries are in stage_licenses, guarded by
# `[ -d ... ]` so a platform without them is a no-op).
stage_licenses

run_smoke_test '$ORIGIN' -ldl

zip_artifact linux-x86_64
