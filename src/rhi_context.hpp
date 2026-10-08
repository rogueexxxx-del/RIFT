// RhiContext - real QRhi (D3D11) GPU backend. Offscreen render of the ported
// engine shaders. Windowed swapchain comes later (chunk D). This is the port
// of the proven render_engine_test pattern into the engine.
#pragma once
#include <memory>
#include <string>
#include <vector>
#include <cstdint>
#include "engine_ubo.hpp"

namespace rift {

using TexId  = uint32_t;   // 0 = invalid
using PipeId = uint32_t;   // 0 = invalid

class RhiContext {
public:
    // qsbDir: dir with <id>.frag.qsb + engine_fullscreen.vert.qsb (+ .layout.json)
    explicit RhiContext(std::string qsbDir);
    // Adopt an EXISTING QRhi rather than creating one (P4: Qt Quick owns the
    // device, and a texture can only be shared inside one QRhi). `rhi` is a
    // QRhi* - void* keeps this header Qt-free. Not owned: the caller's device
    // outlives us, so the destructor must not delete it.
    RhiContext(std::string qsbDir, void* rhi);
    ~RhiContext();
    bool valid() const;
    // The underlying QRhi* (borrowed or owned). Needed to hand engine output
    // to Qt Quick's scene graph.
    void* rhiHandle() const;
    // QRhiTexture* behind a TexId, so Qt Quick can wrap engine output in a
    // QSGTexture with no copy. Null if the id is unknown.
    void* textureHandle(TexId) const;
    // Record into someone else's frame (Qt Quick's). `cb` is a
    // QRhiCommandBuffer*; null restores own-offscreen-frame behaviour. Must be
    // set per frame, since Quick's command buffer is not stable across frames.
    void  setExternalCommandBuffer(void* cb);

    // Load + cache a graphics pipeline for a shader id. 0 on failure.
    PipeId pipeline(const std::string& shaderId);
    // Pre-compile and cache shader pipelines ahead of time (0ms freeze on switch)
    void   warmPipelines(const std::vector<std::string>& shaderIds = {});
    // Number of custom params the shader's Params UBO holds (from .layout.json).
    int    paramCount(const std::string& shaderId);
    // Sampler bindings the shader uses (from .layout.json): pairs of
    // (glsl name, binding). binding 2 = u_tex is the primary input.
    const std::vector<std::pair<std::string,int>>& samplers(const std::string& shaderId);

    // Make the audible signal samplable by shaders: `wave` is -1..1 around the
    // playhead, `spec` is 0..1 magnitude, low frequency first. Both are
    // resampled internally, so any length works.
    // `trigger` is where a scope should start drawing, 0..1 across the wave
    // row - the first rising zero crossing. Computed on the CPU because it is
    // ONE number for the whole frame: searching for it per-pixel in the shader
    // cost 64 texture fetches for every pixel and made the oscilloscope 2.4x
    // more expensive than any other effect.
    void uploadAudio(const float* wave, int nwave, const float* spec, int nspec,
                     float trigger = 0.0f, const float* raw_spec = nullptr,
                     const float* vecX = nullptr, const float* vecY = nullptr);

    // Upload 256-entry RGBA8 color lookup tables for visualizers (0=scope, 1=spectrum, 2=spectro, 3=vectorscope).
    // lineLut256: 256 uint32_t RGBA8 values for trace/fill.
    // glowLut256: 256 uint32_t RGBA8 values for glow (or nullptr to match lineLut).
    void uploadLut(int visIndex, const uint32_t* lineLut256, const uint32_t* glowLut256 = nullptr);

    // GPU time of the last completed frame in ms, 0 when the backend cannot
    // report it (notably when the QRhi was adopted from Qt Quick).
    double gpuLastMs() const;

    // Textures
    TexId createTarget(int w, int h);                 // RGBA8 render target
    TexId uploadImage(const uint8_t* rgba, int w, int h);
    // Upload a CPU RGBA frame into a REUSABLE sampled texture. Pass the id
    // returned last time as `reuse` (0 first call); a new texture is made only
    // when the size changes, so per-frame video upload doesn't leak. Returns
    // the texture to sample.
    TexId uploadMedia(TexId reuse, const uint8_t* rgba, int w, int h);
    void  releaseTexture(TexId);
    // Keep a copy of the finished frame for the NEXT one to sample as
    // u_feedback_tex. Call once per frame, after the last pass, with whatever
    // is about to be shown or encoded.
    //
    // One shared history rather than one per node: a feedback node reads the
    // previous FINAL frame, which is the loop that produces trails and tunnels.
    // Per-node history would need a target per node kept alive across frames,
    // and nothing yet asks for two independent feedback chains.
    void  capturePrev(TexId scene, int w, int h);
    // Call once per displayed frame. Advances the retire clock and destroys
    // textures released a few frames ago - see releaseTexture().
    void  endOfFrame();

    // Frame
    bool beginFrame();
    // One fullscreen pass: shader -> outTex, sampling inputTex at binding 2.
    // Aux samplers (audio/spectro/atlas) bound to a 1x1 dummy for now.
    // secondTex feeds sampler binding 3 - only the compositor uses it (the
    // layers already accumulated under the one being drawn). 0 = unused.
    void drawPass(PipeId pipe, TexId outTex, int w, int h,
                  const EngineUBO& eng, const float* params, int nparams,
                  TexId inputTex, TexId secondTex = 0);
    void endFrame();

    // CPU readback (export / debug). Fills out with RGBA8 (w*h*4).
    bool readback(TexId tex, int w, int h, std::vector<uint8_t>& out);

    // On-screen preview (chunk D). `window` is a QWindow* (void* keeps this
    // header Qt-free). initSwapchain once; present() blits a scene texture to
    // the backbuffer; resizeSwapchain() on window resize/expose.
    bool initSwapchain(void* window);
    void resizeSwapchain();
    bool present(TexId scene);

private:
    void initResources_();      // shared by both constructors
    void initDefaultLut_();

    struct Impl;
    std::unique_ptr<Impl> d_;
};

} // namespace rift
