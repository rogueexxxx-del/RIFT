// Chunk E proof: libav decodes real media -> RhiContext texture -> graph.
// Decodes a frame from argv[1], runs it through source->ascii, reads back.
// Skips (pass) when no path is given so CI without a sample stays green.
//
// Usage: rift_media_decode_test [media.mp4|image.png]
#include <QGuiApplication>
#include "rhi_context.hpp"
#include "render_graph.hpp"
#include "media_decoder.hpp"
#include "rift/rift_types.h"
#include <thread>
#include <chrono>
#include <vector>
#include <cstdio>

#ifndef SHADER_QSB_DIR
#define SHADER_QSB_DIR "."
#endif

static rift::Param stat(float v) {
    rift::Param p{}; p.value = v; p.min_v = -1e9f; p.max_v = 1e9f;
    p.bind.channel = -1;
    return p;
}

int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);
    if (argc < 2) { std::puts("no media path given; SKIP (pass)"); return 0; }

    rift::RhiContext rhi(SHADER_QSB_DIR);
    if (!rhi.valid()) { std::puts("RhiContext INVALID"); return 1; }

    rift::MediaDecoder dec(&rhi);
    dec.open(argv[1]);
    for (int i = 0; i < 200 && !dec.ready(); ++i)
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    if (!dec.ready()) { std::puts("decoder not ready"); return 1; }

    int w = 0, h = 0; dec.size(w, h);
    std::printf("media: %dx%d  video=%d  fps=%.2f  dur=%.2fs\n",
                w, h, (int)dec.isVideo(), dec.fps(), dec.duration());
    if (w <= 0 || h <= 0) { std::puts("open failed (0x0) - unsupported/bad file"); return 1; }

    // give the decode thread a moment to stage a frame, then pull it
    rift::TexId media = 0;
    for (int i = 0; i < 100 && !media; ++i) {
        media = dec.frameForPlayhead(0.0);
        if (!media) std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    if (!media) { std::puts("no decoded frame arrived"); return 1; }

    rift::RenderGraph g;
    uint32_t src = g.addSource();
    uint32_t fx  = g.addEffect("ascii");
    g.connect(src, fx);
    g.setParams(fx, { stat(160.f), stat(0.f), stat(1.1f), stat(1.f), stat(0.9f), stat(0.f) });
    g.build(rhi);

    rift_channel_frame cf{};
    cf.ch[RIFT_CH_BASS] = 0.3f; cf.ch[RIFT_CH_DRUMS] = 0.4f;

    rift::TexId out = g.execute(rhi, cf, media, 0.0, w, h);
    std::vector<uint8_t> px;
    if (!rhi.readback(out, w, h, px) || px.empty()) { std::puts("readback FAILED"); return 1; }

    long sum = 0; for (size_t i = 0; i < px.size(); i += 4) sum += px[i]+px[i+1]+px[i+2];
    double mean = double(sum) / (double(w) * h * 3);
    std::printf("decoded->ascii render mean: %.2f\n", mean);

    FILE* f = std::fopen("media_decode.ppm", "wb");
    if (f) { std::fprintf(f, "P6\n%d %d\n255\n", w, h);
        for (int i = 0; i < w*h; ++i)
            std::fputc(px[i*4], f), std::fputc(px[i*4+1], f), std::fputc(px[i*4+2], f);
        std::fclose(f); std::puts("wrote media_decode.ppm"); }

    if (mean <= 0.5) { std::puts("FAIL: ~black output"); return 1; }
    std::puts("PASS");
    return 0;
}
