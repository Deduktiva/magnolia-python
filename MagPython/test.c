#include <Python/Python.h>
#include <stdio.h>

int main(int argc, char *argv[]) {
    printf("MagPython smoke test\n");

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
    int success = PyRun_SimpleString("import sys; sys.stdout.write('Hi from MagPython!\\nsys.path: %r\\n' % sys.path)");
    if (success == 0)
    {
        return 0; // success
    } else
    {
        return 1; // unknown error;
    }
}
