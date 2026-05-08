#include <Python/Python.h>
#include <stdio.h>

static int try_import(const char *module) {
    char buf[256];
    snprintf(buf, sizeof(buf),
             "import %s; print('  %s OK:', %s)",
             module, module, module);
    int rc = PyRun_SimpleString(buf);
    if (rc != 0) {
        fprintf(stderr, "  %s FAILED\n", module);
    }
    return rc;
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
    printf("Importing modules:\n");
    failures += try_import("decimal") != 0;
    failures += try_import("ssl") != 0;
    failures += try_import("ctypes") != 0;

    // Exercise each module a little to make sure the C extensions
    // actually load and not just the Python wrappers.
    rc = PyRun_SimpleString(
        "import decimal, ssl, ctypes, ctypes.util\n"
        "assert decimal.Decimal('1.1') + decimal.Decimal('2.2') == decimal.Decimal('3.3'), 'decimal arithmetic'\n"
        "ctx = ssl.create_default_context()\n"
        "assert ctx.protocol is not None, 'ssl context'\n"
        "print('  ssl OPENSSL_VERSION:', ssl.OPENSSL_VERSION)\n"
        "print('  ctypes find_library(c):', ctypes.util.find_library('c'))\n"
        "print('  ctypes sizeof(c_int):', ctypes.sizeof(ctypes.c_int))\n");
    if (rc != 0) {
        failures += 1;
    }

    if (failures != 0) {
        fprintf(stderr, "%d smoke test failure(s)\n", failures);
        return 1;
    }
    return 0;
}
