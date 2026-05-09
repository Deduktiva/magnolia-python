# shellcheck shell=bash
# Shared helpers for the Unix build scripts (build-linux.sh, build-macos.sh).
# Sourced, never executed directly.

set -euo pipefail
# Verbose command tracing — the failing line is the actionable signal in CI
# when the rendered logs are gated behind auth. Cheap to leave on; the
# Windows build's MSBuild output is similarly verbose.
set -x

# REPO is the top-level checkout (one level above this file).
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$REPO/build-out"
STAGE="$BUILD/stage/MagPython"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# Derive the imported tree's <major>.<minor> version from the upstream
# header so the build scripts don't have to hardcode it — every spot
# that previously named libpython3.13 or lib/python3.13 reads $PY_X_Y
# instead, and a future update-python.sh run to 3.14+ flows through
# automatically.
PY_X_Y="$(awk '
    /^#define PY_MAJOR_VERSION[ \t]+/ { maj=$3 }
    /^#define PY_MINOR_VERSION[ \t]+/ { min=$3 }
    END { if (maj!="" && min!="") printf "%s.%s\n", maj, min }
' "$REPO/Python/Include/patchlevel.h")"
if [ -z "$PY_X_Y" ]; then
    echo "Failed to parse PY_MAJOR_VERSION/PY_MINOR_VERSION from Python/Include/patchlevel.h" >&2
    exit 1
fi

log() { printf '\n=== %s ===\n' "$*"; }

prep_build_tree() {
    rm -rf "$BUILD"
    mkdir -p "$BUILD" "$STAGE"
}

# Build vendored deps that are linked statically into libMagPython:
#   zlib    -> $REPO/zlib/libz.a
#   libffi  -> $REPO/libffi/.libs/libffi.a (+ generated headers)
#   sqlite  -> $BUILD/sqlite/libsqlite3.a
# $1 (optional): libffi --host triple (for cross-build edge cases).
build_static_deps() {
    local libffi_host="${1:-}"

    log "Building zlib static lib"
    # zlib's configure doesn't add -fPIC under --static, but we link the .a
    # into a shared libpython, so pass it explicitly. (libffi handles --with-pic
    # itself; sqlite gets -fPIC from our cc invocation below.)
    (cd "$REPO/zlib"
     [ -f Makefile ] && make distclean >/dev/null 2>&1 || true
     CFLAGS="-O3 -fPIC" ./configure --static
     make -j"$JOBS" libz.a)

    log "Building libffi static lib"
    (cd "$REPO/libffi"
     [ -f Makefile ] && make distclean >/dev/null 2>&1 || true
     local args=(--enable-static --disable-shared --with-pic --disable-docs)
     [ -n "$libffi_host" ] && args+=(--host="$libffi_host")
     ./configure "${args[@]}"
     make -j"$JOBS")

    log "Compiling sqlite3 amalgamation"
    mkdir -p "$BUILD/sqlite"
    cc -c -O2 -fPIC \
       -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_JSON1 \
       "$REPO/sqlite/sqlite3.c" -o "$BUILD/sqlite/sqlite3.o"
    ar rcs "$BUILD/sqlite/libsqlite3.a" "$BUILD/sqlite/sqlite3.o"
}

# Locate the libffi build's generated include dir (host triple subdir).
# After `./configure && make`, libffi puts fficonfig.h + ffi.h into
# $REPO/libffi/<triple>/include. We need this on the include path so that
# CPython's _ctypes build picks up the right ABI macros.
libffi_include_dir() {
    local d
    # `find -quit` stops on first hit, sidestepping head|pipefail trouble.
    d="$(find "$REPO/libffi" -mindepth 2 -maxdepth 2 -type d -name include \
            -print -quit 2>/dev/null || true)"
    [ -n "$d" ] || d="$REPO/libffi/include"
    printf '%s' "$d"
}

# Path to the static libffi.a produced by `make`. libffi puts the build
# under $REPO/libffi/<host-triple>/.libs/libffi.a, where the triple comes
# from autoconf detection (e.g. x86_64-pc-linux-gnu, aarch64-apple-darwin).
libffi_static_lib() {
    local d
    d="$(find "$REPO/libffi" -mindepth 3 -maxdepth 3 -type f -name libffi.a \
            -path '*/.libs/libffi.a' -print -quit 2>/dev/null || true)"
    [ -n "$d" ] || d="$REPO/libffi/.libs/libffi.a"
    printf '%s' "$d"
}

# Detect the vendored OpenSSL's SHLIB_VERSION ("3" today). Threaded into the
# patchelf / install_name_tool calls below so soname-bearing filenames adapt
# automatically when openssl/ is replaced.
openssl_shlib_version() {
    awk -F= '/^SHLIB_VERSION=/ { gsub(/[ \t\r]/, "", $2); print $2; exit }' \
        "$REPO/openssl/VERSION.dat"
}

# Build vendored OpenSSL as shared libs at $BUILD/openssl-out.
# $1: OpenSSL Configure target (linux-x86_64, darwin64-arm64-cc, ...)
#
# --libdir=lib pins the install path so x86_64 doesn't auto-pick lib64/;
# CPython's configure looks for $prefix/lib/, not lib64/.
#
# The no-* set trims the build to the surface CPython's _ssl /
# _hashopenssl actually use. Each was verified by greping the relevant
# CPython sources (no callers, or already #ifdef'd):
#   no-fips no-docs no-legacy no-cmp no-apps no-cms no-comp no-ct
#   no-engine no-dso no-ocsp no-srp no-srtp no-ssl3 no-ts no-tests
#   no-async no-uplink no-idea no-mdc2
build_openssl() {
    local target="$1"
    log "Building OpenSSL ($target)"
    (cd "$REPO/openssl"
     [ -f Makefile ] && make distclean >/dev/null 2>&1 || true
     ./Configure "$target" shared --libdir=lib \
         no-idea no-mdc2 no-cms no-comp no-ct no-engine no-dso \
         no-ocsp no-srp no-srtp no-ssl3 no-ts no-tests no-async \
         no-uplink no-fips no-docs no-legacy no-cmp no-apps \
         --prefix="$BUILD/openssl-out" \
         --openssldir="$BUILD/openssl-out/ssl"
     make -j"$JOBS"
     make install_sw)

    verify_openssl_install
}

# Sanity-check the staged OpenSSL install with MagPython/openssl-verify.c
# before we hand it to CPython's configure, so a misconfigured no-* set or a
# missing soname doesn't surface 50 layers deep as a silent
#   "checking whether OpenSSL provides required ssl module APIs... no".
# Same source is reused on Windows from openssl.vcxproj.
verify_openssl_install() {
    local out="$BUILD/openssl-out"
    log "Verifying OpenSSL install at $out"
    cc "$REPO/MagPython/openssl-verify.c" \
        -I"$out/include" -L"$out/lib" -Wl,-rpath,"$out/lib" \
        -lssl -lcrypto \
        -o "$BUILD/openssl-verify" \
        || { echo "OpenSSL link-check FAILED — CPython configure will reject this build" >&2; exit 1; }
    "$BUILD/openssl-verify" \
        || { echo "OpenSSL run-check FAILED" >&2; exit 1; }
    rm -f "$BUILD/openssl-verify"
}

# Regenerate frozen sources via upstream's make targets, inside the main
# build dir (so we don't pay for a second configure). The output is
# gitignored and required before linking libMagPython. CPython 3.13
# dropped deepfreeze (the .c-pre-baked importlib bootstrap) — frozen
# modules are now the only path, so we only invoke regen-frozen.
# $1: build dir (already configured)
# $2: host python interpreter for freeze_modules.py.
regen_frozen() {
    local build_dir="$1"
    local host_python="$2"
    log "Regenerating frozen modules with $host_python"
    (cd "$build_dir"
     make -j"$JOBS" PYTHON_FOR_REGEN="$host_python" regen-frozen)
}

# Drop in the project's Setup.local (disables stdlib modules that aren't in
# MagPython/MagPython.vcxproj on Windows, so libMagPython matches that
# subset on every platform). Run before configure so the file is in place
# when makesetup processes it.
install_setup_local() {
    log "Installing MagPython/Setup.local -> Python/Modules/Setup.local"
    cp "$REPO/MagPython/Setup.local" "$REPO/Python/Modules/Setup.local"
}

# Configure CPython for the libMagPython build. Caller cd's into a build dir.
# $1: extra LDFLAGS_NODIST (e.g. rpath flag)
# remaining args: appended to configure (e.g. MACOSX_DEPLOYMENT_TARGET=11.0)
configure_libmagpython() {
    local extra_ldflags="$1"; shift
    local libffi_inc libffi_lib
    libffi_inc="$(libffi_include_dir)"
    libffi_lib="$(libffi_static_lib)"
    "$REPO/Python/configure" \
        --enable-shared \
        --without-static-libpython \
        --with-openssl="$BUILD/openssl-out" \
        --with-openssl-rpath=auto \
        --with-system-ffi \
        --disable-test-modules \
        --without-pymalloc-debug \
        LIBFFI_CFLAGS="-I$libffi_inc -I$REPO/libffi/include" \
        LIBFFI_LIBS="$libffi_lib" \
        ZLIB_CFLAGS="-I$REPO/zlib" \
        ZLIB_LIBS="$REPO/zlib/libz.a" \
        LIBSQLITE3_CFLAGS="-I$REPO/sqlite" \
        LIBSQLITE3_LIBS="$BUILD/sqlite/libsqlite3.a" \
        CFLAGS_NODIST="-fPIC" \
        LDFLAGS_NODIST="$extra_ldflags" \
        "$@"
}

# Rewrite Modules/Setup.stdlib post-configure so we get the same module
# subset as MagPython/MagPython.vcxproj on Windows:
#
#   1. Flip the `*shared*` directive at the top to `*static*` so every
#      kept module gets linked into libpython rather than dlopen'd as a
#      separate .so.
#   2. Comment out the lines for modules listed under `*disabled*` in
#      MagPython/Setup.local. (`*disabled*` in Setup.local is recorded
#      into config.c's runtime DISABLED list but does NOT prevent
#      compilation — makesetup processes each Setup file independently,
#      so a module enabled in Setup.stdlib still gets a build rule.
#      Commenting the stdlib line is what actually skips the build.)
#   3. Re-run makesetup so Makefile and Modules/config.c pick up the edits.
flip_modules_to_static() {
    local build_dir="$1"
    local setup_local="$REPO/MagPython/Setup.local"
    log "Rewriting Modules/Setup.stdlib (static + disabled-by-policy)"
    awk -v setup_local="$setup_local" '
        BEGIN {
            # Read the disabled module names from Setup.local into a set.
            in_disabled = 0
            while ((getline line < setup_local) > 0) {
                if (line ~ /^\*disabled\*$/) { in_disabled = 1; continue }
                if (line ~ /^\*/)            { in_disabled = 0; continue }
                if (!in_disabled)            { continue }
                # Skip blank lines and comments
                sub(/#.*$/, "", line)
                gsub(/[ \t]+/, " ", line)
                sub(/^ +/, "", line); sub(/ +$/, "", line)
                if (line == "") continue
                disabled[line] = 1
            }
            close(setup_local)
        }
        # Flip the build-type directive once.
        /^\*shared\*$/ { print "*static*"; next }
        # Comment out lines whose first whitespace-separated token is a
        # disabled module name. Active stdlib lines look like:
        #   <modname> <sources> [flags...]
        # Skip lines that are already commented out or empty.
        /^[^#[:space:]]/ {
            modname = $1
            if (modname in disabled) {
                print "# disabled-by-magpython " $0
                next
            }
        }
        { print }
    ' "$build_dir/Modules/Setup.stdlib" > "$build_dir/Modules/Setup.stdlib.tmp"
    mv "$build_dir/Modules/Setup.stdlib.tmp" "$build_dir/Modules/Setup.stdlib"
    # Re-run makesetup so config.c and module rules pick up the new linkage.
    (cd "$build_dir" && make -j1 Makefile Modules/config.c)
}

# Stage OpenSSL development files (public + internal headers) into the artifact
# tree, mirroring the Windows artifact shape produced by openssl.vcxproj's
# CopyArtifacts target. The public include/openssl/ tree comes from the
# install_sw output (includes Configure-generated headers like opensslconf.h);
# the internal include/crypto/ tree isn't installed by install_sw, so we copy
# .h files straight from the post-Configure source tree (which is where
# Configure materialises bn_conf.h / dso_conf.h from their .h.in templates).
# Linux/macOS link against libssl/libcrypto via the unversioned symlinks
# install_sw creates next to the real shared libs, so no platform-specific
# import library is needed here — that part is handled by the per-platform
# library copy step.
stage_openssl_headers() {
    log "Staging OpenSSL headers"
    mkdir -p "$STAGE/include/openssl" "$STAGE/include/crypto"
    cp -R "$BUILD/openssl-out/include/openssl/." "$STAGE/include/openssl/"
    find "$REPO/openssl/include/crypto" -maxdepth 1 -type f -iname '*.h' \
        -exec cp {} "$STAGE/include/crypto/" \;
}

# Stage headers and pure-Python stdlib into the artifact tree.
# On Unix the stdlib lives under `lib/python$PY_X_Y/` so Python's path
# discovery (which looks for `lib/pythonX.Y/os.py` walking up from the
# executable) just works without env vars or symlinks. The Windows
# artifact uses `lib/` directly because Windows discovery looks for
# `Lib/` instead — that's handled by MagPython.vcxproj, not here.
stage_headers_and_stdlib() {
    local build_dir="$1"
    log "Staging headers and stdlib"
    mkdir -p "$STAGE/include/Python" "$STAGE/lib/python$PY_X_Y/lib-dynload"
    cp -R "$REPO/Python/Include/." "$STAGE/include/Python/"
    cp "$build_dir/pyconfig.h" "$STAGE/include/Python/pyconfig.h"
    # Only .py files from the stdlib tree. Use a tar pipe so we don't depend
    # on rsync (manylinux_2_28 doesn't ship it) or GNU-specific cp --parents.
    (cd "$REPO/Python/Lib" && find . -name '*.py' -print0 | tar --null -T - -cf -) \
        | (cd "$STAGE/lib/python$PY_X_Y" && tar -xf -)
}

# Build and run the smoke test (MagPython/test.c) against the staged tree.
# $1: rpath token ('$ORIGIN' on Linux, '@loader_path' on macOS).
#
# The cc invocation deliberately uses ONLY $STAGE for both -I and -L: the
# build dir's openssl-out/ and CPython build outputs are off the search path,
# so a missing header or unversioned shared-lib symlink (e.g. libssl.dylib ->
# libssl.<ver>.dylib) in the artifact is a hard failure here rather than a
# silent fallback to the build tree.
run_smoke_test() {
    local rpath_token="$1"
    log "Building smoke test"
    cc "$REPO/MagPython/test.c" \
        -I"$STAGE/include" \
        -L"$STAGE" \
        "-Wl,-rpath,${rpath_token}" \
        -lMagPython -lssl -lcrypto \
        -o "$STAGE/MagPython_test"
    log "Running smoke test"
    # No PYTHONPATH/PYTHONHOME needed: stage_headers_and_stdlib added a
    # `lib/python$PY_X_Y -> .` symlink so Python's Unix path discovery
    # finds `lib/python$PY_X_Y/os.py` next to the executable and computes
    # the right sys.prefix. Same shape as the Windows test which runs
    # MagPython.dll's smoke test without setting any env vars.
    (cd "$STAGE" && ./MagPython_test)
    rm -f "$STAGE/MagPython_test"
}

zip_artifact() {
    local platform="$1"
    local out="$REPO/MagPython-${platform}.zip"
    log "Zipping artifact -> $out"
    rm -f "$out"
    (cd "$BUILD/stage" && zip -qr "$out" MagPython)
    ls -lh "$out"
}
