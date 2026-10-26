#ifndef BERRY_MP301_RUNTIME_H
#define BERRY_MP301_RUNTIME_H
#include <stddef.h>
void berry_heap_bind(void *base, size_t bytes);
size_t berry_heap_used(void);
int berry_heap_failed(void);
#endif
