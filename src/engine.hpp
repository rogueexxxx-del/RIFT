// Engine facade - owns threads + subsystems, implements the C API.
//
// Thread model (the whole point of the C++ rewrite):
//   UI thread     : C API calls, marshaled in.
//   Render thread : owns RHI context, runs RenderGraph at vsync. ONLY thread
//                   that touches GPU resources.
//   Audio thread  : miniaudio callback + runtime analyzer; pushes ChannelRing.
//   Decode thread : libav HW decode; pushes decoded frames to a queue the
//                   render thread uploads (staging/PBO).
//
// No shared mutable GPU state across threads. Audio->render handoff is the
// lock-free ChannelRing. Decode->render handoff is a bounded frame queue.
#pragma once
#include <thread>
#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <vector>
#include "render_graph.hpp"
#include "parameter_graph.hpp"
#include "timeline.hpp"
#include "layer_stack.hpp"
#include "channel_ring.hpp"
#include "rift/rift_types.h"

namespace rift {

class AudioSystem;    // analyzer + playback, P3
class RhiContext;     // Qt RHI wrapper, P1
#if RIFT_WITH_FFMPEG
class MediaDecoder;   // libav, P2
#endif
// Exporter (P5) intentionally omitted until implemented - a unique_ptr to an
// undefined type breaks Engine's destructor.

class Engine {
public:
    Engine(void* native_window, std::string shaders_dir, std::string cache_dir);
    // P4 external-render mode. Qt Quick owns the QRhi and its own render
    // thread, so the engine must NOT start one or create a swapchain - two
    // threads cannot drive one device. `rhi` is a QRhi* borrowed from
    // QQuickWindow; the caller pumps frames by calling renderExternal().
    Engine(std::string shaders_dir, std::string cache_dir, void* rhi);
    ~Engine();

    // Render one frame on the CALLER's thread (Qt Quick's render thread).
    // Advances audio, picks the media frame, executes the graph. Returns the
    // scene TexId to display, 0 if nothing rendered. External mode only.
    TexId renderExternal(int w, int h);
    // True when this engine does not own a render thread.
    bool  isExternal() const { return external_; }
    RhiContext* rhiContext() { return rhi_.get(); }

    // media
    void loadMedia(const std::string& path);      // convenience: one-clip track
    bool mediaReady() const;
    // Declarative track description. Queued and applied on the render thread;
    // decoders for unchanged sources are reused, so drag/trim does not reopen.
    void   setClips(const std::vector<ClipSpec>& clips);
    double timelineDuration() const;
    // Length of the loaded audio, 0 when there is none. The piece is as long as
    // the music, so this is what a clip should be filled against.
    double audioDuration() const;
    int    activeClip() const;                    // index at the current playhead
    // Resolved layout (auto-append positions filled in, real source durations
    // applied) so the UI draws where clips actually are.
    double clipStart(int i) const;
    double clipSpan(int i) const;
    int    laneCount() const;

    // audio
    void loadAudio(const std::string& audio, const std::string& analysis);
    // Audio tracks - declarative like setClips. Queued and applied on the
    // render thread, where AudioSystem builds its mixer. `analysis` only
    // matters for the single-clip blob optimization.
    void   setAudioClips(const std::vector<AudioClipSpec>& clips,
                         const std::string& analysis = {});
    int    audioClipCount() const;
    int    audioLaneCount() const;
    double audioClipStart(int i) const;   // resolved placement, for the UI
    double audioClipSpan(int i) const;
    bool audioReady() const;
    void play();  void pause();  void seek(double s);
    double playhead() const;
    bool   playing() const;
    void setLoop(bool);
    void channels(rift_channel_frame& out) const;
    // Live input (mic / loopback) drives the channels instead of a blob.
    void  setLiveInput(bool on);
    bool  liveInput() const;
    float liveLevel() const;
    // Peak envelope of the loaded audio for the timeline (empty if none).
    // By value: AudioSystem rebuilds it on the render thread at load time, so a
    // reference handed to the UI thread could be read mid-reallocation.
    std::vector<float> waveform() const;
    // Detected beat/onset times in seconds (empty if no audio).
    std::vector<double> beats() const;
    float bpm() const;
    // Changes once per completed audio load. Lets a poller tell a NEW track
    // from the same one without copying either vector every tick.
    uint32_t audioDataGeneration() const;

    // graph + params -> delegate to graph_
    RenderGraph& graph() { return graph_; }
    // One effect in a chain: shader id, its uniforms in layout order, and how
    // its output folds back over its input.
    struct ChainNode {
        std::string        effect;
        std::vector<Param> params;
        int   blend = Blend_Normal;
        float mix   = 1.f;
    };
    // Thread-safe chain setup: the render thread starts inside the ctor and
    // reads graph_ every frame, so mutating it from another thread is a race.
    // Queued here and applied on the render thread. Nodes render in list order:
    // source -> nodes[0] -> nodes[1] -> ... -> output.
    void setChain(const std::vector<ChainNode>& nodes);
    // Master colour grade, applied after everything else. Params in
    // color_grade.layout.json order. Queued like the rest.
    void setGrade(const std::vector<Param>& params);

    // present
    void resize(int w, int h);
    void setPreviewScale(rift_preview_scale);
    void requestRedraw();

    // export
    void exportStart(const rift_export_spec&, rift_export_cb, void* user);
    void exportCancel();

    void stats(rift_stats& out) const;
    const char* lastError() const { return err_.c_str(); }

private:
    // Render every clip covering the playhead through ITS OWN effect chain and
    // composite them bottom lane upward. Returns the final texture, or 0 when
    // nothing is on screen. Falls back to the shared graph for a single
    // un-chained clip so the simple case costs no extra passes.
    TexId renderLayers_(const rift_channel_frame& cf, double t, int w, int h);
    // Source texture for an empty track. Preview and export MUST agree here:
    // the export used to hand the chain texture 0, which drawPass binds to the
    // 1x1 black dummy, so every shader that samples u_tex (tunnel, lens,
    // kaleido, flow_warp, ...) exported pure black while the viewport showed it
    // working. Render thread only - it uploads.
    TexId emptySource_();
    TexId placeholder_ = 0;

    void renderLoop_();          // render thread body
    void runExport_();           // offscreen render+encode, on the render thread
    // Shared render/readback/encode loop. Still templated on the encoder so a
    // second backend needs no vtable, but Exporter is the only one today.
    template <class Ex> bool runExportLoop_(Ex& ex, const rift_export_spec& s,
                                            int total);

    std::unique_ptr<RhiContext>   rhi_;
    std::unique_ptr<AudioSystem>  audio_;
#if RIFT_WITH_FFMPEG
    // Every source goes through the timeline now, including a single file
    // (loadMedia builds a one-clip track), so there is one decode path.
    std::unique_ptr<Timeline>     timeline_;
#endif
    // Exporter (P5) added when implemented.

    RenderGraph   graph_;
    LayerStack    layers_;        // per-clip chains + compositing
    ChannelRing   channels_;      // audio -> render
    TexId         last_scene_ = 0; // most recent rendered target (for readback)
    void*         win_ = nullptr;  // QWindow* for on-screen preview (0 = offscreen)

    std::thread        render_thread_;
    std::atomic<bool>  running_{false};
    bool               external_ = false;   // Qt Quick drives rendering
    bool               graph_built_ = false;

    // External mode: media/audio loading touches GPU resources (MediaDecoder
    // is built on the QRhi), but the calls arrive on the UI thread while the
    // render thread owns the device. Queue them and apply at the top of
    // renderExternal(), on the render thread.
    // Transport clock owned by the engine (AudioSystem playback is stubbed).
    std::atomic<bool> playing_{false};
    double            ph_offset_ = 0.0;      // playhead at last play/pause/seek
    std::chrono::steady_clock::time_point ph_start_;
    double computePlayhead_() const;

    std::mutex  pending_mu_;
    std::string pending_media_;
    bool        want_media_ = false;
    std::vector<ChainNode> pending_chain_;
    bool                   want_chain_ = false;
    bool                   pending_live_ = false, want_live_ = false;
    std::vector<Param>     pending_grade_;
    bool                   want_grade_ = false;
    std::vector<Param>     grade_;      // render thread only
    std::vector<ClipSpec>  pending_clips_;
    bool                   want_clips_ = false;
    // Audio clips, queued the same way: the mixer they build is read by the
    // audio callback, and decoding touches files, so it belongs on the
    // render thread.
    std::vector<AudioClipSpec> pending_audio_clips_;
    std::string                pending_audio_analysis_;
    bool                       want_audio_clips_ = false;
    std::vector<AudioClipSpec> audio_clips_;   // render thread: last applied
    void applyPendingLoads_();          // render thread only
    // Push the current audio window to the GPU so scope effects have something
    // to draw. Called wherever audio_->tick() is, including during export.
    void feedScope_(double playhead, double dt = 0.016);

public:
    // Live input sources, including the output of anything currently playing.
    std::vector<std::pair<std::string, bool>> liveDevices();
    void setLiveDevice(int index);
    void setSpectrumSlope(float dbPerOct) { slope_db_per_oct_.store(dbPerOct, std::memory_order_relaxed); }

private:
    std::atomic<float> slope_db_per_oct_{3.0f};
    std::atomic<int>   preview_scale_{1};
    std::atomic<bool>  exporting_{false};

    // Export request (owned copy of the spec + its strings; consumed on the
    // render thread by runExport_).
    rift_export_spec exp_spec_{};
    std::string      exp_out_, exp_audio_, exp_logo_, exp_font_;
    std::string      cache_dir_;         // temp bounces (the mix WAV) land here
    std::string      export_mix_path_;   // bounced audio mix handed to Exporter
    rift_export_cb   exp_cb_ = nullptr;
    void*            exp_user_ = nullptr;

    std::string err_;
    rift_stats  stats_{};
    // Rolling window of recent frame times, for the percentiles in rift_stats.
    // A ring rather than a growing list: this is touched every frame forever,
    // and 2 s at 120 fps is plenty to catch a hitch while staying cache-warm.
    static constexpr int kFrameWindow = 256;
    double      frame_hist_[kFrameWindow] = {0};
    int         frame_hist_n_ = 0;      // how many slots are populated
    int         frame_hist_i_ = 0;      // next write position
    void        recordFrameTime_(double ms);
};

} // namespace rift
