#ifndef BITSTACK_H
#define BITSTACK_H

#include <stdint.h>
#include <stdlib.h>

typedef struct {
    int X, Y, D;
    int bits_per_stack;
    int blocks_per_stack; // bits_per_stack / 64 rounded up
    uint64_t *blocks;    // contiguous blocks: blocks[( ((x*Y + y)*D) * blocks_per_stack + b )]
} BitStacks;

/* create / free */
BitStacks *bitstacks_create(int X, int Y, int D, int bits_per_stack);
void bitstacks_free(BitStacks *bs);

/* push/pop/get/set bit at stack index (stack_idx relative 0..bits_per_stack-1) */
void bitstacks_set(BitStacks *bs, int x, int y, int d, int stack_idx, int value);
int bitstacks_get(BitStacks *bs, int x, int y, int d, int stack_idx);

/* atomic-like push/pop not implemented fully; simple set/get provided */
size_t bitstacks_index(BlockSizes_unused);

#endif // BITSTACK_H