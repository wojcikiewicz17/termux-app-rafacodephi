#include "bitstack.h"
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <assert.h>

BitStacks *bitstacks_create(int X, int Y, int D, int bits_per_stack) {
    BitStacks *bs = (BitStacks*)malloc(sizeof(BitStacks));
    if(!bs) return NULL;
    bs->X = X; bs->Y = Y; bs->D = D;
    bs->bits_per_stack = bits_per_stack;
    bs->blocks_per_stack = (bits_per_stack + 63) / 64;
    size_t total_stacks = (size_t)X * Y * D;
    size_t total_blocks = total_stacks * bs->blocks_per_stack;
    bs->blocks = (uint64_t*)calloc(total_blocks, sizeof(uint64_t));
    if(!bs->blocks) { free(bs); return NULL; }
    return bs;
}

void bitstacks_free(BitStacks *bs) {
    if(!bs) return;
    if(bs->blocks) free(bs->blocks);
    free(bs);
}

/* helper index */
static inline size_t _block_index(BitStacks *bs, int x, int y, int d, int block_idx) {
    assert(x>=0 && x<bs->X && y>=0 && y<bs->Y && d>=0 && d<bs->D && block_idx>=0 && block_idx<bs->blocks_per_stack);
    size_t stack_idx = ((size_t)x * bs->Y + (size_t)y) * bs->D + (size_t)d;
    return stack_idx * bs->blocks_per_stack + block_idx;
}

void bitstacks_set(BitStacks *bs, int x, int y, int d, int stack_idx, int value) {
    if(stack_idx < 0 || stack_idx >= bs->bits_per_stack) return;
    int block = stack_idx / 64;
    int offset = stack_idx % 64;
    size_t bi = _block_index(bs,x,y,d,block);
    uint64_t mask = 1ULL << offset;
    if(value) bs->blocks[bi] |= mask;
    else bs->blocks[bi] &= ~mask;
}

int bitstacks_get(BitStacks *bs, int x, int y, int d, int stack_idx) {
    if(stack_idx < 0 || stack_idx >= bs->bits_per_stack) return 0;
    int block = stack_idx / 64;
    int offset = stack_idx % 64;
    size_t bi = _block_index(bs,x,y,d,block);
    uint64_t word = bs->blocks[bi];
    return (word >> offset) & 1ULL;
}