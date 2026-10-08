// LayerStack impl. Render thread only.
#include "layer_stack.hpp"
#include "engine_ubo.hpp"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cmath>

namespace rift {

void LayerStack::ensure_(RhiContext& rhi, int w, int h) {
    if (w_ == w && h_ == h && pool_[0]) return;
    // releaseTexture() is deferred inside RhiContext, so calling it here is
    // safe even though the current frame may still reference these.
    for (auto& t : pool_) { if (t) rhi.releaseTexture(t); t = 0; }
    if (final_) { rhi.releaseTexture(final_); final_ = 0; }
    if (grade_) { rhi.releaseTexture(grade_); grade_ = 0; }
    for (auto& t : pool_) t = rhi.createTarget(w, h);
    final_ = rhi.createTarget(w, h);
    grade_ = rhi.createTarget(w, h);
    if (std::getenv("RIFT_GRAPH_DBG"))
        std::fprintf(stderr, "[layer] pool rebuilt %dx%d -> %dx%d\n",
                     w_, h_, w, h), std::fflush(stderr);
    w_ = w; h_ = h;
}

// All pool churn happens HERE, before any pass runs. Resizing mid-frame â€” which
// is what ensure_() used to do when called from composite() â€” swapped targets
// out from under passes that had already rendered into the old ones, and the
// D3D11 backend then died reading a freed texture's format.
void LayerStack::beginFrame(RhiContext& rhi, int w, int h) {
    next_ = 0;
    ensure_(rhi, w, h);
}

TexId LayerStack::acquire_(TexId avoidA, TexId avoidB) {
    // Round-robin, skipping anything the pass is about to sample. With four
    // targets and at most two inputs there is always a free one.
    for (int i = 0; i < kPool; ++i) {
        TexId t = pool_[(next_ + i) % kPool];
        if (t && t != avoidA && t != avoidB) {
            next_ = (next_ + i + 1) % kPool;
            return t;
        }
    }
    return pool_[0];
}

TexId LayerStack::runChain(RhiContext& rhi, const rift_channel_frame& cf,
                           TexId input, double time, int w, int h,
                           Chain& chain) {
    // No ensure_ here: beginFrame() already sized the pool. Rebuilding
    // mid-frame is exactly what caused the resize crash.
    if (chain.empty() || !pool_[0]) return input;

    const EngineUBO eng = makeEngineUBO(cf, float(time), w, h);
    const PipeId blendPipe = rhi.pipeline("composite");
    TexId cur = input;
    std::vector<float> vals;
    for (auto& pass : chain) {
        const PipeId pipe = rhi.pipeline(pass.shader);
        if (!pipe) continue;                 // shader missing: pass through

        // Resolve here, per frame: this applies the keyframed base and the
        // audio patch-bay modulation, exactly as RenderGraph does for the
        // shared chain. Passing stored values would freeze both.
        vals.clear();
        vals.reserve(pass.params.size());
        for (auto& p : pass.params) vals.push_back(resolve(p, cf));

        const TexId out = acquire_(cur, 0);
        rhi.beginFrame();
        rhi.drawPass(pipe, out, w, h, eng,
                     vals.empty() ? nullptr : vals.data(), int(vals.size()), cur);
        rhi.endFrame();

        // Fold the pass back over its own input. Skipped when the pass is a
        // plain replace, so the common case costs exactly what it did before.
        if (!pass.passthrough() && blendPipe && cur != out) {
            // composite.layout.json order; identity transform - this blends a
            // pass with its input, not a clip with a lane.
            // Nine, not five. drawPass zero-fills the rest of the uniform
            // block, and a zero crop rectangle means the shader draws NOTHING
            // and hands back its input - which looks exactly like the effect
            // silently not working.
            const float bp[kCompositeParams] = {
                float(pass.blend), std::clamp(pass.mix, 0.f, 1.f),
                0.f, 0.f, 1.f,
                0.f, 0.f, 1.f, 1.f };
            const TexId mixed = acquire_(out, cur);
            rhi.beginFrame();
            rhi.drawPass(blendPipe, mixed, w, h, eng, bp, kCompositeParams, out, cur);
            rhi.endFrame();
            cur = mixed;
        } else {
            cur = out;
        }
    }
    return cur;
}

// Neutral means "identity": skip the pass entirely rather than burn a draw and
// a texture on a no-op. Order must match color_grade.layout.json.
static bool gradeIsNeutral(const float v[8]) {
    return std::fabs(v[0])        < 1e-4f &&   // lift 0
           std::fabs(v[1] - 1.f)  < 1e-4f &&   // gamma 1
           std::fabs(v[2] - 1.f)  < 1e-4f &&   // gain 1
           std::fabs(v[3] - 1.f)  < 1e-4f &&   // contrast 1
           std::fabs(v[4] - 1.f)  < 1e-4f &&   // saturation 1
           std::fabs(v[5])        < 1e-4f &&   // temperature 0
           std::fabs(v[6])        < 1e-4f &&   // tint 0
           std::fabs(v[7])        < 1e-4f;     // exposure 0
}

TexId LayerStack::applyGrade(RhiContext& rhi, const rift_channel_frame& cf,
                             TexId src, double time, int w, int h,
                             std::vector<Param>& params) {
    if (!grade_ || !src || params.size() < 8) return src;

    // Resolve every frame: the grade supports keyframes and audio patching
    // exactly like an effect parameter.
    float v[8] = {0};
    for (int i = 0; i < 8; ++i) v[i] = resolve(params[i], cf);
    if (gradeIsNeutral(v)) return src;

    const PipeId pipe = rhi.pipeline("color_grade");
    if (!pipe) return src;

    const EngineUBO eng = makeEngineUBO(cf, float(time), w, h);
    rhi.beginFrame();
    rhi.drawPass(pipe, grade_, w, h, eng, v, 8, src);
    rhi.endFrame();
    return grade_;
}

TexId LayerStack::composite(RhiContext& rhi, const rift_channel_frame& cf,
                            TexId top, TexId under, double time, int w, int h,
                            const float* params, TexId finalTarget) {
    if (!pool_[0]) return top;               // pool not sized yet this frame
    const PipeId pipe = rhi.pipeline("composite");
    if (std::getenv("RIFT_GRAPH_DBG"))
        std::fprintf(stderr, "[layer] composite pipe=%u top=%u under=%u "
                             "pool=%u/%u/%u/%u %dx%d\n",
                     pipe, top, under, pool_[0], pool_[1], pool_[2], pool_[3], w, h);
    if (!pipe) return top;                   // no compositor: show the top layer

    const EngineUBO eng = makeEngineUBO(cf, float(time), w, h);

    // Final layer -> the caller's stable target, so the displayed texture id
    // never changes; intermediates rotate through the pool.
    const TexId out = finalTarget ? finalTarget : acquire_(top, under);
    rhi.beginFrame();
    rhi.drawPass(pipe, out, w, h, eng, params, kCompositeParams, top, under);
    rhi.endFrame();
    return out;
}

} // namespace rift

