// Overlay/ladder export proof: render graph frames -> readback -> Exporter ->
// probed hardware encoder -> mp4 with watermark + per-frame lyrics.
//
// Mirrors export_test.cpp, but exercises the parts that plain export does not:
// the encoder ladder's real-open probe and QPainter overlay compositing.
// Validate the result with ffprobe.
#include <QGuiApplication>
#include "rhi_context.hpp"
#include "render_graph.hpp"
#include "exporter.hpp"
#include "parameter_graph.hpp"
#include "rift/rift_types.h"
#include <vector>
#include <string>
#include <cstdio>

#ifndef SHADER_QSB_DIR
#define SHADER_QSB_DIR "."
#endif

static rift::Param stat(float v) {
    rift::Param p{}; p.value = v; p.min_v = -1e9f; p.max_v = 1e9f;
    p.bind.channel = -1; return p;
}

int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);
    rift::RhiContext rhi(SHADER_QSB_DIR);
    if (!rhi.valid()) { std::puts("RhiContext INVALID"); return 1; }

    const int W = 640, H = 360, FPS = 30, N = 45;

    std::vector<uint8_t> img(W * H * 4);
    for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) {
        int i = (y*W+x)*4;
        img[i]=uint8_t(x*255/W); img[i+1]=uint8_t(y*255/H);
        img[i+2]=uint8_t(((x/40+y/40)&1)?200:40); img[i+3]=255;
    }
    rift::TexId media = rhi.uploadImage(img.data(), W, H);

    rift::RenderGraph g;
    uint32_t src = g.addSource(), fx = g.addEffect("ascii");
    g.connect(src, fx);
    g.setParams(fx, { stat(120.f), stat(0.f), stat(1.1f), stat(1.f),
                      stat(0.9f), stat(0.f) });
    g.build(rhi);

    rift_export_spec spec{};
    spec.width = W; spec.height = H; spec.fps = FPS;
    spec.quality = RIFT_EXPORT_YOUTUBE;
    spec.out_path = (argc > 1) ? argv[1] : "export_hybrid_out.mp4";
    spec.audio_path = (argc > 2) ? argv[2] : nullptr;
    spec.font_dir = (argc > 3) ? argv[3] : nullptr;
    spec.total_frames = N;

    rift::Exporter ex;
    if (!ex.open(spec)) {
        std::printf("open FAILED: %s\n", ex.error());
        return 1;
    }
    std::printf("encoder selected: %s\n", ex.encoder().c_str());

    std::vector<uint8_t> rgba;
    for (int i = 0; i < N; ++i) {
        rift_channel_frame cf{};
        cf.ch[RIFT_CH_BASS]  = 0.5f + 0.5f * float(i) / N;
        cf.ch[RIFT_CH_DRUMS] = (i % 15 < 3) ? 1.0f : 0.1f;
        rift::TexId scene = g.execute(rhi, cf, media, double(i)/FPS, W, H);
        if (!rhi.readback(scene, W, H, rgba)) { std::puts("readback FAILED"); return 1; }

        // per-frame overlay text, on for half the frames
        const std::string text = (i / 15) % 2 == 0
            ? ("FRAME " + std::to_string(i)) : std::string();
        if (!ex.writeFrame(rgba.data(), text.empty() ? nullptr : text.c_str())) {
            std::printf("writeFrame %d FAILED: %s\n", i, ex.error()); return 1;
        }
    }
    if (!ex.finish()) { std::printf("finish FAILED: %s\n", ex.error()); return 1; }

    std::printf("wrote %s (%d frames @ %dfps, encoder %s)\nPASS\n",
                spec.out_path, N, FPS, ex.encoder().c_str());
    return 0;
}
