# magnolia-python

A custom build of CPython 3.12.2 for 32-bit Windows that packages the
interpreter, the standard library extension modules, and the supporting
crypto/compression/database libraries into a single `MagPython.dll`. It is
intended for embedding Python into a host application rather than as a
standalone Python distribution.

## What's in here

| Path | Contents |
| --- | --- |
| `Python/` | Vendored CPython 3.12.2 source tree (upstream `python/cpython`). |
| `openssl/` | Vendored OpenSSL 1.1.1j source. |
| `zlib/` | Vendored zlib 1.3.1 source. |
| `libffi/` | Vendored libffi 3.4.5 source (used by `_ctypes`). |
| `sqlite/` | Vendored SQLite 3.45.1 amalgamation (`sqlite3.c` + headers). |
| `MagPython/` | All of the project's own build glue: MSBuild projects, props, the smoke test, and a few helper scripts. |
| `.github/workflows/Build All.yml` | CI that builds and uploads the artifact. |

The vendored library directories are the upstream sources, used as-is; all of
the project-specific build configuration lives under `MagPython/`.

## Build outputs

The build produces a self-contained drop with this layout (delivered as
`MagPython.zip` from CI):

```
MagPython/
  MagPython.dll          # Python core + builtin modules + zlib + sqlite + libffi
  libcrypto-1_1.dll      # OpenSSL
  libssl-1_1.dll         # OpenSSL
  include/Python/...     # Public + cpython + internal headers, plus PC/pyconfig.h
  lib/...                # Pure-Python stdlib (.py files copied from Python/Lib)
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

## Building locally

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

## Continuous integration

`.github/workflows/Build All.yml` runs on `windows-2022`:

- Triggers: pushes to `main`, PRs to `main`, a weekly schedule (Mondays
  06:00 UTC, added to catch silent breakages), and `workflow_dispatch`.
- Concurrency-grouped per `github.ref` with cancel-in-progress.
- Sets up the MSVC x86 environment via `ilammy/msvc-dev-cmd@v1`.
- Runs the `msbuild` command above, packages `MagPython\Release` as
  `MagPython.zip`, and uploads it as the `build-artifacts` artifact with
  7-day retention.

`.github/dependabot.yaml` keeps the GitHub Actions versions current on a
monthly cadence.

## Licensing

The vendored sources keep their upstream licenses:

- CPython — PSF License (`Python/LICENSE`)
- OpenSSL 1.1.1j — dual OpenSSL/SSLeay license (`openssl/LICENSE`)
- zlib — zlib license (`zlib/README`)
- libffi — MIT (`libffi/LICENSE`)
- SQLite — public domain
