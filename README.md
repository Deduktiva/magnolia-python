# magnolia-python

A custom build of CPython 3.12.2 for embedding into a host application,
packaging the interpreter, the standard library extension modules, and the
supporting crypto/compression/database libraries into a single
shared library. Three platforms are produced from the same source tree:

| Platform        | Runner          | Main library             |
| ---             | ---             | ---                      |
| Windows x86     | `windows-2022`  | `MagPython.dll`          |
| Linux x86_64    | manylinux_2_28  | `libMagPython.so`        |
| macOS arm64     | `macos-14`      | `libMagPython.dylib`     |

## What's in here

| Path | Contents |
| --- | --- |
| `Python/` | Vendored CPython 3.12.2 source tree (upstream `python/cpython`). |
| `openssl/` | Vendored OpenSSL 1.1.1w source. |
| `zlib/` | Vendored zlib 1.3.2 source. |
| `libffi/` | Vendored libffi 3.5.2 source (used by `_ctypes`). |
| `sqlite/` | Vendored SQLite 3.53.1 amalgamation (`sqlite3.c` + headers). |
| `MagPython/` | All of the project's own build glue: MSBuild projects + `*.props` for Windows, `build-linux.sh` / `build-macos.sh` / `build-common.sh` for Unix, the shared smoke test (`test.c`), `Setup.local` (modules omitted from libMagPython on Unix to mirror MagPython.vcxproj), and helper scripts (`update-openssl.sh`, `update-zlib.sh`, `update-libffi.sh`, `update-sqlite.sh`, `download-nasm.ps1`). |
| `.github/workflows/Build All.yml` | CI that builds and uploads the artifact. |

The vendored library directories are the upstream sources, used as-is; all of
the project-specific build configuration lives under `MagPython/`.

## Build outputs

Each platform produces one zip with the same shape — a `MagPython/`
directory containing the main shared lib, the OpenSSL libs, the headers,
and the pure-Python stdlib. zlib, libffi, and sqlite are linked statically
into the main library on every platform.

Windows (`MagPython-windows-x86.zip`):

```
MagPython/
  MagPython.dll          # Python core + builtin modules + zlib + sqlite + libffi
  libcrypto-1_1.dll      # OpenSSL
  libssl-1_1.dll         # OpenSSL
  include/Python/...     # Public + cpython + internal headers, plus PC/pyconfig.h
  lib/...                # Pure-Python stdlib (.py files copied from Python/Lib)
```

Linux (`MagPython-linux-x86_64.zip`):

```
MagPython/
  libMagPython.so        # SONAME libMagPython.so, RUNPATH $ORIGIN
  libcrypto.so.1.1
  libssl.so.1.1
  include/Python/...
  lib/python3.12/        # stdlib at the path Python's Unix discovery
                         # looks for (lib/python<X.Y>/os.py)
  lib/python3.12/lib-dynload/   # empty (modules are statically linked)
```

macOS arm64 (`MagPython-macos-arm64.zip`):

```
MagPython/
  libMagPython.dylib     # install_name @rpath/libMagPython.dylib
  libcrypto.1.1.dylib    # install_name @rpath/libcrypto.1.1.dylib
  libssl.1.1.dylib       # install_name @rpath/libssl.1.1.dylib
  include/Python/...
  lib/python3.12/
  lib/python3.12/lib-dynload/
```

Notable differences from a stock CPython Windows build:

- A single `MagPython.dll` instead of `python312.dll` plus a forest of `.pyd`
  files. Modules that upstream ships as separate `.pyd`s (`_ssl`, `_socket`,
  `select`, `_sqlite3`, `unicodedata`, `_ctypes`, …) are linked directly into
  the DLL — see the `<ClCompile>` items in `MagPython/MagPython.vcxproj`.
- `SubSystem` is `Windows` (no console), `GenerateManifest` is off,
  `Py_BUILD_CORE_BUILTIN` is defined for everything in the DLL, and the link
  uses `version.lib;Crypt32.lib;winmm.lib;pathcch.lib;bcrypt.lib;ws2_32.lib;
  iphlpapi.lib;Rpcrt4.lib`.
- Targets `x86` only (the `Platform` defaults to `Win32` in
  `MagPython/common.props`); `PlatformToolset` is `v142` (VS 2019).
- Frozen modules and `Python/deepfreeze/deepfreeze.c` are regenerated as part
  of the build (see below) and are gitignored.

## How the build is wired

### Windows

`MagPython/MagPython.metaproj` is the top-level MSBuild project. It runs the
following sub-projects in order, each `BuildInParallel="True"
StopOnFirstFailure="True"`:

1. **`LibFFI.vcxproj`** — builds `libffi.lib` (static) from `libffi/src` for
   `X86_WIN32` using libffi's own pre-generated MSVC headers
   (`libffi/msvc_build/x86_win32/include`).
2. **`openssl.vcxproj`** — a `Makefile`-type project that runs
   `perl Configure VC-WIN32-ONECORE no-idea no-mdc2` and then
   `nmake -f openssl-makefile-faster prep build_libs` inside `openssl/`.
   The `download-nasm.ps1` target fetches NASM 2.16.01 from nasm.us before
   the build (NASM is required by OpenSSL's x86 assembly). The custom
   `openssl-makefile-faster` overrides OpenSSL's per-file compile rules to
   compile each `crypto/<dir>` in a single `cl.exe` invocation, which is
   substantially faster than the stock makefile. Outputs: `libcrypto-1_1.dll`,
   `libssl-1_1.dll`, import libs, `applink.c`, and the headers, all copied
   into `MagPython/Release/`.
3. **`FreezeMagPython.vcxproj`** — builds `FreezeMagPython.exe` from
   CPython's `Programs/_freeze_module.c`. After it builds, post-build targets
   re-freeze the Python modules listed in the project (importlib bootstrap,
   `os`, `site`, `runpy`, the `__phello__` modules, etc.) into
   `Python/Python/frozen_modules/*.h`, freeze `getpath.py` separately, and
   then call `Python/Tools/build/deepfreeze.py` (using a host Python found
   via `Python/PCbuild/find_python.bat`) to regenerate
   `Python/Python/deepfreeze/deepfreeze.c`. Both generated trees are
   gitignored. Note: the freezer binary is built but not shipped (commit
   `3afe7fc`).
4. **`MagPython.vcxproj`** — the main DLL. Compiles the Python core,
   `Objects/`, `Parser/`, selected `Modules/`, `PC/` glue, `zlib`, the
   amalgamated `sqlite3.c`, `_sqlite/*`, `_ssl`, `_hashopenssl`, `_socket`,
   `select`, `unicodedata`, and `_ctypes`. Links against the `libcrypto.lib`,
   `libssl.lib`, and `libffi.lib` produced by the earlier steps. The
   `CopyArtifacts` target then stages headers and the pure-Python stdlib
   into `Release/include/Python/` and `Release/lib/` so the output directory
   is a complete SDK drop.
5. **`test.vcxproj`** — compiles `MagPython/test.c` (a tiny embedding host
   that calls `Py_Initialize`, prints the compiler string, and runs an
   `import sys` line), copies the DLLs and `lib/` next to it, and **executes
   `test.exe`** as part of the build via an `<Exec>` task. A failed smoke
   test fails the build.

`MagPython/common.props` pins the defaults: `Platform=Win32`,
`Configuration=Release`, `PlatformToolset=v142`.

### Linux and macOS

`MagPython/build-linux.sh` and `MagPython/build-macos.sh` orchestrate the
Unix builds. Both source `MagPython/build-common.sh` and follow the same
five-stage shape as the Windows metaproj:

1. **Static deps** — `zlib/libz.a` (built with `CFLAGS=-fPIC`),
   `libffi/<host-triple>/.libs/libffi.a`, `build-out/sqlite/libsqlite3.a`.
   All three end up linked into the main library, mirroring the Windows
   configuration where their sources are compiled directly into
   `MagPython.dll`.
2. **OpenSSL** — `./Configure linux-x86_64` or `darwin64-arm64-cc`, then
   `make && make install_sw` into `build-out/openssl-out`. Produces
   `libcrypto.{so.1.1,1.1.dylib}` + `libssl.{so.1.1,1.1.dylib}`.
3. **Configure libpython** — out-of-tree configure in `build-out/main`
   with `--enable-shared --without-static-libpython
   --with-openssl=...build-out/openssl-out`, plus `LIBFFI_*`, `ZLIB_*`,
   and `LIBSQLITE3_*` env vars pointing at the static libs from stage 1.
4. **Regen frozen + deepfreeze, then make** — `make regen-frozen
   regen-deepfreeze` followed by an awk pass that rewrites
   `Modules/Setup.stdlib`: it flips `*shared*` to `*static*`, then
   comments out the lines for modules listed under `*disabled*` in
   `MagPython/Setup.local`. (The `*disabled*` directive on its own only
   affects runtime registration in `Modules/config.c` — to keep modules
   out of the build entirely we need to drop their stdlib lines.) This
   produces a libpython that contains the same module subset as
   `MagPython/MagPython.vcxproj` does on Windows.
5. **Rename, stage, smoke test, zip** — `libpython3.12.{so.1.0,dylib}` is
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

The host Python required by `regen-deepfreeze` is
`/opt/python/cp312-cp312/bin/python3` inside the manylinux_2_28 container
on Linux, and the `macos-14` runner's preinstalled `python3` on macOS.

## Building locally

### Windows

Requirements:

- Windows with Visual Studio 2019 build tools (MSVC v142, x86 cross tools,
  Windows 8.1 SDK baseline — see commit `1bbd920`).
- Perl in `PATH` (for OpenSSL `Configure`).
- A host Python in `PATH` or one discoverable by
  `Python/PCbuild/find_python.bat` (used by `deepfreeze.py`).
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

## Updating vendored OpenSSL

This project intentionally stays on the OpenSSL 1.1.1 branch (the API/ABI
matters for `_ssl` / `_hashopenssl` against this CPython, and the Windows
build glue under `MagPython/` is wired up for `libcrypto-1_1.dll` /
`libssl-1_1.dll`). The script `MagPython/update-openssl.sh` automates a
patch-level bump within that branch:

```sh
MagPython/update-openssl.sh 1.1.1w
```

It is a portable bash script (no bashisms beyond bash 3.2, so it works on
macOS as well as Linux). What it does:

1. Refuses any version that is not on the `1.1.1` branch — keeps us on the
   line where the build glue is known to work.
2. Downloads `openssl-<version>.tar.gz` and its `.sha256` from the GitHub
   release for the matching `OpenSSL_1_1_1<letter>` tag (with openssl.org's
   `/source/old/1.1.1/` as a fallback). Verifies the SHA-256 with `shasum`
   or `sha256sum`.
3. Replaces the contents of `openssl/` in place with the extracted tree.
   The OpenSSL tree has no project-local patches — all build customisation
   lives in `MagPython/openssl.vcxproj` and `MagPython/openssl-makefile-faster`
   — so a clean replacement is the correct strategy. Re-importing the
   currently-vendored version produces a byte-identical tree (`git status`
   shows no changes).
4. Reports drift between `MagPython/openssl-makefile-faster` and the new
   source tree:
   - **GONE** files (referenced by the faster makefile but missing from
     the new tree) are always reported and must be fixed — they will
     break the build.
   - **NEW** files: the script snapshots the previous tree's set of
     "in covered dirs but not listed" files before replacing, then
     subtracts that baseline from the post-replace report. So only files
     added *by this upgrade* in directories the makefile covers (≥50%
     coverage) surface; the standing exclusions (assembly-replaced
     variants, `no-mdc2`/`no-idea`, alt implementations like
     `crypto/sha/keccak1600.c`) stay quiet.

### What else changes on an OpenSSL bump?

For a patch-level bump *within* the 1.1.1 branch (the only kind of bump
this script supports), the **Windows build projects need no changes** —
they all key off the soname `1_1`, which is stable for the entire 1.1.x
line. Concretely:

- `MagPython/openssl.vcxproj` — `<LibraryFileVersion>1_1</LibraryFileVersion>`
  drives the `libcrypto-1_1.dll` / `libssl-1_1.dll` paths and stays as-is.
- `MagPython/MagPython.vcxproj` — links `libcrypto.lib` / `libssl.lib`
  (import-lib names stable).
- `MagPython/MagPython.metaproj`, `.github/workflows/Build All.yml`,
  `.gitignore` — contain no version-specific references.
- The `perl Configure VC-WIN32-ONECORE no-idea no-mdc2` invocation and
  the `MY_*` file lists in `MagPython/openssl-makefile-faster` are valid
  for any 1.1.1 release (the script verifies the latter on every run).

The only places that need a manual edit on a patch bump are the two
human-readable version strings in this file:

- The vendored-libraries table (`Vendored OpenSSL 1.1.1<letter> source.`)
- The Licensing section (`OpenSSL 1.1.1<letter> — dual …`)

After updating those two lines, run the full Windows build to confirm
the new tree compiles, then commit with a message like
`Import unpacked OpenSSL 1.1.1w`.

(A major version change — e.g. moving to OpenSSL 3.x — would also
require updating `<LibraryFileVersion>`, the `Configure` flags, and
likely the entire `openssl-makefile-faster` layout. The script refuses
non-1.1.1 versions for exactly this reason.)

## Updating vendored zlib

`MagPython/update-zlib.sh` is the analogous helper for the zlib tree:

```sh
MagPython/update-zlib.sh 1.3.1
```

Same shape as the OpenSSL script (bash 3.2, macOS-friendly), with two
notable differences in how it behaves:

1. Pinned to the zlib **1.x** line. A 2.x bump would warrant a manual
   review of the build glue, so the script refuses anything outside
   `1.*`.
2. zlib does not publish `.sha256` sidecars on its GitHub releases, so
   there is no upstream-anchored hash to verify against. The script
   trusts HTTPS to GitHub plus the immutability of release artifacts,
   and prints the SHA-256 of the downloaded tarball for the record
   (paste it into the commit message). If you want stronger assurance,
   GitHub does publish `.tar.gz.asc` GPG signatures from Mark Adler —
   verify out of band before running the script.

The drift detector compares the `$(zlibDir)\<name>.c` and
`$(zlibDir)\<name>.h` references in `MagPython/MagPython.vcxproj`
against the top-level files in the new tree, with the previous tree's
intentional exclusions (the `gz*` family — Python's `zlibmodule`
doesn't use them) subtracted as a baseline. As with OpenSSL, only drift
introduced by the current upgrade surfaces; **GONE** entries
(`<ClCompile>` references that no longer exist would break the build,
`<ClInclude>` ones rot the IDE view) are always reported regardless.

### What else changes on a zlib bump?

Unlike OpenSSL, zlib is statically linked into `MagPython.dll` rather
than shipped as its own DLL — there are no soname-bearing artifacts.
So a patch bump only touches:

- `MagPython/MagPython.vcxproj` — the `<ClCompile>` and `<ClInclude>`
  lists, *if and only if* the drift detector reports new files.
- The version string in the vendored-libraries table at the top of
  this README. (zlib's licensing line carries no version because the
  license terms are stable across the 1.x line, unlike OpenSSL.)

The `<zlibDir>` property and CI workflow have no version-specific
references and stay as-is.

## Updating vendored SQLite

`MagPython/update-sqlite.sh` is the analogous helper for the SQLite
amalgamation:

```sh
MagPython/update-sqlite.sh 3.45.1 2024
```

The second argument is the **calendar year** the release was
published — sqlite.org's download URLs embed the year and there is no
reliable way to derive it from the version alone. Look it up on
<https://sqlite.org/chronology.html> or in the release announcement.

What the script does, in the same shape as the OpenSSL/zlib helpers:

1. Refuses anything off the SQLite **3.x** line.
2. Downloads `sqlite-amalgamation-<NNNNNNN>.zip` from
   `https://sqlite.org/<year>/`, where `<NNNNNNN>` is the version
   encoded as `<major>*1000000 + <minor>*10000 + <patch>*100`
   (e.g. 3.45.1 → `3450100`). SQLite does not publish `.sha256`
   sidecars; the script trusts HTTPS to sqlite.org and prints the
   downloaded zip's SHA-256 for the record. The unpacked
   `sqlite3.h`'s embedded `SQLITE_VERSION` is also cross-checked
   against the requested version as a sanity guard.
3. Replaces the contents of `sqlite/` in place. The vendored tree is
   the upstream amalgamation as-is — four files: `sqlite3.c`,
   `sqlite3.h`, `sqlite3ext.h`, and `shell.c` (the SQLite CLI, which
   the build deliberately does not compile).
4. Reports drift between `MagPython/MagPython.vcxproj`'s
   `$(sqlite3Dir)\<name>.c|h` references and the new tree, with the
   previous tree's intentional exclusions (just `shell.c`) subtracted
   so each run only surfaces drift introduced by *this* upgrade.
   GONE entries (referenced files missing from the new tree) are
   always reported.

### What else changes on a SQLite bump?

SQLite is statically linked into `MagPython.dll` (not shipped as its
own DLL), so a patch bump only touches:

- `MagPython/MagPython.vcxproj` — the `<ClCompile>`/`<ClInclude>`
  lists, *if and only if* the drift detector reports new files.
- The version string in the vendored-libraries table at the top of
  this README. (The licensing line says "SQLite — public domain" and
  carries no version.)

`MagPython/sqlite3.vcxproj` exists in the tree but is not referenced
from `MagPython.metaproj` — the actual build pulls `sqlite3.c`
directly into `MagPython.vcxproj` via `$(sqlite3Dir)`. Either way,
neither file has a version-specific reference.

## Updating vendored libffi

`MagPython/update-libffi.sh` is the analogous helper for libffi:

```sh
MagPython/update-libffi.sh 3.5.2
```

Same overall shape as the OpenSSL/zlib/SQLite scripts (bash 3.2,
macOS-friendly, no upstream-anchored hash so just prints the SHA-256
of the downloaded tarball for the record), with one libffi-specific
twist around the pre-built MSVC headers.

### The msvc_build/x86_win32/include/ headers

Upstream libffi ships pre-generated MSVC headers only for `aarch64`
(under `msvc_build/aarch64/`); it has never published an x86 Windows
variant. Two files we need, `ffi.h` and `fficonfig.h`, therefore
have to live in the project's idea of `msvc_build/x86_win32/include/`.
The script handles them differently:

- **`ffi.h`** is regenerated on every run from upstream's
  `include/ffi.h.in` template via four `sed` substitutions
  (`@VERSION@` → the requested version, `@TARGET@` → `X86_WIN32`,
  `@HAVE_LONG_DOUBLE@` → `0`, `@FFI_EXEC_TRAMPOLINE_TABLE@` → `0`).
  No autoconf / configure required, and the file stays in sync with
  every libffi version automatically. The script aborts if upstream
  introduces a new `@VAR@` token it doesn't know how to substitute.

- **`fficonfig.h`** is autoheader output that depends on autoconf
  feature-detection results and would need a real `configure` run to
  regenerate honestly. The script preserves the previously-committed
  copy across upgrades. If upstream's `fficonfig.h.in` template
  changes between the previous and new libffi versions, the script
  warns loudly and prints the template diff so the project-local
  `fficonfig.h` can be regenerated by hand on a Linux/macOS host:

  ```sh
  cd <fresh libffi-X.Y.Z>
  ./configure --host=i686-w64-mingw32 --enable-static
  cp fficonfig.h <repo>/libffi/msvc_build/x86_win32/include/
  ```

### Drift detection

The script reports drift between `MagPython/LibFFI.vcxproj`'s
referenced `.c`/`.S`/`.h` files and the new tree across the four
directories the x86_win32 build cares about (`src/`, `src/x86/`,
`include/`, `msvc_build/x86_win32/include/`), with the previous
tree's intentional exclusions (the 64-bit assembly variants, the
GNU-asm `.S` files we don't use, raw/java/tramp APIs the project
doesn't enable, …) subtracted as a baseline. As elsewhere, GONE
entries (referenced files missing from the new tree) are always
reported.

### What else changes on a libffi bump?

For a patch-level bump within the same minor line, the only manual
step is the version string in the vendored-libraries table at the
top of this README. The `LibFFI.vcxproj` file lists are stable for
the libffi 3.x line as long as the drift detector reports nothing.

A minor bump may surface a non-empty template diff for
`fficonfig.h.in` — review it and decide whether the project-local
`fficonfig.h` needs to be regenerated as described above.

## Continuous integration

`.github/workflows/Build All.yml` is a single matrix-based workflow that
fans out across three platforms:

- `windows-2022` (x86, MSVC) — runs the existing `msbuild MagPython.metaproj`
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

## Licensing

The vendored sources keep their upstream licenses:

- CPython — PSF License (`Python/LICENSE`)
- OpenSSL 1.1.1w — dual OpenSSL/SSLeay license (`openssl/LICENSE`)
- zlib — zlib license (`zlib/README`)
- libffi — MIT (`libffi/LICENSE`)
- SQLite — public domain
