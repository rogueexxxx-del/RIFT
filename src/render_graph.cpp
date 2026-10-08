// RenderGraph impl - topo sort + per-frame execute over RhiContext.
// Graph logic (structure, ordering, texture routing, param resolve) is here.
// GPU pass submission is delegated to RhiContext::drawPass.
#include "render_graph.hpp"
#include <algorithm>
#include <unordered_map>
#include <cstdio>
#include <cstdlib>

namespace rift {

static uint32_t g_next_id = 1;

uint32_t RenderGraph::addSource() {
    nodes_.push_back({g_next_id++, NodeKind::Source, "", 0, {}, {}, 0});
    retopo_(); return nodes_.back().id;
}
uint32_t RenderGraph::addEffect(const std::string& sid) {
    nodes_.push_back({g_next_id++, NodeKind::Effect, sid, 0, {}, {}, 0});
    retopo_(); return nodes_.back().id;
}
uint32_t RenderGraph::addOutput() {
    nodes_.push_back({g_next_id++, NodeKind::Output, "post_fx", 0, {}, {}, 0});
    retopo_(); return nodes_.back().id;
}

static Node* find(std::vector<Node>& v, uint32_t id) {
    for (auto& n : v) if (n.id == id) return &n;
    return nullptr;
}

void RenderGraph::connect(uint32_t from, uint32_t to) {
    if (auto* n = find(nodes_, to)) {
        if (std::find(n->inputs.begin(), n->inputs.end(), from) == n->inputs.end())
            n->inputs.push_back(from);
        retopo_();
    }
}

void RenderGraph::setParams(uint32_t id, std::vector<Param> params) {
    if (auto* n = find(nodes_, id)) n->params = std::move(params);
}

void RenderGraph::setBlend(uint32_t id, int blend, float mix) {
    if (auto* n = find(nodes_, id)) {
        n->blend = (blend >= 0 && blend < Blend_Count) ? blend : Blend_Normal;
        n->mix   = std::clamp(mix, 0.f, 1.f);
    }
}

void RenderGraph::remove(uint32_t id) {
    nodes_.erase(std::remove_if(nodes_.begin(), nodes_.end(),
        [&](const Node& n){ return n.id == id; }), nodes_.end());
    for (auto& n : nodes_)
        n.inputs.erase(std::remove(n.inputs.begin(), n.inputs.end(), id),
                       n.inputs.end());
    retopo_();
}

void RenderGraph::reorder(uint32_t id, int index) {
    auto it = std::find_if(nodes_.begin(), nodes_.end(),
                           [&](const Node& n){ return n.id == id; });
    if (it == nodes_.end()) return;
    Node n = *it; nodes_.erase(it);
    index = std::clamp(index, 0, (int)nodes_.size());
    nodes_.insert(nodes_.begin() + index, n);
    retopo_();
}

void RenderGraph::clear() { nodes_.clear(); topo_.clear(); }

// Kahn topological sort over the DAG (inputs = dependencies).
void RenderGraph::retopo_() {
    std::unordered_map<uint32_t, int> indeg;
    std::unordered_map<uint32_t, std::vector<uint32_t>> outs;
    for (auto& n : nodes_) indeg[n.id];               // ensure present
    for (auto& n : nodes_)
        for (uint32_t in : n.inputs) { indeg[n.id]++; outs[in].push_back(n.id); }

    std::vector<uint32_t> q;
    for (auto& [id, d] : indeg) if (d == 0) q.push_back(id);
    topo_.clear();
    for (size_t i = 0; i < q.size(); ++i) {
        uint32_t u = q[i];
        topo_.push_back(u);
        for (uint32_t v : outs[u]) if (--indeg[v] == 0) q.push_back(v);
    }
    // cycle => topo_.size() < nodes_.size(); UI prevents cycles for linear chain
}

void RenderGraph::build(RhiContext& rhi) {
    for (auto& n : nodes_) {
        if (n.kind == NodeKind::Source) continue;
        n.pipeline = rhi.pipeline(n.shader_id);
        if (!n.pipeline) {
            std::fprintf(stderr, "[RenderGraph] ERROR: pipeline creation failed for '%s'\n", n.shader_id.c_str());
        }
    }
}

void RenderGraph::ensureScratch_(RhiContext& rhi, int w, int h) {
    if (scratchW_ == w && scratchH_ == h && scratch_[0] && scratch_[1] && out_)
        return;
    for (auto& s : scratch_) { if (s) rhi.releaseTexture(s); s = 0; }
    if (out_)   { rhi.releaseTexture(out_);   out_ = 0; }
    if (blend_) { rhi.releaseTexture(blend_); blend_ = 0; }
    scratch_[0] = rhi.createTarget(w, h);
    scratch_[1] = rhi.createTarget(w, h);
    out_        = rhi.createTarget(w, h);
    scratchW_ = w; scratchH_ = h;
}

TexId RenderGraph::ensureOutput(RhiContext& rhi, int w, int h) {
    ensureScratch_(rhi, w, h);
    return out_;
}

TexId RenderGraph::execute(RhiContext& rhi, const rift_channel_frame& cf,
                           TexId media, double time, int w, int h) {
    ensureScratch_(rhi, w, h);
    EngineUBO eng = makeEngineUBO(cf, float(time), w, h);

    // Which node draws last? Its output goes to the dedicated out_ target so
    // the returned id is stable regardless of chain length.
    uint32_t lastDrawId = 0;
    for (uint32_t id : topo_) {
        Node* n = find(nodes_, id);
        if (n && n->kind != NodeKind::Source && n->pipeline) lastDrawId = id;
    }

    if (std::getenv("RIFT_GRAPH_DBG")) {
        std::fprintf(stderr, "[graph] topo:");
        for (uint32_t id : topo_) {
            Node* n = find(nodes_, id);
            std::fprintf(stderr, " %u(%s)", id,
                         n ? (n->kind == NodeKind::Source ? "src"
                                                          : n->shader_id.c_str())
                           : "?");
        }
        std::fprintf(stderr, "  lastDraw=%u out_=%u\n", lastDrawId, out_);
    }

    TexId last = media;
    int ping = 0;                       // next scratch target to write
    for (uint32_t id : topo_) {
        Node* n = find(nodes_, id);
        if (!n) continue;
        if (n->kind == NodeKind::Source) { n->output = media; last = media; continue; }
        if (!n->pipeline) {
            static bool warned = false;
            if (!warned) {
                std::fprintf(stderr, "[RenderGraph] ERROR: skipping '%s' - null pipeline!\n", n->shader_id.c_str());
                warned = true;
            }
            n->output = last;
            continue;
        }

        // single-input linear chain: read `last`; explicit inputs override.
        TexId input = last;
        if (!n->inputs.empty()) {
            Node* s = find(nodes_, n->inputs.front());
            if (s && s->output) input = s->output;
        }

        // resolve params in layout order (patch bay). Missing => shader default.
        std::vector<float> pv;
        pv.reserve(n->params.size());
        for (auto& p : n->params) pv.push_back(resolve(p, cf));

        // Final pass -> stable output target; intermediates ping-pong.
        // out_ is never used as an input, so it can never alias `input`.
        TexId out = (id == lastDrawId) ? out_ : scratch_[ping];
        if (out == input) { ping ^= 1; out = scratch_[ping]; }   // never in==out

        // Per-node blend: the effect draws to a private target first, then gets
        // laid back over its own input. blend_ is never anyone's input, so it
        // cannot alias `input` or `out`.
        const bool wantBlend =
            !(n->blend == Blend_Normal && n->mix >= 0.999f);
        const PipeId blendPipe = wantBlend ? rhi.pipeline("composite") : 0;
        if (blendPipe && !blend_) blend_ = rhi.createTarget(w, h);
        const bool doBlend = blendPipe && blend_;
        const TexId drawTo = doBlend ? blend_ : out;

        if (std::getenv("RIFT_GRAPH_DBG"))
            std::fprintf(stderr, "[graph] pass %s pipe=%u in=%u out=%u np=%d"
                                 " blend=%d mix=%.2f\n",
                         n->shader_id.c_str(), n->pipeline, input, out,
                         (int)pv.size(), n->blend, n->mix);
        rhi.beginFrame();
        rhi.drawPass(n->pipeline, drawTo, w, h, eng,
                     pv.empty() ? nullptr : pv.data(), (int)pv.size(), input);
        rhi.endFrame();

        if (doBlend) {
            // composite.layout.json order, identity transform: this folds a
            // pass over its input, it does not place a clip in a lane.
            // Nine: the last four are the crop rectangle, and a zeroed one
            // makes the compositor discard every pixel and return its input.
            const float bp[9] = { float(n->blend), std::clamp(n->mix, 0.f, 1.f),
                                  0.f, 0.f, 1.f,
                                  0.f, 0.f, 1.f, 1.f };
            rhi.beginFrame();
            rhi.drawPass(blendPipe, out, w, h, eng, bp, 9, blend_, input);
            rhi.endFrame();
        }

        n->output = out;
        last = out;
        ping ^= 1;
    }
    return last;
}

} // namespace rift
