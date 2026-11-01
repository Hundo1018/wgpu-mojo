// The slice of a C runtime and of Mojo's KGEN/AsyncRT surface that the web IR
// leaves undefined (#16). Freestanding wasm64; no libc. Everything beyond this
// is a `wgpu*` import, which the JS translation layer provides.
#include <stddef.h>
#include <stdint.h>

extern unsigned char __heap_base;

// A size-class allocator: power-of-two classes with free lists. Mojo frees what
// it allocates every frame, so a bump allocator would leak without bound.
typedef struct hdr { uint64_t cls; uint64_t pad; } hdr;   // 16 bytes keeps 16-byte alignment
static void *free_list[48];
static uintptr_t brk;

static void *grab(size_t n) {
    if (!brk) brk = ((uintptr_t)&__heap_base + 15) & ~(uintptr_t)15;
    uintptr_t p = brk;
    uintptr_t end = p + n;
    size_t have = __builtin_wasm_memory_size(0) * 65536;
    if (end > have) {
        size_t pages = (end - have + 65535) / 65536;
        if (__builtin_wasm_memory_grow(0, pages) == (size_t)-1) return 0;
    }
    brk = end;
    return (void *)p;
}

static void *rt_alloc(size_t size, size_t align) {
    if (align < 16) align = 16;
    size_t need = size + sizeof(hdr) + (align > 16 ? align : 0);
    int cls = 5;
    while (((size_t)1 << cls) < need) cls++;
    void *blk = free_list[cls];
    if (blk) free_list[cls] = *(void **)blk;
    else { blk = grab((size_t)1 << cls); if (!blk) return 0; }
    uintptr_t user = ((uintptr_t)blk + sizeof(hdr) + align - 1) & ~(uintptr_t)(align - 1);
    hdr *h = (hdr *)(user - sizeof(hdr));
    h->cls = (uint64_t)cls;
    h->pad = (uint64_t)(user - (uintptr_t)blk);      // distance back to the block start
    return (void *)user;
}

static void rt_free(void *p) {
    if (!p) return;
    hdr *h = (hdr *)((uintptr_t)p - sizeof(hdr));
    void *blk = (void *)((uintptr_t)p - h->pad);
    *(void **)blk = free_list[h->cls];
    free_list[h->cls] = blk;
}

void *KGEN_CompilerRT_AlignedAlloc(size_t align, size_t size) { return rt_alloc(size, align); }
void KGEN_CompilerRT_AlignedFree(void *p) { rt_free(p); }
int KGEN_CompilerRT_fprintf(void *f, const char *fmt, ...) { (void)f; (void)fmt; return 0; }
long KGEN_CompilerRT_GetStackTrace(void *buf, long depth) { (void)buf; (void)depth; return 0; }

// Exported for the JS side: wasm memory it can write strings and structs into.
__attribute__((export_name("mw_alloc"))) void *mw_alloc(size_t n) { return rt_alloc(n, 16); }
__attribute__((export_name("mw_free"))) void mw_free(void *p) { rt_free(p); }

// stdio left over from Mojo's print paths; a browser build has no fds.
int dup(int fd) { return fd; }
int fclose(void *f) { (void)f; return 0; }
void *fdopen(int fd, const char *mode) { (void)fd; (void)mode; return 0; }
int fflush(void *f) { (void)f; return 0; }
long write(int fd, const void *buf, unsigned long n) { (void)fd; (void)buf; return (long)n; }
