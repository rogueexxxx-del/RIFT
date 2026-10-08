// Effect graph: DAG of fullscreen passes. Nodes = passes (source / effect /
// output), edges = textures. Topo-sorted, executed once per frame on the
// render thread. Generalizes the prototype's linear generator->chain->
// post_fx into a graph (linear chain is the trivial path).
//
// GPU work is delegated to RhiContext: build() caches a PipeId per node,
// execute() runs each pass with an EngineUBO + resolved params into ping-pong
// targets. The linear chain is the fast path; DAG branches are future work.
#pragma once
#include <cstdint>
#include <vector>
#include <string>
#include "parameter_graph.hpp"
#include "rhi_context.hpp"
#include "engine_ubo.hpp"
#include "rift/rift_types.h"

namespace rift {

enum class NodeKind { Source, Effect, Output };

struct Node {
    uint32_t              id;
    NodeKind              kind;
    std::string           shader_id;     // empty for Source
    PipeId                pipeline = 0;   // cached RhiContext pipeline
    std::vector<uint32_t> inputs;         // upstream node ids
    std::vector<Param>    params;         // resolved per-frame, in layout order
    // How this pass folds back over its own input. Normal + mix 1 = replace,
    // which is the historical behaviour and costs no extra draw.
    int                   blend = Blend_Normal;
    float                 mix   = 1.f;
    TexId                 output = 0;      // last-rendered target
};

class RenderGraph {
public:
    uint32_t addSource();
    uint32_t addEffect(const std::string& shader_id);
    uint32_t addOutput();
    void     connect(uint32_t from, uint32_t to);
    void     setParams(uint32_t node, std::vector<Param> params);  // layout order
    void     setBlend(uint32_t node, int blend, float mix);
    void     remove(uint32_t id);
    void     reorder(uint32_t id, int index);     // linear-chain convenience
    void     clear();

    // Compile pipelines for all nodes (uses RhiContext). Call on structural
    // change, not per-frame.
    void     build(RhiContext&);

    // Execute the whole graph: resolve params from `cf`, run passes into
    // ping-pong targets, return the final texture. Runs on render thread each
    // frame. `media` is the source texture (0 => nothing decoded yet).
    TexId execute(RhiContext& rhi, const rift_channel_frame& cf,
                  TexId media, double time, int w, int h);

    // The graph's dedicated output target, creating it if needed. Anything
    // that produces the final image (the layer compositor) should render HERE,
    // so the id handed to the display never changes - Qt Quick rebuilds its
    // QSGTexture wrapper whenever it does, which is not survivable per frame.
    TexId ensureOutput(RhiContext& rhi, int w, int h);

private:
    std::vector<Node>     nodes_;
    std::vector<uint32_t> topo_;          // cached topological order
    TexId scratch_[2] = {0, 0};           // ping-pong targets
    // The LAST pass always renders here, so the returned texture id does not
    // depend on how many effects are in the chain. With ping-pong alone an
    // N-pass chain ended on scratch_[N%2], and a consumer that caches a
    // wrapper around the returned id (Qt Quick's QSGTexture) then showed an
    // earlier pass: odd-length chains rendered as if only the first ran.
    TexId out_ = 0;
    // Third target, only allocated once something actually blends. Per-node
    // blending needs to read the pass output AND its input while writing a
    // third texture, which two ping-pong slots cannot do.
    TexId blend_ = 0;
    int   scratchW_ = 0, scratchH_ = 0;
    void  retopo_();
    void  ensureScratch_(RhiContext& rhi, int w, int h);
};

} // namespace rift
