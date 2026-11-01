// Mojo runtime surface for Emscripten: only KGEN_* / AsyncRT_*; libc+libm come from emscripten (musl).
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
void *KGEN_CompilerRT_AlignedAlloc(size_t align, size_t size) { void *p = 0; if (align < sizeof(void*)) align = sizeof(void*); return posix_memalign(&p, align, size ? size : 1) ? 0 : p; }
void KGEN_CompilerRT_AlignedFree(void *p) { free(p); }
int KGEN_CompilerRT_fprintf(void *f, const char *fmt, ...) { va_list ap; va_start(ap, fmt); int r = vfprintf(f ? (FILE*)f : stderr, fmt, ap); va_end(ap); return r; }
long long KGEN_CompilerRT_GetStackTrace(void *p, long long n) { return 0; }
long long KGEN_CompilerRT_TracyIsEnabled(void) { return 0; }
long long KGEN_CompilerRT_TracyZoneBegin(void *s, long long n, int c) { return 0; }
void KGEN_CompilerRT_TracyZoneEnd(long long z) {}
long long KGEN_CompilerRT_NumPhysicalCores(void) { return 1; }
int KGEN_CompilerRT_AsyncRT_ParallelismLevel(void) { return 1; }
long long AsyncRT_DeviceContext_create(void *a, void *b, int c) { __builtin_trap(); }
void AsyncRT_DeviceContext_deviceApi(void *a, long long b) { __builtin_trap(); }
long long AsyncRT_DeviceContext_enqueueHostFunctionRange(long long a, void *b, void *c, void *d, long long e) { __builtin_trap(); }
void AsyncRT_DeviceContext_release(long long a) { __builtin_trap(); }
void AsyncRT_DeviceContext_strfree(long long a) { __builtin_trap(); }
long long AsyncRT_DeviceContext_synchronize(long long a) { __builtin_trap(); }
