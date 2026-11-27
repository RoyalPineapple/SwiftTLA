// Diagnostic dylib for otherwise uninstrumented release clients on Darwin.
// Counts successful calls and requested bytes at the interposed malloc-family boundaries.
#include <malloc/malloc.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>

static _Atomic int active;
static _Atomic uint64_t events, bytes;
static _Thread_local int inside;
void bench_begin(void) { events = 0; bytes = 0; active = 1; }
void bench_end(void) { active = 0; }
uint64_t bench_events(void) { return events; }
uint64_t bench_bytes(void) { return bytes; }

static int enter(void) {
    if (!atomic_load_explicit(&active, memory_order_relaxed) || inside) return 0;
    inside = 1;
    return 1;
}
static void finish(int outer, const void *p, size_t n) {
    if (!outer) return;
    if (p) {
        atomic_fetch_add_explicit(&events, 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&bytes, n, memory_order_relaxed);
    }
    inside = 0;
}
#define INTERPOSE(name) \
    __attribute__((used,section("__DATA,__interpose"))) static const struct { \
        const void *replacement; const void *original; \
    } ip_##name = { (const void *)&probe_##name, (const void *)&name };
#define ALLOCATOR(name, params, args, requested) \
    static void *probe_##name params { \
        int outer = enter(); void *p = name args; finish(outer, p, requested); return p; \
    } \
    INTERPOSE(name)
ALLOCATOR(malloc,(size_t n),(n),n)
ALLOCATOR(calloc,(size_t n,size_t s),(n,s),n*s)
ALLOCATOR(realloc,(void *p0,size_t n),(p0,n),n)
ALLOCATOR(aligned_alloc,(size_t a,size_t n),(a,n),n)
ALLOCATOR(malloc_zone_malloc,(malloc_zone_t *z,size_t n),(z,n),n)
ALLOCATOR(malloc_zone_calloc,(malloc_zone_t *z,size_t n,size_t s),(z,n,s),n*s)
ALLOCATOR(malloc_zone_realloc,(malloc_zone_t *z,void *p0,size_t n),(z,p0,n),n)
ALLOCATOR(malloc_zone_memalign,(malloc_zone_t *z,size_t a,size_t n),(z,a,n),n)
static int probe_posix_memalign(void **out, size_t alignment, size_t n) {
    int outer = enter();
    int status = posix_memalign(out,alignment,n);
    finish(outer,status == 0 ? *out : NULL,n);
    return status;
}
INTERPOSE(posix_memalign)
