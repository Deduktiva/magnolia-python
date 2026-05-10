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

# CPython is downloaded at build time rather than vendored. Same shape
# as the other devendored deps. PY_X_Y is the major.minor pair every
# spot that previously named libpython3.13 or lib/python3.13 reads —
# derive it from the version pin so a future bump to 3.14+ flows
# through with no code change.
PYTHON_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/python-version")"
if [ -z "$PYTHON_VERSION" ]; then
    echo "Failed to read Python version from MagPython/python-version" >&2
    exit 1
fi
PYTHON_SHA256="$(tr -d '[:space:]' < "$REPO/MagPython/python-sha256")"
if [ -z "$PYTHON_SHA256" ]; then
    echo "Failed to read Python sha256 from MagPython/python-sha256" >&2
    exit 1
fi
PYTHON_CACHE="$REPO/MagPython/python"
PYTHON_SRC="$PYTHON_CACHE/python-$PYTHON_VERSION"
PY_X_Y="$(printf '%s' "$PYTHON_VERSION" | awk -F. '{ printf "%s.%s\n", $1, $2 }')"
if [ -z "$PY_X_Y" ]; then
    echo "Failed to derive PY_X_Y from $PYTHON_VERSION" >&2
    exit 1
fi

# libmpdec is downloaded at build time rather than vendored. The version
# pin lives in MagPython/libmpdec-version (also read by common.props on
# Windows); the expected SHA-256 of the upstream tarball lives next to
# it in MagPython/libmpdec-sha256. Both files together are the bump
# input shared by all three platforms.
LIBMPDEC_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/libmpdec-version")"
if [ -z "$LIBMPDEC_VERSION" ]; then
    echo "Failed to read libmpdec version from MagPython/libmpdec-version" >&2
    exit 1
fi
LIBMPDEC_SHA256="$(tr -d '[:space:]' < "$REPO/MagPython/libmpdec-sha256")"
if [ -z "$LIBMPDEC_SHA256" ]; then
    echo "Failed to read libmpdec sha256 from MagPython/libmpdec-sha256" >&2
    exit 1
fi
LIBMPDEC_CACHE="$REPO/MagPython/libmpdec"
LIBMPDEC_SRC="$LIBMPDEC_CACHE/mpdecimal-$LIBMPDEC_VERSION"

# OpenSSL is downloaded at build time rather than vendored. The version
# pin lives in MagPython/openssl-version (also read by common.props on
# Windows); the expected SHA-256 of the upstream tarball lives next to
# it in MagPython/openssl-sha256. Both files together are the bump
# input shared by all three platforms.
OPENSSL_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/openssl-version")"
if [ -z "$OPENSSL_VERSION" ]; then
    echo "Failed to read OpenSSL version from MagPython/openssl-version" >&2
    exit 1
fi
OPENSSL_SHA256="$(tr -d '[:space:]' < "$REPO/MagPython/openssl-sha256")"
if [ -z "$OPENSSL_SHA256" ]; then
    echo "Failed to read OpenSSL sha256 from MagPython/openssl-sha256" >&2
    exit 1
fi
OPENSSL_CACHE="$REPO/MagPython/openssl"
OPENSSL_SRC="$OPENSSL_CACHE/openssl-$OPENSSL_VERSION"

# zlib is downloaded at build time rather than vendored. Same shape
# as the OpenSSL / libmpdec blocks above.
ZLIB_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/zlib-version")"
if [ -z "$ZLIB_VERSION" ]; then
    echo "Failed to read zlib version from MagPython/zlib-version" >&2
    exit 1
fi
ZLIB_SHA256="$(tr -d '[:space:]' < "$REPO/MagPython/zlib-sha256")"
if [ -z "$ZLIB_SHA256" ]; then
    echo "Failed to read zlib sha256 from MagPython/zlib-sha256" >&2
    exit 1
fi
ZLIB_CACHE="$REPO/MagPython/zlib"
ZLIB_SRC="$ZLIB_CACHE/zlib-$ZLIB_VERSION"

# libffi is downloaded at build time rather than vendored. Same shape
# as the OpenSSL / libmpdec / zlib blocks above.
LIBFFI_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/libffi-version")"
if [ -z "$LIBFFI_VERSION" ]; then
    echo "Failed to read libffi version from MagPython/libffi-version" >&2
    exit 1
fi
LIBFFI_SHA256="$(tr -d '[:space:]' < "$REPO/MagPython/libffi-sha256")"
if [ -z "$LIBFFI_SHA256" ]; then
    echo "Failed to read libffi sha256 from MagPython/libffi-sha256" >&2
    exit 1
fi
LIBFFI_CACHE="$REPO/MagPython/libffi"
LIBFFI_SRC="$LIBFFI_CACHE/libffi-$LIBFFI_VERSION"

# SQLite is downloaded at build time rather than vendored. Same shape
# as the other devendored deps, plus an extra sqlite-year pin
# (sqlite.org's URL embeds a calendar-year segment that isn't
# derivable from the version — see https://sqlite.org/chronology.html).
SQLITE_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/sqlite-version")"
if [ -z "$SQLITE_VERSION" ]; then
    echo "Failed to read sqlite version from MagPython/sqlite-version" >&2
    exit 1
fi
SQLITE_YEAR="$(tr -d '[:space:]' < "$REPO/MagPython/sqlite-year")"
if [ -z "$SQLITE_YEAR" ]; then
    echo "Failed to read sqlite year from MagPython/sqlite-year" >&2
    exit 1
fi
SQLITE_SHA256="$(tr -d '[:space:]' < "$REPO/MagPython/sqlite-sha256")"
if [ -z "$SQLITE_SHA256" ]; then
    echo "Failed to read sqlite sha256 from MagPython/sqlite-sha256" >&2
    exit 1
fi
SQLITE_CACHE="$REPO/MagPython/sqlite"
SQLITE_SRC="$SQLITE_CACHE/sqlite-$SQLITE_VERSION"

# ncurses is downloaded at build time rather than vendored. POSIX-only
# (no Windows equivalent — the Windows artifact ships no curses module).
# Backs CPython's _curses / _curses_panel; built statically so the
# artifact zip stays self-contained on platforms whose system ncurses
# either isn't installable from a manylinux_2_28 base (Linux) or ships
# only a narrow-char libncurses (macOS).
NCURSES_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/ncurses-version")"
if [ -z "$NCURSES_VERSION" ]; then
    echo "Failed to read ncurses version from MagPython/ncurses-version" >&2
    exit 1
fi
NCURSES_SHA256="$(tr -d '[:space:]' < "$REPO/MagPython/ncurses-sha256")"
if [ -z "$NCURSES_SHA256" ]; then
    echo "Failed to read ncurses sha256 from MagPython/ncurses-sha256" >&2
    exit 1
fi
NCURSES_CACHE="$REPO/MagPython/ncurses"
NCURSES_SRC="$NCURSES_CACHE/ncurses-$NCURSES_VERSION"

log() { printf '\n=== %s ===\n' "$*"; }

prep_build_tree() {
    rm -rf "$BUILD"
    mkdir -p "$BUILD" "$STAGE"
}

# Build deps that are linked statically into libMagPython:
#   zlib    -> $ZLIB_SRC/libz.a (built from build-time download)
#   libffi  -> $LIBFFI_SRC/<triple>/.libs/libffi.a (+ generated headers)
#   sqlite  -> $BUILD/sqlite/libsqlite3.a
# $1 (optional): libffi --host triple (for cross-build edge cases).
build_static_deps() {
    local libffi_host="${1:-}"

    setup_zlib
    log "Building zlib static lib"
    # zlib's configure doesn't add -fPIC under --static, but we link the .a
    # into a shared libpython, so pass it explicitly. (libffi handles --with-pic
    # itself; sqlite gets -fPIC from our cc invocation below.)
    (cd "$ZLIB_SRC"
     [ -f Makefile ] && make distclean >/dev/null 2>&1 || true
     CFLAGS="-O3 -fPIC" ./configure --static
     make -j"$JOBS" libz.a)

    setup_libffi
    log "Building libffi static lib"
    (cd "$LIBFFI_SRC"
     [ -f Makefile ] && make distclean >/dev/null 2>&1 || true
     local args=(--enable-static --disable-shared --with-pic --disable-docs)
     [ -n "$libffi_host" ] && args+=(--host="$libffi_host")
     ./configure "${args[@]}"
     make -j"$JOBS")

    setup_sqlite
    log "Compiling sqlite3 amalgamation"
    mkdir -p "$BUILD/sqlite"
    cc -c -O2 -fPIC \
       -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_JSON1 \
       "$SQLITE_SRC/sqlite3.c" -o "$BUILD/sqlite/sqlite3.o"
    ar rcs "$BUILD/sqlite/libsqlite3.a" "$BUILD/sqlite/sqlite3.o"
}

# Download + verify + extract the upstream CPython tag archive into
# $PYTHON_CACHE/python-$PYTHON_VERSION/. Idempotent — the cache lives
# outside $BUILD so re-runs of the build script (which wipes $BUILD via
# prep_build_tree) reuse the already-fetched tarball.
#
# python.org publishes a release tarball with .sigstore signatures, but
# the GitHub tag archive is what the previous in-tree update-python.sh
# used (and is signed-by-HTTPS plus immutable per-tag), so we keep
# fetching from there.
#
# Upstream extracts to cpython-<version>/. Renamed to python-<version>/
# so the vcxproj's $(PythonSourceDir) substitution keeps a clean
# python-$(PythonVersion)/ shape.
setup_python() {
    if [ ! -d "$PYTHON_SRC" ]; then
        log "Fetching CPython $PYTHON_VERSION"
        mkdir -p "$PYTHON_CACHE"
        local url="https://github.com/python/cpython/archive/refs/tags/v$PYTHON_VERSION.tar.gz"
        local tarball="$PYTHON_CACHE/cpython-$PYTHON_VERSION.tar.gz"

        if [ ! -f "$tarball" ]; then
            curl --fail --silent --show-error --location \
                -o "$tarball" "$url"
        fi

        local sha256_cmd
        if command -v shasum >/dev/null 2>&1; then sha256_cmd="shasum -a 256"
        elif command -v sha256sum >/dev/null 2>&1; then sha256_cmd="sha256sum"
        else echo "Need shasum or sha256sum" >&2; exit 1; fi
        local actual
        actual="$($sha256_cmd "$tarball" | awk '{print $1}')"
        if [ "$PYTHON_SHA256" != "$actual" ]; then
            echo "CPython SHA-256 mismatch: expected $PYTHON_SHA256, got $actual" >&2
            echo "  (pinned in MagPython/python-sha256 — regenerate via" >&2
            echo "   MagPython/update-python.sh before changing)" >&2
            rm -f "$tarball"
            exit 1
        fi

        tar -xzf "$tarball" -C "$PYTHON_CACHE"
        # Upstream tag archive extracts to cpython-<version>/. Rename for
        # path symmetry with the other devendored deps (and so $PYTHON_SRC
        # stays a clean python-<version>/ path).
        mv "$PYTHON_CACHE/cpython-$PYTHON_VERSION" "$PYTHON_SRC"
    fi

    # Always run the patch — the GitHub Actions workflow caches
    # MagPython/python/ by python-version+sha256, so a fresh download
    # only happens when the pin moves. On a cache hit, the cached
    # source tree may pre-date this patch and needs it applied
    # against. patch_cpython_configure is idempotent: it skips silently
    # if the marker is already gone.
    patch_cpython_configure
}

# Patch CPython's pre-built configure script to stop the Darwin libffi
# block from clobbering user-supplied LIBFFI_CFLAGS / LIBFFI_LIBS.
#
# CPython 3.13's configure.ac (and the generated configure shell script)
# has a hard-coded block that runs only on Darwin:
#
#     have_libffi=missing
#     if test "x$ac_sys_system" = xDarwin; then
#         CFLAGS="-I${SDKROOT}/usr/include/ffi $CFLAGS"
#         <AC_CHECK_HEADER([ffi.h]) + AC_CHECK_LIB([ffi], [ffi_call])>
#         if both checks pass:
#             have_libffi=yes
#             LIBFFI_CFLAGS="-I${SDKROOT}/usr/include/ffi -DUSING_APPLE_OS_LIBFFI=1"
#             LIBFFI_LIBS="-lffi"
#         fi
#     fi
#
# On any modern macOS the SDK's <ffi.h> is reachable and `-lffi` resolves
# to /usr/lib/libffi.dylib (or a Homebrew copy), so the inner assignments
# always run — and they unconditionally OVERWRITE the user-passed
# LIBFFI_CFLAGS / LIBFFI_LIBS we set in configure_libmagpython. The
# subsequent fallback PKG_CHECK_MODULES block (which would honour our env
# vars) is gated on `have_libffi=missing`, so it's skipped. End result:
# _ctypes compiles against the SDK's ffi.h and links against
# /usr/lib/libffi.dylib instead of our pinned static libffi.a, leaving
# libMagPython.dylib with a NEEDED dependency on system libffi.
#
# Drop just the two assignment lines; have_libffi=yes still gets set, so
# the configure flow proceeds normally with our env-supplied LIBFFI_*
# values intact. The Linux/Windows builds never enter this block (the
# `xDarwin` test is false), so the patch is a no-op there.
#
# Idempotent: the marker (USING_APPLE_OS_LIBFFI=1) only exists in the
# pre-patched source, so re-running on an already-patched tree no-ops.
patch_cpython_configure() {
    local f="$PYTHON_SRC/configure"
    if ! grep -q 'USING_APPLE_OS_LIBFFI=1' "$f"; then
        # Already patched (or upstream removed the marker entirely).
        return 0
    fi
    log "Patching CPython configure: skip Darwin LIBFFI_* overwrite"
    # Markers chosen to be unique to this block: USING_APPLE_OS_LIBFFI
    # appears nowhere else, and the bare `LIBFFI_LIBS="-lffi"` form
    # (no ${VAR-default}) is only in this block — the fallback uses
    # `LIBFFI_LIBS=${LIBFFI_LIBS-"-lffi"}` which our pattern excludes.
    sed -i.bak \
        -e '/USING_APPLE_OS_LIBFFI=1/d' \
        -e '/^[[:space:]]*LIBFFI_LIBS="-lffi"$/d' \
        "$f"
    rm -f "$f.bak"
}

# Download + verify + extract the upstream zlib tarball into
# $ZLIB_CACHE/zlib-$ZLIB_VERSION/. Idempotent — the cache lives outside
# $BUILD so re-runs of the build script (which wipes $BUILD via
# prep_build_tree) reuse the already-fetched tarball.
#
# madler/zlib doesn't publish per-tarball .sha256 sidecars on its
# GitHub releases, so the expected hash is pinned in-tree at
# MagPython/zlib-sha256 and checked against the downloaded bytes.
setup_zlib() {
    if [ -d "$ZLIB_SRC" ]; then return 0; fi

    log "Fetching zlib $ZLIB_VERSION"
    mkdir -p "$ZLIB_CACHE"
    local base="https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION"
    local tarball="$ZLIB_CACHE/zlib-$ZLIB_VERSION.tar.gz"

    if [ ! -f "$tarball" ]; then
        curl --fail --silent --show-error --location \
            -o "$tarball" "$base/zlib-$ZLIB_VERSION.tar.gz"
    fi

    local sha256_cmd
    if command -v shasum >/dev/null 2>&1; then sha256_cmd="shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then sha256_cmd="sha256sum"
    else echo "Need shasum or sha256sum" >&2; exit 1; fi
    local actual
    actual="$($sha256_cmd "$tarball" | awk '{print $1}')"
    if [ "$ZLIB_SHA256" != "$actual" ]; then
        echo "zlib SHA-256 mismatch: expected $ZLIB_SHA256, got $actual" >&2
        echo "  (pinned in MagPython/zlib-sha256 — regenerate via" >&2
        echo "   MagPython/update-zlib.sh before changing)" >&2
        rm -f "$tarball"
        exit 1
    fi

    tar -xzf "$tarball" -C "$ZLIB_CACHE"
}

# Download + verify + extract the upstream SQLite amalgamation zip
# into $SQLITE_CACHE/sqlite-$SQLITE_VERSION/. Idempotent — the cache
# lives outside $BUILD so re-runs of the build script (which wipes
# $BUILD via prep_build_tree) reuse the already-fetched zip.
#
# sqlite.org's URL embeds a calendar-year segment (read from
# MagPython/sqlite-year) and a numeric encoding of the version
# (<major>*1000000 + <minor>*10000 + <patch>*100, e.g. 3.53.1 ->
# 3530100). The extracted upstream dir is sqlite-amalgamation-<numeric>;
# rename it to sqlite-<version> so the path consumers can refer to it
# via SQLITE_SRC without recomputing the numeric encoding.
#
# sqlite.org doesn't publish per-zip .sha256 sidecars, so the expected
# hash is pinned in-tree at MagPython/sqlite-sha256.
setup_sqlite() {
    if [ -d "$SQLITE_SRC" ]; then return 0; fi

    log "Fetching SQLite $SQLITE_VERSION ($SQLITE_YEAR)"
    mkdir -p "$SQLITE_CACHE"
    # Compute the numeric encoding sqlite.org's URL embeds.
    local sq_maj sq_min sq_pat sq_num zipname url tarball
    IFS=. read -r sq_maj sq_min sq_pat <<EOF
$SQLITE_VERSION
EOF
    sq_num="$(printf '%07d' $(( sq_maj * 1000000 + sq_min * 10000 + sq_pat * 100 )))"
    zipname="sqlite-amalgamation-$sq_num.zip"
    url="https://sqlite.org/$SQLITE_YEAR/$zipname"
    tarball="$SQLITE_CACHE/$zipname"

    if [ ! -f "$tarball" ]; then
        curl --fail --silent --show-error --location \
            -o "$tarball" "$url"
    fi

    local sha256_cmd
    if command -v shasum >/dev/null 2>&1; then sha256_cmd="shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then sha256_cmd="sha256sum"
    else echo "Need shasum or sha256sum" >&2; exit 1; fi
    local actual
    actual="$($sha256_cmd "$tarball" | awk '{print $1}')"
    if [ "$SQLITE_SHA256" != "$actual" ]; then
        echo "SQLite SHA-256 mismatch: expected $SQLITE_SHA256, got $actual" >&2
        echo "  (pinned in MagPython/sqlite-sha256 — regenerate via" >&2
        echo "   MagPython/update-sqlite.sh before changing)" >&2
        rm -f "$tarball"
        exit 1
    fi

    # unzip ships in manylinux_2_28 and on macOS; bsdtar's zip support
    # would also work but unzip is the more universal choice.
    if ! command -v unzip >/dev/null 2>&1; then
        echo "Need 'unzip' on PATH to extract the SQLite amalgamation" >&2
        exit 1
    fi
    (cd "$SQLITE_CACHE" && unzip -q "$zipname")
    # Rename upstream sqlite-amalgamation-<numeric>/ to sqlite-<version>/.
    mv "$SQLITE_CACHE/sqlite-amalgamation-$sq_num" "$SQLITE_SRC"
}

# Download + verify + extract the upstream libffi tarball into
# $LIBFFI_CACHE/libffi-$LIBFFI_VERSION/. Idempotent.
#
# libffi/libffi doesn't publish per-tarball .sha256 sidecars on its
# GitHub releases, so the expected hash is pinned in-tree at
# MagPython/libffi-sha256 and checked against the downloaded bytes.
setup_libffi() {
    if [ -d "$LIBFFI_SRC" ]; then return 0; fi

    log "Fetching libffi $LIBFFI_VERSION"
    mkdir -p "$LIBFFI_CACHE"
    local base="https://github.com/libffi/libffi/releases/download/v$LIBFFI_VERSION"
    local tarball="$LIBFFI_CACHE/libffi-$LIBFFI_VERSION.tar.gz"

    if [ ! -f "$tarball" ]; then
        curl --fail --silent --show-error --location \
            -o "$tarball" "$base/libffi-$LIBFFI_VERSION.tar.gz"
    fi

    local sha256_cmd
    if command -v shasum >/dev/null 2>&1; then sha256_cmd="shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then sha256_cmd="sha256sum"
    else echo "Need shasum or sha256sum" >&2; exit 1; fi
    local actual
    actual="$($sha256_cmd "$tarball" | awk '{print $1}')"
    if [ "$LIBFFI_SHA256" != "$actual" ]; then
        echo "libffi SHA-256 mismatch: expected $LIBFFI_SHA256, got $actual" >&2
        echo "  (pinned in MagPython/libffi-sha256 — regenerate via" >&2
        echo "   MagPython/update-libffi.sh before changing)" >&2
        rm -f "$tarball"
        exit 1
    fi

    tar -xzf "$tarball" -C "$LIBFFI_CACHE"
}

# Download + verify + extract the upstream mpdecimal tarball into
# $LIBMPDEC_CACHE/mpdecimal-$LIBMPDEC_VERSION/. Idempotent — the cache
# lives outside $BUILD so re-runs of the build script (which wipes
# $BUILD via prep_build_tree) reuse the already-fetched tarball.
#
# bytereef.org publishes hashes only in an HTML table on
# https://www.bytereef.org/mpdecimal/download.html — there is no per-
# tarball .sha256 sidecar to fetch. The expected hash is therefore
# pinned in-tree at MagPython/libmpdec-sha256 and checked against the
# downloaded bytes. A version bump means updating libmpdec-version AND
# libmpdec-sha256 together (see README's "Updating pinned libmpdec").
setup_libmpdec() {
    if [ -d "$LIBMPDEC_SRC" ]; then return 0; fi

    log "Fetching libmpdec $LIBMPDEC_VERSION"
    mkdir -p "$LIBMPDEC_CACHE"
    local base="https://www.bytereef.org/software/mpdecimal/releases"
    local tarball="$LIBMPDEC_CACHE/mpdecimal-$LIBMPDEC_VERSION.tar.gz"

    if [ ! -f "$tarball" ]; then
        curl --fail --silent --show-error --location \
            -o "$tarball" "$base/mpdecimal-$LIBMPDEC_VERSION.tar.gz"
    fi

    local sha256_cmd
    if command -v shasum >/dev/null 2>&1; then sha256_cmd="shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then sha256_cmd="sha256sum"
    else echo "Need shasum or sha256sum" >&2; exit 1; fi
    local actual
    actual="$($sha256_cmd "$tarball" | awk '{print $1}')"
    if [ "$LIBMPDEC_SHA256" != "$actual" ]; then
        echo "libmpdec SHA-256 mismatch: expected $LIBMPDEC_SHA256, got $actual" >&2
        echo "  (pinned in MagPython/libmpdec-sha256 — confirm against the table at" >&2
        echo "   https://www.bytereef.org/mpdecimal/download.html before changing)" >&2
        rm -f "$tarball"
        exit 1
    fi

    tar -xzf "$tarball" -C "$LIBMPDEC_CACHE"
}

# Build libmpdec as a static lib at $BUILD/libmpdec-out via upstream's
# autoconf. Mirrors zlib/sqlite/libffi handling — the .a is consumed by
# CPython's _decimal via LIBMPDEC_CFLAGS/LIBMPDEC_LIBS in
# configure_libmagpython.
#
# --disable-cxx skips libmpdec++ which we don't ship. CPython's
# configure.ac treats Darwin specially with libmpdec_machine=universal
# ("use the compiler's default arch flags") because mpdecimal's
# x64-specific inline asm doesn't apply to arm64 — pass the same flag
# through to upstream's configure on macOS.
#
# Args: optional extra args appended to ./configure (e.g. machine override).
build_libmpdec() {
    setup_libmpdec
    log "Building libmpdec $LIBMPDEC_VERSION"
    (cd "$LIBMPDEC_SRC"
     [ -f Makefile ] && make distclean >/dev/null 2>&1 || true
     ./configure \
         --prefix="$BUILD/libmpdec-out" \
         --disable-cxx \
         CFLAGS="-O2 -fPIC" \
         "$@"
     make -j"$JOBS"
     make install)
}

# Download + verify + extract the upstream ncurses tarball into
# $NCURSES_CACHE/ncurses-$NCURSES_VERSION/. Idempotent — the cache
# lives outside $BUILD so re-runs of the build script (which wipes
# $BUILD via prep_build_tree) reuse the already-fetched tarball.
#
# invisible-island.net (the canonical upstream) doesn't publish a
# Renovate-trackable release feed, and ftp.gnu.org (the GNU mirror)
# carries the same tarball with stable HTTPS — fetch from the GNU
# mirror so the download path matches every other devendored dep
# (no per-dep TLS quirks). The expected hash is pinned in-tree at
# MagPython/ncurses-sha256 and checked against the downloaded bytes.
setup_ncurses() {
    if [ -d "$NCURSES_SRC" ]; then return 0; fi

    log "Fetching ncurses $NCURSES_VERSION"
    mkdir -p "$NCURSES_CACHE"
    local url="https://ftp.gnu.org/gnu/ncurses/ncurses-$NCURSES_VERSION.tar.gz"
    local tarball="$NCURSES_CACHE/ncurses-$NCURSES_VERSION.tar.gz"

    if [ ! -f "$tarball" ]; then
        curl --fail --silent --show-error --location \
            -o "$tarball" "$url"
    fi

    local sha256_cmd
    if command -v shasum >/dev/null 2>&1; then sha256_cmd="shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then sha256_cmd="sha256sum"
    else echo "Need shasum or sha256sum" >&2; exit 1; fi
    local actual
    actual="$($sha256_cmd "$tarball" | awk '{print $1}')"
    if [ "$NCURSES_SHA256" != "$actual" ]; then
        echo "ncurses SHA-256 mismatch: expected $NCURSES_SHA256, got $actual" >&2
        echo "  (pinned in MagPython/ncurses-sha256 — regenerate via" >&2
        echo "   MagPython/update-ncurses.sh before changing)" >&2
        rm -f "$tarball"
        exit 1
    fi

    tar -xzf "$tarball" -C "$NCURSES_CACHE"
}

# Build ncurses as a static lib at $BUILD/ncurses-out via upstream's
# autoconf. Mirrors libmpdec handling — the .a is consumed by CPython's
# _curses / _curses_panel via CURSES_CFLAGS/CURSES_LIBS (and the
# PANEL_* equivalents) in configure_libmagpython.
#
# Configure flag set:
#   --without-shared --with-pic     static-only, PIC for the libpython link
#   --enable-widec                  Unicode (wide-char) support; selects
#                                   the libncursesw / libpanelw names
#   --without-debug                 drop debug-build artifacts
#   --without-tests --without-progs no test/binary executables
#   --without-cxx --without-cxx-binding  drop the C++ binding
#   --without-manpages              drop manpages from the install tree
#   --without-ada                   drop the Ada95 binding (some hosts
#                                   have gnat installed and would otherwise
#                                   build it)
#   --enable-pc-files=no            don't install pkg-config .pc files
#                                   into the staged tree (we point CPython
#                                   at the .a files directly via
#                                   CURSES_LIBS, not via pkg-config)
#   --without-termlib               keep terminfo functions inside
#                                   libncursesw rather than splitting them
#                                   into a separate libtinfo — one fewer
#                                   .a to plumb through CURSES_LIBS, and
#                                   matches the macOS shape (where libtinfo
#                                   isn't separated)
build_ncurses() {
    setup_ncurses
    log "Building ncurses $NCURSES_VERSION"
    (cd "$NCURSES_SRC"
     [ -f Makefile ] && make distclean >/dev/null 2>&1 || true
     ./configure \
         --prefix="$BUILD/ncurses-out" \
         --without-shared --with-pic \
         --enable-widec \
         --without-debug \
         --without-tests \
         --without-progs \
         --without-cxx --without-cxx-binding \
         --without-ada \
         --without-manpages \
         --enable-pc-files=no \
         --without-termlib \
         CFLAGS="-O2 -fPIC"
     make -j"$JOBS"
     # Install only the .a files and headers — `make install` would
     # also run `install.data`, which compiles ncurses' terminfo
     # database with `tic`. We pass `--without-progs`, so `tic` isn't
     # built here; install.data then falls back to a system `tic` on
     # PATH. manylinux_2_28's base image carries a compatible
     # /usr/bin/tic from its ncurses-devel package, but the macos-14
     # runner doesn't ship a widec-aware tic — install.data fails
     # there. We don't ship the terminfo database in the artifact
     # anyway (curses uses the host system's terminfo at runtime),
     # so installing only libs + includes keeps the two platforms on
     # the same path and gives CPython's configure exactly what
     # CURSES_CFLAGS/CURSES_LIBS need to point at.
     make install.libs install.includes)
}

# Locate the libffi build's generated include dir (host triple subdir).
# After `./configure && make`, libffi puts fficonfig.h + ffi.h into
# $LIBFFI_SRC/<triple>/include. We need this on the include path so that
# CPython's _ctypes build picks up the right ABI macros.
libffi_include_dir() {
    local d
    # `find -quit` stops on first hit, sidestepping head|pipefail trouble.
    d="$(find "$LIBFFI_SRC" -mindepth 2 -maxdepth 2 -type d -name include \
            -print -quit 2>/dev/null || true)"
    [ -n "$d" ] || d="$LIBFFI_SRC/include"
    printf '%s' "$d"
}

# Path to the static libffi.a produced by `make`. libffi puts the build
# under $LIBFFI_SRC/<host-triple>/.libs/libffi.a, where the triple comes
# from autoconf detection (e.g. x86_64-pc-linux-gnu, aarch64-apple-darwin).
libffi_static_lib() {
    local d
    d="$(find "$LIBFFI_SRC" -mindepth 3 -maxdepth 3 -type f -name libffi.a \
            -path '*/.libs/libffi.a' -print -quit 2>/dev/null || true)"
    [ -n "$d" ] || d="$LIBFFI_SRC/.libs/libffi.a"
    printf '%s' "$d"
}

# Detect the OpenSSL SHLIB_VERSION ("3" today). Threaded into the
# patchelf / install_name_tool calls below so soname-bearing filenames
# adapt automatically when the pinned version moves to a new major.
# OpenSSL's SHLIB_VERSION equals MAJOR on the 3.x line; the post-extract
# VERSION.dat (only present after setup_openssl has run) is parsed
# defensively in case a future minor changes that.
openssl_shlib_version() {
    if [ -f "$OPENSSL_SRC/VERSION.dat" ]; then
        awk -F= '/^SHLIB_VERSION=/ { gsub(/[ \t\r]/, "", $2); print $2; exit }' \
            "$OPENSSL_SRC/VERSION.dat"
    else
        # Pre-download fallback: derive from the pinned version's major.
        printf '%s' "${OPENSSL_VERSION%%.*}"
    fi
}

# Download + verify + extract the upstream OpenSSL tarball into
# $OPENSSL_CACHE/openssl-$OPENSSL_VERSION/. Idempotent — the cache lives
# outside $BUILD so re-runs of the build script (which wipes $BUILD via
# prep_build_tree) reuse the already-fetched tarball.
#
# OpenSSL publishes per-tarball .sha256 sidecars on its GitHub Releases.
# The expected hash is pinned in-tree at MagPython/openssl-sha256 and
# checked against the downloaded bytes; the upstream sidecar is also
# fetched and cross-checked as defense-in-depth (mirrors the Windows
# download-openssl.ps1).
setup_openssl() {
    if [ -d "$OPENSSL_SRC" ]; then return 0; fi

    log "Fetching OpenSSL $OPENSSL_VERSION"
    mkdir -p "$OPENSSL_CACHE"
    local base="https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION"
    local tarball="$OPENSSL_CACHE/openssl-$OPENSSL_VERSION.tar.gz"
    local sidecar="$tarball.sha256"

    if [ ! -f "$tarball" ]; then
        curl --fail --silent --show-error --location \
            -o "$tarball" "$base/openssl-$OPENSSL_VERSION.tar.gz"
    fi
    curl --fail --silent --show-error --location \
        -o "$sidecar" "$base/openssl-$OPENSSL_VERSION.tar.gz.sha256"

    local sha256_cmd
    if command -v shasum >/dev/null 2>&1; then sha256_cmd="shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then sha256_cmd="sha256sum"
    else echo "Need shasum or sha256sum" >&2; exit 1; fi

    local actual
    actual="$($sha256_cmd "$tarball" | awk '{print $1}')"
    if [ "$OPENSSL_SHA256" != "$actual" ]; then
        echo "OpenSSL SHA-256 mismatch: expected $OPENSSL_SHA256, got $actual" >&2
        echo "  (pinned in MagPython/openssl-sha256 — confirm against $base/openssl-$OPENSSL_VERSION.tar.gz.sha256 before changing)" >&2
        rm -f "$tarball" "$sidecar"
        exit 1
    fi
    local upstream
    upstream="$(awk '{print $1; exit}' "$sidecar")"
    if [ "$OPENSSL_SHA256" != "$upstream" ]; then
        echo "Upstream .sha256 sidecar disagrees with MagPython/openssl-sha256: sidecar=$upstream, pinned=$OPENSSL_SHA256" >&2
        rm -f "$tarball" "$sidecar"
        exit 1
    fi
    rm -f "$sidecar"

    tar -xzf "$tarball" -C "$OPENSSL_CACHE"
}

# Build OpenSSL as shared libs at $BUILD/openssl-out.
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
    setup_openssl
    log "Building OpenSSL ($target)"
    (cd "$OPENSSL_SRC"
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
    log "Installing MagPython/Setup.local -> python-$PYTHON_VERSION/Modules/Setup.local"
    cp "$REPO/MagPython/Setup.local" "$PYTHON_SRC/Modules/Setup.local"
}

# Configure CPython for the libMagPython build. Caller cd's into a build dir.
# $1: extra LDFLAGS_NODIST (e.g. rpath flag)
# remaining args: appended to configure (e.g. MACOSX_DEPLOYMENT_TARGET=11.0)
configure_libmagpython() {
    local extra_ldflags="$1"; shift
    local libffi_inc libffi_lib
    libffi_inc="$(libffi_include_dir)"
    libffi_lib="$(libffi_static_lib)"
    # CPython's configure has --with-system-libmpdec on by default and
    # uses pkg-config; with no .pc on PATH it falls back to "-lmpdec -lm"
    # ELSE the user-supplied LIBMPDEC_CFLAGS / LIBMPDEC_LIBS. Pointing the
    # latter at the static .a we just built mirrors how zlib and libffi
    # are wired in, and stops _decimal from picking up a system libmpdec
    # instead.
    #
    # sqlite3 is wired in as -L<dir> -lsqlite3 rather than a bare .a
    # path because configure runs AC_CHECK_LIB([sqlite3], ...) probes
    # that prepend a literal -lsqlite3 to the link line; on hosts
    # without sqlite-devel that prepended -l can't be resolved (the
    # linker only sees our $BUILD/sqlite directory via LIBSQLITE3_LIBS
    # AFTER the -l, which is too late) and configure marks
    # have_supported_sqlite3=no, dropping _sqlite3 from the build.
    # Pre-cache the probe results below so AC_CHECK_LIB never runs the
    # link tests at all — have_supported_sqlite3 stays yes regardless
    # of how the host's linker would resolve `-lsqlite3`. The actual
    # `_sqlite3` build link still uses LIBSQLITE3_LIBS, where our -L
    # IS in effect (no AC_CHECK_LIB-prepended -l ahead of it), so the
    # linker picks our pinned libsqlite3.a (the only file in
    # $BUILD/sqlite). Pre-caching is robust to linker quirks (e.g. ld
    # implementations that prefer .so across all -L dirs over .a in any).
    "$PYTHON_SRC/configure" \
        --enable-shared \
        --without-static-libpython \
        --with-openssl="$BUILD/openssl-out" \
        --with-openssl-rpath=auto \
        --with-system-ffi \
        --with-system-libmpdec \
        --disable-test-modules \
        --without-pymalloc-debug \
        LIBFFI_CFLAGS="-I$libffi_inc -I$LIBFFI_SRC/include" \
        LIBFFI_LIBS="$libffi_lib" \
        ZLIB_CFLAGS="-I$ZLIB_SRC" \
        ZLIB_LIBS="$ZLIB_SRC/libz.a" \
        LIBSQLITE3_CFLAGS="-I$SQLITE_SRC" \
        LIBSQLITE3_LIBS="-L$BUILD/sqlite -lsqlite3" \
        LIBMPDEC_CFLAGS="-I$BUILD/libmpdec-out/include" \
        LIBMPDEC_LIBS="$BUILD/libmpdec-out/lib/libmpdec.a -lm" \
        CURSES_CFLAGS="-DHAVE_NCURSESW=1 -I$BUILD/ncurses-out/include -I$BUILD/ncurses-out/include/ncursesw" \
        CURSES_LIBS="$BUILD/ncurses-out/lib/libncursesw.a" \
        PANEL_CFLAGS="-DHAVE_NCURSESW=1 -I$BUILD/ncurses-out/include -I$BUILD/ncurses-out/include/ncursesw" \
        PANEL_LIBS="$BUILD/ncurses-out/lib/libpanelw.a $BUILD/ncurses-out/lib/libncursesw.a" \
        CFLAGS_NODIST="-fPIC" \
        LDFLAGS_NODIST="$extra_ldflags" \
        ac_cv_lib_sqlite3_sqlite3_bind_double=yes \
        ac_cv_lib_sqlite3_sqlite3_column_decltype=yes \
        ac_cv_lib_sqlite3_sqlite3_column_double=yes \
        ac_cv_lib_sqlite3_sqlite3_complete=yes \
        ac_cv_lib_sqlite3_sqlite3_progress_handler=yes \
        ac_cv_lib_sqlite3_sqlite3_result_double=yes \
        ac_cv_lib_sqlite3_sqlite3_set_authorizer=yes \
        ac_cv_lib_sqlite3_sqlite3_trace_v2=yes \
        ac_cv_lib_sqlite3_sqlite3_value_double=yes \
        ac_cv_lib_sqlite3_sqlite3_load_extension=yes \
        ac_cv_lib_sqlite3_sqlite3_serialize=yes \
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
    find "$OPENSSL_SRC/include/crypto" -maxdepth 1 -type f -iname '*.h' \
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
    cp -R "$PYTHON_SRC/Include/." "$STAGE/include/Python/"
    cp "$build_dir/pyconfig.h" "$STAGE/include/Python/pyconfig.h"
    # Only .py files from the stdlib tree. Use a tar pipe so we don't depend
    # on rsync (manylinux_2_28 doesn't ship it) or GNU-specific cp --parents.
    (cd "$PYTHON_SRC/Lib" && find . -name '*.py' -print0 | tar --null -T - -cf -) \
        | (cd "$STAGE/lib/python$PY_X_Y" && tar -xf -)
}

# Verify $1 (the libMagPython artifact) has no dynamic linkage to any of
# the deps we statically bundle. A leakage here means the build picked
# up a system libsqlite3 / libmpdec / libffi / libz at link time despite
# our LIBxxx_LIBS / LIBxxx_CFLAGS settings — which can happen if the
# build host has the matching -dev package installed and its
# /usr/lib<arch> happens to be searched ahead of our $BUILD/<dep>
# directory by the linker. The configure-time AC_CHECK_LIB probes can
# also inadvertently pull in a system .so when AC_CHECK_LIB prepends
# `-lsqlite3` to LIBS without our `-L` first. Both failure modes are
# invisible at configure time and to the structural built-in-module
# check in test.c (the C extension is still in libMagPython, it's just
# *calling* the system .so for sqlite3 functions). Only post-link
# inspection catches it.
verify_no_static_dep_leakage() {
    local libpath="$1"
    log "Verifying $(basename "$libpath") has no dynamic linkage to bundled deps"
    local deps
    case "$(uname -s)" in
        Linux)
            # readelf -d prints NEEDED entries as `[libname.so.N]`.
            deps="$(readelf -d "$libpath" | awk '/NEEDED/ { gsub(/[][]/, "", $5); print $5 }')"
            ;;
        Darwin)
            # otool -L's first line is the file itself; subsequent lines
            # are LC_LOAD_DYLIB references (`<path> (compatibility ...)`).
            deps="$(otool -L "$libpath" | tail -n +2 | awk '{ print $1 }')"
            ;;
        *)
            echo "verify_no_static_dep_leakage: unsupported OS $(uname -s)" >&2
            return 1
            ;;
    esac
    local forbidden hit fail=0
    # libsqlite3 / libmpdec / libffi / libz are all statically linked into
    # libMagPython and must not appear as a runtime dependency. libssl /
    # libcrypto are intentionally *not* in this list — they're the one dep
    # we ship as sibling .so/.dylib files (test.c verifies the loaded path).
    for forbidden in libsqlite3 libmpdec libffi libz; do
        hit="$(printf '%s\n' "$deps" | grep -E "(^|/)$forbidden\\.(so|dylib)" || true)"
        if [ -n "$hit" ]; then
            echo "ERROR: $libpath dynamically links $forbidden — bundled .a was not used:" >&2
            printf '  %s\n' $hit >&2
            fail=1
        fi
    done
    if [ "$fail" -ne 0 ]; then
        echo "Inspect LIBSQLITE3_LIBS / LIBMPDEC_LIBS / LIBFFI / ZLIB_LIBS in" >&2
        echo "configure_libmagpython and the build host's installed -dev packages." >&2
        exit 1
    fi
}

# Build and run the smoke test (MagPython/test.c) against the staged tree.
# $1: rpath token ('$ORIGIN' on Linux, '@loader_path' on macOS).
# $2..: extra link args (e.g. '-ldl' on Linux for dladdr; macOS has it
#       in libSystem and Windows in kernel32, so no extra arg there).
#
# The cc invocation deliberately uses ONLY $STAGE for both -I and -L: the
# build dir's openssl-out/ and CPython build outputs are off the search path,
# so a missing header or unversioned shared-lib symlink (e.g. libssl.dylib ->
# libssl.<ver>.dylib) in the artifact is a hard failure here rather than a
# silent fallback to the build tree.
run_smoke_test() {
    local rpath_token="$1"; shift
    log "Building smoke test"
    cc "$REPO/MagPython/test.c" \
        -I"$STAGE/include" \
        -L"$STAGE" \
        "-Wl,-rpath,${rpath_token}" \
        -lMagPython -lssl -lcrypto \
        "$@" \
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

# Stage the upstream license / NOTICE files from each pinned dep into
# $STAGE/licenses/ as a flat tree of <dep>-license.txt files. Each file
# starts with a "<dep> <version>" header line so the project and pinned
# version are unambiguous to a downstream consumer; the upstream license
# text follows after a blank line. Per-dep:
#   cpython  -> LICENSE                          (PSF)
#   openssl  -> LICENSE.txt                      (Apache-2.0 since 3.x)
#   libffi   -> LICENSE                          (MIT; LICENSE-BUILDTOOLS
#               covers autotools wrappers we don't redistribute)
#   libmpdec -> LICENSE.txt                      (BSD)
#   zlib     -> LICENSE                          (zlib)
#   sqlite   -> leading /* ... */ block of sqlite3.h. The amalgamation
#               zip ships only sqlite3.{c,h}/sqlite3ext.h/shell.c — the
#               public-domain blessing lives in that comment block (the
#               same text https://www.sqlite.org/copyright.html publishes).
#   ncurses  -> ANNOUNCE (release blurb naming the upstream maintainer)
#               concatenated with COPYING (the MIT-style "X11" license).
#               POSIX-only — the Windows artifact ships no curses.
stage_licenses() {
    log "Staging license files into licenses/"
    rm -rf "$STAGE/licenses"
    mkdir -p "$STAGE/licenses"

    _stage_license() {
        local dep="$1" version="$2" src_dir="$3" filename="$4"
        if [ ! -f "$src_dir/$filename" ]; then
            echo "stage_licenses: $filename not found in $src_dir (for $dep)" >&2
            exit 1
        fi
        {
            printf '%s %s\n\n' "$dep" "$version"
            cat "$src_dir/$filename"
        } > "$STAGE/licenses/${dep}-license.txt"
    }

    _stage_license cpython   "$PYTHON_VERSION"   "$PYTHON_SRC"   LICENSE
    _stage_license openssl   "$OPENSSL_VERSION"  "$OPENSSL_SRC"  LICENSE.txt
    _stage_license libffi    "$LIBFFI_VERSION"   "$LIBFFI_SRC"   LICENSE
    _stage_license libmpdec  "$LIBMPDEC_VERSION" "$LIBMPDEC_SRC" LICENSE.txt
    _stage_license zlib      "$ZLIB_VERSION"     "$ZLIB_SRC"     LICENSE

    {
        printf 'sqlite %s\n\n' "$SQLITE_VERSION"
        awk '
            /^\/\*/         { in_block = 1 }
            in_block        { print }
            in_block && /\*\// { exit }
        ' "$SQLITE_SRC/sqlite3.h"
    } > "$STAGE/licenses/sqlite-license.txt"
    # Guard against an unexpectedly-empty awk extraction (e.g. upstream
    # restructures sqlite3.h's leading comment): the header line we just
    # wrote means the file is never zero-byte, so check for the blessing
    # text instead.
    if ! grep -q 'disclaims copyright' "$STAGE/licenses/sqlite-license.txt"; then
        echo "stage_licenses: failed to extract leading comment block from $SQLITE_SRC/sqlite3.h" >&2
        exit 1
    fi

    # ncurses: the upstream tarball doesn't ship a single LICENSE file —
    # ANNOUNCE names the upstream maintainer and the release; COPYING
    # holds the MIT-style "X11" blessing. Concatenate both so the staged
    # file carries both pieces upstream points consumers at.
    for f in ANNOUNCE COPYING; do
        if [ ! -f "$NCURSES_SRC/$f" ]; then
            echo "stage_licenses: $f not found in $NCURSES_SRC (for ncurses)" >&2
            exit 1
        fi
    done
    {
        printf 'ncurses %s\n\n' "$NCURSES_VERSION"
        cat "$NCURSES_SRC/ANNOUNCE"
        printf '\n--- COPYING ---\n\n'
        cat "$NCURSES_SRC/COPYING"
    } > "$STAGE/licenses/ncurses-license.txt"
}

zip_artifact() {
    local platform="$1"
    local out="$REPO/MagPython-${platform}.zip"
    log "Zipping artifact -> $out"
    rm -f "$out"
    (cd "$BUILD/stage" && zip -qr "$out" MagPython)
    ls -lh "$out"
}
