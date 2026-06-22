#include <Python/Python.h>
#include <openssl/opensslv.h>
#include <openssl/crypto.h>
#include <openssl/ssl.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#ifdef _WIN32
#  include <windows.h>
#else
#  include <dlfcn.h>
#  include <limits.h>
#endif
#ifdef __APPLE__
#  include <mach-o/dyld.h>
#endif

#ifdef _WIN32
#  define PATH_SEP '\\'
#else
#  define PATH_SEP '/'
#endif

static int try_import(const char *module) {
    PyObject *m = PyImport_ImportModule(module);
    if (m == NULL) {
        PyErr_Print();
        fprintf(stderr, "  %s FAILED\n", module);
        return -1;
    }
    printf("  %s OK\n", module);
    Py_DECREF(m);
    return 0;
}

// Resolve the directory containing this executable. Used by the OpenSSL
// path-of-loaded-lib check below to verify libcrypto was loaded from the
// artifact's own dir (where build-{linux,macos}.sh / test.vcxproj stage
// it) rather than a same-version copy elsewhere on the system.
static int get_exe_dir(char *out, size_t out_size) {
    char path[4096];
#ifdef _WIN32
    DWORD n = GetModuleFileNameA(NULL, path, (DWORD)sizeof(path));
    if (n == 0 || n >= sizeof(path)) return -1;
#elif defined(__APPLE__)
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) return -1;
    char resolved[4096];
    if (realpath(path, resolved) == NULL) return -1;
    if (strlen(resolved) >= sizeof(path)) return -1;
    strcpy(path, resolved);
#else
    ssize_t n = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (n <= 0 || (size_t)n >= sizeof(path)) return -1;
    path[n] = '\0';
#endif
    char *slash = strrchr(path, PATH_SEP);
    if (slash == NULL) return -1;
    *slash = '\0';
    if (strlen(path) + 1 > out_size) return -1;
    strcpy(out, path);
    return 0;
}

// Resolve the absolute path of the shared library that owns `addr`. On
// POSIX this is dladdr -> dli_fname (canonicalized via realpath because
// dladdr can return the lookup name rather than the loaded path); on
// Windows it's GetModuleHandleEx(FROM_ADDRESS) -> GetModuleFileName.
static int get_lib_path_for(void *addr, char *out, size_t out_size) {
#ifdef _WIN32
    HMODULE h;
    if (!GetModuleHandleExA(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            (LPCSTR)addr, &h)) {
        return -1;
    }
    DWORD n = GetModuleFileNameA(h, out, (DWORD)out_size);
    if (n == 0 || n >= out_size) return -1;
    return 0;
#else
    Dl_info info;
    if (dladdr(addr, &info) == 0 || info.dli_fname == NULL) return -1;
    char resolved[4096];
    if (realpath(info.dli_fname, resolved) == NULL) return -1;
    if (strlen(resolved) + 1 > out_size) return -1;
    strcpy(out, resolved);
    return 0;
#endif
}

// Exercise OpenSSL directly (not just through Python's _ssl) so the artifact
// is validated as a usable OpenSSL SDK: the headers must be present at
// compile time, the libcrypto/libssl import lib (Windows) or unversioned
// symlink (Linux/macOS) must be present at link time, and the shared lib
// must resolve at runtime via the artifact's rpath.
//
// Two consistency checks: the header's compile-time version must equal
// libcrypto's runtime version (catches a header/lib version skew), and
// the loaded libcrypto must live in the same directory as this binary
// (catches a system libcrypto.<so|dylib|dll> with a matching version
// being picked up via LD_LIBRARY_PATH / DYLD_LIBRARY_PATH / PATH ahead
// of the artifact's $ORIGIN / @loader_path / DLL search dir). The path
// check is what makes the openssl validation robust to a system shipping
// the same OpenSSL version as our pin - version-string match alone can't
// distinguish "loaded ours" from "loaded system's".
static int exercise_openssl(void) {
    const char *header_ver = OPENSSL_VERSION_TEXT;
    const char *runtime_ver = OpenSSL_version(OPENSSL_VERSION);
    printf("  OpenSSL header:  %s\n", header_ver);
    printf("  OpenSSL runtime: %s\n", runtime_ver);
    if (strcmp(header_ver, runtime_ver) != 0) {
        fprintf(stderr, "  OpenSSL header/runtime version mismatch\n");
        return -1;
    }

    char exe_dir[4096], lib_path[4096];
    if (get_exe_dir(exe_dir, sizeof(exe_dir)) != 0) {
        fprintf(stderr, "  failed to resolve test binary directory\n");
        return -1;
    }
    // OpenSSL_version_num lives in libcrypto, so its load address
    // identifies which libcrypto was actually mapped into the process.
    if (get_lib_path_for((void *)(uintptr_t)OpenSSL_version_num,
                         lib_path, sizeof(lib_path)) != 0) {
        fprintf(stderr, "  failed to resolve loaded libcrypto path\n");
        return -1;
    }
    char *slash = strrchr(lib_path, PATH_SEP);
    if (slash == NULL) {
        fprintf(stderr, "  unexpected libcrypto path: %s\n", lib_path);
        return -1;
    }
    *slash = '\0';
    if (strcmp(exe_dir, lib_path) != 0) {
        fprintf(stderr,
                "  libcrypto loaded from %s, expected %s (same dir as test exe)\n",
                lib_path, exe_dir);
        return -1;
    }
    *slash = PATH_SEP;
    printf("  OpenSSL loaded from: %s\n", lib_path);

    if (OPENSSL_init_ssl(0, NULL) != 1) {
        fprintf(stderr, "  OPENSSL_init_ssl FAILED\n");
        return -1;
    }
    printf("  OpenSSL init OK\n");
    return 0;
}

int main(int argc, char *argv[]) {
    printf("MagPython smoke test\n");
    // Flush before Py_Initialize so our banner doesn't get interleaved
    // with Python's own writes to stdout/stderr after it takes over.
    fflush(stdout);
    fflush(stderr);

    // Set program_name to argv[0] so Py_Initialize's path discovery walks
    // up from this executable's directory looking for lib/pythonX.Y/os.py
    // (the Unix landmark) instead of falling back to PATH lookup of
    // "python3" (which would resolve to a system interpreter and use
    // its prefix). On Windows GetModuleFileName already supplies the
    // exe path, so this is a no-op there.
    PyConfig config;
    PyConfig_InitPythonConfig(&config);
    PyStatus status = PyConfig_SetBytesString(&config, &config.program_name, argv[0]);
    if (PyStatus_Exception(status)) {
        PyConfig_Clear(&config);
        Py_ExitStatusException(status);
    }
    status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) {
        Py_ExitStatusException(status);
    }

    printf("Compiler: %s\n", Py_GetCompiler());

    int rc = PyRun_SimpleString(
        "import sys; sys.stdout.write('Hi from MagPython!\\nsys.path: %r\\n' % sys.path)");
    if (rc != 0) {
        return 1;
    }

    int failures = 0;
    printf("Exercising OpenSSL:\n");
    failures += exercise_openssl() != 0;

    printf("Importing modules:\n");
    failures += try_import("decimal") != 0;
    failures += try_import("ssl") != 0;
    failures += try_import("ctypes") != 0;
    failures += try_import("hashlib") != 0;
    failures += try_import("sqlite3") != 0;

    // Exercise each module a little to make sure the C extensions
    // actually load and not just the Python wrappers. The crypto block
    // generates 32 bytes of secret material via libcrypto's RAND, then
    // uses it as an HMAC key and as PBKDF2/scrypt salt - that path
    // touches RAND, EVP digest, HMAC, PKCS5_PBKDF2_HMAC, and
    // EVP_PBE_scrypt, which is most of the surface CPython's
    // _hashopenssl wraps. The TLS block sanity-checks libssl's cipher
    // list and an in-process MemoryBIO TLS handshake (no network).
    rc = PyRun_SimpleString(
        "import decimal, ssl, ctypes, ctypes.util, hashlib, hmac, secrets, sqlite3\n"
        "\n"
        "assert decimal.Decimal('1.1') + decimal.Decimal('2.2') == decimal.Decimal('3.3'), 'decimal arithmetic'\n"
        "print('  ctypes find_library(c):', ctypes.util.find_library('c'))\n"
        "print('  ctypes sizeof(c_int):', ctypes.sizeof(ctypes.c_int))\n"
        "\n"
        "# Generate a 256-bit secret via libcrypto's RAND, then exercise\n"
        "# the symmetric-crypto pipeline against it.\n"
        "key = secrets.token_bytes(32)\n"
        "assert len(key) == 32 and key != b'\\x00' * 32, 'RAND_bytes'\n"
        "print('  secrets.token_bytes(32):', key.hex()[:16] + '...')\n"
        "\n"
        "digest = hashlib.sha256(key).hexdigest()\n"
        "assert len(digest) == 64, 'sha256'\n"
        "print('  sha256(key):', digest[:16] + '...')\n"
        "\n"
        "mac = hmac.new(key, b'magpython', hashlib.sha256).hexdigest()\n"
        "assert len(mac) == 64, 'hmac-sha256'\n"
        "print('  hmac-sha256:', mac[:16] + '...')\n"
        "\n"
        "kdf = hashlib.pbkdf2_hmac('sha256', b'password', key, 1000, 32)\n"
        "assert len(kdf) == 32, 'pbkdf2'\n"
        "print('  pbkdf2-hmac-sha256:', kdf.hex()[:16] + '...')\n"
        "\n"
        "sc = hashlib.scrypt(b'password', salt=key, n=2, r=8, p=1, dklen=32)\n"
        "assert len(sc) == 32, 'scrypt'\n"
        "print('  scrypt:', sc.hex()[:16] + '...')\n"
        "\n"
        "ctx = ssl.create_default_context()\n"
        "assert ctx.protocol is not None, 'ssl context'\n"
        "ciphers = ctx.get_ciphers()\n"
        "assert ciphers, 'TLS cipher list empty'\n"
        "print('  ssl OPENSSL_VERSION:', ssl.OPENSSL_VERSION)\n"
        "print('  ssl ciphers:', len(ciphers), 'available')\n"
        "\n"
        "# In-process TLS handshake via MemoryBIO. We expect it to fail\n"
        "# because we haven't loaded a server cert, but the failure must\n"
        "# come from the certificate-required check, not from libssl\n"
        "# itself misbehaving - proves the handshake state machine runs.\n"
        "client = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)\n"
        "client.check_hostname = False\n"
        "client.verify_mode = ssl.CERT_NONE\n"
        "in_bio, out_bio = ssl.MemoryBIO(), ssl.MemoryBIO()\n"
        "sock = client.wrap_bio(in_bio, out_bio, server_hostname='example.invalid')\n"
        "try: sock.do_handshake()\n"
        "except ssl.SSLWantReadError: pass\n"
        "assert out_bio.pending > 0, 'libssl produced no ClientHello bytes'\n"
        "print('  TLS ClientHello bytes:', out_bio.pending)\n"
        "\n"
        "# Verify the C extensions backed by our pinned deps are actually\n"
        "# built into libMagPython rather than loaded from a system\n"
        "# .so/.pyd. __spec__.origin == 'built-in' iff the module was\n"
        "# registered via _PyImport_Inittab (which the project does from\n"
        "# MagPython-config.c on Windows and from a flipped Setup.stdlib\n"
        "# + Setup.local on Unix). Together with the linkage of libmpdec.a\n"
        "# / libz.a / libffi.a (Linux) into libMagPython and the sibling\n"
        "# libsqlite3 / libffi (macOS-system) loaded from @rpath, this is\n"
        "# what guarantees we're using OUR pinned dep at runtime - a\n"
        "# version-string match could be a coincidence if the host happens\n"
        "# to ship the same upstream version.\n"
        "import _sqlite3, _decimal, _ctypes, _ssl, _hashlib, zlib\n"
        "for _mod in (_sqlite3, _decimal, zlib, _ctypes, _ssl, _hashlib):\n"
        "    _origin = _mod.__spec__.origin\n"
        "    assert _origin == 'built-in', \\\n"
        "        f'{_mod.__name__} is not built-in (origin={_origin!r}); a non-pinned copy may have been loaded'\n"
        "print('  built-in C extensions verified: _sqlite3, _decimal, zlib, _ctypes, _ssl, _hashlib')\n"
        "\n"
        "# Exercise the bundled SQLite via the _sqlite3 C extension: open\n"
        "# an in-memory DB, run DDL/DML with parameter binding, commit a\n"
        "# transaction, and read it back through an aggregate. Touches the\n"
        "# prepare/bind/step/finalize path plus the type adapters.\n"
        "print('  sqlite3 sqlite_version:', sqlite3.sqlite_version)\n"
        "con = sqlite3.connect(':memory:')\n"
        "con.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, n REAL)')\n"
        "con.executemany('INSERT INTO t (name, n) VALUES (?, ?)',\n"
        "                [('alpha', 1.5), ('beta', 2.5), ('gamma', 4.0)])\n"
        "con.commit()\n"
        "rows = con.execute('SELECT name, n FROM t ORDER BY id').fetchall()\n"
        "assert rows == [('alpha', 1.5), ('beta', 2.5), ('gamma', 4.0)], rows\n"
        "(total,) = con.execute('SELECT SUM(n) FROM t').fetchone()\n"
        "assert total == 8.0, total\n"
        "con.close()\n"
        "print('  sqlite3 rows:', len(rows), 'sum:', total)\n");
    if (rc != 0) {
        failures += 1;
    }

    if (failures != 0) {
        fprintf(stderr, "%d smoke test failure(s)\n", failures);
        return 1;
    }
    return 0;
}
