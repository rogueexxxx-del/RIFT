// Chunk D proof (on-screen preview): opens a real window and presents the
// live-rendered ascii shader via the QRhi swapchain, animating a channel.
// Interactive - run it and watch. Close the window to exit.
#include <QGuiApplication>
#include <QWindow>
#include <QElapsedTimer>
#include "rhi_context.hpp"
#include "render_graph.hpp"
#include "parameter_graph.hpp"
#include "rift/rift_types.h"
#include <vector>
#include <cmath>

#ifndef SHADER_QSB_DIR
#define SHADER_QSB_DIR "."
#endif

static rift::Param stat(float v) {
    rift::Param p{}; p.value = v; p.min_v = -1e9f; p.max_v = 1e9f;
    p.bind.channel = -1; return p;
}

class PreviewWindow : public QWindow {
public:
    PreviewWindow() { setSurfaceType(QSurface::Direct3DSurface); resize(1280, 720); }

    void exposeEvent(QExposeEvent*) override {
        if (isExposed() && !inited_) init_();
        if (isExposed()) requestUpdate();
    }
    void resizeEvent(QResizeEvent*) override { if (inited_) rhi_.resizeSwapchain(); }
    bool event(QEvent* e) override {
        if (e->type() == QEvent::UpdateRequest) { render_(); return true; }
        return QWindow::event(e);
    }

private:
    void init_() {
        if (!rhi_.valid() || !rhi_.initSwapchain(this)) { qWarning("swapchain init failed"); return; }
        const int W = 1280, H = 720;
        std::vector<uint8_t> img(W * H * 4);
        for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) {
            int i = (y*W+x)*4;
            img[i]=uint8_t(x*255/W); img[i+1]=uint8_t(y*255/H);
            img[i+2]=uint8_t(((x/60+y/60)&1)?200:40); img[i+3]=255;
        }
        media_ = rhi_.uploadImage(img.data(), W, H);
        src_ = g_.addSource(); fx_ = g_.addEffect("ascii"); g_.connect(src_, fx_);
        g_.setParams(fx_, { stat(160.f), stat(0.f), stat(1.15f), stat(1.f), stat(0.9f), stat(0.f) });
        g_.build(rhi_);
        clock_.start();
        inited_ = true;
    }
    void render_() {
        if (!inited_) return;
        double t = clock_.elapsed() / 1000.0;
        rift_channel_frame cf{};
        cf.ch[RIFT_CH_BASS]  = 0.5f + 0.5f * float(std::sin(t * 2.0));
        cf.ch[RIFT_CH_HIGHS] = 0.5f + 0.5f * float(std::sin(t * 5.0));
        cf.ch[RIFT_CH_DRUMS] = (std::fmod(t, 0.5) < 0.08) ? 1.0f : 0.1f;
        rift::TexId scene = g_.execute(rhi_, cf, media_, t, 1280, 720);
        rhi_.present(scene);
        requestUpdate();                    // continuous animation
    }

    rift::RhiContext rhi_{ SHADER_QSB_DIR };
    rift::RenderGraph g_;
    rift::TexId media_ = 0;
    uint32_t src_ = 0, fx_ = 0;
    QElapsedTimer clock_;
    bool inited_ = false;
};

int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);
    PreviewWindow w;
    w.setTitle("RIFT preview - chunk D");
    w.show();
    return app.exec();
}
