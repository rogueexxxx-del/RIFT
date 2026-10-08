// C API implementation.
//   RIFT_WITH_RHI ON  -> real rift::Engine (threads + RHI + audio).
//   RIFT_WITH_RHI OFF -> lightweight StubEngine so the C ABI + core logic
//                        (pool/cache/parity) compile and test with no GPU.
#include "rift/rift_engine.h"
#include <string>
#include <cstring>

#if RIFT_WITH_RHI
// ─────────────────────────── REAL ENGINE ───────────────────────────
#include "engine.hpp"
using rift::Engine;
#define E(h) reinterpret_cast<Engine*>(h)

extern "C" {

RIFT_API rift_engine* rift_create(void* win, const char* sh, const char* ca) {
    return reinterpret_cast<rift_engine*>(
        new Engine(win, sh ? sh : "", ca ? ca : ""));
}
RIFT_API void rift_destroy(rift_engine* h) { delete E(h); }
RIFT_API void rift_resize(rift_engine* h, int32_t w, int32_t hh) { E(h)->resize(w, hh); }

RIFT_API void    rift_load_media(rift_engine* h, const char* p) { E(h)->loadMedia(p ? p : ""); }
RIFT_API int32_t rift_media_ready(rift_engine* h) { return E(h)->mediaReady(); }
RIFT_API void    rift_media_size(rift_engine*, int32_t* w, int32_t* hh) { if(w)*w=0; if(hh)*hh=0; }

RIFT_API void    rift_load_audio(rift_engine* h, const char* a, const char* an) {
    E(h)->loadAudio(a ? a : "", an ? an : "");
}
RIFT_API int32_t rift_audio_ready(rift_engine* h) { return E(h)->audioReady(); }
RIFT_API void    rift_play(rift_engine* h)  { E(h)->play(); }
RIFT_API void    rift_pause(rift_engine* h) { E(h)->pause(); }
RIFT_API void    rift_seek(rift_engine* h, double s) { E(h)->seek(s); }
RIFT_API double  rift_playhead(rift_engine* h) { return E(h)->playhead(); }
RIFT_API void    rift_set_loop(rift_engine* h, int32_t on) { E(h)->setLoop(on != 0); }
RIFT_API void    rift_channels(rift_engine* h, rift_channel_frame* out) { if(out) E(h)->channels(*out); }

RIFT_API rift_node rift_graph_add_source(rift_engine* h) { return E(h)->graph().addSource(); }
RIFT_API rift_node rift_graph_add_effect(rift_engine* h, const char* s) { return E(h)->graph().addEffect(s ? s : ""); }
RIFT_API rift_node rift_graph_add_output(rift_engine* h) { return E(h)->graph().addOutput(); }
RIFT_API void      rift_graph_connect(rift_engine* h, rift_node a, rift_node b) { E(h)->graph().connect(a, b); }
RIFT_API void      rift_graph_remove(rift_engine* h, rift_node n) { E(h)->graph().remove(n); }
RIFT_API void      rift_graph_reorder(rift_engine* h, rift_node n, int32_t i) { E(h)->graph().reorder(n, i); }
RIFT_API void      rift_graph_clear(rift_engine* h) { E(h)->graph().clear(); }

// Param-by-name setters land with the manifest binding loader (P4); no-op now.
RIFT_API void  rift_param_set_value(rift_engine*, rift_node, const char*, float) {}
RIFT_API void  rift_param_set_binding(rift_engine*, rift_node, const char*, const rift_binding*) {}
RIFT_API float rift_param_get_value(rift_engine*, rift_node, const char*) { return 0.f; }

RIFT_API int32_t rift_project_save(rift_engine*, const char*, const char*) { return 1; }
RIFT_API int32_t rift_project_load(rift_engine*, const char*) { return 1; }

RIFT_API void rift_set_preview_scale(rift_engine* h, rift_preview_scale s) { E(h)->setPreviewScale(s); }
RIFT_API void rift_request_redraw(rift_engine* h) { E(h)->requestRedraw(); }

RIFT_API void rift_export_start(rift_engine* h, const rift_export_spec* s, rift_export_cb cb, void* u) {
    if (s) E(h)->exportStart(*s, cb, u);
}
RIFT_API void rift_export_cancel(rift_engine* h) { E(h)->exportCancel(); }

RIFT_API void        rift_get_stats(rift_engine* h, rift_stats* out) { if(out) E(h)->stats(*out); }
RIFT_API const char* rift_last_error(rift_engine* h) { return E(h)->lastError(); }
RIFT_API int32_t     rift_effect_count(rift_engine*) { return 0; }
RIFT_API const char* rift_effect_id(rift_engine*, int32_t) { return ""; }

} // extern "C"

#else
// ─────────────────────────── STUB ENGINE ───────────────────────────
namespace {
struct StubEngine {
    std::string shaders_dir, cache_dir, err;
    bool media_ready = false, audio_ready = false, loop = true;
    double playhead = 0.0;
    rift_channel_frame ch{};
    rift_stats stats{};
    uint32_t next_node = 1;
};
}
using Engine = StubEngine;
#define E(h) reinterpret_cast<Engine*>(h)

extern "C" {

RIFT_API rift_engine* rift_create(void*, const char* sh, const char* ca) {
    auto* e = new Engine();
    e->shaders_dir = sh ? sh : "";
    e->cache_dir   = ca ? ca : "";
    return reinterpret_cast<rift_engine*>(e);
}
RIFT_API void rift_destroy(rift_engine* h) { delete E(h); }
RIFT_API void rift_resize(rift_engine*, int32_t, int32_t) {}

RIFT_API void    rift_load_media(rift_engine* h, const char*) { E(h)->media_ready = true; }
RIFT_API int32_t rift_media_ready(rift_engine* h) { return E(h)->media_ready; }
RIFT_API void    rift_media_size(rift_engine*, int32_t* w, int32_t* hh) { if(w)*w=0; if(hh)*hh=0; }

RIFT_API void    rift_load_audio(rift_engine* h, const char*, const char*) { E(h)->audio_ready = true; }
RIFT_API int32_t rift_audio_ready(rift_engine* h) { return E(h)->audio_ready; }
RIFT_API void    rift_play(rift_engine*)  {}
RIFT_API void    rift_pause(rift_engine*) {}
RIFT_API void    rift_seek(rift_engine* h, double s) { E(h)->playhead = s; }
RIFT_API double  rift_playhead(rift_engine* h) { return E(h)->playhead; }
RIFT_API void    rift_set_loop(rift_engine* h, int32_t on) { E(h)->loop = on; }
RIFT_API void    rift_channels(rift_engine* h, rift_channel_frame* out) { if(out) *out = E(h)->ch; }

RIFT_API rift_node rift_graph_add_source(rift_engine* h) { return E(h)->next_node++; }
RIFT_API rift_node rift_graph_add_effect(rift_engine* h, const char*) { return E(h)->next_node++; }
RIFT_API rift_node rift_graph_add_output(rift_engine* h) { return E(h)->next_node++; }
RIFT_API void      rift_graph_connect(rift_engine*, rift_node, rift_node) {}
RIFT_API void      rift_graph_remove(rift_engine*, rift_node) {}
RIFT_API void      rift_graph_reorder(rift_engine*, rift_node, int32_t) {}
RIFT_API void      rift_graph_clear(rift_engine*) {}

RIFT_API void  rift_param_set_value(rift_engine*, rift_node, const char*, float) {}
RIFT_API void  rift_param_set_binding(rift_engine*, rift_node, const char*, const rift_binding*) {}
RIFT_API float rift_param_get_value(rift_engine*, rift_node, const char*) { return 0.f; }

RIFT_API int32_t rift_project_save(rift_engine*, const char*, const char*) { return 1; }
RIFT_API int32_t rift_project_load(rift_engine*, const char*) { return 1; }

RIFT_API void rift_set_preview_scale(rift_engine*, rift_preview_scale) {}
RIFT_API void rift_request_redraw(rift_engine*) {}

RIFT_API void rift_export_start(rift_engine*, const rift_export_spec*, rift_export_cb cb, void* u) {
    if (cb) cb(100, 1, u);
}
RIFT_API void rift_export_cancel(rift_engine*) {}

RIFT_API void        rift_get_stats(rift_engine* h, rift_stats* out) { if(out) *out = E(h)->stats; }
RIFT_API const char* rift_last_error(rift_engine* h) { return E(h)->err.c_str(); }
RIFT_API int32_t     rift_effect_count(rift_engine*) { return 0; }
RIFT_API const char* rift_effect_id(rift_engine*, int32_t) { return ""; }

} // extern "C"

#endif // RIFT_WITH_RHI
