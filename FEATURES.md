# MagPython features

Embeddable build of CPython 3.13.13 packaged as a single shared library plus
the OpenSSL DLLs and the pure-Python stdlib. zlib and libmpdec are linked
statically into the main library on every platform; libffi is statically
linked on Windows/Linux and used from the SDK on macOS; sqlite ships as a
sibling shared lib on Linux/macOS and statically on Windows; ncurses is
linked statically into the POSIX builds (the Windows artifact ships no
curses module).

Linux, macOS, and **windows-x64** additionally bundle **Qt6 qtbase Core**
and **PySide6 Core**, built from source against this CPython so
`import PySide6.QtCore` works without `pip install`. windows-x86 ships
no PySide6 (Qt 6 has no 32-bit Windows port). The bundled PySide6 on
windows-x64 is linked directly against `MagPython.lib`, so the
generated `.pyd` files record `MagPython.dll` in their PE import
table; no `python3.dll` forwarder is shipped.

## Platforms

| Platform     | Artifact                    | Main library          |
| ---          | ---                         | ---                   |
| Windows x86  | `MagPython-windows-x86.zip` | `MagPython.dll`       |
| Windows x64  | `MagPython-windows-x64.zip` | `MagPython.dll`       |
| Linux x86_64 | `MagPython-linux-x86_64.zip`| `libMagPython.so`     |
| macOS arm64  | `MagPython-macos-arm64.zip` | `libMagPython.dylib`  |

Each zip contains the main lib, OpenSSL libs, headers under
`include/Python/`, the pure-Python stdlib under `lib/python3.13/` (or
`lib/` on Windows), and license files under `licenses/`.

## Pinned third-party libraries

| Library  | Linkage                                                | Notes |
| ---      | ---                                                    | --- |
| OpenSSL  | shared (libcrypto, libssl)                             | trimmed Configure flag set |
| zlib     | static                                                 | |
| libffi   | static (Windows, Linux); SDK system libffi (macOS)     | backs `_ctypes` |
| SQLite   | shared sibling (Linux, macOS); static (Windows)        | backs `_sqlite3` |
| libmpdec | static                                                 | backs `_decimal` |
| ncurses  | static                                                 | backs `_curses` / `_curses_panel`, POSIX only |
| Qt6      | shared sibling (libQt6Core)                            | qtbase Core only, POSIX only |
| PySide6  | shared siblings (libshiboken6, libpyside6) + abi3 module | Core module only, POSIX only |

Versions are pinned in `MagPython/<dep>-version` and SHA-256 in
`MagPython/<dep>-sha256`; see `README.md` for bump procedures.

## Native (C) modules included

All three platforms ship the same module surface (modulo `_winapi`,
Windows-only).

Core / runtime: `_abc`, `_asyncio`, `_codecs`, `_collections`,
`_contextvars`, `_functools`, `_io`, `_locale`, `_opcode`, `_operator`,
`_queue`, `_signal`, `_sre`, `_stat`, `_string`, `_suggestions`,
`_symtable`, `_sysconfig`, `_thread`, `_tracemalloc`, `_typing`,
`_warnings`, `_weakref`, `atexit`, `builtins`, `errno`, `faulthandler`,
`gc`, `itertools`, `marshal`, `posix` (Unix) / `nt` (Windows), `sys`,
`time`, `xxsubtype`.

Data / numerics: `_bisect`, `_csv`, `_datetime`, `_decimal` (libmpdec),
`_heapq`, `_json`, `_lsprof`, `_pickle`, `_random`, `_statistics`,
`_struct`, `array`, `binascii`, `cmath`, `math`, `mmap`,
`unicodedata`.

Crypto / hashing: `_blake2`, `_hashlib` (OpenSSL), `_md5`, `_sha1`,
`_sha2`, `_sha3`, `_ssl` (OpenSSL).

Networking / IO: `_socket`, `select`.

FFI / DB / compression: `_ctypes` (libffi), `_sqlite3` (sqlite),
`zlib`.

Terminal (POSIX only): `_curses` (ncurses), `_curses_panel` (ncurses).

CJK codecs: `_codecs_cn`, `_codecs_hk`, `_codecs_iso2022`,
`_codecs_jp`, `_codecs_kr`, `_codecs_tw`, `_multibytecodec`.

Subinterpreters: `_interpreters`, `_interpchannels`, `_interpqueues`.

Windows-only: `_winapi`.

## Stdlib modules deliberately omitted

Not built into the library, so any pure-Python stdlib that `import`s
them will fail (canonical list: `MagPython/Setup.local`):

`_bz2`, `_crypt`, `_dbm`, `_elementtree`, `_gdbm`, `_lzma`,
`_multiprocessing`, `_posixshmem`, `_scproxy`, `_testbuffer`,
`_testcapi`, `_testclinic`, `_testimportmultiple`,
`_testinternalcapi`, `_testmultiphase`, `_testsinglephase`,
`_tkinter`, `_uuid`, `_xxtestfuzz`, `_zoneinfo`, `nis`, `ossaudiodev`,
`pyexpat`, `readline`, `spwd`, `xxlimited`, `xxlimited_35`.

User-visible consequences include: no `bz2`, `lzma`,
`multiprocessing`, `tkinter`, `uuid` (the C accelerator;
the pure-Python parts of `uuid` still import), `zoneinfo`, `dbm`,
`xml.etree` (no `pyexpat`). `curses` is POSIX-only — Windows ships
no `_curses` (CPython upstream relies on the `windows-curses` PyPI
shim there), so a host application targeting all three platforms
should treat `curses` as Linux/macOS only.

## Notes for embedders

- Windows: single `MagPython.dll`, no separate per-module `.pyd` files
  for the stdlib (those C extensions are statically linked into the
  main DLL). The bundled PySide6 `.pyd` files on x64 (and any extension
  a downstream builds against this SDK) link directly against
  `MagPython.lib`, so their PE import tables name `MagPython.dll` — no
  `python3.dll` forwarder is shipped, and pre-built abi3 wheels from
  PyPI (linked against upstream's `python3.lib`) are NOT supported. No
  console subsystem; no manifest. Built for both x86 (Win32) and x64
  (AMD64), `v142` toolset, Windows 8.1 baseline (`Py_WINVER = 0x0603`).
- Linux: `SONAME=libMagPython.so`, `RUNPATH=$ORIGIN`. glibc 2.28
  baseline (manylinux_2_28). `libpython3.13.so.1.0`,
  `libpython3.13.so`, `libpython3.so` are symlinks onto
  `libMagPython.so` so abi3 / stable-ABI extension modules with
  `NEEDED=libpython*.so` resolve transparently.
- macOS: `install_name=@rpath/libMagPython.dylib`; OpenSSL
  `LC_LOAD_DYLIB` and `LC_RPATH` rewritten to `@rpath/...`.
  `libpython3.13.dylib` / `libpython3.dylib` symlinks point at
  `libMagPython.dylib` for the same abi3 reason as Linux.
- The stdlib must be present on disk at the path Python's discovery
  expects (`lib/python3.13/os.py` on Unix, `lib/os.py` on Windows).
- `lib-dynload/` ships empty — built-in extension modules are
  statically linked into `libMagPython`. Dynamic extension loading
  (HAVE_DYNAMIC_LOADING) is enabled on every platform, so externally-
  installed `.so` / `.dylib` / `.pyd` extensions load via the regular
  importlib path. On Linux/macOS this includes anything a downstream
  `pip install`s into a site-packages on `sys.path` (`libpython3.{so,
  dylib}` symlinks point at `libMagPython` so the abi3 `NEEDED` /
  `LC_LOAD_DYLIB` records resolve). On Windows there is no such
  symlink mechanism for DLLs — pip-installed abi3 wheels that
  reference `python3.dll` will NOT load, only the bundled PySide6
  and SDK-built extensions (which link against `MagPython.lib`
  directly) work.
- PySide6 / Qt6 (Linux, macOS, windows-x64 — NOT windows-x86): the
  artifact ships `Qt6Core`, `shiboken6`, `pyside6` (the `.so` /
  `.dylib` / `.dll` form per platform) next to the main library,
  and the PySide6 + shiboken6 Python packages under
  `site-packages/`. Downstream embedders should add
  `<artifact>/MagPython/site-packages` to `sys.path` (or
  `PYTHONPATH`) before importing PySide6. The Qt platform plugin
  defaults to none (no QtGui) — set `QT_QPA_PLATFORM=offscreen` if
  a future build pulls in QtGui without a display.
