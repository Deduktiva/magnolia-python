# magnolia-python

A custom build of CPython 3.13.13 for embedding into a host application.
Builds Windows x86, Windows x64, Linux x86_64, macOS arm64 artifacts to
be used as development and link targets. Linux, macOS, and Windows x64
additionally bundle Qt6 qtbase (Core only) and PySide6 (Core module)
built from source against this CPython, so a downstream embedder can
`import PySide6.QtCore` without further wiring. PySide6 on windows-x86
is not supported (Qt 6 dropped 32-bit Windows entirely).

## Build outputs

Each platform produces one zip with the same shape — a `MagPython/`
directory containing the main shared lib, the OpenSSL libs, the headers,
and the pure-Python stdlib. zlib and libmpdec are linked statically into
the main library on every platform; libffi is linked statically on
Windows/Linux, while macOS uses the SDK's system libffi; sqlite ships as
a sibling shared library on Linux/macOS and statically on Windows;
ncurses is linked statically into the POSIX builds only (the Windows
artifact ships no curses module — CPython upstream relies on the
`windows-curses` PyPI shim there).

Windows (`MagPython-windows-x86.zip` and `MagPython-windows-x64.zip`,
broadly the same shape — the binaries' architecture and OpenSSL DLL
names differ, and the windows-x64 zip additionally bundles Qt6 + PySide6
the same way the POSIX zips do):

```
MagPython/
  MagPython.dll                       # Python core + builtin modules + zlib + sqlite + libffi + libmpdec
  libcrypto-3.dll / libcrypto-3-x64.dll   # OpenSSL (x86 / x64)
  libssl-3.dll    / libssl-3-x64.dll      # OpenSSL (x86 / x64)
  Qt6Core.dll                         # x64 only — Qt6 qtbase Core
  shiboken6.abi3.dll                  # x64 only — PySide6 binding runtime
  pyside6.abi3.dll                    # x64 only — PySide6 binding runtime
  include/Python/...                  # Public + cpython + internal headers, plus PC/pyconfig.h
  lib/...                             # Pure-Python stdlib (.py files copied from Python/Lib)
  site-packages/                      # x64 only — PySide6 + shiboken6 Python packages
    PySide6/__init__.py
    PySide6/QtCore.pyd                # imports MagPython.dll directly (no python3.dll forwarder)
    shiboken6/...
```

Linux (`MagPython-linux-x86_64.zip`):

```
MagPython/
  libMagPython.so        # SONAME libMagPython.so, RUNPATH $ORIGIN
  libpython3.13.so.1.0   # symlink -> libMagPython.so (for abi3 NEEDED)
  libpython3.13.so       # symlink -> libMagPython.so (link-time alias)
  libpython3.so          # symlink -> libMagPython.so (stable-ABI alias)
  libcrypto.so.3
  libssl.so.3
  libsqlite3.so.0        # SONAME libsqlite3.so.0
  libsqlite3.so          # symlink -> libsqlite3.so.0
  libQt6Core.so.6        # Qt6 Core, RUNPATH $ORIGIN
  libshiboken6.abi3.so.6.X  # PySide6 binding runtime
  libpyside6.abi3.so.6.X    # PySide6 binding runtime
  include/Python/...
  lib/python3.13/        # stdlib at the path Python's Unix discovery
                         # looks for (lib/python<X.Y>/os.py)
  lib/python3.13/lib-dynload/   # empty (modules are statically linked)
  site-packages/
    PySide6/__init__.py
    PySide6/QtCore.abi3.so      # PySide6 Core module
    shiboken6/...               # PySide6 binding-runtime package
```

macOS arm64 (`MagPython-macos-arm64.zip`):

```
MagPython/
  libMagPython.dylib     # install_name @rpath/libMagPython.dylib
  libpython3.13.dylib    # symlink -> libMagPython.dylib
  libpython3.dylib       # symlink -> libMagPython.dylib
  libcrypto.3.dylib      # install_name @rpath/libcrypto.3.dylib
  libssl.3.dylib         # install_name @rpath/libssl.3.dylib
  libsqlite3.0.dylib     # install_name @rpath/libsqlite3.0.dylib
  libsqlite3.dylib       # symlink -> libsqlite3.0.dylib
  libQt6Core.6.dylib     # Qt6 Core
  libshiboken6.abi3.6.X.dylib  # PySide6 binding runtime
  libpyside6.abi3.6.X.dylib    # PySide6 binding runtime
  include/Python/...
  lib/python3.13/
  lib/python3.13/lib-dynload/
  site-packages/
    PySide6/__init__.py
    PySide6/QtCore.abi3.so
    shiboken6/...
```

Notable differences from a stock CPython Windows build:

- A single `MagPython.dll` instead of `python313.dll` plus a forest of `.pyd`
  files. Modules that upstream ships as separate `.pyd`s (`_ssl`, `_socket`,
  `select`, `_sqlite3`, `unicodedata`, `_ctypes`, `_decimal`, …) are linked
  directly into the DLL — see the `<ClCompile>` items in
  `MagPython/MagPython.vcxproj`.
- Builds for both `x86` (32-bit Win32) and `x64` (64-bit AMD64). The
  `Platform` defaults to `Win32` in `MagPython/common.props`; the x64
  build is selected by passing `/p:Platform=x64` to MSBuild.
  `PlatformToolset` is `v142` (VS 2019) on both. Deployment target is
  Windows 8.1 — `Py_WINVER` is `0x0603` in `Python/PC/pyconfig.h.in`,
  so `MagPython.dll` statically imports Windows 8.1 APIs (e.g. PSS) and
  is expected to load on Windows 8.1 and newer with the VC++
  2015-2022 redistributable installed.
- Frozen modules under `Python/Python/frozen_modules/` are regenerated
  as part of the build (see below) and are gitignored. The freezer
  binary itself is built but not shipped.

## How the build is wired

### Windows

`MagPython/MagPython.metaproj` is the top-level MSBuild project. It runs the
following sub-projects in order, each `BuildInParallel="True"
StopOnFirstFailure="True"`:

1. **`LibFFI.vcxproj`** — builds `libffi.lib` (static) from the
   build-time-downloaded source tree (`MagPython/libffi/libffi-<v>/`,
   populated by `download-libffi.ps1` running before the C compile).
   On Win32 it builds the `X86_WIN32` variant (`ffi.c` +
   `sysv_intel.S`, assembled with `ml.exe`); on x64 it builds the
   `X86_WIN64` variant (`ffiw64.c` + `win64_intel.S`, assembled with
   `ml64.exe`).
2. **`openssl.vcxproj`** — a `Makefile`-type project that runs
   `perl Configure VC-WIN32-ONECORE <no-* set>` (Win32) or
   `perl Configure VC-WIN64A-ONECORE <no-* set>` (x64) and then
   `jom -j%NUMBER_OF_PROCESSORS% build_libs` inside the build-time-
   downloaded source tree (`MagPython/openssl/openssl-<v>/`, populated
   by `download-openssl.ps1` and verified against the pinned SHA-256).
   `download-nasm.ps1` fetches
   NASM 2.16.01 from nasm.us before the build (NASM is required by
   OpenSSL's x86/x86_64 assembly). `download-jom.ps1` fetches jom — Qt's
   drop-in `nmake` replacement that supports parallel jobs (`-j`);
   Microsoft's nmake is single-threaded, so this cuts the OpenSSL
   build from sequential `cl.exe` spawns down to one process per core.
   Outputs: `libcrypto-<N>{,-x64}.dll`, `libssl-<N>{,-x64}.dll` (where
   `<N>` is derived from `openssl-version`'s major component, and the
   `-x64` suffix is OpenSSL's `shlib_variant` on x64; see the
   `OpenSslShlibVariant` property in `MagPython/common.props`), import
   libs, `applink.c`, and the headers, all copied into
   `MagPython/Release/`.
   A `VerifyOpenSSL` post-build target compiles + runs
   `MagPython/openssl-verify.c` against the staged libs to catch a
   misconfigured `no-*` set or a missing soname here, with a clear error,
   instead of surfacing later as a baffling `MagPython.dll` link failure.
3. **`ZLib.vcxproj`** — a `Makefile`-type project that runs upstream's
   `win32/Makefile.msc` via `jom -j%NUMBER_OF_PROCESSORS%` (re-using
   the same jom downloaded for OpenSSL) inside the build-time-
   downloaded zlib tree (`MagPython/zlib/zlib-<v>/`, populated by
   `download-zlib.ps1`). Targets just `zlib.lib`; `CopyArtifacts`
   stages it alongside `zlib.h` + `zconf.h` under
   `MagPython/Release/` (and `Release/include/`).
4. **`SQLite.vcxproj`** — a `Makefile`-type project that drives
   `cl.exe + lib.exe` directly on the upstream amalgamation
   (`MagPython/sqlite/sqlite-<v>/sqlite3.c`, populated by
   `download-sqlite.ps1`). sqlite ships no Makefile.msc — only the
   amalgamation — so there's nothing for jom to parallelise across.
   `CopyArtifacts` stages `sqlite3.lib` + `sqlite3.h` + `sqlite3ext.h`
   under `MagPython/Release/` (and `Release/include/`).
5. **`LibMpdec.vcxproj`** — a `Makefile`-type project that runs
   `nmake /f Makefile.vc MACHINE=ppro` on Win32 (the x87 inline-asm
   flavour) or `MACHINE=x64` on x64 (the AMD64 flavour), inside the
   build-time-downloaded mpdecimal source
   (`MagPython/libmpdec/mpdecimal-<v>/`, populated by
   `download-libmpdec.ps1`). Both match what CPython's bundled
   `_decimal.vcxproj` picks for the same platforms. `CopyArtifacts`
   renames `libmpdec-<version>.lib` to `libmpdec.lib` and stages
   alongside `mpdecimal.h` under `MagPython/Release/` (and
   `Release/include/`).
6. **`FreezeMagPython.vcxproj`** — builds `FreezeMagPython.exe` from
   CPython's `Programs/_freeze_module.c`. After it builds, post-build targets
   re-freeze the Python modules listed in the project (importlib bootstrap,
   `os`, `site`, `runpy`, the `__phello__` modules, etc.) into
   `Python/Python/frozen_modules/*.h` and freeze `getpath.py` separately.
   The generated tree is gitignored. CPython 3.13 removed deepfreeze
   entirely (the pre-3.13 deep-baked importlib bootstrap as a generated
   `.c` file), so frozen modules are now the only regen step.
7. **`MagPython.vcxproj`** — the main DLL. Compiles the Python core,
   `Objects/`, `Parser/`, selected `Modules/`, `PC/` glue,
   `_sqlite/*`, `_decimal/_decimal.c`, `_ssl`, `_hashopenssl`,
   `_socket`, `select`, `unicodedata`, `_ctypes`, and CPython's
   `zlibmodule.c` wrapper. Links against the `libcrypto.lib`,
   `libssl.lib`, `libffi.lib`, `zlib.lib`, `sqlite3.lib`, and
   `libmpdec.lib` produced by the earlier steps. The `CopyArtifacts`
   target then stages headers and the pure-Python stdlib into
   `Release/include/Python/` and `Release/lib/` so the output directory
   is a complete SDK drop.
8. **`test.vcxproj`** — compiles `MagPython/test.c` (a tiny embedding host
   that calls `Py_Initialize`, prints the compiler string, and runs an
   `import sys` line), copies the DLLs and `lib/` next to it, and **executes
   `test.exe`** as part of the build via an `<Exec>` task. A failed smoke
   test fails the build.

After the metaproj completes, the windows-x64 path additionally runs
`MagPython/build-pyside6-windows.sh` (driven by the workflow, not the
metaproj — it shells out to CMake + Ninja against MSVC and is awkward
to express as a vcxproj). The script fetches the same Qt6 + PySide6
source tarballs the Linux/macOS builds use, configures qtbase Core
only via CMake, then builds shiboken6 + pyside6 with
`Python_LIBRARY=MagPython/Release/MagPython.lib` so the linker
records `MagPython.dll` as the IAT DLL name on every generated
`.pyd`. The resulting DLLs + site-packages are staged into
`MagPython/Release/` next to `MagPython.dll`. No `python3.dll`
forwarder is shipped — pre-built abi3 wheels from PyPI (which link
against upstream's `python3.lib` and would expect `python3.dll` at
load time) are out of scope; only the bundled PySide6 + extensions
a downstream builds against this SDK (whose `pyconfig.h` `#pragma
comment(lib)` is rewritten to `MagPython.lib`) are supported.
windows-x86 skips this step (Qt 6 has no 32-bit Windows port).

`MagPython/common.props` pins the defaults: `Platform=Win32`,
`Configuration=Release`, `PlatformToolset=v142`. Build the x64 artifact
by overriding the platform: `msbuild /m /p:Configuration=Release
/p:Platform=x64 MagPython\MagPython.metaproj`. Add the PySide6 bundle
locally after that with `bash MagPython/build-pyside6-windows.sh`.

### Linux and macOS

`MagPython/build-linux.sh` and `MagPython/build-macos.sh` orchestrate the
Unix builds. Both source `MagPython/build-common.sh` and follow the same
shape as the Windows metaproj:

1. **Static deps** — zlib's `libz.a` (built from the build-time-
   downloaded source under `MagPython/zlib/zlib-<v>/`) is linked into
   the main library on both Linux and macOS. On Linux only, libffi's
   `libffi.a` (from `MagPython/libffi/libffi-<v>/`) is also linked
   statically; macOS instead uses the SDK's `/usr/lib/libffi.dylib`
   via CPython's Darwin-specific autoconf block, so no MagPython-built
   libffi exists in the macOS artifact. SQLite is built from the
   build-time-downloaded amalgamation
   (`MagPython/sqlite/sqlite-<v>/sqlite3.c`) into a shared library
   (`build-out/sqlite/libsqlite3.so.0` on Linux,
   `build-out/sqlite/libsqlite3.0.dylib` on macOS) that is shipped
   next to `libMagPython` rather than statically linked, so CPython's
   `configure` can find it via the standard `-L`/`-lsqlite3` autoconf
   probe path. Windows continues to build all three as separate static
   libs via `ZLib.vcxproj` / `LibFFI.vcxproj` / `SQLite.vcxproj`.
2. **OpenSSL** — `./Configure linux-x86_64` or `darwin64-arm64-cc`, then
   `make && make install_sw` into `build-out/openssl-out`. Produces
   `libcrypto.{so.3,3.dylib}` + `libssl.{so.3,3.dylib}`.
3. **libmpdec** — `setup_libmpdec` fetches
   `mpdecimal-<version>.tar.gz` from bytereef.org (version pinned in
   `MagPython/libmpdec-version`), verifies it against the SHA-256 hash
   pinned in `MagPython/libmpdec-sha256`, and extracts under
   `MagPython/libmpdec/` (cached across `prep_build_tree`
   wipes since it lives outside `build-out/`). `build_libmpdec` then
   runs upstream's `./configure --disable-cxx --enable-static
   --disable-shared` (with `--with-machine=universal` on macOS to
   match what CPython's own configure picks for arm64) and installs
   into `build-out/libmpdec-out/`.
4. **ncurses** — `build_ncurses` fetches `ncurses-<version>.tar.gz`
   from ftp.gnu.org (version pinned in `MagPython/ncurses-version`,
   hash in `MagPython/ncurses-sha256`), then runs upstream's
   `./configure --without-shared --with-pic --enable-widec
   --without-debug --without-tests --without-progs --without-cxx
   --without-cxx-binding --without-ada --without-manpages
   --enable-pc-files=no --without-termlib` and installs into
   `build-out/ncurses-out/`. Produces `libncursesw.a` + `libpanelw.a`
   (terminfo functions stay inside `libncursesw.a` because we don't
   pass `--with-termlib`, so there is no separate `libtinfo.a` to
   plumb through). POSIX-only — there is no Windows equivalent.
5. **Configure libpython** — out-of-tree configure in `build-out/main`
   with `--enable-shared --without-static-libpython
   --with-openssl=...build-out/openssl-out --with-system-libmpdec`,
   plus `ZLIB_*`, `LIBSQLITE3_*`, `LIBMPDEC_*`, and `CURSES_*` /
   `PANEL_*` env vars pointing at the libs from the earlier stages.
   `LDFLAGS=-Lbuild-out/sqlite` puts the shared sqlite directory on
   the linker's search path so `AC_CHECK_LIB([sqlite3], …)` probes
   resolve `-lsqlite3` cleanly. On Linux the call additionally passes
   `LIBFFI_CFLAGS` / `LIBFFI_LIBS` for the bundled static libffi; on
   macOS those are omitted so CPython's Darwin block in `configure`
   auto-detects the SDK's `ffi.h` and `-lffi`.
6. **Regen frozen, then make** — `make regen-frozen` followed by an
   awk pass that rewrites
   `Modules/Setup.stdlib`: it flips `*shared*` to `*static*`, then
   comments out the lines for modules listed under `*disabled*` in
   `MagPython/Setup.local`. (The `*disabled*` directive on its own only
   affects runtime registration in `Modules/config.c` — to keep modules
   out of the build entirely we need to drop their stdlib lines.) This
   produces a libpython that contains the same module subset as
   `MagPython/MagPython.vcxproj` does on Windows, plus the POSIX-only
   `_curses` / `_curses_panel` modules backed by the static ncurses.
7. **Rename, stage libMagPython** — `libpython3.13.{so.1.0,dylib}` is
   copied to `libMagPython.{so,dylib}` and its SONAME / install name is
   rewritten with `patchelf` (Linux) or `install_name_tool` (macOS).
   Linux additionally rewrites the RUNPATH to `$ORIGIN` so the artifact
   is relocatable; macOS rewrites OpenSSL `LC_LOAD_DYLIB` paths and
   absolute `LC_RPATH` entries to `@rpath/...`. The shared
   `libsqlite3.{so.0,0.dylib}` (already built with `SONAME=libsqlite3.so.0`
   / `install_name=@rpath/libsqlite3.0.dylib`) is copied alongside, with
   the unversioned symlink consumers expect from a normal sqlite
   install. Headers and the pure-Python stdlib are staged next to the
   libs (with a `Python/python.h -> Python.h` symlink so
   `MagPython/test.c`'s lowercase include resolves on case-sensitive
   filesystems).
8. **libpython symlinks** — `libpython3.13.{so.1.0,so,dylib}` and
   `libpython3.{so,dylib}` are added as symlinks pointing at
   `libMagPython.{so,dylib}`. Any abi3 / stable-ABI extension built
   with `-lpythonX.Y` ends up with a NEEDED of `libpythonX.Y.so.1.0` —
   the symlink chain forwards that into `libMagPython.so` at runtime
   without changing libMagPython's SONAME.
9. **Qt6 + PySide6** — `setup_qt6` / `build_qt6` fetches and builds
   qtbase (Core feature only — gui/widgets/network/sql/etc. are all
   `-DQT_FEATURE_*=OFF`) via CMake + Ninja into `$BUILD/qt6-out`.
   `setup_pyside6` / `build_pyside6` fetches the pyside-setup tarball
   and builds shiboken6 and pyside6 (Core module only) against our
   Qt6 + our libMagPython (via `Python_INCLUDE_DIR` /
   `Python_LIBRARY` pointed at the staged tree). `stage_pyside6`
   copies `libQt6Core`, `libshiboken6`, `libpyside6` into `$STAGE`
   next to `libMagPython`, copies the PySide6/shiboken6 Python
   packages into `$STAGE/site-packages/`, rewrites RPATHs /
   install_names so the binaries resolve as siblings of
   libMagPython, and strips debug symbols. The pip-installed `cmake`
   (>=3.21) + `ninja` from the host Python are used on both
   platforms; `clang` + `libclang` come from the system package
   manager on Linux and from Xcode on macOS.
10. **Smoke test + zip** — `MagPython/test.c` is built (with
    `-DMAGPYTHON_TEST_PYSIDE6=1` on POSIX) and run against the
    staged tree. The smoke test imports PySide6, instantiates a
    QCoreApplication, exercises a signal/slot round trip and a
    Q_PROPERTY access. Failure fails the build. The final zip is
    produced from `$BUILD/stage/MagPython/`.

The host Python required by `regen-frozen` is
`/opt/python/cp313-cp313/bin/python3` inside the manylinux_2_28 container
on Linux, and the `macos-14` runner's preinstalled `python3` on macOS.

## Building locally

### Windows

Requirements:

- Windows with Visual Studio 2019 build tools (MSVC v142, x86 and x64
  cross tools, Windows 8.1 SDK baseline).
- Perl in `PATH` (for OpenSSL `Configure`).
- A host Python in `PATH` or one discoverable by
  `Python/PCbuild/find_python.bat` (used by the frozen-modules regen).
- Network access on the first build (NASM is downloaded by
  `MagPython/download-nasm.ps1`).

From a "x86 Native Tools Command Prompt for VS 2019" at the repo root:

```cmd
msbuild /m /p:Configuration=Release MagPython\MagPython.metaproj
```

From a "x64 Native Tools Command Prompt for VS 2019" at the repo root:

```cmd
msbuild /m /p:Configuration=Release /p:Platform=x64 MagPython\MagPython.metaproj
```

These are exactly what the CI invokes. The shipped artifact is built by
then renaming `MagPython\Release` to `MagPython\MagPython` and zipping it.

### Linux

```sh
docker run --rm -v "$PWD":/src -w /src \
    quay.io/pypa/manylinux_2_28_x86_64 ./MagPython/build-linux.sh
```

(glibc 2.28 baseline — covers RHEL 8 / Ubuntu 20.04+.) Produces
`MagPython-linux-x86_64.zip` at the repo root. Build artifacts live under
`build-out/` (gitignored).

### macOS

On an Apple Silicon Mac with Xcode Command Line Tools installed:

```sh
./MagPython/build-macos.sh
```

Produces `MagPython-macos-arm64.zip` at the repo root.

## Updating pinned dependencies

Every dep follows the same shape: a `<dep>-version` and
`<dep>-sha256` pin file under `MagPython/`, the build downloads the
tarball at build time (Windows: `MagPython/download-<dep>.ps1`; Unix:
`setup_<dep>` in `build-common.sh`), verifies it against the pinned
hash, and caches under `MagPython/<dep>/` (gitignored). Each dep has
an `update-<dep>.sh` wrapper that bumps the pins; the shared logic
lives in `MagPython/update-pin-common.sh`, and the wrappers refuse
cross-major bumps so the build glue can be reviewed manually when an
ABI line changes.

The in-tree pin is the sole hash check; `update-<dep>.sh` downloads
the tarball and computes SHA-256 locally.

| Dep      | Source                                 | Line | Bump command                   |
| ---      | ---                                    | ---  | ---                            |
| OpenSSL  | `openssl/openssl` GitHub Releases      | 3.x  | `update-openssl.sh 3.5.7`      |
| zlib     | `madler/zlib` GitHub Releases          | 1.x  | `update-zlib.sh 1.3.3`         |
| SQLite   | sqlite.org                             | 3.x  | `update-sqlite.sh 3.53.2 2025` |
| libffi   | `libffi/libffi` GitHub Releases        | 3.x  | `update-libffi.sh 3.5.3`       |
| libmpdec | bytereef.org                           | 2.x  | `update-libmpdec.sh 2.5.2`     |
| ncurses  | ftp.gnu.org                            | 6.x  | `update-ncurses.sh 6.5`        |
| CPython  | `python/cpython` tag archive on GitHub | 3.x  | `update-python.sh 3.13.14`     |
| Qt6      | download.qt.io (qtbase submodule)      | 6.x  | edit `qt6-version` / `qt6-sha256` (no update-script yet — let the first build run, copy the actual sha from the mismatch message) |
| PySide6  | download.qt.io (pyside-setup)          | 6.x  | edit `pyside6-version` / `pyside6-sha256` (same bootstrap-via-CI workflow as Qt6) |

libmpdec is the C library behind the `_decimal` module. ncurses is
POSIX-only — the Windows artifact ships no curses module, so there is
no Windows download or build step; the canonical upstream is
invisible-island.net but the build pulls from ftp.gnu.org's mirror
because it serves the same tarball over stable HTTPS.

For a patch-level bump within the same major line nothing else needs
editing: every consumer (the `.vcxproj` files, `build-common.sh`,
`common.props`, the verification step) substitutes the version from
the relevant pin file, and the Windows DLL suffix / Unix soname for
OpenSSL is derived from the version's major component. A few deps
have extra moving parts noted below.

### SQLite — the `sqlite-year` pin

sqlite.org's download URL embeds a calendar-year segment that isn't
derivable from the version (e.g.
`https://sqlite.org/2025/sqlite-amalgamation-3530100.zip`), so the
year is pinned in `MagPython/sqlite-year` and passed as a second
positional arg to `update-sqlite.sh`. Look it up on
<https://sqlite.org/chronology.html> or in the release announcement.
The numeric `3530100` in the URL is the version encoded as
`<major>*1000000 + <minor>*10000 + <patch>*100`; the download scripts
compute it inline from the version pin.

### CPython — cross-minor bumps

The `Verify python drift` workflow (`.github/workflows/Verify python
drift.yml`) downloads the new tarball on Linux and confirms every
`$(PythonSourceDir)\<path>\<name>.c|h` ref in `MagPython.vcxproj` /
`FreezeMagPython.vcxproj` exists in the new tree. Cross-minor bumps
(e.g. 3.13 → 3.14) routinely surface MISSING refs here, and
reconciling them is part of the upgrade work — expect:

- `MagPython.vcxproj` — per-file `<ClCompile>`/`<ClInclude>` lists
  may need fixups for upstream renames or additions.
- `MagPython/Setup.local` — verify the disabled-modules list still
  matches the upstream `Modules/Setup.stdlib` shape.
- The Linux/macOS build scripts derive `python3.<minor>` paths from
  `PY_X_Y` (computed from the pin), so the libpython soname and
  staged `lib/python<X.Y>/` directory follow automatically.

### Cross-major bumps

`update-<dep>.sh` rejects anything outside the configured major line
because cross-major bumps typically need build-glue revisions —
Configure flag sets, soname conventions, OpenSSL's `OpenSslDllSuffix`
derivation, mpdecimal's `MACHINE=ppro` / `--with-machine=universal`
/ `CONFIG_32;PPRO` flavour selection, and so on.

## Continuous integration

`.github/workflows/Build All.yml` is a single matrix-based workflow that
fans out across four platforms:

- `windows-2025` (x86, MSVC) — runs the existing `msbuild MagPython.metaproj`
  flow with `Platform=Win32` (the default).
- `windows-2025` (x64, MSVC) — runs the same flow with `Platform=x64`.
  Shares the image with the x86 job; the x86 and x64 MSVC tools both
  come from the `VC.Tools.142.x86.x64` component group.
- `ubuntu-22.04` inside the `quay.io/pypa/manylinux_2_28_x86_64` container
  — runs `MagPython/build-linux.sh`.
- `macos-14` — runs `MagPython/build-macos.sh`.

`fail-fast: false` so a transient failure on one platform doesn't cancel
the others. `timeout-minutes: 30` per matrix job. Each job uploads its
zip as a separate artifact named `MagPython-<platform>` with 7-day
retention; downstream consumers (the host application's CI) fetch them
by name.

## Licensing

| Dependency    | License                                                                                    |
| ---           | ---                                                                                        |
| CPython       | PSF License                                                                                |
| OpenSSL       | Apache-2.0 license                                                                         |
| zlib          | zlib license                                                                               |
| libffi        | MIT                                                                                        |
| libmpdec      | BSD-2-Clause                                                                               |
| SQLite        | public domain (from the comment in `sqlite3.h`, cf. https://www.sqlite.org/copyright.html) |
| ncurses       | MIT-style "X11" license                                                                    |
| Qt6 qtbase    | LGPL-3.0-only (with the usual relinking exception)                                         |
| PySide6       | LGPL-3.0-only                                                                              |

License files are added to the build artifacts for downstream consumers.
