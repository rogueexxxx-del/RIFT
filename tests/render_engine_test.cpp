// Renders a REAL ported engine shader (ascii) through QRhi onto an input
// image, with the engine's Engine+Params UBO layout, and reads it back.
// Proves the ported shaders + UBO scheme work on the GPU before wiring the
// full graph. Writes engine_render.ppm.
//
// Usage: rift_render_engine_test <image.png>
#include <QGuiApplication>
#include <QFile>
#include <rhi/qrhi.h>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <vector>

#ifndef SHADER_QSB_DIR
#define SHADER_QSB_DIR "."
#endif

static QShader loadQsb(const char* name) {
    QFile f(QString(SHADER_QSB_DIR "/") + name);
    if (!f.open(QIODevice::ReadOnly)) return {};
    return QShader::fromSerialized(f.readAll());
}

// Engine UBO - fixed 7*vec4 layout matching shaders_qrhi preamble.
struct EngineUBO {
    float timeRes[4];   // time, _, resX, resY
    float A[4];         // bass, melody, highs, drums
    float B[4];         // transient, bpm, centroid, playhead
    float C[4];         // kick, snare, _, _
    float bg[4];        // color_bg.rgb, palette_active
    float fg1[4];
    float fg2[4];
};

int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);

    QRhiD3D11InitParams params;
    QRhi* rhi = QRhi::create(QRhi::D3D11, &params);
    if (!rhi) { std::puts("QRhi create FAILED"); return 1; }

    // --- synthetic input image (gradient + bands) -> texture (binding 2) ---
    // No file load (avoids the missing PNG plugin); gives the ascii shader
    // varied luminance to quantize.
    const int W = 640, H = 360;
    std::vector<unsigned char> imgBytes(W * H * 4);
    for (int y = 0; y < H; ++y)
        for (int x = 0; x < W; ++x) {
            int i = (y * W + x) * 4;
            imgBytes[i + 0] = (unsigned char)(x * 255 / W);           // R ramp
            imgBytes[i + 1] = (unsigned char)(y * 255 / H);           // G ramp
            imgBytes[i + 2] = (unsigned char)(((x / 40 + y / 40) & 1) ? 200 : 40); // checker
            imgBytes[i + 3] = 255;
        }

    QRhiTexture* inTex = rhi->newTexture(QRhiTexture::RGBA8, QSize(W, H));
    inTex->create();

    // dummy 1x1 for the ascii glyph-atlas sampler (binding 5, unused: count=0)
    QRhiTexture* dummy = rhi->newTexture(QRhiTexture::RGBA8, QSize(1, 1));
    dummy->create();

    QRhiSampler* samp = rhi->newSampler(QRhiSampler::Linear, QRhiSampler::Linear,
        QRhiSampler::None, QRhiSampler::ClampToEdge, QRhiSampler::ClampToEdge);
    samp->create();

    // --- output target ---
    QRhiTexture* outTex = rhi->newTexture(QRhiTexture::RGBA8, QSize(W, H), 1,
        QRhiTexture::RenderTarget | QRhiTexture::UsedAsTransferSource);
    outTex->create();
    QRhiTextureRenderTarget* rt = rhi->newTextureRenderTarget({ outTex });
    QRhiRenderPassDescriptor* rp = rt->newCompatibleRenderPassDescriptor();
    rt->setRenderPassDescriptor(rp);
    rt->create();

    // --- UBOs ---
    QRhiBuffer* engUbo = rhi->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::UniformBuffer, sizeof(EngineUBO));
    engUbo->create();
    QRhiBuffer* parUbo = rhi->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::UniformBuffer, 32); // 2*vec4
    parUbo->create();

    QRhiShaderResourceBindings* srb = rhi->newShaderResourceBindings();
    const auto FS = QRhiShaderResourceBinding::FragmentStage;
    srb->setBindings({
        QRhiShaderResourceBinding::uniformBuffer(0, FS, engUbo),
        QRhiShaderResourceBinding::uniformBuffer(1, FS, parUbo),
        QRhiShaderResourceBinding::sampledTexture(2, FS, inTex, samp),
        QRhiShaderResourceBinding::sampledTexture(5, FS, dummy, samp),
    });
    srb->create();

    QShader vs = loadQsb("engine_fullscreen.vert.qsb");
    QShader fs = loadQsb("ascii.frag.qsb");
    if (!vs.isValid() || !fs.isValid()) { std::puts("load qsb FAILED"); return 1; }

    QRhiGraphicsPipeline* ps = rhi->newGraphicsPipeline();
    ps->setShaderStages({ { QRhiShaderStage::Vertex, vs }, { QRhiShaderStage::Fragment, fs } });
    ps->setVertexInputLayout({});
    ps->setShaderResourceBindings(srb);
    ps->setRenderPassDescriptor(rp);
    if (!ps->create()) { std::puts("pipeline create FAILED"); return 1; }

    // --- frame ---
    QRhiCommandBuffer* cb = nullptr;
    if (rhi->beginOffscreenFrame(&cb) != QRhi::FrameOpSuccess) { std::puts("beginFrame FAILED"); return 1; }

    QRhiResourceUpdateBatch* u = rhi->nextResourceUpdateBatch();

    // upload input image
    QRhiTextureSubresourceUploadDescription sub(imgBytes.data(), int(imgBytes.size()));
    u->uploadTexture(inTex, QRhiTextureUploadDescription({ { 0, 0, sub } }));
    unsigned char black[4] = {0,0,0,255};
    QRhiTextureSubresourceUploadDescription dsub(black, 4);
    u->uploadTexture(dummy, QRhiTextureUploadDescription({ { 0, 0, dsub } }));

    EngineUBO e{};
    e.timeRes[0] = 1.0f; e.timeRes[2] = W; e.timeRes[3] = H;
    e.A[0]=0.3f; e.A[1]=0.2f; e.A[2]=0.15f; e.A[3]=0.45f;   // bass,melody,highs,drums
    e.B[0]=0.0f; e.B[1]=0.4f; e.B[2]=0.5f;  e.B[3]=0.0f;
    // palette off
    u->updateDynamicBuffer(engUbo, 0, sizeof(EngineUBO), &e);

    // ascii params order: columns,char_set,brightness,color_mode,dot_size,u_ascii_count
    float par[8] = { 120.f, 0.f, 1.1f, 1.f, 0.9f, 0.f, 0.f, 0.f };
    u->updateDynamicBuffer(parUbo, 0, 32, par);

    cb->beginPass(rt, QColor(0,0,0,255), { 1.0f, 0 }, u);
    cb->setGraphicsPipeline(ps);
    cb->setViewport({ 0, 0, float(W), float(H) });
    cb->setShaderResources(srb);
    cb->draw(3);

    QRhiReadbackResult rb;
    QRhiResourceUpdateBatch* rbatch = rhi->nextResourceUpdateBatch();
    rbatch->readBackTexture({ outTex }, &rb);
    cb->endPass(rbatch);
    rhi->endOffscreenFrame();

    if (rb.data.isEmpty()) { std::puts("readback EMPTY"); return 1; }
    const uchar* px = reinterpret_cast<const uchar*>(rb.data.constData());
    long sum = 0; for (int i = 0; i < W*H*4; i += 4) sum += px[i]+px[i+1]+px[i+2];
    std::printf("ascii render mean: %.1f\n", double(sum)/(W*H*3));

    FILE* f = std::fopen("engine_render.ppm", "wb");
    if (f) { std::fprintf(f, "P6\n%d %d\n255\n", W, H);
        for (int i=0;i<W*H;++i) std::fputc(px[i*4],f),std::fputc(px[i*4+1],f),std::fputc(px[i*4+2],f);
        std::fclose(f); std::puts("wrote engine_render.ppm"); }

    delete rhi;
    return 0;
}
