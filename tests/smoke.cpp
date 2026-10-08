// Phase 0 smoke test: exercises the C ABI surface end-to-end against the
// stub engine. Proves the header + build + link are sound before any GPU
// code exists. Grows into the golden-diff harness in P1.
#include "rift/rift_engine.h"
#include <cassert>
#include <cstdio>

// Exercises the C ABI surface: create -> load calls (must not crash) ->
// graph ops -> params -> introspection -> destroy. Does NOT assert on
// optional-subsystem readiness (media needs FFmpeg, audio needs an analysis
// blob) - those are environment-dependent and covered by the parity gate.
int main() {
    rift_engine* e = rift_create(nullptr, "shaders", "cache");
    assert(e);

    rift_load_media(e, "x.png");           // must not crash (may not be "ready")
    rift_load_audio(e, "x.wav", nullptr);

    rift_node src = rift_graph_add_source(e);
    rift_node gen = rift_graph_add_effect(e, "ascii");
    rift_node out = rift_graph_add_output(e);
    rift_graph_connect(e, src, gen);
    rift_graph_connect(e, gen, out);
    assert(src && gen && out && gen != src);

    rift_binding b{ RIFT_CH_KICK, 6.0f, 0.f, 1.f, RIFT_CURVE_EXP, 0.3f, 0.8f, 0 };
    rift_param_set_binding(e, gen, "ht_scale", &b);

    rift_channel_frame cf{};
    rift_channels(e, &cf);

    rift_stats s{};
    rift_get_stats(e, &s);

    rift_destroy(e);
    std::puts("RIFT smoke OK");
    return 0;
}
