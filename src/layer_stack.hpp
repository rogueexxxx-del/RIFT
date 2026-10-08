// LayerStack - per-clip effect passes and layer compositing.
//
// RenderGraph handles ONE chain shared by the whole frame. Stacked clips need
// something different: each clip runs its own list of shader passes, then the
// results are laid over each other. That is what this does.
//
// It keeps a small pool of render targets and hands out one that is not being
// read by the current pass, so a chain of any length and any number of layers
// never renders into a texture it is sampling.
#pragma once
#include <string>
#include <utility>
#include <vector>
#include "rhi_context.hpp"
#include "parameter_graph.hpp"
#include "rift/rift_types.h"

namespace rift {

class LayerStack {
public:
    // Shader id + uniforms in layout order, plus how the pass folds back over
    // its input. Params (not floats) because each one is resolved per frame -
    // audio modulation and keyframes both move.
    using Pass  = ChainPass;
    using Chain = std::vector<Pass>;

    // Run `chain` over `input`. Returns `input` unchanged for an empty chain.
    // Chain is non-const: resolving a Param advances its envelope state.
    TexId runChain(RhiContext& rhi, const rift_channel_frame& cf, TexId input,
                   double time, int w, int h, Chain& chain);

    // Lay `top` over `under` (0 = nothing beneath) using the composite shader.
    // blend: 0 normal, 1 add, 2 multiply, 3 screen.
    // `isFinal` sends the result to a dedicated, STABLE target instead of a
    // rotating pool slot. The consumer (Qt Quick) wraps the returned id in a
    // QSGTexture; if that id changed every frame the wrapper was destroyed and
    // rebuilt every frame, which crashed. RenderGraph does the same thing with
    // its own out_ target.
    // `finalTarget` != 0 renders there instead of a rotating pool slot. The
    // caller passes RenderGraph's output target for the last layer so the id
    // handed to the display is identical to the non-composited path.
    // `params` is composite.layout.json in order: blend, opacity, posX, posY,
    // scale, cropX, cropY, cropW, cropH.
    static constexpr int kCompositeParams = 9;
    TexId composite(RhiContext& rhi, const rift_channel_frame& cf,
                    TexId top, TexId under, double time, int w, int h,
                    const float* params, TexId finalTarget);

    // Master colour grade, applied last. Renders into its own STABLE target
    // (same reasoning as the composite's final target: the display wraps the
    // returned id, and an id that changes per frame is not survivable).
    // Returns `src` unchanged when the grade is neutral, so an untouched grade
    // costs nothing.
    TexId applyGrade(RhiContext& rhi, const rift_channel_frame& cf, TexId src,
                     double time, int w, int h, std::vector<Param>& params);

    // Stable target for the composited result. MUST be used as the final
    // layer's destination instead of RenderGraph's out_: every layer whose
    // clip has no chain of its own is produced BY the graph into out_, so
    // compositing into out_ meant sampling and writing one texture in the
    // same draw - only one layer survived.
    TexId finalTarget() const { return final_; }

    // Frame boundary: resets the round-robin and frees targets retired by a
    // resize during the PREVIOUS frame (they cannot be freed at resize time -
    // the frame still being recorded has bindings pointing at them).
    void beginFrame(RhiContext& rhi, int w, int h);

private:
    void  ensure_(RhiContext& rhi, int w, int h);
    // A target that is neither of the two textures the pass will sample.
    TexId acquire_(TexId avoidA, TexId avoidB);

    static constexpr int kPool = 4;
    TexId pool_[kPool] = { 0, 0, 0, 0 };
    TexId final_ = 0;              // stable id handed to the display
    TexId grade_ = 0;              // stable target for the colour grade
    int   next_ = 0;
    int   w_ = 0, h_ = 0;
};

} // namespace rift
