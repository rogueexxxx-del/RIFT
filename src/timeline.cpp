// Timeline impl â€” clip lookup + lazy decoder management. Render thread only.
#include "timeline.hpp"
#include "media_decoder.hpp"
#include "text_source.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <vector>

namespace rift {

struct Timeline::Entry {
    ClipSpec spec;
    std::unique_ptr<MediaDecoder> dec;
    std::unique_ptr<TextSource>   text;   // set only for Kind::Text
    bool opened = false;
    // Resolved start: equals spec.start when the caller pinned it, otherwise
    // the previous clip's end. Recomputed every lookup because a source's
    // duration â€” and therefore every later clip's position â€” only becomes
    // known once that source opens.
    double at = 0.0;
};

Timeline::Timeline(RhiContext* rhi) : rhi_(rhi) {}
Timeline::~Timeline() = default;

double Timeline::spanOf_(const Entry& e) const {
    // Trimmed span when the user set an out point, otherwise whatever the
    // source turns out to be. Duration is 0 until the decoder has opened, so a
    // not-yet-ready clip reports a nominal length instead of collapsing to zero
    // and swallowing every later clip's position.
    if (e.spec.out > e.spec.in) return e.spec.out - e.spec.in;
    // Text has no source to measure, so it can only ever use its own span. A
    // text clip without one gets the same nominal 5 s as a cold decoder.
    if (e.spec.kind == ClipSpec::Text) return 5.0;
    const double d = (e.dec && e.dec->ready()) ? e.dec->duration() : 0.0;
    // A still image reports one frame's worth of time, or nothing at all. Used
    // literally that put a PNG on the timeline a few pixels wide, with a trim
    // handle too small to grab - which is what "I cannot stretch an image"
    // actually was. A still has no length of its own, so it gets the same
    // nominal span text does and is stretched from there.
    if (d < 0.2) return 5.0;
    if (d > e.spec.in) return d - e.spec.in;
    return 5.0;                       // provisional, replaced once ready
}

void Timeline::apply(const std::vector<ClipSpec>& want) {
    std::vector<std::unique_ptr<Entry>> next;
    next.reserve(want.size());

    // Which old entry each new one takes over, resolved BEFORE anything moves -
    // taking entries out of clips_ as we go would shift the indices that
    // position-based matching depends on.
    std::vector<int> take(want.size(), -1);
    std::vector<bool> used(clips_.size(), false);

    for (size_t i = 0; i < want.size(); ++i) {
        const ClipSpec& s = want[i];
        if (s.kind == ClipSpec::Text) {
            // Text clips have no path, so matching on it would make every text
            // clip look like every other one and swap their rasterized textures
            // around. Match by position instead: that keeps the cache across an
            // edit to the text itself, which is the case that matters (typing).
            if (i < clips_.size() && clips_[i] && !used[i]
                && clips_[i]->spec.kind == ClipSpec::Text) {
                take[i] = int(i);
                used[i] = true;
            }
            continue;
        }
        // Reuse a live decoder for the same source: dragging or trimming a clip
        // must not reopen the file (which would stall and reset the queue).
        for (size_t j = 0; j < clips_.size(); ++j) {
            if (used[j] || !clips_[j]) continue;
            if (clips_[j]->spec.kind == ClipSpec::Text) continue;
            if (clips_[j]->spec.path != s.path) continue;
            take[i] = int(j);
            used[j] = true;
            break;
        }
    }

    for (size_t i = 0; i < want.size(); ++i) {
        if (take[i] >= 0) {
            auto e = std::move(clips_[size_t(take[i])]);
            e->spec = want[i];             // position/trim may have changed
            next.push_back(std::move(e));
        } else {
            auto e = std::make_unique<Entry>();
            e->spec = want[i];
            next.push_back(std::move(e));  // decoder opened lazily
        }
    }
    // Anything left in clips_ was removed from the track; destroying the Entry
    // stops and joins its decoder thread.
    clips_ = std::move(next);
}

// Lazy opening is right for playback - a long track must not spawn a thread per
// file up front. An export is the opposite: every clip WILL be needed, and the
// track's real length cannot be known until each source reports its duration.
// Getting that wrong is what made exports fall back to a nominal 5 s.
void Timeline::prepareForExport(int timeout_ms) {
    for (int i = 0; i < int(clips_.size()); ++i) {
        ensureOpen_(i);
        if (clips_[i]->dec) clips_[i]->dec->setBlocking(true);
    }
    const auto deadline = std::chrono::steady_clock::now()
                        + std::chrono::milliseconds(timeout_ms);
    for (const auto& e : clips_) {
        while (e->dec && !e->dec->ready()
               && std::chrono::steady_clock::now() < deadline)
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    layout_();

    if (std::getenv("RIFT_DBG"))
        for (size_t i = 0; i < clips_.size(); ++i)
            std::fprintf(stderr, "[export] clip %zu '%s' dec=%d ready=%d "
                                 "dur=%.3f span=%.3f at=%.3f\n",
                         i, clips_[i]->spec.path.c_str(),
                         clips_[i]->dec ? 1 : 0,
                         clips_[i]->dec && clips_[i]->dec->ready() ? 1 : 0,
                         clips_[i]->dec ? clips_[i]->dec->duration() : -1.0,
                         spanOf_(*clips_[i]), clips_[i]->at),
            std::fflush(stderr);
}

double Timeline::duration() const {
    layout_();
    double end = 0.0;
    for (const auto& e : clips_) end = std::max(end, e->at + spanOf_(*e));
    return end;
}

// Lay clips out left to right, filling in auto-append positions. Cheap (a few
// entries) and always current, so it runs before any position query.
void Timeline::layout_() const {
    // Auto-append follows the end of the previous clip IN THE SAME LANE, so
    // dropping a clip on lane 1 does not get pushed along by lane 0's content.
    std::vector<double> cursor;
    for (const auto& e : clips_) {
        const int ln = std::max(0, e->spec.lane);
        if (int(cursor.size()) <= ln) cursor.resize(ln + 1, 0.0);
        e->at = (e->spec.start >= 0.0) ? e->spec.start : cursor[ln];
        cursor[ln] = e->at + spanOf_(*e);
    }
}

int Timeline::laneCount() const {
    int hi = 0;
    for (const auto& e : clips_) hi = std::max(hi, std::max(0, e->spec.lane));
    return hi + 1;
}

double Timeline::clipStart(int i) const {
    if (i < 0 || i >= int(clips_.size())) return 0.0;
    layout_();
    return clips_[i]->at;
}
double Timeline::clipSpan(int i) const {
    if (i < 0 || i >= int(clips_.size())) return 0.0;
    return spanOf_(*clips_[i]);
}

double Timeline::wrap_(double t) const {
    if (!loop_track_) return t;
    const double d = duration();
    if (d <= 1e-6) return t;
    double x = std::fmod(t, d);
    if (x < 0.0) x += d;
    return x;
}

int Timeline::activeIndex(double t) const {
    const double tt = wrap_(t);
    layout_();
    // Overlaps resolve by lane: the highest lane covering `t` is what shows.
    int best = -1, bestLane = -1;
    for (int i = 0; i < int(clips_.size()); ++i) {
        const auto& e = *clips_[i];
        if (tt < e.at || tt >= e.at + spanOf_(e)) continue;
        const int ln = std::max(0, e.spec.lane);
        if (ln > bestLane) { bestLane = ln; best = i; }
    }
    return best;
}

void Timeline::seek(double raw_t) {
    const double t = wrap_(raw_t);
    const int idx = activeIndex(t);
    if (idx < 0) return;
    Entry& e = *clips_[idx];
    if (e.dec) e.dec->seek(e.spec.in + (t - e.at));
}

// Decoders are opened on demand: a long track must not spawn a thread per file
// up front, and only what is on (or about to be on) screen needs to decode.
void Timeline::ensureOpen_(int i) {
    if (i < 0 || i >= int(clips_.size())) return;
    Entry& e = *clips_[i];
    if (e.opened) return;
    // Text clips have no file: rasterized on demand in frameFor_, no decoder
    // and no worker thread.
    if (e.spec.kind == ClipSpec::Text) {
        e.text = std::make_unique<TextSource>(rhi_);
        e.opened = true;
        return;
    }
    e.dec = std::make_unique<MediaDecoder>(rhi_);
    // The DECODER loops; how long the clip occupies is still decided by its
    // span, so this does not make a clip play twice. It keeps the worker alive
    // past EOF, which is what the wrapped lookup in Engine::renderLayers_ needs:
    // with loop(false) the worker broke out at EOF and its thread ended, so the
    // second time round the queue was empty and frameForPlayhead re-served the
    // last decoded frame. Footage shorter than the track froze on its final
    // frame instead of repeating - measured as 3x the frames for 1.35x the bytes.
    e.dec->setLoop(true);
    e.dec->open(e.spec.path);
    e.opened = true;
}

// One place that turns "this clip, at this position inside it" into a texture,
// whichever kind of source it is.
uint32_t Timeline::frameFor_(Entry& e, double local) {
    if (e.spec.kind == ClipSpec::Text)
        return e.text ? e.text->texture(e.spec.text, rw_, rh_) : 0;
    return e.dec ? e.dec->frameForPlayhead(local) : 0;
}

ClipSpec* Timeline::spec(int i) {
    if (i < 0 || i >= int(clips_.size())) return nullptr;
    return &clips_[i]->spec;
}

// Bottom lane first, so the caller composites in the order layers stack.
std::vector<Timeline::Layer> Timeline::activeAt(double raw_t) {
    const double t = wrap_(raw_t);
    layout_();

    std::vector<int> hits;
    for (int i = 0; i < int(clips_.size()); ++i) {
        const auto& e = *clips_[i];
        if (t >= e.at && t < e.at + spanOf_(e)) hits.push_back(i);
    }
    std::stable_sort(hits.begin(), hits.end(), [&](int a, int b) {
        return clips_[a]->spec.lane < clips_[b]->spec.lane;
    });

    // Open what is on screen now, plus the next clip in each lane shortly
    // before its cut, so a switch does not stall on a cold demuxer.
    std::vector<Layer> out;
    out.reserve(hits.size());
    for (int i : hits) {
        ensureOpen_(i);
        Entry& e = *clips_[i];
        const double local = e.spec.in + (t - e.at);
        const uint32_t tex = frameFor_(e, local);
        if (!tex) continue;
        out.push_back({ i, tex });
        if (e.at + spanOf_(e) - t < 1.0) ensureOpen_(i + 1);
    }
    return out;
}

uint32_t Timeline::frameForPlayhead(double raw_t) {
    const double t = wrap_(raw_t);
    const int idx = activeIndex(t);

    ensureOpen_(idx);
    if (idx >= 0) {
        const Entry& cur = *clips_[idx];
        const double endsAt = cur.at + spanOf_(cur);
        if (endsAt - t < 1.0) ensureOpen_(idx + 1);     // 1 s of lead-in
    }

    if (idx < 0) return 0;                              // gap on the track

    Entry& e = *clips_[idx];
    // Timeline position -> position inside the source.
    const double local = e.spec.in + (t - e.at);
    return frameFor_(e, local);
}

} // namespace rift

