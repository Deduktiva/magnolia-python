# MagPython features

Embeddable build of CPython 3.13.13 packaged as a single shared library plus
the OpenSSL DLLs and the pure-Python stdlib. zlib, libffi, sqlite, and
libmpdec are linked statically into the main library.

## Platforms

| Platform     | Artifact                    | Main library          |
| ---          | ---                         | ---                   |
| Windows x86  | `MagPython-windows-x86.zip` | `MagPython.dll`       |
| Linux x86_64 | `MagPython-linux-x86_64.zip`| `libMagPython.so`     |
| macOS arm64  | `MagPython-macos-arm64.zip` | `libMagPython.dylib`  |

Each zip contains the main lib, OpenSSL libs, headers under
`include/Python/`, the pure-Python stdlib under `lib/python3.13/` (or
`lib/` on Windows), and license files under `licenses/`.

## Pinned third-party libraries

| Library  | Linkage                    | Notes |
| ---      | ---                        | --- |
| OpenSSL  | shared (libcrypto, libssl) | trimmed Configure flag set |
| zlib     | static                     | |
| libffi   | static                     | backs `_ctypes` |
| SQLite   | static                     | backs `_sqlite3` |
| libmpdec | static                     | backs `_decimal` |

Versions are pinned in `MagPython/<dep>-version` and SHA-256 in
`MagPython/<dep>-sha256`; see `README.md` for bump procedures.

## Native (C) modules included

All three platforms ship the same module surface (modulo `_winapi`,
Windows-only).

Core / runtime: `_abc`, `_codecs`, `_collections`, `_contextvars`,
`_functools`, `_io`, `_locale`, `_opcode`, `_operator`, `_signal`,
`_sre`, `_stat`, `_string`, `_suggestions`, `_symtable`, `_sysconfig`,
`_thread`, `_tracemalloc`, `_typing`, `_warnings`, `_weakref`, `atexit`,
`builtins`, `errno`, `faulthandler`, `gc`, `itertools`, `marshal`,
`posix` (Unix) / `nt` (Windows), `sys`, `time`, `xxsubtype`.

Data / numerics: `_bisect`, `_csv`, `_datetime`, `_decimal` (libmpdec),
`_heapq`, `_json`, `_lsprof`, `_pickle`, `_random`, `_statistics`,
`_struct`, `array`, `binascii`, `cmath`, `math`, `mmap`,
`unicodedata`.

Crypto / hashing: `_blake2`, `_hashlib` (OpenSSL), `_md5`, `_sha1`,
`_sha2`, `_sha3`, `_ssl` (OpenSSL).

Networking / IO: `_socket`, `select`.

FFI / DB / compression: `_ctypes` (libffi), `_sqlite3` (sqlite),
`zlib`.

CJK codecs: `_codecs_cn`, `_codecs_hk`, `_codecs_iso2022`,
`_codecs_jp`, `_codecs_kr`, `_codecs_tw`, `_multibytecodec`.

Subinterpreters: `_interpreters`, `_interpchannels`, `_interpqueues`.

Windows-only: `_winapi`.

## Stdlib modules deliberately omitted

Not built into the library, so any pure-Python stdlib that `import`s
them will fail (canonical list: `MagPython/Setup.local`):

`_asyncio`, `_bz2`, `_crypt`, `_curses`, `_curses_panel`, `_dbm`,
`_elementtree`, `_gdbm`, `_lzma`, `_multiprocessing`, `_posixshmem`,
`_queue`, `_scproxy`, `_testbuffer`, `_testcapi`, `_testclinic`,
`_testimportmultiple`, `_testinternalcapi`, `_testmultiphase`,
`_testsinglephase`, `_tkinter`, `_uuid`, `_xxtestfuzz`, `_zoneinfo`,
`nis`, `ossaudiodev`, `pyexpat`, `readline`, `spwd`, `xxlimited`,
`xxlimited_35`.

User-visible consequences include: no `asyncio`, `bz2`, `lzma`,
`multiprocessing`, `queue`, `tkinter`, `uuid` (the C accelerator;
the pure-Python parts of `uuid` still import), `zoneinfo`, `dbm`,
`curses`, `xml.etree` (no `pyexpat`).

## Notes for embedders

- Windows: single `MagPython.dll`, no separate `.pyd` files; no
  console subsystem; no manifest. x86 only, `v142` toolset, Windows
  8.1 baseline (`Py_WINVER = 0x0603`).
- Linux: `SONAME=libMagPython.so`, `RUNPATH=$ORIGIN`. glibc 2.28
  baseline (manylinux_2_28).
- macOS: `install_name=@rpath/libMagPython.dylib`; OpenSSL
  `LC_LOAD_DYLIB` and `LC_RPATH` rewritten to `@rpath/...`.
- The stdlib must be present on disk at the path Python's discovery
  expects (`lib/python3.13/os.py` on Unix, `lib/os.py` on Windows).
- `lib-dynload/` ships empty — there are no loadable extension
  modules; everything is statically linked.
