#!/usr/bin/env bash
# Build Qt6 qtbase (Core only) + PySide6 (Core module only) for the
# windows-x64 artifact and stage the binaries into MagPython\Release\
# next to MagPython.dll. Mirrors what build_qt6 / build_pyside6 /
# stage_pyside6 do for linux-x86_64 and macos-arm64, but Windows-specific:
#
#   - CMake + Ninja drive the build (same as POSIX), with cl.exe /
#     link.exe from the MSVC environment activated by the workflow's
#     ilammy/msvc-dev-cmd step before this script runs.
#   - No rpath story — Windows DLLs are searched in the loading binary's
#     directory and PATH, so staging everything next to MagPython.dll
#     is sufficient.
#   - libclang for shiboken6's binding generator comes from the LLVM
#     Windows installer (installed by the workflow via `choco install
#     llvm` before this script runs). LLVM_INSTALL_DIR is exported so
#     shiboken6's CMake finds it.
#   - The .pyd output files are linked against $STAGE/MagPython.lib
#     (CMake's Python_LIBRARY), so the linker records MagPython.dll as
#     the IAT DLL name. We deliberately do NOT ship a python3.dll
#     forwarder: pip-installed abi3 wheels from PyPI (linked against
#     upstream's python3.lib) are out of scope for this artifact.
#
# Output layout (in MagPython\Release\):
#
#   Release\
#     MagPython.dll            (from MagPython.vcxproj, already present)
#     Qt6Core.dll              (built here)
#     shiboken6.abi3.dll       (built here)
#     pyside6.abi3.dll         (built here)
#     site-packages\PySide6\__init__.py
#     site-packages\PySide6\QtCore.pyd       (built here)
#     site-packages\shiboken6\...

set -euo pipefail
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

# Pin files — same source of truth as the POSIX builds, so a bump on
# any platform only needs the version + sha files edited.
QT6_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/qt6-version")"
QT6_SHA256="$(tr -d '[:space:]' < "$REPO/MagPython/qt6-sha256")"
PYSIDE6_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/pyside6-version")"
PYSIDE6_SHA256="$(tr -d '[:space:]' < "$REPO/MagPython/pyside6-sha256")"
PYTHON_VERSION="$(tr -d '[:space:]' < "$REPO/MagPython/python-version")"
PY_X_Y="$(printf '%s' "$PYTHON_VERSION" | awk -F. '{ printf "%s.%s\n", $1, $2 }')"
QT6_TRACK="$(printf '%s' "$QT6_VERSION" | awk -F. '{ printf "%s.%s\n", $1, $2 }')"

JOBS="$(nproc 2>/dev/null || echo 4)"

# Source-cache dirs match the POSIX layout so the actions/cache@v5
# entries in Build All.yml ("Cache Qt6 download" / "Cache PySide6
# download") restore tarballs into the same place this script reads.
QT6_CACHE="$REPO/MagPython/qt6"
QT6_SRC="$QT6_CACHE/qtbase-everywhere-src-$QT6_VERSION"
PYSIDE6_CACHE="$REPO/MagPython/pyside6"
# Qt names the source tarball with the major.minor only — see the
# matching comment in build-common.sh.
PYSIDE6_MAJOR_MINOR="$(printf '%s' "$PYSIDE6_VERSION" | awk -F. '{ printf "%s.%s\n", $1, $2 }')"
PYSIDE6_SRC="$PYSIDE6_CACHE/pyside-setup-everywhere-src-$PYSIDE6_MAJOR_MINOR"

# Build outputs go under MagPython\build-out-windows\ (sibling of the
# existing Release\ tree the vcxprojs write to, so MSBuild's incremental
# cleanup doesn't sweep them). Mirrors POSIX's $REPO/build-out/.
BUILD="$REPO/MagPython/build-out-windows"
mkdir -p "$BUILD"

# Where MSBuild already staged MagPython.dll + headers etc. Same
# shared dir all the .vcxproj files write to.
STAGE="$REPO/MagPython/Release"
[ -f "$STAGE/MagPython.dll" ] || { echo "ERROR: $STAGE/MagPython.dll not found — run msbuild before this script" >&2; exit 1; }
[ -f "$STAGE/MagPython.lib" ] || { echo "ERROR: $STAGE/MagPython.lib not found — Python_LIBRARY can't be resolved" >&2; exit 1; }

# LLVM_INSTALL_DIR: the workflow installs LLVM via choco before this
# script runs. Resolve a few common install locations so the script
# works whether choco/winget/the user installed it.
if [ -z "${LLVM_INSTALL_DIR:-}" ]; then
    for cand in "C:/Program Files/LLVM" "/c/Program Files/LLVM" "C:/Program Files (x86)/LLVM" "/c/Program Files (x86)/LLVM"; do
        if [ -d "$cand/bin" ]; then LLVM_INSTALL_DIR="$cand"; break; fi
    done
fi
[ -n "${LLVM_INSTALL_DIR:-}" ] || { echo "ERROR: LLVM_INSTALL_DIR not set and no LLVM install found" >&2; exit 1; }
export LLVM_INSTALL_DIR
echo "Using LLVM at: $LLVM_INSTALL_DIR"

# cmake + ninja: the workflow `pip install`s them via the host Python's
# pip just like the Linux/macOS scripts do; the wrappers land on PATH
# courtesy of the workflow's PATH overlay step.
command -v cmake >/dev/null || { echo "cmake not on PATH" >&2; exit 1; }
command -v ninja >/dev/null || { echo "ninja not on PATH" >&2; exit 1; }

# PySide6's CMake invokes Python_EXECUTABLE for sysconfig queries; we
# point it at the python3.exe MagPythonExe.vcxproj built (and aliased
# from MagPython.exe) into the same Release\ tree, linked against
# MagPython.lib. Using our own interpreter (rather than the host's
# setup-python install) keeps sysconfig's include/lib paths internally
# consistent with the headers shiboken6 will actually consume — same
# rationale as on the POSIX side, where $STAGE/python3 plays the same
# role.
OUR_PYTHON="$STAGE/python3.exe"
[ -f "$OUR_PYTHON" ] || { echo "ERROR: $OUR_PYTHON not found — MagPythonExe.vcxproj must build before this script" >&2; exit 1; }
# Fail fast with a clear error if our python can't run end-to-end —
# FindPython will invoke it for sysconfig queries below.
"$OUR_PYTHON" -c 'import sys, sysconfig; print(sys.version); print(sysconfig.get_paths()["include"])' >/dev/null

log() { printf '\n=== %s ===\n' "$*"; }

setup_qt6() {
    if [ -d "$QT6_SRC" ]; then return 0; fi
    log "Fetching Qt6 qtbase $QT6_VERSION"
    mkdir -p "$QT6_CACHE"
    local url="https://download.qt.io/archive/qt/$QT6_TRACK/$QT6_VERSION/submodules/qtbase-everywhere-src-$QT6_VERSION.tar.xz"
    local tarball="$QT6_CACHE/qtbase-everywhere-src-$QT6_VERSION.tar.xz"
    if [ ! -f "$tarball" ]; then
        curl --fail --silent --show-error --location -o "$tarball" "$url"
    fi
    local actual
    actual="$(sha256sum "$tarball" | awk '{print $1}')"
    if [ "$QT6_SHA256" != "$actual" ]; then
        echo "Qt6 SHA-256 mismatch: expected $QT6_SHA256, got $actual" >&2
        rm -f "$tarball"
        exit 1
    fi
    # Windows runners ship 7z which handles .tar.xz; tar shipped with
    # Git Bash also handles -xJ. Prefer tar for the same invocation
    # shape as the POSIX scripts.
    tar -xJf "$tarball" -C "$QT6_CACHE"
}

build_qt6() {
    setup_qt6
    log "Configuring Qt6 qtbase $QT6_VERSION (Core only) on windows-x64"
    mkdir -p "$BUILD/qt6-build" "$BUILD/qt6-out"
    # Match build-common.sh's POSIX configure: drop the
    # QT_BUILD_TOOLS_BY_DEFAULT=OFF / --target Core hack, build the
    # default targets (host tools moc/rcc/uic/qmake6 included), and
    # let cmake --install do one full install pass. PySide6's CMake
    # needs the host tools at build time.
    cmake -S "$QT6_SRC" -B "$BUILD/qt6-build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$BUILD/qt6-out" \
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
        -DQT_FEATURE_icu=OFF
    log "Building Qt6 qtbase"
    cmake --build "$BUILD/qt6-build" -j "$JOBS"
    cmake --install "$BUILD/qt6-build"
}

setup_pyside6() {
    if [ -d "$PYSIDE6_SRC" ]; then return 0; fi
    log "Fetching PySide6 $PYSIDE6_VERSION"
    mkdir -p "$PYSIDE6_CACHE"
    local dirname url tarball
    dirname="PySide6-$PYSIDE6_VERSION-src"
    url="https://download.qt.io/official_releases/QtForPython/pyside6/$dirname/pyside-setup-everywhere-src-$PYSIDE6_MAJOR_MINOR.tar.xz"
    tarball="$PYSIDE6_CACHE/pyside-setup-everywhere-src-$PYSIDE6_MAJOR_MINOR.tar.xz"
    if [ ! -f "$tarball" ]; then
        curl --fail --silent --show-error --location -o "$tarball" "$url"
    fi
    local actual
    actual="$(sha256sum "$tarball" | awk '{print $1}')"
    if [ "$PYSIDE6_SHA256" != "$actual" ]; then
        echo "PySide6 SHA-256 mismatch: expected $PYSIDE6_SHA256, got $actual" >&2
        rm -f "$tarball"
        exit 1
    fi
    tar -xJf "$tarball" -C "$PYSIDE6_CACHE"
}

build_pyside6() {
    setup_pyside6
    # CMAKE_PREFIX_PATH must cover both Qt6 (built into qt6-out) and the
    # LLVM/Clang install (choco landed it at $LLVM_INSTALL_DIR). shiboken6's
    # `find_package(Clang ...)` looks for ClangConfig.cmake under
    # <prefix>/lib/cmake/clang/, and a default CMake prefix search doesn't
    # cover C:\Program Files\LLVM. Use ';' as the cmake-internal list
    # separator (cross-platform) and pass as a -D arg below so the env
    # var separator (':' vs ';') doesn't enter the picture.
    #
    # cygpath -m converts $BUILD's MSYS-style path (/d/a/...) to mixed
    # Windows-style (D:/a/...). MSVC's cmake doesn't understand
    # /<drive-letter>/<path> at all — it'll silently treat it as a
    # relative path under the current drive and fail to find Qt6Config.cmake.
    # $LLVM_INSTALL_DIR is already Windows-style from the for-cand loop
    # above; convert it through cygpath defensively in case the loop
    # ever picks an MSYS-style match.
    # Every -D path arg below needs an MSYS→Windows conversion: MSVC's
    # cmake silently treats "/d/..." as a relative path under the
    # current drive, so find_package(Qt6) doesn't find Qt6Config.cmake
    # under our qt6-out prefix, ditto Clang, ditto Shiboken6_DIR. -S /
    # -B are tolerant (cmake normalises them) so we leave those alone.
    local cmake_prefix pyside6_out_win python_exe_win
    cmake_prefix="$(cygpath -m "$BUILD/qt6-out");$(cygpath -m "$LLVM_INSTALL_DIR")"
    pyside6_out_win="$(cygpath -m "$BUILD/pyside6-out")"
    python_exe_win="$(cygpath -m "$OUR_PYTHON")"

    # Only Python_EXECUTABLE is passed — no Python_INCLUDE_DIR or
    # Python_LIBRARY overrides. FindPython queries the executable for
    # sysconfig data and resolves the rest from there, so the headers
    # and import lib it picks are guaranteed to match the interpreter
    # (avoids the Development.Module rejection seen when host-python's
    # paths conflicted with our staged overrides).
    log "Building shiboken6 $PYSIDE6_VERSION"
    mkdir -p "$BUILD/shiboken6-build" "$BUILD/pyside6-out"
    cmake -S "$PYSIDE6_SRC/sources/shiboken6" -B "$BUILD/shiboken6-build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$pyside6_out_win" \
        -DBUILD_TESTS=OFF \
        -DUSE_PYTHON_VERSION="$PY_X_Y" \
        -DPython_EXECUTABLE="$python_exe_win" \
        -DCMAKE_PREFIX_PATH="$cmake_prefix" \
        -DSHIBOKEN_BUILD_TOOLS=ON
    cmake --build "$BUILD/shiboken6-build" -j "$JOBS"
    cmake --install "$BUILD/shiboken6-build"

    log "Building pyside6 $PYSIDE6_VERSION (Core only)"
    mkdir -p "$BUILD/pyside6-build"
    cmake -S "$PYSIDE6_SRC/sources/pyside6" -B "$BUILD/pyside6-build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$pyside6_out_win" \
        -DBUILD_TESTS=OFF \
        -DMODULES="Core" \
        -DUSE_PYTHON_VERSION="$PY_X_Y" \
        -DPython_EXECUTABLE="$python_exe_win" \
        -DShiboken6_DIR="$pyside6_out_win/lib/cmake/Shiboken6" \
        -DShiboken6Generator_DIR="$pyside6_out_win/lib/cmake/Shiboken6Generator" \
        -DCMAKE_PREFIX_PATH="$cmake_prefix"
    cmake --build "$BUILD/pyside6-build" -j "$JOBS"
    cmake --install "$BUILD/pyside6-build"
}

stage_pyside6() {
    log "Staging PySide6 + Qt6 Core DLLs into $STAGE"
    # Qt6Core.dll lands under <prefix>/bin on Windows (CMake's GNUInstallDirs
    # for runtime artifacts). Copy any matching DLLs.
    for d in "$BUILD/qt6-out/bin" "$BUILD/qt6-out/lib"; do
        [ -d "$d" ] || continue
        for f in "$d"/Qt6Core*.dll; do
            [ -f "$f" ] || continue
            cp -v "$f" "$STAGE/"
        done
    done

    # shiboken6 / pyside6 runtime DLLs.
    for d in "$BUILD/pyside6-out/bin" "$BUILD/pyside6-out/lib"; do
        [ -d "$d" ] || continue
        for f in "$d"/shiboken6*.dll "$d"/pyside6*.dll; do
            [ -f "$f" ] || continue
            cp -v "$f" "$STAGE/"
        done
    done

    # Python packages (PySide6/, shiboken6/) — drop into site-packages
    # next to the bundled DLLs, same as POSIX layout.
    mkdir -p "$STAGE/site-packages"
    local py_sitepkgs
    for cand in \
        "$BUILD/pyside6-out/lib/python$PY_X_Y/site-packages" \
        "$BUILD/pyside6-out/Lib/site-packages" \
        "$BUILD/pyside6-out/lib/site-packages"; do
        if [ -d "$cand" ]; then py_sitepkgs="$cand"; break; fi
    done
    [ -n "${py_sitepkgs:-}" ] || { echo "ERROR: PySide6 site-packages not found under $BUILD/pyside6-out" >&2; exit 1; }
    cp -R "$py_sitepkgs/." "$STAGE/site-packages/"
}

build_qt6
build_pyside6
stage_pyside6

log "Windows Qt6 + PySide6 build done"
ls -la "$STAGE/"
