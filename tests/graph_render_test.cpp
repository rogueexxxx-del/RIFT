// End-to-end chunk-B proof: RenderGraph drives RhiContext on the GPU.
// Uploads a synthetic image, builds source->ascii, resolves the EngineUBO +
// params, executes the graph, reads the result back. Proves rhi_context.cpp +
// render_graph.cpp + engine_ubo.hpp all agree on the GPU.
//
// Writes graph_render.ppm. Non-zero mean = the pass actually ran.
#include <QGuiApplication>
#include "rhi_context.hpp"
#include "render_graph.hpp"
#include "parameter_graph.hpp"
#include "rift/rift_types.h"
#include <vector>
#include <cstdio>

#ifndef SHADER_QSB_DIR
#define SHADER_QSB_DIR "."
#endif

static rift::Param stat(float v) {
    rift::Param p{}; p.value = v; p.min_v = -1e9f; p.max_v = 1e9f;
    p.bind.channel = -1;                 // static, no channel
    return p;
}

int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);

    rift::RhiContext rhi(SHADER_QSB_DIR);
    if (!rhi.valid()) { std::puts("RhiContext INVALID"); return 1; }

    const int W = 640, H = 360;
    std::vector<uint8_t> img(W * H * 4);
    for (int y = 0; y < H; ++y)
        for (int x = 0; x < W; ++x) {
            int i = (y * W + x) * 4;
            img[i+0] = uint8_t(x * 255 / W);
            img[i+1] = uint8_t(y * 255 / H);
            img[i+2] = uint8_t(((x/40 + y/40) & 1) ? 200 : 40);
            img[i+3] = 255;
        }
    rift::TexId media = rhi.uploadImage(img.data(), W, H);

    rift::RenderGraph g;
    uint32_t src = g.addSource();
    uint32_t fx  = g.addEffect("ascii");
    g.connect(src, fx);
    // ascii params in layout order: columns,char_set,brightness,color_mode,dot_size,count
    g.setParams(fx, { stat(120.f), stat(0.f), stat(1.1f), stat(1.f), stat(0.9f), stat(0.f) });
    g.build(rhi);

    rift_channel_frame cf{};
    cf.ch[RIFT_CH_BASS]   = 0.3f;
    cf.ch[RIFT_CH_MELODY] = 0.2f;
    cf.ch[RIFT_CH_HIGHS]  = 0.15f;
    cf.ch[RIFT_CH_DRUMS]  = 0.45f;

    rift::TexId out = g.execute(rhi, cf, media, 1.0, W, H);
    if (!out) { std::puts("execute returned 0"); return 1; }

    std::vector<uint8_t> px;
    if (!rhi.readback(out, W, H, px) || px.empty()) { std::puts("readback FAILED"); return 1; }

    long sum = 0; for (int i = 0; i < W*H*4; i += 4) sum += px[i]+px[i+1]+px[i+2];
    double mean = double(sum) / (W*H*3);
    std::printf("graph ascii render mean: %.2f (out tex=%u)\n", mean, out);

    FILE* f = std::fopen("graph_render.ppm", "wb");
    if (f) { std::fprintf(f, "P6\n%d %d\n255\n", W, H);
        for (int i = 0; i < W*H; ++i)
            std::fputc(px[i*4], f), std::fputc(px[i*4+1], f), std::fputc(px[i*4+2], f);
        std::fclose(f); std::puts("wrote graph_render.ppm"); }

    if (mean <= 0.5) { std::puts("FAIL: output ~black, pass did not render"); return 1; }
    std::puts("PASS");
    return 0;
}
