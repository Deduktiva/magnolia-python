# magnolia-python

A custom build of CPython 3.13.13 for embedding into a host application,
packaging the interpreter, the standard library extension modules, and the
supporting crypto/compression/database libraries into a single
shared library. Three platforms are produced from the same source tree:

| Platform        | Runner          | Main library             |
| ---             | ---             | ---                      |
| Windows x86     | `windows-2025`  | `MagPython.dll`          |
| Linux x86_64    | manylinux_2_28  | `libMagPython.so`        |
| macOS arm64     | `macos-14`      | `libMagPython.dylib`     |

## What's in here

| Path | Contents |
| --- | --- |
| `Python/` | Vendored CPython 3.13.13 source tree (upstream `python/cpython`). |
| `MagPython/openssl-version`, `MagPython/openssl-sha256` | Pinned version + expected tarball SHA-256 of OpenSSL. The source is downloaded from openssl/openssl GitHub Releases at build time (`MagPython/download-openssl.ps1` on Windows, `setup_openssl` in `build-common.sh` on Unix), verified against the pinned hash *and* the upstream `.sha256` sidecar, and cached under `MagPython/openssl/`; not vendored. |
| `MagPython/zlib-version`, `MagPython/zlib-sha256` | Pinned version + expected tarball SHA-256 of zlib. The source is downloaded from madler/zlib GitHub Releases at build time (`MagPython/download-zlib.ps1` on Windows, `setup_zlib` in `build-common.sh` on Unix), verified against the pinned hash, and cached under `MagPython/zlib/`; not vendored. |
| `MagPython/libffi-version`, `MagPython/libffi-sha256` | Pinned version + expected tarball SHA-256 of libffi (used by `_ctypes`). The source is downloaded from libffi/libffi GitHub Releases at build time (`MagPython/download-libffi.ps1` on Windows, `setup_libffi` in `build-common.sh` on Unix), verified against the pinned hash, and cached under `MagPython/libffi/`; not vendored. The project-local pregenerated MSVC headers (`ffi.h`, `fficonfig.h`) live under `MagPython/libffi-msvc-include/`. |
| `MagPython/sqlite-version`, `MagPython/sqlite-year`, `MagPython/sqlite-sha256` | Pinned version + release-year + expected SHA-256 of the SQLite amalgamation zip. The zip is downloaded from sqlite.org at build time (`MagPython/download-sqlite.ps1` on Windows, `setup_sqlite` in `build-common.sh` on Unix), verified against the pinned hash, and cached under `MagPython/sqlite/`; not vendored. |
| `MagPython/libmpdec-version`, `MagPython/libmpdec-sha256` | Pinned version + expected tarball SHA-256 of mpdecimal (used by `_decimal`). The source is downloaded from bytereef.org at build time (`MagPython/download-libmpdec.ps1` on Windows, `setup_libmpdec` in `build-common.sh` on Unix), verified against the pinned hash, and cached under `MagPython/libmpdec/`; not vendored. |
| `MagPython/` | All of the project's own build glue: MSBuild projects + `*.props` for Windows, `build-linux.sh` / `build-macos.sh` / `build-common.sh` for Unix, the shared smoke test (`test.c`), `Setup.local` (modules omitted from libMagPython on Unix to mirror MagPython.vcxproj), and helper scripts (`update-python.sh`, `update-openssl.sh`, `update-zlib.sh`, `update-libffi.sh`, `update-sqlite.sh`, `update-libmpdec.sh`, `update-nasm.sh`, `update-jom.sh`, `download-nasm.ps1`, `download-openssl.ps1`, `download-zlib.ps1`, `download-libffi.ps1`, `download-sqlite.ps1`, `download-libmpdec.ps1`, `download-jom.ps1`). |
| `.github/workflows/Build All.yml` | CI that builds and uploads the artifact. |

The vendored library directories are the upstream sources, used as-is; all of
the project-specific build configuration lives under `MagPython/`.

## Build outputs

Each platform produces one zip with the same shape — a `MagPython/`
directory containing the main shared lib, the OpenSSL libs, the headers,
and the pure-Python stdlib. zlib, libffi, sqlite, and libmpdec are linked
statically into the main library on every platform.

Windows (`MagPython-windows-x86.zip`):

```
MagPython/
  MagPython.dll          # Python core + builtin modules + zlib + sqlite + libffi + libmpdec
  libcrypto-3.dll        # OpenSSL
  libssl-3.dll           # OpenSSL
  include/Python/...     # Public + cpython + internal headers, plus PC/pyconfig.h
  lib/...                # Pure-Python stdlib (.py files copied from Python/Lib)
```

Linux (`MagPython-linux-x86_64.zip`):

```
MagPython/
  libMagPython.so        # SONAME libMagPython.so, RUNPATH $ORIGIN
  libcrypto.so.3
  libssl.so.3
  include/Python/...
  lib/python3.13/        # stdlib at the path Python's Unix discovery
                         # looks for (lib/python<X.Y>/os.py)
  lib/python3.13/lib-dynload/   # empty (modules are statically linked)
```

macOS arm64 (`MagPython-macos-arm64.zip`):

```
MagPython/
  libMagPython.dylib     # install_name @rpath/libMagPython.dylib
  libcrypto.3.dylib      # install_name @rpath/libcrypto.3.dylib
  libssl.3.dylib         # install_name @rpath/libssl.3.dylib
  include/Python/...
  lib/python3.13/
  lib/python3.13/lib-dynload/
```

Notable differences from a stock CPython Windows build:

- A single `MagPython.dll` instead of `python312.dll` plus a forest of `.pyd`
  files. Modules that upstream ships as separate `.pyd`s (`_ssl`, `_socket`,
  `select`, `_sqlite3`, `unicodedata`, `_ctypes`, `_decimal`, …) are linked
  directly into the DLL — see the `<ClCompile>` items in
  `MagPython/MagPython.vcxproj`.
- `SubSystem` is `Windows` (no console), `GenerateManifest` is off,
  `Py_BUILD_CORE_BUILTIN` is defined for everything in the DLL, and the link
  uses `version.lib;Crypt32.lib;winmm.lib;pathcch.lib;bcrypt.lib;ws2_32.lib;
  iphlpapi.lib;Rpcrt4.lib`.
- Targets `x86` only (the `Platform` defaults to `Win32` in
  `MagPython/common.props`); `PlatformToolset` is `v142` (VS 2019).
  Deployment target is Windows 8.1 — `Py_WINVER` is `0x0603` in
  `Python/PC/pyconfig.h.in`, so `MagPython.dll` statically imports
  Windows 8.1 APIs (e.g. PSS) and is expected to load on Windows 8.1
  and newer with the VC++ 2015-2022 redistributable installed.
- Frozen modules under `Python/Python/frozen_modules/` are regenerated
  as part of the build (see below) and are gitignored.

## How the build is wired

### Windows

`MagPython/MagPython.metaproj` is the top-level MSBuild project. It runs the
following sub-projects in order, each `BuildInParallel="True"
StopOnFirstFailure="True"`:

1. **`LibFFI.vcxproj`** — builds `libffi.lib` (static) from the
   build-time-downloaded source tree (`MagPython/libffi/libffi-<v>/`,
   populated by `download-libffi.ps1` running before the C compile)
   for `X86_WIN32`, using the project-local pregenerated MSVC headers
   under `MagPython/libffi-msvc-include/` (upstream only ships
   pregenerated MSVC headers for aarch64; the x86_win32 variant is
   maintained here, regenerated by `update-libffi.sh` on each version
   bump).
2. **`openssl.vcxproj`** — a `Makefile`-type project that runs
   `perl Configure VC-WIN32-ONECORE <no-* set>` and then
   `jom -j%NUMBER_OF_PROCESSORS% build_libs` inside the build-time-
   downloaded source tree (`MagPython/openssl/openssl-<v>/`, populated
   by `download-openssl.ps1` and verified against the pinned SHA-256
   *and* the upstream `.sha256` sidecar). `download-nasm.ps1` fetches
   NASM 2.16.01 from nasm.us before the build (NASM is required by
   OpenSSL's x86 assembly). `download-jom.ps1` fetches jom — Qt's
   drop-in `nmake` replacement that supports parallel jobs (`-j`);
   Microsoft's nmake is single-threaded, so this cuts the OpenSSL
   build from sequential `cl.exe` spawns down to one process per core.
   Outputs: `libcrypto-<N>.dll`, `libssl-<N>.dll` (where `<N>` is
   derived from `openssl-version`'s major component), import libs,
   `applink.c`, and the headers, all copied into `MagPython/Release/`.
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
   `nmake /f Makefile.vc MACHINE=ppro` inside the build-time-
   downloaded mpdecimal source (`MagPython/libmpdec/mpdecimal-<v>/`,
   populated by `download-libmpdec.ps1`). `CopyArtifacts` renames
   `libmpdec-<version>.lib` to `libmpdec.lib` and stages alongside
   `mpdecimal.h` under `MagPython/Release/` (and `Release/include/`).
6. **`FreezeMagPython.vcxproj`** — builds `FreezeMagPython.exe` from
   CPython's `Programs/_freeze_module.c`. After it builds, post-build targets
   re-freeze the Python modules listed in the project (importlib bootstrap,
   `os`, `site`, `runpy`, the `__phello__` modules, etc.) into
   `Python/Python/frozen_modules/*.h` and freeze `getpath.py` separately.
   The generated tree is gitignored. CPython 3.13 removed deepfreeze
   entirely (the pre-3.13 deep-baked importlib bootstrap as a generated
   `.c` file), so frozen modules are now the only regen step. The
   freezer binary is built but not shipped (commit `3afe7fc`).
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

`MagPython/common.props` pins the defaults: `Platform=Win32`,
`Configuration=Release`, `PlatformToolset=v142`.

### Linux and macOS

`MagPython/build-linux.sh` and `MagPython/build-macos.sh` orchestrate the
Unix builds. Both source `MagPython/build-common.sh` and follow the same
shape as the Windows metaproj:

1. **Static deps** — zlib's `libz.a` and libffi's `libffi.a` (both
   built from the build-time-downloaded sources under
   `MagPython/zlib/zlib-<v>/` and `MagPython/libffi/libffi-<v>/`),
   plus `build-out/sqlite/libsqlite3.a` (compiled from the
   build-time-downloaded amalgamation under
   `MagPython/sqlite/sqlite-<v>/sqlite3.c`). All three end up linked
   into the main library, mirroring the Windows configuration where
   they're each built as separate static libs by `ZLib.vcxproj` /
   `LibFFI.vcxproj` / `SQLite.vcxproj`.
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
4. **Configure libpython** — out-of-tree configure in `build-out/main`
   with `--enable-shared --without-static-libpython
   --with-openssl=...build-out/openssl-out --with-system-libmpdec`,
   plus `LIBFFI_*`, `ZLIB_*`, `LIBSQLITE3_*`, and `LIBMPDEC_*` env
   vars pointing at the static libs from the earlier stages.
5. **Regen frozen, then make** — `make regen-frozen` followed by an
   awk pass that rewrites
   `Modules/Setup.stdlib`: it flips `*shared*` to `*static*`, then
   comments out the lines for modules listed under `*disabled*` in
   `MagPython/Setup.local`. (The `*disabled*` directive on its own only
   affects runtime registration in `Modules/config.c` — to keep modules
   out of the build entirely we need to drop their stdlib lines.) This
   produces a libpython that contains the same module subset as
   `MagPython/MagPython.vcxproj` does on Windows.
6. **Rename, stage, smoke test, zip** — `libpython3.13.{so.1.0,dylib}` is
   copied to `libMagPython.{so,dylib}` and its SONAME / install name is
   rewritten with `patchelf` (Linux) or `install_name_tool` (macOS).
   Linux additionally rewrites the RUNPATH to `$ORIGIN` so the artifact
   is relocatable; macOS rewrites OpenSSL `LC_LOAD_DYLIB` paths and
   absolute `LC_RPATH` entries to `@rpath/...`. Headers and the
   pure-Python stdlib are staged next to the libs (with a
   `Python/python.h -> Python.h` symlink so `MagPython/test.c`'s
   lowercase include resolves on case-sensitive filesystems),
   `MagPython/test.c` is built and run against the staged tree (failure
   fails the build), and the final zip is produced.

The host Python required by `regen-frozen` is
`/opt/python/cp313-cp313/bin/python3` inside the manylinux_2_28 container
on Linux, and the `macos-14` runner's preinstalled `python3` on macOS.

## Building locally

### Windows

Requirements:

- Windows with Visual Studio 2019 build tools (MSVC v142, x86 cross tools,
  Windows 8.1 SDK baseline — see commit `1bbd920`).
- Perl in `PATH` (for OpenSSL `Configure`).
- A host Python in `PATH` or one discoverable by
  `Python/PCbuild/find_python.bat` (used by the frozen-modules regen).
- Network access on the first build (NASM is downloaded by
  `MagPython/download-nasm.ps1`).

From a "x86 Native Tools Command Prompt for VS 2019" at the repo root:

```cmd
msbuild /m /p:Configuration=Release MagPython\MagPython.metaproj
```

This is exactly what the CI invokes. The shipped artifact is built by then
renaming `MagPython\Release` to `MagPython\MagPython` and zipping it.

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

## Updating pinned OpenSSL

OpenSSL is the first dependency to move off the in-tree vendoring
pattern: its version is pinned in `MagPython/openssl-version` and the
expected tarball SHA-256 in `MagPython/openssl-sha256`; the tarball
itself is downloaded from `openssl/openssl` GitHub Releases at build
time (`download-openssl.ps1` on Windows, `setup_openssl` in
`build-common.sh` on Unix), verified against the pinned hash *and*
cross-checked against the upstream `.sha256` sidecar, and cached under
`MagPython/openssl/` (gitignored).

### How a bump works

```sh
MagPython/update-openssl.sh 3.5.7
```

The script validates the version is on the 3.x line, fetches the
upstream `.sha256` sidecar, validates it as a 64-char hex digest, and
rewrites `MagPython/openssl-version` and `MagPython/openssl-sha256`
in place. It deliberately does NOT download the tarball itself — the
build does that with the same hash check, so duplicating it here would
just slow down the bump.

After running:

1. Run a full Windows + Linux + macOS build. The download scripts fetch
   the tarball, hash it, and compare against `openssl-sha256` *and* the
   upstream sidecar; any mismatch deletes the downloaded file and fails
   the build immediately.
2. Commit both `MagPython/openssl-version` and
   `MagPython/openssl-sha256` together (no other file changes are
   expected on a patch bump within the 3.x line).

### What else changes on an OpenSSL bump?

For a patch-level bump within the 3.x line, the build glue needs **no
version-specific edits**:

- The Windows DLL suffix (`3` today) is derived by `MagPython/common.props`
  from the major component of `MagPython/openssl-version`, which feeds
  `libcrypto-$(OpenSslDllSuffix).dll` / `libssl-$(OpenSslDllSuffix).dll`
  in `MagPython/openssl.vcxproj` and `MagPython/MagPython.vcxproj`.
- The Unix soname (`3` today) is auto-detected by
  `MagPython/build-common.sh:openssl_shlib_version()` from the
  downloaded tree's `VERSION.dat` (with the major-component fallback
  used pre-download), and threaded into the `patchelf` /
  `install_name_tool` calls in `build-linux.sh` / `build-macos.sh`.
- The `Configure` flag set lives in
  `MagPython/build-common.sh:build_openssl()` (Unix) and
  `MagPython/openssl.vcxproj`'s `NMakeBuildCommandLine` (Windows). It
  trims the build to the surface CPython's `_ssl` / `_hashopenssl`
  actually use — see the comments in `build_openssl` for the per-flag
  rationale.

A cross-major bump (e.g. 3.x → 4.x) is a different kind of upgrade:
the Configure flag set, soname conventions, and `OpenSslDllSuffix`
derivation may all need revisiting.

## Updating pinned zlib

zlib's version is pinned in `MagPython/zlib-version` and the expected
tarball SHA-256 in `MagPython/zlib-sha256`; the tarball itself is
downloaded from `madler/zlib` GitHub Releases at build time
(`download-zlib.ps1` on Windows, `setup_zlib` in `build-common.sh` on
Unix), verified against the pinned hash, and cached under
`MagPython/zlib/` (gitignored). madler/zlib doesn't publish per-tarball
`.sha256` sidecars on its GitHub releases, so the in-tree pin is the
sole hash check (same shape as libmpdec, and matches the OpenSSL flow
minus the upstream-sidecar cross-check).

### How a bump works

```sh
MagPython/update-zlib.sh 1.3.3
```

The script validates the version is on the 1.x line, downloads the
tarball, computes SHA-256 locally, and rewrites
`MagPython/zlib-version` and `MagPython/zlib-sha256` in place.

After running:

1. Run a full Windows + Linux + macOS build. The download scripts
   re-fetch the tarball, hash it, and compare against `zlib-sha256`;
   any mismatch deletes the downloaded file and fails the build
   immediately.
2. Commit both `MagPython/zlib-version` and `MagPython/zlib-sha256`
   together (no other file changes are expected on a patch bump within
   the 1.x line).

### What else changes on a zlib bump?

For a patch-level bump within the same minor line, nothing else
should need editing — `ZLib.vcxproj` (Windows), `setup_zlib` /
`build_static_deps` in `build-common.sh` (Unix), and `common.props`
all substitute the version from `zlib-version`, and the verification
step reads the new hash from `zlib-sha256`.

A cross-major bump (e.g. 1.x → 2.x) would warrant a manual review of
the build glue (the upstream `win32/Makefile.msc` target name and the
`./configure --static` flag set may shift), so `update-zlib.sh`
refuses anything outside `1.*`.

## Updating pinned SQLite

SQLite's version is pinned in `MagPython/sqlite-version`, the
calendar release-year in `MagPython/sqlite-year`, and the expected
amalgamation-zip SHA-256 in `MagPython/sqlite-sha256`. The zip is
downloaded from sqlite.org at build time (`download-sqlite.ps1` on
Windows, `setup_sqlite` in `build-common.sh` on Unix), verified
against the pinned hash, and cached under `MagPython/sqlite/`
(gitignored). sqlite.org doesn't publish per-zip `.sha256` sidecars,
so the in-tree pin is the sole hash check.

The year pin exists because sqlite.org's download URL embeds a
calendar-year segment (e.g.
`https://sqlite.org/2025/sqlite-amalgamation-3530100.zip`) that isn't
derivable from the version. Look it up on
<https://sqlite.org/chronology.html> or in the release announcement.

The numeric `3530100` in the URL is the version encoded as
`<major>*1000000 + <minor>*10000 + <patch>*100` (e.g. 3.53.1 →
`3530100`); the download scripts compute it inline from the version
pin.

### How a bump works

```sh
MagPython/update-sqlite.sh 3.53.2 2025
```

The script validates the version is on the 3.x line and the year is
four digits, downloads the zip, computes SHA-256 locally, and
rewrites all three pin files (`sqlite-version`, `sqlite-year`,
`sqlite-sha256`).

After running:

1. Run a full Windows + Linux + macOS build. The download scripts
   re-fetch the zip, hash it, and compare against `sqlite-sha256`;
   any mismatch deletes the downloaded file and fails the build
   immediately.
2. Commit all three pin files together:

   ```sh
   git add MagPython/sqlite-version MagPython/sqlite-year MagPython/sqlite-sha256
   git commit -m 'Bump sqlite pin to 3.53.2 (2025)'
   ```

### What else changes on a SQLite bump?

For a patch-level bump within the 3.x line, no other files need
editing — `SQLite.vcxproj` and `setup_sqlite` substitute the version
from `sqlite-version`, the URL year comes from `sqlite-year`, and
the verification step reads the new hash from `sqlite-sha256`.

A cross-major bump (e.g. 3.x → 4.x) would warrant a manual review of
the build glue, so `update-sqlite.sh` refuses anything outside the
3.x line.

## Updating pinned libffi

libffi's version is pinned in `MagPython/libffi-version` and the
expected tarball SHA-256 in `MagPython/libffi-sha256`; the tarball
itself is downloaded from `libffi/libffi` GitHub Releases at build
time (`download-libffi.ps1` on Windows, `setup_libffi` in
`build-common.sh` on Unix), verified against the pinned hash, and
cached under `MagPython/libffi/` (gitignored). libffi/libffi doesn't
publish per-tarball `.sha256` sidecars on its GitHub releases, so the
in-tree pin is the sole hash check (same shape as zlib and libmpdec).

### The MagPython/libffi-msvc-include/ headers

Upstream libffi ships pre-generated MSVC headers only for `aarch64`
(under `msvc_build/aarch64/`); it has never published an x86 Windows
variant. Two files we need, `ffi.h` and `fficonfig.h`, therefore live
under `MagPython/libffi-msvc-include/`, outside the build-time-
downloaded source tree (which gets wiped on each tarball extract).
`update-libffi.sh` handles them differently:

- **`ffi.h`** is regenerated on every run from upstream's
  `include/ffi.h.in` template via six `sed` substitutions (`@VERSION@`,
  `@FFI_VERSION_STRING@`, `@FFI_VERSION_NUMBER@`, `@TARGET@` →
  `X86_WIN32`, `@HAVE_LONG_DOUBLE@` → `0`, `@FFI_EXEC_TRAMPOLINE_TABLE@`
  → `0`). The script aborts if upstream introduces a new `@VAR@` token
  it doesn't know how to substitute, or if any token slips through
  unsubstituted into the regenerated file.

- **`fficonfig.h`** is autoheader output that depends on autoconf
  feature-detection results, so the script can't substitute tokens by
  hand the way `ffi.h` works. The committed copy is preserved across
  upgrades. If upstream's `fficonfig.h.in` template changes between
  the previous and new libffi versions, the project-local
  `fficonfig.h` may need to be regenerated by hand on a Linux/macOS
  host (the script prints the recipe at the end of its run):

  ```sh
  cd MagPython/libffi/libffi-X.Y.Z
  ./configure --host=i686-w64-mingw32 --enable-static
  cp fficonfig.h <repo>/MagPython/libffi-msvc-include/fficonfig.h
  ```

### How a bump works

```sh
MagPython/update-libffi.sh 3.5.3
```

The script validates the version is on the 3.x line, downloads the
tarball, computes SHA-256 locally, rewrites
`MagPython/libffi-version` and `MagPython/libffi-sha256`, then
regenerates `MagPython/libffi-msvc-include/ffi.h` from the new
upstream's template.

After running:

1. Run a full Windows + Linux + macOS build. The download scripts
   re-fetch the tarball, hash it, and compare against `libffi-sha256`;
   any mismatch deletes the downloaded file and fails the build
   immediately.
2. Commit pin + regenerated header(s) together:

   ```sh
   git add MagPython/libffi-version MagPython/libffi-sha256 \
           MagPython/libffi-msvc-include/
   git commit -m 'Bump libffi pin to 3.5.3'
   ```

### What else changes on a libffi bump?

For a patch-level bump within the 3.x line, the build glue needs
no version-specific edits — `LibFFI.vcxproj` substitutes the
version from `libffi-version` into its source path, the build glue
on Unix looks up the cache via `$LIBFFI_SRC`, and the regenerated
`ffi.h` carries the new version string. Changes to the
`LibFFI.vcxproj` per-file `<ClCompile>` / `<CustomBuild>` list (rare
on the 3.x line) need to be made by hand and would surface as a
build failure on the new version.

A cross-major bump (e.g. 3.x → 4.x) is a different kind of upgrade
and the script refuses anything outside the 3.x line.

## Updating vendored Python

`MagPython/update-python.sh` is the analogous helper for the CPython
source tree:

```sh
MagPython/update-python.sh 3.13.3
```

Same overall shape as the OpenSSL/zlib/SQLite/libffi scripts (bash
3.2, macOS-friendly, no upstream-anchored hash so just prints the
SHA-256 of the downloaded tarball for the record). What's
Python-specific:

1. Pinned to the CPython **3.x** line. A 4.x bump would warrant a
   manual review of every piece of build glue, so the script refuses
   anything outside `3.*`. Note that *cross-minor* bumps (e.g. 3.12 →
   3.13) routinely add or rename C source files and tweak APIs
   `MagPython.vcxproj` references — the drift detector flags those,
   but reconciling them is part of the upgrade work.
2. Downloads `cpython-<version>.tar.gz` from
   `https://github.com/python/cpython/archive/refs/tags/v<version>.tar.gz`.
   We use the GitHub tag archive rather than python.org's release
   tarball because the GitHub archive is also signed-by-HTTPS,
   immutable per-tag, and the only material content differences are
   files the build doesn't use anyway.
3. After extracting, the script drops files the build never references
   and that python.org's release tarball also omits, so the imported
   tree stays minimal:

   - `.azure-pipelines/`, `.github/` — CI for python/cpython itself.
   - `.gitignore`, `.gitattributes` — git metadata.
   - `Misc/NEWS.d/` — per-version changelog fragments.
   - `PC/icons/` — icons for the `python.exe` / `launcher.exe` GUI
     executables that we don't ship.

   The unpacked `Include/patchlevel.h`'s embedded `PY_VERSION` is
   cross-checked against the requested version as a sanity guard.
4. Replaces the contents of `Python/` in place. The wipe-and-replace
   intentionally removes any project-local patches sitting on top of
   the previous import (e.g. the Windows-API-baseline tweak in
   `PC/pyconfig.h`, the static-module hookups in `PC/config.c`).
   Re-apply those in *separate* follow-up commits so the import
   commit is purely the upstream tree:

   ```sh
   git log --oneline <prev-import-sha>..HEAD -- Python/
   ```

   shows the project-local commits to replay against the new tree.

### Drift detection

Drift between `MagPython/MagPython.vcxproj`'s
`$(PythonSourceDir)\<path>\<name>.c|h` references and the new tree
is scoped to the directories the vcxproj substantially curates
(≥50% of the directory's `.c`/`.h` files referenced) — otherwise
CPython's much larger module/test/doc tree would drown the report
in noise. The previous tree's intentional exclusions in those
covered directories are subtracted as a baseline so each run only
surfaces drift introduced by *this* upgrade. As elsewhere, **GONE**
entries (vcxproj refs that no longer exist in the new tree) are
always reported regardless — `<ClInclude>` ones rot the IDE view,
`<ClCompile>` ones break the build.

### What else changes on a Python bump?

- `README.md` — the intro paragraph (`A custom build of CPython
  X.Y.Z`), the vendored-libraries table (`Vendored CPython X.Y.Z
  source tree.`), and the `lib/python<X.Y>/` paths in the Linux /
  macOS build-output examples (these track the minor version, so
  patch-only bumps within the same minor leave them alone).
- `MagPython/MagPython.vcxproj` — the `<ClCompile>`/`<ClInclude>`
  lists, *if and only if* the drift detector reports new or gone
  files. Patch-level bumps within a minor line generally stay quiet;
  cross-minor bumps usually need fixups.
- The Linux/macOS build scripts hardcode `python3.<minor>`-shaped
  paths in a few places (the libpython soname, the staged
  `lib/python<X.Y>/` directory). Those need a manual edit on a
  cross-minor bump.
- Any project-local Python-tree patches that the wipe-and-replace
  removed (re-apply in separate commits, as above).

## Updating pinned libmpdec

`libmpdec` (the C library behind `_decimal`) is the one dependency that
isn't checked in. Its version is pinned in `MagPython/libmpdec-version`
and the expected tarball SHA-256 in `MagPython/libmpdec-sha256`; the
tarball itself is downloaded from bytereef.org at build time, verified
against that pinned hash, and cached under `MagPython/libmpdec/`
(gitignored). bytereef.org doesn't publish per-tarball `.sha256`
sidecars — the hashes live only in the table at
<https://www.bytereef.org/mpdecimal/download.html> — which is why the
hash is pinned in-tree alongside the version.

### Why not vendored

CPython 3.13 still ships a bundled libmpdec but plans to remove it in
3.16; on macOS arm64 the bundled copy hits ADRP relocation issues that
this repo previously worked around by disabling `_decimal` entirely
(see commit history of `MagPython/Setup.local`). Pulling upstream
mpdecimal at build time and linking it as a static archive sidesteps
both: we get a `_decimal` that works on all three platforms, and we
don't carry the ~40-file libmpdec source tree in this repo.

### How a bump works

```sh
MagPython/update-libmpdec.sh 2.5.2
```

The script validates the version is on the 2.x line, downloads the
tarball from `bytereef.org`, computes SHA-256 locally (bytereef.org
doesn't publish per-tarball sidecars), and rewrites
`MagPython/libmpdec-version` and `MagPython/libmpdec-sha256` in
place.

After running:

1. Run a full Windows + Linux + macOS build. The download scripts
   re-fetch the tarball from
   `https://www.bytereef.org/software/mpdecimal/releases/`, hash it,
   and compare against `libmpdec-sha256`; any mismatch deletes the
   downloaded file and fails the build immediately.
2. Commit both `MagPython/libmpdec-version` and
   `MagPython/libmpdec-sha256` together (no other file changes are
   expected on a patch bump).

### What else changes on a libmpdec bump?

For a patch-level bump within the same minor line, nothing else
should need editing — `LibMpdec.vcxproj`, `setup_libmpdec` /
`build_libmpdec` in `build-common.sh`, and `common.props` all
substitute the version from `libmpdec-version`, and the verification
step reads the new hash from `libmpdec-sha256`.

A cross-minor bump (e.g. 2.5.x → 4.x) is a different kind of
upgrade: mpdecimal's ABI and `MACHINE=` flavours have changed
between major lines, so you'll likely need to revisit the
`MACHINE=ppro` flag in `LibMpdec.vcxproj`, the
`--with-machine=universal` flag in `build-macos.sh`, and the
`CONFIG_32;PPRO` defines on the `_decimal.c` ClCompile in
`MagPython.vcxproj`.

## Continuous integration

`.github/workflows/Build All.yml` is a single matrix-based workflow that
fans out across three platforms:

- `windows-2025` (x86, MSVC) — runs the existing `msbuild MagPython.metaproj`
  flow.
- `ubuntu-22.04` inside the `quay.io/pypa/manylinux_2_28_x86_64` container
  — runs `MagPython/build-linux.sh`.
- `macos-14` — runs `MagPython/build-macos.sh`.

`fail-fast: false` so a transient failure on one platform doesn't cancel
the others. `timeout-minutes: 30` per matrix job. Each job uploads its
zip as a separate artifact named `MagPython-<platform>` with 7-day
retention; downstream consumers (the host application's CI) fetch them
by name.

Triggers: pushes to `main`, PRs to `main`, a weekly schedule (Mondays
06:00 UTC, to catch silent breakages), and `workflow_dispatch`.
Concurrency-grouped per `github.ref` with cancel-in-progress.

`.github/dependabot.yaml` keeps the GitHub Actions versions current on a
monthly cadence.

`.github/workflows/Verify libffi drift.yml` runs on PRs that touch
`MagPython/{libffi-version,libffi-sha256,LibFFI.vcxproj}`. It downloads
the pinned libffi tarball on a Linux runner and confirms every `.c` /
`.S` / `.h` file `LibFFI.vcxproj` references actually exists in the
new tree — without this, drift only surfaces later as a cl.exe C1083
error during a 5+ minute Windows build job. The drift logic lives in
`MagPython/check-libffi-drift.sh` and is the libffi-specific
counterpart to the per-file file-list management the Makefile-typed
`ZLib.vcxproj` / `SQLite.vcxproj` / `LibMpdec.vcxproj` projects don't
need (their file lists come from upstream's own makefile or from a
single amalgamation file).

## Auto-update via Renovate

`.github/renovate.json` configures Renovate to open monthly version-
bump PRs for the three pinned dependencies whose upstream is a
GitHub repo:

| Dep | Datasource | Filter |
| --- | --- | --- |
| openssl | `openssl/openssl` GitHub tags | `openssl-3.x.y` |
| zlib | `madler/zlib` GitHub tags | `v1.x.y` |
| libffi | `libffi/libffi` GitHub releases | `v3.x.y` |

When Renovate opens a bump PR, it rewrites the `<dep>-version` pin and
runs `MagPython/update-<dep>.sh <newVersion>` as a `postUpgradeTask`.
That script downloads the new tarball, computes the SHA-256, and
rewrites `<dep>-sha256` (and, for libffi, also regenerates
`MagPython/libffi-msvc-include/ffi.h` from upstream's template). All
three modified files end up in Renovate's PR commit.

The other three pinned deps stay manually-bumped because their
upstream isn't tracked by Renovate-supported datasources:

- **sqlite** — sqlite.org's URL embeds a calendar-year segment that
  isn't derivable from the version (see "Updating pinned SQLite"
  above). Bump via `MagPython/update-sqlite.sh <version> <year>`.
- **libmpdec** — bytereef.org has no Renovate-trackable release
  feed. Bump via `MagPython/update-libmpdec.sh <version>`.
- **NASM, jom** — build tools, rarely updated; bump via
  `MagPython/update-nasm.sh <version>` / `MagPython/update-jom.sh
  <version>` when you want to.

### Self-host requirement for `postUpgradeTasks`

Renovate's hosted (Mend) bot disables `postUpgradeTasks` by default
on its public app — running arbitrary commands per PR is a privilege
the cloud bot doesn't grant without explicit allowlist configuration.
If this repo is using the public Mend Renovate, the version-pin update
will land but the SHA-256 (and, for libffi, `ffi.h`) won't auto-refresh
— CI will fail loudly with a clear "SHA-256 mismatch" error. Two
recovery paths:

1. **Self-host Renovate** in this repo's CI (an `.github/workflows/
   renovate.yml` that runs the official renovate-action) and grant
   it the right permissions; `postUpgradeTasks` then works.
2. **Fix up Renovate's PR by hand** — fetch the branch, run
   `MagPython/update-<dep>.sh <newVersion>`, push. The two extra
   files land as a follow-up commit.

Either way, the in-tree pin is the source of truth and CI's hash
check protects against a stale SHA being merged.

## Licensing

The vendored sources keep their upstream licenses:

- CPython — PSF License (`Python/LICENSE`)
- OpenSSL — Apache-2.0 license (downloaded at build time; license ships in the upstream tarball)
- zlib — zlib license (downloaded at build time; license ships in the upstream tarball)
- libffi — MIT (downloaded at build time; license ships in the upstream tarball)
- SQLite — public domain
