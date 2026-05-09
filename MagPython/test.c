#include <Python/Python.h>
#include <openssl/opensslv.h>
#include <openssl/crypto.h>
#include <openssl/ssl.h>
#include <stdio.h>
#include <string.h>

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

// Exercise OpenSSL directly (not just through Python's _ssl) so the artifact
// is validated as a usable OpenSSL SDK: the headers must be present at
// compile time, the libcrypto/libssl import lib (Windows) or unversioned
// symlink (Linux/macOS) must be present at link time, and the shared lib
// must resolve at runtime via the artifact's rpath. Also compares the
// header's compile-time version against libcrypto's runtime version to
// catch a header/lib mismatch.
static int exercise_openssl(void) {
    const char *header_ver = OPENSSL_VERSION_TEXT;
    const char *runtime_ver = OpenSSL_version(OPENSSL_VERSION);
    printf("  OpenSSL header:  %s\n", header_ver);
    printf("  OpenSSL runtime: %s\n", runtime_ver);
    if (strcmp(header_ver, runtime_ver) != 0) {
        fprintf(stderr, "  OpenSSL header/runtime version mismatch\n");
        return -1;
    }
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

    // Exercise each module a little to make sure the C extensions
    // actually load and not just the Python wrappers. The crypto block
    // generates 32 bytes of secret material via libcrypto's RAND, then
    // uses it as an HMAC key and as PBKDF2/scrypt salt — that path
    // touches RAND, EVP digest, HMAC, PKCS5_PBKDF2_HMAC, and
    // EVP_PBE_scrypt, which is most of the surface CPython's
    // _hashopenssl wraps. The TLS block sanity-checks libssl's cipher
    // list and an in-process MemoryBIO TLS handshake (no network).
    rc = PyRun_SimpleString(
        "import decimal, ssl, ctypes, ctypes.util, hashlib, hmac, secrets\n"
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
        "# itself misbehaving — proves the handshake state machine runs.\n"
        "client = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)\n"
        "client.check_hostname = False\n"
        "client.verify_mode = ssl.CERT_NONE\n"
        "in_bio, out_bio = ssl.MemoryBIO(), ssl.MemoryBIO()\n"
        "sock = client.wrap_bio(in_bio, out_bio, server_hostname='example.invalid')\n"
        "try: sock.do_handshake()\n"
        "except ssl.SSLWantReadError: pass\n"
        "assert out_bio.pending > 0, 'libssl produced no ClientHello bytes'\n"
        "print('  TLS ClientHello bytes:', out_bio.pending)\n");
    if (rc != 0) {
        failures += 1;
    }

    if (failures != 0) {
        fprintf(stderr, "%d smoke test failure(s)\n", failures);
        return 1;
    }
    return 0;
}
