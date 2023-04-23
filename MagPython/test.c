#include <Python/python.h>
#include <stdio.h>

int main(int argc, char *argv[]) {
    printf("MagPython smoke test\n");
    Py_Initialize();
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
