#include <stddef.h>
#include <stdint.h>
#include "berry_mp301_runtime.h"

static uint8_t *g_heap;
static size_t g_heap_size, g_heap_used;
static int g_heap_failed;

void berry_heap_bind(void *base, size_t bytes)
{
    g_heap=(uint8_t*)base; g_heap_size=bytes; g_heap_used=0; g_heap_failed=0;
}
size_t berry_heap_used(void) { return g_heap_used; }
int berry_heap_failed(void) { return g_heap_failed; }

void *memset(void *dst, int c, size_t n)
{
    uint8_t *d=(uint8_t*)dst; while(n--) *d++=(uint8_t)c; return dst;
}
void *memcpy(void *dst, const void *src, size_t n)
{
    uint8_t *d=(uint8_t*)dst; const uint8_t *s=(const uint8_t*)src;
    while(n--) *d++=*s++; return dst;
}
void *memmove(void *dst, const void *src, size_t n)
{
    uint8_t *d=(uint8_t*)dst; const uint8_t *s=(const uint8_t*)src;
    if(d<s) while(n--) *d++=*s++;
    else { d+=n; s+=n; while(n--) *--d=*--s; }
    return dst;
}

void *malloc(size_t n)
{
    size_t a=(n+15u)&~15u;
    if(!g_heap || a>g_heap_size-g_heap_used) { g_heap_failed=1; return 0; }
    void *p=g_heap+g_heap_used; g_heap_used+=a; memset(p,0,a); return p;
}
void free(void *p) { (void)p; }
void *calloc(size_t n, size_t s)
{
    if(s && n>((size_t)-1)/s) { g_heap_failed=1; return 0; }
    return malloc(n*s);
}
