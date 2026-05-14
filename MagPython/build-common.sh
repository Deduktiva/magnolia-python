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

# Qt6 is downloaded at build time rather than vendored. POSIX-only here;
# windows-x64 uses the same pin via build-pyside6-windows.sh (which sources
# this file in spirit but runs Qt6's CMake build natively, not through the
# POSIX helpers below). windows-x86 ships no Qt/PySide6 — Qt 6 dropped
# 32-bit Windows entirely. Only qtbase is built, with every feature except
# Core disabled, so the artifact carries one library (libQt6Core) plus
# PySide6.QtCore bindings — enough for a downstream host application to
# embed Qt's event loop, signal/slot, QObject, and property system.
# Anything beyond Core is the downstream's responsibility to add (see
# README's PySide6 section for the recipe).
QT6_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/qt6-version")"
if [ -z "$QT6_VERSION" ]; then
    echo "Failed to read Qt6 version from MagPython/qt6-version" >&2
    exit 1
fi
QT6_SHA256="$(tr -d '[:space:]' < "$REPO/MagPython/qt6-sha256")"
if [ -z "$QT6_SHA256" ]; then
    echo "Failed to read Qt6 sha256 from MagPython/qt6-sha256" >&2
    exit 1
fi
QT6_CACHE="$REPO/MagPython/qt6"
QT6_SRC="$QT6_CACHE/qtbase-everywhere-src-$QT6_VERSION"
# Qt6's release stream uses major.minor.0 / major.minor.1 / ... within a
# major.minor track, with the tarball directory derived from the
# major.minor pair. Pre-compute the track so the URL stays a single
# substitution.
QT6_TRACK="$(printf '%s' "$QT6_VERSION" | awk -F. '{ printf "%s.%s\n", $1, $2 }')"

# PySide6 is the Python bindings for Qt; bundled in this artifact rather
# than installed from the PyPI wheel because the wheels' .abi3.so files
# are built against the upstream CPython runtime and have rpaths /
# Qt-library dependencies that don't match MagPython's relocatable
# $ORIGIN-rpath shape. Building from source against our libMagPython +
# our Qt6 produces a binary that ships next to libMagPython.so with
# matching linkage. POSIX-only — see QT6 block above.
#
# Same version pin as Qt6: PySide6 6.X.Y is built against Qt 6.X (the
# tarball major.minor must match the host Qt's major.minor, with the
# PySide6 patch number free to differ). Set to 6.8.0 in this PR.
PYSIDE6_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/pyside6-version")"
if [ -z "$PYSIDE6_VERSION" ]; then
    echo "Failed to read PySide6 version from MagPython/pyside6-version" >&2
    exit 1
fi
PYSIDE6_SHA256="$(tr -d '[:space:]' < "$REPO/MagPython/pyside6-sha256")"
if [ -z "$PYSIDE6_SHA256" ]; then
    echo "Failed to read PySide6 sha256 from MagPython/pyside6-sha256" >&2
    exit 1
fi
PYSIDE6_CACHE="$REPO/MagPython/pyside6"
# Qt names the PySide6 source tarball with the major.minor (no patch)
# even when the directory uses the full version — e.g.
# `PySide6-6.8.0-src/pyside-setup-everywhere-src-6.8.tar.xz`. Carry both
# forms so the URL and the extracted-dir path stay in lockstep.
PYSIDE6_MAJOR_MINOR="$(printf '%s' "$PYSIDE6_VERSION" | awk -F. '{ printf "%s.%s\n", $1, $2 }')"
PYSIDE6_SRC="$PYSIDE6_CACHE/pyside-setup-everywhere-src-$PYSIDE6_MAJOR_MINOR"

log() { printf '\n=== %s ===\n' "$*"; }

prep_build_tree() {
    rm -rf "$BUILD"
    mkdir -p "$BUILD" "$STAGE"
}

# Build zlib as a static lib at $ZLIB_SRC/libz.a. Linked into libpython.
build_zlib_static() {
    setup_zlib
    log "Building zlib static lib"
    # zlib's configure doesn't add -fPIC under --static, but we link the .a
    # into a shared libpython, so pass it explicitly.
    (cd "$ZLIB_SRC"
     [ -f Makefile ] && make distclean >/dev/null 2>&1 || true
     CFLAGS="-O3 -fPIC" ./configure --static
     make -j"$JOBS" libz.a)
}

# Build libffi as a static lib at $LIBFFI_SRC/<triple>/.libs/libffi.a (plus
# generated headers next to it). Linked into libpython. Linux-only — on macOS
# the build uses the system libffi shipped with the SDK.
# $1 (optional): libffi --host triple (for cross-build edge cases).
build_libffi_static() {
    local libffi_host="${1:-}"
    setup_libffi
    log "Building libffi static lib"
    (cd "$LIBFFI_SRC"
     [ -f Makefile ] && make distclean >/dev/null 2>&1 || true
     local args=(--enable-static --disable-shared --with-pic --disable-docs)
     [ -n "$libffi_host" ] && args+=(--host="$libffi_host")
     ./configure "${args[@]}"
     make -j"$JOBS")
}

# Build sqlite3 as a shared lib at $BUILD/sqlite/libsqlite3.<so.0|0.dylib>
# (with the unversioned $BUILD/sqlite/libsqlite3.<so|dylib> symlink the
# linker resolves `-lsqlite3` against). Shipped as a sibling of libMagPython
# in the artifact.
#
# Building shared (rather than the previous static .a) lets CPython's
# configure find sqlite3 the normal autoconf way: AC_CHECK_LIB([sqlite3],
# ...) link probes resolve `-lsqlite3` against $BUILD/sqlite via -L without
# an order-of-arguments dance. The previous static path needed the
# ac_cv_lib_sqlite3_* cache to be pre-populated to skip those probes
# entirely; shared lib + standard -L makes that workaround unnecessary.
#
# Soname / install_name use the major-zero suffix matching the convention
# Linux distros and Homebrew apply to their libsqlite3 packages, so
# libMagPython's recorded NEEDED / LC_LOAD_DYLIB entry has the same shape
# a host application sees from a system sqlite.
build_sqlite_shared() {
    setup_sqlite
    log "Building sqlite3 shared lib"
    mkdir -p "$BUILD/sqlite"
    case "$(uname -s)" in
        Darwin)
            cc -dynamiclib -O2 -fPIC \
               -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_JSON1 \
               -install_name "@rpath/libsqlite3.0.dylib" \
               "$SQLITE_SRC/sqlite3.c" \
               -o "$BUILD/sqlite/libsqlite3.0.dylib"
            ln -sf libsqlite3.0.dylib "$BUILD/sqlite/libsqlite3.dylib"
            ;;
        *)
            cc -shared -O2 -fPIC \
               -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_JSON1 \
               -Wl,-soname,libsqlite3.so.0 \
               "$SQLITE_SRC/sqlite3.c" \
               -o "$BUILD/sqlite/libsqlite3.so.0" \
               -lm -lpthread
            ln -sf libsqlite3.so.0 "$BUILD/sqlite/libsqlite3.so"
            ;;
    esac
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
}

# Download + verify + extract the upstream zlib tarball into
# $ZLIB_CACHE/zlib-$ZLIB_VERSION/. Idempotent — the cache lives outside
# $BUILD so re-runs of the build script (which wipes $BUILD via
# prep_build_tree) reuse the already-fetched tarball.
#
# The expected hash is pinned in-tree at MagPython/zlib-sha256 and
# checked against the downloaded bytes.
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
# The expected hash is pinned in-tree at MagPython/sqlite-sha256 and
# checked against the downloaded bytes.
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
# The expected hash is pinned in-tree at MagPython/libffi-sha256 and
# checked against the downloaded bytes.
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
# The expected hash is pinned in-tree at MagPython/libmpdec-sha256 and
# checked against the downloaded bytes.
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
# The expected hash is pinned in-tree at MagPython/openssl-sha256 and
# checked against the downloaded bytes.
setup_openssl() {
    if [ -d "$OPENSSL_SRC" ]; then return 0; fi

    log "Fetching OpenSSL $OPENSSL_VERSION"
    mkdir -p "$OPENSSL_CACHE"
    local base="https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION"
    local tarball="$OPENSSL_CACHE/openssl-$OPENSSL_VERSION.tar.gz"

    if [ ! -f "$tarball" ]; then
        curl --fail --silent --show-error --location \
            -o "$tarball" "$base/openssl-$OPENSSL_VERSION.tar.gz"
    fi

    local sha256_cmd
    if command -v shasum >/dev/null 2>&1; then sha256_cmd="shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then sha256_cmd="sha256sum"
    else echo "Need shasum or sha256sum" >&2; exit 1; fi

    local actual
    actual="$($sha256_cmd "$tarball" | awk '{print $1}')"
    if [ "$OPENSSL_SHA256" != "$actual" ]; then
        echo "OpenSSL SHA-256 mismatch: expected $OPENSSL_SHA256, got $actual" >&2
        echo "  (pinned in MagPython/openssl-sha256 — regenerate via" >&2
        echo "   MagPython/update-openssl.sh before changing)" >&2
        rm -f "$tarball"
        exit 1
    fi

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
# remaining args: appended to configure (e.g. LIBFFI_CFLAGS=... on Linux,
# MACOSX_DEPLOYMENT_TARGET=11.0 on macOS).
configure_libmagpython() {
    local extra_ldflags="$1"; shift
    # CPython's configure has --with-system-libmpdec on by default and
    # uses pkg-config; with no .pc on PATH it falls back to "-lmpdec -lm"
    # ELSE the user-supplied LIBMPDEC_CFLAGS / LIBMPDEC_LIBS. Pointing the
    # latter at the static .a we just built mirrors how zlib and libffi
    # are wired in, and stops _decimal from picking up a system libmpdec
    # instead.
    #
    # sqlite3 is wired in as a normal -I/-L/-lsqlite3 triple. The shared
    # libsqlite3 in $BUILD/sqlite has the conventional libsqlite3.so.0 /
    # libsqlite3.0.dylib soname (with the unversioned symlink the linker
    # resolves -lsqlite3 against), so AC_CHECK_LIB's link probes succeed
    # the normal autoconf way — no ac_cv_* cache pre-population needed.
    #
    # All link flags go into LDFLAGS rather than LDFLAGS_NODIST because
    # CPython's Makefile.pre.in defines:
    #   PY_LDFLAGS_NOLTO=$(PY_LDFLAGS) $(CONFIGURE_LDFLAGS_NOLTO) $(LDFLAGS_NODIST)
    # which is used by Programs/_bootstrap_python — a build-time helper
    # that loads libpython to freeze modules. PY_LDFLAGS_NOLTO references
    # only $(LDFLAGS_NODIST), NOT $(CONFIGURE_LDFLAGS_NODIST) (the
    # autoconf-substituted value of the LDFLAGS_NODIST configure env).
    # Anything we set via LDFLAGS_NODIST=... at configure-time therefore
    # never reaches _bootstrap_python's link, and it dies with
    # "Library not loaded: @rpath/libsqlite3.0.dylib" the first time the
    # build tries to freeze a module. _freeze_module avoids this by using
    # PY_CORE_LDFLAGS (which includes both NODIST vars).
    # PY_LDFLAGS = $(CONFIGURE_LDFLAGS) $(LDFLAGS) is used unconditionally
    # by every link rule, so LDFLAGS is the one variable that reaches all
    # of them. We don't ship CPython's sysconfig, so the LDFLAGS-vs-NODIST
    # "don't leak into user wheels" distinction doesn't apply here.
    # The $BUILD/sqlite rpath is build-only — the macOS staging step
    # strips any LC_RPATH under $BUILD, and Linux's `patchelf --set-rpath`
    # replaces the full RPATH at staging.
    #
    # libffi is platform-split: on Linux the caller passes
    # LIBFFI_CFLAGS / LIBFFI_LIBS pointing at the static libffi.a built
    # by build_libffi_static; on macOS no LIBFFI_* are passed and
    # CPython's own Darwin-specific block in configure picks up the
    # SDK's ffi.h + /usr/lib/libffi.dylib.
    "$PYTHON_SRC/configure" \
        --enable-shared \
        --without-static-libpython \
        --with-openssl="$BUILD/openssl-out" \
        --with-openssl-rpath=auto \
        --with-system-ffi \
        --with-system-libmpdec \
        --disable-test-modules \
        --without-pymalloc-debug \
        ZLIB_CFLAGS="-I$ZLIB_SRC" \
        ZLIB_LIBS="$ZLIB_SRC/libz.a" \
        LIBSQLITE3_CFLAGS="-I$SQLITE_SRC" \
        LIBSQLITE3_LIBS="-lsqlite3" \
        LIBMPDEC_CFLAGS="-I$BUILD/libmpdec-out/include" \
        LIBMPDEC_LIBS="$BUILD/libmpdec-out/lib/libmpdec.a -lm" \
        CURSES_CFLAGS="-DHAVE_NCURSESW=1 -I$BUILD/ncurses-out/include -I$BUILD/ncurses-out/include/ncursesw" \
        CURSES_LIBS="$BUILD/ncurses-out/lib/libncursesw.a" \
        PANEL_CFLAGS="-DHAVE_NCURSESW=1 -I$BUILD/ncurses-out/include -I$BUILD/ncurses-out/include/ncursesw" \
        PANEL_LIBS="$BUILD/ncurses-out/lib/libpanelw.a $BUILD/ncurses-out/lib/libncursesw.a" \
        CFLAGS_NODIST="-fPIC" \
        LDFLAGS="-L$BUILD/sqlite -Wl,-rpath,$BUILD/sqlite $extra_ldflags" \
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
    # Pull in the build-generated _sysconfigdata_<abi>_<plat>_<multi>.py.
    # sysconfig._init_posix imports it by name (see Lib/sysconfig/__init__.py
    # _get_sysconfigdata_name); upstream's `make install` would copy it
    # alongside the rest of the stdlib, but we don't run install — only
    # make. Without it, anything that asks sysconfig for config vars
    # (e.g. `help()` → pydoc → sysconfig.get_path) raises
    # ModuleNotFoundError on first use. The `pybuilddir.txt` Makefile
    # target writes the file under build/lib.<platform>-cpython-X.Y/;
    # exactly one such .py per build.
    local sysconfigdata_file
    sysconfigdata_file="$(find "$build_dir/build" -maxdepth 2 -type f -name '_sysconfigdata_*.py' -print -quit 2>/dev/null || true)"
    if [ -z "$sysconfigdata_file" ]; then
        echo "stage_headers_and_stdlib: could not find generated _sysconfigdata_*.py under $build_dir/build/" >&2
        exit 1
    fi
    cp "$sysconfigdata_file" "$STAGE/lib/python$PY_X_Y/"
}

# Verify $1 (the libMagPython artifact) has no dynamic linkage to any of
# the deps we statically bundle. A leakage here means the build picked
# up a system libmpdec / libffi / libz at link time despite our
# LIBxxx_LIBS / LIBxxx_CFLAGS settings — which can happen if the build
# host has the matching -dev package installed and its /usr/lib<arch>
# happens to be searched ahead of our $BUILD/<dep> directory by the
# linker. Invisible at configure time and to the structural
# built-in-module check in test.c (the C extension is still in
# libMagPython, it's just *calling* the system .so for those functions).
# Only post-link inspection catches it.
#
# libsqlite3 is intentionally NOT in the forbidden list — it's shipped as
# a sibling .so/.dylib (built by build_sqlite_shared and staged next to
# libMagPython). libffi is forbidden on Linux but allowed on macOS, where
# the build deliberately uses the SDK's libffi (/usr/lib/libffi.dylib) —
# CPython's Darwin block in configure auto-detects it.
verify_no_static_dep_leakage() {
    local libpath="$1"
    log "Verifying $(basename "$libpath") has no dynamic linkage to bundled deps"
    local deps forbidden_deps
    case "$(uname -s)" in
        Linux)
            # readelf -d prints NEEDED entries as `[libname.so.N]`.
            deps="$(readelf -d "$libpath" | awk '/NEEDED/ { gsub(/[][]/, "", $5); print $5 }')"
            forbidden_deps="libmpdec libffi libz"
            ;;
        Darwin)
            # otool -L's first line is the file itself; subsequent lines
            # are LC_LOAD_DYLIB references (`<path> (compatibility ...)`).
            deps="$(otool -L "$libpath" | tail -n +2 | awk '{ print $1 }')"
            forbidden_deps="libmpdec libz"
            ;;
        *)
            echo "verify_no_static_dep_leakage: unsupported OS $(uname -s)" >&2
            return 1
            ;;
    esac
    local forbidden hit fail=0
    for forbidden in $forbidden_deps; do
        hit="$(printf '%s\n' "$deps" | grep -E "(^|/)$forbidden\\.(so|dylib)" || true)"
        if [ -n "$hit" ]; then
            echo "ERROR: $libpath dynamically links $forbidden — bundled .a was not used:" >&2
            printf '  %s\n' $hit >&2
            fail=1
        fi
    done
    if [ "$fail" -ne 0 ]; then
        echo "Inspect LIBMPDEC_LIBS / LIBFFI / ZLIB_LIBS in" >&2
        echo "configure_libmagpython and the build host's installed -dev packages." >&2
        exit 1
    fi
}

# Build the MagPython executable (CPython's Programs/python.c — a tiny
# wrapper around Py_BytesMain) and stage it next to libMagPython in the
# artifact tree. Counterpart to MagPython.exe on Windows
# (MagPythonExe.vcxproj). Dynamically linked against libMagPython.so/.dylib
# via -lMagPython; rpath '$ORIGIN' / '@loader_path' so the binary finds
# its sibling lib + lib/python<X.Y>/ stdlib without env vars when invoked
# from inside the artifact dir.
#
# Also stages a `python3` copy next to it so consumers expecting the
# canonical CPython binary name find one in the artifact. Same shape
# upstream uses (python3 alongside python3.<minor> on Linux/macOS); a
# copy rather than a symlink keeps `zip` happy across all three
# platforms (Windows artifact does the same — see MagPythonExe.vcxproj).
# $1: rpath token ('$ORIGIN' on Linux, '@loader_path' on macOS).
build_magpython_exe() {
    local rpath_token="$1"
    log "Building MagPython executable"
    cc "$PYTHON_SRC/Programs/python.c" \
        -I"$STAGE/include/Python" \
        -L"$STAGE" \
        "-Wl,-rpath,${rpath_token}" \
        -lMagPython \
        -o "$STAGE/MagPython"
    log "Smoke-testing MagPython --version"
    (cd "$STAGE" && ./MagPython --version)
    log "Staging python3 alias next to MagPython"
    cp "$STAGE/MagPython" "$STAGE/python3"
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
    # -DMAGPYTHON_TEST_PYSIDE6 enables the PySide6 import + Q*Application
    # block in test.c. The PySide6 bundle is staged into
    # $STAGE/site-packages by stage_pyside6 on POSIX; if a future build
    # script ends up here without having staged PySide6 (e.g. a stripped
    # platform that intentionally omits it), pass -UMAGPYTHON_TEST_PYSIDE6
    # in $@.
    cc "$REPO/MagPython/test.c" \
        -DMAGPYTHON_TEST_PYSIDE6=1 \
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
    #
    # QT_QPA_PLATFORM=offscreen forces Qt to use the headless platform
    # plugin so the smoke test runs on CI machines without an X server
    # / display attached. We don't ship QtGui in the artifact today, so
    # this is defensive against a future QtGui addition triggering
    # platform-plugin discovery.
    (cd "$STAGE" && QT_QPA_PLATFORM=offscreen ./MagPython_test)
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
#               Linux only — macOS uses the SDK's libffi, no redistribution
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
    # libffi is bundled (static) only on Linux; on macOS we use the SDK's
    # libffi, so there's nothing to attach a LICENSE to here.
    if [ -d "$LIBFFI_SRC" ]; then
        _stage_license libffi "$LIBFFI_VERSION" "$LIBFFI_SRC" LICENSE
    fi
    _stage_license libmpdec  "$LIBMPDEC_VERSION" "$LIBMPDEC_SRC" LICENSE.txt
    _stage_license zlib      "$ZLIB_VERSION"     "$ZLIB_SRC"     LICENSE
    # Qt6 / PySide6 are POSIX-only and the source trees only exist
    # after setup_qt6 / setup_pyside6 has run — guard with `-d` so a
    # platform without them (or an early-exit before they're fetched)
    # doesn't break this step. Qt6 ships LICENSES/<text>.txt rather
    # than a single LICENSE file; LGPL-3.0-only is the active license
    # for qtbase. PySide6 ships LICENSES/LGPL-3.0-only.txt as well.
    if [ -d "$QT6_SRC" ] && [ -f "$QT6_SRC/LICENSES/LGPL-3.0-only.txt" ]; then
        _stage_license qt6 "$QT6_VERSION" "$QT6_SRC/LICENSES" LGPL-3.0-only.txt
    fi
    if [ -d "$PYSIDE6_SRC" ] && [ -f "$PYSIDE6_SRC/LICENSES/LGPL-3.0-only.txt" ]; then
        _stage_license pyside6 "$PYSIDE6_VERSION" "$PYSIDE6_SRC/LICENSES" LGPL-3.0-only.txt
    fi

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

# Download + verify + extract the upstream Qt6 qtbase tarball into
# $QT6_CACHE/qtbase-everywhere-src-$QT6_VERSION/. Idempotent — the cache
# lives outside $BUILD so re-runs of the build script (which wipes $BUILD
# via prep_build_tree) reuse the already-fetched tarball.
#
# We fetch the qtbase submodule tarball, not the full qt-everywhere
# tarball: PySide6.QtCore only needs qtbase Core, and the full source
# tree is ~1.5GB whereas qtbase alone is ~50MB. If a future module is
# added that needs (say) qtdeclarative or qtsvg, the equivalent
# submodule-only tarball can be fetched here in parallel.
#
# The expected hash is pinned in-tree at MagPython/qt6-sha256 and
# checked against the downloaded bytes.
setup_qt6() {
    if [ -d "$QT6_SRC" ]; then return 0; fi

    log "Fetching Qt6 qtbase $QT6_VERSION"
    mkdir -p "$QT6_CACHE"
    local url="https://download.qt.io/archive/qt/$QT6_TRACK/$QT6_VERSION/submodules/qtbase-everywhere-src-$QT6_VERSION.tar.xz"
    local tarball="$QT6_CACHE/qtbase-everywhere-src-$QT6_VERSION.tar.xz"

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
    if [ "$QT6_SHA256" != "$actual" ]; then
        echo "Qt6 qtbase SHA-256 mismatch: expected $QT6_SHA256, got $actual" >&2
        echo "  (pinned in MagPython/qt6-sha256 — confirm against the metalink at" >&2
        echo "   https://download.qt.io/archive/qt/$QT6_TRACK/$QT6_VERSION/submodules/qtbase-everywhere-src-$QT6_VERSION.tar.xz.metalink" >&2
        echo "   before changing)" >&2
        rm -f "$tarball"
        exit 1
    fi

    tar -xJf "$tarball" -C "$QT6_CACHE"
}

# Build Qt6 qtbase as a shared lib + headers + CMake config at
# $BUILD/qt6-out via upstream's CMake build. Only Core is enabled
# (every other qtbase feature is turned off via -DFEATURE_*=OFF so
# the build doesn't spend time on Gui / Widgets / Network / SQL / etc.,
# none of which Core needs and none of which PySide6.QtCore consumes).
# Output: $BUILD/qt6-out/lib/libQt6Core.{so,dylib} plus the
# Qt6CoreConfig.cmake bits PySide6's setup CMake reads.
#
# CMAKE_INSTALL_RPATH=$ORIGIN (Linux) / @loader_path (macOS) so
# libQt6Core can find sibling libs (if any are added later) the same
# way libMagPython does. Bundle install is `cmake --install` rather
# than `make install` because Qt6 dropped qmake-driven installs.
#
# CMake / Ninja are expected on PATH (installed via pip install
# ninja cmake / brew install ninja in the per-platform build scripts);
# C++17 compiler from the system toolchain.
#
# $1: extra cmake -D... args appended (e.g. -DCMAKE_OSX_DEPLOYMENT_TARGET
#     on macOS, an extra dependency hint on Linux).
build_qt6() {
    setup_qt6
    log "Configuring Qt6 qtbase $QT6_VERSION (Core only)"
    mkdir -p "$BUILD/qt6-build"

    local rpath_token
    case "$(uname -s)" in
        Darwin) rpath_token='@loader_path' ;;
        *)      rpath_token='$ORIGIN' ;;
    esac

    # Disable everything that isn't Core. Qt6's CMake build uses
    # `-DFEATURE_<name>=OFF` to skip a feature; the most relevant ones
    # are listed here. The set was derived by reading qtbase/configure.cmake
    # at the pinned version and noting which feature groups produce a
    # separate library that consumers might NEEDED-link. -DBUILD_<module>
    # toggles drop entire qtbase sub-libs.
    #
    # Host tools (qmake6, moc, rcc, uic, syncqt) are built by default —
    # PySide6's CMake invokes them while generating bindings and we'd
    # rather pay the few extra minutes here than figure out which
    # subset PySide6 actually wants. Same reason we don't pass
    # QT_BUILD_TOOLS_BY_DEFAULT=OFF: cmake_install.cmake still tries
    # to copy every tool's output and aborts on the first missing
    # libexec/<tool> file.
    cmake -S "$QT6_SRC" -B "$BUILD/qt6-build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$BUILD/qt6-out" \
        -DCMAKE_INSTALL_RPATH="$rpath_token" \
        -DBUILD_SHARED_LIBS=ON \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF \
        -DQT_FEATURE_gui=OFF \
        -DQT_FEATURE_widgets=OFF \
        -DQT_FEATURE_network=OFF \
        -DQT_FEATURE_sql=OFF \
        -DQT_FEATURE_testlib=OFF \
        -DQT_FEATURE_xml=OFF \
        -DQT_FEATURE_dbus=OFF \
        -DQT_FEATURE_concurrent=OFF \
        -DQT_FEATURE_printsupport=OFF \
        -DQT_FEATURE_opengl=OFF \
        -DQT_FEATURE_icu=OFF \
        "$@"

    log "Building Qt6 qtbase"
    cmake --build "$BUILD/qt6-build" -j "$JOBS"
    cmake --install "$BUILD/qt6-build"
}

# Download + verify + extract the upstream pyside-setup tarball into
# $PYSIDE6_CACHE/pyside-setup-everywhere-src-$PYSIDE6_VERSION/. Idempotent.
#
# Same shape as setup_qt6: outside $BUILD so it's preserved across
# prep_build_tree wipes; SHA-256 pinned in-tree.
setup_pyside6() {
    if [ -d "$PYSIDE6_SRC" ]; then return 0; fi

    log "Fetching PySide6 $PYSIDE6_VERSION"
    mkdir -p "$PYSIDE6_CACHE"
    # Qt publishes the source tarball under `PySide6-<X.Y.Z>-src/` but
    # the tarball itself is named with the major.minor only:
    #   PySide6-6.8.0-src/pyside-setup-everywhere-src-6.8.tar.xz
    # The extracted tree also lacks the patch component — it's
    # `pyside-setup-everywhere-src-6.8/`. PYSIDE6_MAJOR_MINOR
    # captures that form for both filenames and PYSIDE6_SRC's path.
    local dirname url tarball
    dirname="PySide6-$PYSIDE6_VERSION-src"
    url="https://download.qt.io/official_releases/QtForPython/pyside6/$dirname/pyside-setup-everywhere-src-$PYSIDE6_MAJOR_MINOR.tar.xz"
    tarball="$PYSIDE6_CACHE/pyside-setup-everywhere-src-$PYSIDE6_MAJOR_MINOR.tar.xz"

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
    if [ "$PYSIDE6_SHA256" != "$actual" ]; then
        echo "PySide6 SHA-256 mismatch: expected $PYSIDE6_SHA256, got $actual" >&2
        echo "  (pinned in MagPython/pyside6-sha256 — confirm via the metalink at" >&2
        echo "   the same dir as the tarball before changing)" >&2
        rm -f "$tarball"
        exit 1
    fi

    tar -xJf "$tarball" -C "$PYSIDE6_CACHE"
    # Upstream extracts to pyside-setup-everywhere-src-<version>/, which
    # matches $PYSIDE6_SRC already — no rename needed.
}

# Build PySide6 shiboken6 + pyside6 (Core module only) against our Qt6 +
# the MagPython interpreter staged at $STAGE/python3. Mirrors
# setup_libmpdec / build_ncurses shape: a setup_* fetch step, then a
# build_* step that runs the upstream build system and stages into a
# $BUILD subdir.
#
# Deliberately uses ONLY our own Python — no host python on the path.
# build_magpython_exe staged $STAGE/python3 (CPython's Programs/python.c
# wrapper linked against libMagPython). shiboken6's CMake
# `find_package(Python ... Development.Module)` invokes
# Python_EXECUTABLE to populate Python_INCLUDE_DIRS / Python_LIBRARIES
# from sysconfig; pointing at our binary keeps the entire ABI surface
# in lockstep (compile-time + link-time + runtime), avoiding the "found
# suitable version but missing Development.Module" failure mode a host
# python + staged Python_INCLUDE_DIR/Python_LIBRARY override produces
# when the overrides don't match the executable's reported paths.
#
# At runtime, the resulting .so files have NEEDED libpython3.13.so.1.0
# (or LC_LOAD_DYLIB libpython3.13.dylib on macOS). The artifact's
# libpython3.13.so.1.0 / libpython3.13.dylib symlinks (staged by
# stage_libpython_symlinks) point at libMagPython, so the runtime
# resolution lands in libMagPython.
#
# shiboken6 depends on libclang to parse Qt6 headers; libclang is
# expected on the system (installed via build-linux.sh / build-macos.sh
# per platform).
build_pyside6() {
    setup_pyside6

    local our_python="$STAGE/python3"
    [ -x "$our_python" ] || { echo "build_pyside6: $our_python not found or not executable; build_magpython_exe must run first" >&2; exit 1; }

    local rpath_token
    case "$(uname -s)" in
        Darwin) rpath_token='@loader_path' ;;
        *)      rpath_token='$ORIGIN' ;;
    esac

    # PySide6's build expects CMAKE_PREFIX_PATH to find Qt6; point it
    # at the Qt6 install we just built.
    export CMAKE_PREFIX_PATH="$BUILD/qt6-out${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"

    log "Building shiboken6 $PYSIDE6_VERSION"
    mkdir -p "$BUILD/shiboken6-build"
    cmake -S "$PYSIDE6_SRC/sources/shiboken6" -B "$BUILD/shiboken6-build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$BUILD/pyside6-out" \
        -DCMAKE_INSTALL_RPATH="$rpath_token" \
        -DBUILD_TESTS=OFF \
        -DUSE_PYTHON_VERSION="$PY_X_Y" \
        -DPython_EXECUTABLE="$our_python" \
        -DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH" \
        -DSHIBOKEN_BUILD_TOOLS=ON
    cmake --build "$BUILD/shiboken6-build" -j "$JOBS"
    cmake --install "$BUILD/shiboken6-build"

    log "Building pyside6 $PYSIDE6_VERSION (Core module only)"
    mkdir -p "$BUILD/pyside6-build"
    cmake -S "$PYSIDE6_SRC/sources/pyside6" -B "$BUILD/pyside6-build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$BUILD/pyside6-out" \
        -DCMAKE_INSTALL_RPATH="$rpath_token" \
        -DBUILD_TESTS=OFF \
        -DMODULES="Core" \
        -DUSE_PYTHON_VERSION="$PY_X_Y" \
        -DPython_EXECUTABLE="$our_python" \
        -DShiboken6_DIR="$BUILD/pyside6-out/lib/cmake/Shiboken6" \
        -DShiboken6Generator_DIR="$BUILD/pyside6-out/lib/cmake/Shiboken6Generator" \
        -DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH"
    cmake --build "$BUILD/pyside6-build" -j "$JOBS"
    cmake --install "$BUILD/pyside6-build"
}

# Stage PySide6 + libQt6Core into the artifact tree. Goes under
# site-packages/ next to libQt6Core/ — Python's import machinery picks
# up site-packages automatically via the lib/python<X.Y>/site-packages
# convention (the staged stdlib already has that dir from CPython's Lib/).
#
# Layout in the final zip:
#   MagPython/
#     libQt6Core.<so.6 | 6.dylib>   ← Qt's Core library
#     libshiboken6.abi3.so.<ver>    ← PySide6 binding runtime
#     libpyside6.abi3.so.<ver>      ← PySide6 binding runtime
#     site-packages/
#       PySide6/__init__.py
#       PySide6/QtCore.abi3.so      ← Python module
#       shiboken6/...               ← Python module
#
# The downstream host application adds <artifact>/MagPython/site-packages
# to sys.path (or PYTHONPATH) to make `import PySide6.QtCore` resolve.
# Libraries (libQt6Core, libshiboken6, libpyside6) are siblings of
# libMagPython so the runtime loader finds them via the same $ORIGIN /
# @loader_path rpath the embedder already sets up.
stage_pyside6() {
    log "Staging PySide6 + Qt6 Core into $STAGE/"
    # Qt6Core lib: the cmake install drops it under $BUILD/qt6-out/lib.
    case "$(uname -s)" in
        Darwin)
            cp -P "$BUILD/qt6-out/lib"/libQt6Core.*.dylib "$STAGE/" 2>/dev/null || true
            cp -P "$BUILD/qt6-out/lib"/libQt6Core.dylib "$STAGE/" 2>/dev/null || true
            ;;
        *)
            cp -P "$BUILD/qt6-out/lib"/libQt6Core.so* "$STAGE/" 2>/dev/null || true
            ;;
    esac

    # shiboken6/pyside6 runtime libs: PySide6's install drops them under
    # $BUILD/pyside6-out/lib (some versions use lib64 on x86_64 — handle
    # both with a glob).
    local pyside_libdir
    for pyside_libdir in "$BUILD/pyside6-out/lib" "$BUILD/pyside6-out/lib64"; do
        [ -d "$pyside_libdir" ] || continue
        case "$(uname -s)" in
            Darwin)
                cp -P "$pyside_libdir"/libshiboken6.*.dylib "$STAGE/" 2>/dev/null || true
                cp -P "$pyside_libdir"/libpyside6.*.dylib   "$STAGE/" 2>/dev/null || true
                ;;
            *)
                cp -P "$pyside_libdir"/libshiboken6.*.so*   "$STAGE/" 2>/dev/null || true
                cp -P "$pyside_libdir"/libpyside6.*.so*     "$STAGE/" 2>/dev/null || true
                ;;
        esac
    done

    # Python modules. PySide6's install places them under
    # <prefix>/lib/pythonX.Y/site-packages/{PySide6,shiboken6}/. Copy the
    # full tree so consumers can `import PySide6.QtCore` and `import
    # shiboken6` without further wiring.
    mkdir -p "$STAGE/site-packages"
    local py_sitepkgs="$BUILD/pyside6-out/lib/python$PY_X_Y/site-packages"
    [ -d "$py_sitepkgs" ] || py_sitepkgs="$BUILD/pyside6-out/lib64/python$PY_X_Y/site-packages"
    if [ -d "$py_sitepkgs" ]; then
        cp -R "$py_sitepkgs/." "$STAGE/site-packages/"
    else
        echo "stage_pyside6: PySide6 site-packages not found under $BUILD/pyside6-out" >&2
        exit 1
    fi

    # Rewrite install_name / rpaths on the staged binaries so they
    # resolve as siblings of libMagPython (matches the rest of the artifact).
    case "$(uname -s)" in
        Darwin)
            for f in "$STAGE"/libQt6Core.*.dylib "$STAGE"/libshiboken6.*.dylib "$STAGE"/libpyside6.*.dylib "$STAGE"/site-packages/PySide6/*.dylib "$STAGE"/site-packages/PySide6/QtCore.abi3.so; do
                [ -f "$f" ] || continue
                base="$(basename "$f")"
                # If it's a top-level library, make its install_name @rpath/<base>.
                case "$base" in
                    libQt6Core*|libshiboken6*|libpyside6*)
                        install_name_tool -id "@rpath/$base" "$f" 2>/dev/null || true
                        ;;
                esac
                # Rewrite any absolute LC_LOAD_DYLIB entries that point under
                # the build tree to @rpath/<basename>.
                otool -L "$f" \
                    | awk -v root="$BUILD" 'NR>1 && $1 ~ root {print $1}' \
                    | while read -r path; do
                        b="$(basename "$path")"
                        install_name_tool -change "$path" "@rpath/$b" "$f" 2>/dev/null || true
                    done
                # Drop absolute LC_RPATHs under $BUILD; add @loader_path
                # (already covered by libMagPython's tree but cheap to
                # double-add — install_name_tool ignores duplicates).
                otool -l "$f" \
                    | awk '/^ +cmd LC_RPATH/{r=1;next} r && /path /{print $2;r=0}' \
                    | while read -r rp; do
                        case "$rp" in
                            "$BUILD"/*) install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null || true ;;
                        esac
                    done
                if ! otool -l "$f" \
                        | awk '/^ +cmd LC_RPATH/{r=1;next} r && /path /{print $2;r=0}' \
                        | grep -qx '@loader_path'; then
                    install_name_tool -add_rpath '@loader_path' "$f" 2>/dev/null || true
                fi
            done
            ;;
        *)
            for f in "$STAGE"/libQt6Core.so* "$STAGE"/libshiboken6.*.so* "$STAGE"/libpyside6.*.so* "$STAGE"/site-packages/PySide6/*.so "$STAGE"/site-packages/PySide6/QtCore.abi3.so; do
                [ -f "$f" ] || continue
                # patchelf is already a hard requirement for the Linux
                # build (see build-linux.sh's preflight check).
                patchelf --set-rpath '$ORIGIN/../..' "$f" 2>/dev/null || true
                # libQt6Core etc. sit at the top of the artifact, so
                # $ORIGIN is the same dir as libMagPython.so. For the
                # site-packages/PySide6/*.so files, they sit one
                # subdirectory deeper, so $ORIGIN/../.. lands at the
                # MagPython/ dir — that's where libQt6Core/libshiboken6
                # are. Override per-file:
                case "$f" in
                    "$STAGE"/libQt6Core.so*|"$STAGE"/libshiboken6.*|"$STAGE"/libpyside6.*)
                        patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
                        ;;
                esac
            done
            ;;
    esac

    # Strip debug symbols off the bundled binaries — Qt6 in particular
    # ships substantial debug info even in Release builds. Same intent as
    # the libMagPython / libcrypto strip step.
    case "$(uname -s)" in
        Darwin)
            for f in "$STAGE"/libQt6Core.*.dylib "$STAGE"/libshiboken6.*.dylib "$STAGE"/libpyside6.*.dylib "$STAGE"/site-packages/PySide6/*.dylib "$STAGE"/site-packages/PySide6/*.so; do
                [ -f "$f" ] || continue
                strip -x "$f" 2>/dev/null || true
            done
            ;;
        *)
            for f in "$STAGE"/libQt6Core.so* "$STAGE"/libshiboken6.*.so* "$STAGE"/libpyside6.*.so* "$STAGE"/site-packages/PySide6/*.so; do
                [ -f "$f" ] || continue
                strip "$f" 2>/dev/null || true
            done
            ;;
    esac
}

# libpython symlinks consumed by build_pyside6's PySide6 link step: the
# CMake build's `find_package(Python)` plus PySide6's linker invocation
# expect a libpythonX.Y.{so.1.0,dylib} sibling to libMagPython. We added
# the libpython forwarder by symlinking onto libMagPython so PySide6's
# NEEDED / LC_LOAD_DYLIB entry comes out as the canonical libpythonX.Y
# name, with runtime resolution landing in libMagPython.
#
# Called from build-linux.sh / build-macos.sh after libMagPython is
# staged (so the symlink target exists) and before build_pyside6 (so
# the PySide6 link sees it).
stage_libpython_symlinks() {
    log "Adding libpython symlinks for PySide6 linkage"
    case "$(uname -s)" in
        Darwin)
            ln -sf libMagPython.dylib "$STAGE/libpython$PY_X_Y.dylib"
            ln -sf libMagPython.dylib "$STAGE/libpython3.dylib"
            ;;
        *)
            # Linux libpython convention is libpythonX.Y.so.1.0 (the
            # real file) with libpythonX.Y.so as the unversioned linker
            # alias. Both point at libMagPython.so; the linker uses the
            # unversioned name to resolve -lpythonX.Y at link time, and
            # the .so.1.0 form is what gets recorded as the binary's
            # NEEDED entry (because libMagPython.so's SONAME is
            # libMagPython.so — see the soname forwarding note below).
            #
            # Note: the SONAME on libMagPython.so stays libMagPython.so;
            # the symlinks are file-tree fixtures only. The dynamic
            # linker walks symlink chains and applies the resolved
            # file's SONAME, so a NEEDED of `libpythonX.Y.so.1.0`
            # against this symlink chain ends up loading libMagPython.so
            # under that NEEDED entry — exactly what we want.
            ln -sf libMagPython.so "$STAGE/libpython$PY_X_Y.so.1.0"
            ln -sf libMagPython.so "$STAGE/libpython$PY_X_Y.so"
            ln -sf libMagPython.so "$STAGE/libpython3.so"
            ;;
    esac
}
