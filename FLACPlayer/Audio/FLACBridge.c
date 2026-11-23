#include "FLACBridge.h"
#include <FLAC/stream_decoder.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <math.h>

struct FLACBridge {
    FLAC__StreamDecoder *decoder;
    uint32_t rate, channels, bits;
    uint64_t total_samples;
    float *pending;       /* interleaved samples for one decoded FLAC frame */
    size_t pending_capacity, pending_frames, pending_offset;
    char *title, *artist, *album, *album_artist;
    uint8_t *art;
    size_t art_len;
    int failed;
};

static char *copy_utf8(const uint8_t *data, size_t n) {
    if (n == 0 || n > 8192) return NULL;
    char *s = (char *)malloc(n + 1);
    if (s != NULL) {
        memcpy(s, data, n);
        s[n] = '\0';
    }
    return s;
}

static void parse_tag(FLACBridge *ctx, const FLAC__StreamMetadata_VorbisComment_Entry *entry) {
    const uint8_t *p = entry->entry;
    size_t n = (size_t)entry->length;
    if (!p || n == 0 || n > 8192) return;
    const uint8_t *equal = memchr(p, '=', n);
    if (!equal) return;
    size_t k = (size_t)(equal - p);
    char **dest = NULL;
    if (k == 5 && strncasecmp((const char *)p, "TITLE", k) == 0) dest = &ctx->title;
    else if (k == 6 && strncasecmp((const char *)p, "ARTIST", k) == 0) dest = &ctx->artist;
    else if (k == 5 && strncasecmp((const char *)p, "ALBUM", k) == 0) dest = &ctx->album;
    else if ((k == 11 && strncasecmp((const char *)p, "ALBUMARTIST", k) == 0) ||
             (k == 12 && strncasecmp((const char *)p, "ALBUM_ARTIST", k) == 0)) dest = &ctx->album_artist;
    if (dest != NULL && *dest == NULL) *dest = copy_utf8(equal + 1, n - k - 1);
}

static FLAC__StreamDecoderWriteStatus on_audio(const FLAC__StreamDecoder *decoder,
                                                 const FLAC__Frame *frame,
                                                 const FLAC__int32 *const buffers[],
                                                 void *client_data) {
    (void)decoder;
    FLACBridge *ctx = (FLACBridge *)client_data;
    const size_t n = (size_t)frame->header.blocksize;
    const size_t channels = (size_t)frame->header.channels;
    if ((channels != 1 && channels != 2) || channels != ctx->channels ||
        (ctx->bits != 16 && ctx->bits != 24) || n > SIZE_MAX / channels) {
        ctx->failed = 1;
        return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    }
    const size_t count = n * channels;
    if (count > ctx->pending_capacity) {
        float *new_data = (float *)realloc(ctx->pending, count * sizeof(float));
        if (!new_data) {
            ctx->failed = 1;
            return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
        }
        ctx->pending = new_data;
        ctx->pending_capacity = count;
    }
    const float scale = ldexpf(1.0f, (int)ctx->bits - 1);
    for (size_t frame_index = 0; frame_index < n; frame_index++) {
        for (size_t ch = 0; ch < channels; ch++) {
            ctx->pending[frame_index * channels + ch] =
                (float)buffers[ch][frame_index] / scale;
        }
    }
    ctx->pending_frames = n;
    ctx->pending_offset = 0;
    return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

static void on_metadata(const FLAC__StreamDecoder *decoder,
                        const FLAC__StreamMetadata *metadata, void *client_data) {
    (void)decoder;
    FLACBridge *ctx = (FLACBridge *)client_data;
    if (metadata->type == FLAC__METADATA_TYPE_STREAMINFO) {
        ctx->rate = metadata->data.stream_info.sample_rate;
        ctx->channels = metadata->data.stream_info.channels;
        ctx->bits = metadata->data.stream_info.bits_per_sample;
        ctx->total_samples = metadata->data.stream_info.total_samples;
    } else if (metadata->type == FLAC__METADATA_TYPE_VORBIS_COMMENT) {
        const FLAC__StreamMetadata_VorbisComment *v = &metadata->data.vorbis_comment;
        for (uint32_t i = 0; i < v->num_comments; i++) parse_tag(ctx, &v->comments[i]);
    } else if (metadata->type == FLAC__METADATA_TYPE_PICTURE) {
        const FLAC__StreamMetadata_Picture *pic = &metadata->data.picture;
        const size_t n = (size_t)pic->data_length;
        /* Keep bounded artwork memory and prefer the front cover. */
        if (pic->data && n > 0 && n <= 10u * 1024u * 1024u &&
            (ctx->art == NULL || pic->type == FLAC__STREAM_METADATA_PICTURE_TYPE_FRONT_COVER)) {
            uint8_t *copy = (uint8_t *)malloc(n);
            if (copy) {
                memcpy(copy, pic->data, n);
                free(ctx->art);
                ctx->art = copy;
                ctx->art_len = n;
            }
        }
    }
}

static void on_error(const FLAC__StreamDecoder *decoder,
                     FLAC__StreamDecoderErrorStatus status, void *client_data) {
    (void)decoder; (void)status;
    ((FLACBridge *)client_data)->failed = 1;
}

FLACBridge *flac_bridge_open(const char *utf8_filename) {
    if (!utf8_filename) return NULL;
    FLACBridge *ctx = (FLACBridge *)calloc(1, sizeof(FLACBridge));
    if (!ctx) return NULL;
    ctx->decoder = FLAC__stream_decoder_new();
    if (!ctx->decoder) { free(ctx); return NULL; }
    FLAC__stream_decoder_set_metadata_respond_all(ctx->decoder);
    if (FLAC__stream_decoder_init_file(ctx->decoder, utf8_filename, on_audio, on_metadata,
                                       on_error, ctx) != FLAC__STREAM_DECODER_INIT_STATUS_OK ||
        !FLAC__stream_decoder_process_until_end_of_metadata(ctx->decoder) ||
        ctx->rate == 0 || ctx->channels < 1 || ctx->channels > 2 ||
        (ctx->bits != 16 && ctx->bits != 24)) {
        flac_bridge_close(ctx);
        return NULL;
    }
    return ctx;
}

void flac_bridge_close(FLACBridge *ctx) {
    if (!ctx) return;
    if (ctx->decoder) {
        FLAC__stream_decoder_finish(ctx->decoder);
        FLAC__stream_decoder_delete(ctx->decoder);
    }
    free(ctx->pending);
    free(ctx->title); free(ctx->artist); free(ctx->album); free(ctx->album_artist);
    free(ctx->art);
    free(ctx);
}

uint32_t flac_bridge_sample_rate(const FLACBridge *ctx) { return ctx ? ctx->rate : 0; }
uint32_t flac_bridge_channels(const FLACBridge *ctx) { return ctx ? ctx->channels : 0; }
uint32_t flac_bridge_bits_per_sample(const FLACBridge *ctx) { return ctx ? ctx->bits : 0; }
uint64_t flac_bridge_total_samples(const FLACBridge *ctx) { return ctx ? ctx->total_samples : 0; }
const char *flac_bridge_title(const FLACBridge *ctx) { return ctx ? ctx->title : NULL; }
const char *flac_bridge_artist(const FLACBridge *ctx) { return ctx ? ctx->artist : NULL; }
const char *flac_bridge_album(const FLACBridge *ctx) { return ctx ? ctx->album : NULL; }
const char *flac_bridge_album_artist(const FLACBridge *ctx) { return ctx ? ctx->album_artist : NULL; }
const uint8_t *flac_bridge_picture(const FLACBridge *ctx, size_t *byte_count) {
    if (byte_count) *byte_count = ctx ? ctx->art_len : 0;
    return ctx ? ctx->art : NULL;
}

int32_t flac_bridge_read(FLACBridge *ctx, float *out_interleaved, uint32_t frame_capacity) {
    if (!ctx || !out_interleaved || ctx->failed) return -1;
    uint32_t written = 0;
    while (written < frame_capacity) {
        if (ctx->pending_offset == ctx->pending_frames) {
            ctx->pending_frames = ctx->pending_offset = 0;
            FLAC__StreamDecoderState state = FLAC__stream_decoder_get_state(ctx->decoder);
            if (state == FLAC__STREAM_DECODER_END_OF_STREAM) break;
            if (state == FLAC__STREAM_DECODER_ABORTED ||
                !FLAC__stream_decoder_process_single(ctx->decoder) || ctx->failed) return -1;
            /* Could encounter non-audio metadata or recoverable sync changes. */
            if (ctx->pending_frames == 0) continue;
        }
        size_t available = ctx->pending_frames - ctx->pending_offset;
        size_t remaining = (size_t)(frame_capacity - written);
        size_t count = available < remaining ? available : remaining;
        memcpy(out_interleaved + (size_t)written * ctx->channels,
               ctx->pending + ctx->pending_offset * ctx->channels,
               count * ctx->channels * sizeof(float));
        ctx->pending_offset += count;
        written += (uint32_t)count;
    }
    return (int32_t)written;
}

int flac_bridge_seek(FLACBridge *ctx, uint64_t absolute_sample) {
    if (!ctx) return 0;
    ctx->pending_frames = ctx->pending_offset = 0;
    ctx->failed = 0;
    if (ctx->total_samples != 0 && absolute_sample >= ctx->total_samples)
        absolute_sample = ctx->total_samples - 1;
    return FLAC__stream_decoder_seek_absolute(ctx->decoder, absolute_sample) ? 1 : 0;
}
