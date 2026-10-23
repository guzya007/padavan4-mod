/* SPDX-License-Identifier: GPL-2.0 OR MIT */
/* Header protection uses the module's Zinc implementation on old kernels. */
#ifndef _AWG_COMPAT_CRYPTO_CHACHA_H
#define _AWG_COMPAT_CRYPTO_CHACHA_H

#include <zinc/chacha20.h>
#include <linux/string.h>

#define CHACHA_KEY_SIZE CHACHA20_KEY_SIZE
#define CHACHA_BLOCK_SIZE CHACHA20_BLOCK_SIZE

static inline void chacha_init(u32 *state, const u32 *key, const u8 *iv)
{
	int i;
	state[0] = CHACHA20_CONSTANT_EXPA;
	state[1] = CHACHA20_CONSTANT_ND_3;
	state[2] = CHACHA20_CONSTANT_2_BY;
	state[3] = CHACHA20_CONSTANT_TE_K;
	memcpy(state + 4, key, CHACHA20_KEY_SIZE);
	for (i = 0; i < 4; i++)
		state[12 + i] = get_unaligned_le32(iv + i * 4);
}

static inline void chacha20_crypt(u32 *state, u8 *dst, const u8 *src,
				unsigned int bytes)
{
	struct chacha20_ctx ctx;
	simd_context_t simd;
	memcpy(ctx.state, state, sizeof(ctx.state));
	simd_get(&simd);
	chacha20(&ctx, dst, src, bytes, &simd);
	simd_put(&simd);
	memcpy(state, ctx.state, sizeof(ctx.state));
	memzero_explicit(&ctx, sizeof(ctx));
}

#endif
