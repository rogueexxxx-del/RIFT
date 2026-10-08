// TextSource - rasterizes a TextSpec to a GPU texture.
//
// Text becomes a source layer rather than an overlay: once it is a texture it
// flows through the same per-clip chain, blend modes, lanes, keyframes and audio
// bindings as footage. That is what makes it reactive - an ascii or glitch pass
// bound to KICK treats text exactly as it treats a video frame, with no separate
// text-effect path to maintain.
//
// QPainter, not a glyph atlas: the exporter already rasterizes overlay text this
// way, and re-rendering only happens when the spec changes (typing), never per
// frame.
#pragma once
#include <cstdint>
#include <string>
#include "timeline.hpp"

namespace rift {

class RhiContext;

class TextSource {
public:
    explicit TextSource(RhiContext* rhi) : rhi_(rhi) {}
    ~TextSource();

    // Texture for `spec` at this size. Re-rasterizes only when the spec or the
    // size actually changed; otherwise returns the cached texture. 0 on failure.
    uint32_t texture(const TextSpec& spec, int w, int h);

private:
    RhiContext* rhi_ = nullptr;
    uint32_t    tex_ = 0;
    TextSpec    last_;
    int         last_w_ = 0, last_h_ = 0;
    bool        have_ = false;
};

} // namespace rift
