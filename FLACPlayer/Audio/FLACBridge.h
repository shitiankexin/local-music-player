#ifndef LOCAL_FLAC_BRIDGE_H
#define LOCAL_FLAC_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FLACBridge FLACBridge;

/* A single instance is not thread safe. Keep every call on one serial queue. */
FLACBridge *flac_bridge_open(const char *utf8_filename);
void flac_bridge_close(FLACBridge *ctx);
uint32_t flac_bridge_sample_rate(const FLACBridge *ctx);
uint32_t flac_bridge_channels(const FLACBridge *ctx);
uint32_t flac_bridge_bits_per_sample(const FLACBridge *ctx);
uint64_t flac_bridge_total_samples(const FLACBridge *ctx);
const char *flac_bridge_title(const FLACBridge *ctx);
const char *flac_bridge_artist(const FLACBridge *ctx);
const char *flac_bridge_album(const FLACBridge *ctx);
const char *flac_bridge_album_artist(const FLACBridge *ctx);
const uint8_t *flac_bridge_picture(const FLACBridge *ctx, size_t *byte_count);

/* Reads at most frame_capacity frames, interleaved Float32 PCM. 0 = EOF, -1 = error. */
int32_t flac_bridge_read(FLACBridge *ctx, float *out_interleaved, uint32_t frame_capacity);
int flac_bridge_seek(FLACBridge *ctx, uint64_t absolute_sample);

#ifdef __cplusplus
}
#endif
#endif
