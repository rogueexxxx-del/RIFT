// Timeline - an ordered set of media clips on one track.
//
// Replaces "the engine has a single media file" with "the engine has a track".
// Each clip names a source plus where it sits on the timeline and which part of
// the source it uses:
//
//     |<-- start -->|<======= out - in =======>|
//                    reads source[in .. out]
//
// One MediaDecoder per clip, opened lazily - only the playing clip (and the
// next one, prefetched near a boundary) decodes, so a long track does not spawn
// a decoder thread per file up front.
//
// Threading: owned by Engine and touched ONLY on the render thread. The UI
// describes the track declaratively via Engine::setClips(), which queues the
// list; apply() then diffs it against the live clips and reuses decoders whose
// source path is unchanged, so trimming or dragging a clip does not reopen it.
#pragma once
#include <memory>
#include <string>
#include <utility>
#include <vector>
#include <cstdint>
#include "parameter_graph.hpp"

namespace rift {

class RhiContext;
class MediaDecoder;

// A text clip's appearance. Rasterized to a texture and then treated exactly
// like a decoded frame, so text goes through the same per-clip chain, blend
// modes, lanes, keyframes and audio bindings as footage - reactivity comes from
// machinery that already exists rather than a parallel text pipeline.
struct TextSpec {
    std::string text;
    std::string font;              // family name; empty = default mono
    double      size    = 0.18;    // fraction of frame height, so it scales
    double      x       = 0.5;     // 0..1 within the frame
    double      y       = 0.5;
    float       r = 1.f, g = 1.f, b = 1.f;
    double      letterSpacing = 0.0;   // extra px per glyph at render size
    bool        bold = false;
    // Wall of text vs one word: 0 = no wrapping.
    double      wrapWidth = 0.0;   // fraction of frame width

    // Everything here comes from the UI verbatim, so a member-wise compare
    // is exactly "would this rasterize differently".
    bool operator==(const TextSpec&) const = default;
};

// An audio clip on an AUDIO track (A1..An). Audio lanes are a separate
// namespace from video lanes: only video lanes composite, and audio is mixed
// by gain instead. Placed, trimmed and gain-staged like a video clip so the
// two read the same to the UI.
//
// `link` ties this clip to a video clip (same integer on both) so an editing
// gesture in a later phase can move/trim/split the pair together. -1 means
// independent. Audio itself does not use it - it is stored and round-tripped.
struct AudioClipSpec {
    std::string path;          // audio file, decodable by libav
    std::string name;          // display label (basename by default)
    // Timeline seconds. NEGATIVE means "append after the previous clip on this
    // audio lane", resolved once the source duration is known - same rule as a
    // video clip.
    double start = -1.0;
    double in    = 0.0;        // trim start within the source, seconds
    double out   = 0.0;        // trim end within the source; <= in means "to end"
    int    lane  = 0;          // A-track index, 0 = A1
    double gain  = 1.0;        // linear, 0..2. The UI may show dB.
    int    link  = -1;         // shared id with a video ClipSpec; -1 = independent
};

struct ClipSpec {
    // A clip is EITHER a media file or generated text. Text has no file and no
    // measurable duration, so it carries its own span (see `out`).
    enum Kind { Media = 0, Text = 1 };
    int  kind = Media;
    TextSpec text;

    std::string path;
    // Position on the timeline in seconds. NEGATIVE means "append after the
    // previous clip" - the caller usually cannot compute this itself, because a
    // clip's length is unknown until its source opens. The timeline resolves it.
    double start = -1.0;
    double in    = 0.0;    // trim start within the source, seconds
    double out   = 0.0;    // trim end within the source; <= in means "to end"
    // Stacking order, like a video editor's V1/V2. Overlapping clips composite
    // bottom lane upward.
    int    lane  = 0;

    // How this clip lays over the layers beneath it. Same BlendMode values
    // as per-effect blending - it is the same shader doing the work.
    int    blend   = Blend_Normal;
    double opacity = 1.0;
    // Placement within the frame, so a stacked clip can be moved and resized
    // instead of always covering everything. Offsets are fractions of the
    // frame; scale 1 is full size.
    double posX = 0.0, posY = 0.0, scale = 1.0;
    // The part of the FRAME this clip is allowed to paint, as a rectangle in
    // 0..1 screen coordinates. Scaling a clip down gives picture-in-picture;
    // this is what gives split screen, where two clips each keep their own
    // framing and meet at an edge. Full frame = no crop.
    double cropX = 0.0, cropY = 0.0, cropW = 1.0, cropH = 1.0;

    // This clip's own effect stack. Empty = show the source untouched.
    // Each entry is a shader id plus its uniforms in layout order. Full Params,
    // not plain floats: a uniform carries its audio binding and its keyframes,
    // both of which have to be re-evaluated every frame.
    std::vector<ChainPass> chain;

    // Shared id with an AudioClipSpec (same integer on both); -1 = independent.
    // Stored and round-tripped here; the linked-edit gestures are a later phase.
    int link = -1;
};

class Timeline {
public:
    explicit Timeline(RhiContext* rhi);
    ~Timeline();

    // Render thread. Diffs against the current clips, reusing decoders by path.
    void apply(const std::vector<ClipSpec>& clips);

    // Render thread. Texture for this timeline position, 0 if nothing to show
    // (gap between clips, or the clip has not decoded a frame yet). Returns the
    // TOPMOST clip's raw source only - use activeAt() for layered compositing.
    uint32_t frameForPlayhead(double t);

    // Every clip covering `t`, bottom lane first: {clip index, source texture}.
    // The engine runs each clip's own chain and composites them in this order.
    struct Layer { int index; uint32_t tex; };
    std::vector<Layer> activeAt(double t);

    // Non-const: the engine resolves this clip's Params each frame, which
    // advances their envelope state.
    ClipSpec* spec(int i);

    // Render thread. Flush the clip covering `t` and re-seek it, so a scrub
    // does not play stale queued frames.
    void seek(double t);

    // Wrap the playhead at the end of the track. Individual clips never loop
    // (a clip plays its trimmed span once); this is the track repeating, which
    // is what a single dropped file did before clips existed.
    void setLoopTrack(bool on) { loop_track_ = on; }

    // Frame size the layers are being rendered at. Text is rasterized to this,
    // so it has to be told before a frame is fetched - a caption sized as a
    // fraction of frame height cannot be rendered without knowing the height.
    void setRenderSize(int w, int h) { rw_ = w; rh_ = h; }

    // Export mode. Opens every clip up front and makes frame fetches wait for
    // the frame that covers the playhead, so an export that renders faster than
    // real time still gets the right picture. `timeout_ms` bounds the wait for
    // sources to report their duration.
    void prepareForExport(int timeout_ms = 3000);

    // Seconds from 0 to the end of the last clip.
    double duration() const;
    bool   empty() const { return clips_.empty(); }
    size_t count() const { return clips_.size(); }

    // Index of the clip covering `t`, or -1 in a gap. Used by the UI to show
    // which clip is live.
    int    activeIndex(double t) const;

    // Resolved geometry for the UI: where clips actually sit once auto-append
    // positions and real source durations are known.
    double clipStart(int i) const;
    double clipSpan(int i) const;
    int    laneCount() const;      // highest lane in use, + 1 (minimum 1)

private:
    struct Entry;
    // Length a clip occupies on the timeline: the trimmed span, falling back to
    // the source duration once it is known.
    double spanOf_(const Entry& e) const;

    // Fold `t` into [0, duration) when the track loops.
    double wrap_(double t) const;
    // Resolve auto-append positions into Entry::at. Const because every
    // position query needs it and the result is derived, not owned state.
    void   layout_() const;
    void   ensureOpen_(int i);     // lazily create+open a clip's decoder
    // Source texture for one entry at a position inside it. Hides whether the
    // pixels came from a decoder or from rasterized text, so every caller
    // downstream treats the two identically.
    uint32_t frameFor_(Entry& e, double local);

    RhiContext* rhi_;
    int rw_ = 1920, rh_ = 1080;    // render size, for text rasterization
    std::vector<std::unique_ptr<Entry>> clips_;
    bool loop_track_ = true;
};

} // namespace rift
