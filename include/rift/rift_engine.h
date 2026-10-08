/* RIFT Engine - stable C API (ABI boundary).
 *
 * The C++ core sits behind this flat C interface so the UI (QML/Qt) or any
 * host binds to a stable ABI. Opaque handles, no C++ types leak out.
 *
 * Threading: the engine owns its render/audio/decode threads. API calls are
 * marshaled to the correct thread internally; callers use it from the UI
 * thread. Callbacks fire on an engine thread - marshal to UI yourself.
 */
#ifndef RIFT_ENGINE_H
#define RIFT_ENGINE_H

#include "rift_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(RIFT_BUILD_DLL)
#  define RIFT_API __declspec(dllexport)
#elif defined(_WIN32) && defined(RIFT_USE_DLL)
#  define RIFT_API __declspec(dllimport)
#else
#  define RIFT_API
#endif

typedef struct rift_engine  rift_engine;   /* opaque */
typedef uint32_t            rift_node;      /* graph node handle */

/* ── Lifecycle ─────────────────────────────────────────────── */
/* native_window: HWND (Win) the engine presents into. shaders_dir + cache
 * from disk. Returns NULL on failure. */
RIFT_API rift_engine* rift_create(void* native_window,
                                  const char* shaders_dir,
                                  const char* shader_cache_dir);
RIFT_API void         rift_destroy(rift_engine*);

/* Resize the presentation surface (letterbox is internal). */
RIFT_API void rift_resize(rift_engine*, int32_t w, int32_t h);

/* ── Media (async decode) ──────────────────────────────────── */
/* Non-blocking. Poll rift_media_ready(). Image/video/svg. */
RIFT_API void    rift_load_media(rift_engine*, const char* path);
RIFT_API int32_t rift_media_ready(rift_engine*);          /* bool */
RIFT_API void    rift_media_size(rift_engine*, int32_t* w, int32_t* h);

/* ── Audio ─────────────────────────────────────────────────── */
/* Loads audio + attaches a precomputed .analysis blob if analysis_path set,
 * else triggers the offline analyzer (may take seconds; poll ready). */
RIFT_API void    rift_load_audio(rift_engine*, const char* audio_path,
                                 const char* analysis_path /*nullable*/);
RIFT_API int32_t rift_audio_ready(rift_engine*);          /* bool */
RIFT_API void    rift_play(rift_engine*);
RIFT_API void    rift_pause(rift_engine*);
RIFT_API void    rift_seek(rift_engine*, double seconds);
RIFT_API double  rift_playhead(rift_engine*);
RIFT_API void    rift_set_loop(rift_engine*, int32_t on);
/* Latest smoothed channel values (for meters/debug). */
RIFT_API void    rift_channels(rift_engine*, rift_channel_frame* out);

/* ── Effect graph ──────────────────────────────────────────── */
RIFT_API rift_node rift_graph_add_source(rift_engine*);
RIFT_API rift_node rift_graph_add_effect(rift_engine*, const char* shader_id);
RIFT_API rift_node rift_graph_add_output(rift_engine*);
RIFT_API void      rift_graph_connect(rift_engine*, rift_node from, rift_node to);
RIFT_API void      rift_graph_remove(rift_engine*, rift_node);
RIFT_API void      rift_graph_reorder(rift_engine*, rift_node, int32_t index);
RIFT_API void      rift_graph_clear(rift_engine*);

/* ── Parameters / patch bay ────────────────────────────────── */
RIFT_API void rift_param_set_value(rift_engine*, rift_node, const char* uniform, float v);
RIFT_API void rift_param_set_binding(rift_engine*, rift_node, const char* uniform,
                                     const rift_binding*);
RIFT_API float rift_param_get_value(rift_engine*, rift_node, const char* uniform);

/* ── Project (.rift) ───────────────────────────────────────── */
RIFT_API int32_t rift_project_save(rift_engine*, const char* path, const char* name);
RIFT_API int32_t rift_project_load(rift_engine*, const char* path);

/* ── Preview / present ─────────────────────────────────────── */
RIFT_API void rift_set_preview_scale(rift_engine*, rift_preview_scale);
/* The engine drives its own vsync'd render thread; no per-frame call needed.
 * This forces a redraw when paused (e.g. after a param edit). */
RIFT_API void rift_request_redraw(rift_engine*);

/* ── Export ────────────────────────────────────────────────── */
/* rift_export_cb is declared in rift_types.h */
RIFT_API void rift_export_start(rift_engine*, const rift_export_spec*,
                                rift_export_cb, void* user);
RIFT_API void rift_export_cancel(rift_engine*);

/* ── Introspection ─────────────────────────────────────────── */
RIFT_API void rift_get_stats(rift_engine*, rift_stats* out);
RIFT_API const char* rift_last_error(rift_engine*);

/* Enumerate available effects (from shader manifests). */
RIFT_API int32_t     rift_effect_count(rift_engine*);
RIFT_API const char* rift_effect_id(rift_engine*, int32_t index);

#ifdef __cplusplus
}
#endif
#endif /* RIFT_ENGINE_H */
