/* Module configuration for MagPython.dll */

/* Project-local replacement for Python/PC/config.c (upstream's
   Windows static-builtin module table). This file is identical to
   the upstream config.c at the corresponding Python version, plus
   one block of additions: the C extensions that this project
   *statically* links into MagPython.dll (rather than dlopen()-ing
   them as separate .pyd files like a stock CPython Windows build).
   Those extensions need _PyImport_Inittab entries so that
   `import _ssl`, `import _ctypes`, etc. find them — without these,
   builtin lookup misses and the import machinery falls through to
   dynamic loading, which the project deliberately disables (see
   the HAVE_DYNAMIC_LOADING comment-out applied to PC/pyconfig.h.in
   by GenerateMagPythonConfigH in magpython-pyconfig-h.targets).

   We compile this file in lieu of $(PythonSourceDir)\PC\config.c
   (see MagPython.vcxproj) so the imported Python tree stays
   pristine. When upstream gains or loses a stock builtin between
   minor releases, this file needs to be re-synced — the diff
   against $(PythonSourceDir)\PC\config.c at upgrade time should
   be exactly the project-local block, nothing else. */

#include "Python.h"

extern PyObject* PyInit__abc(void);
extern PyObject* PyInit_array(void);
extern PyObject* PyInit_binascii(void);
extern PyObject* PyInit_cmath(void);
extern PyObject* PyInit_errno(void);
extern PyObject* PyInit_faulthandler(void);
extern PyObject* PyInit__tracemalloc(void);
extern PyObject* PyInit_gc(void);
extern PyObject* PyInit_math(void);
extern PyObject* PyInit__md5(void);
extern PyObject* PyInit_nt(void);
extern PyObject* PyInit__operator(void);
extern PyObject* PyInit__signal(void);
extern PyObject* PyInit__sha1(void);
extern PyObject* PyInit__sha2(void);
extern PyObject* PyInit__sha3(void);
extern PyObject* PyInit__statistics(void);
extern PyObject* PyInit__sysconfig(void);
extern PyObject* PyInit__typing(void);
extern PyObject* PyInit__blake2(void);
extern PyObject* PyInit_time(void);
extern PyObject* PyInit__thread(void);
#ifdef WIN32
extern PyObject* PyInit_msvcrt(void);
extern PyObject* PyInit__locale(void);
#endif
extern PyObject* PyInit__codecs(void);
extern PyObject* PyInit__weakref(void);
/* XXX: These two should really be extracted to standalone extensions. */
extern PyObject* PyInit_xxsubtype(void);
extern PyObject* PyInit__interpreters(void);
extern PyObject* PyInit__interpchannels(void);
extern PyObject* PyInit__interpqueues(void);
extern PyObject* PyInit__random(void);
extern PyObject* PyInit_itertools(void);
extern PyObject* PyInit__collections(void);
extern PyObject* PyInit__heapq(void);
extern PyObject* PyInit__bisect(void);
extern PyObject* PyInit__symtable(void);
extern PyObject* PyInit_mmap(void);
extern PyObject* PyInit__csv(void);
extern PyObject* PyInit__sre(void);
#if defined(MS_WINDOWS_DESKTOP) || defined(MS_WINDOWS_SYSTEM) || defined(MS_WINDOWS_GAMES)
extern PyObject* PyInit_winreg(void);
#endif
extern PyObject* PyInit__struct(void);
extern PyObject* PyInit__datetime(void);
extern PyObject* PyInit__functools(void);
extern PyObject* PyInit__json(void);
#ifdef _Py_HAVE_ZLIB
extern PyObject* PyInit_zlib(void);
#endif

extern PyObject* PyInit__multibytecodec(void);
extern PyObject* PyInit__codecs_cn(void);
extern PyObject* PyInit__codecs_hk(void);
extern PyObject* PyInit__codecs_iso2022(void);
extern PyObject* PyInit__codecs_jp(void);
extern PyObject* PyInit__codecs_kr(void);
extern PyObject* PyInit__codecs_tw(void);
extern PyObject* PyInit__winapi(void);
extern PyObject* PyInit__lsprof(void);
extern PyObject* PyInit__ast(void);
extern PyObject* PyInit__io(void);
extern PyObject* PyInit__pickle(void);
extern PyObject* PyInit_atexit(void);
extern PyObject* _PyWarnings_Init(void);
extern PyObject* PyInit__string(void);
extern PyObject* PyInit__stat(void);
extern PyObject* PyInit__opcode(void);
extern PyObject* PyInit__contextvars(void);
extern PyObject* PyInit__tokenize(void);
extern PyObject* PyInit__suggestions(void);

/* MagPython project-local additions: extensions statically linked
   into MagPython.dll instead of being shipped as separate .pyd
   files. Their .c sources are listed in MagPython.vcxproj. */
extern PyObject* PyInit__ctypes(void);
extern PyObject* PyInit__ssl(void);
extern PyObject* PyInit__hashlib(void);
extern PyObject* PyInit__socket(void);
extern PyObject* PyInit_select(void);
extern PyObject* PyInit_unicodedata(void);

/* tools/freeze/makeconfig.py marker for additional "extern" */
/* -- ADDMODULE MARKER 1 -- */

extern PyObject* PyMarshal_Init(void);
extern PyObject* PyInit__imp(void);

struct _inittab _PyImport_Inittab[] = {
    {"_abc", PyInit__abc},
    {"array", PyInit_array},
    {"_ast", PyInit__ast},
    {"binascii", PyInit_binascii},
    {"cmath", PyInit_cmath},
    {"errno", PyInit_errno},
    {"faulthandler", PyInit_faulthandler},
    {"gc", PyInit_gc},
    {"math", PyInit_math},
    {"nt", PyInit_nt}, /* Use the NT os functions, not posix */
    {"_operator", PyInit__operator},
    {"_signal", PyInit__signal},
    {"_md5", PyInit__md5},
    {"_sha1", PyInit__sha1},
    {"_sha2", PyInit__sha2},
    {"_sha3", PyInit__sha3},
    {"_blake2", PyInit__blake2},
    {"_sysconfig", PyInit__sysconfig},
    {"time", PyInit_time},
    {"_thread", PyInit__thread},
    {"_tokenize", PyInit__tokenize},
    {"_typing", PyInit__typing},
    {"_statistics", PyInit__statistics},
#ifdef WIN32
    {"msvcrt", PyInit_msvcrt},
    {"_locale", PyInit__locale},
#endif
    {"_tracemalloc", PyInit__tracemalloc},
    /* XXX Should _winapi go in a WIN32 block?  not WIN64? */
    {"_winapi", PyInit__winapi},

    {"_codecs", PyInit__codecs},
    {"_weakref", PyInit__weakref},
    {"_random", PyInit__random},
    {"_bisect", PyInit__bisect},
    {"_heapq", PyInit__heapq},
    {"_lsprof", PyInit__lsprof},
    {"itertools", PyInit_itertools},
    {"_collections", PyInit__collections},
    {"_symtable", PyInit__symtable},
#if defined(MS_WINDOWS_DESKTOP) || defined(MS_WINDOWS_GAMES)
    {"mmap", PyInit_mmap},
#endif
    {"_csv", PyInit__csv},
    {"_sre", PyInit__sre},
#if defined(MS_WINDOWS_DESKTOP) || defined(MS_WINDOWS_SYSTEM) || defined(MS_WINDOWS_GAMES)
    {"winreg", PyInit_winreg},
#endif
    {"_struct", PyInit__struct},
    {"_datetime", PyInit__datetime},
    {"_functools", PyInit__functools},
    {"_json", PyInit__json},
    {"_suggestions", PyInit__suggestions},

    {"xxsubtype", PyInit_xxsubtype},
    {"_interpreters", PyInit__interpreters},
    {"_interpchannels", PyInit__interpchannels},
    {"_interpqueues", PyInit__interpqueues},
#ifdef _Py_HAVE_ZLIB
    {"zlib", PyInit_zlib},
#endif

    /* CJK codecs */
    {"_multibytecodec", PyInit__multibytecodec},
    {"_codecs_cn", PyInit__codecs_cn},
    {"_codecs_hk", PyInit__codecs_hk},
    {"_codecs_iso2022", PyInit__codecs_iso2022},
    {"_codecs_jp", PyInit__codecs_jp},
    {"_codecs_kr", PyInit__codecs_kr},
    {"_codecs_tw", PyInit__codecs_tw},

    /* MagPython project-local additions, see comment above. */
    {"_ctypes", PyInit__ctypes},
    {"_ssl", PyInit__ssl},
    {"_hashlib", PyInit__hashlib},
    {"_socket", PyInit__socket},
    {"select", PyInit_select},
    {"unicodedata", PyInit_unicodedata},

/* tools/freeze/makeconfig.py marker for additional "_inittab" entries */
/* -- ADDMODULE MARKER 2 -- */

    /* This module "lives in" with marshal.c */
    {"marshal", PyMarshal_Init},

    /* This lives it with import.c */
    {"_imp", PyInit__imp},

    /* These entries are here for sys.builtin_module_names */
    {"builtins", NULL},
    {"sys", NULL},
    {"_warnings", _PyWarnings_Init},
    {"_string", PyInit__string},

    {"_io", PyInit__io},
    {"_pickle", PyInit__pickle},
    {"atexit", PyInit_atexit},
    {"_stat", PyInit__stat},
    {"_opcode", PyInit__opcode},

    {"_contextvars", PyInit__contextvars},

    /* Sentinel */
    {0, 0}
};
