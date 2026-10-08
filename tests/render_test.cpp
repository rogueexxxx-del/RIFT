// QRhi offscreen render smoke test - de-risks the whole GPU path before it
// goes into rhi_context.cpp. Renders a fullscreen shader (uniform-block,
// audio-reactive) to an offscreen RGBA texture via QRhi (D3D11), reads it
// back, asserts it's non-black, and writes a PPM you can open.
//
// No window, no threading - same offscreen-readback approach we used to
// validate everything else. If this passes, QRhi + QShaderBaker + D3D11 are
// good on this machine and the render core just needs wiring.
#include <QGuiApplication>
#include <QFile>
#include <rhi/qrhi.h>
#include <cstdio>
#include <cstring>
#include <vector>
#include <cmath>

#ifndef SHADER_QSB_DIR
#define SHADER_QSB_DIR "."
#endif

// Load a precompiled .qsb (built by qsb.exe) -> QShader (public API).
static QShader loadQsb(const char* name) {
    QFile f(QString(SHADER_QSB_DIR "/") + name);
    if (!f.open(QIODevice::ReadOnly)) return {};
    return QShader::fromSerialized(f.readAll());
}

int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);

    // D3D11 offscreen (no swapchain/window)
    QRhiD3D11InitParams params;
    QRhi* rhi = QRhi::create(QRhi::D3D11, &params);
    if (!rhi) { std::puts("QRhi D3D11 create FAILED"); return 1; }
    std::printf("QRhi backend: %s\n", rhi->backendName());

    const int W = 640, H = 360;

    QRhiTexture* tex = rhi->newTexture(QRhiTexture::RGBA8, QSize(W, H), 1,
        QRhiTexture::RenderTarget | QRhiTexture::UsedAsTransferSource);
    tex->create();
    QRhiTextureRenderTarget* rt = rhi->newTextureRenderTarget({ tex });
    QRhiRenderPassDescriptor* rp = rt->newCompatibleRenderPassDescriptor();
    rt->setRenderPassDescriptor(rp);
    rt->create();

    // uniform buffer (std140: float,float,vec2 -> 16 bytes)
    QRhiBuffer* ubuf = rhi->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::UniformBuffer, 16);
    ubuf->create();

    QRhiShaderResourceBindings* srb = rhi->newShaderResourceBindings();
    srb->setBindings({
        QRhiShaderResourceBinding::uniformBuffer(0,
            QRhiShaderResourceBinding::FragmentStage, ubuf),
    });
    srb->create();

    QShader vs = loadQsb("fullscreen.vert.qsb");
    if (!vs.isValid()) { std::puts("load fullscreen.vert.qsb FAILED"); return 1; }
    QShader fs = loadQsb("test.frag.qsb");
    if (!fs.isValid()) { std::puts("load test.frag.qsb FAILED"); return 1; }

    QRhiGraphicsPipeline* ps = rhi->newGraphicsPipeline();
    ps->setShaderStages({
        { QRhiShaderStage::Vertex,   vs },
        { QRhiShaderStage::Fragment, fs },
    });
    QRhiVertexInputLayout inputLayout;          // no vertex buffers
    ps->setVertexInputLayout(inputLayout);
    ps->setShaderResourceBindings(srb);
    ps->setRenderPassDescriptor(rp);
    if (!ps->create()) { std::puts("pipeline create FAILED"); return 1; }

    // render one frame offscreen
    QRhiCommandBuffer* cb = nullptr;
    if (rhi->beginOffscreenFrame(&cb) != QRhi::FrameOpSuccess) {
        std::puts("beginOffscreenFrame FAILED"); return 1;
    }

    QRhiResourceUpdateBatch* u = rhi->nextResourceUpdateBatch();
    float uni[4] = { 1.0f /*time*/, 0.5f /*bass*/, float(W), float(H) };
    u->updateDynamicBuffer(ubuf, 0, 16, uni);

    cb->beginPass(rt, QColor(0, 0, 0, 255), { 1.0f, 0 }, u);
    cb->setGraphicsPipeline(ps);
    cb->setViewport({ 0, 0, float(W), float(H) });
    cb->setShaderResources(srb);
    cb->draw(3);                                 // fullscreen triangle

    QRhiReadbackResult rb;
    bool done = false;
    rb.completed = [&done]{ done = true; };
    QRhiResourceUpdateBatch* rbatch = rhi->nextResourceUpdateBatch();
    rbatch->readBackTexture({ tex }, &rb);
    cb->endPass(rbatch);

    rhi->endOffscreenFrame();                    // blocks until GPU done

    if (rb.data.isEmpty()) { std::puts("readback EMPTY"); return 1; }

    // check non-black + write PPM
    const uchar* px = reinterpret_cast<const uchar*>(rb.data.constData());
    long sum = 0; for (int i = 0; i < W * H * 4; i += 4) sum += px[i] + px[i+1] + px[i+2];
    double mean = double(sum) / (W * H * 3);
    std::printf("rendered mean brightness: %.1f (expect > 10)\n", mean);

    FILE* f = std::fopen("render_test.ppm", "wb");
    if (f) {
        std::fprintf(f, "P6\n%d %d\n255\n", W, H);
        for (int i = 0; i < W * H; ++i)
            std::fputc(px[i*4], f), std::fputc(px[i*4+1], f), std::fputc(px[i*4+2], f);
        std::fclose(f);
        std::puts("wrote render_test.ppm");
    }

    delete ps; delete srb; delete ubuf; delete rp; delete rt; delete tex; delete rhi;
    return mean > 10.0 ? 0 : 2;
}
