/* RIFT Engine - shared POD types for the C ABI boundary.
 * Kept trivially-copyable and stable across versions. */
#ifndef RIFT_TYPES_H
#define RIFT_TYPES_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Channel indices - MUST match .analysis blob + shader uniform order. */
typedef enum {
    RIFT_CH_BASS = 0,
    RIFT_CH_MELODY,      /* MIDS */
    RIFT_CH_HIGHS,       /* AIR  */
    RIFT_CH_DRUMS,       /* BEAT */
    RIFT_CH_TRANSIENT,   /* HIT  */
    RIFT_CH_BPM,
    RIFT_CH_CENTROID,
    RIFT_CH_TIME,
    RIFT_CH_KICK,
    RIFT_CH_SNARE,
    RIFT_CH_COUNT        /* = 10 */
} rift_channel;

/* One frame of resolved channel values handed audio->render (lock-free). */
typedef struct {
    float  ch[RIFT_CH_COUNT];
    double playhead;     /* seconds */
} rift_channel_frame;

/* Modulation curve, mirrors params.py Mod.curve. */
typedef enum { RIFT_CURVE_LIN = 0, RIFT_CURVE_EXP, RIFT_CURVE_LOG } rift_curve;

/* Patch-bay binding, mirrors params.py Mod (v2). */
typedef struct {
    int32_t   channel;     /* rift_channel, or -1 = none */
    float     depth;       /* mod_amount */
    float     in_lo, in_hi;
    rift_curve curve;
    float     attack, release;
    int32_t   invert;      /* bool */
} rift_binding;

typedef enum {
    RIFT_PREVIEW_FULL = 0,
    RIFT_PREVIEW_HALF,
    RIFT_PREVIEW_QUARTER
} rift_preview_scale;

typedef enum {
    RIFT_EXPORT_HIGH = 0,
    RIFT_EXPORT_YOUTUBE,
    RIFT_EXPORT_ARCHIVE,
    RIFT_EXPORT_PREVIEW
} rift_export_quality;

typedef struct {
    int32_t  width, height;          /* even; letterbox handled at present */
    int32_t  fps;
    rift_export_quality quality;
    int32_t  no_watermark;           /* bool */
    const char* out_path;            /* utf-8 */
    const char* audio_path;          /* muxed at full quality; may be null */
    /* --- appended; older callers zero-init and get the previous behaviour --- */
    const char* logo_path;           /* PNG w/ alpha, bottom-right; may be null */
    const char* font_dir;            /* dir of .ttf/.otf for overlays; may be null */
    int32_t  total_frames;           /* 0 = derive from media/audio duration */
    /* Export only a range. Both in seconds; out <= in means "whole piece", so
       a zero-initialised spec keeps the old behaviour. The rendered playhead
       is still real time, not time-since-in, so keyframes and audio land
       exactly where the preview showed them. */
    double   mark_in;
    double   mark_out;
} rift_export_spec;

/* Export progress callback (fires on an engine thread). Declared here so the
   C++ engine headers can use it without pulling the full C API header. */
typedef void (*rift_export_cb)(int32_t percent, int32_t done, void* user);

typedef struct {
    double   frame_ms;               /* last render frame time */
    double   fps;
    uint64_t frames_rendered;
    int32_t  gpu_textures_live;
    int32_t  gpu_pool_free;
    /* Frame-time distribution over a rolling window, in ms.

       frame_ms alone is the LAST frame, so a hitch every 30th frame is
       invisible unless you happen to sample it at that instant - and a hitch
       is exactly what people notice. A mean hides it too: 59 frames at 8 ms
       and one at 200 ms still averages a comfortable 11 ms.

       p95/p99 are what a dropped frame actually shows up in; frame_ms_max is
       the worst frame seen in the window. New fields are appended, so the ABI
       stays compatible with anything compiled against the old struct. */
    double   frame_ms_p50;
    double   frame_ms_p95;
    double   frame_ms_p99;
    double   frame_ms_max;
    /* GPU time for the last completed frame, 0 when the backend cannot report
       it. Distinguishes "the shader is heavy" from "the CPU is not feeding it
       fast enough", which is the first fork in any render investigation. */
    double   gpu_ms;
} rift_stats;

#ifdef __cplusplus
}
#endif
#endif /* RIFT_TYPES_H */
