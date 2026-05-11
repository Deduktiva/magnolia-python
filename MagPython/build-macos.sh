#!/usr/bin/env bash
# Build MagPython for macOS arm64 (Apple Silicon) on a `macos-14` runner.
# Mirrors MagPython/MagPython.metaproj on Windows and produces
# MagPython-macos-arm64.zip with the same shape as the Windows artifact:
#
#   MagPython/
#     libMagPython.dylib
#     libcrypto.<openssl-shlib-version>.dylib  # 3 on the 3.x line
#     libssl.<openssl-shlib-version>.dylib
#     libsqlite3.0.dylib
#     libsqlite3.dylib -> libsqlite3.0.dylib
#     include/Python/...
#     lib/...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-common.sh
source "$SCRIPT_DIR/build-common.sh"

# Anything < 11.0 won't run native arm64. Pin to 11.0 to match the runner's
# baseline and avoid accidental forward references in libpython.
export MACOSX_DEPLOYMENT_TARGET=11.0

# The runner's preinstalled python3 is recent enough for freeze_modules.py
# (CPython 3.13 dropped deepfreeze.py — frozen modules are now the only
# regen step).
HOST_PYTHON="$(command -v python3)"

command -v zip >/dev/null || { echo "zip not found"; exit 1; }

prep_build_tree
setup_python
install_setup_local
build_zlib_static
# libffi is the SDK's /usr/lib/libffi.dylib on macOS — CPython's Darwin
# block in configure auto-detects the SDK headers and -lffi. No
# libMagPython-bundled libffi here (unlike the Linux build).
build_sqlite_shared
build_openssl darwin64-arm64-cc
# CPython's configure.ac forces libmpdec_machine=universal on Darwin
# ("compile with whatever -arch the C compiler is using"); pass the same
# override to upstream's configure so the x64 inline asm path doesn't get
# selected on arm64. Without this, autoconf detection trips on arm64
# Macs and falls back to ANSI in inconsistent ways.
build_libmpdec --with-machine=universal
build_ncurses

log "Configuring libMagPython"
mkdir -p "$BUILD/main"
(cd "$BUILD/main"
 configure_libmagpython "-Wl,-rpath,@loader_path" \
     --enable-universalsdk=no \
     PYTHON_FOR_REGEN="$HOST_PYTHON")

regen_frozen      "$BUILD/main" "$HOST_PYTHON"
flip_modules_to_static "$BUILD/main"

# CPython's libpython dylib link rule on macOS uses $(SHLIB_LIBS) only,
# while the Linux .so rule uses $(MODLIBS) $(SHLIBS) $(LIBS). With our
# stdlib modules (_ssl, _hashopenssl, ...) statically linked into
# libpython, their per-module linker flags (-lssl, -lcrypto, ...) live
# in $(MODLIBS) — unreferenced on macOS. -undefined dynamic_lookup hides
# this at link time, but the smoke test then dies with
#   dyld: symbol not found in flat namespace '_GENERAL_NAME_free'
# because libcrypto isn't loaded into the process. Append $(MODLIBS) to
# the dylib rule so the link records the right LC_LOAD_DYLIB entries.
log "Patching Makefile to include MODLIBS in the dylib link"
# Python/Makefile.pre.in line 826-827 has the macOS dylib rule:
#   $(CC) -dynamiclib ... -o $@ $(LIBRARY_OBJS) $(DTRACE_OBJS) $(SHLIBS) $(LIBC) $(LIBM)
# The .sl (HP-UX) rule a few lines below uses $(LIBRARY_OBJS) $(MODLIBS)
# $(SHLIBS) $(LIBC) $(LIBM) — the dylib variant is just missing $(MODLIBS).
# Inject it so the libpython.dylib link picks up per-module deps
# (-lssl, -lcrypto, ...) and records LC_LOAD_DYLIB entries for them.
awk '
    /-o \$@ \$\(LIBRARY_OBJS\) \$\(DTRACE_OBJS\) \$\(SHLIBS\) \$\(LIBC\) \$\(LIBM\)/ {
        sub(/\$\(LIBRARY_OBJS\) \$\(DTRACE_OBJS\)/,
            "$(LIBRARY_OBJS) $(MODLIBS) $(DTRACE_OBJS)")
        patched = 1
    }
    { print }
    END { if (!patched) { print "ERROR: dylib rule pattern not found in Makefile" > "/dev/stderr"; exit 1 } }
' "$BUILD/main/Makefile" > "$BUILD/main/Makefile.tmp"
mv "$BUILD/main/Makefile.tmp" "$BUILD/main/Makefile"

log "Building libpython"
(cd "$BUILD/main" && make -j"$JOBS")

log "Renaming libpython$PY_X_Y -> libMagPython"
(cd "$BUILD/main"
 # Apple equivalent of patchelf --set-soname is install_name_tool -id.
 cp "libpython$PY_X_Y.dylib" "$STAGE/libMagPython.dylib"
 install_name_tool -id @rpath/libMagPython.dylib "$STAGE/libMagPython.dylib")

log "Copying libsqlite3 dylib"
# build_sqlite_shared already linked it with install_name=@rpath/libsqlite3.0.dylib
# and dropped a libsqlite3.dylib -> libsqlite3.0.dylib symlink. Both ship.
cp -P "$BUILD/sqlite/libsqlite3.0.dylib" "$STAGE/"
ln -sf libsqlite3.0.dylib "$STAGE/libsqlite3.dylib"

log "Copying OpenSSL dylibs"
ssl_libdir="$BUILD/openssl-out/lib"
cp -P "$ssl_libdir"/libcrypto.*.dylib "$STAGE/"
cp -P "$ssl_libdir"/libssl.*.dylib    "$STAGE/"
# install_sw also creates unversioned symlinks (libcrypto.dylib ->
# libcrypto.<ver>.dylib, same for libssl). The libcrypto.*.dylib glob above
# requires at least one char between the dots, so it doesn't pick those up.
# Copy them with -P so consumers can link against -lcrypto / -lssl, mirroring
# the libssl.so / libcrypto.so symlinks already shipped on Linux and the
# libssl.lib / libcrypto.lib import libs shipped on Windows.
cp -P "$ssl_libdir"/libcrypto.dylib "$STAGE/"
cp -P "$ssl_libdir"/libssl.dylib    "$STAGE/"
# Rewrite OpenSSL install names to @rpath so the host application's @rpath
# controls resolution, and rewrite cross-references between the staged
# dylibs (libMagPython -> libssl/libcrypto, libssl -> libcrypto) the same way.
log "Rewriting install names to @rpath"
for f in "$STAGE"/libcrypto.*.dylib "$STAGE"/libssl.*.dylib; do
    base="$(basename "$f")"
    install_name_tool -id "@rpath/$base" "$f"
done
# libMagPython links against libcrypto/libssl, and libssl links against
# libcrypto, all with absolute paths from $BUILD/openssl-out. Without
# rewriting libssl's reference too, a host running the artifact directly
# (no DYLD_FALLBACK_LIBRARY_PATH) hits a dyld error pointing at the
# runner's build dir. Apply the same rewrite + rpath cleanup uniformly.
for f in "$STAGE/libMagPython.dylib" "$STAGE"/libcrypto.*.dylib "$STAGE"/libssl.*.dylib; do
    otool -L "$f" \
        | awk -v root="$BUILD/openssl-out" '$1 ~ root {print $1}' \
        | while read -r path; do
            base="$(basename "$path")"
            install_name_tool -change "$path" "@rpath/$base" "$f"
        done
    # Drop any absolute LC_RPATH entries that point under $BUILD so the
    # artifact is relocatable. Catches both --with-openssl-rpath=auto's
    # $BUILD/openssl-out/lib entry (added by configure + OpenSSL's own
    # link rules) and the $BUILD/sqlite entry we add to LDFLAGS_NODIST
    # so build-time helpers (_freeze_module) can load libsqlite3.
    otool -l "$f" \
        | awk -v root="$BUILD" '
            /^ +cmd LC_RPATH/   { in_rpath=1; next }
            in_rpath && /path / { if (index($2, root) == 1) print $2; in_rpath=0 }
        ' | while read -r rpath; do
            install_name_tool -delete_rpath "$rpath" "$f"
        done
done
# Add @loader_path to LC_RPATH on libssl/libcrypto so the @rpath/libcrypto
# reference inside libssl resolves to its sibling regardless of what
# rpaths the loading binary supplies. libMagPython already has this via
# LDFLAGS_NODIST in configure_libmagpython.
for f in "$STAGE"/libcrypto.*.dylib "$STAGE"/libssl.*.dylib; do
    if ! otool -l "$f" \
            | awk '/^ +cmd LC_RPATH/{r=1;next} r && /path /{print $2;r=0}' \
            | grep -qx "@loader_path"; then
        install_name_tool -add_rpath "@loader_path" "$f"
    fi
done

log "Stripping debug symbols from shared libs"
# CPython builds with -g -O3 by default; the embedded debug info adds
# tens of MB to libMagPython.dylib. `strip -x` keeps the symbol table's
# dynamic entries while dropping local/debug symbols — same intent as
# Linux's plain `strip`.
for f in "$STAGE"/libMagPython.dylib "$STAGE"/libcrypto.*.dylib "$STAGE"/libssl.*.dylib "$STAGE"/libsqlite3.*.dylib; do
    strip -x "$f"
done

stage_headers_and_stdlib "$BUILD/main"
stage_openssl_headers
stage_licenses
verify_no_static_dep_leakage "$STAGE/libMagPython.dylib"
run_smoke_test '@loader_path'

# Sanity: only @rpath/* and system libs should remain in the LC_LOAD_DYLIB
# entries of any shipped dylib. libssl in particular must not retain the
# absolute libcrypto reference baked in at OpenSSL build time.
log "otool sanity"
for f in "$STAGE"/libMagPython.dylib "$STAGE"/libcrypto.*.dylib "$STAGE"/libssl.*.dylib; do
    otool -L "$f"
    if otool -L "$f" | awk -v root="$BUILD/openssl-out" 'NR>1 && $1 ~ root {found=1} END {exit !found}'; then
        echo "ERROR: $f still references $BUILD/openssl-out" >&2
        exit 1
    fi
done

zip_artifact macos-arm64
