#!/usr/bin/env bash
# Build MagPython for macOS arm64 (Apple Silicon) on a `macos-14` runner.
# Mirrors MagPython/MagPython.metaproj on Windows and produces
# MagPython-macos-arm64.zip with the same shape as the Windows artifact:
#
#   MagPython/
#     libMagPython.dylib
#     libcrypto.1.1.dylib
#     libssl.1.1.dylib
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
# and deepfreeze.py.
HOST_PYTHON="$(command -v python3)"

command -v zip >/dev/null || { echo "zip not found"; exit 1; }

prep_build_tree
install_setup_local
build_static_deps aarch64-apple-darwin
build_openssl darwin64-arm64-cc

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

log "Renaming libpython3.12 -> libMagPython"
(cd "$BUILD/main"
 # Apple equivalent of patchelf --set-soname is install_name_tool -id.
 cp libpython3.12.dylib "$STAGE/libMagPython.dylib"
 install_name_tool -id @rpath/libMagPython.dylib "$STAGE/libMagPython.dylib")

log "Copying OpenSSL dylibs"
ssl_libdir="$BUILD/openssl-out/lib"
cp -P "$ssl_libdir"/libcrypto.*.dylib "$STAGE/"
cp -P "$ssl_libdir"/libssl.*.dylib    "$STAGE/"
# Rewrite OpenSSL install names to @rpath so the host application's @rpath
# controls resolution, and rewrite libMagPython's references to them.
log "Rewriting install names to @rpath"
for f in "$STAGE"/libcrypto.*.dylib "$STAGE"/libssl.*.dylib; do
    base="$(basename "$f")"
    install_name_tool -id "@rpath/$base" "$f"
done
# libMagPython links against libcrypto/libssl with absolute paths from
# $BUILD/openssl-out; rewrite each to @rpath/<basename>.
otool -L "$STAGE/libMagPython.dylib" \
    | awk -v root="$BUILD/openssl-out" '$1 ~ root {print $1}' \
    | while read -r path; do
        base="$(basename "$path")"
        install_name_tool -change "$path" "@rpath/$base" "$STAGE/libMagPython.dylib"
    done
# Drop any absolute LC_RPATH entries that point at the build's openssl-out
# (added by --with-openssl-rpath=auto). @loader_path was already added via
# LDFLAGS_NODIST, so removing the absolutes makes the artifact relocatable.
otool -l "$STAGE/libMagPython.dylib" \
    | awk -v root="$BUILD/openssl-out" '
        /^ +cmd LC_RPATH/   { in_rpath=1; next }
        in_rpath && /path / { if (index($2, root) == 1) print $2; in_rpath=0 }
    ' | while read -r rpath; do
        install_name_tool -delete_rpath "$rpath" "$STAGE/libMagPython.dylib"
    done

log "Stripping debug symbols from shared libs"
# CPython builds with -g -O3 by default; the embedded debug info adds
# tens of MB to libMagPython.dylib. `strip -x` keeps the symbol table's
# dynamic entries while dropping local/debug symbols — same intent as
# Linux's plain `strip`.
for f in "$STAGE"/libMagPython.dylib "$STAGE"/libcrypto.*.dylib "$STAGE"/libssl.*.dylib; do
    strip -x "$f"
done

stage_headers_and_stdlib "$BUILD/main"
run_smoke_test '@loader_path'

# Sanity: only @rpath/* and system libs should remain in the LC_LOAD_DYLIB
# entries of libMagPython.
log "otool sanity"
otool -L "$STAGE/libMagPython.dylib"

zip_artifact macos-arm64
