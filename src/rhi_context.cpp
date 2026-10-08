// RhiContext - real QRhi (D3D11) offscreen renderer for the ported engine
// shaders. One offscreen frame per pass (simple + correct; single-frame
// multi-pass batching is a later optimization).
#include "rhi_context.hpp"
#include <QGuiApplication>
#include <QFile>
#include <QByteArray>
#include <QColor>
#include <QSize>
#include <QPoint>
#include <QWindow>
#include <QVarLengthArray>
#include <rhi/qrhi.h>
#include <unordered_map>
#include <cstdio>
#include <cstring>
#include <algorithm>
#include <vector>

namespace rift {

// ---- .layout.json (minimal parse: params count + sampler bindings) ----
struct ShaderLayout {
    int paramCount = 0;
    std::vector<std::pair<std::string,int>> samplers;   // (name, binding)
};

static ShaderLayout parseLayout(const QByteArray& json) {
    // tiny hand parse (avoids QJson dependency churn): count "params" entries
    // and read samplers as [name, binding] pairs.
    ShaderLayout L;
    QByteArray s = json;
    int p = s.indexOf("\"params\"");
    if (p >= 0) {
        int lb = s.indexOf('[', p), rb = s.indexOf(']', lb);
        if (lb >= 0 && rb > lb) {
            QByteArray arr = s.mid(lb + 1, rb - lb - 1);
            // count quoted names
            for (int i = 0; i < arr.size(); ++i) if (arr[i] == '"') ++L.paramCount;
            L.paramCount /= 2;
        }
    }
    int sp = s.indexOf("\"samplers\"");
    if (sp >= 0) {
        int lb = s.indexOf('[', sp), rb = s.lastIndexOf(']');
        QByteArray arr = s.mid(lb + 1, rb - lb - 1);
        // entries like ["u_tex", 2]
        int i = 0;
        while (true) {
            int q1 = arr.indexOf('"', i); if (q1 < 0) break;
            int q2 = arr.indexOf('"', q1 + 1); if (q2 < 0) break;
            QByteArray name = arr.mid(q1 + 1, q2 - q1 - 1);
            int comma = arr.indexOf(',', q2);
            int close = arr.indexOf(']', q2);
            int numStart = comma + 1;
            QByteArray num = arr.mid(numStart, close - numStart).trimmed();
            L.samplers.emplace_back(name.toStdString(), num.toInt());
            i = close + 1;
        }
    }
    return L;
}

struct Pipe {
    QRhiGraphicsPipeline* ps = nullptr;
    QRhiShaderResourceBindings* srb = nullptr;   // template (dummy input)
    ShaderLayout layout;
};

struct TexEntry {
    QRhiTexture* tex = nullptr;
    QRhiTextureRenderTarget* rt = nullptr;
    QRhiRenderPassDescriptor* rp = nullptr;
    int w = 0, h = 0;
};

struct RhiContext::Impl {
    std::string qsbDir;
    QRhi* rhi = nullptr;
    bool  owns_rhi = true;      // false when adopted from Qt Quick
    QRhiSampler* sampler = nullptr;
    QRhiTexture* dummy = nullptr;
    // Audio made visible to shaders. audioTex is 512x2: row 0 spectrum, row 1
    // waveform, both stored 0..1. spectroTex is that spectrum stacked over
    // time, newest row first, which is what a waterfall draws.
    QRhiTexture* audioTex   = nullptr;
    QRhiTexture* spectroTex = nullptr;
    QRhiTexture* lutTex     = nullptr;   // 256x8 RGBA8 visualizer color tables
    QByteArray   lutData;                // 256*8*4 bytes
    // Last finished frame, for shaders declaring u_feedback_tex. Sized to the
    // frame and rebuilt when that changes.
    QRhiTexture* prevTex = nullptr;
    int          prevW = 0, prevH = 0;
    float        scopeTrigger = 0.f;   // published to shaders via EngineUBO.C[2]
    int          spectroRow = 0;       // ring write position -> EngineUBO.C[3]
    QByteArray   audioRows;     // 1024*2 bytes
    QByteArray   spectroRows;   // 1024*256 bytes, scrolled each frame
    QRhiBuffer* engUbo = nullptr;
    static constexpr int kMaxPasses = 32;
    QRhiBuffer* parUbos[kMaxPasses] = {};
    int curPass = 0;
    // Persistent RGBA8 render-pass descriptor kept alive for the process:
    // every pipeline is built against it, and all RGBA8 targets are
    // structurally compatible, so it stays valid for every beginPass.
    QRhiTexture* tmplTex = nullptr;
    QRhiTextureRenderTarget* tmplRt = nullptr;
    QRhiRenderPassDescriptor* tmplRp = nullptr;
    std::unordered_map<uint32_t, TexEntry> textures;
    // Textures released by callers but not yet destroyed. Kept for a few frames
    // so nothing outside this class is still pointing at them.
    struct Retired { TexEntry e; uint64_t frame; };
    std::vector<Retired> retired;
    uint64_t frameCounter = 0;
    static constexpr uint64_t kRetireFrames = 3;

    // Destroy anything retired at least kRetireFrames ago.
    void drainRetired() {
        for (size_t i = 0; i < retired.size();) {
            if (frameCounter - retired[i].frame >= kRetireFrames) {
                delete retired[i].e.rt;
                delete retired[i].e.rp;
                delete retired[i].e.tex;
                retired[i] = retired.back();
                retired.pop_back();
            } else {
                ++i;
            }
        }
    }
    std::unordered_map<std::string, Pipe> pipes;
    uint32_t nextTex = 1;
    uint32_t nextPipe = 1;
    std::unordered_map<uint32_t, std::string> pipeIdToShader;

    QRhiCommandBuffer* cb = nullptr;
    // Outstanding beginFrame() calls. Frames nest: the outermost owns the
    // submit, inner ones record into the same command buffer.
    int frameDepth = 0;
    QRhiCommandBuffer* extCb = nullptr;   // Qt Quick's cb (adopted-QRhi mode)
    bool external = false;                // adopted QRhi: never open own frames
    bool pendingDummy = false;            // dummy upload deferred to first frame
    std::vector<QRhiShaderResourceBindings*> frameSrbs;   // freed at endFrame

    // Submit a resource-update batch. Inside Qt Quick's frame we must reuse
    // its command buffer; standalone we open a short offscreen frame. Callers
    // must not care which.
    template <class F>
    bool withUpdates(F&& fill) {
        if (extCb) {                        // recording inside someone's frame
            auto* u = rhi->nextResourceUpdateBatch();
            fill(u);
            extCb->resourceUpdate(u);
            return true;
        }
        if (frameDepth > 0 && cb) {         // join the frame already open
            auto* u = rhi->nextResourceUpdateBatch();
            fill(u);
            cb->resourceUpdate(u);
            return true;
        }
        if (rhi->beginOffscreenFrame(&cb) != QRhi::FrameOpSuccess) return false;
        auto* u = rhi->nextResourceUpdateBatch();
        fill(u);
        cb->resourceUpdate(u);
        rhi->endOffscreenFrame();
        cb = nullptr;
        return true;
    }

    // Swapchain (on-screen preview)
    QWindow* win = nullptr;
    QRhiSwapChain* sc = nullptr;
    QRhiRenderPassDescriptor* scRp = nullptr;
    QRhiGraphicsPipeline* blitPs = nullptr;
    QRhiShaderResourceBindings* blitTmpl = nullptr;
    std::unordered_map<uint32_t, QRhiShaderResourceBindings*> blitSrbs;  // per scene tex

    QShader loadQsb(const std::string& name) {
        QFile f(QString::fromStdString(qsbDir + "/" + name));
        if (!f.open(QIODevice::ReadOnly)) return {};
        return QShader::fromSerialized(f.readAll());
    }
    QByteArray loadFile(const std::string& name) {
        QFile f(QString::fromStdString(qsbDir + "/" + name));
        if (!f.open(QIODevice::ReadOnly)) return {};
        return f.readAll();
    }
};

RhiContext::RhiContext(std::string qsbDir) : d_(std::make_unique<Impl>()) {
    d_->qsbDir = std::move(qsbDir);
    QRhiD3D11InitParams params;
    // EnableTimestamps turns on GPU timer queries, which is the only way to
    // tell "this shader is heavy" from "the CPU is not feeding the GPU". Costs
    // nothing when nobody reads the result. Only settable where we create the
    // QRhi - in the Qt Quick path the device is Quick's, so gpuLastMs() there
    // reports 0 and callers must treat it as "unknown", not "instant".
    d_->rhi = QRhi::create(QRhi::D3D11, &params, QRhi::EnableTimestamps);
    d_->owns_rhi = true;
    if (!d_->rhi) { std::puts("[RhiContext] QRhi D3D11 create FAILED"); return; }
    initResources_();
}

// Adopt Qt Quick's QRhi. A QRhiTexture belongs to the device that made it, so
// sharing engine output with the scene graph is only possible on one device.
RhiContext::RhiContext(std::string qsbDir, void* rhi) : d_(std::make_unique<Impl>()) {
    d_->qsbDir = std::move(qsbDir);
    d_->rhi = static_cast<QRhi*>(rhi);
    d_->owns_rhi = false;
    d_->external = true;
    if (!d_->rhi) { std::puts("[RhiContext] adopted QRhi is null"); return; }
    initResources_();
}

void* RhiContext::rhiHandle() const { return d_->rhi; }

void* RhiContext::textureHandle(TexId id) const {
    auto it = d_->textures.find(id);
    return it == d_->textures.end() ? nullptr : it->second.tex;
}

void RhiContext::initResources_() {
    d_->sampler = d_->rhi->newSampler(QRhiSampler::Linear, QRhiSampler::Linear,
        QRhiSampler::None, QRhiSampler::ClampToEdge, QRhiSampler::ClampToEdge);
    d_->sampler->create();
    d_->dummy = d_->rhi->newTexture(QRhiTexture::RGBA8, QSize(1, 1));
    d_->dummy->create();
    d_->engUbo = d_->rhi->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::UniformBuffer, sizeof(EngineUBO));
    d_->engUbo->create();
    for (int i = 0; i < Impl::kMaxPasses; ++i) {
        d_->parUbos[i] = d_->rhi->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::UniformBuffer, 128);
        d_->parUbos[i]->create();
    }

    // template render target -> compatible RGBA8 render-pass descriptor (kept)
    d_->tmplTex = d_->rhi->newTexture(QRhiTexture::RGBA8, QSize(8, 8), 1,
        QRhiTexture::RenderTarget);
    d_->tmplTex->create();
    d_->tmplRt = d_->rhi->newTextureRenderTarget({ d_->tmplTex });
    d_->tmplRp = d_->tmplRt->newCompatibleRenderPassDescriptor();
    d_->tmplRt->setRenderPassDescriptor(d_->tmplRp);
    d_->tmplRt->create();

    // Upload the dummy once. Safe in both modes: construction happens outside
    // any active frame (beforeSynchronizing), so an offscreen frame is legal.
    d_->withUpdates([this](QRhiResourceUpdateBatch* u) {
        unsigned char black[4] = {0,0,0,255};
        QRhiTextureSubresourceUploadDescription sub(black, 4);
        u->uploadTexture(d_->dummy, QRhiTextureUploadDescription({ { 0, 0, sub } }));
    });
    initDefaultLut_();
    warmPipelines();
}

RhiContext::~RhiContext() {
    if (!d_->rhi) return;
    // Everything is going away now, so retired textures can go immediately.
    for (auto& r : d_->retired) { delete r.e.rt; delete r.e.rp; delete r.e.tex; }
    d_->retired.clear();
    for (auto& [id, p] : d_->pipes) { delete p.ps; delete p.srb; }
    for (auto& [id, t] : d_->textures) { delete t.rt; delete t.rp; delete t.tex; }
    for (auto& [id, s] : d_->blitSrbs) delete s;
    delete d_->blitPs; delete d_->blitTmpl;
    delete d_->sc; delete d_->scRp;
    delete d_->tmplRt; delete d_->tmplRp; delete d_->tmplTex;
    delete d_->audioTex; delete d_->spectroTex; delete d_->prevTex; delete d_->lutTex;
    delete d_->engUbo;
    for (int i = 0; i < Impl::kMaxPasses; ++i) delete d_->parUbos[i];
    delete d_->dummy; delete d_->sampler;
    if (d_->owns_rhi) delete d_->rhi;   // borrowed from Qt Quick: not ours
}

bool RhiContext::valid() const { return d_->rhi != nullptr; }

int RhiContext::paramCount(const std::string& id) {
    pipeline(id);
    auto it = d_->pipes.find(id);
    return it == d_->pipes.end() ? 0 : it->second.layout.paramCount;
}
// GPU time for the last COMPLETED frame, in ms; 0 when unavailable.
//
// Not the frame just submitted: timer queries resolve a frame or two later, so
// this necessarily lags. That is fine for a running average and wrong for
// attributing a single hitch.
double RhiContext::gpuLastMs() const {
    if (!d_->cb) return 0.0;
    const double ns = double(d_->cb->lastCompletedGpuTime());
    return ns > 0.0 ? ns * 1000.0 : 0.0;   // seconds -> ms
}

const std::vector<std::pair<std::string,int>>& RhiContext::samplers(const std::string& id) {
    static std::vector<std::pair<std::string,int>> empty;
    pipeline(id);
    auto it = d_->pipes.find(id);
    return it == d_->pipes.end() ? empty : it->second.layout.samplers;
}

static QRhiShaderResourceBindings* buildSrb(QRhi* rhi, QRhiBuffer* eng,
        QRhiBuffer* par, const ShaderLayout& L, QRhiTexture* input,
        QRhiTexture* dummy, QRhiSampler* samp, QRhiTexture* second = nullptr,
        QRhiTexture* audio = nullptr, QRhiTexture* spectro = nullptr,
        QRhiTexture* prev = nullptr, QRhiTexture* lut = nullptr) {
    const auto FS = QRhiShaderResourceBinding::FragmentStage;
    QVarLengthArray<QRhiShaderResourceBinding, 8> b;
    b.append(QRhiShaderResourceBinding::uniformBuffer(0, FS, eng));
    b.append(QRhiShaderResourceBinding::uniformBuffer(1, FS, par));
    for (auto& [name, binding] : L.samplers) {
        // Matched by NAME, not binding number: composite.frag's u_under and
        // oscilloscope.frag's u_audio_texture both sit at binding 3, so the
        // number alone cannot say which texture a shader is asking for.
        QRhiTexture* t = dummy;
        if      (name == "u_audio_texture") t = audio   ? audio   : dummy;
        else if (name == "u_spectro_tex")   t = spectro ? spectro : dummy;
        // Previous finished frame. Falls back to the dummy on frame 0 and any
        // time the size just changed, so a feedback shader starts from black
        // rather than from a stale differently-sized texture.
        else if (name == "u_feedback_tex")  t = prev    ? prev    : dummy;
        else if (name == "u_lut_tex")       t = lut     ? lut     : dummy;
        else if (binding == 2)              t = input;
        else if (binding == 3 && second)    t = second;
        b.append(QRhiShaderResourceBinding::sampledTexture(binding, FS, t, samp));
    }
    auto* srb = rhi->newShaderResourceBindings();
    srb->setBindings(b.cbegin(), b.cend());
    srb->create();
    return srb;
}

// Publish the current audio window so shaders can draw it.
//
// Called once per frame from the render thread, whether or not any effect
// samples it - the cost is one 1 KB and one 512 B upload, and gating it on
// "does the chain contain a scope" would have to re-scan the chain anyway.
void RhiContext::uploadAudio(const float* wave, int nwave,
                             const float* spec, int nspec, float trigger,
                             const float* raw_spec,
                             const float* vecX, const float* vecY) {
    if (!d_->rhi) return;
    d_->scopeTrigger = trigger;
    constexpr int kW = 1024, kHist = 256;

    if (!d_->audioTex) {
        d_->audioTex = d_->rhi->newTexture(QRhiTexture::R8, QSize(kW, 4));
        if (!d_->audioTex->create()) { delete d_->audioTex; d_->audioTex = nullptr; return; }
        d_->spectroTex = d_->rhi->newTexture(QRhiTexture::R8, QSize(kW, kHist));
        if (!d_->spectroTex->create()) { delete d_->spectroTex; d_->spectroTex = nullptr; }
        d_->audioRows.fill(0, kW * 4);
        // One row now: the ring uploads a single row per frame.
        d_->spectroRows.fill(0, kW);
    }

    auto sample = [](const float* src, int n, int i) {
        // Whatever length the caller supplied, resampled to kW.
        if (!src || n <= 0) return 0.f;
        return src[std::min(n - 1, i * n / kW)];
    };
    auto toByte = [](float v) {
        return uchar(std::clamp(int(v * 255.f + 0.5f), 0, 255));
    };

    uchar* rows = reinterpret_cast<uchar*>(d_->audioRows.data());
    for (int x = 0; x < kW; ++x) {
        rows[x]              = toByte(sample(spec, nspec, x));                     // row 0: spectrum
        // Waveform is -1..1 but the texture is unsigned, so it rides at 0.5.
        rows[kW + x]         = toByte(sample(wave, nwave, x) * 0.5f + 0.5f);       // row 1: mono waveform
        rows[kW * 2 + x]     = toByte(sample(vecX, kW, x) * 0.5f + 0.5f);          // row 2: vectorscope X (side)
        rows[kW * 3 + x]     = toByte(sample(vecY, kW, x) * 0.5f + 0.5f);          // row 3: vectorscope Y (mid)
    }
    if (!d_->spectroTex) {
        d_->withUpdates([&](QRhiResourceUpdateBatch* u) {
            QRhiTextureSubresourceUploadDescription sub(d_->audioRows);
            u->uploadTexture(d_->audioTex,
                             QRhiTextureUploadDescription({ { 0, 0, sub } }));
        });
        return;
    }
    // A ring: write ONE row and upload ONLY that row. The spectrogram uses the raw
    // un-smoothed dB array directly from the FFT analyzer.
    d_->spectroRow = (d_->spectroRow + 1) % kHist;
    uchar* srow_data = reinterpret_cast<uchar*>(d_->spectroRows.data());
    const float* spectro_src = raw_spec ? raw_spec : spec;
    for (int x = 0; x < kW; ++x) {
        srow_data[x] = toByte(sample(spectro_src, nspec, x));
    }

    // BOTH textures in ONE batch. Each withUpdates() opens and closes an
    // offscreen frame, and an offscreen frame is a submit followed by a wait
    // for the GPU to drain. Doing this twice per frame doubled the stalls for
    // no reason - during an export that is thousands of avoidable waits.
    d_->withUpdates([&](QRhiResourceUpdateBatch* u) {
        QRhiTextureSubresourceUploadDescription arow(d_->audioRows);
        u->uploadTexture(d_->audioTex, QRhiTextureUploadDescription({ { 0, 0, arow } }));

        QRhiTextureSubresourceUploadDescription srow(d_->spectroRows);
        srow.setSourceSize(QSize(kW, 1));
        srow.setDestinationTopLeft(QPoint(0, d_->spectroRow));
        u->uploadTexture(d_->spectroTex, QRhiTextureUploadDescription({ { 0, 0, srow } }));
    });
}

void RhiContext::initDefaultLut_() {
    constexpr int kLutW = 256, kLutH = 8;
    if (!d_->lutTex) {
        d_->lutTex = d_->rhi->newTexture(QRhiTexture::RGBA8, QSize(kLutW, kLutH));
        if (!d_->lutTex->create()) { delete d_->lutTex; d_->lutTex = nullptr; return; }
        d_->lutData.fill(char(0xFF), kLutW * kLutH * 4);
    }
    uint32_t* p = reinterpret_cast<uint32_t*>(d_->lutData.data());
    for (int x = 0; x < 256; ++x) {
        float t = float(x) / 255.f;
        p[0 * 256 + x] = 0xFFFFFFFF; // osc core
        p[1 * 256 + x] = 0xFFFFFF00; // osc cyan glow
        p[2 * 256 + x] = 0xFF50D0FF; // spec line
        p[3 * 256 + x] = 0xFF0060FF; // spec glow
        uint8_t r = uint8_t(std::clamp(t * 1.5f, 0.f, 1.f) * 255.f);
        uint8_t g = uint8_t(std::clamp((t - 0.3f) * 1.4f, 0.f, 1.f) * 255.f);
        uint8_t b = uint8_t(std::clamp((t - 0.7f) * 3.3f, 0.f, 1.f) * 255.f);
        p[4 * 256 + x] = (255u << 24) | (uint32_t(b) << 16) | (uint32_t(g) << 8) | uint32_t(r);
        p[5 * 256 + x] = p[4 * 256 + x];
        p[6 * 256 + x] = 0xFF60FF60; // vector line
        p[7 * 256 + x] = 0xFF20A020; // vector glow
    }
    d_->withUpdates([&](QRhiResourceUpdateBatch* u) {
        QRhiTextureSubresourceUploadDescription sub(d_->lutData);
        u->uploadTexture(d_->lutTex, QRhiTextureUploadDescription({ { 0, 0, sub } }));
    });
}

void RhiContext::uploadLut(int visIndex, const uint32_t* lineLut256, const uint32_t* glowLut256) {
    if (!d_->rhi || !lineLut256 || visIndex < 0 || visIndex >= 4) return;
    constexpr int kLutW = 256, kLutH = 8;
    if (!d_->lutTex) {
        d_->lutTex = d_->rhi->newTexture(QRhiTexture::RGBA8, QSize(kLutW, kLutH));
        if (!d_->lutTex->create()) { delete d_->lutTex; d_->lutTex = nullptr; return; }
        d_->lutData.fill(char(0xFF), kLutW * kLutH * 4);
    }
    const int rowBytes = kLutW * 4;
    // Row 2*visIndex: line LUT
    std::memcpy(d_->lutData.data() + (visIndex * 2) * rowBytes, lineLut256, rowBytes);
    // Row 2*visIndex + 1: glow LUT
    const uint32_t* glowSrc = glowLut256 ? glowLut256 : lineLut256;
    std::memcpy(d_->lutData.data() + (visIndex * 2 + 1) * rowBytes, glowSrc, rowBytes);

    d_->withUpdates([&](QRhiResourceUpdateBatch* u) {
        QRhiTextureSubresourceUploadDescription sub(d_->lutData);
        u->uploadTexture(d_->lutTex, QRhiTextureUploadDescription({ { 0, 0, sub } }));
    });
}

PipeId RhiContext::pipeline(const std::string& id) {
    auto it = d_->pipes.find(id);
    if (it != d_->pipes.end()) {
        for (auto& [pid, sid] : d_->pipeIdToShader) if (sid == id) return pid;
        PipeId pid = d_->nextPipe++;
        d_->pipeIdToShader[pid] = id;
        return pid;
    }
    if (!d_->rhi) return 0;
    QShader vs = d_->loadQsb("engine_fullscreen.vert.qsb");
    QShader fs = d_->loadQsb(id + ".frag.qsb");
    if (!vs.isValid() || !fs.isValid()) {
        std::printf("[RhiContext] load qsb FAILED for %s\n", id.c_str());
        return 0;
    }
    Pipe p;
    p.layout = parseLayout(d_->loadFile(id + ".layout.json"));
    if (p.layout.samplers.empty())            // ensure at least u_tex
        p.layout.samplers.emplace_back("u_tex", 2);

    p.srb = buildSrb(d_->rhi, d_->engUbo, d_->parUbos[0], p.layout,
                     d_->dummy, d_->dummy, d_->sampler);
    p.ps = d_->rhi->newGraphicsPipeline();
    p.ps->setShaderStages({ { QRhiShaderStage::Vertex, vs },
                            { QRhiShaderStage::Fragment, fs } });
    p.ps->setVertexInputLayout({});
    p.ps->setShaderResourceBindings(p.srb);
    p.ps->setRenderPassDescriptor(d_->tmplRp);   // persistent, compatible
    bool ok = p.ps->create();
    if (!ok) { std::printf("[RhiContext] pipeline create FAILED %s\n", id.c_str()); return 0; }
    d_->pipes[id] = p;
    PipeId pid = d_->nextPipe++;
    d_->pipeIdToShader[pid] = id;
    return pid;
}

void RhiContext::warmPipelines(const std::vector<std::string>& shaderIds) {
    if (!d_->rhi) return;
    if (shaderIds.empty()) {
        static const std::vector<std::string> kKnownShaders = {
            "ascii", "bloom", "blur", "color_grade", "composite", "cyanotype",
            "datamosh", "dither", "dot_field", "electron_scan", "feedback",
            "flow_warp", "fracture", "glitch", "halftone", "kaleido", "lens",
            "mirror_tile", "noise_field", "oscilloscope", "pixel_sort", "post_fx",
            "risograph", "slit_scan", "terminal", "thermal", "tunnel", "voronoi_shatter", "blit"
        };
        for (const auto& sid : kKnownShaders) {
            pipeline(sid);
        }
    } else {
        for (const auto& sid : shaderIds) {
            pipeline(sid);
        }
    }
}

TexId RhiContext::createTarget(int w, int h) {
    TexEntry e; e.w = w; e.h = h;
    e.tex = d_->rhi->newTexture(QRhiTexture::RGBA8, QSize(w, h), 1,
        QRhiTexture::RenderTarget | QRhiTexture::UsedAsTransferSource);
    e.tex->create();
    e.rt = d_->rhi->newTextureRenderTarget({ e.tex });
    e.rp = e.rt->newCompatibleRenderPassDescriptor();
    e.rt->setRenderPassDescriptor(e.rp); e.rt->create();
    TexId id = d_->nextTex++;
    d_->textures[id] = e;
    return id;
}

TexId RhiContext::uploadImage(const uint8_t* rgba, int w, int h) {
    TexEntry e; e.w = w; e.h = h;
    e.tex = d_->rhi->newTexture(QRhiTexture::RGBA8, QSize(w, h));
    e.tex->create();
    d_->withUpdates([&](QRhiResourceUpdateBatch* u) {
        QRhiTextureSubresourceUploadDescription sub(rgba, w * h * 4);
        u->uploadTexture(e.tex, QRhiTextureUploadDescription({ { 0, 0, sub } }));
    });
    TexId id = d_->nextTex++;
    d_->textures[id] = e;
    return id;
}

TexId RhiContext::uploadMedia(TexId reuse, const uint8_t* rgba, int w, int h) {
    auto it = d_->textures.find(reuse);
    TexId id = reuse;
    if (it == d_->textures.end() || it->second.w != w || it->second.h != h) {
        if (it != d_->textures.end()) releaseTexture(reuse);
        TexEntry e; e.w = w; e.h = h;
        e.tex = d_->rhi->newTexture(QRhiTexture::RGBA8, QSize(w, h));  // sampled
        e.tex->create();
        id = d_->nextTex++;
        d_->textures[id] = e;
    }
    QRhiTexture* tex = d_->textures[id].tex;
    // Rows go up as they arrive: fullscreen.vert is orientation-neutral, so a
    // pass neither flips nor needs pre-flipping here.
    //
    // QByteArray, not a raw pointer: the pointer form of
    // QRhiTextureSubresourceUploadDescription does NOT copy, and the batch is
    // submitted later - the source has to outlive this call.
    const QByteArray pixels(reinterpret_cast<const char*>(rgba),
                            int(size_t(w) * size_t(h) * 4));
    d_->withUpdates([&](QRhiResourceUpdateBatch* u) {
        QRhiTextureSubresourceUploadDescription sub(pixels);   // holds a copy
        u->uploadTexture(tex, QRhiTextureUploadDescription({ { 0, 0, sub } }));
    });
    return id;
}

// Immediate destruction is correct because this class is the SOLE owner of
// every QRhiTexture it hands out. Anything that wraps one for display must
// disown it (see RiftViewport::updatePaintNode) - a second owner deleting a
// live target is what the stacked-clip crash turned out to be.
void RhiContext::releaseTexture(TexId id) {
    auto it = d_->textures.find(id);
    if (it == d_->textures.end()) return;
    delete it->second.rt; delete it->second.rp; delete it->second.tex;
    d_->textures.erase(it);
}

// GPU-to-GPU copy of the finished frame, so the next one can sample it.
//
// A copy rather than swapping which texture the chain writes into: the id Qt
// Quick receives has to stay stable (a changing id destroys and rebuilds the
// QSGTexture wrapper every frame, which crashed), and ping-ponging the final
// target is exactly what would change it.
void RhiContext::capturePrev(TexId scene, int w, int h) {
    if (!d_->rhi || w <= 0 || h <= 0) return;
    auto it = d_->textures.find(scene);
    if (it == d_->textures.end()) return;

    if (!d_->prevTex || d_->prevW != w || d_->prevH != h) {
        delete d_->prevTex;
        d_->prevTex = d_->rhi->newTexture(QRhiTexture::RGBA8, QSize(w, h));
        if (!d_->prevTex->create()) {
            delete d_->prevTex; d_->prevTex = nullptr;
            d_->prevW = d_->prevH = 0;
            return;
        }
        d_->prevW = w; d_->prevH = h;
        // Leave this frame out: the new texture holds garbage until something
        // writes it, and sampling that is worse than sampling black.
        return;
    }

    // Source must carry UsedAsTransferSource; createTarget() sets it, so any
    // chain output qualifies. A texture that came from uploadMedia does not,
    // which is why this is only ever called with the composited scene.
    QRhiTexture* src = it->second.tex;
    if (it->second.w != w || it->second.h != h) return;
    d_->withUpdates([&](QRhiResourceUpdateBatch* u) {
        u->copyTexture(d_->prevTex, src, QRhiTextureCopyDescription());
    });
}

void RhiContext::endOfFrame() {
    d_->frameCounter++;
    d_->drainRetired();
}

bool RhiContext::beginFrame() {
    // Adopted-QRhi mode: we are already inside Qt Quick's frame, and QRhi
    // refuses a nested one ("beginOffscreenFrame() within a still active
    // frame"). Record into Quick's command buffer instead.
    if (d_->extCb) { d_->cb = d_->extCb; if (d_->frameDepth == 0) d_->curPass = 0; ++d_->frameDepth; return true; }

    // Already inside a frame: record into it. Opening one per PASS is what made
    // exporting so slow, since each costs a submit and a wait.
    if (d_->frameDepth > 0) { ++d_->frameDepth; return true; }

    if (d_->rhi->beginOffscreenFrame(&d_->cb) != QRhi::FrameOpSuccess) return false;
    d_->frameDepth = 1;
    d_->curPass = 0;
    return true;
}

void RhiContext::setExternalCommandBuffer(void* cb) {
    d_->extCb = static_cast<QRhiCommandBuffer*>(cb);
}

void RhiContext::drawPass(PipeId pipe, TexId outTex, int w, int h,
                          const EngineUBO& eng, const float* params, int nparams,
                          TexId inputTex, TexId secondTex) {
    auto sit = d_->pipeIdToShader.find(pipe);
    if (sit == d_->pipeIdToShader.end()) return;
    Pipe& P = d_->pipes[sit->second];
    auto oit = d_->textures.find(outTex);
    if (oit == d_->textures.end()) return;
    QRhiTexture* input = d_->dummy;
    auto iit = d_->textures.find(inputTex);
    if (iit != d_->textures.end()) input = iit->second.tex;
    QRhiTexture* second = nullptr;
    if (secondTex) {
        auto sit2 = d_->textures.find(secondTex);
        if (sit2 != d_->textures.end()) second = sit2->second.tex;
    }

    auto* u = d_->rhi->nextResourceUpdateBatch();
    // Patched here rather than in makeEngineUBO: the trigger is a property of
    // the uploaded audio, which the callers building an EngineUBO know nothing
    // about.
    EngineUBO engf = eng;
    engf.C[2] = d_->scopeTrigger;
    engf.C[3] = float(d_->spectroRow);
    u->updateDynamicBuffer(d_->engUbo, 0, sizeof(EngineUBO), &engf);
    float pbuf[32] = {0};
    for (int i = 0; i < nparams && i < 32; ++i) pbuf[i] = params[i];
    QRhiBuffer* curPar = d_->parUbos[d_->curPass % Impl::kMaxPasses];
    ++d_->curPass;
    u->updateDynamicBuffer(curPar, 0, 128, pbuf);

    // per-draw SRB with the real input at binding 2 (layout-compatible)
    QRhiShaderResourceBindings* srb = buildSrb(d_->rhi, d_->engUbo, curPar,
        P.layout, input, d_->dummy, d_->sampler, second,
        d_->audioTex, d_->spectroTex, d_->prevTex, d_->lutTex);

    d_->cb->beginPass(oit->second.rt, QColor(0,0,0,255), { 1.0f, 0 }, u);
    d_->cb->setGraphicsPipeline(P.ps);
    d_->cb->setViewport({ 0, 0, float(w), float(h) });
    d_->cb->setShaderResources(srb);
    d_->cb->draw(3);
    d_->cb->endPass();
    d_->frameSrbs.push_back(srb);        // freed after endOffscreenFrame
}

void RhiContext::endFrame() {
    // Only the outermost close actually submits.
    if (d_->frameDepth > 0) --d_->frameDepth;
    if (d_->frameDepth > 0) return;

    if (d_->extCb) {
        // Quick owns the frame and ends it. The GPU has NOT finished with this
        // frame's SRBs yet, so hand them to QRhi's deferred-release queue
        // instead of deleting them out from under an in-flight frame.
        for (auto* s : d_->frameSrbs) s->deleteLater();
        d_->frameSrbs.clear();
        d_->cb = nullptr;
        return;
    }
    d_->rhi->endOffscreenFrame();        // GPU done -> safe to free per-pass SRBs
    for (auto* s : d_->frameSrbs) delete s;
    d_->frameSrbs.clear();
    d_->cb = nullptr;
}

bool RhiContext::readback(TexId tex, int w, int h, std::vector<uint8_t>& out) {
    (void)w; (void)h;                    // size implied by the texture
    auto it = d_->textures.find(tex);
    if (it == d_->textures.end()) return false;
    // A readback needs a completed frame, which we cannot force from inside
    // someone else's. Only an issue while borrowing a command buffer; the
    // shell renders in its own offscreen frame, so this normally does not fire.
    if (d_->extCb) {
        std::puts("[RhiContext] readback unsupported while sharing Qt Quick's "
                  "frame (export from the QML shell is not wired yet)");
        return false;
    }
    if (d_->rhi->beginOffscreenFrame(&d_->cb) != QRhi::FrameOpSuccess) return false;
    QRhiReadbackResult rb;
    auto* u = d_->rhi->nextResourceUpdateBatch();
    u->readBackTexture({ it->second.tex }, &rb);
    d_->cb->resourceUpdate(u);
    d_->rhi->endOffscreenFrame();
    d_->cb = nullptr;
    if (rb.data.isEmpty()) return false;
    out.assign(rb.data.constData(), rb.data.constData() + rb.data.size());
    return true;
}

// ---- swapchain / on-screen preview ----
static QRhiShaderResourceBindings* makeBlitSrb(QRhi* rhi, QRhiTexture* tex,
                                               QRhiSampler* samp) {
    const auto FS = QRhiShaderResourceBinding::FragmentStage;
    QRhiShaderResourceBinding b = QRhiShaderResourceBinding::sampledTexture(2, FS, tex, samp);
    auto* s = rhi->newShaderResourceBindings();
    s->setBindings({ b });
    s->create();
    return s;
}

bool RhiContext::initSwapchain(void* window) {
    if (!d_->rhi || !window) return false;
    d_->win = static_cast<QWindow*>(window);
    d_->sc = d_->rhi->newSwapChain();
    d_->sc->setWindow(d_->win);
    d_->scRp = d_->sc->newCompatibleRenderPassDescriptor();
    d_->sc->setRenderPassDescriptor(d_->scRp);
    if (!d_->sc->createOrResize()) { std::puts("[RhiContext] swapchain createOrResize FAILED"); return false; }

    QShader vs = d_->loadQsb("engine_fullscreen.vert.qsb");
    QShader fs = d_->loadQsb("blit.frag.qsb");
    if (!vs.isValid() || !fs.isValid()) { std::puts("[RhiContext] blit qsb load FAILED"); return false; }

    d_->blitTmpl = makeBlitSrb(d_->rhi, d_->dummy, d_->sampler);
    d_->blitPs = d_->rhi->newGraphicsPipeline();
    d_->blitPs->setShaderStages({ { QRhiShaderStage::Vertex, vs },
                                  { QRhiShaderStage::Fragment, fs } });
    d_->blitPs->setVertexInputLayout({});
    d_->blitPs->setShaderResourceBindings(d_->blitTmpl);
    d_->blitPs->setRenderPassDescriptor(d_->scRp);
    if (!d_->blitPs->create()) { std::puts("[RhiContext] blit pipeline FAILED"); return false; }
    return true;
}

void RhiContext::resizeSwapchain() {
    if (!d_->sc) return;
    for (auto& [k, s] : d_->blitSrbs) delete s;   // scene textures may be recreated
    d_->blitSrbs.clear();
    d_->sc->createOrResize();
}

bool RhiContext::present(TexId scene) {
    if (!d_->sc) return false;
    if (d_->rhi->beginFrame(d_->sc) != QRhi::FrameOpSuccess) return false;

    QRhiCommandBuffer* cb = d_->sc->currentFrameCommandBuffer();
    QRhiRenderTarget* rt  = d_->sc->currentFrameRenderTarget();

    QRhiTexture* stex = d_->dummy;
    auto it = d_->textures.find(scene);
    if (it != d_->textures.end()) stex = it->second.tex;

    // cache one SRB per scene texture id (ping-pong => at most a couple)
    QRhiShaderResourceBindings* srb;
    auto sit = d_->blitSrbs.find(scene);
    if (sit == d_->blitSrbs.end()) {
        srb = makeBlitSrb(d_->rhi, stex, d_->sampler);
        d_->blitSrbs[scene] = srb;
    } else srb = sit->second;

    const QSize sz = d_->sc->currentPixelSize();
    cb->beginPass(rt, QColor(0, 0, 0, 1), { 1.0f, 0 });
    cb->setGraphicsPipeline(d_->blitPs);
    cb->setViewport({ 0, 0, float(sz.width()), float(sz.height()) });
    cb->setShaderResources(srb);
    cb->draw(3);
    cb->endPass();

    d_->rhi->endFrame(d_->sc);
    return true;
}

} // namespace rift
