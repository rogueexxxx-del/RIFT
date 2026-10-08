// Engine impl â€” thread orchestration + facade.
// P1 scope: render thread owning the RHI context, driving RenderGraph at
// vsync, reading the ChannelRing. Audio/decode subsystems land P2/P3 (stubs
// wired here). This file compiles under RIFT_WITH_RHI (needs Qt RHI).
#include <algorithm>   // std::sort/copy for the frame-time percentiles
#include <cmath>       // std::fmod for looping short footage
#include "engine.hpp"
#include "rhi_context.hpp"
#include "audio_system.hpp"
#include "exporter.hpp"
#include <chrono>
#include <vector>
#if RIFT_WITH_FFMPEG
  #include "media_decoder.hpp"
#endif

namespace rift {

// qsbDir: directory holding <id>.frag.qsb + engine_fullscreen.vert.qsb +
// <id>.layout.json (produced by the qsb build step). Passed as `shaders_dir`.
Engine::Engine(void* win, std::string shaders_dir, std::string cache_dir)
    : win_(win), cache_dir_(std::move(cache_dir)) {
    // No shader cache: RhiContext loads .qsb itself. The cache dir IS used,
    // for the export's temporary mix bounce.
    rhi_ = std::make_unique<RhiContext>(shaders_dir);   // owns QRhi (D3D11)
    running_ = true;
    render_thread_ = std::thread([this]{ renderLoop_(); });
}

// External-render mode (P4). No render thread and no swapchain: Qt Quick owns
// both the device and the thread that drives it. Frames come from
// renderExternal(), called on Quick's render thread.
Engine::Engine(std::string shaders_dir, std::string cache_dir, void* rhi)
    : win_(nullptr), external_(true), cache_dir_(std::move(cache_dir)) {
    rhi_ = std::make_unique<RhiContext>(shaders_dir, rhi);   // borrowed QRhi
}

Engine::~Engine() {
    running_ = false;
    if (render_thread_.joinable()) render_thread_.join();
}

// Caller's thread == Qt Quick's render thread. Mirrors the body of
// renderLoop_() minus threading, pacing, and present: Quick composites the
// returned texture itself.
// Gradient + coarse checker, so "no footage loaded" reads as a deliberate
// stand-in and a chain over it is visibly doing something.
TexId Engine::emptySource_() {
    if (placeholder_ || !rhi_) return placeholder_;
    constexpr int W = 640, H = 360;
    std::vector<uint8_t> img(size_t(W) * H * 4);
    for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) {
        const size_t i = (size_t(y) * W + x) * 4;
        img[i]     = uint8_t(x * 255 / W);
        img[i + 1] = uint8_t(y * 255 / H);
        img[i + 2] = uint8_t(((x / 40 + y / 40) & 1) ? 200 : 40);
        img[i + 3] = 255;
    }
    placeholder_ = rhi_->uploadImage(img.data(), W, H);
    return placeholder_;
}

TexId Engine::renderExternal(int w, int h) {
    if (!external_ || !rhi_ || w <= 0 || h <= 0) return 0;
    applyPendingLoads_();          // UI-queued media/audio, applied on this thread
    if (!graph_built_) { graph_.build(*rhi_); graph_built_ = true; }

    if (exporting_.load(std::memory_order_acquire)) {
        runExport_();                      // blocking, but we own the device here
        exporting_.store(false, std::memory_order_release);
    }

    const bool is_playing = playing_.load(std::memory_order_acquire);
    const double playhead = computePlayhead_();     // engine-owned clock
    using clock = std::chrono::steady_clock;
    static thread_local auto last_ext_scope = clock::now();
    const auto now_ext = clock::now();
    const double dt_ext = std::chrono::duration<double>(now_ext - last_ext_scope).count();
    last_ext_scope = now_ext;
    const double safe_dt = (dt_ext > 0.001 && dt_ext < 0.2) ? dt_ext : 0.016;
    if (audio_ && is_playing) audio_->tick(playhead);
    feedScope_(playhead, is_playing ? safe_dt : 0.0);

    rift_channel_frame cf{};
    channels_.latest(cf);
    cf.playhead = playhead;          // channels_ carries 0 when audio is absent

    int ps = preview_scale_.load();
    if (ps == 2) { w /= 2; h /= 2; }
    else if (ps == 3) { w /= 4; h /= 4; }

    // Layered path: every clip covering the playhead, each through its own
    // stack, composited bottom lane up.
    TexId scene = 0;
#if RIFT_WITH_FFMPEG
    scene = renderLayers_(cf, cf.playhead, w, h);
#endif
    // Nothing on the track (or no timeline at all): fall back to the shared
    // graph over the placeholder, so the viewport is never blank.
    if (!scene) scene = graph_.execute(*rhi_, cf, emptySource_(), cf.playhead, w, h);

    // Master colour grade, last. beginFrame sizes its target; applyGrade
    // returns `scene` untouched when the grade is neutral.
    layers_.beginFrame(*rhi_, w, h);
    scene = layers_.applyGrade(*rhi_, cf, scene, cf.playhead, w, h, grade_);

    // After the LAST pass: what a feedback shader samples next frame is the
    // finished picture, grade included, not a mid-chain intermediate.
    if (is_playing) {
        rhi_->capturePrev(scene, w, h);
    }

    last_scene_ = scene;
    rhi_->endOfFrame();          // retire clock: frees textures released earlier

    // renderLoop_ computes these from its own pacing; in external mode Quick
    // drives the cadence, so measure it here or the UI readout stays at 0.
    using clock = std::chrono::steady_clock;
    static thread_local auto last_ext = clock::now();
    const auto now = clock::now();
    const double dt = std::chrono::duration<double>(now - last_ext).count();
    last_ext = now;
    if (dt > 0.0 && dt < 1.0) {         // ignore the first frame and long stalls
        stats_.frame_ms = dt * 1000.0;
        stats_.fps = 1.0 / dt;
        recordFrameTime_(stats_.frame_ms);
    }
    stats_.frames_rendered++;
    return last_scene_;
}

#if RIFT_WITH_FFMPEG
TexId Engine::renderLayers_(const rift_channel_frame& cf, double t, int w, int h) {
    if (!timeline_) return 0;
    // Text clips rasterize to this size, so it has to be current before any
    // frame is fetched.
    timeline_->setRenderSize(w, h);

    // Loop the footage when it is shorter than the piece.
    //
    // The playhead follows the AUDIO, so a 4 s clip under a 2 minute track ran
    // out after 4 s and every later frame found no clip at all - exports came
    // out as a few seconds of picture followed by two minutes of black. Wrap
    // the lookup instead so the footage repeats.
    //
    // Only the clip lookup wraps. `t` is still the real playhead everywhere
    // else, so keyframes and audio reactivity keep running forward through the
    // whole track rather than restarting with the video.
    double look = t;
    const double trackDur = timeline_->duration();
    if (trackDur > 0.0 && t >= trackDur) look = std::fmod(t, trackDur);

    auto layers = timeline_->activeAt(look);
    if (layers.empty()) return 0;

    auto isIdentityComposite = [](const ClipSpec* s) {
        if (!s) return true;
        return s->blend == Blend_Normal &&
               std::abs(s->opacity - 1.0) < 1e-3 &&
               std::abs(s->posX) < 1e-4 &&
               std::abs(s->posY) < 1e-4 &&
               std::abs(s->scale - 1.0) < 1e-4 &&
               std::abs(s->cropX) < 1e-4 &&
               std::abs(s->cropY) < 1e-4 &&
               std::abs(s->cropW - 1.0) < 1e-4 &&
               std::abs(s->cropH - 1.0) < 1e-4;
    };

    TexId acc = 0;
    if (layers.size() == 1 && isIdentityComposite(timeline_->spec(layers[0].index))) {
        ClipSpec* s = timeline_->spec(layers[0].index);
        acc = (s && !s->chain.empty())
            ? layers_.runChain(*rhi_, cf, layers[0].tex, t, w, h, s->chain)
            : layers[0].tex;
    } else {
        layers_.beginFrame(*rhi_, w, h);
        for (size_t li = 0; li < layers.size(); ++li) {
            const auto& L = layers[li];
            ClipSpec* s = timeline_->spec(L.index);
            if (!s) continue;

            TexId img = (!s->chain.empty())
                      ? layers_.runChain(*rhi_, cf, L.tex, t, w, h, s->chain)
                      : L.tex;

            if (li == 0 && isIdentityComposite(s)) {
                acc = img;
            } else {
                // Layer 0 over nothing must be Normal blend to avoid multiplying/subtracting with black texture 0
                const int blendMode = (li == 0) ? int(Blend_Normal) : s->blend;
                const float cp[LayerStack::kCompositeParams] = {
                    float(blendMode), float(s->opacity),
                    float(s->posX),   float(s->posY), float(s->scale),
                    float(s->cropX),  float(s->cropY), float(s->cropW), float(s->cropH)
                };
                acc = layers_.composite(*rhi_, cf, img, acc, t, w, h, cp, 0);
            }
        }
    }

    if (!acc) return 0;
    return graph_.execute(*rhi_, cf, acc, t, w, h);
}
#endif

void Engine::renderLoop_() {
    using clock = std::chrono::steady_clock;
    auto last = clock::now();
    graph_.build(*rhi_);

    // Swapchain must be created on this (the render) thread â€” it owns QRhi.
    const bool swap = win_ && rhi_->initSwapchain(win_);

    while (running_.load(std::memory_order_relaxed)) {
        applyPendingLoads_();       // media/audio/chain queued from other threads
        if (exporting_.load(std::memory_order_acquire)) {
            runExport_();                       // blocking; owns the render thread
            exporting_.store(false, std::memory_order_release);
            last = clock::now();
            continue;
        }

        auto now = clock::now();
        double dt = std::chrono::duration<double>(now - last).count();
        last = now;

        // Advance audio: playhead -> analysis frame -> smoother -> ChannelRing.
        // Frame-rate-locked to render, like the prototype's per-paintGL update.
        double playhead = computePlayhead_();      // engine-owned clock
        if (audio_) audio_->tick(playhead);
        feedScope_(playhead, dt);

        rift_channel_frame cf{};
        channels_.latest(cf);            // lock-free read of latest audio frame
        cf.playhead = playhead;

        int w = 1920, h = 1080;
        int ps = preview_scale_.load();
        if (ps == 2) { w /= 2; h /= 2; }
        else if (ps == 3) { w /= 4; h /= 4; }

        // Layered: every clip covering the playhead through its own stack,
        // composited bottom lane up. Falls back to the shared graph over a
        // black source when the track has nothing here.
        TexId scene = 0;
#if RIFT_WITH_FFMPEG
        scene = renderLayers_(cf, cf.playhead, w, h);
#endif
        if (!scene) scene = graph_.execute(*rhi_, cf, emptySource_(), cf.playhead, w, h);

        layers_.beginFrame(*rhi_, w, h);
        scene = layers_.applyGrade(*rhi_, cf, scene, cf.playhead, w, h, grade_);
        rhi_->capturePrev(scene, w, h);

        last_scene_ = scene;
        rhi_->endOfFrame();      // retire clock: frees textures released earlier
        if (swap) rhi_->present(last_scene_);    // blit to window (vsync-paced)

        stats_.frame_ms = dt * 1000.0;
        stats_.fps = dt > 0 ? 1.0 / dt : 0.0;
        stats_.gpu_ms = rhi_ ? rhi_->gpuLastMs() : 0.0;
        if (dt > 0.0 && dt < 1.0) recordFrameTime_(stats_.frame_ms);
        stats_.frames_rendered++;

        // present() blocks on vsync; without a swapchain, pace manually so the
        // loop doesn't peg a core.
        if (!swap) std::this_thread::sleep_for(std::chrono::milliseconds(8));
    }
}

// --- facade delegates ---
// Always queued: decoders are built on the QRhi, which belongs to whichever
// thread drives rendering (Quick's in external mode, renderLoop_'s otherwise).
// Both drain via applyPendingLoads_().
//
// A single file is just a one-clip track, so there is one code path downstream.
void Engine::loadMedia(const std::string& path) {
    // Field-by-field, not an aggregate initializer: ClipSpec gained `kind` and
    // `text` at the front, and positional init would silently put the path in
    // the wrong member.
    ClipSpec c;
    c.path  = path;
    c.start = 0.0;
    setClips({ c });
}

void Engine::setClips(const std::vector<ClipSpec>& clips) {
    std::lock_guard<std::mutex> lk(pending_mu_);
    pending_clips_ = clips;
    want_clips_ = true;
}

double Engine::timelineDuration() const {
#if RIFT_WITH_FFMPEG
    return timeline_ ? timeline_->duration() : 0.0;
#else
    return 0.0;
#endif
}

int Engine::activeClip() const {
#if RIFT_WITH_FFMPEG
    return timeline_ ? timeline_->activeIndex(computePlayhead_()) : -1;
#else
    return -1;
#endif
}

double Engine::clipStart(int i) const {
#if RIFT_WITH_FFMPEG
    return timeline_ ? timeline_->clipStart(i) : 0.0;
#else
    (void)i; return 0.0;
#endif
}
double Engine::clipSpan(int i) const {
#if RIFT_WITH_FFMPEG
    return timeline_ ? timeline_->clipSpan(i) : 0.0;
#else
    (void)i; return 0.0;
#endif
}
int Engine::laneCount() const {
#if RIFT_WITH_FFMPEG
    return timeline_ ? timeline_->laneCount() : 1;
#else
    return 1;
#endif
}

void Engine::setChain(const std::vector<ChainNode>& nodes) {
    std::lock_guard<std::mutex> lk(pending_mu_);
    pending_chain_ = nodes;
    want_chain_ = true;
}

void Engine::setGrade(const std::vector<Param>& params) {
    std::lock_guard<std::mutex> lk(pending_mu_);
    pending_grade_ = params;
    want_grade_ = true;
}

// Render thread. Drains whatever another thread queued.
// Keep the rolling window and republish the percentiles.
//
// Sorting a 256-entry copy every frame is ~microseconds and runs once per
// frame, not per pixel - cheap enough that it is not worth the complexity of
// an incremental structure, and this has to stay correct rather than clever.
void Engine::recordFrameTime_(double ms) {
    frame_hist_[frame_hist_i_] = ms;
    frame_hist_i_ = (frame_hist_i_ + 1) % kFrameWindow;
    if (frame_hist_n_ < kFrameWindow) ++frame_hist_n_;

    double sorted[kFrameWindow];
    std::copy(frame_hist_, frame_hist_ + frame_hist_n_, sorted);
    std::sort(sorted, sorted + frame_hist_n_);

    auto pct = [&](double q) {
        const int i = std::min(frame_hist_n_ - 1,
                               int(q * (frame_hist_n_ - 1) + 0.5));
        return sorted[i];
    };
    stats_.frame_ms_p50 = pct(0.50);
    stats_.frame_ms_p95 = pct(0.95);
    stats_.frame_ms_p99 = pct(0.99);
    stats_.frame_ms_max = sorted[frame_hist_n_ - 1];
}

std::vector<std::pair<std::string, bool>> Engine::liveDevices() {
    std::vector<std::pair<std::string, bool>> out;
    if (!audio_) audio_ = std::make_unique<AudioSystem>(&channels_);
    for (const auto& d : audio_->liveDevices()) out.emplace_back(d.name, d.loopback);
    return out;
}

void Engine::setLiveDevice(int index) {
    if (!audio_) audio_ = std::make_unique<AudioSystem>(&channels_);
    audio_->setLiveDevice(index);
}

void Engine::feedScope_(double playhead, double dt) {
    if (!rhi_) return;
    constexpr int kW = 1024;
    float wave[kW] = {0}, spec[kW] = {0}, vecX[kW] = {0}, vecY[kW] = {0};
    const float* raw_spec = nullptr;
    if (audio_) {
        audio_->getOscilloscope(playhead, wave, kW);
        audio_->getSpectrum(playhead, spec, kW, float(dt), slope_db_per_oct_.load(std::memory_order_relaxed));
        audio_->getVectorscope(playhead, vecX, vecY, kW);
        if (!audio_->rawSpectrum().empty()) raw_spec = audio_->rawSpectrum().data();
    }
    rhi_->uploadAudio(wave, kW, spec, kW, 0.0f, raw_spec, vecX, vecY);
}

void Engine::applyPendingLoads_() {
    std::string audio_analysis;
    std::vector<ChainNode> chain;
    std::vector<ClipSpec>  clips;
    std::vector<AudioClipSpec> aclips;
    bool do_audioclips = false, do_chain = false, do_clips = false;
    bool do_live = false, live_on = false;
    {
        std::lock_guard<std::mutex> lk(pending_mu_);
        if (want_audio_clips_) {
            aclips = pending_audio_clips_;
            audio_analysis = pending_audio_analysis_;
            do_audioclips = true;
            want_audio_clips_ = false;
        }
        if (want_chain_) { chain = pending_chain_; do_chain = true; want_chain_ = false; }
        if (want_live_)  { live_on = pending_live_; do_live = true; want_live_ = false; }
        if (want_clips_) { clips = pending_clips_; do_clips = true; want_clips_ = false; }
        if (want_grade_) { grade_ = pending_grade_; want_grade_ = false; }
    }

#if RIFT_WITH_FFMPEG
    if (do_clips) {
        if (!timeline_) timeline_ = std::make_unique<Timeline>(rhi_.get());
        timeline_->apply(clips);
    }
#else
    (void)do_clips;
#endif

    if (do_live) {
        // Live input needs neither media nor a blob, so create AudioSystem here.
        if (live_on && !audio_) audio_ = std::make_unique<AudioSystem>(&channels_);
        if (audio_) { if (live_on) audio_->startLive(); else audio_->stopLive(); }
    }

    if (do_chain && !chain.empty()) {
        graph_.clear();
        // source -> n0 -> n1 -> ... : each node reads the previous output, so
        // list order is render order (same wiring as the live viewport).
        uint32_t prev = graph_.addSource();
        for (const auto& n : chain) {
            const uint32_t fx = graph_.addEffect(n.effect);
            graph_.connect(prev, fx);
            if (!n.params.empty()) {
                graph_.setParams(fx, n.params);
                if (n.effect == "oscilloscope" && n.params.size() > 3)
                    setSpectrumSlope(n.params[3].value);
            }
            graph_.setBlend(fx, n.blend, n.mix);
            prev = fx;
        }
        graph_.build(*rhi_);
        graph_built_ = true;
    }
    if (do_audioclips) {
        if (!audio_) audio_ = std::make_unique<AudioSystem>(&channels_);
        audio_->setAudioClips(aclips, audio_analysis);
        audio_clips_ = aclips;         // remembered for the export bounce
        // The UI can hit play or scrub before this queued update lands (the
        // shell does exactly that on startup), so adopt the current transport
        // state instead of silently coming up stopped at the old cursor.
        const double ph = computePlayhead_();
        if (ph > 0.0) audio_->seek(ph);
        if (playing_.load(std::memory_order_acquire)) audio_->play();
    }
}
bool Engine::mediaReady() const {
#if RIFT_WITH_FFMPEG
    // "Ready" now means the track has something to show, not that one file is
    // open â€” clips open lazily as the playhead reaches them.
    return timeline_ && !timeline_->empty();
#else
    return false;
#endif
}
// One file is one A1 audio clip now - both the legacy entry point and the
// audio-track path go through the same queue.
void Engine::loadAudio(const std::string& audio, const std::string& analysis) {
    std::vector<AudioClipSpec> clips;
    if (!audio.empty()) {
        AudioClipSpec a;
        a.path  = audio;
        a.start = 0.0;
        a.lane  = 0;
        clips.push_back(a);
    }
    setAudioClips(clips, analysis);
}

void Engine::setAudioClips(const std::vector<AudioClipSpec>& clips,
                           const std::string& analysis) {
    std::lock_guard<std::mutex> lk(pending_mu_);
    pending_audio_clips_     = clips;
    pending_audio_analysis_  = analysis;
    want_audio_clips_        = true;
}

int    Engine::audioClipCount() const {
    return audio_ ? audio_->audioClipCount() : 0;
}
int    Engine::audioLaneCount() const {
    return audio_ ? audio_->audioLaneCount() : 1;
}
double Engine::audioClipStart(int i) const {
    return audio_ ? audio_->audioClipStart(i) : 0.0;
}
double Engine::audioClipSpan(int i) const {
    return audio_ ? audio_->audioClipSpan(i) : 0.0;
}
bool Engine::audioReady() const { return audio_ && audio_->ready(); }
double Engine::audioDuration() const { return audio_ ? audio_->duration() : 0.0; }
// Transport clock. AudioSystem's playback is still a stub (miniaudio is
// commented out behind the <<MA>> markers), so its playhead never advances on
// its own â€” and the render loop was feeding audio_->playhead() straight back
// into audio_->tick(), which pinned it at zero. The engine owns the clock
// instead: it works media-only, and AudioSystem stays the consumer.
double Engine::computePlayhead_() const {
    if (!playing_.load(std::memory_order_acquire)) return ph_offset_;

    // With a real audio device the DEVICE owns the clock — channel lookup is
    // driven off this, so it has to follow what is actually being heard. The
    // steady_clock path is only the fallback for media-only playback.
    if (audio_ && audio_->hasPlayback() && !audio_->empty()) return audio_->playhead();

    const auto now = std::chrono::steady_clock::now();
    return ph_offset_ + std::chrono::duration<double>(now - ph_start_).count();
}

void Engine::play() {
    ph_offset_ = computePlayhead_();
    ph_start_  = std::chrono::steady_clock::now();
    playing_.store(true, std::memory_order_release);
    if (audio_) audio_->play();
}
void Engine::pause() {
    ph_offset_ = computePlayhead_();          // freeze where we are
    playing_.store(false, std::memory_order_release);
    if (audio_) audio_->pause();
}
void Engine::seek(double s) {
    ph_offset_ = s;
    ph_start_  = std::chrono::steady_clock::now();
    if (audio_) audio_->seek(s);
#if RIFT_WITH_FFMPEG
    if (timeline_) timeline_->seek(s);
#endif
}
double Engine::playhead() const { return computePlayhead_(); }
bool   Engine::playing() const { return playing_.load(std::memory_order_acquire); }
void Engine::setLoop(bool on) {
    // Track-level looping is a timeline concern; individual clips always play
    // their trimmed span once (Timeline sets loop=false per decoder).
    if (audio_) audio_->setLoop(on);
#if RIFT_WITH_FFMPEG
    if (timeline_) timeline_->setLoopTrack(on);
#endif
}
void Engine::channels(rift_channel_frame& out) const { channels_.latest(out); }

// Live input needs no media and no .analysis: the capture device feeds the FFT
// directly. AudioSystem is created on demand so mic-only use works with nothing
// loaded at all.
void Engine::setLiveInput(bool on) {
    // Queued: this creates/updates AudioSystem, which the render thread reads
    // every frame. Applied in applyPendingLoads_ like the media/audio loads.
    std::lock_guard<std::mutex> lk(pending_mu_);
    pending_live_ = on;
    want_live_ = true;
}
bool  Engine::liveInput() const { return audio_ && audio_->liveMode(); }
float Engine::liveLevel() const { return audio_ ? audio_->liveLevel() : 0.f; }

std::vector<float> Engine::waveform() const {
    return audio_ ? audio_->waveform() : std::vector<float>{};
}
std::vector<double> Engine::beats() const {
    return audio_ ? audio_->beats() : std::vector<double>{};
}
uint32_t Engine::audioDataGeneration() const {
    return audio_ ? audio_->dataGeneration() : 0u;
}
float Engine::bpm() const { return audio_ ? audio_->bpm() : 0.f; }
void Engine::resize(int, int) {}
void Engine::setPreviewScale(rift_preview_scale s) { preview_scale_ = int(s) + 1; }
void Engine::requestRedraw() {}
void Engine::exportStart(const rift_export_spec& spec, rift_export_cb cb, void* u) {
    // Copy the spec + its strings; the render thread consumes them.
    exp_spec_  = spec;
    exp_out_   = spec.out_path   ? spec.out_path   : "";
    exp_audio_ = spec.audio_path ? spec.audio_path : "";
    exp_logo_  = spec.logo_path  ? spec.logo_path  : "";
    exp_font_  = spec.font_dir   ? spec.font_dir   : "";
    exp_cb_    = cb;
    exp_user_  = u;
    exporting_.store(true, std::memory_order_release);
}
void Engine::exportCancel() { exporting_.store(false, std::memory_order_release); }

// Offscreen render + encode. Runs on the render thread (owns the QRhi context),
// so no other frames render meanwhile. Audio channels are advanced in playhead
// order so the Smoother envelopes match a realtime playthrough at export fps.
template <class Ex>
bool Engine::runExportLoop_(Ex& ex, const rift_export_spec& s, int total) {
    const int fps = s.fps > 0 ? s.fps : 30;
    const int W = s.width & ~1, H = s.height & ~1;

    // Mark in / out. `first` is the frame the range starts at; `total` has
    // already been narrowed to the range by the caller.
    const bool ranged = s.mark_out > s.mark_in;
    const int first = ranged ? int(s.mark_in * fps) : 0;

    if (audio_) { audio_->pause(); audio_->seek(ranged ? s.mark_in : 0.0); }

    const bool dbg = std::getenv("RIFT_DBG") != nullptr;
    std::vector<uint8_t> rgba;
    for (int i = 0; i < total && exporting_.load(std::memory_order_acquire); ++i) {
        // Real time, not time-since-in: keyframes, audio reactivity and clip
        // positions all read this, and shifting it would silently re-time the
        // whole piece whenever a range was exported.
        double ph = double(first + i) / fps;
        if (audio_) audio_->tick(ph);
        feedScope_(ph, 1.0 / double(fps));
        rift_channel_frame cf{}; channels_.latest(cf);
        cf.playhead = ph;                // keyframes read the playhead from here

        // Same path as the preview: per-clip stacks, lane compositing and the
        // master grade all apply. Exporting through graph_.execute() alone
        // silently dropped every one of them.
        // Size the pool BEFORE the passes run. The live path gets away with
        // doing this at the end of the frame because the next frame reuses the
        // pool; an export has to be right on frame 0, which is the one being
        // written.
        // ONE GPU frame for the entire exported frame. Every pass used to
        // open its own, and each is a submit plus a wait for the GPU to finish.
        rhi_->beginFrame();
        layers_.beginFrame(*rhi_, W, H);
        TexId scene = 0;
#if RIFT_WITH_FFMPEG
        scene = renderLayers_(cf, ph, W, H);
#endif
        const bool fellBack = (scene == 0);
        if (!scene) scene = graph_.execute(*rhi_, cf, emptySource_(), ph, W, H);
        scene = layers_.applyGrade(*rhi_, cf, scene, ph, W, H, grade_);
        // Inside the open frame, so the copy costs no extra submit. An export
        // has to build the same history a live playthrough does or a feedback
        // effect renders with no trail.
        rhi_->capturePrev(scene, W, H);
        // Close it before the readback: reading a texture back needs the frame
        // that wrote it to have completed.
        rhi_->endFrame();

        if (dbg && i < 5)
            std::fprintf(stderr, "[export] frame %d ph=%.3f scene=%u%s\n",
                         i, ph, scene, fellBack ? " (no media)" : ""),
            std::fflush(stderr);

        if (rhi_->readback(scene, W, H, rgba) && !ex.writeFrame(rgba.data())) {
            err_ = ex.error();       // a dead encoder will not recover
            return false;
        }

        if (exp_cb_ && (i % 3 == 0)) exp_cb_(int(100.0 * i / total), 0, exp_user_);
    }

    if (!ex.finish()) { err_ = ex.error(); return false; }
    return true;
}

void Engine::runExport_() {
    applyPendingLoads_();
    rift_export_spec s = exp_spec_;
    s.out_path   = exp_out_.c_str();
    // s.audio_path is set later, after the mix bounce: it must name the
    // bounced mix whenever audio clips exist, not the one legacy file.
    s.logo_path  = exp_logo_.empty()  ? nullptr : exp_logo_.c_str();
    s.font_dir   = exp_font_.empty()  ? nullptr : exp_font_.c_str();

    const int fps = s.fps > 0 ? s.fps : 30;

#if RIFT_WITH_FFMPEG
    // Open every source and switch its decoder to blocking BEFORE measuring:
    // a clip that has not opened yet reports a nominal span, which is how a
    // real 12 s track used to export as 5 s of black.
    if (timeline_) timeline_->prepareForExport();
#endif

    // Longest of the two, not "audio else footage": a piece runs until both
    // the music and the picture have finished. Footage shorter than the track
    // loops (see renderLayers_), so the audio is usually what decides.
    double dur = 0.0;
    if (audio_) dur = audio_->duration();
#if RIFT_WITH_FFMPEG
    if (timeline_) dur = std::max(dur, timeline_->duration());
#endif
    int total = int(dur * fps);
    // A marked range overrides the full duration.
    if (s.mark_out > s.mark_in) {
        const double lo = std::max(0.0, s.mark_in);
        const double hi = dur > 0.0 ? std::min(s.mark_out, dur) : s.mark_out;
        total = int((hi - lo) * fps);
    }
    if (total <= 0) total = fps * 5;         // fallback: 5s

    if (std::getenv("RIFT_DBG")) {
#if RIFT_WITH_FFMPEG
        std::fprintf(stderr, "[export] timeline=%p clips=%zu dur=%.3f total=%d\n",
                     (void*)timeline_.get(),
                     timeline_ ? timeline_->count() : 0u, dur, total);
#else
        std::fprintf(stderr, "[export] no ffmpeg, dur=%.3f total=%d\n", dur, total);
#endif
        std::fflush(stderr);
    }
    // Let the PROC backend report a real percentage instead of -1.
    if (s.total_frames <= 0) s.total_frames = total;

    // ── audio: bounce the mix over exactly the exported range ──
    // The exporter transcodes a file, so render the mix to a temp WAV first;
    // playback and export then hear the same thing, because the mixer is a
    // pure function of the clip set. A job with no audio clips falls back to
    // whatever single file it was queued with, so legacy queue specs work.
    std::string audio_path = exp_audio_;
    if (!audio_clips_.empty() && audio_) {
        const bool   ranged = s.mark_out > s.mark_in;
        const double a0     = ranged ? std::max(0.0, s.mark_in) : 0.0;
        export_mix_path_ = cache_dir_;
        if (!export_mix_path_.empty() && export_mix_path_.back() != '/'
                                             && export_mix_path_.back() != '\\')
            export_mix_path_ += '/';
        export_mix_path_ += "rift-mix-bounce.wav";
        if (audio_->renderMixToWav(export_mix_path_, a0, double(total) / fps))
            audio_path = export_mix_path_;
        else
            export_mix_path_.clear();
    }
    s.audio_path = audio_path.empty() ? nullptr : audio_path.c_str();

    Exporter ex;
    if (!ex.open(s)) { err_ = ex.error(); if (exp_cb_) exp_cb_(-1, 1, exp_user_); return; }
    const bool ok = runExportLoop_(ex, s, total);

    if (exp_cb_) exp_cb_(ok ? 100 : -1, 1, exp_user_);
}
void Engine::stats(rift_stats& out) const { out = stats_; }

} // namespace rift

