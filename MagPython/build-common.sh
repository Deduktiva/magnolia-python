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
    if [ -d "$PYTHON_SRC" ]; then return 0; fi

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
    # latter at the static .a we just built mirrors how zlib / sqlite /
    # libffi are wired in, and stops _decimal from picking up a system
    # libmpdec instead.
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
        LIBSQLITE3_LIBS="$BUILD/sqlite/libsqlite3.a" \
        LIBMPDEC_CFLAGS="-I$BUILD/libmpdec-out/include" \
        LIBMPDEC_LIBS="$BUILD/libmpdec-out/lib/libmpdec.a -lm" \
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

# Stage the upstream license / NOTICE files from each pinned dep into
# $STAGE/licenses/<dep>/. Consumers of the artifact zip can drop the
# resulting tree into their own build's third-party-licenses directory
# verbatim. Per-dep:
#   cpython  -> LICENSE                          (PSF)
#   openssl  -> LICENSE.txt                      (Apache-2.0 since 3.x)
#   libffi   -> LICENSE [+ LICENSE-BUILDTOOLS]   (MIT + autotools notice)
#   libmpdec -> LICENSE.txt                      (BSD)
#   zlib     -> LICENSE                          (zlib)
#   sqlite   -> leading /* ... */ block of sqlite3.h. The amalgamation
#               zip ships only sqlite3.{c,h}/sqlite3ext.h/shell.c — the
#               public-domain blessing lives in that comment block (the
#               same text https://www.sqlite.org/copyright.html publishes).
stage_licenses() {
    log "Staging license files into licenses/"
    rm -rf "$STAGE/licenses"
    mkdir -p "$STAGE/licenses"

    _copy_license() {
        local dep="$1" src_dir="$2"; shift 2
        mkdir -p "$STAGE/licenses/$dep"
        local found=0 f
        for f in "$@"; do
            if [ -f "$src_dir/$f" ]; then
                cp "$src_dir/$f" "$STAGE/licenses/$dep/"
                found=1
            fi
        done
        if [ "$found" -eq 0 ]; then
            echo "stage_licenses: no license file found for $dep in $src_dir (looked for: $*)" >&2
            exit 1
        fi
    }

    _copy_license cpython   "$PYTHON_SRC"   LICENSE
    _copy_license openssl   "$OPENSSL_SRC"  LICENSE.txt
    _copy_license libffi    "$LIBFFI_SRC"   LICENSE LICENSE-BUILDTOOLS
    _copy_license libmpdec  "$LIBMPDEC_SRC" LICENSE.txt
    _copy_license zlib      "$ZLIB_SRC"     LICENSE

    mkdir -p "$STAGE/licenses/sqlite"
    awk '
        /^\/\*/         { in_block = 1 }
        in_block        { print }
        in_block && /\*\// { exit }
    ' "$SQLITE_SRC/sqlite3.h" > "$STAGE/licenses/sqlite/LICENSE.txt"
    if [ ! -s "$STAGE/licenses/sqlite/LICENSE.txt" ]; then
        echo "stage_licenses: failed to extract leading comment block from $SQLITE_SRC/sqlite3.h" >&2
        exit 1
    fi
}

zip_artifact() {
    local platform="$1"
    local out="$REPO/MagPython-${platform}.zip"
    log "Zipping artifact -> $out"
    rm -f "$out"
    (cd "$BUILD/stage" && zip -qr "$out" MagPython)
    ls -lh "$out"
}
